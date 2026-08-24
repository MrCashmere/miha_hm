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

import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType,
  HdsTabs,
  HdsTabsController,
  hdsMaterial
} from '@kit.UIDesignKit';
import { XiaomiDevice, XiaomiHome, InfoExcludeOption, ALL_HOMES_ID, ALL_HOMES_NAME } from '../models/XiaomiHomeModels';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';
import { DataSourceState } from '../models/CacheState';
import { XiaomiAuthError } from '../models/XiaomiErrors';
import { HwColor, HwRadius, HwSpace, HwGlassCardColor } from '../utils/DesignTokens';
import { isApi26OrAbove, immersiveMaterialModifier, legacyMaterialModifier, sheetSystemMaterial, sheetBlurStyle } from '../utils/SystemMaterial';
import { isCelsiusUnit, celsiusToFahrenheit } from '../utils/TemperatureDisplay';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { AppBackground } from '../components/AppBackground';
import { DeviceDetailRouteParam } from '../models/NavRouteParams';
import { DeviceController } from '../controllers/DeviceController';
import { DevicePropertyParam, DevicePropertyResult } from '../controllers/DeviceTransport';
import { MIoTSpecInstance } from '../models/MIotSpecModels';
import { RoomStore, UserRoom } from '../storage/RoomStore';

const TITLE_BAR_HEIGHT_FREE: number = 137;
const CONTENT_TOP_OFFSET: number = 137;
const BOTTOM_BAR_HEIGHT: number = 56;
const BOTTOM_BAR_MARGIN: number = 12;
const INFO_CARD_HEIGHT: number = 128;
const SIDE_BAR_WIDTH_DEFAULT: number = 96;
const SIDE_BAR_WIDTH_MIN: number = 80;
const SIDE_BAR_WIDTH_MAX: number = 320;
const MAX_CONTENT_WIDTH: number = 1080;

interface InfoSpecProperty {
  siid: number;
  piid: number;
  unit: string;
}

interface InfoPropertyTarget {
  did: string;
  name: string;
  roomName: string;
  siid: number;
  piid: number;
  unit: string;
}

interface InfoMetricRange {
  min: number;
  max: number;
  count: number;
  average: number;
}

interface InfoDeviceEntry {
  did: string;
  name: string;
  roomName: string;
  valueText: string;
}

interface InfoMetricResult {
  range: InfoMetricRange;
  entries: InfoDeviceEntry[];
}

interface InfoMetricCardConfig {
  title: string;
  rangeText: string;
  moreText: string;
}

@Entry
@Component
struct HomePage {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  @StorageLink('homeSmoothSwitch') homeSmoothSwitch: boolean = false;
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
  @Provide('pageInfos') pageInfos: NavPathStack = new NavPathStack();
  private tabsController: HdsTabsController = new HdsTabsController();
  private homeScroller: Scroller = new Scroller();
  private mineScroller: Scroller = new Scroller();
  private infoScroller: Scroller = new Scroller();
  private allVisibleDevices: XiaomiDevice[] = [];
  private infoFetching: boolean = false;
  @StorageLink('selectedHomeId') selectedHomeId: string = '';
  @StorageLink('selectedHomeName') selectedHomeName: string = '';
  @StorageLink('homeSelectionVersion') @Watch('onHomeSelectionChanged') homeSelectionVersion: number = 0;
  @State homes: XiaomiHome[] = [];
  @State devices: XiaomiDevice[] = [];
  @State loading: boolean = true;
  @State statusMessage: string = '';
  @State errorMessage: string = '';
  @State dataState: DataSourceState = DataSourceState.ONLINE;
  @State activeTab: number = 0;
  @State accountUserId: string = '';
  @State accountNickname: string = '';
  @State accountAvatarUrl: string = '';
  @StorageLink('hideOfflineDevices') @Watch('onHideOfflineDevicesChanged') hideOfflineDevices: boolean = false;
  @StorageLink('dualColumnMode') dualColumnMode: boolean = false;
  @StorageLink('autoMultiColumn') autoMultiColumn: boolean = false;
  @StorageProp('isLargeScreen') isLargeScreen: boolean = false;
  @StorageProp('is2in1') is2in1: boolean = false;
  @StorageProp('isWearable') isWearable: boolean = false;
  @StorageProp('currentWidthBreakpoint') @Watch('onBreakpointChange')
  widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;
  @StorageProp('screenWidthVp') screenWidthVp: number = 0;
  @StorageLink('pcLayoutEnabled') @Watch('onBreakpointChange') pcLayoutEnabled: boolean = false;
  @State isWideScreen: boolean = false;
  @State sideBarWidth: number = SIDE_BAR_WIDTH_DEFAULT;
  @State dragHovered: boolean = false;
  private dragStartWidth: number = SIDE_BAR_WIDTH_DEFAULT;
  @StorageLink('temperatureFahrenheit') @Watch('onTemperatureUnitChanged') temperatureFahrenheit: boolean = false;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('infoExcludedDevices') infoExcludedDevices: string[] = [];
  @StorageLink('backgroundImage') wallpaperImage: string = '';
  @StorageLink('infoShowMoreContent') infoShowMoreContent: boolean = true;
  @StorageLink('sortDevicesByRoom') sortDevicesByRoom: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('defaultHomeTab') defaultHomeTab: string = 'home';
  @StorageLink('infoRefreshInterval') @Watch('onInfoRefreshIntervalChanged') infoRefreshInterval: string = '30';
  @State localRooms: UserRoom[] = [];
  private pendingDeviceDid: string = '';
  private infoRefreshTimer: number = -1;
  private lastInfoRefreshAt: number = 0;
  @State infoLoading: boolean = false;
  @State infoError: string = '';
  @State temperatureRangeText: string = '--';
  @State humidityRangeText: string = '--';
  @State pm25RangeText: string = '--';
  @State temperatureMoreText: string = '';
  @State humidityMoreText: string = '';
  @State pm25MoreText: string = '';
  @State onDeviceCount: number = 0;
  @State infoDeviceCount: number = 0;
  @State temperatureDevices: InfoDeviceEntry[] = [];
  @State humidityDevices: InfoDeviceEntry[] = [];
  @State pm25Devices: InfoDeviceEntry[] = [];
  @State onDevices: InfoDeviceEntry[] = [];
  @State showTemperatureSheet: boolean = false;
  @State showHumiditySheet: boolean = false;
  @State showPm25Sheet: boolean = false;
  @State showOnSheet: boolean = false;
  @State showExcludeSheet: boolean = false;
  @State showFamilySheet: boolean = false;

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('首页');
    this.onBreakpointChange();
    this.localRooms = RoomStore.loadRooms();
    this.loadData(true);
    this.loadAccount();
    if (this.defaultHomeTab === 'info' && !this.isWearable) {
      this.activeTab = 1;
      this.refreshInfoOnEnter();
      this.startInfoRefreshTimer();
    }
  }

  aboutToDisappear(): void {
    this.stopInfoRefreshTimer();
  }

  onPageShow(): void {
    this.localRooms = RoomStore.loadRooms();
    this.applyDeviceVisibility();
  }

  onHideOfflineDevicesChanged(): void {
    this.applyDeviceVisibility();
  }

  private applyDeviceVisibility(): void {
    let visible = this.allVisibleDevices;
    if (this.hideOfflineDevices) {
      visible = visible.filter((device: XiaomiDevice) => device.online);
    }
    this.devices = this.sortVisibleDevices(visible);
  }

  async loadData(forceRefresh: boolean, silent: boolean = false): Promise<void> {
    if (!silent) {
      this.loading = true;
    }
    this.errorMessage = '';
    this.statusMessage = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const snapshot = await xiaomiDataService.getHomeSnapshot(context, forceRefresh);
      const homes = JSON.parse(snapshot.homesJson) as XiaomiHome[];
      const deviceMap = JSON.parse(snapshot.devicesJson) as Record<string, XiaomiDevice>;
      this.dataState = snapshot.state;
      this.homes = homes;
      if (this.selectedHomeId.length === 0 && homes.length > 0) {
        this.selectedHomeId = homes[0].homeId;
        this.selectedHomeName = homes[0].name;
        AppSettingsStore.setString('selectedHomeId', homes[0].homeId);
        AppSettingsStore.setString('selectedHomeName', homes[0].name);
      }
      const allDevices: XiaomiDevice[] = [];
      const dids = Object.keys(deviceMap);
      for (let i = 0; i < dids.length; i++) {
        allDevices.push(deviceMap[dids[i]]);
      }
      let visibleDevices: XiaomiDevice[] = [];
      if (this.selectedHomeId.length === 0) {
        visibleDevices = [];
      } else if (this.selectedHomeId === ALL_HOMES_ID) {
        visibleDevices = allDevices;
      } else {
        visibleDevices = allDevices.filter((device: XiaomiDevice) => device.homeId === this.selectedHomeId);
      }
      this.allVisibleDevices = visibleDevices;
      let displayDevices: XiaomiDevice[] = [];
      if (this.hideOfflineDevices) {
        displayDevices = visibleDevices.filter((device: XiaomiDevice) => device.online);
      } else {
        displayDevices = visibleDevices;
      }
      this.devices = this.sortVisibleDevices(displayDevices);
      FeedbackLogService.recordOperation('PAGE',
        `首页设备列表: 共 ${displayDevices.length} 台，${this.deviceListSummary(displayDevices)}`);
      const excludeOptions: InfoExcludeOption[] = [];
      for (let i = 0; i < displayDevices.length; i++) {
        excludeOptions.push({
          did: displayDevices[i].did,
          name: displayDevices[i].name,
          roomName: displayDevices[i].roomName
        });
      }
      AppStorage.setOrCreate('infoDeviceOptions', excludeOptions);

      if (this.selectedHomeId.length === 0) {
        this.statusMessage = '请先选择家庭';
      } else if (this.dataState === DataSourceState.STALE) {
        this.statusMessage = '网络不可用，当前显示过期缓存';
      } else if (this.dataState === DataSourceState.CACHED) {
        this.statusMessage = '网络不可用，当前显示最近缓存';
      } else if (this.devices.length === 0) {
        this.statusMessage = this.selectedHomeId === ALL_HOMES_ID ? '没有设备' : '当前家庭没有设备';
      }
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '加载家庭数据失败';
      Logger.error('load home data failed, %{public}s', this.errorMessage);
      if (err instanceof XiaomiAuthError) {
        await xiaomiDataService.clearSession();
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' });
      }
    } finally {
      if (!silent) {
        this.loading = false;
      }
    }
  }

  async loadAccount(): Promise<void> {
    try {
      const auth = await xiaomiDataService.getMijiaAuth();
      if (auth !== null) {
        this.accountUserId = auth.userId;
      }
      const profile = await xiaomiDataService.getUserProfile();
      if (profile !== null) {
        this.accountNickname = profile.nickname;
        this.accountAvatarUrl = profile.avatarUrl;
      } else {
        this.accountNickname = '';
        this.accountAvatarUrl = '';
      }
    } catch (err) {
      this.accountUserId = '';
      this.accountNickname = '';
      this.accountAvatarUrl = '';
    }
  }

  onHomeSelectionChanged(): void {
    if (this.selectedHomeId.length > 0) {
      this.loadData(true);
    }
  }

  showLogoutDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: HwColor.danger,
        action: () => {
          this.confirmLogout();
        }
      }
    });
  }

  async confirmLogout(): Promise<void> {
    FeedbackLogService.recordOperation('UI', '退出登录');
    await xiaomiDataService.clearSession();
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' });
  }

  async loadInfoData(silent: boolean = false): Promise<void> {
    if (this.infoFetching) {
      return;
    }
    this.infoFetching = true;
    if (!silent) {
      this.infoLoading = true;
      this.infoError = '';
      this.temperatureRangeText = '--';
      this.humidityRangeText = '--';
      this.pm25RangeText = '--';
      this.temperatureMoreText = '';
      this.humidityMoreText = '';
      this.pm25MoreText = '';
      this.onDeviceCount = 0;
      this.temperatureDevices = [];
      this.humidityDevices = [];
      this.pm25Devices = [];
      this.onDevices = [];
      this.infoDeviceCount = 0;
    }
    try {
      let familyDevices = this.devices;
      if (familyDevices.length === 0) {
        await this.loadData(false);
        familyDevices = this.devices;
      }
      const temperatureTargets: InfoPropertyTarget[] = [];
      const humidityTargets: InfoPropertyTarget[] = [];
      const pm25Targets: InfoPropertyTarget[] = [];
      const switchTargets: InfoPropertyTarget[] = [];
      for (let i = 0; i < familyDevices.length; i++) {
        const device = familyDevices[i];
        if (!device.online) {
          continue;
        }
        if (this.isDeviceExcluded(device.did)) {
          continue;
        }
        let spec: MIoTSpecInstance;
        try {
          spec = await xiaomiDataService.getDeviceSpecForDevice(device);
        } catch (err) {
          Logger.warn('load info spec failed for %{public}s, %{public}s',
            device.did, err instanceof Error ? err.message : String(err));
          continue;
        }
        const temperatureProp = this.findInfoProperty(spec, ['temperature'],
          ['target', 'set', 'color-temperature', 'colour-temperature', 'color temperature',
            'colour temperature', 'color.temperature', 'colour.temperature'],
          ['kelvin', 'k']);
        if (temperatureProp !== null) {
          const temperatureTarget: InfoPropertyTarget = {
            did: device.did,
            name: device.name,
            roomName: device.roomName,
            siid: temperatureProp.siid,
            piid: temperatureProp.piid,
            unit: temperatureProp.unit
          };
          temperatureTargets.push(temperatureTarget);
        }
        const humidityProp = this.findInfoProperty(spec, ['humidity'], ['target', 'set'], []);
        if (humidityProp !== null) {
          const humidityTarget: InfoPropertyTarget = {
            did: device.did,
            name: device.name,
            roomName: device.roomName,
            siid: humidityProp.siid,
            piid: humidityProp.piid,
            unit: humidityProp.unit
          };
          humidityTargets.push(humidityTarget);
        }
        const pm25Prop = this.findInfoProperty(spec, ['pm2.5'], [], []);
        if (pm25Prop !== null) {
          const pm25Target: InfoPropertyTarget = {
            did: device.did,
            name: device.name,
            roomName: device.roomName,
            siid: pm25Prop.siid,
            piid: pm25Prop.piid,
            unit: pm25Prop.unit
          };
          pm25Targets.push(pm25Target);
        }
        const switchProp = this.findSwitchProperty(spec);
        if (switchProp !== null) {
          const switchTarget: InfoPropertyTarget = {
            did: device.did,
            name: device.name,
            roomName: device.roomName,
            siid: switchProp.siid,
            piid: switchProp.piid,
            unit: ''
          };
          switchTargets.push(switchTarget);
        }
      }
      this.infoDeviceCount = temperatureTargets.length + humidityTargets.length +
        pm25Targets.length + switchTargets.length;
      const controller = await xiaomiDataService.getDeviceController();
      const temperatureResult = await this.fetchInfoMetric(controller, temperatureTargets);
      const humidityResult = await this.fetchInfoMetric(controller, humidityTargets);
      const pm25Result = await this.fetchInfoMetric(controller, pm25Targets);
      this.temperatureRangeText = this.formatInfoRange(temperatureResult.range,
        this.infoUnitText(this.firstTargetUnit(temperatureTargets)));
      this.humidityRangeText = this.formatInfoRange(humidityResult.range,
        this.infoUnitText(this.firstTargetUnit(humidityTargets)));
      this.pm25RangeText = this.formatInfoRange(pm25Result.range,
        this.infoUnitText(this.firstTargetUnit(pm25Targets)));
      this.temperatureMoreText = this.formatInfoMore(temperatureResult.range,
        temperatureTargets.length, this.firstTargetUnit(temperatureTargets));
      this.humidityMoreText = this.formatInfoMore(humidityResult.range,
        humidityTargets.length, this.firstTargetUnit(humidityTargets));
      this.pm25MoreText = this.formatInfoMore(pm25Result.range,
        pm25Targets.length, this.firstTargetUnit(pm25Targets));
      this.temperatureDevices = temperatureResult.entries;
      this.humidityDevices = humidityResult.entries;
      this.pm25Devices = pm25Result.entries;
      const onEntries = await this.fetchSwitchOnDevices(controller, switchTargets);
      this.onDevices = onEntries;
      this.onDeviceCount = onEntries.length;
      FeedbackLogService.recordOperation('PAGE',
        `信息页内容: 温度=${this.temperatureRangeText} 湿度=${this.humidityRangeText} PM2.5=${this.pm25RangeText} 在线设备=${this.onDeviceCount} 设备总数=${familyDevices.length}`);
    } catch (err) {
      if (!silent) {
        this.infoError = err instanceof Error ? err.message : '加载信息页数据失败';
      }
      Logger.error('load info data failed, %{public}s',
        err instanceof Error ? err.message : String(err));
      if (err instanceof XiaomiAuthError) {
        await xiaomiDataService.clearSession();
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' });
      }
    } finally {
      this.infoFetching = false;
      if (!silent) {
        this.infoLoading = false;
      }
    }
  }

  private deviceListSummary(devices: XiaomiDevice[]): string {
    const parts: string[] = [];
    for (let i = 0; i < devices.length; i++) {
      const device = devices[i];
      parts.push(`${device.name}(${device.did},${device.online ? '在线' : '离线'},${device.roomName})`);
    }
    return parts.join(' | ');
  }

  private findInfoProperty(
    spec: MIoTSpecInstance,
    keywords: string[],
    excludes: string[],
    excludeUnits: string[]
  ): InfoSpecProperty | null {
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      for (let j = 0; j < service.properties.length; j++) {
        const prop = service.properties[j];
        if (!prop.readable) {
          continue;
        }
        const format = prop.format.toLowerCase();
        if (format !== 'float' && format !== 'int') {
          continue;
        }
        const unitKey = prop.unit.trim().toLowerCase();
        let unitExcluded = false;
        for (let u = 0; u < excludeUnits.length; u++) {
          if (unitKey === excludeUnits[u]) {
            unitExcluded = true;
            break;
          }
        }
        if (unitExcluded) {
          continue;
        }
        const text = `${prop.name} ${prop.description} ${prop.type} ${prop.unit}`.toLowerCase()
          .split('_').join('.');
        let matched = false;
        for (let k = 0; k < keywords.length; k++) {
          if (text.includes(keywords[k])) {
            matched = true;
            break;
          }
        }
        if (!matched) {
          continue;
        }
        let excluded = false;
        for (let m = 0; m < excludes.length; m++) {
          if (text.includes(excludes[m])) {
            excluded = true;
            break;
          }
        }
        if (excluded) {
          continue;
        }
        return {
          siid: service.iid,
          piid: prop.iid,
          unit: prop.unit
        };
      }
    }
    return null;
  }

  private findSwitchProperty(spec: MIoTSpecInstance): InfoSpecProperty | null {
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      for (let j = 0; j < service.properties.length; j++) {
        const prop = service.properties[j];
        if (!prop.readable) {
          continue;
        }
        if (prop.format.toLowerCase() !== 'bool') {
          continue;
        }
        const text = `${prop.name} ${prop.description} ${prop.type}`.toLowerCase();
        const isPowerSwitch = text.includes('switch') || text.includes('power') ||
          prop.name === 'on';
        if (!isPowerSwitch) {
          continue;
        }
        if (text.includes('lock') || text.includes('physical control')) {
          continue;
        }
        return {
          siid: service.iid,
          piid: prop.iid,
          unit: ''
        };
      }
    }
    return null;
  }

  private async fetchSwitchOnDevices(
    controller: DeviceController,
    targets: InfoPropertyTarget[]
  ): Promise<InfoDeviceEntry[]> {
    if (targets.length === 0) {
      return [];
    }
    const params: DevicePropertyParam[] = [];
    for (let i = 0; i < targets.length; i++) {
      const param: DevicePropertyParam = {
        did: targets[i].did,
        siid: targets[i].siid,
        piid: targets[i].piid
      };
      params.push(param);
    }
    let results: DevicePropertyResult[] = [];
    try {
      results = await controller.getProperties(targets[0].did, params);
    } catch (err) {
      Logger.warn('fetch switch properties failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
    const valueMap = new Map<string, Object | undefined>();
    for (let i = 0; i < results.length; i++) {
      const key = `${String(results[i].did)}.${results[i].siid}.${results[i].piid}`;
      valueMap.set(key, results[i].value);
    }
    const entries: InfoDeviceEntry[] = [];
    for (let i = 0; i < targets.length; i++) {
      const target = targets[i];
      const key = `${target.did}.${target.siid}.${target.piid}`;
      if (!this.isOnValue(valueMap.get(key))) {
        continue;
      }
      const entry: InfoDeviceEntry = {
        did: target.did,
        name: target.name,
        roomName: target.roomName,
        valueText: '开启'
      };
      entries.push(entry);
    }
    return entries;
  }

  private isOnValue(value: Object | undefined): boolean {
    return value === true || value === 1 || value === 'true' || value === '1';
  }

  private async fetchInfoMetric(
    controller: DeviceController,
    targets: InfoPropertyTarget[]
  ): Promise<InfoMetricResult> {
    if (targets.length === 0) {
      return {
        range: { min: 0, max: 0, count: 0, average: 0 },
        entries: []
      };
    }
    const params: DevicePropertyParam[] = [];
    for (let i = 0; i < targets.length; i++) {
      const param: DevicePropertyParam = {
        did: targets[i].did,
        siid: targets[i].siid,
        piid: targets[i].piid
      };
      params.push(param);
    }
    let results: DevicePropertyResult[] = [];
    try {
      results = await controller.getProperties(targets[0].did, params);
    } catch (err) {
      Logger.warn('fetch info properties failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
    const valueMap = new Map<string, Object | undefined>();
    for (let i = 0; i < results.length; i++) {
      const key = `${String(results[i].did)}.${results[i].siid}.${results[i].piid}`;
      valueMap.set(key, results[i].value);
    }
    const entries: InfoDeviceEntry[] = [];
    let min = 0;
    let max = 0;
    let count = 0;
    let sum = 0;
    for (let i = 0; i < targets.length; i++) {
      const target = targets[i];
      const key = `${target.did}.${target.siid}.${target.piid}`;
      const value = Number(valueMap.get(key));
      if (Number.isNaN(value)) {
        continue;
      }
      const displayValue = this.displayTemperature(value, target.unit);
      const entry: InfoDeviceEntry = {
        did: target.did,
        name: target.name,
        roomName: target.roomName,
        valueText: `${this.formatInfoValue(displayValue)}${this.infoUnitText(this.displayTemperatureUnit(target.unit))}`
      };
      entries.push(entry);
      if (count === 0) {
        min = value;
        max = value;
      } else {
        min = Math.min(min, value);
        max = Math.max(max, value);
      }
      count++;
      sum += value;
    }
    let range: InfoMetricRange = { min: 0, max: 0, count: 0, average: 0 };
    if (count > 0) {
      range = { min: min, max: max, count: count, average: sum / count };
    }
    return {
      range: range,
      entries: entries
    };
  }

  private formatInfoRange(range: InfoMetricRange, unit: string): string {
    if (range.count === 0) {
      return '--';
    }
    const minText = this.formatInfoValue(this.displayTemperature(range.min, unit));
    const maxText = this.formatInfoValue(this.displayTemperature(range.max, unit));
    const displayUnit = this.infoUnitText(this.displayTemperatureUnit(unit));
    if (displayUnit.length === 0) {
      return `${minText} - ${maxText}`;
    }
    return `${minText}${displayUnit} - ${maxText}${displayUnit}`;
  }

  private formatInfoMore(range: InfoMetricRange, deviceCount: number, unit: string): string {
    if (deviceCount === 0 || range.count === 0) {
      return '';
    }
    const average = this.displayTemperature(range.average, unit);
    const displayUnit = this.infoUnitText(this.displayTemperatureUnit(unit));
    return `共 ${deviceCount} 台设备 · 平均 ${average.toFixed(1)}${displayUnit}`;
  }

  private formatInfoValue(value: number): string {
    return Number.isInteger(value) ? String(value) : value.toFixed(1);
  }

  private firstTargetUnit(targets: InfoPropertyTarget[]): string {
    return targets.length > 0 ? targets[0].unit : '';
  }

  private displayTemperature(value: number, unit: string): number {
    if (!this.temperatureFahrenheit) {
      return value;
    }
    return isCelsiusUnit(unit) ? celsiusToFahrenheit(value) : value;
  }

  private displayTemperatureUnit(unit: string): string {
    if (!this.temperatureFahrenheit) {
      return unit;
    }
    return isCelsiusUnit(unit) ? 'fahrenheit' : unit;
  }

  private infoUnitText(unit: string): string {
    const key = unit.trim().toLowerCase();
    if (key === 'celsius') {
      return '°C';
    }
    if (key === 'fahrenheit') {
      return '°F';
    }
    if (key === 'percentage' || key === 'percent') {
      return '%';
    }
    if (key === 'ug/m3' || key === 'ug/m³') {
      return 'μg/m³';
    }
    return unit;
  }

  private openDeviceFromSheet(did: string): void {
    if (this.pendingDeviceDid.length > 0) {
      return;
    }
    this.pendingDeviceDid = did;
    this.closeInfoSheets();
    setTimeout(() => {
      this.pendingDeviceDid = '';
      this.pageInfos.pushPathByName('deviceDetail', new DeviceDetailRouteParam(did));
    }, 300);
  }

  private closeInfoSheets(): void {
    this.showTemperatureSheet = false;
    this.showHumiditySheet = false;
    this.showPm25Sheet = false;
    this.showOnSheet = false;
  }

  private isDeviceExcluded(did: string): boolean {
    return this.infoExcludedDevices.indexOf(did) >= 0;
  }

  private setDeviceExcluded(did: string, excluded: boolean): void {
    const next: string[] = this.infoExcludedDevices.slice();
    const idx = next.indexOf(did);
    if (excluded && idx < 0) {
      next.push(did);
    }
    if (!excluded && idx >= 0) {
      next.splice(idx, 1);
    }
    this.infoExcludedDevices = next;
    AppSettingsStore.setStringArray('infoExcludedDevices', next);
  }

  private selectAllHomesFromSheet(): void {
    this.selectedHomeId = ALL_HOMES_ID;
    this.selectedHomeName = ALL_HOMES_NAME;
    AppSettingsStore.setString('selectedHomeId', ALL_HOMES_ID);
    AppSettingsStore.setString('selectedHomeName', ALL_HOMES_NAME);
    this.homeSelectionVersion = this.homeSelectionVersion + 1;
    this.showFamilySheet = false;
  }

  private selectHomeFromSheet(home: XiaomiHome): void {
    this.selectedHomeId = home.homeId;
    this.selectedHomeName = home.name;
    AppSettingsStore.setString('selectedHomeId', home.homeId);
    AppSettingsStore.setString('selectedHomeName', home.name);
    this.homeSelectionVersion = this.homeSelectionVersion + 1;
    this.showFamilySheet = false;
  }

  private refreshInfoOnEnter(): void {
    const now = Date.now();
    if (now - this.lastInfoRefreshAt < 1000) {
      return;
    }
    this.lastInfoRefreshAt = now;
    this.loadInfoData(true);
  }

  private startInfoRefreshTimer(): void {
    this.stopInfoRefreshTimer();
    const seconds = this.infoRefreshIntervalSeconds();
    this.infoRefreshTimer = setInterval(() => {
      if (this.activeTab === 1) {
        this.refreshInfoOnEnter();
      }
    }, seconds * 1000);
  }

  private stopInfoRefreshTimer(): void {
    if (this.infoRefreshTimer >= 0) {
      clearInterval(this.infoRefreshTimer);
      this.infoRefreshTimer = -1;
    }
  }

  private infoRefreshIntervalSeconds(): number {
    const value = Number(this.infoRefreshInterval);
    return Number.isNaN(value) || value <= 0 ? 30 : value;
  }

  private topOffset(): number {
    return (this.isWearable ? 64 : CONTENT_TOP_OFFSET) + this.statusBarHeight;
  }

  private contentPadding(): number {
    return this.isWearable ? 12 : 20;
  }

  private cardPadding(): number {
    return this.isWearable ? 10 : HwSpace.md;
  }

  onInfoRefreshIntervalChanged(): void {
    if (this.activeTab === 1) {
      this.startInfoRefreshTimer();
    }
  }

  onTemperatureUnitChanged(): void {
    if (this.activeTab === 1) {
      this.loadInfoData(true);
    }
  }

  deviceLocation(device: XiaomiDevice): string {
    if (this.selectedHomeId === ALL_HOMES_ID) {
      const homeTitle = this.homeTitleForDevice(device);
      const localTitle = this.localRoomTitleForDevice(device);
      if (localTitle.length > 0) {
        return `${homeTitle} · ${localTitle}`;
      }
      if (device.roomName.length > 0) {
        return `${homeTitle} · ${device.roomName}`;
      }
      return homeTitle;
    }
    const localTitle = this.localRoomTitleForDevice(device);
    if (localTitle.length > 0) {
      return localTitle;
    }
    return device.roomName;
  }

  private homeTitleForDevice(device: XiaomiDevice): string {
    const homeName = device.homeName;
    if (homeName.length === 0) {
      return '我的家';
    }
    if (homeName.endsWith('家')) {
      return homeName;
    }
    return `${homeName}的家`;
  }

  private localRoomTitleForDevice(device: XiaomiDevice): string {
    for (let i = 0; i < this.localRooms.length; i++) {
      const room = this.localRooms[i];
      if (room.dids.indexOf(device.did) >= 0) {
        return `${room.floor}楼 ${room.name}`;
      }
    }
    return '';
  }

  private sortVisibleDevices(devices: XiaomiDevice[]): XiaomiDevice[] {
    const working = devices.slice();
    if (!this.sortDevicesByRoom) {
      working.sort((a: XiaomiDevice, b: XiaomiDevice): number => {
        const aOnline = a.online ? 1 : 0;
        const bOnline = b.online ? 1 : 0;
        return bOnline - aOnline;
      });
      return working;
    }
    const result: XiaomiDevice[] = [];
    const added = new Set<string>();
    for (let i = 0; i < this.localRooms.length; i++) {
      const room = this.localRooms[i];
      const roomDevices: XiaomiDevice[] = [];
      for (let j = 0; j < room.dids.length; j++) {
        const did = room.dids[j];
        if (added.has(did)) {
          continue;
        }
        const matched = this.findDeviceByDid(working, did);
        if (matched !== null) {
          roomDevices.push(matched);
          added.add(did);
        }
      }
      roomDevices.sort((a: XiaomiDevice, b: XiaomiDevice): number => {
        const aOnline = a.online ? 1 : 0;
        const bOnline = b.online ? 1 : 0;
        return bOnline - aOnline;
      });
      for (let k = 0; k < roomDevices.length; k++) {
        result.push(roomDevices[k]);
      }
    }
    const rest: XiaomiDevice[] = [];
    for (let i = 0; i < working.length; i++) {
      if (!added.has(working[i].did)) {
        rest.push(working[i]);
      }
    }
    rest.sort((a: XiaomiDevice, b: XiaomiDevice): number => {
      const aOnline = a.online ? 1 : 0;
      const bOnline = b.online ? 1 : 0;
      return bOnline - aOnline;
    });
    for (let k = 0; k < rest.length; k++) {
      result.push(rest[k]);
    }
    return result;
  }

  private findDeviceByDid(devices: XiaomiDevice[], did: string): XiaomiDevice | null {
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].did === did) {
        return devices[i];
      }
    }
    return null;
  }

  pageTitle(): string {
    if (this.activeTab === 0) {
      return this.selectedHomeName.length > 0 ? this.selectedHomeName : '我的家庭';
    }
    if (this.isWearable) {
      return '我的';
    }
    return this.activeTab === 1 ? '信息' : '我的';
  }

  onBreakpointChange(): void {
    const wideBp: boolean = this.widthBp === WidthBreakpoint.WIDTH_LG ||
      this.widthBp === WidthBreakpoint.WIDTH_XL;
    const wide: boolean = wideBp && this.pcLayoutEnabled;
    if (wide !== this.isWideScreen) {
      this.isWideScreen = wide;
      if (wide) {
        this.sideBarWidth = SIDE_BAR_WIDTH_DEFAULT;
      }
    }
  }

  private refreshCurrentTab(): void {
    if (this.isWearable && this.activeTab === 1) {
      this.loadData(true, true);
      this.loadAccount();
      return;
    }
    if (this.activeTab === 1) {
      this.loadInfoData(false);
    } else if (this.activeTab === 2) {
      this.loadData(true, true);
      this.loadAccount();
    } else {
      this.loadData(true);
    }
  }

  private tabLabel(index: number): string {
    if (index === 0) {
      return '首页';
    }
    if (index === 1) {
      return this.isWearable ? '我的' : '信息';
    }
    return '我的';
  }

  @Builder
  tabIcon(index: number) {
    if (index === 0) {
      SymbolGlyph(this.activeTab === 0 ? $r('sys.symbol.house_fill') : $r('sys.symbol.house'))
        .fontSize(24)
        .fontColor([this.activeTab === 0 ? HwColor.primary : HwColor.textSecondary])
    } else if (index === 1 && !this.isWearable) {
      SymbolGlyph(this.activeTab === 1 ? $r('sys.symbol.info_circle_fill') : $r('sys.symbol.info_circle'))
        .fontSize(24)
        .fontColor([this.activeTab === 1 ? HwColor.primary : HwColor.textSecondary])
    } else {
      SymbolGlyph((this.activeTab === 2 || (this.isWearable && this.activeTab === 1))
        ? $r('sys.symbol.person_fill') : $r('sys.symbol.person'))
        .fontSize(24)
        .fontColor([(this.activeTab === 2 || (this.isWearable && this.activeTab === 1))
          ? HwColor.primary : HwColor.textSecondary])
    }
  }

  @Builder
  tabItem(index: number) {
    Column({ space: 4 }) {
      this.tabIcon(index)
      Text(this.tabLabel(index))
        .fontSize(12)
        .fontColor(this.activeTab === index ? HwColor.primary : HwColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.isWideScreen ? 64 : 56)
    .justifyContent(FlexAlign.Center)
  }

  tabBarStyle(index: number): BottomTabBarStyle {
    if (index === 0) {
      const homeNormal = new SymbolGlyphModifier($r('sys.symbol.house'));
      homeNormal.fontColor([HwColor.textSecondary]);
      const homeSelected = new SymbolGlyphModifier($r('sys.symbol.house_fill'));
      homeSelected.fontColor([HwColor.primary]);
      return new BottomTabBarStyle({ normal: homeNormal, selected: homeSelected }, '首页');
    }
    if (index === 1 && !this.isWearable) {
      const infoNormal = new SymbolGlyphModifier($r('sys.symbol.info_circle'));
      infoNormal.fontColor([HwColor.textSecondary]);
      const infoSelected = new SymbolGlyphModifier($r('sys.symbol.info_circle_fill'));
      infoSelected.fontColor([HwColor.primary]);
      return new BottomTabBarStyle({ normal: infoNormal, selected: infoSelected }, '信息');
    }
    const mineNormal = new SymbolGlyphModifier($r('sys.symbol.person'));
    mineNormal.fontColor([HwColor.textSecondary]);
    const mineSelected = new SymbolGlyphModifier($r('sys.symbol.person_fill'));
    mineSelected.fontColor([HwColor.primary]);
    return new BottomTabBarStyle({ normal: mineNormal, selected: mineSelected }, '我的');
  }

  @Builder
  tabHeader() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.pageTitle())
          .fontFamily(this.appFontFamily(this.pageTitle()))
          .fontWeight(this.appFontWeight())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.activeTab === 1 && this.selectedHomeName.length > 0) {
          Text(this.selectedHomeName)
            .fontFamily(this.appFontFamily(this.selectedHomeName))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.activeTab === 0) {
        IconCircleButton({
          symbol: $r('sys.symbol.house'),
          buttonSize: 36,
          iconSize: 18,
          onAction: (): void => {
            FeedbackLogService.recordOperation('UI', '打开选择家庭');
            this.showFamilySheet = true;
          }
        })
        IconCircleButton({
          symbol: $r('sys.symbol.arrow_counterclockwise'),
          buttonSize: 36,
          iconSize: 18,
          buttonEnabled: !this.loading,
          onAction: (): void => {
            FeedbackLogService.recordOperation('UI', '刷新首页数据');
            this.loadData(true);
          }
        })
      } else if (this.activeTab === 1) {
        IconCircleButton({
          symbol: $r('sys.symbol.line_3_horizontal_circle'),
          buttonSize: 36,
          iconSize: 18,
          onAction: (): void => {
            FeedbackLogService.recordOperation('UI', '打开排除设备');
            this.showExcludeSheet = true;
          }
        })
        IconCircleButton({
          symbol: $r('sys.symbol.arrow_counterclockwise'),
          buttonSize: 36,
          iconSize: 18,
          buttonEnabled: !this.infoLoading,
          onAction: (): void => {
            FeedbackLogService.recordOperation('UI', '刷新信息页数据');
            this.loadInfoData(false);
          }
        })
      }
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ left: 20, right: 20, top: this.statusBarHeight })
  }

  @Builder
  deviceCard(device: XiaomiDevice) {
    Column({ space: 6 }) {
      Row({ space: 12 }) {
        Column()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(device.online ? HwColor.online : '#B8BEC7')
        Text(device.name)
          .fontFamily(this.appFontFamily(device.name))
          .fontWeight(this.appFontWeight())
          .fontSize(this.isWearable ? 13 : 15)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(device.online ? '在线' : '离线')
          .fontFamily(this.appFontFamily(device.online ? '在线' : '离线'))
          .fontWeight(this.appFontWeight())
          .fontSize(this.isWearable ? 11 : 12)
          .fontColor(device.online ? HwColor.online : HwColor.textSecondary)
      }
      .width('100%')

      if (this.deviceLocation(device).length > 0) {
        Text(this.deviceLocation(device))
          .fontFamily(this.appFontFamily(this.deviceLocation(device)))
          .fontWeight(this.appFontWeight())
          .fontSize(this.isWearable ? 11 : 12)
          .fontColor(HwColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 22 })
          .width('100%')
      }
    }
    .width('100%')
    .padding(this.cardPadding())
    .borderRadius(this.isWearable ? 16 : HwRadius.card)
    .backgroundColor(HwGlassCardColor.surface)
    .attributeModifier(this.immersiveLightEnabled && isApi26OrAbove() ? immersiveMaterialModifier : legacyMaterialModifier)
    .border({ width: 1, color: HwGlassCardColor.border })
    .clip(true)
    .hoverEffect(HoverEffect.Highlight)
    .focusable(true)
    .onClick(() => {
      FeedbackLogService.recordOperation('UI', `点击设备 ${device.name} (${device.did})`);
      if (this.isRouterDevice(device)) {
        this.showRouterWarningDialog(device.did);
      } else {
        this.pageInfos.pushPathByName('deviceDetail', new DeviceDetailRouteParam(device.did));
      }
    })
  }

  private isRouterDevice(device: XiaomiDevice): boolean {
    return device.model.includes('router') || device.name.includes('路由');
  }

  private showRouterWarningDialog(did: string): void {
    this.getUIContext().showAlertDialog({
      title: '警告',
      message: '本软件暂不支持控制路由器，但您仍可手动修改这些参数',
      primaryButton: {
        value: '取消',
        fontColor: HwColor.primary,
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '我已知悉风险并继续',
        fontColor: HwColor.danger,
        action: (): void => {
          this.pageInfos.pushPathByName('deviceDetail', new DeviceDetailRouteParam(did));
        }
      }
    });
  }

  @Builder
  homeTabContent() {
    Column({ space: 12 }) {
      Blank().height(this.isWideScreen ? 12 : this.topOffset())

      if (this.loading) {
        LoadingProgress()
          .width(64)
          .height(64)
      }
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontFamily(this.appFontFamily(this.errorMessage))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.danger)
      }
      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .fontFamily(this.appFontFamily(this.statusMessage))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.primary)
      }

      if (this.dualColumnMode) {
        Flex({
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.SpaceBetween,
          alignItems: ItemAlign.Start
        }) {
          ForEach(this.devices, (device: XiaomiDevice) => {
            Column() {
              this.deviceCard(device)
            }
            .width('48%')
            .margin({ bottom: 10 })
          }, (device: XiaomiDevice) => device.did)
        }
        .width('100%')
      } else {
        Column({ space: 10 }) {
          ForEach(this.devices, (device: XiaomiDevice) => {
            this.deviceCard(device)
          }, (device: XiaomiDevice) => device.did)
        }
        .width('100%')
      }

      Blank()
        .height(this.isWideScreen ? 24 : BOTTOM_BAR_HEIGHT + BOTTOM_BAR_MARGIN + this.navigationBarHeight + 24)
    }
    .width('100%')
    .constraintSize({
      maxWidth: this.isWideScreen ? MAX_CONTENT_WIDTH : '100%'
    })
    .padding({ left: this.contentPadding(), right: this.contentPadding() })
  }

  @Builder
  mineTabContent() {
    Column({ space: 14 }) {
      Blank().height(this.isWideScreen ? 12 : this.topOffset())

      Column({ space: 12 }) {
        Row({ space: 12 }) {
          if (this.accountAvatarUrl.length > 0) {
            Image(this.accountAvatarUrl)
              .width(56)
              .height(56)
              .borderRadius(28)
              .objectFit(ImageFit.Cover)
          } else {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.person_fill'))
                .fontSize(28)
                .fontColor([HwColor.textSecondary])
            }
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor('#E8EAED')
          }
          Column({ space: 4 }) {
            Text(this.accountNickname || '已登录用户')
              .fontFamily(this.appFontFamily(this.accountNickname || '已登录用户'))
              .fontWeight(this.appFontWeight())
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(HwColor.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.accountUserId || '未获取到账号')
              .fontFamily(this.appFontFamily(this.accountUserId || '未获取到账号'))
              .fontWeight(this.appFontWeight())
              .fontSize(13)
              .fontColor(HwColor.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider()
          .color('#14000000')
          .margin({ top: HwSpace.md, bottom: HwSpace.md })

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.arrow_right_to_line'))
            .fontSize(18)
            .fontColor([HwColor.danger])
          Text('退出登录')
            .fontFamily(this.appFontFamily('退出登录'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.danger)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.showLogoutDialog();
        })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(HwSpace.lg)
      .borderRadius(HwRadius.card)
      .backgroundColor(HwGlassCardColor.surface)
      .attributeModifier(this.immersiveLightEnabled && isApi26OrAbove() ? immersiveMaterialModifier : legacyMaterialModifier)
      .border({ width: 1, color: HwGlassCardColor.border })
      .clip(true)

      Column() {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.house'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Text('房间')
            .fontFamily(this.appFontFamily('房间'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .padding(HwSpace.lg)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入房间页');
          this.getUIContext().getRouter().pushUrl({ url: 'pages/RoomsPage' });
        })

        Divider()
          .color('#14000000')
          .margin({ left: HwSpace.lg, right: HwSpace.lg })

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Text('设置')
            .fontFamily(this.appFontFamily('设置'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .padding(HwSpace.lg)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入设置页');
          this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' });
        })

        Divider()
          .color('#14000000')
          .margin({ left: HwSpace.lg, right: HwSpace.lg })

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.envelope'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Text('反馈')
            .fontFamily(this.appFontFamily('反馈'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .padding(HwSpace.lg)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入反馈页');
          this.getUIContext().getRouter().pushUrl({ url: 'pages/FeedbackPage' });
        })

        Divider()
          .color('#14000000')
          .margin({ left: HwSpace.lg, right: HwSpace.lg })

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Text('关于')
            .fontFamily(this.appFontFamily('关于'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .padding(HwSpace.lg)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入关于页');
          this.getUIContext().getRouter().pushUrl({ url: 'pages/AboutPage' });
        })
      }
      .width('100%')
      .borderRadius(HwRadius.card)
      .backgroundColor(HwGlassCardColor.surface)
      .attributeModifier(this.immersiveLightEnabled && isApi26OrAbove() ? immersiveMaterialModifier : legacyMaterialModifier)
      .border({ width: 1, color: HwGlassCardColor.border })
      .clip(true)

      Blank()
        .height(this.isWideScreen ? 24 : BOTTOM_BAR_HEIGHT + BOTTOM_BAR_MARGIN + this.navigationBarHeight + 24)
    }
    .width('100%')
    .constraintSize({
      maxWidth: this.isWideScreen ? MAX_CONTENT_WIDTH : '100%'
    })
    .padding({ left: this.contentPadding(), right: this.contentPadding() })
  }

  @Builder
  infoMetricCard($$: InfoMetricCardConfig) {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 6 }) {
        Text($$.title)
          .fontFamily(this.appFontFamily($$.title))
          .fontWeight(this.appFontWeight())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
        Text($$.rangeText)
          .fontFamily(this.appFontFamily($$.rangeText))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(HwColor.textSecondary)
        if (this.infoShowMoreContent && $$.moreText.length > 0) {
          Text($$.moreText)
            .fontFamily(this.appFontFamily($$.moreText))
            .fontWeight(this.appFontWeight())
            .fontSize(13)
            .fontColor(HwColor.textSecondary)
        }
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg })
    }
    .width('100%')
    .height(INFO_CARD_HEIGHT)
    .borderRadius(HwRadius.card)
    .backgroundColor(HwGlassCardColor.surface)
    .attributeModifier(this.immersiveLightEnabled && isApi26OrAbove() ? immersiveMaterialModifier : legacyMaterialModifier)
    .border({ width: 1, color: HwGlassCardColor.border })
    .clip(true)
  }

  @Builder
  infoDeviceRow(entry: InfoDeviceEntry) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(entry.name)
          .fontFamily(this.appFontFamily(entry.name))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.roomName.length > 0) {
          Text(entry.roomName)
            .fontFamily(this.appFontFamily(entry.roomName))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(entry.valueText)
        .fontFamily(this.appFontFamily(entry.valueText))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontColor(HwColor.primary)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([HwColor.textSecondary])
    }
    .width('100%')
    .padding(HwSpace.md)
    .borderRadius(HwRadius.control)
    .backgroundColor(HwColor.surface)
    .onClick(() => {
      this.openDeviceFromSheet(entry.did);
    })
  }

  @Builder
  temperatureDeviceSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(`提供温度的设备（${this.temperatureDevices.length}）`)
          .fontFamily(this.appFontFamily(`提供温度的设备（${this.temperatureDevices.length}）`))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 36,
          iconSize: 18,
          onAction: () => {
            this.showTemperatureSheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      Column({ space: 10 }) {
        if (this.temperatureDevices.length === 0) {
          Text('暂无提供温度的设备')
            .fontFamily(this.appFontFamily('暂无提供温度的设备'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
            .padding({ top: 12, bottom: 12 })
        }
        ForEach(this.temperatureDevices, (entry: InfoDeviceEntry) => {
          this.infoDeviceRow(entry)
        }, (entry: InfoDeviceEntry) => entry.did)
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
      .margin({ top: 12 })
    }
    .width('100%')
  }

  @Builder
  humidityDeviceSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(`提供湿度的设备（${this.humidityDevices.length}）`)
          .fontFamily(this.appFontFamily(`提供湿度的设备（${this.humidityDevices.length}）`))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 36,
          iconSize: 18,
          onAction: () => {
            this.showHumiditySheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      Column({ space: 10 }) {
        if (this.humidityDevices.length === 0) {
          Text('暂无提供湿度的设备')
            .fontFamily(this.appFontFamily('暂无提供湿度的设备'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
            .padding({ top: 12, bottom: 12 })
        }
        ForEach(this.humidityDevices, (entry: InfoDeviceEntry) => {
          this.infoDeviceRow(entry)
        }, (entry: InfoDeviceEntry) => entry.did)
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
      .margin({ top: 12 })
    }
    .width('100%')
  }

  @Builder
  pm25DeviceSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(`提供PM2.5的设备（${this.pm25Devices.length}）`)
          .fontFamily(this.appFontFamily(`提供PM2.5的设备（${this.pm25Devices.length}）`))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 36,
          iconSize: 18,
          onAction: () => {
            this.showPm25Sheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      Column({ space: 10 }) {
        if (this.pm25Devices.length === 0) {
          Text('暂无提供PM2.5的设备')
            .fontFamily(this.appFontFamily('暂无提供PM2.5的设备'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
            .padding({ top: 12, bottom: 12 })
        }
        ForEach(this.pm25Devices, (entry: InfoDeviceEntry) => {
          this.infoDeviceRow(entry)
        }, (entry: InfoDeviceEntry) => entry.did)
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
      .margin({ top: 12 })
    }
    .width('100%')
  }

  @Builder
  onDeviceSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(`开启中的设备（${this.onDevices.length}）`)
          .fontFamily(this.appFontFamily(`开启中的设备（${this.onDevices.length}）`))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 36,
          iconSize: 18,
          onAction: () => {
            this.showOnSheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      Column({ space: 10 }) {
        if (this.onDevices.length === 0) {
          Text('当前没有开启中的设备')
            .fontFamily(this.appFontFamily('当前没有开启中的设备'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
            .padding({ top: 12, bottom: 12 })
        }
        ForEach(this.onDevices, (entry: InfoDeviceEntry) => {
          this.infoDeviceRow(entry)
        }, (entry: InfoDeviceEntry) => entry.did)
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
      .margin({ top: 12 })
    }
    .width('100%')
  }

  @Builder
  excludeDeviceRow(device: XiaomiDevice) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(device.name)
          .fontFamily(this.appFontFamily(device.name))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (device.roomName.length > 0) {
          Text(device.roomName)
            .fontFamily(this.appFontFamily(device.roomName))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Checkbox()
        .select(this.isDeviceExcluded(device.did))
        .selectedColor(HwColor.primary)
        .onChange((checked: boolean) => {
          this.setDeviceExcluded(device.did, checked);
        })
    }
    .width('100%')
    .padding(HwSpace.md)
    .borderRadius(HwRadius.control)
    .backgroundColor(HwColor.surface)
    .onClick(() => {
      this.setDeviceExcluded(device.did, !this.isDeviceExcluded(device.did));
    })
  }

  @Builder
  excludeDeviceSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text('信息页排除设备')
          .fontFamily(this.appFontFamily('信息页排除设备'))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 36,
          iconSize: 18,
          onAction: () => {
            this.showExcludeSheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      Text('勾选后该设备的数据不再计入信息页')
        .fontFamily(this.appFontFamily('勾选后该设备的数据不再计入信息页'))
        .fontWeight(this.appFontWeight())
        .fontSize(12)
        .fontColor(HwColor.textSecondary)
        .width('100%')
        .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 8 })

      if (this.devices.length === 0) {
        Text('暂无设备')
          .fontFamily(this.appFontFamily('暂无设备'))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.textSecondary)
          .padding({ top: 24, bottom: 24 })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.devices, (device: XiaomiDevice) => {
              this.excludeDeviceRow(device)
            }, (device: XiaomiDevice) => device.did)
          }
          .width('100%')
          .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
          .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  familyHomeRow(home: XiaomiHome, selected: boolean) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(home.name)
          .fontFamily(this.appFontFamily(home.name))
          .fontWeight(this.appFontWeight())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
        Text(`${home.roomList.length} 个房间`)
          .fontFamily(this.appFontFamily(`${home.roomList.length} 个房间`))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(HwColor.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      if (selected) {
        Text('当前')
          .fontFamily(this.appFontFamily('当前'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.primary)
      }
    }
    .width('100%')
    .padding(HwSpace.lg)
    .borderRadius(HwRadius.card)
    .backgroundColor(HwColor.surface)
    .border({
      width: selected ? 1 : 0,
      color: selected ? HwColor.primary : '#00000000'
    })
    .onClick(() => {
      this.selectHomeFromSheet(home);
    })
  }

  @Builder
  familySelectSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text('选择家庭')
          .fontFamily(this.appFontFamily('选择家庭'))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 36,
          iconSize: 18,
          onAction: () => {
            this.showFamilySheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      if (this.homes.length === 0) {
        Text('暂无家庭，请先下拉刷新')
          .fontFamily(this.appFontFamily('暂无家庭，请先下拉刷新'))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.textSecondary)
          .padding({ top: 24, bottom: 24 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text(ALL_HOMES_NAME)
                  .fontFamily(this.appFontFamily(ALL_HOMES_NAME))
                  .fontWeight(this.appFontWeight())
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(HwColor.textPrimary)
                Text('显示账号下所有家庭的所有设备')
                  .fontFamily(this.appFontFamily('显示账号下所有家庭的所有设备'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(13)
                  .fontColor(HwColor.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              Blank()
              if (this.selectedHomeId === ALL_HOMES_ID) {
                Text('当前')
                  .fontFamily(this.appFontFamily('当前'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(12)
                  .fontColor(HwColor.primary)
              }
            }
            .width('100%')
            .padding(HwSpace.lg)
            .borderRadius(HwRadius.card)
            .backgroundColor(HwColor.surface)
            .border({
              width: this.selectedHomeId === ALL_HOMES_ID ? 1 : 0,
              color: this.selectedHomeId === ALL_HOMES_ID ? HwColor.primary : '#00000000'
            })
            .onClick(() => {
              this.selectAllHomesFromSheet();
            })

            ForEach(this.homes, (home: XiaomiHome) => {
              this.familyHomeRow(home, this.selectedHomeId === home.homeId)
            }, (home: XiaomiHome) => home.homeId)
          }
          .width('100%')
          .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
          .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  infoTabContent() {
    Column({ space: 14 }) {
      Blank().height(this.isWideScreen ? 12 : this.topOffset())

      if (this.infoLoading) {
        LoadingProgress()
          .width(64)
          .height(64)
      }
      if (this.infoError.length > 0) {
        Text(this.infoError)
          .fontFamily(this.appFontFamily(this.infoError))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.danger)
      }
      if (!this.infoLoading && this.infoError.length === 0 && this.infoDeviceCount === 0) {
        Text('当前家庭暂无可用设备数据')
          .fontFamily(this.appFontFamily('当前家庭暂无可用设备数据'))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.textSecondary)
      }

      Column() {
        this.infoMetricCard({
          title: '温度',
          rangeText: this.temperatureRangeText,
          moreText: this.temperatureMoreText
        })
      }
      .width('100%')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.showTemperatureSheet = true;
      })
      .bindSheet($$this.showTemperatureSheet, this.temperatureDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: sheetSystemMaterial(),
        blurStyle: sheetBlurStyle(),
      })

      Column() {
        this.infoMetricCard({
          title: '湿度',
          rangeText: this.humidityRangeText,
          moreText: this.humidityMoreText
        })
      }
      .width('100%')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.showHumiditySheet = true;
      })
      .bindSheet($$this.showHumiditySheet, this.humidityDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: sheetSystemMaterial(),
        blurStyle: sheetBlurStyle(),
      })

      Column() {
        this.infoMetricCard({
          title: 'PM2.5',
          rangeText: this.pm25RangeText,
          moreText: this.pm25MoreText
        })
      }
      .width('100%')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.showPm25Sheet = true;
      })
      .bindSheet($$this.showPm25Sheet, this.pm25DeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: sheetSystemMaterial(),
        blurStyle: sheetBlurStyle(),
      })

      Column() {
        this.infoMetricCard({
          title: '开启中',
          rangeText: `${this.onDeviceCount} 台`,
          moreText: ''
        })
      }
      .width('100%')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.showOnSheet = true;
      })
      .bindSheet($$this.showOnSheet, this.onDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: sheetSystemMaterial(),
        blurStyle: sheetBlurStyle(),
      })

      Blank()
        .height(this.isWideScreen ? 24 : BOTTOM_BAR_HEIGHT + BOTTOM_BAR_MARGIN + this.navigationBarHeight + 24)
    }
    .width('100%')
    .constraintSize({
      maxWidth: this.isWideScreen ? MAX_CONTENT_WIDTH : '100%'
    })
    .padding({ left: 20, right: 20 })
  }

  @Builder
  homePane() {
    Column() {
      if (this.isWideScreen) {
        this.tabHeader()
      }
      Scroll(this.homeScroller) {
        this.homeTabContent()
      }
      .width('100%')
      .layoutWeight(1)
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.isWearable ? 1 : 0)
  }

  @Builder
  infoPane() {
    Column() {
      if (this.isWideScreen) {
        this.tabHeader()
      }
      Scroll(this.infoScroller) {
        this.infoTabContent()
      }
      .width('100%')
      .layoutWeight(1)
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.isWearable ? 1 : 0)
  }

  @Builder
  minePane() {
    Column() {
      if (this.isWideScreen) {
        this.tabHeader()
      }
      Scroll(this.mineScroller) {
        this.mineTabContent()
      }
      .width('100%')
      .layoutWeight(1)
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.isWearable ? 1 : 0)
  }

  @Builder
  wearableTabButton(index: number) {
    Column({ space: 3 }) {
      this.tabIcon(index)
      Text(this.tabLabel(index))
        .fontSize(11)
        .fontColor(this.activeTab === index ? HwColor.primary : HwColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTabSelected(index);
    })
  }

  @Builder
  wearableContent() {
    Column() {
      if (this.activeTab === 0) {
        this.homePane()
      } else {
        this.minePane()
      }
      Row() {
        this.wearableTabButton(0)
        this.wearableTabButton(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8, bottom: this.navigationBarHeight })
      .backgroundColor('#CCFFFFFF')
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.isWearable ? 1 : 0)
  }

  private onTabSelected(index: number): void {
    FeedbackLogService.recordOperation('UI', `切换标签 ${index}`);
    this.activeTab = index;
    if (this.isWearable) {
      if (index === 1) {
        this.loadData(true, true);
        this.loadAccount();
      }
      return;
    }
    if (index === 1) {
      this.refreshInfoOnEnter();
      this.startInfoRefreshTimer();
    } else {
      this.stopInfoRefreshTimer();
    }
    if (index === 2) {
      this.loadData(true, true);
      this.loadAccount();
    }
  }

  build() {
    HdsNavigation(this.pageInfos) {
      Stack({ alignContent: Alignment.TopStart }) {
        AppBackground()

        if (this.isWideScreen) {
          HdsTabs({
            controller: this.tabsController,
            index: this.activeTab
          }) {
            TabContent() { this.homePane() }.tabBar(this.tabItem(0))
            TabContent() { this.infoPane() }.tabBar(this.tabItem(1))
            TabContent() { this.minePane() }.tabBar(this.tabItem(2))
          }
          .width('100%')
          .height('100%')
          .barPosition(BarPosition.Start)
          .vertical(true)
          .barWidth(this.sideBarWidth)
          .barHeight('100%')
          .barOverlap(false)
          .scrollable(false)
          .animationDuration(this.homeSmoothSwitch ? 300 : 0)
          .onSelected((index: number) => {
            this.onTabSelected(index);
          })

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(1)
              .height('100%')
              .backgroundColor('#14000000')
          }
          .width(12)
          .height('100%')
          .position({ x: this.sideBarWidth - 6, y: 0 })
          .backgroundColor(this.dragHovered ? '#0A000000' : Color.Transparent)
          .onHover((isHover: boolean) => {
            this.dragHovered = isHover;
          })
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
              .onActionStart(() => {
                this.dragStartWidth = this.sideBarWidth;
              })
              .onActionUpdate((event: GestureEvent) => {
                const maxWidth: number = Math.min(this.screenWidthVp * 0.4, SIDE_BAR_WIDTH_MAX);
                this.sideBarWidth = Math.max(SIDE_BAR_WIDTH_MIN,
                  Math.min(this.dragStartWidth + event.offsetX, maxWidth));
              })
          )
        } else if (this.isWearable) {
          this.wearableContent()
        } else {
          HdsTabs({
            controller: this.tabsController,
            index: this.activeTab
          }) {
            TabContent() { this.homePane() }.tabBar(this.tabBarStyle(0))
            TabContent() { this.infoPane() }.tabBar(this.tabBarStyle(1))
            TabContent() { this.minePane() }.tabBar(this.tabBarStyle(2))
          }
          .width('100%')
          .height('100%')
          .barPosition(BarPosition.End)
          .barOverlap(true)
          .scrollable(false)
          .animationDuration(this.homeSmoothSwitch ? 300 : 0)
          .onSelected((index: number) => {
            this.onTabSelected(index);
          })
          .barFloatingStyle({
            barBottomMargin: BOTTOM_BAR_MARGIN + this.navigationBarHeight,
            barSideMargin: 16,
            gradientMask: {
              maskColor: '#00000000',
              maskHeight: 1
            },
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.ADAPTIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
            },
            lightColor: Color.White
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .clip(this.isWearable)
      .borderRadius(this.isWearable ? '50%' : 0)
      .bindSheet($$this.showFamilySheet, this.familySelectSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: sheetSystemMaterial(),
        blurStyle: sheetBlurStyle(),
      })
      .bindSheet($$this.showExcludeSheet, this.excludeDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        systemMaterial: sheetSystemMaterial(),
        blurStyle: sheetBlurStyle(),
        onDisappear: () => {
          this.refreshInfoOnEnter();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? HwColor.backgroundDark : HwColor.background)
    .mode(this.isLargeScreen && !this.pcLayoutEnabled && this.autoMultiColumn ? NavigationMode.Auto : NavigationMode.Stack)
    .titleBar({
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        }
      },
      content: {
        title: {
          mainTitle: this.pageTitle(),
          subTitle: this.activeTab === 1 && this.selectedHomeName.length > 0
            ? this.selectedHomeName
            : undefined
        },
        menu: this.activeTab === 0 ? {
          value: [
            {
              content: {
                label: '选择家庭',
                icon: $r('sys.symbol.house'),
                isEnabled: true,
                action: () => {
                  FeedbackLogService.recordOperation('UI', '打开选择家庭');
                  this.showFamilySheet = true;
                }
              }
            },
            {
              content: {
                label: '刷新',
                icon: $r('sys.symbol.arrow_counterclockwise'),
                isEnabled: !this.loading,
                action: () => {
                  FeedbackLogService.recordOperation('UI', '刷新首页数据');
                  this.loadData(true);
                }
              }
            }
          ]
        } : this.activeTab === 1 ? {
          value: [
            {
              content: {
                label: '排除设备',
                icon: $r('sys.symbol.line_3_horizontal_circle'),
                isEnabled: true,
                action: () => {
                  FeedbackLogService.recordOperation('UI', '打开排除设备');
                  this.showExcludeSheet = true;
                }
              }
            },
            {
              content: {
                label: '刷新',
                icon: $r('sys.symbol.arrow_counterclockwise'),
                isEnabled: !this.infoLoading,
                action: () => {
                  FeedbackLogService.recordOperation('UI', '刷新信息页数据');
                  this.loadInfoData(false);
                }
              }
            }
          ]
        } : undefined
      }
    })
    .titleMode(HdsNavigationTitleMode.FREE)
    .hideTitleBar(this.isWideScreen)
    .hideBackButton(true)
    .hideToolBar(true, true)
    .bindToScrollable([this.homeScroller, this.mineScroller, this.infoScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .keyboardShortcut('R', [ModifierKey.CTRL], () => {
      FeedbackLogService.recordOperation('KEYBOARD', 'Ctrl+R 刷新当前页');
      this.refreshCurrentTab();
    })
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      if (this.pageInfos.size() > 0) {
        this.pageInfos.pop();
      }
    })
  }
}
