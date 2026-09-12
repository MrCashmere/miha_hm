/*
 * 鸿米家（miha）— 本地智能创建页。
 *
 * 用户可自建「智能」：设置名称，选择设备并调整动作（如打开灯、调亮度），
 * 保存后在本应用内一键执行（通过 miot spec 属性写入），不同步米家云端。
 *
 * Copyright (C) 2026 鸿米家（miha）项目开发者
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { reloadAppTheme, HwColor, HwRadius, HwSpace, withAlpha } from '../utils/DesignTokens';
import { MaterialCard, MaterialCardLayer, MaterialSheetPanel, AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppBackground } from '../components/AppBackground';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { XiaomiDevice, XiaomiHome, LocalScene, LocalSceneAction, ALL_HOMES_ID } from '../models/XiaomiHomeModels';
import { LocalSceneStore } from '../storage/LocalSceneStore';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';
import { DeviceController } from '../controllers/DeviceController';
import { DevicePropertyParam, DevicePropertyResult } from '../controllers/DeviceTransport';
import { DeviceRemovalStore } from '../storage/DeviceRemovalStore';
import { MIoTSpecInstance } from '../models/MIotSpecModels';
import { PropertyControlDescriptor, buildServiceControls, CapabilityControlType, resolveServiceDisplayNames, translateMiotText } from '../components/CapabilityRenderer';
import { PropertyControl } from '../components/PropertyControl';

interface PickerValueState {
  key: string;
  value: Object | undefined;
}

@Entry
@Component
struct SceneCreatePage {
  @StorageLink('fontMode') fontMode: string = 'system';
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('selectedHomeId') selectedHomeId: string = '';
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;

  /** 正在编辑的智能 id；为空表示新建 */
  private editingSceneId: string = '';
  @State sceneName: string = '';
  @State actions: LocalSceneAction[] = [];
  @State message: string = '';
  @State timerEnabled: boolean = false;
  @State timerSelected: Date = new Date();
  @State timerDays: boolean[] = [true, true, true, true, true, true, true];
  private timerDayLabels: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @State devices: XiaomiDevice[] = [];
  @State devicesLoading: boolean = false;
  private roomNames: Map<string, string> = new Map();
  private roomNamesByDid: Map<string, string> = new Map();
  @State showDeviceSheet: boolean = false;

  @State pickerDevice: XiaomiDevice | undefined = undefined;
  @State pickerControls: PropertyControlDescriptor[] = [];
  @State pickerValues: PickerValueState[] = [];
  @State pickerLoading: boolean = false;
  @State pickerError: string = '';
  @State pickerSaving: boolean = false;

  private controller: DeviceController | null = null;

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  /**
   * 开关的选中色。
   * 读 accentColor 建立依赖：直接写 HwColor.primary 在切换主题色后不会重新求值，
   * 开关会停留在旧色。
   */
  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  aboutToAppear(): void {
    this.readEditTarget();
    this.loadDevices();
  }

  /**
   * 从路由参数取要编辑的智能。
   *
   * 由智能页的「编辑」按钮带 `sceneId` 进来；没有该参数就是新建。
   * 回填时把定时开关、时刻、重复日一并还原，编辑完直接覆盖原条目而不是新增一条。
   */
  private readEditTarget(): void {
    try {
      const params = router.getParams() as Record<string, Object>;
      const sceneId = String(params['sceneId'] ?? '');
      if (sceneId.length === 0) {
        return;
      }
      const scenes = LocalSceneStore.load();
      for (let i = 0; i < scenes.length; i++) {
        if (scenes[i].sceneId !== sceneId) {
          continue;
        }
        const scene = scenes[i];
        this.editingSceneId = scene.sceneId;
        this.sceneName = scene.name;
        this.actions = scene.actions.slice();
        this.timerEnabled = scene.timerEnabled;
        const when = new Date();
        when.setHours(scene.timerHour, scene.timerMinute, 0, 0);
        this.timerSelected = when;
        const days: boolean[] = [];
        for (let d = 0; d < 7; d++) {
          days.push(scene.timerDays.length === 7 ? scene.timerDays.charAt(d) === '1' : true);
        }
        this.timerDays = days;
        FeedbackLogService.recordOperation('UI', `编辑本地智能 ${scene.name}`);
        return;
      }
    } catch (err) {
      Logger.warn('read edit target failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
  }

  private appFontFamily(content: string): string {
    if (this.fontMode !== 'custom') {
      return '';
    }
    const family = this.hasCjk(content) ? this.fontFamilyZh : this.fontFamilyEn;
    return family === 'system' || family.length === 0 ? '' : family;
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

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }

  async loadDevices(): Promise<void> {
    if (this.devicesLoading) {
      return;
    }
    this.devicesLoading = true;
    try {
      // 云端房间表：roomId → 房间名 + did → 房间名（设备列表接口不带可靠房间信息）
      try {
        const context = getContext(this) as common.UIAbilityContext;
        const snapshot = await xiaomiDataService.getHomeSnapshot(context, false);
        const homes = JSON.parse(snapshot.homesJson) as XiaomiHome[];
        for (let h = 0; h < homes.length; h++) {
          const rooms = homes[h].roomList;
          for (let r = 0; r < rooms.length; r++) {
            this.roomNames.set(rooms[r].roomId, rooms[r].name);
            const dids = rooms[r].dids;
            for (let d = 0; d < dids.length; d++) {
              this.roomNamesByDid.set(dids[d], rooms[r].name);
            }
          }
        }
      } catch (err) {
        // 房间表获取失败时退回 device.roomName
      }
      const map = await xiaomiDataService.getDevices();
      const keys = Object.keys(map);
      const list: XiaomiDevice[] = [];
      for (let i = 0; i < keys.length; i++) {
        const device = map[keys[i]];
        if (device === undefined || !device.online) {
          continue;
        }
        // 仅显示当前家庭的在线设备；未选择或选择「全部家庭」时显示全部
        if (this.selectedHomeId.length > 0 && this.selectedHomeId !== ALL_HOMES_ID &&
          device.homeId !== this.selectedHomeId) {
          continue;
        }
        list.push(device);
      }
      list.sort((a: XiaomiDevice, b: XiaomiDevice) => {
        if (a.roomName === b.roomName) {
          return a.name.localeCompare(b.name);
        }
        return a.roomName.localeCompare(b.roomName);
      });
      this.devices = DeviceRemovalStore.filter(list);
    } catch (err) {
      this.message = err instanceof Error ? err.message : '加载设备失败';
    } finally {
      this.devicesLoading = false;
    }
  }

  buildControls(spec: MIoTSpecInstance): PropertyControlDescriptor[] {
    const result: PropertyControlDescriptor[] = [];
    const displayNames = resolveServiceDisplayNames(spec.services);
    for (let i = 0; i < spec.services.length; i++) {
      const controls = buildServiceControls(spec.services[i], displayNames);
      for (let j = 0; j < controls.length; j++) {
        if (controls[j].writable && controls[j].type !== CapabilityControlType.READOUT) {
          result.push(controls[j]);
        }
      }
    }
    return result;
  }

  async pickDevice(device: XiaomiDevice): Promise<void> {
    this.pickerDevice = device;
    this.pickerLoading = true;
    this.pickerError = '';
    this.pickerControls = [];
    this.pickerValues = [];
    try {
      const spec = await xiaomiDataService.getDeviceSpecForDevice(device);
      const controls = this.buildControls(spec);
      this.pickerControls = controls;
      this.controller = await xiaomiDataService.getDeviceController();
      await this.prefillPickerValues(device.did, controls);
    } catch (err) {
      this.pickerError = err instanceof Error ? err.message : '加载设备控制失败';
    } finally {
      this.pickerLoading = false;
    }
  }

  async prefillPickerValues(did: string, controls: PropertyControlDescriptor[]): Promise<void> {
    if (this.controller === null) {
      return;
    }
    const params: DevicePropertyParam[] = [];
    for (let i = 0; i < controls.length; i++) {
      if (controls[i].readable) {
        params.push({ did: did, siid: controls[i].siid, piid: controls[i].piid });
      }
    }
    let results: DevicePropertyResult[] = [];
    if (params.length > 0) {
      try {
        results = await this.controller.getProperties(did, params);
      } catch (err) {
        results = [];
      }
    }
    const valueMap = new Map<string, Object | undefined>();
    for (let i = 0; i < results.length; i++) {
      valueMap.set(`${results[i].siid}.${results[i].piid}`, results[i].value);
    }
    const states: PickerValueState[] = [];
    for (let i = 0; i < controls.length; i++) {
      states.push({
        key: `${controls[i].siid}.${controls[i].piid}`,
        value: valueMap.get(`${controls[i].siid}.${controls[i].piid}`)
      });
    }
    this.pickerValues = states;
  }

  pickerValueOf(control: PropertyControlDescriptor): Object | undefined {
    const key = `${control.siid}.${control.piid}`;
    for (let i = 0; i < this.pickerValues.length; i++) {
      if (this.pickerValues[i].key === key) {
        return this.pickerValues[i].value;
      }
    }
    return undefined;
  }

  updatePickerValue(control: PropertyControlDescriptor, value: Object): void {
    const key = `${control.siid}.${control.piid}`;
    const next: PickerValueState[] = [];
    let found = false;
    for (let i = 0; i < this.pickerValues.length; i++) {
      if (this.pickerValues[i].key === key) {
        next.push({ key: key, value: value });
        found = true;
      } else {
        next.push(this.pickerValues[i]);
      }
    }
    if (!found) {
      next.push({ key: key, value: value });
    }
    this.pickerValues = next;
  }

  /** 枚举反查中文选项文本；布尔转开关；非数值兜底走全局词典 */
  private actionValueText(control: PropertyControlDescriptor, value: Object): string {
    for (let i = 0; i < control.optionValues.length; i++) {
      if (String(control.optionValues[i]) === String(value)) {
        return control.options[i];
      }
    }
    const raw = String(value);
    if (raw === 'true') {
      return '开启';
    }
    if (raw === 'false') {
      return '关闭';
    }
    if (Number.isNaN(Number(raw))) {
      return translateMiotText(raw);
    }
    return raw;
  }

  confirmAddActions(): void {
    if (this.pickerDevice === undefined) {
      return;
    }
    const device = this.pickerDevice;
    const next: LocalSceneAction[] = this.actions.slice();
    let added = 0;
    for (let i = 0; i < this.pickerControls.length; i++) {
      const control = this.pickerControls[i];
      const value = this.pickerValueOf(control);
      if (value === undefined) {
        continue;
      }
      next.push({
        did: device.did,
        deviceName: device.name,
        siid: control.siid,
        piid: control.piid,
        label: control.label,
        value: value,
        valueText: this.actionValueText(control, value)
      });
      added++;
    }
    this.actions = next;
    this.pickerDevice = undefined;
    this.pickerControls = [];
    this.pickerValues = [];
    this.showDeviceSheet = false;
    if (added === 0) {
      this.message = '请调整至少一个动作后确认';
    }
  }

  removeAction(index: number): void {
    const next: LocalSceneAction[] = this.actions.slice();
    next.splice(index, 1);
    this.actions = next;
  }

  private timerDaysMask(): string {
    let mask = '';
    for (let i = 0; i < this.timerDays.length; i++) {
      mask += this.timerDays[i] ? '1' : '0';
    }
    return mask;
  }

  toggleTimerDay(index: number): void {
    const next: boolean[] = this.timerDays.slice();
    next[index] = !next[index];
    this.timerDays = next;
  }

  saveScene(): void {
    const name = this.sceneName.trim();
    if (name.length === 0) {
      this.message = '请输入智能名称';
      return;
    }
    if (this.actions.length === 0) {
      this.message = '请至少添加一个设备动作';
      return;
    }
    const mask = this.timerDaysMask();
    if (this.timerEnabled && !mask.includes('1')) {
      this.message = '定时执行需选择至少一个重复日';
      return;
    }
    // lastFireDay 沿用原条目：编辑不该让当天已经触发过的定时重新可触发
    let lastFireDay = '';
    if (this.editingSceneId.length > 0) {
      const existing = LocalSceneStore.load();
      for (let i = 0; i < existing.length; i++) {
        if (existing[i].sceneId === this.editingSceneId) {
          lastFireDay = existing[i].lastFireDay;
          break;
        }
      }
    }
    const scene: LocalScene = {
      sceneId: this.editingSceneId.length > 0 ? this.editingSceneId : `${Date.now()}`,
      name: name,
      actions: this.actions.slice(),
      timerEnabled: this.timerEnabled,
      timerHour: this.timerSelected.getHours(),
      timerMinute: this.timerSelected.getMinutes(),
      timerDays: mask,
      lastFireDay: lastFireDay
    };
    if (this.editingSceneId.length > 0) {
      LocalSceneStore.update(scene);
      this.getUIContext().getPromptAction().showToast({ message: `已保存「${name}」` });
    } else {
      const list = LocalSceneStore.load();
      list.push(scene);
      LocalSceneStore.save(list);
      this.getUIContext().getPromptAction().showToast({ message: `已创建「${name}」` });
    }
    router.back();
  }

  @Builder
  devicePickerSheet() {
    MaterialSheetPanel() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text(this.pickerDevice === undefined ? '选择设备' : this.pickerDevice.name)
            .fontFamily(this.appFontFamily(this.pickerDevice === undefined ? '选择设备' : this.pickerDevice.name))
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
              this.showDeviceSheet = false;
              this.pickerDevice = undefined;
              this.pickerControls = [];
              this.pickerValues = [];
            }
          })
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .padding({ left: HwSpace.lg, right: HwSpace.lg })

        if (this.pickerDevice === undefined) {
          this.deviceListContent()
        } else {
          this.pickerControlsContent()
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 设备位置：家庭 · 房间（房间名优先按 did 从云端房间归属反查） */
  private deviceLocationText(device: XiaomiDevice): string {
    const home = device.homeName.trim();
    const byDid = this.roomNamesByDid.get(device.did);
    const byRoomId = this.roomNames.get(device.roomId);
    let room = device.roomName.trim();
    if (byDid !== undefined && byDid.trim().length > 0) {
      room = byDid.trim();
    } else if (byRoomId !== undefined && byRoomId.trim().length > 0) {
      room = byRoomId.trim();
    }
    if (home.length > 0 && room.length > 0) {
      return `${home} · ${room}`;
    }
    if (home.length > 0) {
      return home;
    }
    if (room.length > 0) {
      return room;
    }
    return '未分配房间';
  }

  @Builder
  deviceListContent() {
    Column({ space: 0 }) {
      if (this.devicesLoading) {
        Text('加载中…')
          .fontFamily(this.appFontFamily('加载中…'))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 24 })
      } else if (this.devices.length === 0) {
        Column({ space: 8 }) {
          Text('暂无在线设备')
            .fontFamily(this.appFontFamily('暂无在线设备'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
          Text('请先返回首页确认设备已加载')
            .fontFamily(this.appFontFamily('请先返回首页确认设备已加载'))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
        }
        .width('100%')
        .padding({ top: 40, bottom: 40 })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.devices, (device: XiaomiDevice) => {
              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardSpace: 12,
                cardPadding: HwSpace.md,
                cardRadius: HwRadius.control,
                cardOnClick: (): void => {
                  this.pickDevice(device);
                }
              }) {
                Column({ space: 2 }) {
                  Text(device.name)
                    .fontFamily(this.appFontFamily(device.name))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.deviceLocationText(device))
                    .fontFamily(this.appFontFamily(this.deviceLocationText(device)))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([HwColor.textSecondary])
              }
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
    .layoutWeight(1)
  }

  @Builder
  pickerControlsContent() {
    Column({ space: 0 }) {
      if (this.pickerLoading) {
        Text('加载中…')
          .fontFamily(this.appFontFamily('加载中…'))
          .fontWeight(this.appFontWeight())
          .fontSize(14)
          .fontColor(HwColor.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 24 })
      } else if (this.pickerError.length > 0) {
        Column({ space: 8 }) {
          Text(this.pickerError)
            .fontFamily(this.appFontFamily(this.pickerError))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.danger)
          Button('返回设备列表')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.pickerDevice = undefined;
              this.pickerControls = [];
              this.pickerValues = [];
            })
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
      } else if (this.pickerControls.length === 0) {
        Column({ space: 8 }) {
          Text('该设备没有可控制的属性')
            .fontFamily(this.appFontFamily('该设备没有可控制的属性'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
          Button('返回设备列表')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.pickerDevice = undefined;
              this.pickerControls = [];
              this.pickerValues = [];
            })
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            Text('调整动作后点击下方「添加这些动作」')
              .fontFamily(this.appFontFamily('调整动作后点击下方「添加这些动作」'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
              .width('100%')

            ForEach(this.pickerControls, (control: PropertyControlDescriptor) => {
              PropertyControl({
                control: control,
                value: this.pickerValueOf(control),
                onChanged: (value: Object) => {
                  this.updatePickerValue(control, value);
                }
              })
            }, (control: PropertyControlDescriptor) => `${control.siid}.${control.piid}`)

            Blank().height(8)
          }
          .width('100%')
          .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 12 })
          .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 确认按钮固定在底部，避免控件过多时被滚动内容挤出屏幕
        Row({ space: 12 }) {
          Button('返回设备列表')
            .buttonStyle(ButtonStyleMode.NORMAL)
            .height(44)
            .fontSize(15)
            .fontColor(HwColor.textSecondary)
            .backgroundColor(withAlpha(HwColor.textPrimary, 0.06))
            .layoutWeight(1)
            .onClick(() => {
              this.pickerDevice = undefined;
              this.pickerControls = [];
              this.pickerValues = [];
            })
          Stack() {
            MaterialCardLayer({ layerRadius: HwRadius.pill })
            Button('添加这些动作')
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(Color.Transparent)
              .fontColor(this.accentOrPrimary())
              .stateEffect(false)
              .onClick(() => {
                this.confirmAddActions();
              })
          }
          .width('55%')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({
          left: HwSpace.lg,
          right: HwSpace.lg,
          top: 8,
          bottom: this.navigationBarHeight + 20
        })
        .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  actionRow(action: LocalSceneAction, index: number) {
    MaterialCard({
      cardDirection: FlexDirection.Row,
      cardSpace: 12,
      cardPadding: HwSpace.md,
      cardRadius: HwRadius.control
    }) {
      Column({ space: 2 }) {
        Text(action.deviceName)
          .fontFamily(this.appFontFamily(action.deviceName))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${action.label} = ${action.valueText !== undefined ? action.valueText : String(action.value)}`)
          .fontFamily(this.appFontFamily(`${action.label} = ${action.valueText !== undefined ? action.valueText : String(action.value)}`))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      IconCircleButton({
        symbol: $r('sys.symbol.trash'),
        buttonSize: 32,
        iconSize: 16,
        tint: HwColor.danger,
        onAction: () => {
          this.removeAction(index);
        }
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
      AccentColorSentinel()
      AppBackground()
      Column() {
        Scroll() {
          Column({ space: 12 }) {
            Blank().height(56 + this.statusBarHeight)

            if (this.message.length > 0) {
              Text(this.message)
                .fontFamily(this.appFontFamily(this.message))
                .fontWeight(this.appFontWeight())
                .fontSize(13)
                .fontColor(HwColor.danger)
                .width('100%')
                .padding({ left: 4, right: 4 })
            }

            // 名称输入刻意**不放进 MaterialCard**：卡片外壳挂了长按手势，
            // 会抢走 TextInput 需要的按压序列，表现为「点不进、打不了字」。
            // 与首页搜索框是同一个坑，解法一致：输入框直接暴露在最上层。
            Stack() {
              // 承载层只画材质、不参与命中（MaterialCardLayer 内部是 enabled(false) +
              // hitTestBehavior(None)），所以放在这里不会抢走 TextInput 的按压序列。
              MaterialCardLayer({ layerRadius: HwRadius.card })
              Column({ space: HwSpace.sm }) {
                Text('智能名称')
                  .fontFamily(this.appFontFamily('智能名称'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(12)
                  .fontColor(HwColor.textSecondary)
                  .width('100%')
                TextInput({ text: this.sceneName, placeholder: '例如：回家模式' })
                  .fontFamily(this.appFontFamily('例如：回家模式'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(15)
                  .fontColor(HwColor.textPrimary)
                  .placeholderColor(HwColor.textSecondary)
                  .caretColor(this.accentOrPrimary())
                  .backgroundColor(Color.Transparent)
                  .height(44)
                  .width('100%')
                  .onChange((value: string) => {
                    this.sceneName = value;
                  })
              }
              .width('100%')
              .padding(HwSpace.lg)
            }
            .width('100%')
            .borderRadius(HwRadius.card)
            .clip(true)

            // bindSheet 不能挂在本卡片上（自定义组件尾随闭包后不能链式挂属性，
            // 且该 sheet 是「设备动作」选择器，本就属于这张卡片的触发器）：
            // 外层包一个 Column 来挂 sheet，卡片自身保持纯展示。
            Column() {
              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardSpace: 12,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardOnClick: (): void => {
                  this.showDeviceSheet = true;
                }
              }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(18)
                  .fontColor([HwColor.primary])
                Text('添加设备动作')
                  .fontFamily(this.appFontFamily('添加设备动作'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(15)
                  .fontColor(HwColor.textPrimary)
                  .layoutWeight(1)
              }
            }
            .width('100%')
            .bindSheet($$this.showDeviceSheet, this.devicePickerSheet(), {
              height: SheetSize.LARGE,
              dragBar: true,
              // 系统默认 Color.White，会盖在材质之上，必须显式透明
              backgroundColor: Color.Transparent,
              showClose: false
            })

            MaterialCard({
              cardPadding: HwSpace.lg,
              cardRadius: HwRadius.card
            }) {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.moon_fill'))
                  .fontSize(18)
                  .fontColor([this.accentOrPrimary()])
                Column({ space: 2 }) {
                  Text('定时执行')
                    .fontFamily(this.appFontFamily('定时执行'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text('到达设定时刻后自动执行本智能')
                    .fontFamily(this.appFontFamily('到达设定时刻后自动执行本智能'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.timerEnabled })
                  .selectedColor(this.accentOrPrimary())
                  .onChange((on: boolean) => {
                    this.timerEnabled = on;
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              if (this.timerEnabled) {
                Text('触发时刻')
                  .fontFamily(this.appFontFamily('触发时刻'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(12)
                  .fontColor(HwColor.textSecondary)
                  .width('100%')
                TimePicker({ selected: this.timerSelected })
                  .useMilitaryTime(true)
                  .disappearTextStyle({ color: withAlpha(HwColor.textPrimary, 0.4), font: { size: 13 } })
                  .textStyle({ color: withAlpha(HwColor.textPrimary, 0.75), font: { size: 15 } })
                  .selectedTextStyle({ color: HwColor.textPrimary, font: { size: 19, weight: FontWeight.Medium } })
                  .height(120)
                  .width('100%')
                  .onChange((value: TimePickerResult) => {
                    const next = new Date();
                    next.setHours(value.hour, value.minute, 0, 0);
                    this.timerSelected = next;
                  })
                Text('重复日')
                  .fontFamily(this.appFontFamily('重复日'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(12)
                  .fontColor(HwColor.textSecondary)
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.timerDayLabels, (label: string, index: number) => {
                    Text(label)
                      .fontFamily(this.appFontFamily(label))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(this.timerDays[index] ? '#FFFFFF' : HwColor.textPrimary)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .borderRadius(14)
                      .backgroundColor(this.timerDays[index]
                        ? this.accentOrPrimary() : withAlpha(HwColor.textPrimary, 0.06))
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => {
                        this.toggleTimerDay(index);
                      })
                  }, (label: string) => label)
                }
                .width('100%')
              }
            }

            if (this.actions.length > 0) {
              Text(`动作（${this.actions.length}）`)
                .fontFamily(this.appFontFamily(`动作（${this.actions.length}）`))
                .fontWeight(this.appFontWeight())
                .fontSize(13)
                .fontColor(HwColor.textSecondary)
                .width('100%')
                .padding({ left: 4, right: 4 })

              ForEach(this.actions, (action: LocalSceneAction, index: number) => {
                this.actionRow(action, index)
              }, (action: LocalSceneAction, index: number) => `${action.did}_${action.siid}_${action.piid}_${index}`)
            }

            Blank().height(HwSpace.xl)

            Stack() {
              // 材质承载层：普通 Button 直接挂 systemMaterial 真机不渲染，
              // 统一走与卡片同源的 Toggle 承载路径。
              MaterialCardLayer({ layerRadius: HwRadius.pill })
              Button(this.editingSceneId.length > 0 ? '保存修改' : '保存智能')
                .width('100%')
                .height(46)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .backgroundColor(Color.Transparent)
                .fontColor(this.accentOrPrimary())
                .stateEffect(false)
                .onClick(() => {
                  this.saveScene();
                })
            }
            .width('100%')

            Blank().height(HwSpace.xl)
          }
          .width('100%')
          .constraintSize({ maxWidth: 1080 })
          .padding({ left: HwSpace.lg, right: HwSpace.lg, top: HwSpace.lg, bottom: HwSpace.xl })
        }
        .width('100%')
        .height('100%')
        // align 必须挂在 Scroll 上：通用 align 属性默认 Alignment.Center，
        // 不设的话内容会被垂直居中，而不是从顶部往下排。
        .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      Row() {
        IconCircleButton({
          symbol: $r('sys.symbol.chevron_left'),
          buttonSize: 40,
          iconSize: 20,
          onAction: () => {
            router.back();
          }
        })
        Text(this.editingSceneId.length > 0 ? '编辑智能' : '创建智能')
          .fontFamily(this.appFontFamily(this.editingSceneId.length > 0 ? '编辑智能' : '创建智能'))
          .fontWeight(this.appFontWeight())
          .margin({ left: HwSpace.md })
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(HwColor.textPrimary)
        Blank()
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      // 与全站其余页面一致的浅色毛玻璃（这里原本是深蓝渐变 + 白字）
      .backgroundEffect({ radius: 12, color: '#66FFFFFF' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HwColor.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
