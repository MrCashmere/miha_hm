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
import { XiaomiDevice, XiaomiHome, InfoExcludeOption, ALL_HOMES_ID, ALL_HOMES_NAME, LocalScene } from '../models/XiaomiHomeModels';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { localSceneService } from '../services/LocalSceneService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';
import { deviceSymbolFor, isLightDeviceText } from '../utils/DeviceSymbol';
import { DataSourceState } from '../models/CacheState';
import { XiaomiAuthError } from '../models/XiaomiErrors';
import { HwColor, HwGlassCardColor, HwRadius, HwSpace, onAccentColor, reloadAppTheme, resolvePageBackground, withAlpha } from '../utils/DesignTokens';
import { applyMaterialCarrier, pressLightColor, sheetSystemMaterial, sheetBlurStyle } from '../utils/SystemMaterial';
import { isCelsiusUnit, celsiusToFahrenheit } from '../utils/TemperatureDisplay';
import { MaterialCard, MaterialCardLayer, MaterialSheetPanel, AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { DeviceOverrideStore } from '../storage/DeviceOverrideStore';
import { DeviceRemovalStore } from '../storage/DeviceRemovalStore';
import { MessageReadStore } from '../storage/MessageReadStore';
import { MijiaMessageItem } from '../cloud/MijiaApiClient';
import { AppBackground } from '../components/AppBackground';
import { DeviceDetailRouteParam, DeviceManageRouteParam } from '../models/NavRouteParams';
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

/** 房间筛选 chip 的哨兵 key：分别代表「全部」与「未归类到任何房间」 */
const ROOM_ALL_KEY: string = '__all_rooms__';
const ROOM_UNROOMED_KEY: string = '__unroomed__';

/** 设备排序模式持久化键（与设置页共享，保证两处一致） */
const DEVICE_SORT_MODE_KEY: string = 'deviceSortMode';
/** 快捷开关的电源属性与开关状态持久化键：冷启动时按钮即可见、颜色为上次已知状态 */
const QUICK_POWER_PROPS_KEY: string = 'quick_power_props_v1';
const QUICK_POWER_STATES_KEY: string = 'quick_power_states_v1';

/**
 * 快捷开关目标属性。
 * used=false 表示该设备已确认没有可写电源属性（传感器/网关/路由等），
 * 记下来避免每次进首页都重新拉 spec。
 */
interface QuickPowerTarget {
  siid: number;
  piid: number;
  used: boolean;
}

/** 房间候选：云端房间、本地房间、设备自带的 roomName 都先归一化成候选再汇总 */
interface RoomCandidate {
  key: string;
  name: string;
  roomId: string;
  dids: string[];
}

/** 首页房间筛选 chip */
/** 排序方式选项 */
interface SortModeOption {
  key: string;
  label: string;
}

/** 首页设备排序方式：与设备排序按钮、设置页共用同一套 key */
const SORT_MODES: SortModeOption[] = [
  { key: 'smart', label: '在线优先' },
  { key: 'name', label: '按名称' },
  { key: 'room', label: '按房间分组' }
];

/** 设备卡长按菜单的动作项 */
interface DeviceActionItem {
  label: string;
  /** 菜单项图标，用系统符号 */
  icon: Resource;
  action: () => void;
}

interface RoomChip {
  key: string;
  name: string;
  roomId: string;
  dids: string[];
  count: number;
}

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
  /**
   * 点击卡片要执行的动作（打开对应的设备明细弹窗）。
   *
   * 必须通过 cardOnClick 传进 MaterialCard：卡片外壳自带 onClick，
   * 会把事件吞掉，外面再包一层 Column 挂 onClick 是收不到点击的——
   * 这正是此前「信息页卡片点击无反应」的原因。
   */
  action: () => void;
}

@Entry
@Component
struct HomePage {
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  /**
   * 主题色流光开关。
   *
   * 底部 HdsTab 那圈流光（barFloatingStyle 的 lightColor）默认是白的，
   * 只有读到这个订阅键，拨开关时底部栏才会重新求值、换色。
   */
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
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
  private messageScroller: Scroller = new Scroller();
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
  /** 页面底色（由 applyAppTheme 发布）。订阅它而不是读 HwColor 属性，见 docs/ThemeColor.md §7.8 */
  @StorageProp('pageBackground') pageBackground: string = '';
  @StorageLink('infoExcludedDevices') infoExcludedDevices: string[] = [];
  @StorageLink('backgroundImage') wallpaperImage: string = '';
  @StorageLink('infoShowMoreContent') infoShowMoreContent: boolean = true;
  @StorageLink('sortDevicesByRoom') @Watch('onSortDevicesByRoomChanged') sortDevicesByRoom: boolean = false;
  /** 采集页概览区开关，对应设置页「首页概览卡片」 */
  @StorageLink('showOverviewCards') showOverviewCards: boolean = true;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('defaultHomeTab') defaultHomeTab: string = 'home';
  @StorageLink('infoRefreshInterval') @Watch('onInfoRefreshIntervalChanged') infoRefreshInterval: string = '30';
  @State localRooms: UserRoom[] = [];

  // ---- 首页检索 / 房间筛选 ----
  @State searchKeyword: string = '';
  /** 经「本地移除过滤 → 房间 chip → 关键词」三道筛选后的最终列表，ForEach 只渲染它 */
  @State filteredDevices: XiaomiDevice[] = [];
  @State selectedRoomKey: string = ROOM_ALL_KEY;
  @State roomChips: RoomChip[] = [];

  // ---- 设备排序 / 置顶 / 改名 ----
  @State deviceSortMode: string = 'smart';
  @State favoriteDevices: string[] = [];
  /** 显示名覆盖的内存副本：@State 是为了让改名后列表立刻重绘 */
  @State nameOverrides: Record<string, string> = {};
  @State showRenameSheet: boolean = false;
  @State showFavoriteSheet: boolean = false;
  @State renameDid: string = '';
  @State renameValue: string = '';

  // ---- 快捷开关 ----
  @State quickPowerStates: Record<string, boolean> = {};
  /**
   * 渲染依赖计数器：电源属性在后台异步解析完成后自增，触发设备卡里
   * 「是否显示快捷开关」的条件重新求值（属性表本身是 Map，改它不会触发重绘）。
   */
  @State quickPowerVersion: number = 0;
  private quickPowerTargets: Map<string, QuickPowerTarget> = new Map();
  /** 详情页点击与快捷开关点击共处一张卡：标记本次点击已被开关消费 */
  private quickSwitchTapHandled: boolean = false;

  // ---- 一键关灯 / 下拉刷新 / 骨架屏 ----
  @State lightsOffing: boolean = false;
  // ---- 家庭消息（云端告警）----
  @State cloudMessages: MijiaMessageItem[] = [];
  /** 长按设备弹窗：当前设备与可见性 */
  @State showDeviceActionSheet: boolean = false;
  /** 排序选择面板可见性（自定义面板，替代系统 showActionSheet） */
  @State showSortSheet: boolean = false;
  @State actionDevice: XiaomiDevice | null = null;
  @State messageLoading: boolean = false;
  /** 已读消息 id：用于在列表上区分未读，持久化在 MessageReadStore */
  @State readMessageIds: string[] = [];
  @State homeRefreshing: boolean = false;
  @State homeRefreshText: string = '下拉刷新';
  @State skeletonPlaceholders: number[] = [0, 1, 2, 3, 4, 5];
  /**
   * 快捷开关要按设备拉 spec + 读属性，是长串异步任务。
   * 离开页面后这些任务仍会返回，必须靠这个标志把它们挡在 setState 之前，
   * 否则会对已销毁的组件写状态。
   */
  private pageAlive: boolean = true;

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
  /**
   * 通知直达：EntryAbility 冷启动解析 want 里的设备 did 写进该键。
   * 冷启动时值可能早于本页构建，所以除了 @Watch 还要在 aboutToAppear 主动消费一次。
   */
  @StorageProp('pendingDeviceDetailDid') @Watch('onPendingDeviceDidChanged') pendingDeviceDetailDid: string = '';

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  /**
   * 开关的选中色。
   * 读 accentColor 建立依赖：直接写 HwColor.primary 在切主题色后不会重新求值，
   * 开关会停留在旧色。
   */
  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  aboutToAppear(): void {
    this.readMessageIds = MessageReadStore.loadReadIds();
    FeedbackLogService.setCurrentPage('首页');
    this.pageAlive = true;
    this.onBreakpointChange();
    this.localRooms = RoomStore.loadRooms();
    this.loadDeviceOverrides();
    // 快捷开关：先恢复上次的电源属性与状态，按钮冷启动立即可见
    this.loadPersistedQuickPower();
    this.loadData(true);
    this.loadAccount();
    this.consumePendingDeviceDetail();
    if (this.defaultHomeTab === 'info' && !this.isWearable) {
      this.activeTab = 1;
      this.refreshInfoOnEnter();
      this.startInfoRefreshTimer();
    }
    // 本地智能定时：首页在整个前台生命周期内常驻，心跳挂在这里最稳。
    // 到点后由服务自己执行动作，这里只负责把「已执行」提示出来。
    localSceneService.onFired = (scene: LocalScene): void => {
      if (this.pageAlive) {
        this.getUIContext().getPromptAction().showToast({ message: `已执行「${scene.name}」` });
      }
    };
    localSceneService.start();
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
    this.stopInfoRefreshTimer();
    // 首页是应用的主容器，它退场说明应用已离开前台；本地智能定时随之停摆
    localSceneService.stop();
  }

  onPageShow(): void {
    this.localRooms = RoomStore.loadRooms();
    // 详情页/设置页可能改了本地名、置顶或排序模式，返回时必须重新读盘再重排
    this.loadDeviceOverrides();
    this.applyDeviceVisibility();
    this.loadQuickSwitchStates();
  }

  onHideOfflineDevicesChanged(): void {
    this.applyDeviceVisibility();
  }

  /** 房间分组开关在设置页被改动后，首页排序语义要跟着切（与 deviceSortMode 双向同步） */
  onSortDevicesByRoomChanged(): void {
    const nextMode = this.sortDevicesByRoom ? 'room' : 'smart';
    if (nextMode !== this.deviceSortMode) {
      this.deviceSortMode = nextMode;
      AppSettingsStore.setString(DEVICE_SORT_MODE_KEY, nextMode);
    }
    this.applyDeviceVisibility();
  }

  private applyDeviceVisibility(): void {
    let visible = this.allVisibleDevices;
    if (this.hideOfflineDevices) {
      visible = visible.filter((device: XiaomiDevice) => device.online);
    }
    this.devices = this.sortVisibleDevices(visible);
    // 设备集合变了，房间 chip 的计数与命中范围必须同步重建，否则筛选会选中已消失的房间
    this.rebuildRoomChips();
    if (this.selectedRoomKey !== ROOM_ALL_KEY && this.findRoomChip(this.selectedRoomKey) === null) {
      this.selectedRoomKey = ROOM_ALL_KEY;
    }
    this.updateFilteredDevices();
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
      // 本地移除的设备在首页（以及信息页统计口径）里彻底不出现
      visibleDevices = DeviceRemovalStore.filter(visibleDevices);
      this.allVisibleDevices = visibleDevices;
      let displayDevices: XiaomiDevice[] = [];
      if (this.hideOfflineDevices) {
        displayDevices = visibleDevices.filter((device: XiaomiDevice) => device.online);
      } else {
        displayDevices = visibleDevices;
      }
      this.devices = this.sortVisibleDevices(displayDevices);
      this.rebuildRoomChips();
      if (this.selectedRoomKey !== ROOM_ALL_KEY && this.findRoomChip(this.selectedRoomKey) === null) {
        this.selectedRoomKey = ROOM_ALL_KEY;
      }
      // 家庭确定后异步拉消息，不阻塞首屏列表渲染
      this.loadCloudMessages();
      this.updateFilteredDevices();
      // 快捷开关属性解析是网络活，放到列表渲染之后异步跑，不阻塞首页出图
      this.loadQuickSwitchStates();
      FeedbackLogService.recordOperation('PAGE',
        `首页设备列表: 共 ${displayDevices.length} 台，${this.deviceListSummary(displayDevices)}`);
      const excludeOptions: InfoExcludeOption[] = [];
      for (let i = 0; i < displayDevices.length; i++) {
        excludeOptions.push({
          did: displayDevices[i].did,
          name: this.homeDisplayName(displayDevices[i]),
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
      if (this.activeTab === this.infoTabIndex()) {
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
    if (this.activeTab === this.infoTabIndex()) {
      this.startInfoRefreshTimer();
    }
  }

  onTemperatureUnitChanged(): void {
    if (this.activeTab === this.infoTabIndex()) {
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
    // 收藏（置顶）优先级高于排序模式：无论怎么排，置顶设备都在最前面
    const favorites: XiaomiDevice[] = [];
    const others: XiaomiDevice[] = [];
    for (let i = 0; i < devices.length; i++) {
      if (this.isFavoriteDevice(devices[i].did)) {
        favorites.push(devices[i]);
      } else {
        others.push(devices[i]);
      }
    }
    const result: XiaomiDevice[] = this.applyDeviceBaseSort(favorites);
    const rest = this.applyDeviceBaseSort(others);
    for (let k = 0; k < rest.length; k++) {
      result.push(rest[k]);
    }
    return result;
  }

  /** 收藏组内 / 非收藏组内各自应用的基准排序（在线优先 / 按名称 / 按房间分组） */
  private applyDeviceBaseSort(devices: XiaomiDevice[]): XiaomiDevice[] {
    const working = devices.slice();
    if (this.deviceSortMode === 'name') {
      working.sort((a: XiaomiDevice, b: XiaomiDevice): number => {
        return this.homeDisplayName(a).localeCompare(this.homeDisplayName(b), 'zh-CN');
      });
      return working;
    }
    const byOnlineDesc = (a: XiaomiDevice, b: XiaomiDevice): number => {
      const aOnline = a.online ? 1 : 0;
      const bOnline = b.online ? 1 : 0;
      return bOnline - aOnline;
    };
    if (this.deviceSortMode !== 'room') {
      working.sort(byOnlineDesc);
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
      roomDevices.sort(byOnlineDesc);
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
    rest.sort(byOnlineDesc);
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

  /** 同步本地设备覆盖数据（改名 / 收藏 / 排序模式），从详情页或设置页返回后保持一致 */
  private loadDeviceOverrides(): void {
    this.favoriteDevices = DeviceOverrideStore.loadFavorites();
    this.nameOverrides = DeviceOverrideStore.loadNameOverrides();
    const storedMode = AppSettingsStore.getString(DEVICE_SORT_MODE_KEY, '');
    if (storedMode === 'smart' || storedMode === 'name' || storedMode === 'room') {
      this.deviceSortMode = storedMode;
    } else {
      this.deviceSortMode = this.sortDevicesByRoom ? 'room' : 'smart';
    }
  }

  /**
   * 设备显示名：本地改名覆盖优先，其次云端名称。
   * 走内存副本而不是每次读盘，避免列表每帧都做一次 JSON 解析。
   */
  private homeDisplayName(device: XiaomiDevice): string {
    const override = this.nameOverrides[device.did];
    if (override !== undefined && override.length > 0) {
      return override;
    }
    return device.name;
  }

  /** 供卡片标识等只需要 did + 云端名的场景使用，统一走 DeviceOverrideStore 口径 */
  private displayNameForDid(did: string, cloudName: string): string {
    return DeviceOverrideStore.getDisplayName(did, cloudName);
  }

  private isFavoriteDevice(did: string): boolean {
    return this.favoriteDevices.indexOf(did) >= 0;
  }

  /**
   * 置顶管理页的列表。
   * 只从当前家庭已展示的设备里取，已下架/已本地移除的 did 不再出现，
   * 但也不会被自动清掉（换回家后置顶关系仍在）。
   */
  private favoriteDeviceList(): XiaomiDevice[] {
    const result: XiaomiDevice[] = [];
    for (let i = 0; i < this.favoriteDevices.length; i++) {
      const matched = this.findDeviceByDid(this.devices, this.favoriteDevices[i]);
      if (matched !== null) {
        result.push(matched);
      }
    }
    return result;
  }

  private setDeviceSortMode(mode: string): void {
    this.deviceSortMode = mode;
    AppSettingsStore.setString(DEVICE_SORT_MODE_KEY, mode);
    // 设置页的「按房间排序」开关与这里的 room 模式是同一个语义，双向同步避免两处显示不一致
    const roomFlag = mode === 'room';
    if (this.sortDevicesByRoom !== roomFlag) {
      AppSettingsStore.setBoolean('sortDevicesByRoom', roomFlag);
      this.sortDevicesByRoom = roomFlag;
    }
    FeedbackLogService.recordOperation('UI', `切换设备排序为 ${mode}`);
    this.applyDeviceVisibility();
  }

  private deviceSortLabel(): string {
    if (this.deviceSortMode === 'name') {
      return '按名称';
    }
    if (this.deviceSortMode === 'room') {
      return '按房间分组';
    }
    return '在线优先';
  }

  /** 排序模式菜单：用符号打勾而不是改文案，避免菜单宽度随选中项跳动 */
  /** 打开排序方式选择面板 */
  private openSortSheet(): void {
    this.showSortSheet = true;
  }


  private toggleDeviceFavorite(did: string): void {
    const favorite = DeviceOverrideStore.toggleFavorite(did);
    this.favoriteDevices = DeviceOverrideStore.loadFavorites();
    this.applyDeviceVisibility();
    this.getUIContext().getPromptAction().showToast({
      message: favorite ? '已置顶，设备排在列表最前' : '已取消置顶'
    });
  }

  private openRenameSheet(did: string): void {
    this.renameDid = did;
    let current = '';
    for (let i = 0; i < this.allVisibleDevices.length; i++) {
      if (this.allVisibleDevices[i].did === did) {
        current = this.homeDisplayName(this.allVisibleDevices[i]);
        break;
      }
    }
    this.renameValue = current;
    this.showRenameSheet = true;
  }

  private saveDeviceRename(): void {
    const did = this.renameDid;
    if (did.length === 0) {
      this.showRenameSheet = false;
      return;
    }
    const trimmed = this.renameValue.trim();
    if (trimmed.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '设备名称不能为空' });
      return;
    }
    DeviceOverrideStore.setNameOverride(did, trimmed);
    this.nameOverrides = DeviceOverrideStore.loadNameOverrides();
    this.showRenameSheet = false;
    this.applyDeviceVisibility();
    this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
  }

  /** 恢复云端名称：清空覆盖值即可（DeviceOverrideStore 对空字符串就是删除语义） */
  private resetDeviceRename(): void {
    if (this.renameDid.length === 0) {
      return;
    }
    DeviceOverrideStore.setNameOverride(this.renameDid, '');
    this.nameOverrides = DeviceOverrideStore.loadNameOverrides();
    this.showRenameSheet = false;
    this.applyDeviceVisibility();
    this.getUIContext().getPromptAction().showToast({ message: '已恢复为云端名称' });
  }

  // ==================== 房间分组 chips ====================

  private currentHome(): XiaomiHome | null {
    for (let i = 0; i < this.homes.length; i++) {
      if (this.homes[i].homeId === this.selectedHomeId) {
        return this.homes[i];
      }
    }
    return null;
  }

  private findRoomChip(key: string): RoomChip | null {
    for (let i = 0; i < this.roomChips.length; i++) {
      if (this.roomChips[i].key === key) {
        return this.roomChips[i];
      }
    }
    return null;
  }

  private deviceMatchesCandidate(device: XiaomiDevice, candidate: RoomCandidate): boolean {
    if (candidate.roomId.length > 0 && device.roomId === candidate.roomId) {
      return true;
    }
    if (candidate.name.length > 0 && device.roomName === candidate.name) {
      return true;
    }
    return candidate.dids.indexOf(device.did) >= 0;
  }

  /**
   * 重建房间 chip。
   *
   * 房间来源三份，按优先级依次占用设备，避免同一台设备被两个 chip 同时统计：
   *   1. 云端家庭房间（home.roomList）；
   *   2. 本地房间（RoomStore 里用户自己划的楼层/房间，只取当前家庭的）；
   *   3. 设备自带 roomName（云端没建房间时的兜底）。
   * 都没命中的设备归到「未分类」。
   */
  private rebuildRoomChips(): void {
    const source = this.allVisibleDevices;
    const chips: RoomChip[] = [];
    chips.push({
      key: ROOM_ALL_KEY,
      name: '全部',
      roomId: '',
      dids: [],
      count: source.length
    });

    const candidates: RoomCandidate[] = [];
    const knownNames = new Set<string>();
    const home = this.currentHome();
    if (home !== null) {
      for (let i = 0; i < home.roomList.length; i++) {
        const room = home.roomList[i];
        if (knownNames.has(room.name)) {
          continue;
        }
        knownNames.add(room.name);
        candidates.push({
          key: `room_${room.roomId}`,
          name: room.name,
          roomId: room.roomId,
          dids: room.dids.slice()
        });
      }
    }
    for (let i = 0; i < this.localRooms.length; i++) {
      const localRoom = this.localRooms[i];
      const displayName = localRoom.floor.length > 0 ? `${localRoom.floor}楼 ${localRoom.name}` : localRoom.name;
      if (displayName.length === 0 || knownNames.has(displayName)) {
        continue;
      }
      knownNames.add(displayName);
      candidates.push({
        key: `local_${localRoom.id}`,
        name: displayName,
        roomId: '',
        dids: localRoom.dids.slice()
      });
    }
    for (let i = 0; i < source.length; i++) {
      const name = source[i].roomName.trim();
      if (name.length === 0 || knownNames.has(name)) {
        continue;
      }
      knownNames.add(name);
      candidates.push({
        key: `name_${name}`,
        name: name,
        roomId: '',
        dids: []
      });
    }

    const consumed = new Set<string>();
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      const dids: string[] = [];
      for (let j = 0; j < source.length; j++) {
        const device = source[j];
        if (consumed.has(device.did)) {
          continue;
        }
        if (!this.deviceMatchesCandidate(device, candidate)) {
          continue;
        }
        dids.push(device.did);
        consumed.add(device.did);
      }
      if (dids.length > 0) {
        chips.push({
          key: candidate.key,
          name: candidate.name,
          roomId: candidate.roomId,
          dids: dids,
          count: dids.length
        });
      }
    }

    const unroomed: string[] = [];
    for (let i = 0; i < source.length; i++) {
      if (!consumed.has(source[i].did)) {
        unroomed.push(source[i].did);
      }
    }
    if (unroomed.length > 0) {
      chips.push({
        key: ROOM_UNROOMED_KEY,
        name: '未分类',
        roomId: '',
        dids: unroomed,
        count: unroomed.length
      });
    }
    this.roomChips = chips;
  }

  /** 房间筛选 + 关键词检索：结果写进 filteredDevices，列表只渲染它 */
  private updateFilteredDevices(): void {
    const keyword = this.searchKeyword.trim().toLowerCase();
    let base: XiaomiDevice[] = this.devices;
    if (this.selectedRoomKey !== ROOM_ALL_KEY) {
      const chip = this.findRoomChip(this.selectedRoomKey);
      if (chip !== null) {
        const roomFiltered: XiaomiDevice[] = [];
        for (let i = 0; i < this.devices.length; i++) {
          if (chip.dids.indexOf(this.devices[i].did) >= 0) {
            roomFiltered.push(this.devices[i]);
          }
        }
        base = roomFiltered;
      }
    }
    if (keyword.length === 0) {
      this.filteredDevices = base;
      return;
    }
    const next: XiaomiDevice[] = [];
    for (let i = 0; i < base.length; i++) {
      const device = base[i];
      const displayName = this.homeDisplayName(device);
      const roomName = this.deviceLocation(device);
      if (displayName.toLowerCase().includes(keyword) ||
        device.name.toLowerCase().includes(keyword) ||
        device.model.toLowerCase().includes(keyword) ||
        roomName.toLowerCase().includes(keyword)) {
        next.push(device);
      }
    }
    this.filteredDevices = next;
  }

  private selectRoom(key: string): void {
    if (this.selectedRoomKey === key) {
      return;
    }
    this.selectedRoomKey = key;
    FeedbackLogService.recordOperation('UI', `切换房间筛选 ${key}`);
    this.updateFilteredDevices();
  }

  private clearSearch(): void {
    this.searchKeyword = '';
    this.updateFilteredDevices();
  }

  /** 空列表原因文案：区分「搜不到」「房间是空的」「这个家没设备」 */
  private emptyDeviceHint(): string {
    if (this.searchKeyword.trim().length > 0) {
      // 带上关键词，便于确认过滤确实生效（而不是输入没进来）
      return `没有匹配「${this.searchKeyword.trim()}」的设备，换个关键词试试`;
    }
    if (this.selectedRoomKey === ROOM_ALL_KEY) {
      return '当前家庭没有设备';
    }
    return '该房间暂无设备';
  }

  // ==================== 快捷开关 ====================

  private hasQuickSwitch(device: XiaomiDevice): boolean {
    const target = this.quickPowerTargets.get(device.did);
    return target !== undefined && target.used;
  }

  private isQuickPowerOn(device: XiaomiDevice): boolean {
    return this.quickPowerStates[device.did] === true;
  }

  /**
   * 在 spec 中查找可写布尔型电源属性。
   * 只要 power/switch/开关 关键字且可写，比设备详情页的属性猜测宽松，
   * 因为首页开关出错的代价是误操作，宁可不显示也不猜错 → 这里仍要求 writable 且 bool。
   */
  private findPowerProperty(spec: MIoTSpecInstance): QuickPowerTarget | null {
    for (let i = 0; i < spec.services.length; i++) {
      const service = spec.services[i];
      for (let j = 0; j < service.properties.length; j++) {
        const prop = service.properties[j];
        if (!prop.writable || prop.format.toLowerCase() !== 'bool') {
          continue;
        }
        const text = `${prop.name} ${prop.description} ${prop.type}`.toLowerCase();
        if (text.includes('power') || text.includes('switch') || text.includes('开关')) {
          return { siid: service.iid, piid: prop.iid, used: true };
        }
      }
    }
    return null;
  }

  /** 恢复持久化的电源属性与开关状态，冷启动时按钮立刻可见、颜色为上次已知状态 */
  private loadPersistedQuickPower(): void {
    try {
      const propsRaw = AppSettingsStore.getString(QUICK_POWER_PROPS_KEY, '');
      if (propsRaw.length > 0) {
        const props = JSON.parse(propsRaw) as Record<string, QuickPowerTarget>;
        const propDids = Object.keys(props);
        for (let i = 0; i < propDids.length; i++) {
          this.quickPowerTargets.set(propDids[i], props[propDids[i]]);
        }
      }
      const statesRaw = AppSettingsStore.getString(QUICK_POWER_STATES_KEY, '');
      if (statesRaw.length > 0) {
        this.quickPowerStates = JSON.parse(statesRaw) as Record<string, boolean>;
      }
      this.quickPowerVersion++;
    } catch (err) {
      // 持久化数据损坏时忽略，等联网重新解析
      Logger.warn('restore quick power cache failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
  }

  private persistQuickPowerTargets(): void {
    const payload: Record<string, QuickPowerTarget> = {};
    this.quickPowerTargets.forEach((value: QuickPowerTarget, did: string) => {
      payload[did] = value;
    });
    AppSettingsStore.setString(QUICK_POWER_PROPS_KEY, JSON.stringify(payload));
  }

  private persistQuickPowerStates(): void {
    AppSettingsStore.setString(QUICK_POWER_STATES_KEY, JSON.stringify(this.quickPowerStates));
  }

  private copyQuickPowerStates(): Record<string, boolean> {
    const copy: Record<string, boolean> = {};
    const copyDids = Object.keys(this.quickPowerStates);
    for (let i = 0; i < copyDids.length; i++) {
      copy[copyDids[i]] = this.quickPowerStates[copyDids[i]];
    }
    return copy;
  }

  /** 并行解析每台在线设备的电源属性并读取当前开关状态 */
  async loadQuickSwitchStates(): Promise<void> {
    if (!this.pageAlive) {
      return;
    }
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < this.allVisibleDevices.length; i++) {
      const device = this.allVisibleDevices[i];
      if (!device.online) {
        continue;
      }
      tasks.push(this.loadQuickSwitchForDevice(device));
    }
    try {
      await Promise.all(tasks);
    } catch (err) {
      // 单设备失败不应影响其它设备
      Logger.warn('load quick switch states failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
    if (!this.pageAlive) {
      return;
    }
    this.persistQuickPowerTargets();
  }

  private async loadQuickSwitchForDevice(device: XiaomiDevice): Promise<void> {
    if (!this.pageAlive) {
      return;
    }
    let target = this.quickPowerTargets.get(device.did);
    if (target === undefined) {
      // 路由器不支持控制，直接不查 spec，省一次网络请求
      if (this.isRouterDevice(device)) {
        return;
      }
      try {
        const context = getContext(this) as common.UIAbilityContext;
        const spec = await xiaomiDataService.getDeviceSpecForDeviceCached(device, context);
        const found = this.findPowerProperty(spec);
        if (!this.pageAlive) {
          return;
        }
        // 没有电源属性（传感器/网关/红外虚拟设备等）标记为不可开关，之后不再重试
        target = found === null ? { siid: -1, piid: -1, used: false } : found;
        this.quickPowerTargets.set(device.did, target);
        // 属性表是普通 Map，改它不会触发重绘，用版本号踢一次条件求值
        this.quickPowerVersion++;
        if (!target.used) {
          return;
        }
      } catch (err) {
        // spec 拉取失败，下次进首页再试
        return;
      }
    }
    if (!target.used) {
      return;
    }
    await this.refreshQuickSwitchState(device, target);
  }

  private async refreshQuickSwitchState(device: XiaomiDevice, target: QuickPowerTarget): Promise<void> {
    try {
      const controller = await xiaomiDataService.getDeviceController(device);
      const results = await controller.getProperties(device.did, [
        { did: device.did, siid: target.siid, piid: target.piid }
      ]);
      if (results.length > 0 && this.pageAlive) {
        const next: Record<string, boolean> = this.copyQuickPowerStates();
        next[device.did] = results[0].value === true;
        this.quickPowerStates = next;
        this.persistQuickPowerStates();
      }
    } catch (err) {
      // 读取失败保持未知态（灰灯），不打断列表
    }
  }

  /** 乐观切换：先改本地状态让按钮立刻响应，写失败再回滚 */
  async toggleQuickSwitch(device: XiaomiDevice): Promise<void> {
    const target = this.quickPowerTargets.get(device.did);
    if (target === undefined || !target.used) {
      return;
    }
    const current = this.quickPowerStates[device.did] === true;
    const optimistic: Record<string, boolean> = this.copyQuickPowerStates();
    optimistic[device.did] = !current;
    this.quickPowerStates = optimistic;
    FeedbackLogService.recordOperation('UI',
      `快捷开关 ${this.homeDisplayName(device)} → ${!current ? '开' : '关'}`);
    try {
      const controller = await xiaomiDataService.getDeviceController(device);
      await controller.setProperty(device.did, target.siid, target.piid, !current);
    } catch (err) {
      if (!this.pageAlive) {
        return;
      }
      const rollback: Record<string, boolean> = this.copyQuickPowerStates();
      rollback[device.did] = current;
      this.quickPowerStates = rollback;
      this.getUIContext().getPromptAction().showToast({ message: '控制失败，请重试' });
    }
  }

  // ==================== 一键关灯 ====================

  /** 灯光类设备判断（与设备图标里灯泡分支的关键字保持一致） */
  private isLightDevice(device: XiaomiDevice): boolean {
    return isLightDeviceText(`${device.model} ${device.name}`);
  }

  private onlineLightDevices(): XiaomiDevice[] {
    const lights: XiaomiDevice[] = [];
    for (let i = 0; i < this.allVisibleDevices.length; i++) {
      const device = this.allVisibleDevices[i];
      if (device.online && this.isLightDevice(device)) {
        lights.push(device);
      }
    }
    return lights;
  }

  private confirmLightsOff(): void {
    this.getUIContext().showAlertDialog({
      title: '一键关灯',
      message: '将关闭当前家庭所有在线灯光设备，确定继续吗？',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '关灯',
        fontColor: HwColor.danger,
        action: (): void => {
          this.turnOffAllLights();
        }
      }
    });
  }

  private async turnOffAllLights(): Promise<void> {
    if (this.lightsOffing) {
      return;
    }
    const lights = this.onlineLightDevices();
    if (lights.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有找到在线的灯光设备' });
      return;
    }
    this.lightsOffing = true;
    FeedbackLogService.recordOperation('UI', `一键关灯 ${lights.length} 台`);
    let failed = 0;
    try {
      const controller = await xiaomiDataService.getDeviceController(lights[0]);
      const nextStates: Record<string, boolean> = this.copyQuickPowerStates();
      for (let i = 0; i < lights.length; i++) {
        const light = lights[i];
        try {
          const spec = await xiaomiDataService.getDeviceSpecForDevice(light);
          const power = this.findPowerProperty(spec);
          if (power === null) {
            failed++;
            continue;
          }
          await controller.setProperty(light.did, power.siid, power.piid, false);
          // 关灯成功的设备顺手把首页快捷开关的灯位同步成「关」，避免列表还显示亮着
          this.quickPowerTargets.set(light.did, power);
          nextStates[light.did] = false;
        } catch (err) {
          failed++;
          Logger.error('light off failed, %{public}s',
            err instanceof Error ? err.message : String(err));
        }
      }
      this.quickPowerStates = nextStates;
      this.persistQuickPowerStates();
      this.persistQuickPowerTargets();
      this.quickPowerVersion++;
      const offCount = lights.length - failed;
      this.getUIContext().getPromptAction().showToast({
        message: failed === 0 ? `已关闭 ${lights.length} 盏灯` : `已关闭 ${offCount} 盏灯，${failed} 盏失败`
      });
    } catch (err) {
      Logger.error('turn off all lights failed, %{public}s',
        err instanceof Error ? err.message : String(err));
      this.getUIContext().getPromptAction().showToast({ message: '关灯失败，请重试' });
    } finally {
      this.lightsOffing = false;
    }
  }

  // ==================== 下拉刷新 / 通知直达 ====================

  private refreshStateText(state: RefreshStatus): string {
    if (state === RefreshStatus.OverDrag) {
      return '释放立即刷新';
    }
    if (state === RefreshStatus.Refresh) {
      return '正在刷新…';
    }
    if (state === RefreshStatus.Done) {
      return '刷新完成';
    }
    return '下拉刷新';
  }

  /** 首页下拉：设备列表与信息页概览一起刷新，避免两块数据不同步 */
  private handleHomePullRefresh(): void {
    this.homeRefreshing = true;
    this.loadDeviceOverrides();
    this.loadData(true, true)
      .then((): Promise<void> => this.loadInfoData(true))
      .catch((err: Error) => {
        Logger.error('pull refresh failed, %{public}s', err.message);
      })
      .finally(() => {
        this.homeRefreshing = false;
      });
  }

  onPendingDeviceDidChanged(): void {
    this.consumePendingDeviceDetail();
  }

  /** 消费通知深链的待处理设备 did：跳详情并清空标记，否则返回首页会反复弹详情 */
  private consumePendingDeviceDetail(): void {
    const did = this.pendingDeviceDetailDid;
    if (did === undefined || did.length === 0) {
      return;
    }
    AppStorage.setOrCreate('pendingDeviceDetailDid', '');
    const target = this.findDeviceByDid(this.allVisibleDevices, did);
    // 路由器详情会先弹风险提示，由用户在提示里决定是否继续
    if (target !== null && this.isRouterDevice(target)) {
      this.showRouterWarningDialog(did);
      return;
    }
    this.pageInfos.pushPathByName('deviceDetail', new DeviceDetailRouteParam(did));
  }

  pageTitle(): string {
    if (this.activeTab === 0) {
      return this.selectedHomeName.length > 0 ? this.selectedHomeName : '我的家庭';
    }
    if (this.isWearable) {
      return '我的';
    }
    if (this.activeTab === this.messagesTabIndex()) {
      return '家庭消息';
    }
    if (this.activeTab === this.infoTabIndex()) {
      return '信息';
    }
    return '我的';
  }

  /** 消息 Tab 下标：手机/平板为 1，穿戴同为 1 */
  private messagesTabIndex(): number {
    return 1;
  }

  /** 信息 Tab 下标：手机/平板为 2；穿戴设备没有信息页，返回 -1 */
  private infoTabIndex(): number {
    return this.isWearable ? -1 : 2;
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

  // ==================== 家庭消息（云端告警）====================

  /**
   * 拉取当前家庭的消息列表。
   *
   * 消息是家庭级接口，失败不影响主流程，因此单独异步拉、静默失败。
   * 已读状态由 MessageReadStore 持久化，换设备/重启后仍能区分未读。
   */
  private async loadCloudMessages(): Promise<void> {
    if (this.messageLoading) {
      return;
    }
    if (this.selectedHomeId.length === 0 || this.selectedHomeId === ALL_HOMES_ID) {
      // 未选家庭 / 全部家庭时不查询：消息接口必须带具体 homeId
      this.cloudMessages = [];
      return;
    }
    this.messageLoading = true;
    try {
      const list = await xiaomiDataService.getCloudMessageList(this.selectedHomeId);
      if (this.pageAlive) {
        this.cloudMessages = list;
      }
    } catch (err) {
      // 消息拉取失败不打扰用户：保留上一次结果
      Logger.error('load cloud messages failed, %{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      this.messageLoading = false;
    }
  }

  /** 首页预览用的最近消息：完整列表在独立消息页 */
  private recentMessages(): MijiaMessageItem[] {
    if (this.cloudMessages.length <= 3) {
      return this.cloudMessages;
    }
    return this.cloudMessages.slice(0, 3);
  }

  private isMessageUnread(item: MijiaMessageItem): boolean {
    return this.readMessageIds.indexOf(item.messageId) < 0;
  }

  private unreadMessageCount(): number {
    let count = 0;
    for (let i = 0; i < this.cloudMessages.length; i++) {
      if (this.isMessageUnread(this.cloudMessages[i])) {
        count++;
      }
    }
    return count;
  }

  private markMessageRead(item: MijiaMessageItem): void {
    MessageReadStore.markRead(item.messageId);
    this.readMessageIds = MessageReadStore.loadReadIds();
  }

  private markAllMessagesRead(): void {
    const ids: string[] = [];
    for (let i = 0; i < this.cloudMessages.length; i++) {
      ids.push(this.cloudMessages[i].messageId);
    }
    MessageReadStore.markAllRead(ids);
    this.readMessageIds = MessageReadStore.loadReadIds();
  }

  private formatMessageTime(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds <= 0) {
      return '';
    }
    const date = new Date(seconds * 1000);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const hour = date.getHours();
    const minute = date.getMinutes();
    const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
    return `${month}/${day} ${pad(hour)}:${pad(minute)}`;
  }

  private refreshCurrentTab(): void {
    if (this.isWearable && this.activeTab === this.tabMineIndex()) {
      this.loadData(true, true);
      this.loadAccount();
      return;
    }
    if (this.activeTab === this.messagesTabIndex()) {
      this.loadCloudMessages();
    } else if (this.activeTab === this.infoTabIndex()) {
      this.loadInfoData(false);
    } else if (this.activeTab === this.tabMineIndex()) {
      this.loadData(true, true);
      this.loadAccount();
    } else {
      this.loadData(true);
    }
  }

  /**
   * 底部 Tab 顺序：首页 / 消息 / 信息 / 我的。
   * 穿戴设备没有信息页，顺序为 首页 / 消息 / 我的。
   */
  private tabLabel(index: number): string {
    if (index === 0) {
      return '首页';
    }
    if (index === 1) {
      return '消息';
    }
    if (index === 2) {
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
    } else if (index === 1) {
      // 消息：有未读时用实心铃铛提示
      // 消息用信封（工程内已确认存在的符号）；有未读时改用实心标记
      SymbolGlyph(this.unreadMessageCount() > 0
        ? $r('sys.symbol.envelope_fill') : $r('sys.symbol.envelope'))
        .fontSize(24)
        .fontColor([this.activeTab === this.messagesTabIndex() || this.unreadMessageCount() > 0
          ? this.accent() : HwColor.textSecondary])
    } else if (index === 2 && !this.isWearable) {
      SymbolGlyph(this.activeTab === this.infoTabIndex() ? $r('sys.symbol.info_circle_fill') : $r('sys.symbol.info_circle'))
        .fontSize(24)
        .fontColor([this.activeTab === this.infoTabIndex() ? this.accent() : HwColor.textSecondary])
    } else {
      SymbolGlyph(this.activeTab === this.tabMineIndex()
        ? $r('sys.symbol.person_fill') : $r('sys.symbol.person'))
        .fontSize(24)
        .fontColor([this.activeTab === this.tabMineIndex()
          ? HwColor.primary : HwColor.textSecondary])
    }
  }

  /** 「我的」在每个平台的索引：手机/平板是 3，穿戴是 2 */
  private tabMineIndex(): number {
    return this.isWearable ? 2 : 3;
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
    if (index === 1) {
      const msgNormal = new SymbolGlyphModifier($r('sys.symbol.envelope'));
      msgNormal.fontColor([HwColor.textSecondary]);
      const msgSelected = new SymbolGlyphModifier($r('sys.symbol.envelope_fill'));
      msgSelected.fontColor([HwColor.primary]);
      return new BottomTabBarStyle({ normal: msgNormal, selected: msgSelected }, '消息');
    }
    if (index === 2 && !this.isWearable) {
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
        if (this.activeTab === this.infoTabIndex() && this.selectedHomeName.length > 0) {
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
        // 家庭切换按钮已移除：选家庭改在「全部家庭」入口与设置里完成，
        // 顶栏只保留回正 + 刷新两个按钮，避免三个圆形按钮挤在一起。
        IconCircleButton({
          symbol: $r('sys.symbol.rectangle_split_2x1'),
          buttonSize: 36,
          iconSize: 18,
          onAction: (): void => {
            FeedbackLogService.recordOperation('UI', '列表回正');
            this.resetPaneScrolls();
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
      } else if (this.activeTab === this.infoTabIndex()) {
        // 信息页顶栏：回正 + 刷新
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

  // ==================== 首页：检索 / 房间 / 设备卡 ====================

  /**
   * 检索 + 排序入口卡。
   * 卡片本身承载输入框与排序菜单（ArkTS 不允许在 MaterialCard 尾随闭包后链式挂
   * bindSheet，所以改名 sheet 挂在外面包一层的 Column 上）。
   */

  @Builder
  homeSearchCard() {
    // 刻意不用自定义组件包装：搜索框此前反复「点不动」，自定义组件的材质承载层
    // 与外壳 onClick 都可能影响 TextInput 的焦点获取。这里退回最朴素的结构，
    // TextInput 直接暴露在最上层，没有任何中间层可能拦截触摸。
    Row({ space: HwSpace.sm }) {
      // 不放开头的搜索图标：图标占宽且与输入框的占位文案重复表意，
      // 去掉后输入区域更宽，视觉也更干净。
      Stack() {
        // 光感底衬：TextInput 不在系统材质的生效清单里，直接挂 systemMaterial 不渲染，
        // 所以用 ToggleType.Button 承载材质（真机实测只有 Toggle 家族稳定出材质）。
        // 不设任何颜色属性——透明色会抑制材质；底衬只负责画材质，不参与命中。
        Toggle({ type: ToggleType.Button, isOn: false })
          .width(LayoutPolicy.matchParent)
          .height(LayoutPolicy.matchParent)
          .borderRadius(HwRadius.pill)
          .clip(true)
          .enabled(false)
          .focusable(false)
          .accessibilityLevel('no')
          .hitTestBehavior(HitTestMode.None)
          .attributeModifier({
            applyNormalAttribute: (instance: ToggleAttribute): void => {
              applyMaterialCarrier(instance, true);
            }
          })

        TextInput({ text: this.searchKeyword, placeholder: '搜索设备名称、型号或房间' })
          .width('100%')
          .height(this.isWearable ? 32 : 36)
          .backgroundColor(Color.Transparent)
          .padding({ left: HwSpace.md, right: HwSpace.md })
          .fontSize(14)
          .placeholderFont({ size: 14 })
          .fontFamily(this.appFontFamily('搜索设备名称、型号或房间'))
          .fontColor(HwColor.textPrimary)
          .placeholderColor(HwColor.textSecondary)
          .caretColor(this.accent())
          .onChange((value: string) => {
            this.searchKeyword = value;
            this.updateFilteredDevices();
          })
      }
      .layoutWeight(1)
      .height(this.isWearable ? 32 : 36)

      if (this.searchKeyword.length > 0) {
        IconCircleButton({
          symbol: $r('sys.symbol.xmark'),
          buttonSize: 28,
          iconSize: 14,
          tint: HwColor.textSecondary,
          onAction: (): void => {
            this.clearSearch();
          }
        })
      }
      IconCircleButton({
        symbol: $r('sys.symbol.line_3_horizontal'),
        buttonSize: 32,
        iconSize: 16,
        tint: HwColor.textPrimary,
        onAction: (): void => {
          this.openSortSheet();
        }
      })
    }
    .width('100%')
    .height(44)
    // 不额外加左右内边距：设备卡片是「撑满内容区、无外边距」，检索行只有同样贴齐
    // 内容区左右边缘，输入框 + 排序按钮的总宽才与下方设备卡片等宽。
    .padding(0)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  roomChip(chip: RoomChip) {
    // 高亮类型与智能页的分类芯片保持一致：
    //   未选中 → 一层很淡的中性底，芯片始终有形状（分段控件的观感）
    //   选中   → 主题色实底 + 其上的 Toggle 材质承载层，得到「主题色玻璃」高亮
    // 尺寸由内容决定：Stack 宽度随内层 Row 的文字走，承载层用 matchParent 跟随，
    // 既不会塌成 0（那样材质画不出来、点击也收不到），也不会撑满整行。
    Column() {
      Stack() {
        // 用 matchParent 而不是 width('100%')：百分比在 Stack 内会按父级满宽解析，
        // 把 chip 撑成一整行；matchParent 按父级实测尺寸解析，随内容走。
        Row()
          .width(LayoutPolicy.matchParent)
          .height(LayoutPolicy.matchParent)
          .borderRadius(HwRadius.pill)
          .backgroundColor(this.selectedRoomKey === chip.key
            ? this.accent() : withAlpha(HwColor.textPrimary, 0.06))

        // 小尺寸芯片关掉材质自带投影：applyShadow 默认为 true，
        // 那层投影在芯片上看起来就像「按钮背后顶了一层影子」。
        MaterialCardLayer({ layerRadius: HwRadius.pill, layerShadow: false })

        // 内容层：触摸穿透到下层
        Row({ space: HwSpace.xs }) {
          Text(chip.name)
            .fontFamily(this.appFontFamily(chip.name))
            .fontWeight(this.appFontWeight())
            .fontSize(this.isWearable ? 12 : 14)
            .fontColor(this.selectedRoomKey === chip.key ? onAccentColor(this.accent()) : HwColor.textPrimary)
            .maxLines(1)
          Text(String(chip.count))
            .fontFamily(this.appFontFamily(String(chip.count)))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor(this.selectedRoomKey === chip.key ? onAccentColor(this.accent()) : HwColor.textSecondary)
            .opacity(0.85)
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: HwSpace.md, right: HwSpace.md })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
      }
      .height(32)
      .onClick((): void => {
        this.selectRoom(chip.key);
      })
    }
    .constraintSize({ minWidth: 64 })
  }

  /** 房间 chips 横向滚动条：房间多时靠滑动而不是换行，避免占掉首屏高度 */
  @Builder
  roomChipBar() {
    Scroll() {
      Row({ space: HwSpace.sm }) {
        // key 里带上主题色与选中态：ForEach 对同 key 会复用旧组件，
        // 只改 HwColor 属性不会让复用的组件换色，必须让 key 变化以强制重建。
        ForEach(this.roomChips, (chip: RoomChip) => {
          this.roomChip(chip)
        }, (chip: RoomChip) => `${chip.key}_${chip.count}_${this.selectedRoomKey === chip.key ? 1 : 0}_${this.accentColor}`)
      }
      .height(36)
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .width('100%')
    .height(36)
  }

  /** 设备卡上的快捷开关：开=主题绿，关闭或未知=灰，避免「不确定」被当成「已关」误触 */
  @Builder
  deviceQuickSwitch(device: XiaomiDevice) {
    IconCircleButton({
      symbol: $r('sys.symbol.power'),
      buttonSize: 34,
      iconSize: 17,
      tint: this.isQuickPowerOn(device) ? HwColor.online : HwColor.textSecondary,
      onAction: (): void => {
        // 卡片自身也有 onClick，用标记把这次点击从「进详情」里摘掉
        this.quickSwitchTapHandled = true;
        this.toggleQuickSwitch(device);
      }
    })
  }

  @Builder
  deviceCard(device: XiaomiDevice) {
    MaterialCard({
      cardSpace: 6,
      cardRadius: this.isWearable ? 16 : HwRadius.card,
      cardPadding: this.cardPadding(),
      cardHoverEffect: HoverEffect.Highlight,
      cardFocusable: true,
      // 菜单走长按：bindMenu 在触摸屏上由「点击」触发，点一下卡片就弹菜单是误触。
      cardOnLongPress: (): void => {
        this.openDeviceActionSheet(device);
      },
      cardOnClick: () => {
        if (this.quickSwitchTapHandled) {
          // 点的是快捷开关，不再进详情页
          this.quickSwitchTapHandled = false;
          return;
        }
        FeedbackLogService.recordOperation('UI', `点击设备 ${this.homeDisplayName(device)} (${device.did})`);
        if (this.isRouterDevice(device)) {
          this.showRouterWarningDialog(device.did);
        } else {
          this.pageInfos.pushPathByName('deviceDetail', new DeviceDetailRouteParam(device.did));
        }
      }
    }) {
      Row({ space: HwSpace.sm }) {
        // 设备图标统一用系统符号且不带底色：原先给图标垫了一层圆角色块，
        // 在浅色光感卡面上会显出多余的小方块，改为透明底直接放符号。
        SymbolGlyph(this.deviceSymbol(device))
          .fontSize(this.isWearable ? 30 : 34)
          .fontColor([this.accent()])
          .width(this.isWearable ? 32 : 38)
          .height(this.isWearable ? 32 : 38)

        Column({ space: 2 }) {
          Row({ space: HwSpace.xs }) {
            if (this.isFavoriteDevice(device.did)) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(12)
                .fontColor(['#F0A020'])
            }
            Text(this.homeDisplayName(device))
              .fontFamily(this.appFontFamily(this.homeDisplayName(device)))
              .fontWeight(this.appFontWeight())
              .fontSize(this.isWearable ? 13 : 15)
              .fontColor(HwColor.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: HwSpace.xs }) {
            Column()
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(device.online ? HwColor.online : '#B8BEC7')
            Text(this.deviceLocation(device).length > 0
              ? this.deviceLocation(device)
              : (device.online ? '在线' : '离线'))
              .fontFamily(this.appFontFamily(device.online ? '在线' : '离线'))
              .fontWeight(this.appFontWeight())
              .fontSize(this.isWearable ? 11 : 12)
              .fontColor(device.online ? HwColor.online : HwColor.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // quickPowerVersion 作为渲染依赖：属性后台解析完成后这里会重新求值
        if (this.quickPowerVersion >= 0 && this.hasQuickSwitch(device)) {
          this.deviceQuickSwitch(device)
        }

        if (this.isFavoriteDevice(device.did)) {
          IconCircleButton({
            symbol: $r('sys.symbol.star_fill'),
            buttonSize: 34,
            iconSize: 17,
            tint: '#F0A020',
            onAction: (): void => {
              this.toggleDeviceFavorite(device.did);
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 设备卡长按菜单：置顶 / 改名 / 详情，与卡片点击不冲突 */
  /** 设备卡片长按菜单的动作项：置顶 / 重命名 / 设备详情 */
  private deviceActions(device: XiaomiDevice): DeviceActionItem[] {
    return [
      {
        label: this.isFavoriteDevice(device.did) ? '取消置顶' : '置顶',
        icon: $r('sys.symbol.star_fill'),
        action: (): void => {
          this.toggleDeviceFavorite(device.did);
        }
      },
      {
        label: '重命名',
        icon: $r('sys.symbol.square_and_pencil'),
        action: (): void => {
          this.openRenameSheet(device.did);
        }
      },
      {
        label: '设备详情',
        icon: $r('sys.symbol.info_circle'),
        action: (): void => {
          this.pageInfos.pushPathByName('deviceDetail', new DeviceDetailRouteParam(device.did));
        }
      }
    ];
  }

  /**
   * 长按设备卡片弹出的动作面板。
   *
   * 用 ActionSheet 而不是 bindMenu：bindMenu 在触摸屏上默认由点击触发，
   * 无法区分点击与长按，会出现「点一下卡片就弹菜单」的误触。
   */
  /**
   * 长按设备弹出的操作面板。
   *
   * 用自定义 bindSheet 而不是系统 showActionSheet：
   * 系统面板的样式（分割线、白底）与全局沉浸光感风格不一致，无法定制；
   * 这里复用工程的 MaterialCard + IconCircleButton，与其它弹窗观感统一。
   */
  private openDeviceActionSheet(device: XiaomiDevice): void {
    this.actionDevice = device;
    this.showDeviceActionSheet = true;
  }

  private closeDeviceActionSheet(): void {
    this.showDeviceActionSheet = false;
    this.actionDevice = null;
  }

  /** 排序方式选择面板（自定义，替代系统 showActionSheet 以统一观感） */
  @Builder
  sortSheet() {
    MaterialSheetPanel() {
      Column({ space: HwSpace.md }) {
        Row({ space: HwSpace.sm }) {
          Column({ space: 4 }) {
            Text('设备排序')
              .fontFamily(this.appFontFamily('设备排序'))
              .fontWeight(this.appFontWeight())
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(HwColor.textPrimary)
            Text('选择首页设备列表的排列方式')
              .fontFamily(this.appFontFamily('选择首页设备列表的排列方式'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          IconCircleButton({
            symbol: $r('sys.symbol.xmark'),
            buttonSize: 32,
            iconSize: 16,
            tint: HwColor.textSecondary,
            onAction: (): void => {
              this.showSortSheet = false;
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        ForEach(SORT_MODES, (mode: SortModeOption) => {
          MaterialCard({
            cardDirection: FlexDirection.Row,
            cardSpace: HwSpace.sm,
            cardPadding: HwSpace.md,
            cardRadius: HwRadius.control,
            cardOnClick: (): void => {
              this.setDeviceSortMode(mode.key);
              this.showSortSheet = false;
            }
          }) {
            SymbolGlyph(this.deviceSortMode === mode.key
              ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
              .fontSize(18)
              .fontColor([this.deviceSortMode === mode.key ? this.accent() : HwColor.textSecondary])
            Text(mode.label)
              .fontFamily(this.appFontFamily(mode.label))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
              .layoutWeight(1)
          }
        }, (mode: SortModeOption) => `${mode.key}_${this.deviceSortMode === mode.key ? 1 : 0}_${this.accentColor}`)

        Blank().height(this.navigationBarHeight)
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg, top: HwSpace.lg })
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 长按设备后的操作面板内容（自定义，风格与全局光感统一） */
  @Builder
  deviceActionSheet() {
    MaterialSheetPanel() {
      Column({ space: HwSpace.md }) {
        Row({ space: HwSpace.sm }) {
          Column({ space: 4 }) {
            Text(this.actionDevice === null ? '' : this.homeDisplayName(this.actionDevice))
              .fontFamily(this.appFontFamily('设备操作'))
              .fontWeight(this.appFontWeight())
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(HwColor.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('长按设备卡片可再次唤起此面板')
              .fontFamily(this.appFontFamily('长按设备卡片可再次唤起此面板'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          IconCircleButton({
            symbol: $r('sys.symbol.xmark'),
            buttonSize: 32,
            iconSize: 16,
            tint: HwColor.textSecondary,
            onAction: (): void => {
              this.closeDeviceActionSheet();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.actionDevice !== null) {
          ForEach(this.deviceActions(this.actionDevice), (item: DeviceActionItem) => {
            MaterialCard({
              cardDirection: FlexDirection.Row,
              cardSpace: HwSpace.sm,
              cardPadding: HwSpace.md,
              cardRadius: HwRadius.control,
              cardOnClick: (): void => {
                this.closeDeviceActionSheet();
                item.action();
              }
            }) {
              SymbolGlyph(item.icon)
                .fontSize(18)
                .fontColor([HwColor.primary])
              Text(item.label)
                .fontFamily(this.appFontFamily(item.label))
                .fontWeight(this.appFontWeight())
                .fontSize(15)
                .fontColor(HwColor.textPrimary)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(15)
                .fontColor([HwColor.textSecondary])
            }
          }, (item: DeviceActionItem) => item.label)
        }

        Blank().height(this.navigationBarHeight)
      }
      .width('100%')
      .padding({ left: HwSpace.lg, right: HwSpace.lg, top: HwSpace.lg })
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 设备图标：统一走共享映射，保证与设备管理页完全一致 */
  private deviceSymbol(device: XiaomiDevice): Resource {
    return deviceSymbolFor(device.model, device.name);
  }
  /** 骨架屏：用真卡片形状的占位块顶住首屏高度，加载完切真列表不会跳版 */
  @Builder
  deviceGridSkeleton() {
    Column({ space: 10 }) {
      ForEach(this.skeletonPlaceholders, (item: number) => {
        MaterialCard({
          cardRadius: this.isWearable ? 16 : HwRadius.card,
          cardPadding: this.cardPadding(),
          cardMaterialEnabled: false,
          cardOpacity: 0.5
        }) {
          Row({ space: HwSpace.sm }) {
            Column()
              .width(this.isWearable ? 32 : 38)
              .height(this.isWearable ? 32 : 38)
              .borderRadius(HwRadius.control)
              .backgroundColor('#C3CEDC')
            Column({ space: HwSpace.sm }) {
              Column()
                .width('60%')
                .height(14)
                .borderRadius(4)
                .backgroundColor('#C3CEDC')
              Column()
                .width('38%')
                .height(12)
                .borderRadius(4)
                .backgroundColor('#D3DCE7')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }, (item: number) => `home_skeleton_${item}`)
    }
    .width('100%')
  }

  /** 一键关灯入口：放在首页而不是智能页，关灯是最高频的全屋批量操作 */
  @Builder
  lightsOffCard() {
    MaterialCard({
      cardRadius: this.isWearable ? 16 : HwRadius.card,
      cardDirection: FlexDirection.Row,
      cardSpace: HwSpace.sm,
      cardPadding: this.cardPadding(),
      cardAlignItems: ItemAlign.Center,
      cardEnabled: !this.lightsOffing,
      cardOpacity: this.lightsOffing ? 0.6 : 1,
      cardHoverEffect: HoverEffect.Highlight,
      cardFocusable: true,
      cardOnClick: () => {
        this.confirmLightsOff();
      }
    }) {
      SymbolGlyph($r('sys.symbol.moon_fill'))
        .fontSize(this.isWearable ? 17 : 19)
        .fontColor([HwColor.primary])
      Column({ space: 2 }) {
        Text(this.lightsOffing ? '正在关灯…' : '一键关灯')
          .fontFamily(this.appFontFamily('一键关灯'))
          .fontWeight(this.appFontWeight())
          .fontSize(this.isWearable ? 13 : 15)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
        Text('关闭当前家庭所有在线灯光设备')
          .fontFamily(this.appFontFamily('关闭当前家庭所有在线灯光设备'))
          .fontWeight(this.appFontWeight())
          .fontSize(this.isWearable ? 11 : 12)
          .fontColor(HwColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.lightsOffing) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(HwColor.primary)
      }
    }
  }

  /** 首页下拉刷新头：文案随 RefreshStatus 变化，给出「可以松手了」的反馈 */
  @Builder
  homeRefreshHeader() {
    Row({ space: HwSpace.xs }) {
      if (this.homeRefreshing) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(HwColor.primary)
      }
      Text(this.homeRefreshText)
        .fontFamily(this.appFontFamily(this.homeRefreshText))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontColor(HwColor.textSecondary)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 消息页内容：完整消息列表。
   *
   * 消息接口必须带具体数字 homeId，所以「全部家庭」时逐家庭拉取后合并去重，
   * 这样在全部家庭视图下也能看到消息，而不是直接空列表。
   */
  @Builder
  messagesPane() {
    Column() {
      if (this.isWideScreen) {
        this.tabHeader()
      }
      Scroll(this.messageScroller) {
        Column({ space: 10 }) {
          Blank().height(this.isWideScreen ? 12 : this.topOffset())

          Row({ space: HwSpace.sm }) {
            Text(this.unreadMessageCount() > 0 ? `${this.unreadMessageCount()} 条未读` : '全部已读')
              .fontFamily(this.appFontFamily('未读'))
              .fontWeight(this.appFontWeight())
              .fontSize(13)
              .fontColor(this.unreadMessageCount() > 0 ? HwColor.primary : HwColor.textSecondary)
              .layoutWeight(1)
            if (this.unreadMessageCount() > 0) {
              Text('全部已读')
                .fontFamily(this.appFontFamily('全部已读'))
                .fontWeight(this.appFontWeight())
                .fontSize(13)
                .fontColor(HwColor.primary)
                .padding({ left: HwSpace.sm, right: HwSpace.sm, top: 4, bottom: 4 })
                .onClick((): void => {
                  this.markAllMessagesRead();
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.messageLoading && this.cloudMessages.length === 0) {
            LoadingProgress()
              .width(48)
              .height(48)
              .margin({ top: 40 })
          } else if (this.cloudMessages.length === 0) {
            Text('暂无家庭消息')
              .fontFamily(this.appFontFamily('暂无家庭消息'))
              .fontWeight(this.appFontWeight())
              .fontSize(14)
              .fontColor(HwColor.textSecondary)
              .margin({ top: 40 })
          } else {
            ForEach(this.cloudMessages, (item: MijiaMessageItem) => {
              this.messageRow(item)
            }, (item: MijiaMessageItem) => item.messageId)
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
      .width('100%')
      // 不再同时设 height('100%') 与 layoutWeight(1)：两套尺寸来源互相冲突，
      // 交给 layoutWeight 填满 Column 的剩余空间即可（对齐 CLink 的 Scroll 结构）。
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  /** 单条消息行：未读左侧有主色圆点，点击标记已读 */
  @Builder
  messageRow(item: MijiaMessageItem) {
    Row({ space: HwSpace.sm }) {
      Circle()
        .width(8)
        .height(8)
        .fill(this.isMessageUnread(item) ? HwColor.primary : Color.Transparent)
      Column({ space: 2 }) {
        Row({ space: HwSpace.xs }) {
          Text(item.title)
            .fontFamily(this.appFontFamily(item.title))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontWeight(this.isMessageUnread(item) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(HwColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.formatMessageTime(item.time))
            .fontFamily(this.appFontFamily(this.formatMessageTime(item.time)))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor(HwColor.textSecondary)
            .maxLines(1)
        }
        .width('100%')
        if (item.desc.length > 0) {
          Text(item.desc)
            .fontFamily(this.appFontFamily(item.desc))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: HwSpace.sm, bottom: HwSpace.sm })
    .onClick((): void => {
      this.markMessageRead(item);
    })
  }

  @Builder
  homeEmptyHint() {
    Text(this.emptyDeviceHint())
      .fontFamily(this.appFontFamily(this.emptyDeviceHint()))
      .fontWeight(this.appFontWeight())
      .fontSize(14)
      .fontColor(HwColor.textSecondary)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: HwSpace.xl, bottom: HwSpace.xl })
  }

  @Builder
  homeTabContent() {
    Column({ space: 12 }) {
      Blank().height(this.isWideScreen ? 12 : this.topOffset())
      // 排序选择面板：同样挂在零尺寸 Column 上
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSortSheet, this.sortSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          blurStyle: sheetBlurStyle(),
        })

      // 长按操作面板：挂在零尺寸 Column 上，避免影响布局
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showDeviceActionSheet, this.deviceActionSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          blurStyle: sheetBlurStyle(),
        })

      // 概览区：检索 + 房间筛选 + 一键关灯。设置页的「首页概览卡片」开关关闭时
      // 整块收起，只留设备列表。
      if (this.showOverviewCards) {
        this.homeSearchCard()
        if (this.roomChips.length > 1) {
          this.roomChipBar()
        }
        this.lightsOffCard()
      }

      if (this.loading) {
        this.deviceGridSkeleton()
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
      if (!this.loading && this.errorMessage.length === 0 && this.devices.length > 0
        && this.filteredDevices.length === 0) {
        this.homeEmptyHint()
      }

      // 设备列表固定单排：分栏模式会让卡片变窄、文字被截断，按体验取舍只保留单排。
      // （设置里的分栏开关已一并移除，避免留下无效开关。）
      Column({ space: 10 }) {
        // key 里必须带上 accentColor：ForEach 复用同 key 的项，键不变就不会重建卡片，
        // 卡内写死的 HwColor.primary（图标、快捷开关）在切主题色后会停在旧色。
        ForEach(this.filteredDevices, (device: XiaomiDevice) => {
          this.deviceCard(device)
        }, (device: XiaomiDevice) =>
        `${device.did}_${this.favoriteDevices.indexOf(device.did) >= 0 ? 1 : 0}_${this.accentColor}`)
      }
      .width('100%')

      Blank()
        .height(this.isWideScreen ? 24 : BOTTOM_BAR_HEIGHT + BOTTOM_BAR_MARGIN + this.navigationBarHeight + 24)
    }
    .width('100%')
    .constraintSize({
      maxWidth: this.isWideScreen ? MAX_CONTENT_WIDTH : '100%'
    })
    .padding({ left: this.contentPadding(), right: this.contentPadding() })
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

  /** 排序模式 chip：选中态用主色底 + 白字，和房间 chip 视觉语言一致 */
  @Builder
  homeSortChip(mode: string, label: string) {
    // 高亮类型与智能页的分类芯片一致：未选中给一层淡中性底，选中为主题色玻璃高亮。
    // 不依赖 Toggle 的 isOn 表现选中，避免它内部选中态的渲染时机导致
    // 「第一次点击颜色不对、第二次才正常」。
    Stack() {
      Row()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(HwRadius.pill)
        .backgroundColor(this.deviceSortMode === mode
          ? this.accent() : withAlpha(HwColor.textPrimary, 0.06))

      // 小尺寸芯片关掉材质自带投影：applyShadow 默认为 true，
      // 那层投影在芯片上看起来就像「按钮背后顶了一层影子」。
      MaterialCardLayer({ layerRadius: HwRadius.pill, layerShadow: false })

      Text(label)
        .fontFamily(this.appFontFamily(label))
        .fontWeight(this.appFontWeight())
        .fontSize(this.isWearable ? 12 : 13)
        .fontColor(this.deviceSortMode === mode ? onAccentColor(this.accent()) : HwColor.textPrimary)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    .layoutWeight(1)
    .height(32)
    .onClick((): void => {
      this.setDeviceSortMode(mode);
    })
  }

  @Builder
  mineTabContent() {
    Column({ space: 14 }) {
      Blank().height(this.isWideScreen ? 12 : this.topOffset())

      MaterialCard({
        cardSpace: 12,
        cardRadius: HwRadius.card,
        cardPadding: HwSpace.lg,
        cardAlignItems: ItemAlign.Start
      }) {
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

      // 首页展示偏好：排序模式与置顶管理放在「我的」里，避免首页再塞一排控件
      MaterialCard({
        cardRadius: HwRadius.card,
        cardSpace: HwSpace.md,
        cardPadding: HwSpace.lg,
        cardAlignItems: ItemAlign.Start
      }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.rectangle_split_2x1'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Text('设备排序')
            .fontFamily(this.appFontFamily('设备排序'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          Text(this.deviceSortLabel())
            .fontFamily(this.appFontFamily(this.deviceSortLabel()))
            .fontWeight(this.appFontWeight())
            .fontSize(13)
            .fontColor(HwColor.textSecondary)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: HwSpace.sm }) {
          this.homeSortChip('smart', '在线优先')
          this.homeSortChip('name', '按名称')
          this.homeSortChip('room', '按房间')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider()
          .color('#14000000')

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Column({ space: 2 }) {
            Text('置顶管理')
              .fontFamily(this.appFontFamily('置顶管理'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text(this.favoriteDevices.length > 0
              ? `已置顶 ${this.favoriteDevices.length} 台设备`
              : '长按首页设备卡片可置顶')
              .fontFamily(this.appFontFamily('置顶管理'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '打开置顶管理');
          this.showFavoriteSheet = true;
        })

        Divider()
          .color('#14000000')

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Text('设备管理')
            .fontFamily(this.appFontFamily('设备管理'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入设备管理页');
          this.pageInfos.pushPathByName('deviceManage', new DeviceManageRouteParam());
        })
      }

      MaterialCard({
        cardRadius: HwRadius.card
      }) {
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
          SymbolGlyph($r('sys.symbol.bolt'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Column({ space: 2 }) {
            Text('智能')
              .fontFamily(this.appFontFamily('智能'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('本地智能、自动化与手动场景')
              .fontFamily(this.appFontFamily('本地智能、自动化与手动场景'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .padding(HwSpace.lg)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入智能页');
          this.getUIContext().getRouter().pushUrl({ url: 'pages/ScenePage' });
        })

        Divider()
          .color('#14000000')
          .margin({ left: HwSpace.lg, right: HwSpace.lg })

        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.leaf'))
            .fontSize(20)
            .fontColor([HwColor.textPrimary])
          Column({ space: 2 }) {
            Text('耗材中心')
              .fontFamily(this.appFontFamily('耗材中心'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('汇总各设备的滤芯、尘袋等耗材余量')
              .fontFamily(this.appFontFamily('汇总各设备的滤芯、尘袋等耗材余量'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([HwColor.textSecondary])
        }
        .width('100%')
        .padding(HwSpace.lg)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          FeedbackLogService.recordOperation('UI', '进入耗材中心');
          this.getUIContext().getRouter().pushUrl({ url: 'pages/ConsumablesPage' });
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
    MaterialCard({
      cardRadius: HwRadius.card,
      cardHoverEffect: HoverEffect.Highlight,
      cardOnClick: (): void => {
        $$.action();
      }
    }) {
      // 固定高度由内容容器自己撑开卡片，取代原先挂在卡片容器上的 .height()：
      // 尾随闭包形式的自定义组件后面不能链式调用属性，卡片高度只能从内容侧给。
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
      .height(INFO_CARD_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })
    }
  }

  @Builder
  infoDeviceRow(entry: InfoDeviceEntry) {
    MaterialCard({
      cardDirection: FlexDirection.Row,
      cardSpace: 12,
      cardPadding: HwSpace.md,
      cardRadius: HwRadius.control,
      cardOnClick: (): void => {
        this.openDeviceFromSheet(entry.did);
      }
    }) {
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
  }

  @Builder
  temperatureDeviceSheet() {
    MaterialSheetPanel() {
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
  }

  @Builder
  humidityDeviceSheet() {
    MaterialSheetPanel() {
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
  }

  @Builder
  pm25DeviceSheet() {
    MaterialSheetPanel() {
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
  }

  @Builder
  onDeviceSheet() {
    MaterialSheetPanel() {
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
  }

  @Builder
  excludeDeviceRow(device: XiaomiDevice) {
    MaterialCard({
      cardDirection: FlexDirection.Row,
      cardSpace: 12,
      cardPadding: HwSpace.md,
      cardRadius: HwRadius.control,
      cardOnClick: (): void => {
        this.setDeviceExcluded(device.did, !this.isDeviceExcluded(device.did));
      }
    }) {
      Column({ space: 2 }) {
        Text(this.homeDisplayName(device))
          .fontFamily(this.appFontFamily(this.homeDisplayName(device)))
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
        .selectedColor(this.accentOrPrimary())
        .onChange((checked: boolean) => {
          this.setDeviceExcluded(device.did, checked);
        })
    }
  }

  @Builder
  excludeDeviceSheet() {
    MaterialSheetPanel() {
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
              }, (device: XiaomiDevice) => `${device.did}_${this.accentColor}`)
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
  }

  /**
   * 改名 sheet。
   * 米家云端不提供改名接口，所以这里改的是本地显示名覆盖，
   * 用「恢复云端名称」把覆盖清掉，而不是把云端名写回去。
   */
  @Builder
  renameDeviceSheet() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text('设备重命名')
          .fontFamily(this.appFontFamily('设备重命名'))
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
          onAction: (): void => {
            this.showRenameSheet = false;
          }
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: HwSpace.lg, right: HwSpace.lg })

      Scroll() {
        Column({ space: HwSpace.md }) {
          MaterialCard({
            cardRadius: HwRadius.card,
            cardSpace: HwSpace.sm,
            cardPadding: HwSpace.lg,
            cardAlignItems: ItemAlign.Start
          }) {
            Text('设备名称')
              .fontFamily(this.appFontFamily('设备名称'))
              .fontWeight(this.appFontWeight())
              .fontSize(13)
              .fontColor(HwColor.textSecondary)
            TextInput({ text: this.renameValue, placeholder: '输入新的设备名称' })
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontFamily(this.appFontFamily('输入新的设备名称'))
              .fontColor(HwColor.textPrimary)
              .placeholderColor(HwColor.textSecondary)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .caretColor(HwColor.primary)
              .onChange((value: string) => {
                this.renameValue = value;
              })
            Text('仅在本机生效，不会修改米家云端名称')
              .fontFamily(this.appFontFamily('仅在本机生效，不会修改米家云端名称'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }

          Row({ space: HwSpace.sm }) {
            Button('恢复云端名称')
              .layoutWeight(1)
              .height(46)
              .fontSize(15)
              .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
              .fontColor(HwColor.textPrimary)
              .onClick(() => {
                this.resetDeviceRename();
              })
            Button('保存')
              .layoutWeight(1)
              .height(46)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(HwColor.primary)
              .fontColor(onAccentColor(this.accent()))
              .onClick(() => {
                this.saveDeviceRename();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
        .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  favoriteDeviceRow(device: XiaomiDevice) {
    MaterialCard({
      cardRadius: HwRadius.card,
      cardDirection: FlexDirection.Row,
      cardSpace: HwSpace.sm,
      cardPadding: HwSpace.md,
      cardAlignItems: ItemAlign.Center
    }) {
      Column({ space: 2 }) {
        Text(this.homeDisplayName(device))
          .fontFamily(this.appFontFamily(this.homeDisplayName(device)))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deviceLocation(device))
          .fontFamily(this.appFontFamily(this.deviceLocation(device)))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      IconCircleButton({
        symbol: $r('sys.symbol.star_fill'),
        buttonSize: 34,
        iconSize: 17,
        tint: '#F0A020',
        onAction: (): void => {
          this.toggleDeviceFavorite(device.did);
        }
      })
    }
  }

  /** 置顶管理：只列已置顶设备，取消后立即从本表消失，方便一次清干净 */
  @Builder
  favoriteDeviceSheet() {
    MaterialSheetPanel() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text(`已置顶设备（${this.favoriteDevices.length}）`)
            .fontFamily(this.appFontFamily(`已置顶设备（${this.favoriteDevices.length}）`))
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
            onAction: (): void => {
              this.showFavoriteSheet = false;
            }
          })
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .padding({ left: HwSpace.lg, right: HwSpace.lg })

        Text('置顶设备始终排在首页列表最前，不受排序模式影响')
          .fontFamily(this.appFontFamily('置顶设备始终排在首页列表最前，不受排序模式影响'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.textSecondary)
          .width('100%')
          .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 8 })

        if (this.favoriteDevices.length === 0) {
          Text('还没有置顶设备，长按首页设备卡片即可置顶')
            .fontFamily(this.appFontFamily('还没有置顶设备，长按首页设备卡片即可置顶'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
            .padding({ top: 24, bottom: 24 })
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.favoriteDeviceList(), (device: XiaomiDevice) => {
                this.favoriteDeviceRow(device)
              }, (device: XiaomiDevice) => `${device.did}_${this.accentColor}`)
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
  }

  @Builder
  familyHomeRow(home: XiaomiHome, selected: boolean) {    Row({ space: 10 }) {
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
    MaterialSheetPanel() {
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
              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardSpace: 10,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                // 「全部家庭」被选中时用主色描边标记当前项
                cardBorderWidth: this.selectedHomeId === ALL_HOMES_ID ? 1 : 0,
                cardBorderColor: this.selectedHomeId === ALL_HOMES_ID ? HwColor.primary : '#00000000',
                cardOnClick: (): void => {
                  this.selectAllHomesFromSheet();
                }
              }) {
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

      // sheet 挂在外层 Column；点击走卡片自己的 cardOnClick（外壳会吞掉外层 onClick）
      Column() {
        this.infoMetricCard({
          title: '温度',
          rangeText: this.temperatureRangeText,
          moreText: this.temperatureMoreText,
          action: (): void => {
            this.showTemperatureSheet = true;
          }
        })
      }
      .width('100%')
      .bindSheet($$this.showTemperatureSheet, this.temperatureDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
      })

      // sheet 挂在外层 Column；点击走卡片自己的 cardOnClick（外壳会吞掉外层 onClick）
      Column() {
        this.infoMetricCard({
          title: '湿度',
          rangeText: this.humidityRangeText,
          moreText: this.humidityMoreText,
          action: (): void => {
            this.showHumiditySheet = true;
          }
        })
      }
      .width('100%')
      .bindSheet($$this.showHumiditySheet, this.humidityDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
      })

      // sheet 挂在外层 Column；点击走卡片自己的 cardOnClick（外壳会吞掉外层 onClick）
      Column() {
        this.infoMetricCard({
          title: 'PM2.5',
          rangeText: this.pm25RangeText,
          moreText: this.pm25MoreText,
          action: (): void => {
            this.showPm25Sheet = true;
          }
        })
      }
      .width('100%')
      .bindSheet($$this.showPm25Sheet, this.pm25DeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
      })

      // sheet 挂在外层 Column；点击走卡片自己的 cardOnClick（外壳会吞掉外层 onClick）
      Column() {
        this.infoMetricCard({
          title: '开启中',
          rangeText: `${this.onDeviceCount} 台`,
          moreText: '',
          action: (): void => {
            this.showOnSheet = true;
          }
        })
      }
      .width('100%')
      .bindSheet($$this.showOnSheet, this.onDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
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
      // 不再同时设 height('100%') 与 layoutWeight(1)：两套尺寸来源互相冲突，
      // 交给 layoutWeight 填满 Column 的剩余空间即可（对齐 CLink 的 Scroll 结构）。
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
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
      // 不再同时设 height('100%') 与 layoutWeight(1)：两套尺寸来源互相冲突，
      // 交给 layoutWeight 填满 Column 的剩余空间即可（对齐 CLink 的 Scroll 结构）。
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
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
      this.onTabChanged(index);
    })
  }

  @Builder
  wearableContent() {
    Column() {
      if (this.activeTab === 0) {
        this.homePane()
      } else if (this.activeTab === this.messagesTabIndex()) {
        this.messagesPane()
      } else {
        this.minePane()
      }
      Row() {
        this.wearableTabButton(0)
        this.wearableTabButton(1)
        this.wearableTabButton(2)
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

  /**
   * 当前主题色。
   *
   * 为什么读 this.accentColor 而不是直接用 HwColor.primary：
   * HwColor 是模块级对象，改属性不会让页面重建；只有表达式引用了
   * @StorageProp('accentColor') 才会建立依赖，切色时页面重新求值、取到新色。
   * 直接把 HwColor.primary 写在 .backgroundColor() 里会停留在旧色。
   */
  private accent(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  /**
   * 底部 HdsTab 悬浮栏的流光颜色。
   *
   * 这个光由 HdsTabs 自己画（`barFloatingStyle.lightColor`），不归我们的材质管，
   * 所以必须单独下发一次；关掉「主题色流光」时回到系统默认的白光。
   */
  private tabLightColor(): ResourceColor {
    const light = pressLightColor(this.pressGlowSwitch, this.accentColor);
    return light.length > 0 ? light : Color.White;
  }

  /**
   * Tab 切换（绑定 HdsTabs.onChange，切换动画结束后触发）。
   *
   * 下标：0 首页 / 1 消息 / 2 信息 / 3 我的（穿戴设备无信息页：0 首页 / 1 消息 / 2 我的）。
   *
   * 三处写法都是刻意的，对照 CLink 的同类实现：
   *
   * 1. **只在 onChange 里改 activeTab，不挂 onSelected。**
   *    `HdsTabs({ index: this.activeTab })` 是受控属性，而官方文档写明
   *    「构造的状态变量被动态修改」本身就会再触发一次切换。在动画**开始时**
   *    （onSelected）改它，会让目标页在动画中途重新布局，紧随其后的滚动指令被丢弃。
   *    CLink 完全不挂 onSelected，这是它与本仓库最大的差异。
   * 2. **先切状态、再复位滚动**，顺序与 CLink 一致。
   * 3. **同步复位、一次复位全部四个 Scroller**：不依赖「当前哪个 pane 已完成布局」，
   *    也不用延时。CLink 就是这么做的；延时一帧反而正好落在重新布局之后。
   */
  private onTabChanged(index: number): void {
    FeedbackLogService.recordOperation('UI', `切换标签 ${index}`);
    this.activeTab = index;
    this.resetPaneScrolls();
    if (this.isWearable) {
      if (index === 1) {
        // 进消息页才拉消息，避免首屏多打一次云端接口
        this.loadCloudMessages();
      }
      if (index === 2) {
        this.loadData(true, true);
        this.loadAccount();
      }
      return;
    }
    if (index === 1) {
      this.loadCloudMessages();
    }
    if (index === 2) {
      this.refreshInfoOnEnter();
      this.startInfoRefreshTimer();
    } else {
      this.stopInfoRefreshTimer();
    }
    if (index === 3) {
      this.loadData(true, true);
      this.loadAccount();
    }
  }

  /**
   * 把四个 pane 的滚动位置一起复位到顶部。
   *
   * 逐个独立 try/catch：尚未挂载的 pane 调用 scrollEdge 会抛异常，属正常情况，
   * 不应影响其余几个 —— CLink 也是这么写的。
   */
  private resetPaneScrolls(): void {
    const scrollers: Scroller[] = [
      this.homeScroller, this.messageScroller, this.infoScroller, this.mineScroller
    ];
    for (let i = 0; i < scrollers.length; i++) {
      try {
        scrollers[i].scrollEdge(Edge.Top);
      } catch (err) {
      }
    }
  }

  build() {
    HdsNavigation(this.pageInfos) {
      Stack({ alignContent: Alignment.TopStart }) {
        // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
        AccentColorSentinel()
        AppBackground()

        if (this.isWideScreen) {
          HdsTabs({
            controller: this.tabsController,
            index: this.activeTab
          }) {
            TabContent() { this.homePane() }.tabBar(this.tabItem(0))
            TabContent() { this.messagesPane() }.tabBar(this.tabItem(1))
            TabContent() { this.infoPane() }.tabBar(this.tabItem(2))
            TabContent() { this.minePane() }.tabBar(this.tabItem(3))
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
          // 刻意不挂 onSelected：`index: this.activeTab` 是受控属性，
          // 在动画开始时改它会让 HdsTabs 再触发一次切换、目标页重新布局，
          // 滚动指令随之被丢弃。详见 onTabChanged 的说明。
          .onChange((index: number) => {
            this.onTabChanged(index);
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
            TabContent() { this.messagesPane() }.tabBar(this.tabBarStyle(1))
            TabContent() { this.infoPane() }.tabBar(this.tabBarStyle(2))
            TabContent() { this.minePane() }.tabBar(this.tabBarStyle(3))
          }
          .width('100%')
          .height('100%')
          .barPosition(BarPosition.End)
          .barOverlap(true)
          .scrollable(false)
          .animationDuration(this.homeSmoothSwitch ? 300 : 0)
          // 刻意不挂 onSelected：`index: this.activeTab` 是受控属性，
          // 在动画开始时改它会让 HdsTabs 再触发一次切换、目标页重新布局，
          // 滚动指令随之被丢弃。详见 onTabChanged 的说明。
          .onChange((index: number) => {
            this.onTabChanged(index);
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
            lightColor: this.tabLightColor()
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
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
      })
      .bindSheet($$this.showExcludeSheet, this.excludeDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
        onDisappear: () => {
          this.refreshInfoOnEnter();
        }
      })
      .bindSheet($$this.showFavoriteSheet, this.favoriteDeviceSheet(), {
        height: SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
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
          subTitle: this.activeTab === this.infoTabIndex() && this.selectedHomeName.length > 0
            ? this.selectedHomeName
            : undefined
        },
        // 菜单只保留「刷新」：选择家庭与排除设备入口已从顶栏移除
        menu: this.activeTab === 0 ? {
          value: [
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
        } : this.activeTab === this.messagesTabIndex() ? {
          value: [
            {
              content: {
                label: '刷新消息',
                icon: $r('sys.symbol.arrow_counterclockwise'),
                isEnabled: !this.messageLoading,
                action: () => {
                  FeedbackLogService.recordOperation('UI', '刷新家庭消息');
                  this.loadCloudMessages();
                }
              }
            }
          ]
        } : this.activeTab === this.infoTabIndex() ? {
          value: [
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
