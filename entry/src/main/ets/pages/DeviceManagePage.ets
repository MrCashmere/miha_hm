/*
 * 鸿米家（miha）— 设备管理页。
 *
 * 汇总当前所选家庭/全部家庭下的设备清单，提供：
 * - 设备总数/在线/离线统计
 * - 按设备名称、型号、房间、在线状态展示
 * - 点击进入设备详情页
 *
 * Copyright (C) 2026 鸿米家（miha）项目开发者
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { reloadAppTheme, HwColor, HwRadius, HwSpace, MijiaOverviewCardText, MijiaOverviewCardValue } from '../utils/DesignTokens';
import { AppBackground } from '../components/AppBackground';
import { AccentColorSentinel, MaterialCard } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { XiaomiDevice, ALL_HOMES_ID } from '../models/XiaomiHomeModels';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';
import { deviceSymbolFor } from '../utils/DeviceSymbol';
import { DeviceRemovalStore } from '../storage/DeviceRemovalStore';

@Builder
export function DeviceManageBuilder(name: string, param: Object) {
  DeviceManagePage()
}

@Component
export struct DeviceManagePage {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';

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
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }
  @Consume('pageInfos') pageInfos: NavPathStack;
  @StorageLink('selectedHomeId') selectedHomeId: string = '';
  @StorageLink('selectedHomeName') selectedHomeName: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  private scroller: Scroller = new Scroller();
  @State devices: XiaomiDevice[] = [];
  @State loading: boolean = true;
  @State errorMessage: string = '';
  @State refreshing: boolean = false;

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('设备管理页');
    this.loadDevices();
  }

  async loadDevices(forceRefresh: boolean = false): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const snapshot = await xiaomiDataService.getHomeSnapshot(context, forceRefresh);
      const deviceMap = JSON.parse(snapshot.devicesJson) as Record<string, XiaomiDevice>;
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
      visibleDevices.sort((a: XiaomiDevice, b: XiaomiDevice) => {
        const aKey = (a.online ? '0' : '1') + '-' + a.roomName + '-' + a.name;
        const bKey = (b.online ? '0' : '1') + '-' + b.roomName + '-' + b.name;
        return aKey.localeCompare(bKey, 'zh-CN');
      });
      this.devices = DeviceRemovalStore.filter(visibleDevices);
      FeedbackLogService.recordOperation('PAGE', '设备管理页: 共 ' + this.devices.length + ' 台设备');
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '加载设备失败';
      Logger.error('device manage load failed, %{public}s', this.errorMessage);
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private handleRefresh(): void {
    this.refreshing = true;
    this.loadDevices(true);
  }

  private onlineCount(): number {
    let count = 0;
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].online) {
        count++;
      }
    }
    return count;
  }

  /** 设备图标：统一走共享映射，保证与首页完全一致 */
  private deviceSymbol(device: XiaomiDevice): Resource {
    return deviceSymbolFor(device.model, device.name);
  }
  @Builder
  metricCell(label: string, value: string, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(value)
        .fontFamily(this.appFontFamily(value))
        .fontWeight(this.appFontWeight())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontFamily(this.appFontFamily(label))
        .fontWeight(this.appFontWeight())
        .fontSize(12)
        .fontColor(MijiaOverviewCardText)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  deviceRow(device: XiaomiDevice) {
    MaterialCard({
      cardDirection: FlexDirection.Row,
      cardSpace: 12,
      cardPadding: HwSpace.lg,
      cardRadius: HwRadius.control
    }) {
      // 图标统一用系统符号且不带底色（垫色块会在光感卡面上显出多余方块）
      SymbolGlyph(this.deviceSymbol(device))
        .fontSize(30)
        .fontColor([HwColor.primary])
        .width(48)
        .height(48)

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(device.name)
            .fontFamily(this.appFontFamily(device.name))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(HwColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(device.online ? HwColor.online : '#8A93A2')
        }
        .width('100%')

        Text(this.deviceSubtitle(device))
          .fontFamily(this.appFontFamily(this.deviceSubtitle(device)))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(MijiaOverviewCardText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button('删除')
        .height(32)
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(HwColor.danger)
        .stateEffect(true)
        .onClick(() => {
          this.confirmDeleteDevice(device);
        })
    }
  }

  confirmDeleteDevice(device: XiaomiDevice): void {
    this.getUIContext().showAlertDialog({
      title: '删除设备',
      message: `确定删除「${device.name}」吗？\n删除后首页、创建智能等均不再显示该设备（本地记录）。`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: HwColor.danger,
        action: (): void => {
          DeviceRemovalStore.remove(device.did);
          const next: XiaomiDevice[] = [];
          for (let i = 0; i < this.devices.length; i++) {
            if (this.devices[i].did !== device.did) {
              next.push(this.devices[i]);
            }
          }
          this.devices = next;
          this.getUIContext().getPromptAction().showToast({ message: `已删除「${device.name}」` });
          FeedbackLogService.recordOperation('UI', '设备管理: 删除设备 ' + device.name + ' (' + device.did + ')');
        }
      }
    });
  }

  private deviceSubtitle(device: XiaomiDevice): string {
    const parts: string[] = [];
    if (device.roomName.length > 0) {
      parts.push(device.roomName);
    }
    if (device.model.length > 0) {
      parts.push(device.model);
    }
    if (parts.length === 0) {
      parts.push(device.online ? '在线' : '离线');
    }
    return parts.join(' · ');
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
        AccentColorSentinel()
        AppBackground()

        Refresh({ refreshing: $$this.refreshing }) {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
            Blank().height(56 + this.statusBarHeight)

            if (this.loading) {
              Text('加载中…')
                .fontFamily(this.appFontFamily('加载中…'))
                .fontWeight(this.appFontWeight())
                .fontSize(14)
                .fontColor(HwColor.textSecondary)
                .padding({ top: 40, bottom: 40 })
            } else if (this.errorMessage.length > 0) {
              Text(this.errorMessage)
                .fontFamily(this.appFontFamily(this.errorMessage))
                .fontWeight(this.appFontWeight())
                .fontSize(14)
                .fontColor(HwColor.danger)
                .padding({ top: 24, bottom: 24 })
            } else {
              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardSpace: 0,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card
              }) {
                this.metricCell('设备总数', '' + this.devices.length, HwColor.textPrimary)
                Divider()
                  .vertical(true)
                  .height(32)
                  .color('#22000000')
                this.metricCell('在线', '' + this.onlineCount(), HwColor.online)
                Divider()
                  .vertical(true)
                  .height(32)
                  .color('#22000000')
                this.metricCell('离线', '' + (this.devices.length - this.onlineCount()), '#8A93A2')
              }

              if (this.devices.length === 0) {
                Text(this.selectedHomeId === ALL_HOMES_ID ? '没有设备' : '当前家庭没有设备')
                  .fontFamily(this.appFontFamily(this.selectedHomeId === ALL_HOMES_ID ? '没有设备' : '当前家庭没有设备'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(14)
                  .fontColor(HwColor.textSecondary)
                  .padding({ top: 24, bottom: 24 })
              } else {
                Column({ space: 10 }) {
                  ForEach(this.devices, (device: XiaomiDevice) => {
                    this.deviceRow(device)
                  }, (device: XiaomiDevice) => device.did)
                }
                .width('100%')
              }
            }

            Blank().height(40)
          }
          .width('100%')
          .padding({ left: HwSpace.lg, right: HwSpace.lg })
        }
        .width('100%')
        .height('100%')
        .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          this.handleRefresh();
        })

        Row() {
          IconCircleButton({
            symbol: $r('sys.symbol.chevron_left'),
            tint: '#FFFFFF',
            onAction: () => {
              this.pageInfos.pop();
            }
          })
          Text('设备管理')
            .fontFamily(this.appFontFamily('设备管理'))
            .fontWeight(this.appFontWeight())
            .margin({ left: HwSpace.md })
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(HwColor.textPrimary)
          Blank()
          IconCircleButton({
            symbol: $r('sys.symbol.arrow_counterclockwise'),
            tint: HwColor.textPrimary,
            buttonEnabled: !this.refreshing,
            spinning: this.refreshing,
            onAction: () => {
              this.handleRefresh();
            }
          })
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .padding({ left: 16, right: 16, top: this.statusBarHeight })
        // 标题栏毛玻璃：必须用半透明底色，否则 HwGlassCardColor.surface
        // 是不透明的 #E8F0F8，会把毛玻璃盖成纯白块。
        .backgroundBlurStyle(BlurStyle.Thin)
        .backgroundColor('#66FFFFFF')
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .hideBackButton(true)
    .hideToolBar(true, true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.pageInfos.pop();
    })
  }
}