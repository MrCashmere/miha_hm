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

import { router } from '@kit.ArkUI';
import { HwColor, HwRadius, HwSpace, reloadAppTheme, resolvePageBackground } from '../utils/DesignTokens';
// 卡片已全部改为 MaterialCard 承载光感，旧的修饰器不再需要；
// sheet 仍走同一套系统材质，所以保留这两个。
import { sheetSystemMaterial, sheetBlurStyle } from '../utils/SystemMaterial';
import { MaterialCard, MaterialSheetPanel, AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppBackground } from '../components/AppBackground';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { InfoExcludeOption } from '../models/XiaomiHomeModels';
import { FeedbackLogService } from '../services/FeedbackLogService';

interface InfoRefreshOption {
  label: string;
  seconds: string;
}

const INFO_REFRESH_OPTIONS: InfoRefreshOption[] = [
  { label: '每5秒', seconds: '5' },
  { label: '每15秒', seconds: '15' },
  { label: '每30秒', seconds: '30' },
  { label: '每1分钟', seconds: '60' },
  { label: '每5分钟', seconds: '300' },
  { label: '每10分钟', seconds: '600' }
];

@Entry
@Component
struct SettingsPage {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
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
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('isLargeScreen') isLargeScreen: boolean = false;
  @StorageProp('is2in1') is2in1: boolean = false;
  @StorageLink('pcLayoutEnabled') pcLayoutEnabled: boolean = false;
  @StorageProp('currentWidthBreakpoint') @Watch('onBreakpointChange')
  widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;
  @State isWideScreen: boolean = false;
  @StorageLink('hideOfflineDevices') hideOfflineDevices: boolean = false;
  @StorageLink('dualColumnMode') dualColumnMode: boolean = false;
  @StorageLink('autoMultiColumn') autoMultiColumn: boolean = false;
  @StorageLink('homeSmoothSwitch') homeSmoothSwitch: boolean = false;
  @StorageLink('temperatureFahrenheit') temperatureFahrenheit: boolean = false;
  @StorageLink('temperatureShowUnit') temperatureShowUnit: boolean = false;
  @StorageLink('backgroundImage') wallpaperImage: string = '';
  @StorageLink('infoExcludedDevices') infoExcludedDevices: string[] = [];
  @StorageProp('infoDeviceOptions') infoDeviceOptions: InfoExcludeOption[] = [];
  @StorageLink('infoShowMoreContent') infoShowMoreContent: boolean = true;
  @StorageLink('sortDevicesByRoom') sortDevicesByRoom: boolean = false;
  @StorageLink('defaultHomeTab') defaultHomeTab: string = 'home';
  @StorageLink('infoRefreshInterval') infoRefreshInterval: string = '30';
  /** 首页概览区开关：关闭后首页只显示设备列表 */
  @StorageLink('showOverviewCards') showOverviewCards: boolean = true;
  @State clearMessage: string = '';
  @State showDefaultTabSheet: boolean = false;
  @State showRefreshIntervalSheet: boolean = false;
  @State showExcludeSheet: boolean = false;

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
    FeedbackLogService.setCurrentPage('设置页');
    this.onBreakpointChange();
    FeedbackLogService.recordOperation('PAGE',
      `设置项: 隐藏离线=${this.hideOfflineDevices} 分栏=${this.dualColumnMode} 自动多栏=${this.autoMultiColumn} ` +
      `平滑切换=${this.homeSmoothSwitch} 华氏温度=${this.temperatureFahrenheit} 显示单位=${this.temperatureShowUnit} ` +
      `显示更多内容=${this.infoShowMoreContent} 按房间排序=${this.sortDevicesByRoom} 默认标签=${this.defaultHomeTab} ` +
      `刷新间隔=${this.infoRefreshInterval} 排除设备数=${this.infoExcludedDevices.length}`);
  }

  onBreakpointChange(): void {
    this.isWideScreen = this.widthBp === WidthBreakpoint.WIDTH_LG ||
      this.widthBp === WidthBreakpoint.WIDTH_XL;
  }

  clearAllSettings(): void {
    AppSettingsStore.delete('hideOfflineDevices');
    AppSettingsStore.delete('selectedHomeId');
    AppSettingsStore.delete('selectedHomeName');
    AppSettingsStore.delete('dualColumnMode');
    AppSettingsStore.delete('autoMultiColumn');
    AppSettingsStore.delete('temperatureFahrenheit');
    AppSettingsStore.delete('temperatureShowUnit');
    AppSettingsStore.delete('dualColumnRestore');
    AppSettingsStore.delete('infoExcludedDevices');
    AppSettingsStore.delete('infoShowMoreContent');
    AppSettingsStore.delete('sortDevicesByRoom');
    AppSettingsStore.delete('backgroundImage');
    AppSettingsStore.delete('defaultHomeTab');
    AppSettingsStore.delete('infoRefreshInterval');
    // 外观类设置也要清空，否则「已清空所有记住的设置项」之后主题/字体/光感仍是旧值
    AppSettingsStore.delete('showOverviewCards');
    AppSettingsStore.delete('fontMode');
    AppSettingsStore.delete('fontFamilyEn');
    AppSettingsStore.delete('fontFamilyZh');
    AppSettingsStore.delete('fontSizeMode');
    AppSettingsStore.delete('fontSizeValue');
    AppSettingsStore.delete('fontWeightMode');
    AppSettingsStore.delete('fontWeightValue');
    AppSettingsStore.delete('immersiveLightEnabled');
    AppSettingsStore.delete('cardsFromTop');
    AppSettingsStore.delete('darkModeEnabled');
    AppSettingsStore.delete('accentKey');
    AppSettingsStore.delete('accentCustom');
    AppStorage.setOrCreate('hideOfflineDevices', false);
    AppStorage.setOrCreate('selectedHomeId', '');
    AppStorage.setOrCreate('selectedHomeName', '');
    AppStorage.setOrCreate('dualColumnMode', false);
    AppStorage.setOrCreate('autoMultiColumn', false);
    AppStorage.setOrCreate('temperatureFahrenheit', false);
    AppStorage.setOrCreate('temperatureShowUnit', false);
    AppStorage.setOrCreate('infoExcludedDevices', []);
    AppStorage.setOrCreate('infoShowMoreContent', true);
    AppStorage.setOrCreate('sortDevicesByRoom', false);
    AppStorage.setOrCreate('backgroundImage', '');
    AppStorage.setOrCreate('defaultHomeTab', 'home');
    AppStorage.setOrCreate('infoRefreshInterval', '30');
    AppStorage.setOrCreate('showOverviewCards', true);
    AppStorage.setOrCreate('fontMode', 'system');
    AppStorage.setOrCreate('fontFamilyEn', 'system');
    AppStorage.setOrCreate('fontFamilyZh', 'system');
    AppStorage.setOrCreate('fontSizeMode', 'system');
    AppStorage.setOrCreate('fontSizeValue', 16);
    AppStorage.setOrCreate('fontWeightMode', 'system');
    AppStorage.setOrCreate('fontWeightValue', 400);
    AppStorage.setOrCreate('immersiveLightEnabled', true);
    AppStorage.setOrCreate('cardsFromTop', true);
    AppStorage.setOrCreate('darkModeEnabled', false);
    AppStorage.setOrCreate('accentKey', 'harmony');
    AppStorage.setOrCreate('accentCustom', '');
    AppStorage.setOrCreate('accentColor', '#0A59F7');
    AppStorage.setOrCreate('isDarkMode', false);
    this.hideOfflineDevices = false;
    this.dualColumnMode = false;
    this.autoMultiColumn = false;
    this.temperatureFahrenheit = false;
    this.temperatureShowUnit = false;
    this.infoExcludedDevices = [];
    this.infoShowMoreContent = true;
    this.sortDevicesByRoom = false;
    this.wallpaperImage = '';
    this.defaultHomeTab = 'home';
    this.infoRefreshInterval = '30';
    this.clearMessage = '已清空所有记住的设置项';
  }

  setAutoMultiColumn(isOn: boolean): void {
    if (isOn === this.autoMultiColumn) {
      return;
    }
    if (isOn) {
      AppSettingsStore.setBoolean('dualColumnRestore', this.dualColumnMode);
      this.dualColumnMode = false;
      AppSettingsStore.setBoolean('dualColumnMode', false);
    } else {
      if (AppSettingsStore.getBoolean('dualColumnRestore', false)) {
        this.dualColumnMode = true;
        AppSettingsStore.setBoolean('dualColumnMode', true);
      }
      AppSettingsStore.delete('dualColumnRestore');
    }
    this.autoMultiColumn = isOn;
    AppSettingsStore.setBoolean('autoMultiColumn', isOn);
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

  refreshIntervalLabel(): string {
    for (let i = 0; i < INFO_REFRESH_OPTIONS.length; i++) {
      if (INFO_REFRESH_OPTIONS[i].seconds === this.infoRefreshInterval) {
        return INFO_REFRESH_OPTIONS[i].label;
      }
    }
    return '每30秒';
  }

  showClearAllDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '清空所有记住的设置项',
      message: '确定要清空所有记住的设置项吗？包括背景、家庭选择、默认页面、更新频率等。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: HwColor.danger,
        action: () => {
          this.clearAllSettings();
        }
      }
    });
  }

  openAppearanceSettings(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/AppearanceSettingsPage' });
    } catch (err) {
      // Keep the settings page stable when navigation fails.
    }
  }

  openBackupRestore(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/BackupRestorePage' });
    } catch (err) {
      // Keep the settings page stable when navigation fails.
    }
  }

  @Builder
  defaultTabSheet() {
    MaterialSheetPanel() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text('打开应用时默认展示')
            .fontFamily(this.appFontFamily('打开应用时默认展示'))
            .fontWeight(this.appFontWeight())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          IconCircleButton({
            symbol: $r('sys.symbol.xmark'),
            buttonSize: 36,
            iconSize: 18,
            onAction: () => {
              this.showDefaultTabSheet = false;
            }
          })
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .padding({ left: HwSpace.lg, right: HwSpace.lg })

        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Text('首页')
              .fontFamily(this.appFontFamily('首页'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
              .layoutWeight(1)
            if (this.defaultHomeTab === 'home') {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .fontColor([HwColor.primary])
            }
          }
          .width('100%')
          .padding(HwSpace.md)
          .borderRadius(HwRadius.control)
          .backgroundColor(HwColor.surface)
          .onClick(() => {
            this.defaultHomeTab = 'home';
            AppSettingsStore.setString('defaultHomeTab', 'home');
            this.showDefaultTabSheet = false;
          })
          Row({ space: 12 }) {
            Text('信息')
              .fontFamily(this.appFontFamily('信息'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
              .layoutWeight(1)
            if (this.defaultHomeTab === 'info') {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .fontColor([HwColor.primary])
            }
          }
          .width('100%')
          .padding(HwSpace.md)
          .borderRadius(HwRadius.control)
          .backgroundColor(HwColor.surface)
          .onClick(() => {
            this.defaultHomeTab = 'info';
            AppSettingsStore.setString('defaultHomeTab', 'info');
            this.showDefaultTabSheet = false;
          })
        }
        .width('100%')
        .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
        .margin({ top: 12 })
      }
      .width('100%')
    }
  }

  @Builder
  refreshIntervalSheet() {
    MaterialSheetPanel() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text('信息页数据更新频率')
            .fontFamily(this.appFontFamily('信息页数据更新频率'))
            .fontWeight(this.appFontWeight())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          IconCircleButton({
            symbol: $r('sys.symbol.xmark'),
            buttonSize: 36,
            iconSize: 18,
            onAction: () => {
              this.showRefreshIntervalSheet = false;
            }
          })
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .padding({ left: HwSpace.lg, right: HwSpace.lg })

        Column({ space: 10 }) {
          ForEach(INFO_REFRESH_OPTIONS, (option: InfoRefreshOption) => {
            Row({ space: 12 }) {
              Text(option.label)
                .fontFamily(this.appFontFamily(option.label))
                .fontWeight(this.appFontWeight())
                .fontSize(15)
                .fontColor(HwColor.textPrimary)
                .layoutWeight(1)
              if (this.infoRefreshInterval === option.seconds) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([HwColor.primary])
              }
            }
            .width('100%')
            .padding(HwSpace.md)
            .borderRadius(HwRadius.control)
            .backgroundColor(HwColor.surface)
            .onClick(() => {
              this.infoRefreshInterval = option.seconds;
              AppSettingsStore.setString('infoRefreshInterval', option.seconds);
              this.showRefreshIntervalSheet = false;
            })
          }, (option: InfoRefreshOption) => option.seconds)
        }
        .width('100%')
        .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: 24 })
        .margin({ top: 12 })
      }
      .width('100%')
    }
  }

  @Builder
  excludeSettingRow(option: InfoExcludeOption) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(option.name)
          .fontFamily(this.appFontFamily(option.name))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (option.roomName.length > 0) {
          Text(option.roomName)
            .fontFamily(this.appFontFamily(option.roomName))
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
        .select(this.isDeviceExcluded(option.did))
        .selectedColor(this.accentOrPrimary())
        .onChange((checked: boolean) => {
          this.setDeviceExcluded(option.did, checked);
        })
    }
    .width('100%')
    .padding(HwSpace.md)
    .borderRadius(HwRadius.control)
    .backgroundColor(HwColor.surface)
    .onClick(() => {
      this.setDeviceExcluded(option.did, !this.isDeviceExcluded(option.did));
    })
  }

  @Builder
  excludeSettingSheet() {
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

        if (this.infoDeviceOptions.length === 0) {
          Text('暂无设备，请先返回首页加载设备')
            .fontFamily(this.appFontFamily('暂无设备，请先返回首页加载设备'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
            .padding({ top: 24, bottom: 24 })
        } else {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.infoDeviceOptions, (option: InfoExcludeOption) => {
                this.excludeSettingRow(option)
              }, (option: InfoExcludeOption) => option.did)
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
      AccentColorSentinel()
      AppBackground()
      Column() {
        Scroll() {
          Column({ space: 0 }) {
            Blank().height(56 + this.statusBarHeight)
            Column({ space: 12 }) {
        if (this.clearMessage.length > 0) {
          Text(this.clearMessage)
            .fontFamily(this.appFontFamily(this.clearMessage))
            .fontWeight(this.appFontWeight())
            .fontSize(13)
            .fontColor(HwColor.primary)
            .width('100%')
            .padding({ left: 4, right: 4 })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card
        }) {
          Column({ space: 4 }) {
            Text('隐藏离线设备')
              .fontFamily(this.appFontFamily('隐藏离线设备'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('开启后首页不显示离线设备')
              .fontFamily(this.appFontFamily('开启后首页不显示离线设备'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.hideOfflineDevices })
            .selectedColor(this.accentOrPrimary())
            .onChange((isOn: boolean) => {
              this.hideOfflineDevices = isOn;
              AppSettingsStore.setBoolean('hideOfflineDevices', isOn);
            })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card
        }) {
          Column({ space: 4 }) {
            Text('首页设备按照房间(本地)排序')
              .fontFamily(this.appFontFamily('首页设备按照房间(本地)排序'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('开启后首页设备按本地创建的房间分组排序')
              .fontFamily(this.appFontFamily('开启后首页设备按本地创建的房间分组排序'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.sortDevicesByRoom })
            .selectedColor(this.accentOrPrimary())
            .onChange((isOn: boolean) => {
              this.sortDevicesByRoom = isOn;
              AppSettingsStore.setBoolean('sortDevicesByRoom', isOn);
            })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card,
          cardOpacity: this.autoMultiColumn ? 0.4 : 1
        }) {
          Column({ space: 4 }) {
            Text('双列模式')
              .fontFamily(this.appFontFamily('双列模式'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text(this.autoMultiColumn ? '自动多栏开启时不可用' : '开启后首页设备按双列排列')
              .fontFamily(this.appFontFamily(this.autoMultiColumn ? '自动多栏开启时不可用' : '开启后首页设备按双列排列'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.dualColumnMode })
            .selectedColor(this.accentOrPrimary())
            .enabled(!this.autoMultiColumn)
            .onChange((isOn: boolean) => {
              this.dualColumnMode = isOn;
              AppSettingsStore.setBoolean('dualColumnMode', isOn);
            })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card,
          cardOpacity: this.pcLayoutEnabled ? 0.4 : 1
        }) {
          Column({ space: 4 }) {
            Text('主页页面平滑切换')
              .fontFamily(this.appFontFamily('主页页面平滑切换'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(this.pcLayoutEnabled ? HwColor.textSecondary : HwColor.textPrimary)
            Text(this.pcLayoutEnabled ? '开启侧边导航布局后不可用' : '开启后点击底栏切换带平滑动效')
              .fontFamily(this.appFontFamily(this.pcLayoutEnabled ? '开启侧边导航布局后不可用' : '开启后点击底栏切换带平滑动效'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.homeSmoothSwitch })
            .selectedColor(this.accentOrPrimary())
            .enabled(!this.pcLayoutEnabled)
            .onChange((isOn: boolean) => {
              this.homeSmoothSwitch = isOn;
              AppSettingsStore.setBoolean('homeSmoothSwitch', isOn);
            })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card
        }) {
          Column({ space: 4 }) {
            Text('温度以华氏度℉')
              .fontFamily(this.appFontFamily('温度以华氏度℉'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('开启后所有温度以华氏度显示')
              .fontFamily(this.appFontFamily('开启后所有温度以华氏度显示'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.temperatureFahrenheit })
            .selectedColor(this.accentOrPrimary())
            .onChange((isOn: boolean) => {
              this.temperatureFahrenheit = isOn;
              AppSettingsStore.setBoolean('temperatureFahrenheit', isOn);
            })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card
        }) {
          Column({ space: 4 }) {
            Text('温度额外显示单位')
              .fontFamily(this.appFontFamily('温度额外显示单位'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('开启后设备详情页温度数值后显示°C/°F单位，关闭时单位显示在卡片右上角')
              .fontFamily(this.appFontFamily('开启后设备详情页温度数值后显示°C/°F单位，关闭时单位显示在卡片右上角'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.temperatureShowUnit })
            .selectedColor(this.accentOrPrimary())
            .onChange((isOn: boolean) => {
              this.temperatureShowUnit = isOn;
              AppSettingsStore.setBoolean('temperatureShowUnit', isOn);
            })
        }

        if (this.isLargeScreen) {
          MaterialCard({
            cardDirection: FlexDirection.Row,
            cardSpace: 12,
            cardPadding: HwSpace.lg,
            cardRadius: HwRadius.card,
            cardOpacity: this.pcLayoutEnabled ? 0.4 : 1
          }) {
            Column({ space: 4 }) {
              Text('自动多栏')
                .fontFamily(this.appFontFamily('自动多栏'))
                .fontWeight(this.appFontWeight())
                .fontSize(15)
                .fontColor(this.pcLayoutEnabled ? HwColor.textSecondary : HwColor.textPrimary)
              Text(this.pcLayoutEnabled ? '开启侧边导航布局后不可用' : '开启后平板和2in1设备自动分栏，设备详情在右侧栏打开')
                .fontFamily(this.appFontFamily(this.pcLayoutEnabled ? '开启侧边导航布局后不可用' : '开启后平板和2in1设备自动分栏，设备详情在右侧栏打开'))
                .fontWeight(this.appFontWeight())
                .fontSize(12)
                .fontColor(HwColor.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoMultiColumn })
              .selectedColor(this.accentOrPrimary())
              .enabled(!this.pcLayoutEnabled)
              .onChange((isOn: boolean) => {
                this.setAutoMultiColumn(isOn);
              })
          }

          MaterialCard({
            cardDirection: FlexDirection.Row,
            cardSpace: 12,
            cardPadding: HwSpace.lg,
            cardRadius: HwRadius.card
          }) {
            Column({ space: 4 }) {
              Text('侧边导航布局')
                .fontFamily(this.appFontFamily('侧边导航布局'))
                .fontWeight(this.appFontWeight())
                .fontSize(15)
                .fontColor(HwColor.textPrimary)
              Text(this.is2in1 ? '使用 PC 侧边导航样式（2in1 默认开启）' : '使用 PC 侧边导航样式（平板默认关闭）')
                .fontFamily(this.appFontFamily(this.is2in1 ? '使用 PC 侧边导航样式（2in1 默认开启）' : '使用 PC 侧边导航样式（平板默认关闭）'))
                .fontWeight(this.appFontWeight())
                .fontSize(12)
                .fontColor(HwColor.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.pcLayoutEnabled })
            .selectedColor(this.accentOrPrimary())
            .onChange((isOn: boolean) => {
              this.pcLayoutEnabled = isOn;
              AppSettingsStore.setBoolean('pcLayoutEnabled', isOn);
              if (isOn && this.autoMultiColumn) {
                this.setAutoMultiColumn(false);
              }
              if (isOn && this.homeSmoothSwitch) {
                this.homeSmoothSwitch = false;
                AppSettingsStore.setBoolean('homeSmoothSwitch', false);
              }
            })
          }
        }

        Column() {
                  MaterialCard({
                    cardDirection: FlexDirection.Row,
                    cardSpace: 12,
                    cardPadding: HwSpace.lg,
                    cardRadius: HwRadius.card,
                    cardOnClick: (): void => { this.showDefaultTabSheet = true; }
                  }) {
                    Column({ space: 4 }) {
                      Text('默认打开页面')
                        .fontFamily(this.appFontFamily('默认打开页面'))
                        .fontWeight(this.appFontWeight())
                        .fontSize(15)
                        .fontColor(HwColor.textPrimary)
                      Text(this.defaultHomeTab === 'info' ? '信息' : '首页')
                        .fontFamily(this.appFontFamily(this.defaultHomeTab === 'info' ? '信息' : '首页'))
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
        }
        .width('100%')
        .bindSheet($$this.showDefaultTabSheet, this.defaultTabSheet(), { height: SheetSize.MEDIUM, dragBar: true, showClose: false, backgroundColor: Color.Transparent, blurStyle: sheetBlurStyle(), })

        Column() {
                  MaterialCard({
                    cardDirection: FlexDirection.Row,
                    cardSpace: 12,
                    cardPadding: HwSpace.lg,
                    cardRadius: HwRadius.card,
                    cardOnClick: (): void => { this.showRefreshIntervalSheet = true; }
                  }) {
                    Column({ space: 4 }) {
                      Text('信息页数据更新频率')
                        .fontFamily(this.appFontFamily('信息页数据更新频率'))
                        .fontWeight(this.appFontWeight())
                        .fontSize(15)
                        .fontColor(HwColor.textPrimary)
                      Text(this.refreshIntervalLabel())
                        .fontFamily(this.appFontFamily(this.refreshIntervalLabel()))
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
        }
        .width('100%')
        .bindSheet($$this.showRefreshIntervalSheet, this.refreshIntervalSheet(), { height: SheetSize.MEDIUM, dragBar: true, showClose: false, backgroundColor: Color.Transparent, blurStyle: sheetBlurStyle(), })

        Column() {
                  MaterialCard({
                    cardDirection: FlexDirection.Row,
                    cardSpace: 12,
                    cardPadding: HwSpace.lg,
                    cardRadius: HwRadius.card,
                    cardOnClick: (): void => { this.showExcludeSheet = true; }
                  }) {
                    Column({ space: 4 }) {
                      Text('信息页排除设备')
                        .fontFamily(this.appFontFamily('信息页排除设备'))
                        .fontWeight(this.appFontWeight())
                        .fontSize(15)
                        .fontColor(HwColor.textPrimary)
                      Text(this.infoExcludedDevices.length > 0
                        ? `已排除 ${this.infoExcludedDevices.length} 台设备`
                        : '未排除设备')
                        .fontFamily(this.appFontFamily(this.infoExcludedDevices.length > 0
                        ? `已排除 ${this.infoExcludedDevices.length} 台设备`
                        : '未排除设备'))
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
        }
        .width('100%')
        .bindSheet($$this.showExcludeSheet, this.excludeSettingSheet(), { height: SheetSize.MEDIUM, dragBar: true, showClose: false, backgroundColor: Color.Transparent, blurStyle: sheetBlurStyle(), })

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card
        }) {
          Column({ space: 4 }) {
            Text('信息页显示更多内容')
              .fontFamily(this.appFontFamily('信息页显示更多内容'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('开启后信息页卡片显示设备数与平均值')
              .fontFamily(this.appFontFamily('开启后信息页卡片显示设备数与平均值'))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.infoShowMoreContent })
            .selectedColor(this.accentOrPrimary())
            .onChange((isOn: boolean) => {
              this.infoShowMoreContent = isOn;
              AppSettingsStore.setBoolean('infoShowMoreContent', isOn);
            })
        }

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card,
          cardOnClick: (): void => { this.openAppearanceSettings(); }
        }) {
          Column({ space: 4 }) {
            Text('外观设置')
              .fontFamily(this.appFontFamily('外观设置'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('更换背景、清空背景')
              .fontFamily(this.appFontFamily('更换背景、清空背景'))
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

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card,
          cardOnClick: (): void => { this.openBackupRestore(); }
        }) {
          Column({ space: 4 }) {
            Text('备份与恢复')
              .fontFamily(this.appFontFamily('备份与恢复'))
              .fontWeight(this.appFontWeight())
              .fontSize(15)
              .fontColor(HwColor.textPrimary)
            Text('导出或恢复配置文件，迁移设置到其他设备')
              .fontFamily(this.appFontFamily('导出或恢复配置文件，迁移设置到其他设备'))
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

        MaterialCard({
          cardDirection: FlexDirection.Row,
          cardSpace: 12,
          cardPadding: HwSpace.lg,
          cardRadius: HwRadius.card,
          cardOnClick: (): void => { this.showClearAllDialog(); }
        }) {
          Text('清空所有记住的设置项')
            .fontFamily(this.appFontFamily('清空所有记住的设置项'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.danger)
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([HwColor.danger])
        }
            }
            .width('100%')
            .constraintSize({
              maxWidth: this.isWideScreen ? 1080 : '100%'
            })
            .padding({ left: HwSpace.lg, right: HwSpace.lg, top: HwSpace.lg, bottom: HwSpace.xl })
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
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
        Text('设置')
          .fontFamily(this.appFontFamily('设置'))
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
      .backgroundEffect({ radius: 12, color: '#66FFFFFF' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(resolvePageBackground(this.accentColor, this.isDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      router.back();
    })
  }
}
