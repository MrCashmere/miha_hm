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
import { XiaomiHome, ALL_HOMES_ID, ALL_HOMES_NAME } from '../models/XiaomiHomeModels';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { HwColor, HwRadius, HwSpace, reloadAppTheme, resolvePageBackground } from '../utils/DesignTokens';
import { MaterialCard, AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppBackground } from '../components/AppBackground';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { FeedbackLogService } from '../services/FeedbackLogService';

@Entry
@Component
struct FamilySelectPage {
  @StorageLink('fontMode') fontMode: string = 'system';
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
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
  @StorageLink('selectedHomeId') selectedHomeId: string = '';
  @StorageLink('selectedHomeName') selectedHomeName: string = '';
  @StorageLink('homeSelectionVersion') homeSelectionVersion: number = 0;
  @State homes: XiaomiHome[] = [];
  @State loading: boolean = true;
  @State errorMessage: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 页面底色（由 applyAppTheme 发布）。订阅它而不是读 HwColor 属性，见 docs/ThemeColor.md §7.8 */
  @StorageProp('pageBackground') pageBackground: string = '';

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('选择家庭页');
    this.loadHomes();
  }

  async loadHomes(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      this.homes = await xiaomiDataService.getHomes();
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '加载家庭失败';
    } finally {
      this.loading = false;
    }
  }

  selectHome(home: XiaomiHome): void {
    this.selectedHomeId = home.homeId;
    this.selectedHomeName = home.name;
    AppSettingsStore.setString('selectedHomeId', home.homeId);
    AppSettingsStore.setString('selectedHomeName', home.name);
    this.homeSelectionVersion = this.homeSelectionVersion + 1;
    router.back();
  }

  selectAllHomes(): void {
    this.selectedHomeId = ALL_HOMES_ID;
    this.selectedHomeName = ALL_HOMES_NAME;
    AppSettingsStore.setString('selectedHomeId', ALL_HOMES_ID);
    AppSettingsStore.setString('selectedHomeName', ALL_HOMES_NAME);
    this.homeSelectionVersion = this.homeSelectionVersion + 1;
    router.back();
  }

  // ==================== 家庭卡 ====================

  /**
   * 家庭卡：`home === null` 表示「全部家庭」那一项。
   *
   * 必须走 MaterialCard：本页此前是「Row + backgroundColor(HwColor.surface)」的实色块，
   * 与本工程其它页面（首页设备卡、首页的选择家庭弹窗、耗材卡…）完全不是一套观感——
   * 实色底会把沉浸光感材质挡在下面，所以整页看着「没有光感」。
   * MaterialCard 内部用 ToggleType.Button 承载 systemMaterial，选中态改用主色描边表达。
   */
  @Builder
  homeCard(home: XiaomiHome | null) {
    MaterialCard({
      cardDirection: FlexDirection.Row,
      cardSpace: 10,
      cardPadding: HwSpace.lg,
      cardRadius: HwRadius.card,
      // 成排的小卡片关掉材质自带投影：这几张卡上下只隔 10vp，
      // 投影会在卡间缝隙里叠成一条暗带，看着像每张卡背后顶了一层影子
      cardMaterialShadow: false,
      cardBorderWidth: this.isHomeOptionSelected(home) ? 1 : 0,
      cardBorderColor: this.isHomeOptionSelected(home) ? HwColor.primary : '#00000000',
      cardOnClick: (): void => {
        this.selectHomeOption(home);
      }
    }) {
      Column({ space: 4 }) {
        Text(this.homeOptionTitle(home))
          .fontFamily(this.appFontFamily(this.homeOptionTitle(home)))
          .fontWeight(this.appFontWeight())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.homeOptionSubtitle(home))
          .fontFamily(this.appFontFamily(this.homeOptionSubtitle(home)))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(HwColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isHomeOptionSelected(home)) {
        Text('当前')
          .fontFamily(this.appFontFamily('当前'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.primary)
      }
    }
  }

  /** 该项是不是当前选中的家庭（null 即「全部家庭」） */
  private isHomeOptionSelected(home: XiaomiHome | null): boolean {
    return home === null
      ? this.selectedHomeId === ALL_HOMES_ID
      : this.selectedHomeId === home.homeId;
  }

  private homeOptionTitle(home: XiaomiHome | null): string {
    return home === null ? ALL_HOMES_NAME : home.name;
  }

  private homeOptionSubtitle(home: XiaomiHome | null): string {
    return home === null ? '显示账号下所有家庭的所有设备' : `${home.roomList.length} 个房间`;
  }

  private selectHomeOption(home: XiaomiHome | null): void {
    if (home === null) {
      this.selectAllHomes();
      return;
    }
    this.selectHome(home);
  }

  build() {
    Stack() {
      // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
      AccentColorSentinel()
      AppBackground()
      Column() {
        Row() {
          IconCircleButton({
          symbol: $r('sys.symbol.chevron_left'),
          buttonSize: 40,
          iconSize: 20,
          onAction: () => {
            router.back();
          }
        })
        Text('选择家庭')
          .fontFamily(this.appFontFamily('选择家庭'))
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

      Column({ space: 14 }) {
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

        if (!this.loading && this.errorMessage.length === 0 && this.homes.length === 0) {
          Text('暂无家庭，请返回首页下拉刷新后重试')
            .fontFamily(this.appFontFamily('暂无家庭，请返回首页下拉刷新后重试'))
            .fontWeight(this.appFontWeight())
            .fontSize(13)
            .fontColor(HwColor.textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: HwSpace.lg, bottom: HwSpace.lg })
        }

        Scroll() {
          Column({ space: 10 }) {
            // 「全部家庭」+ 各家庭：同一张 MaterialCard 版式，选中项主色描边
            this.homeCard(null)

            ForEach(this.homes, (home: XiaomiHome) => {
              this.homeCard(home)
            }, (home: XiaomiHome) => home.homeId)
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .padding({
        left: HwSpace.xl,
        right: HwSpace.xl,
        top: HwSpace.xl,
        bottom: HwSpace.xl + this.navigationBarHeight
      })
      .width('100%')
      .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      router.back();
    })
  }
}
