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

import { AbilityConstant, common, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uiAppearance, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { xiaomiOAuthSession } from '../services/XiaomiOAuthSession';
import { DeviceNotificationService } from '../services/DeviceNotificationService';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { loadCustomFonts } from '../utils/CustomFonts';
import { applyAppTheme, CARD_TINT_STORAGE, CUSTOM_ACCENT_FULL_ACCESS_STORAGE, DARK_MODE_DARK, DARK_MODE_LIGHT, DARK_MODE_PREF_STORAGE, DARK_MODE_SYSTEM, DEFAULT_ACCENT_KEY, isPresetAccentKey, PRESS_GLOW_STORAGE, resolveAccentColor } from '../utils/DesignTokens';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppSettingsStore.init(this.context);
    // 配色模式统一在读到设置之后再下发（见下方 resolveColorMode），这里不再先设一次
    FeedbackLogService.init(this.context);
    const hideOfflineDevices = AppSettingsStore.getBoolean('hideOfflineDevices', false);
    const selectedHomeId = AppSettingsStore.getString('selectedHomeId', '');
    const selectedHomeName = AppSettingsStore.getString('selectedHomeName', '');
    const backgroundImage = AppSettingsStore.getString('backgroundImage', '');
    const defaultHomeTab = AppSettingsStore.getString('defaultHomeTab', 'home');
    const infoRefreshInterval = AppSettingsStore.getString('infoRefreshInterval', '30');
    let autoMultiColumn = AppSettingsStore.getBoolean('autoMultiColumn', false);
    const temperatureFahrenheit = AppSettingsStore.getBoolean('temperatureFahrenheit', false);
    const temperatureShowUnit = AppSettingsStore.getBoolean('temperatureShowUnit', false);
    const infoExcludedDevices = AppSettingsStore.getStringArray('infoExcludedDevices', []);
    const infoShowMoreContent = AppSettingsStore.getBoolean('infoShowMoreContent', true);
    const showOverviewCards = AppSettingsStore.getBoolean('showOverviewCards', true);
    const sortDevicesByRoom = AppSettingsStore.getBoolean('sortDevicesByRoom', false);
    const fontMode = AppSettingsStore.getString('fontMode', 'system');
    const fontFamilyEn = AppSettingsStore.getString('fontFamilyEn', 'system');
    const fontFamilyZh = AppSettingsStore.getString('fontFamilyZh', 'system');
    const fontSizeMode = AppSettingsStore.getString('fontSizeMode', 'system');
    const fontSizeValue = AppSettingsStore.getNumber('fontSizeValue', 16);
    const fontWeightMode = AppSettingsStore.getString('fontWeightMode', 'system');
    const fontWeightValue = AppSettingsStore.getNumber('fontWeightValue', 400);
    const immersiveLightEnabled = AppSettingsStore.getBoolean('immersiveLightEnabled', true);
    const cardsFromTop = AppSettingsStore.getBoolean('cardsFromTop', true);
    let homeSmoothSwitch = AppSettingsStore.getBoolean('homeSmoothSwitch', false);
    const customFonts = AppSettingsStore.getStringArray('customFonts', []);
    const is2in1 = deviceInfo.deviceType === '2in1';
    const isWearable = deviceInfo.deviceType === 'wearable';
    const isLargeScreen = deviceInfo.deviceType === 'tablet' || is2in1;
    let dualColumnMode = AppSettingsStore.getBoolean('dualColumnMode', isLargeScreen);
    if (!AppSettingsStore.has('dualColumnMode')) {
      AppSettingsStore.setBoolean('dualColumnMode', dualColumnMode);
    }
    if (!AppSettingsStore.has('autoMultiColumn')) {
      AppSettingsStore.setBoolean('autoMultiColumn', autoMultiColumn);
    }
    let pcLayoutEnabled = AppSettingsStore.getBoolean('pcLayoutEnabled', is2in1);
    if (!AppSettingsStore.has('pcLayoutEnabled')) {
      AppSettingsStore.setBoolean('pcLayoutEnabled', pcLayoutEnabled);
    }
    if (pcLayoutEnabled && autoMultiColumn) {
      autoMultiColumn = false;
      AppSettingsStore.setBoolean('autoMultiColumn', false);
    }
    if (pcLayoutEnabled && homeSmoothSwitch) {
      homeSmoothSwitch = false;
      AppSettingsStore.setBoolean('homeSmoothSwitch', false);
    }
    AppStorage.setOrCreate('hideOfflineDevices', hideOfflineDevices);
    AppStorage.setOrCreate('showOverviewCards', showOverviewCards);
    AppStorage.setOrCreate('selectedHomeId', selectedHomeId);
    AppStorage.setOrCreate('selectedHomeName', selectedHomeName);
    AppStorage.setOrCreate('backgroundImage', backgroundImage);
    AppStorage.setOrCreate('defaultHomeTab', defaultHomeTab);
    AppStorage.setOrCreate('infoRefreshInterval', infoRefreshInterval);
    AppStorage.setOrCreate('dualColumnMode', dualColumnMode);
    AppStorage.setOrCreate('autoMultiColumn', autoMultiColumn);
    AppStorage.setOrCreate('pcLayoutEnabled', pcLayoutEnabled);
    AppStorage.setOrCreate('temperatureFahrenheit', temperatureFahrenheit);
    AppStorage.setOrCreate('temperatureShowUnit', temperatureShowUnit);
    AppStorage.setOrCreate('infoExcludedDevices', infoExcludedDevices);
    AppStorage.setOrCreate('infoDeviceOptions', []);
    AppStorage.setOrCreate('infoShowMoreContent', infoShowMoreContent);
    AppStorage.setOrCreate('sortDevicesByRoom', sortDevicesByRoom);
    AppStorage.setOrCreate('fontMode', fontMode);
    AppStorage.setOrCreate('fontFamilyEn', fontFamilyEn);
    AppStorage.setOrCreate('fontFamilyZh', fontFamilyZh);
    AppStorage.setOrCreate('fontSizeMode', fontSizeMode);
    AppStorage.setOrCreate('fontSizeValue', fontSizeValue);
    AppStorage.setOrCreate('fontWeightMode', fontWeightMode);
    AppStorage.setOrCreate('fontWeightValue', fontWeightValue);
    AppStorage.setOrCreate('immersiveLightEnabled', immersiveLightEnabled);
    AppStorage.setOrCreate('cardsFromTop', cardsFromTop);
    AppStorage.setOrCreate('homeSmoothSwitch', homeSmoothSwitch);
    AppStorage.setOrCreate('customFonts', customFonts);
    // 这两个开关要在 applyAppTheme 之前落进 AppStorage：
    // applyAppTheme 会读它们来决定卡片底色与页面背景是否沾主题色。
    const cardTintEnabled = AppSettingsStore.getBoolean(CARD_TINT_STORAGE, false);
    const customAccentFullAccess = AppSettingsStore.getBoolean(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, false);
    AppStorage.setOrCreate(CARD_TINT_STORAGE, cardTintEnabled);
    AppStorage.setOrCreate(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, customAccentFullAccess);
    // 主题色流光开关：材质承载层构造流光时要读它，必须在首帧渲染前就位
    AppStorage.setOrCreate(PRESS_GLOW_STORAGE,
      AppSettingsStore.getBoolean(PRESS_GLOW_STORAGE, true));
    // 深色模式偏好（三态：跟随系统 / 浅色 / 深色）。旧键迁移在这里做，
    // 保证后续读到的都是新键；AppStorage 也写一份供设置页双向绑定。
    const darkModePref = EntryAbility.resolveDarkModePref();
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, darkModePref);
    const darkModeEnabled = EntryAbility.resolveDarkMode(this.context, darkModePref);
    // 平台层的配色也要跟应用内保持一致，否则系统控件与自绘颜色会一深一浅
    try {
      this.context.getApplicationContext().setColorMode(EntryAbility.resolveColorMode(darkModePref));
    } catch (err) {
    }
    // 主题色在启动时就要生效：否则首屏会用默认蓝，切到其它页面才变。
    const accentKey = EntryAbility.resolveAccentKey();
    const accentCustom = AppSettingsStore.getString('accentCustom', '');
    const accentColor = resolveAccentColor(accentKey, accentCustom);
    AppStorage.setOrCreate('accentKey', accentKey);
    AppStorage.setOrCreate('accentCustom', accentCustom);
    AppStorage.setOrCreate('accentColor', accentColor);
    applyAppTheme(darkModeEnabled, accentColor);
    const fontSizeScaleMode = AppStorage.get<string>('fontSizeMode') as string;
    const fontSizeScaleValue = AppStorage.get<number>('fontSizeValue') as number;
    let fontSizeScale: number = 1;
    if (fontSizeScaleMode === 'custom') {
      fontSizeScale = fontSizeScaleValue / 16;
    } else {
      try {
        fontSizeScale = uiAppearance.getFontScale();
      } catch (err) {
        fontSizeScale = 1;
      }
    }
    try {
      this.context.getApplicationContext().setFontSizeScale(fontSizeScale);
    } catch (err) {
    }
    AppStorage.setOrCreate('dualColumnRestore', false);
    AppStorage.setOrCreate('isLargeScreen', isLargeScreen);
    AppStorage.setOrCreate('is2in1', is2in1);
    AppStorage.setOrCreate('isWearable', isWearable);
    AppStorage.setOrCreate('homeSelectionVersion', 0);
    AppStorage.setOrCreate('isDarkMode', darkModeEnabled);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    FeedbackLogService.recordOperation('SYSTEM', '应用启动 onCreate');
    const notificationService = new DeviceNotificationService(xiaomiDataService.getEventBus());
    notificationService.start();
    // 冷启动经通知点入时，解析 want 中的设备 did 供首页直达详情
    this.handleNotificationWant(want);
  }

  /** 解析通知 wantAgent 携带的设备 did，写入 AppStorage 由首页消费 */
  private handleNotificationWant(want: Want): void {
    try {
      const params = want.parameters;
      if (params === undefined) {
        return;
      }
      const raw: Object | undefined = params['deviceDid'];
      if (typeof raw === 'string' && (raw as string).length > 0) {
        AppStorage.setOrCreate('pendingDeviceDetailDid', raw as string);
      }
    } catch (err) {
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    FeedbackLogService.recordOperation('SYSTEM', '应用退出 onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    try {
      const customFonts = AppStorage.get<string[]>('customFonts') as string[];
      loadCustomFonts(this.context.filesDir, customFonts);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'load custom fonts failed');
    }

    const mainWindow = windowStage.getMainWindowSync();
    this.mainWindow = mainWindow;
    mainWindow.setWindowLayoutFullScreen(true).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'setWindowLayoutFullScreen failed, %{public}s', err.message);
    });
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: '#FFFFFF',
      navigationBarContentColor: '#FFFFFF'
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'setWindowSystemBarProperties failed, %{public}s', err.message);
    });

    const loadPage = (page: string): void => {
      windowStage.loadContent(page, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
        // 窗口就绪后再设置背景色，避免窗口状态异常导致 JsError 崩溃
        try {
          mainWindow.setWindowBackgroundColor('#DCEAF8');
        } catch (err) {
          hilog.error(DOMAIN, 'testTag', 'setWindowBackgroundColor failed, %{public}s', (err as Error).message);
        }
        this.publishWindowInsets(mainWindow);
        this.registerWindowSizeListener(mainWindow);
        mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions): void => {
          this.publishWindowInsets(mainWindow);
        });
      });
    };

    xiaomiDataService.isAuthenticated()
      .then((authenticated: boolean): void => {
        loadPage(authenticated ? 'pages/HomePage' : 'pages/LoginPage');
      })
      .catch((err: Error): void => {
        hilog.error(DOMAIN, 'testTag', 'check auth failed, %{public}s', err.message);
        loadPage('pages/LoginPage');
      });
  }

  private publishWindowInsets(win: window.Window): void {
    try {
      const uiContext = win.getUIContext();
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const statusBarHeight = uiContext.px2vp(systemArea.topRect.height);
      const navigationBarHeight = Math.max(
        uiContext.px2vp(systemArea.bottomRect.height),
        uiContext.px2vp(navArea.bottomRect.height)
      );
      AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
      AppStorage.setOrCreate('navigationBarHeight', navigationBarHeight);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'unknown error';
      hilog.error(DOMAIN, 'testTag', 'publishWindowInsets failed, %{public}s', message);
    }
  }

  /**
   * 注册窗口尺寸与系统断点监听（PC/2in1 窗口拖拽、旋转、分屏时布局随动）。
   * 必须在 loadContent 回调内调用，此时窗口已完成布局。
   * - screenWidthVp / screenHeightVp：窗口物理像素转 vp
   * - currentWidthBreakpoint / currentHeightBreakpoint：系统断点枚举
   */
  private registerWindowSizeListener(win: window.Window): void {
    try {
      const uiContext = win.getUIContext();
      const initRect = win.getWindowProperties().windowRect;
      AppStorage.setOrCreate('screenWidthVp', uiContext.px2vp(initRect.width));
      AppStorage.setOrCreate('screenHeightVp', uiContext.px2vp(initRect.height));
      AppStorage.setOrCreate('currentWidthBreakpoint', uiContext.getWindowWidthBreakpoint());
      AppStorage.setOrCreate('currentHeightBreakpoint', uiContext.getWindowHeightBreakpoint());
      win.on('windowSizeChange', (size: window.Size): void => {
        AppStorage.setOrCreate('screenWidthVp', uiContext.px2vp(size.width));
        AppStorage.setOrCreate('screenHeightVp', uiContext.px2vp(size.height));
        AppStorage.setOrCreate('currentWidthBreakpoint', uiContext.getWindowWidthBreakpoint());
        AppStorage.setOrCreate('currentHeightBreakpoint', uiContext.getWindowHeightBreakpoint());
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'unknown error';
      hilog.error(DOMAIN, 'testTag', 'registerWindowSizeListener failed, %{public}s', message);
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    if (this.mainWindow) {
      this.mainWindow.off('windowSizeChange');
      this.mainWindow.off('avoidAreaChange');
      this.mainWindow = null;
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    // 热启动经通知点入时同样解析设备 did
    this.handleNotificationWant(want);
    xiaomiOAuthSession.handleCallback(want).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'oauth callback error, %{public}s', err.message);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色变化时按偏好重新解析：偏好是「跟随系统」就跟着变，否则维持用户选择。
    // 本回调会被 setColorMode 同步触发，存储未就绪时按默认值处理，避免进程崩溃。
    const darkModePref = EntryAbility.resolveDarkModePref();
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, darkModePref);
    const darkModeEnabled = EntryAbility.resolveDarkMode(this.context, darkModePref);
    // 开关本身不变，但 AppStorage 可能尚未就绪（本回调会被 setColorMode 同步触发），
    // 补一次写入，避免 applyAppTheme 读到默认值把卡片/背景染色算错
    AppStorage.setOrCreate(CARD_TINT_STORAGE,
      AppSettingsStore.getBoolean(CARD_TINT_STORAGE, false));
    AppStorage.setOrCreate(CUSTOM_ACCENT_FULL_ACCESS_STORAGE,
      AppSettingsStore.getBoolean(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, false));
    AppStorage.setOrCreate(PRESS_GLOW_STORAGE,
      AppSettingsStore.getBoolean(PRESS_GLOW_STORAGE, true));
    // 同样要把已保存的主题色传入，否则系统深浅色变化会把背景染色重置掉
    const accentColor = resolveAccentColor(
      EntryAbility.resolveAccentKey(),
      AppSettingsStore.getString('accentCustom', ''));
    applyAppTheme(darkModeEnabled, accentColor);
    AppStorage.setOrCreate('isDarkMode', darkModeEnabled);
  }

  /**
   * 读主题色 key，顺带兜底。
   *
   * 只接受「内置预设 key」或 `custom`。其余一律归位到默认主题色并写回存储：
   * 历史版本或异常写入可能留下一个已经不存在的 key（例如曾经短暂存在过的
   * `default`），那时设置页会**一个色块都不显示选中**，看起来像主题色丢了。
   */
  private static resolveAccentKey(): string {
    const stored = AppSettingsStore.getString('accentKey', DEFAULT_ACCENT_KEY);
    if (stored === 'custom' || isPresetAccentKey(stored)) {
      return stored;
    }
    AppSettingsStore.setString('accentKey', DEFAULT_ACCENT_KEY);
    return DEFAULT_ACCENT_KEY;
  }

  /**
   * 读深色模式偏好，顺带做一次旧键迁移。
   *
   * 1.1.0/1.1.1 存的是布尔 `darkModeEnabled`：它一旦被拨动就永久生效、
   * 再也没法回到「跟随系统」，这正是本次要修的问题。升级时把它映射成
   * 'dark' / 'light' 并删掉旧键；没有旧键就是全新安装，默认跟随系统。
   */
  private static resolveDarkModePref(): string {
    try {
      const stored = AppSettingsStore.getString(DARK_MODE_PREF_STORAGE, '');
      if (stored === DARK_MODE_SYSTEM || stored === DARK_MODE_LIGHT || stored === DARK_MODE_DARK) {
        return stored;
      }
      if (AppSettingsStore.has('darkModeEnabled')) {
        const legacy = AppSettingsStore.getBoolean('darkModeEnabled', false);
        const migrated = legacy ? DARK_MODE_DARK : DARK_MODE_LIGHT;
        AppSettingsStore.setString(DARK_MODE_PREF_STORAGE, migrated);
        AppSettingsStore.delete('darkModeEnabled');
        return migrated;
      }
    } catch (err) {
    }
    return DARK_MODE_SYSTEM;
  }

  /**
   * 当前是否使用深色模式。
   * 偏好为「跟随系统」时读系统，其余按偏好取值。
   */
  private static resolveDarkMode(context: common.UIAbilityContext, pref: string): boolean {
    if (pref === DARK_MODE_DARK) {
      return true;
    }
    if (pref === DARK_MODE_LIGHT) {
      return false;
    }
    return EntryAbility.systemDarkMode(context);
  }

  /** 读系统当前的深色模式 */
  private static systemDarkMode(context: common.UIAbilityContext): boolean {
    try {
      const config = context.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  /**
   * 平台配色模式。
   *
   * 偏好为「跟随系统」时下发 COLOR_MODE_NOT_SET —— 把配色权交还系统，
   * 系统切深浅色应用才会跟着走；选了明确值才固定下来。
   */
  private static resolveColorMode(pref: string): ConfigurationConstant.ColorMode {
    if (pref === DARK_MODE_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (pref === DARK_MODE_LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    FeedbackLogService.recordOperation('SYSTEM', '应用回到前台 onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    FeedbackLogService.recordOperation('SYSTEM', '应用退到后台 onBackground');
  }
}
