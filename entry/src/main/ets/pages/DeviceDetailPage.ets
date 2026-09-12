/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 鸿米家（miha）项目开发者
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import {
  ActionArgumentDescriptor,
  ActionControlDescriptor,
  buildServiceActions,
  buildServiceControls,
  CapabilityControlType,
  dedupeControlLabels,
  markPrimaryPower,
  PropertyControlDescriptor,
  resolveServiceDisplayNames,
  translateMiotText
} from '../components/CapabilityRenderer';
import { ActionArgumentControl } from '../components/ActionArgumentControl';
import { ActionControl } from '../components/ActionControl';
import { PropertyControl } from '../components/PropertyControl';
import { MijiaConsumableDetail, MijiaConsumableItem } from '../cloud/MijiaApiClient';
import { DeviceController } from '../controllers/DeviceController';
import { DevicePropertyParam, DevicePropertyResult } from '../controllers/DeviceTransport';
import { MIoTSpecInstance } from '../models/MIotSpecModels';
import { XiaomiDevice } from '../models/XiaomiHomeModels';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { Logger } from '../utils/Logger';
import { HwColor, HwGlassCardColor, HwRadius, HwSpace, reloadAppTheme, withAlpha } from '../utils/DesignTokens';
import { celsiusToFahrenheit, isCelsiusUnit } from '../utils/TemperatureDisplay';
import { AccentColorSentinel, MaterialCard } from '../components/MaterialCard';
import { AppBackground } from '../components/AppBackground';
import { IconCircleButton } from '../components/IconCircleButton';
import { AboutDeviceRouteParam, DeviceDetailRouteParam } from '../models/NavRouteParams';

/** 统计曲线柱体的最大高度（vp）。高度按最大值归一化，所以只需要这一个常量。 */
const TREND_CHART_HEIGHT: number = 84;

interface PropertyValueState {
  key: string;
  value: Object | undefined;
}

interface ActionArgumentValueState {
  key: string;
  value: Object | undefined;
}

/** 统计曲线上的一个数据点 */
interface TrendPoint {
  label: string;
  value: number;
}

/** 可参与统计的候选属性（温/湿/空气质量） */
interface TrendCandidate {
  key: string;
  label: string;
}

/**
 * 服务分区：同一 MIoT 服务下的属性控件（读/写）与动作（aiid）共用一个小标题，
 * 对齐米家「按功能分区」的组织方式，而不是把全设备的属性平铺成一长串。
 */
interface ServiceSection {
  key: string;
  title: string;
  controls: PropertyControlDescriptor[];
  actions: ActionControlDescriptor[];
}

@Builder
export function DeviceDetailBuilder(name: string, param: Object) {
  DeviceDetailPage({ did: (param as DeviceDetailRouteParam).did })
}

@Component
export struct DeviceDetailPage {
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';

  private appFontFamily(content: string): string {
    if (this.fontMode !== 'custom') {
      return 'HarmonyOS Sans';
    }
    const family = this.hasCjk(content) ? this.fontFamilyZh : this.fontFamilyEn;
    return family === 'system' || family.length === 0 ? 'HarmonyOS Sans' : family;
  }

  private hasCjk(content: string): boolean {
    for (let i = 0; i < content.length; i++) {
      const code = content.charCodeAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) {
        return true;
      }
    }
    return false;
  }
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }
  @Consume('pageInfos') pageInfos: NavPathStack;
  @Prop did: string = '';
  private scroller: Scroller = new Scroller();
  @State deviceName: string = '';
  // 明面控件（含主电源）与「更多功能」折叠区；取值时两者都要覆盖，展开后读数立即可见
  @State controls: PropertyControlDescriptor[] = [];
  @State extendedControls: PropertyControlDescriptor[] = [];
  @State showExtended: boolean = false;
  // 主电源单独置顶；其余控件按服务分区
  @State primaryPowerList: PropertyControlDescriptor[] = [];
  @State sections: ServiceSection[] = [];
  @State extendedSections: ServiceSection[] = [];
  @State actionSections: ServiceSection[] = [];
  @State actions: ActionControlDescriptor[] = [];
  @State values: PropertyValueState[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State refreshInFlight: boolean = false;
  @State activeTab: string = 'status';
  @State offline: boolean = false;
  @State errorMessage: string = '';
  @State actionLoadingKey: string = '';
  @State actionArgumentValues: ActionArgumentValueState[] = [];
  @State todayEnergy: string = '';
  @State monthEnergy: string = '';
  @State currentPower: string = '';
  @State showPowerInfo: boolean = false;
  // 该设备在云端登记的耗材（滤芯/滤网等），没有登记时整卡隐藏
  @State consumables: MijiaConsumableDetail[] = [];
  // 红外遥控虚拟设备：单向通信、无可读属性，需要单独引导
  @State infrared: boolean = false;
  // 温湿度计的历史统计曲线：云端只对这类设备提供 stat_* 数据
  @State trendPoints: TrendPoint[] = [];
  @State trendTitle: string = '';
  @State trendGranularity: string = 'day';
  @StorageProp('temperatureFahrenheit') temperatureFahrenheit: boolean = false;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('isWearable') isWearable: boolean = false;

  private device: XiaomiDevice | null = null;
  private controller: DeviceController | null = null;
  // 曲线用的设备与 spec 快照：切换粒度时不必重新拉 spec
  private trendDevice: XiaomiDevice | null = null;
  private trendSpec: MIoTSpecInstance | null = null;

  private topOffset(): number {
    return (this.isWearable ? 52 : 56) + this.statusBarHeight;
  }

  private detailPadding(): number {
    return this.isWearable ? 12 : HwSpace.xl;
  }

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('设备详情页');
    this.loadDevice();
  }

  async loadDevice(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.offline = false;
    this.consumables = [];
    try {
      if (this.did.length === 0) {
        throw new Error('invalid device id');
      }
      const devices = await xiaomiDataService.getDevices();
      const device = devices[this.did];
      if (device === undefined) {
        throw new Error('device not found');
      }
      this.device = device;
      this.deviceName = device.name;
      this.offline = !device.online;
      this.infrared = this.isInfraredDevice(device);
      FeedbackLogService.recordOperation('PAGE',
        `设备详情: ${device.name} did=${device.did} model=${device.model} 在线=${device.online ? '是' : '否'}`);
      if (device.online) {
        const spec = await this.loadSpec(device);
        this.applySpec(spec);
        this.controller = await xiaomiDataService.getDeviceController(device);
        await this.refreshValues();
        this.recordDeviceValues();
        await this.loadPowerInfo(device, spec);
        // 耗材是家庭级接口且失败不影响主流程，放在最后异步拉取，不拖慢首屏
        this.loadConsumables(device);
        // 统计曲线只对温湿度计有意义，且要走多次云端试探，同样不阻塞首屏
        this.loadTrendInfo(device, spec);
      } else {
        this.resetSpecState();
      }
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '加载设备失败';
      Logger.error('load device detail failed, %{public}s', this.errorMessage);
    } finally {
      this.loading = false;
    }
  }

  /**
   * spec 获取：磁盘缓存优先。
   * spec 定义极少变化，缓存命中时页面不再受 miot-spec.org 抖动影响；
   * 缓存层本身出错（上下文缺失/缓存损坏）时回退到原来的直连拉取，保证仍能打开设备。
   */
  private async loadSpec(device: XiaomiDevice): Promise<MIoTSpecInstance> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      return await xiaomiDataService.getDeviceSpecForDeviceCached(device, context);
    } catch (err) {
      Logger.warn('cached device spec failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
    return await xiaomiDataService.getDeviceSpecForDevice(device);
  }

  private resetSpecState(): void {
    this.controls = [];
    this.extendedControls = [];
    this.showExtended = false;
    this.primaryPowerList = [];
    this.sections = [];
    this.extendedSections = [];
    this.actionSections = [];
    this.actions = [];
  }

  private applySpec(spec: MIoTSpecInstance): void {
    const displayNames = resolveServiceDisplayNames(spec.services);
    const all = this.buildControls(spec, displayNames);
    this.splitControls(all, spec, displayNames);
    this.actions = this.buildActions(spec, displayNames);
    this.actionSections = this.buildActionSections(this.actions, spec, displayNames);
    this.buildValueStates(this.controls.concat(this.extendedControls));
    this.buildActionArgumentStates(this.actions);
    // 红外设备只有动作、没有可读属性：默认落到「动作」页签，避免用户先看到空白状态页
    if (this.infrared && this.actions.length > 0 && this.visibleSectionCount() === 0) {
      this.activeTab = 'actions';
    } else {
      this.activeTab = 'status';
    }
  }

  private recordDeviceValues(): void {
    const parts: string[] = [];
    for (let i = 0; i < this.values.length; i++) {
      const state = this.values[i];
      const valueText = state.value === undefined ? 'undefined' : JSON.stringify(state.value);
      parts.push(`${state.key}=${valueText}`);
    }
    FeedbackLogService.recordOperation('PAGE', `设备详情页属性: ${parts.join(' | ')}`);
  }

  buildControls(spec: MIoTSpecInstance, displayNames: Map<number, string>): PropertyControlDescriptor[] {
    const result: PropertyControlDescriptor[] = [];
    // 多实例服务（排插多路、多键墙开）先编号（开关1/开关2…）再参与去重；
    // 去重键为 siid.piid + 类型 + 格式：同一属性重复声明只保留第一个，
    // 不同属性即使标签相同也不会被误隐藏。
    const seen = new Set<string>();
    for (let i = 0; i < spec.services.length; i++) {
      const controls = buildServiceControls(spec.services[i], displayNames);
      for (let j = 0; j < controls.length; j++) {
        const signature = `${controls[j].siid}.${controls[j].piid}|${controls[j].type}|${controls[j].format}`;
        if (seen.has(signature)) {
          continue;
        }
        seen.add(signature);
        result.push(controls[j]);
      }
    }
    // 多主电源收敛：只保留第一个电源并置顶，其余降级为普通开关；重名标签再消歧
    markPrimaryPower(result);
    dedupeControlLabels(result);
    return result;
  }

  buildActions(spec: MIoTSpecInstance, displayNames: Map<number, string>): ActionControlDescriptor[] {
    const result: ActionControlDescriptor[] = [];
    for (let i = 0; i < spec.services.length; i++) {
      const actions = buildServiceActions(spec.services[i], displayNames);
      for (let j = 0; j < actions.length; j++) {
        result.push(actions[j]);
      }
    }
    return result;
  }

  /**
   * 按 isCommon 拆成明面区与「更多功能」折叠区。
   * 兜底保护：明面区没有任何可写控制而设备本身有可写属性时不折叠、全部平铺，
   * 否则未知品类设备会因为白名单不匹配而整页只剩一个折叠入口。
   */
  private splitControls(
    all: PropertyControlDescriptor[],
    spec: MIoTSpecInstance,
    displayNames: Map<number, string>
  ): void {
    const common: PropertyControlDescriptor[] = [];
    const extended: PropertyControlDescriptor[] = [];
    let commonWritable = 0;
    let anyWritable = 0;
    for (let i = 0; i < all.length; i++) {
      const control = all[i];
      if (control.writable) {
        anyWritable++;
      }
      if (control.isCommon) {
        common.push(control);
        if (control.writable) {
          commonWritable++;
        }
      } else {
        extended.push(control);
      }
    }
    let visible = common;
    if (common.length === 0 || (commonWritable === 0 && anyWritable > 0)) {
      visible = all;
      extended.length = 0;
    }
    this.controls = visible;
    this.extendedControls = extended;
    this.showExtended = false;

    // 主电源置顶到概览下方，剩下的按服务分区
    const primary: PropertyControlDescriptor[] = [];
    const rest: PropertyControlDescriptor[] = [];
    for (let i = 0; i < visible.length; i++) {
      const control = visible[i];
      if (primary.length === 0 && control.isPower && control.type === CapabilityControlType.TOGGLE) {
        primary.push(control);
      } else {
        rest.push(control);
      }
    }
    this.primaryPowerList = primary;
    this.sections = this.buildControlSections(rest, spec, displayNames);
    this.extendedSections = this.buildControlSections(extended, spec, displayNames);
  }

  private buildControlSections(
    controls: PropertyControlDescriptor[],
    spec: MIoTSpecInstance,
    displayNames: Map<number, string>
  ): ServiceSection[] {
    const order: number[] = [];
    const grouped = new Map<number, PropertyControlDescriptor[]>();
    for (let i = 0; i < controls.length; i++) {
      const siid = controls[i].siid;
      let list = grouped.get(siid);
      if (list === undefined) {
        list = [];
        grouped.set(siid, list);
        order.push(siid);
      }
      list.push(controls[i]);
    }
    const sections: ServiceSection[] = [];
    for (let i = 0; i < order.length; i++) {
      const siid = order[i];
      sections.push({
        key: `s${siid}`,
        title: this.serviceTitle(siid, spec, displayNames),
        controls: grouped.get(siid) as PropertyControlDescriptor[],
        actions: []
      });
    }
    return sections;
  }

  private buildActionSections(
    actions: ActionControlDescriptor[],
    spec: MIoTSpecInstance,
    displayNames: Map<number, string>
  ): ServiceSection[] {
    const order: number[] = [];
    const grouped = new Map<number, ActionControlDescriptor[]>();
    for (let i = 0; i < actions.length; i++) {
      const siid = actions[i].siid;
      let list = grouped.get(siid);
      if (list === undefined) {
        list = [];
        grouped.set(siid, list);
        order.push(siid);
      }
      list.push(actions[i]);
    }
    const sections: ServiceSection[] = [];
    for (let i = 0; i < order.length; i++) {
      const siid = order[i];
      sections.push({
        key: `a${siid}`,
        title: this.serviceTitle(siid, spec, displayNames),
        controls: [],
        actions: grouped.get(siid) as ActionControlDescriptor[]
      });
    }
    return sections;
  }

  /**
   * 分区标题：多实例服务用带编号的显示名（开关1/开关2），
   * 单实例服务用翻译后的服务描述，词典未收录时退回服务名（连字符替换为空格）。
   */
  private serviceTitle(siid: number, spec: MIoTSpecInstance, displayNames: Map<number, string>): string {
    const numbered = displayNames.get(siid);
    if (numbered !== undefined && numbered.length > 0) {
      return numbered;
    }
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      if (service.iid !== siid) {
        continue;
      }
      const raw = service.description.trim().length > 0
        ? service.description.trim()
        : service.name.replace(/-/g, ' ').trim();
      const translated = translateMiotText(raw).trim();
      if (translated.length > 0) {
        return translated;
      }
    }
    return '设备功能';
  }

  buildValueStates(controls: PropertyControlDescriptor[]): void {
    const states: PropertyValueState[] = [];
    for (let i = 0; i < controls.length; i++) {
      states.push({
        key: `${controls[i].siid}.${controls[i].piid}`,
        value: undefined
      });
    }
    this.values = states;
  }

  buildActionArgumentStates(actions: ActionControlDescriptor[]): void {
    const states: ActionArgumentValueState[] = [];
    for (let i = 0; i < actions.length; i++) {
      const args = actions[i].arguments;
      for (let j = 0; j < args.length; j++) {
        states.push({
          key: `${actions[i].siid}.${actions[i].aiid}.${args[j].piid}`,
          value: undefined
        });
      }
    }
    this.actionArgumentValues = states;
  }

  async refreshValues(): Promise<void> {
    // 下拉/按钮可能连续触发，重复请求会让控件值闪回旧值，这里做单飞保护
    if (this.refreshInFlight) {
      return;
    }
    this.refreshInFlight = true;
    this.refreshing = true;
    try {
      if (this.controller === null || this.offline) {
        return;
      }
      const allControls = this.controls.concat(this.extendedControls);
      const params: DevicePropertyParam[] = [];
      for (let i = 0; i < allControls.length; i++) {
        if (!allControls[i].readable) {
          continue;
        }
        params.push({
          did: this.did,
          siid: allControls[i].siid,
          piid: allControls[i].piid
        });
      }
      if (params.length === 0) {
        return;
      }
      let results: DevicePropertyResult[] = [];
      try {
        results = await this.controller.getProperties(this.did, params);
      } catch (err) {
        results = [];
      }
      const valueMap = new Map<string, Object | undefined>();
      for (let i = 0; i < results.length; i++) {
        valueMap.set(`${results[i].siid}.${results[i].piid}`, results[i].value);
      }
      const newValues: PropertyValueState[] = [];
      for (let i = 0; i < allControls.length; i++) {
        const control = allControls[i];
        newValues.push({
          key: `${control.siid}.${control.piid}`,
          value: valueMap.get(`${control.siid}.${control.piid}`)
        });
      }
      this.values = newValues;
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '刷新属性失败';
      Logger.error('refresh values failed, %{public}s', this.errorMessage);
    } finally {
      this.refreshInFlight = false;
      this.refreshing = false;
    }
  }

  getValue(control: PropertyControlDescriptor): Object | undefined {
    const key = `${control.siid}.${control.piid}`;
    for (let i = 0; i < this.values.length; i++) {
      if (this.values[i].key === key) {
        return this.values[i].value;
      }
    }
    return undefined;
  }

  async setValue(control: PropertyControlDescriptor, value: Object): Promise<void> {
    if (this.controller === null || this.offline) {
      this.errorMessage = '设备离线';
      return;
    }
    const key = `${control.siid}.${control.piid}`;
    // 先本地置新值让开关/滑块即时反馈，失败再回滚，避免控件卡在旧值上
    const previous: Object | undefined = this.getValue(control);
    this.updateValueState(key, value);
    try {
      await this.controller.setProperty(this.did, control.siid, control.piid, value);
    } catch (err) {
      this.updateValueState(key, previous);
      this.errorMessage = err instanceof Error ? err.message : '设置属性失败';
      Logger.error('set property failed, %{public}s', this.errorMessage);
    }
  }

  async callAction(action: ActionControlDescriptor): Promise<void> {
    if (this.controller === null || this.offline) {
      this.errorMessage = '设备离线';
      return;
    }
    const missing = this.firstMissingArgument(action);
    if (missing !== null) {
      this.errorMessage = `请先设置参数「${missing.label}」`;
      return;
    }
    const key = `${action.siid}.${action.aiid}`;
    this.actionLoadingKey = key;
    try {
      const inList: Object[] = [];
      for (let i = 0; i < action.argumentPiids.length; i++) {
        const piid = action.argumentPiids[i];
        inList.push(this.coerceArgumentValue(this.findArgument(action, piid),
          this.getActionArgumentValue(action, piid)));
      }
      await this.controller.callAction(this.did, action.siid, action.aiid, inList);
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '执行动作失败';
      Logger.error('call action failed, %{public}s', this.errorMessage);
    } finally {
      this.actionLoadingKey = '';
    }
  }

  async loadPowerInfo(device: XiaomiDevice, spec: MIoTSpecInstance): Promise<void> {
    // 燃气热水器以燃气加热，不展示用电信息（电量统计/当前功率对用户无意义）。
    if (this.isGasWaterHeater(device, spec)) {
      this.showPowerInfo = false;
      return;
    }
    const energyCandidates = this.findPropertiesByKeywords(
      spec,
      ['consumption', 'electric', 'energy', 'kwh'],
      true
    );
    const powerCandidates = this.findPowerCandidates(spec);
    if (energyCandidates.length === 0 && powerCandidates.length === 0) {
      this.showPowerInfo = false;
      return;
    }
    this.showPowerInfo = true;

    if (energyCandidates.length > 0) {
      const now = Math.floor(Date.now() / 1000);
      const dayStart = now - 24 * 3600;
      const monthStart = now - 30 * 24 * 3600;
      let dayStats: Object[] = [];
      let monthStats: Object[] = [];
      for (let i = 0; i < energyCandidates.length; i++) {
        const keys = this.statisticsKeys(energyCandidates[i].key);
        dayStats = await this.tryStatistics(
          device.did,
          keys,
          ['stat_day_v3', 'stat_day'],
          1,
          dayStart,
          now
        );
        monthStats = await this.tryStatistics(
          device.did,
          keys,
          ['stat_month_v3', 'stat_month'],
          30,
          monthStart,
          now
        );
        if (dayStats.length > 0 || monthStats.length > 0) {
          break;
        }
      }
      this.todayEnergy = this.formatStat(dayStats);
      this.monthEnergy = this.formatStat(monthStats);
    } else {
      this.todayEnergy = '--';
      this.monthEnergy = '--';
    }

    if (powerCandidates.length > 0 && this.controller !== null) {
      let powerValue: Object | undefined;
      for (let i = 0; i < powerCandidates.length; i++) {
        try {
          powerValue = await this.controller.getProperty(
            device.did,
            powerCandidates[i].siid,
            powerCandidates[i].piid
          );
        } catch (err) {
          powerValue = undefined;
        }
        const numeric = Number(powerValue);
        if (powerValue !== undefined && powerValue !== null && !Number.isNaN(numeric)) {
          break;
        }
      }
      this.currentPower = powerValue === undefined || powerValue === null
        ? '--'
        : `${String(powerValue)} W`;
    } else {
      this.currentPower = '--';
    }
  }

  /**
   * 耗材：云端按家庭维度一次性返回全屋设备的耗材项，这里只挑出本设备的。
   * 该接口属于可选增强，失败只记日志（不写 errorMessage），不影响设备控制主流程。
   */
  private async loadConsumables(device: XiaomiDevice): Promise<void> {
    let homeId = device.homeId;
    if (homeId.length === 0) {
      homeId = AppSettingsStore.getString('selectedHomeId', '');
    }
    if (homeId.length === 0) {
      return;
    }
    try {
      const items = await xiaomiDataService.getConsumableItems(homeId);
      const details: MijiaConsumableDetail[] = [];
      for (let i = 0; i < items.length; i++) {
        const item: MijiaConsumableItem = items[i];
        if (item.did !== device.did) {
          continue;
        }
        for (let j = 0; j < item.details.length; j++) {
          details.push(item.details[j]);
        }
      }
      this.consumables = details;
      if (details.length > 0) {
        FeedbackLogService.recordOperation('PAGE', `设备详情耗材: ${device.name} ${details.length} 项`);
      }
    } catch (err) {
      Logger.warn('load device consumables failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
  }

  private isGasWaterHeater(device: XiaomiDevice, spec: MIoTSpecInstance): boolean {
    const parts: string[] = [device.model, device.name, device.manufacturer];
    for (let i = 0; i < spec.services.length; i++) {
      parts.push(spec.services[i].name);
      parts.push(spec.services[i].description);
      parts.push(spec.services[i].type);
      for (let j = 0; j < spec.services[i].properties.length; j++) {
        parts.push(spec.services[i].properties[j].name);
        parts.push(spec.services[i].properties[j].description);
      }
    }
    const text = parts.join(' ').toLowerCase();
    const isWaterHeater = text.includes('waterheater') ||
      text.includes('water-heater') ||
      text.includes('water heater') ||
      text.includes('热水器');
    const isGas = text.includes('gas') || text.includes('燃气');
    return isWaterHeater && isGas;
  }

  /**
   * 红外遥控设备判断：米家的红外虚拟设备（如 chuangmi.ir.v2）是单向通信、
   * 没有可读属性，必须走「动作」而不是实时状态。
   * 先按分隔符切词再精确匹配 ir/remote，避免 "air"/"aircondition" 这类子串误判。
   */
  private isInfraredDevice(device: XiaomiDevice): boolean {
    const text = `${device.model} ${device.urn} ${device.name}`.toLowerCase();
    const tokens = text.split(/[^a-z0-9\u4e00-\u9fff]+/);
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (token === 'ir' || token === 'remote' || token === 'infrared') {
        return true;
      }
    }
    return text.includes('红外') || text.includes('遥控');
  }

  async tryStatistics(
    did: string,
    keys: string[],
    dataTypes: string[],
    limit: number,
    timeStart: number,
    timeEnd: number
  ): Promise<Object[]> {
    for (let keyIndex = 0; keyIndex < keys.length; keyIndex++) {
      for (let i = 0; i < dataTypes.length; i++) {
        try {
          const items = await xiaomiDataService.getDeviceStatistics(
            did,
            keys[keyIndex],
            dataTypes[i],
            limit,
            timeStart,
            timeEnd
          );
          if (items.length > 0) {
            return items;
          }
        } catch (err) {
          // Try the next supported data type or key variant.
        }
      }
    }
    return [] as Object[];
  }

  private statisticsKeys(key: string): string[] {
    // UNVERIFIED: most MIoT statistics use `siid.piid`; some public specs
    // document `prop.siid.piid` for statistics generated from an event. Try
    // both without inventing additional variants.
    return [key, `prop.${key}`];
  }

  // ==================== 温湿度统计曲线 ====================

  /**
   * 拉取历史统计并填充曲线。
   *
   * 云端只对温湿度类设备提供 `stat_day/hour/month` 数据，且不同设备的
   * 统计键不一致（`siid.piid` 或 `prop.siid.piid`），所以逐个候选属性 + 逐个
   * dataType 试，取第一个能返回 ≥2 个点的。
   */
  private async loadTrendInfo(device: XiaomiDevice, spec: MIoTSpecInstance): Promise<void> {
    this.trendDevice = device;
    this.trendSpec = spec;
    this.trendPoints = [];
    this.trendTitle = '';
    const candidates = this.findTrendCandidates(spec);
    if (candidates.length === 0) {
      return;
    }
    const now = Math.floor(Date.now() / 1000);
    let types: string[] = ['stat_day_v3', 'stat_day'];
    let limit = 7;
    let start = now - 7 * 24 * 3600;
    if (this.trendGranularity === 'hour') {
      types = ['stat_hour_v3', 'stat_hour'];
      limit = 24;
      start = now - 24 * 3600;
    } else if (this.trendGranularity === 'month') {
      types = ['stat_month_v3', 'stat_month'];
      limit = 6;
      start = now - 180 * 24 * 3600;
    }
    for (let i = 0; i < candidates.length; i++) {
      const keys = this.statisticsKeys(candidates[i].key);
      const items = await this.tryStatistics(device.did, keys, types, limit, start, now);
      const points = this.parseTrendPoints(items, this.trendGranularity);
      if (points.length >= 2) {
        this.trendTitle = candidates[i].label;
        this.trendPoints = points;
        break;
      }
    }
  }

  private trendWindowLabel(): string {
    if (this.trendGranularity === 'hour') {
      return '近24小时';
    }
    if (this.trendGranularity === 'month') {
      return '近6个月';
    }
    return '近7天';
  }

  async switchTrendGranularity(mode: string): Promise<void> {
    if (this.trendGranularity === mode) {
      return;
    }
    this.trendGranularity = mode;
    const device = this.trendDevice;
    const spec = this.trendSpec;
    if (device === null || spec === null) {
      return;
    }
    await this.loadTrendInfo(device, spec);
  }

  /** 只挑温/湿/空气质量这三类数值属性作为曲线候选，其余属性云端没有统计。 */
  private findTrendCandidates(spec: MIoTSpecInstance): TrendCandidate[] {
    const result: TrendCandidate[] = [];
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      for (let j = 0; j < service.properties.length; j++) {
        const prop = service.properties[j];
        const format = prop.format.toLowerCase();
        if (format === 'bool' || format === 'string') {
          continue;
        }
        const text = `${prop.name} ${prop.description} ${prop.type} ${prop.unit}`.toLowerCase();
        const isTemp = text.includes('temperature');
        const isHumid = text.includes('humidity');
        const isAir = text.includes('pm2.5') || text.includes('aqi') || text.includes('co2');
        if (!isTemp && !isHumid && !isAir) {
          continue;
        }
        let label = prop.name;
        if (isTemp) {
          label = '温度';
        } else if (isHumid) {
          label = '湿度';
        } else if (text.includes('co2')) {
          label = 'CO₂';
        } else {
          label = 'PM2.5';
        }
        result.push({ key: `${service.iid}.${prop.iid}`, label: label });
      }
    }
    return result;
  }

  private parseTrendPoints(items: Object[], granularity: string): TrendPoint[] {
    const points: TrendPoint[] = [];
    for (let i = 0; i < items.length; i++) {
      const raw = (items[i] as Record<string, Object>)['value'];
      // 云端 value 常带单位（如 "23.5℃"），用正则抠出数字部分
      const match = /-?\d+(\.\d+)?/.exec(String(raw ?? ''));
      if (match === null) {
        continue;
      }
      const value = Number(match[0]);
      if (Number.isNaN(value)) {
        continue;
      }
      const ts = Number((items[i] as Record<string, Object>)['time']);
      let label = '';
      if (!Number.isNaN(ts) && ts > 0) {
        const date = new Date(ts * 1000);
        if (granularity === 'hour') {
          label = `${date.getHours()}时`;
        } else if (granularity === 'month') {
          label = `${date.getMonth() + 1}月`;
        } else {
          label = `${date.getMonth() + 1}/${date.getDate()}`;
        }
      } else {
        label = `${i + 1}`;
      }
      points.push({ label: label, value: value });
    }
    const limit = granularity === 'hour' ? 24 : (granularity === 'month' ? 6 : 7);
    if (points.length > limit) {
      return points.slice(points.length - limit);
    }
    return points;
  }

  /** 温湿度计才显示曲线：其他设备云端没有统计，拉了也是空。 */
  private isTempHumiditySensor(device: XiaomiDevice): boolean {
    const text = `${device.model} ${device.name} ${device.manufacturer}`.toLowerCase();
    return text.includes('sensor') || text.includes('thermometer') || text.includes('hygro') ||
      text.includes('miaomiaoce') || text.includes('温湿度') || text.includes('温度计') ||
      text.includes('湿度计');
  }

  private showTrendChart(): boolean {
    return this.trendPoints.length >= 2 && this.device !== null && this.isTempHumiditySensor(this.device);
  }

  private trendTitleText(): string {
    const windowLabel = this.trendWindowLabel();
    return this.trendTitle.length > 0 ? `${windowLabel}趋势：${this.trendTitle}` : `${windowLabel}趋势`;
  }

  private trendMax(): number {
    let max = 0;
    for (let i = 0; i < this.trendPoints.length; i++) {
      const v = this.trendPoints[i].value;
      if (v > max) {
        max = v;
      }
    }
    return max <= 0 ? 1 : max;
  }

  private trendBarHeight(value: number): number {
    const h = (value / this.trendMax()) * TREND_CHART_HEIGHT;
    // 最小高度保证 0 值也有一根可见的柱子，否则柱子会消失看不出有数据
    return h < 6 ? 6 : h;
  }

  private formatTrendValue(value: number): string {
    return Number.isInteger(value) ? `${value}` : value.toFixed(1);
  }

  findPropertiesByKeywords(
    spec: MIoTSpecInstance,
    keywords: string[],
    numericOnly: boolean
  ): PropertyCandidate[] {
    const result: PropertyCandidate[] = [];
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      for (let j = 0; j < service.properties.length; j++) {
        const prop = service.properties[j];
        const format = prop.format.toLowerCase();
        if (numericOnly && (format === 'bool' || format === 'string')) {
          continue;
        }
        const text = `${prop.name} ${prop.description} ${prop.type} ${prop.format} ${prop.unit}`.toLowerCase();
        for (let k = 0; k < keywords.length; k++) {
          if (text.includes(keywords[k])) {
            result.push(new PropertyCandidate(
              service.iid,
              prop.iid,
              `${service.iid}.${prop.iid}`
            ));
            break;
          }
        }
      }
    }
    return result;
  }

  private findPowerCandidates(spec: MIoTSpecInstance): PropertyCandidate[] {
    const result: PropertyCandidate[] = [];
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      for (let j = 0; j < service.properties.length; j++) {
        const prop = service.properties[j];
        const format = prop.format.toLowerCase();
        if (format === 'bool' || format === 'string') {
          continue;
        }
        const text = `${prop.name} ${prop.description} ${prop.type} ${prop.unit}`.toLowerCase();
        const isEnergy = text.includes('consumption') || text.includes('energy') ||
          text.includes('kwh') || text.includes('charge') || text.includes('accumulate');
        const isPower = text.includes('power') || text.includes('watt') ||
          text.includes('current') || text.includes('electric') || text.includes('load');
        if (isPower && !isEnergy) {
          result.push(new PropertyCandidate(
            service.iid,
            prop.iid,
            `${service.iid}.${prop.iid}`
          ));
        }
      }
    }
    return result;
  }

  formatStat(items: Object[]): string {
    if (items.length === 0) {
      return '--';
    }
    const raw = (items[0] as Record<string, Object>)['value'];
    const text = String(raw ?? '');
    const match = /-?\d+(\.\d+)?/.exec(text);
    return match === null ? text : match[0];
  }

  updateValueState(key: string, value: Object | undefined): void {
    const next: PropertyValueState[] = [];
    for (let i = 0; i < this.values.length; i++) {
      next.push(this.values[i].key === key
        ? { key: this.values[i].key, value: value }
        : this.values[i]);
    }
    this.values = next;
  }

  getActionArgumentValue(action: ActionControlDescriptor, piid: number): Object | undefined {
    const key = `${action.siid}.${action.aiid}.${piid}`;
    for (let i = 0; i < this.actionArgumentValues.length; i++) {
      if (this.actionArgumentValues[i].key === key) {
        return this.actionArgumentValues[i].value;
      }
    }
    return undefined;
  }

  updateActionArgumentValue(action: ActionControlDescriptor, piid: number, value: Object): void {
    const key = `${action.siid}.${action.aiid}.${piid}`;
    const next: ActionArgumentValueState[] = [];
    for (let i = 0; i < this.actionArgumentValues.length; i++) {
      next.push(this.actionArgumentValues[i].key === key
        ? { key: this.actionArgumentValues[i].key, value: value }
        : this.actionArgumentValues[i]);
    }
    this.actionArgumentValues = next;
  }

  private findArgument(action: ActionControlDescriptor, piid: number): ActionArgumentDescriptor | null {
    for (let i = 0; i < action.arguments.length; i++) {
      if (action.arguments[i].piid === piid) {
        return action.arguments[i];
      }
    }
    return null;
  }

  // 必填参数（bool 有默认关闭，可缺省）没填时直接拦截，避免发出一条无意义的空指令
  private firstMissingArgument(action: ActionControlDescriptor): ActionArgumentDescriptor | null {
    for (let i = 0; i < action.arguments.length; i++) {
      const arg = action.arguments[i];
      if (arg.format === 'bool') {
        continue;
      }
      const value = this.getActionArgumentValue(action, arg.piid);
      if (value === undefined || value === null) {
        return arg;
      }
      if (typeof value === 'string' && value.trim().length === 0) {
        return arg;
      }
    }
    return null;
  }

  // 输入框拿到的是字符串，int/float 参数必须转成数字，否则云端会按字符串拒绝
  private coerceArgumentValue(arg: ActionArgumentDescriptor | null, value: Object | undefined): Object {
    if (arg !== null && typeof value === 'string' && (arg.format === 'int' || arg.format === 'float')) {
      const text = value.trim();
      if (/^-?\d+(\.\d+)?$/.test(text)) {
        const num = Number(text);
        return arg.format === 'int' ? Math.round(num) : num;
      }
    }
    return value ?? '';
  }

  private boolOf(input: Object | undefined): boolean {
    return input === true || input === 1 || input === 'true' || input === '1';
  }

  private hasReadableValue(control: PropertyControlDescriptor): boolean {
    const value = this.getValue(control);
    return value !== undefined && value !== null && String(value).trim().length > 0;
  }

  private fahrenheitMode(control: PropertyControlDescriptor): boolean {
    return this.temperatureFahrenheit && isCelsiusUnit(control.unit);
  }

  private formatNumber(value: number): string {
    return Number.isInteger(value) ? String(value) : value.toFixed(1);
  }

  private readoutText(control: PropertyControlDescriptor): string {
    const value = this.getValue(control);
    if (value === undefined || value === null) {
      return '--';
    }
    if (control.options.length > 0) {
      const index = control.optionValues.indexOf(value);
      if (index >= 0) {
        return control.options[index];
      }
    }
    if (control.format === 'bool') {
      return this.boolOf(value) ? '开启' : '关闭';
    }
    if (this.fahrenheitMode(control)) {
      const number = Number(value);
      if (!Number.isNaN(number)) {
        return `${this.formatNumber(celsiusToFahrenheit(number))}${control.unit}`;
      }
    }
    return `${String(value)}${control.unit}`;
  }

  private consumableColor(percent: number): string {
    if (percent < 20) {
      return HwColor.danger;
    }
    if (percent < 50) {
      return '#E8A33D';
    }
    return HwColor.online;
  }

  /** 分区内可操作/可展示的内容计数，全空的分区连标题一起隐藏 */
  private sectionHasContent(section: ServiceSection): boolean {
    return this.sectionReadouts(section).length > 0 ||
      this.sectionSelects(section).length > 0 ||
      this.sectionTiles(section).length > 0;
  }

  private visibleSectionCount(): number {
    let count = 0;
    for (let i = 0; i < this.sections.length; i++) {
      if (this.sectionHasContent(this.sections[i])) {
        count++;
      }
    }
    return count;
  }

  // 只读读数：只保留真的取到值的项，否则整卡都是「--」没有信息量
  private sectionReadouts(section: ServiceSection): PropertyControlDescriptor[] {
    const result: PropertyControlDescriptor[] = [];
    for (let i = 0; i < section.controls.length; i++) {
      const control = section.controls[i];
      if (control.type === CapabilityControlType.READOUT && !control.writable &&
        this.hasReadableValue(control)) {
        result.push(control);
      }
    }
    return result;
  }

  // 模式/挡位类：选项要占满一行才好点，用整行卡
  private sectionSelects(section: ServiceSection): PropertyControlDescriptor[] {
    const result: PropertyControlDescriptor[] = [];
    for (let i = 0; i < section.controls.length; i++) {
      if (section.controls[i].type === CapabilityControlType.SELECT) {
        result.push(section.controls[i]);
      }
    }
    return result;
  }

  // 其余开关/滑块/数值：两列网格卡片
  private sectionTiles(section: ServiceSection): PropertyControlDescriptor[] {
    const result: PropertyControlDescriptor[] = [];
    for (let i = 0; i < section.controls.length; i++) {
      const control = section.controls[i];
      if (control.type === CapabilityControlType.SELECT) {
        continue;
      }
      if (control.type === CapabilityControlType.READOUT && !control.writable) {
        continue;
      }
      result.push(control);
    }
    return result;
  }

  // 网格按行切片：一行两个，单数行留等宽占位，保证卡片宽度一致
  /** 概览关键读数：明面控件里已取到值的只读读数，最多三项 */
  private keyReadouts(): PropertyControlDescriptor[] {
    const result: PropertyControlDescriptor[] = [];
    for (let i = 0; i < this.controls.length; i++) {
      if (result.length >= 3) {
        break;
      }
      const control = this.controls[i];
      if (control.type === CapabilityControlType.READOUT && this.hasReadableValue(control)) {
        result.push(control);
      }
    }
    return result;
  }

  private deviceSubtitle(): string {
    const device = this.device;
    if (device === null) {
      return '';
    }
    const parts: string[] = [];
    if (device.model.length > 0) {
      parts.push(device.model);
    }
    if (device.roomName.length > 0) {
      parts.push(device.roomName);
    }
    if (this.infrared) {
      parts.push('红外遥控');
    }
    return parts.join(' · ');
  }

  private deviceOnline(): boolean {
    const device = this.device;
    return device !== null && device.online;
  }

  private emptyStateHint(): string {
    if (this.infrared) {
      return this.actions.length > 0
        ? '红外设备为单向通信、没有实时状态反馈，请切换到「动作」页签发送指令'
        : '红外设备为单向通信、没有实时状态反馈，当前未读取到可发送的指令';
    }
    return this.actions.length > 0
      ? '该设备没有可读属性，请切换到「动作」页签执行设备动作'
      : '该设备的 spec 未声明可展示的属性，可点击右上角刷新重试';
  }

  openAboutDevice(): void {
    const device = this.device;
    if (device === null) {
      return;
    }
    this.pageInfos.pushPathByName('aboutDevice', new AboutDeviceRouteParam(
      device.name,
      device.manufacturer,
      device.model,
      device.did,
      device.fwVersion
    ));
  }

  // 概览卡：名称/型号/在线状态/关键读数，进页面先交代「这是什么设备、现在怎么样」
  @Builder
  overviewCard() {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardSpace: 10,
      cardAlignItems: ItemAlign.Start
    }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.deviceName.length > 0 ? this.deviceName : '设备')
            .fontFamily(this.appFontFamily(this.deviceName))
            .fontWeight(this.appFontWeight())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(HwColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.deviceSubtitle().length > 0) {
            Text(this.deviceSubtitle())
              .fontFamily(this.appFontFamily(this.deviceSubtitle()))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.deviceOnline() ? '在线' : '离线')
          .fontFamily(this.appFontFamily(this.deviceOnline() ? '在线' : '离线'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(this.deviceOnline() ? HwColor.online : HwColor.danger)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(HwRadius.pill)
          .backgroundColor(this.deviceOnline() ? '#1A1AAB6A' : '#1AD94838')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.keyReadouts().length > 0) {
        Divider()
          .color(HwGlassCardColor.border)
        ForEach(this.keyReadouts(), (control: PropertyControlDescriptor) => {
          this.readoutRow(control)
        }, (control: PropertyControlDescriptor) => `key_${control.siid}_${control.piid}`)
      }
    }
  }

  // 读数行：左标签右数值，概览卡与分区读数卡共用
  @Builder
  readoutRow(control: PropertyControlDescriptor) {
    Row({ space: 12 }) {
      Text(control.label)
        .fontFamily(this.appFontFamily(control.label))
        .fontWeight(this.appFontWeight())
        .fontSize(14)
        .fontColor(HwColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.readoutText(control))
        .fontFamily(this.appFontFamily(this.readoutText(control)))
        .fontWeight(this.appFontWeight())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textPrimary)
        .maxLines(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 主电源：从分区里提出来置顶，避免和一堆普通开关混在一起
  @Builder
  primaryPowerCard(control: PropertyControlDescriptor) {
    Column({ space: 10 }) {
      Text('主控')
        .fontFamily(this.appFontFamily('主控'))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textPrimary)
        .width('100%')
      PropertyControl({
        control: control,
        value: this.getValue(control),
        compact: false,
        onChanged: (value: Object) => {
          this.setValue(control, value);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 用电信息卡：保留原有内容，改成卡片内的读数行样式
  @Builder
  powerInfoCard() {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardSpace: 8,
      cardAlignItems: ItemAlign.Start
    }) {
      Text('用电信息')
        .fontFamily(this.appFontFamily('用电信息'))
        .fontWeight(this.appFontWeight())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textPrimary)
      Text(`今日用电：${this.todayEnergy}`)
        .fontFamily(this.appFontFamily(`今日用电：${this.todayEnergy}`))
        .fontWeight(this.appFontWeight())
        .fontSize(14)
        .fontColor(HwColor.textSecondary)
      Text(`近一个月用电：${this.monthEnergy}`)
        .fontFamily(this.appFontFamily(`近一个月用电：${this.monthEnergy}`))
        .fontWeight(this.appFontWeight())
        .fontSize(14)
        .fontColor(HwColor.textSecondary)
      Text(`当前功率：${this.currentPower}`)
        .fontFamily(this.appFontFamily(`当前功率：${this.currentPower}`))
        .fontWeight(this.appFontWeight())
        .fontSize(14)
        .fontColor(HwColor.textSecondary)
    }
  }

  // 耗材卡：云端登记了本设备耗材时才出现（滤芯/滤网/电池等剩余量）
  @Builder
  consumableCard() {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardSpace: 12,
      cardAlignItems: ItemAlign.Start
    }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.leaf'))
          .fontSize(16)
          .fontColor([HwColor.primary])
        Text('耗材')
          .fontFamily(this.appFontFamily('耗材'))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(this.consumables, (detail: MijiaConsumableDetail) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(detail.name)
              .fontFamily(this.appFontFamily(detail.name))
              .fontWeight(this.appFontWeight())
              .fontSize(14)
              .fontColor(HwColor.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (detail.remainText.length > 0) {
              Text(detail.remainText)
                .fontFamily(this.appFontFamily(detail.remainText))
                .fontWeight(this.appFontWeight())
                .fontSize(12)
                .fontColor(HwColor.textSecondary)
                .maxLines(1)
            }
            if (detail.percent >= 0) {
              Text(`${Math.round(detail.percent)}%`)
                .fontFamily(this.appFontFamily(`${Math.round(detail.percent)}%`))
                .fontWeight(this.appFontWeight())
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.consumableColor(detail.percent))
                .maxLines(1)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (detail.percent >= 0) {
            Progress({
              value: Math.max(0, Math.min(100, detail.percent)),
              total: 100,
              type: ProgressType.Linear
            })
              .width('100%')
              .height(6)
              .color(this.consumableColor(detail.percent))
              .backgroundColor(withAlpha(HwColor.primary, 0.1))
              .borderRadius(3)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (detail: MijiaConsumableDetail, index: number) => `consumable_${index}_${detail.name}`)
    }
  }

  // 页签：状态 / 动作，整体居中（卡片只作容器，保证和其余区块视觉一致）
  @Builder
  tabBar() {
    MaterialCard({
      cardRadius: HwRadius.pill,
      cardPadding: 4,
      cardDirection: FlexDirection.Row,
      cardAlignItems: ItemAlign.Center
    }) {
      Row({ space: 4 }) {
        this.tabItem('status', '状态')
        this.tabItem('actions', '动作')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  tabItem(tab: string, label: string) {
    Text(label)
      .fontFamily(this.appFontFamily(label))
      .fontWeight(this.appFontWeight())
      .fontSize(15)
      .fontWeight(this.activeTab === tab ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.activeTab === tab ? Color.White : HwColor.textPrimary)
      .textAlign(TextAlign.Center)
      .padding({ left: 28, right: 28, top: 8, bottom: 8 })
      .borderRadius(HwRadius.pill)
      .backgroundColor(this.activeTab === tab ? HwColor.primary : Color.Transparent)
      .onClick(() => {
        if (this.activeTab === tab) {
          return;
        }
        this.activeTab = tab;
        this.scroller.scrollTo({
          xOffset: 0,
          yOffset: 0,
          animation: { duration: 200, curve: Curve.EaseOut }
        });
      })
  }

  // 单个服务分区：标题 + 读数卡 + 整行选择卡 + 两列控件卡
  @Builder
  sectionView(section: ServiceSection) {
    if (this.sectionHasContent(section)) {
      Column({ space: 10 }) {
        Text(section.title)
          .fontFamily(this.appFontFamily(section.title))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.sectionReadouts(section).length > 0) {
          this.readoutCard(this.sectionReadouts(section))
        }

        ForEach(this.sectionSelects(section), (control: PropertyControlDescriptor) => {
          PropertyControl({
            control: control,
            value: this.getValue(control),
            compact: false,
            selectSingleRow: true,
            onChanged: (value: Object) => {
              this.setValue(control, value);
            }
          })
        }, (control: PropertyControlDescriptor) => `select_${control.siid}_${control.piid}`)

        // 属性卡固定单列：双列会把卡片压到半宽，标签与数值频繁截断
        ForEach(this.sectionTiles(section), (control: PropertyControlDescriptor) => {
          PropertyControl({
            control: control,
            value: this.getValue(control),
            compact: false,
            onChanged: (value: Object) => {
              this.setValue(control, value);
            }
          })
        }, (control: PropertyControlDescriptor) => `tile_${control.siid}_${control.piid}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 分区读数卡：同一服务的多个只读读数合并成一张卡，读数行左右对齐
  @Builder
  readoutCard(readouts: PropertyControlDescriptor[]) {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardSpace: 10,
      cardAlignItems: ItemAlign.Start
    }) {
      ForEach(readouts, (control: PropertyControlDescriptor) => {
        this.readoutRow(control)
      }, (control: PropertyControlDescriptor) => `readout_${control.siid}_${control.piid}`)
    }
  }

  // 更多功能折叠入口：非常用属性不删除、只是默认收起，避免明面被小众开关淹没
  @Builder
  extendedToggleCard() {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardDirection: FlexDirection.Row,
      cardAlignItems: ItemAlign.Center,
      cardOnClick: () => {
        this.showExtended = !this.showExtended;
      }
    }) {
      Text(this.showExtended ? '收起更多功能' : `更多功能（${this.extendedControls.length}）`)
        .fontFamily(this.appFontFamily('更多功能'))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textPrimary)
        .layoutWeight(1)
      // sys.symbol.arrow_up_arrow_down 在当前 SDK 不存在（编译器报 unknown resource），
      // 改用已验证的 chevron 并以旋转表达展开/收起。
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([HwColor.textSecondary])
        .rotate({ angle: this.showExtended ? 90 : 0 })
    }
  }

  // 动作分区：动作本身就是红外设备的「控件」，因此同样按服务分区并带标题
  @Builder
  actionSectionView(section: ServiceSection) {
    Column({ space: 4 }) {
      Text(section.title)
        .fontFamily(this.appFontFamily(section.title))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      ForEach(section.actions, (action: ActionControlDescriptor) => {
        this.actionView(action)
      }, (action: ActionControlDescriptor) => `action_${action.siid}_${action.aiid}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 单个动作：标题 + 参数卡（ActionArgumentControl 自带 MaterialCard）+ 执行按钮
  @Builder
  actionView(action: ActionControlDescriptor) {
    Column({ space: 8 }) {
      Text(action.label)
        .fontFamily(this.appFontFamily(action.label))
        .fontWeight(this.appFontWeight())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })

      ForEach(action.arguments, (argument: ActionArgumentDescriptor) => {
        ActionArgumentControl({
          argument: argument,
          value: this.getActionArgumentValue(action, argument.piid),
          onChanged: (value: Object) => {
            this.updateActionArgumentValue(action, argument.piid, value);
          }
        })
      }, (argument: ActionArgumentDescriptor) => `arg_${action.siid}_${action.aiid}_${argument.piid}`)

      ActionControl({
        control: action,
        loading: this.actionLoadingKey === `${action.siid}.${action.aiid}`,
        onAction: () => {
          this.callAction(action);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 空状态卡：没有可渲染内容时给明确引导，而不是白屏
  @Builder
  emptyStateCard() {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardSpace: 6,
      cardAlignItems: ItemAlign.Center
    }) {
      Text(this.infrared ? '红外遥控设备' : '暂无可展示的功能')
        .fontFamily(this.appFontFamily(this.infrared ? '红外遥控设备' : '暂无可展示的功能'))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(HwColor.textPrimary)
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(this.emptyStateHint())
        .fontFamily(this.appFontFamily(this.emptyStateHint()))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontColor(HwColor.textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
  }

  // ==================== 温湿度统计曲线 ====================

  /** 粒度切换页签：选中态用主色填充，未选中态描边 */
  @Builder
  trendTab(mode: string, label: string) {
    Text(label)
      .fontFamily(this.appFontFamily(label))
      .fontWeight(this.appFontWeight())
      .fontSize(12)
      .fontColor(this.trendGranularity === mode ? HwColor.surface : HwColor.textSecondary)
      .padding({ left: HwSpace.md, right: HwSpace.md, top: 5, bottom: 5 })
      .borderRadius(HwRadius.pill)
      .backgroundColor(this.trendGranularity === mode ? HwColor.primary : Color.Transparent)
      .border({
        width: 1,
        color: this.trendGranularity === mode ? HwColor.primary : HwGlassCardColor.border
      })
      .onClick(() => {
        this.switchTrendGranularity(mode);
      })
  }

  @Builder
  trendBar(point: TrendPoint, index: number) {
    Column({ space: 4 }) {
      Text(this.formatTrendValue(point.value))
        .fontFamily(this.appFontFamily(this.formatTrendValue(point.value)))
        .fontWeight(this.appFontWeight())
        .fontSize(10)
        .fontColor(HwColor.textSecondary)
        .maxLines(1)
      Column()
        .width('100%')
        .height(this.trendBarHeight(point.value))
        .borderRadius(4)
        // 最新一根用主色突出，其余用弱化的主色，形成「递增强调」的观感
        .backgroundColor(index === this.trendPoints.length - 1 ? HwColor.primary : '#4D0A59F7')
      Text(point.label)
        .fontFamily(this.appFontFamily(point.label))
        .fontWeight(this.appFontWeight())
        .fontSize(10)
        .fontColor(HwColor.textSecondary)
        .maxLines(1)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.End)
  }

  @Builder
  trendChart() {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardPadding: HwSpace.lg,
      cardSpace: HwSpace.md,
      cardAlignItems: ItemAlign.Start
    }) {
      Row({ space: HwSpace.sm }) {
        Text(this.trendTitleText())
          .fontFamily(this.appFontFamily(this.trendTitleText()))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .layoutWeight(1)
        this.trendTab('day', '近7天')
        this.trendTab('hour', '近24小时')
        this.trendTab('month', '近6个月')
      }
      .width('100%')

      // 柱状图：每根柱子的高度按当组最大值归一化
      Row({ space: 4 }) {
        ForEach(this.trendPoints, (point: TrendPoint, index: number) => {
          this.trendBar(point, index)
        }, (point: TrendPoint, index: number) => `${index}_${point.label}`)
      }
      .width('100%')
      .height(TREND_CHART_HEIGHT + 34)
      .alignItems(VerticalAlign.Bottom)
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
        AccentColorSentinel()
        AppBackground()

        Scroll(this.scroller) {
          Column({ space: 14 }) {
            Blank().height(this.topOffset())

            if (this.errorMessage.length > 0) {
              Text(this.errorMessage)
                .fontFamily(this.appFontFamily(this.errorMessage))
                .fontWeight(this.appFontWeight())
                .fontSize(14)
                .fontColor(HwColor.danger)
            }

            if (this.loading) {
              LoadingProgress()
                .width(128)
                .height(128)
            } else {
              // 离线也先给概览（名称/型号/状态），用户至少知道打开的是哪台设备
              if (this.device !== null) {
                this.overviewCard()
              }

              if (this.offline) {
                Text('设备离线')
                  .fontFamily(this.appFontFamily('设备离线'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(16)
                  .fontColor(HwColor.danger)
              } else {
                if (this.primaryPowerList.length > 0) {
                  this.primaryPowerCard(this.primaryPowerList[0])
                }

                if (this.showPowerInfo) {
                  this.powerInfoCard()
                }

                if (this.consumables.length > 0) {
                  this.consumableCard()
                }

                // 温湿度计的统计曲线：只在这类设备且云端确实返回数据时出现
                if (this.showTrendChart()) {
                  this.trendChart()
                }

                if (this.actions.length > 0) {
                  this.tabBar()
                }

                if (this.activeTab === 'status') {
                  if (this.visibleSectionCount() === 0 && this.extendedControls.length === 0) {
                    this.emptyStateCard()
                  } else {
                    ForEach(this.sections, (section: ServiceSection) => {
                      this.sectionView(section)
                    }, (section: ServiceSection) => `sec_${section.key}`)

                    if (this.extendedControls.length > 0) {
                      this.extendedToggleCard()
                    }
                    if (this.showExtended) {
                      ForEach(this.extendedSections, (section: ServiceSection) => {
                        this.sectionView(section)
                      }, (section: ServiceSection) => `ext_${section.key}`)
                    }
                  }
                } else {
                  ForEach(this.actionSections, (section: ServiceSection) => {
                    this.actionSectionView(section)
                  }, (section: ServiceSection) => `act_${section.key}`)
                }
              }
            }

            Blank()
              .height(this.navigationBarHeight + 24)
          }
          .width('100%')
          .padding({ left: this.detailPadding(), right: this.detailPadding() })
        }
        .width('100%')
        .height('100%')
        .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        Row({ space: 10 }) {
          IconCircleButton({
            symbol: $r('sys.symbol.chevron_left'),
            onAction: () => {
              this.pageInfos.pop();
            }
          })
          Text(this.deviceName)
            .fontFamily(this.appFontFamily(this.deviceName))
            .fontWeight(this.appFontWeight())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(HwColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          IconCircleButton({
            symbol: $r('sys.symbol.arrow_counterclockwise'),
            buttonEnabled: !this.refreshing,
            onAction: () => {
              this.refreshValues();
            }
          })
          IconCircleButton({
            symbol: $r('sys.symbol.info_circle'),
            onAction: () => {
              this.openAboutDevice();
            }
          })
        }
        .width('100%')
        .height((this.isWearable ? 52 : 56) + this.statusBarHeight)
        .padding({ left: this.isWearable ? 10 : 16, right: this.isWearable ? 10 : 16, top: this.statusBarHeight })
        .backgroundEffect({ radius: 12, color: '#66FFFFFF' })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? HwColor.backgroundDark : HwColor.background)
    .clip(this.isWearable)
    .borderRadius(this.isWearable ? '50%' : 0)
    .hideTitleBar(true)
    .hideBackButton(true)
    .hideToolBar(true, true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.pageInfos.pop();
    })
  }
}

class PropertyCandidate {
  readonly siid: number;
  readonly piid: number;
  readonly key: string;

  constructor(siid: number, piid: number, key: string) {
    this.siid = siid;
    this.piid = piid;
    this.key = key;
  }
}
