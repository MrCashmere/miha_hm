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

import {
  MijiaQrLoginService,
  MijiaQrLoginTicket
} from '../oauth/MijiaQrLoginService';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';
import { HwColor, HwRadius, HwSpace, reloadAppTheme, resolvePageBackground } from '../utils/DesignTokens';
import { AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { PressableButton } from '../components/PressableButton';
import { AppBackground } from '../components/AppBackground';
import { AppSettingsStore } from '../storage/AppSettingsStore';

@Entry
@Component
struct LoginPage {
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

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('登录页');
  }

  @State qrUrl: string = '';
  @State loading: boolean = false;
  @State statusMessage: string = '';
  @State errorMessage: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 页面底色（由 applyAppTheme 发布）。订阅它而不是读 HwColor 属性，见 docs/ThemeColor.md §7.8 */
  @StorageProp('pageBackground') pageBackground: string = '';
  @StorageProp('isWearable') isWearable: boolean = false;

  private loginService: MijiaQrLoginService | null = null;
  private ticket: MijiaQrLoginTicket | null = null;

  /**
   * 跳过登录：置游客态后直接进首页。
   *
   * 游客态只写进 AppStorage、不落盘（见 EntryAbility），所以它只在本次会话有效：
   * 下次冷启动仍然先看有没有账号，没有就回到本页，「跳过登录」不会被永久记住。
   * 首页据此把「已登录用户」「退出登录」换成「未登录用户」「登录」，
   * 并跳过所有云端拉取，避免无账号时被鉴权错误弹回登录页。
   */
  private skipLogin(): void {
    FeedbackLogService.recordOperation('UI', '跳过登录进入首页（游客态）');
    AppStorage.setOrCreate('guestMode', true);
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' });
  }

  /** 登录页也能直接改外观：换背景/字体不需要账号 */
  private openAppearanceSettings(): void {
    try {
      FeedbackLogService.recordOperation('UI', '登录页进入外观设置');
      this.getUIContext().getRouter().pushUrl({ url: 'pages/AppearanceSettingsPage' });
    } catch (err) {
      // 导航失败不影响登录页本身
    }
  }

  async startMijiaLogin(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.statusMessage = '';
    try {
      this.loginService = new MijiaQrLoginService();
      this.ticket = await this.loginService.buildLoginTicket();
      this.qrUrl = this.ticket.qr;
      this.statusMessage = '请使用小米/米家 App 扫码登录';
      const auth = await this.loginService.pollTicket(this.ticket);
      await xiaomiDataService.setMijiaAuth(auth);
      // 真的登录上了：退出游客态，首页恢复「已登录用户 / 退出登录」
      AppStorage.setOrCreate('guestMode', false);
      AppStorage.setOrCreate('selectedHomeId', '');
      AppStorage.setOrCreate('selectedHomeName', '');
      AppStorage.setOrCreate('homeSelectionVersion', 0);
      AppSettingsStore.setString('selectedHomeId', '');
      AppSettingsStore.setString('selectedHomeName', '');
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' });
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '登录失败';
      Logger.error('mijia qr login failed, %{public}s', this.errorMessage);
    } finally {
      this.loading = false;
    }
  }

  build() {
    Stack() {
      // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
      AccentColorSentinel()
      AppBackground()

      Column() {
        Column({ space: HwSpace.sm }) {
          Text('米家控制')
            .fontFamily(this.appFontFamily('米家控制'))
            .fontWeight(this.appFontWeight())
            .fontSize(this.isWearable ? 24 : 32)
            .fontWeight(FontWeight.Bold)
            .fontColor(HwColor.textPrimary)

          Text('使用小米/米家 App 扫码登录')
            .fontFamily(this.appFontFamily('使用小米/米家 App 扫码登录'))
            .fontWeight(this.appFontWeight())
            .fontSize(this.isWearable ? 13 : 16)
            .fontColor(HwColor.textSecondary)
        }
        .margin({ top: this.isWearable ? 24 : 72, bottom: this.isWearable ? 16 : 32 })

        Column({ space: 18 }) {
          Column() {
            if (this.qrUrl.length > 0) {
              Image(this.qrUrl)
                .width(this.isWearable ? 160 : 240)
                .height(this.isWearable ? 160 : 240)
                .objectFit(ImageFit.Contain)
            } else {
              Text('二维码将显示在这里')
                .fontFamily(this.appFontFamily('二维码将显示在这里'))
                .fontWeight(this.appFontWeight())
                .fontSize(14)
                .fontColor(HwColor.textSecondary)
            }
          }
          .width(this.isWearable ? 160 : 240)
          .height(this.isWearable ? 160 : 240)
          .justifyContent(FlexAlign.Center)
          .borderRadius(HwRadius.card)
          .backgroundColor(HwColor.surface)

          PressableButton({
            label: this.loading ? '等待扫码...' : '生成二维码登录',
            emphasized: true,
            loading: this.loading,
            fullWidth: true,
            buttonHeight: 48,
            role: ButtonRole.NORMAL,
            onAction: () => {
              this.startMijiaLogin();
            }
          })

          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .fontFamily(this.appFontFamily(this.statusMessage))
              .fontWeight(this.appFontWeight())
              .fontSize(14)
              .fontColor(HwColor.primary)
          }

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontFamily(this.appFontFamily(this.errorMessage))
              .fontWeight(this.appFontWeight())
              .fontSize(14)
              .fontColor(HwColor.danger)
          }
        }
        .width('100%')
        .padding(this.isWearable ? HwSpace.md : HwSpace.xl)
        .borderRadius(HwRadius.card)
        .backgroundColor(HwColor.surface)

        Blank()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: HwSpace.xl,
        right: HwSpace.xl,
        top: HwSpace.xl + this.statusBarHeight,
        bottom: HwSpace.xl + this.navigationBarHeight
      })
      .backgroundColor(Color.Transparent)

      /**
       * 右上角两个圆形按钮。
       *
       * **对齐必须由容器给出**：`align()` 的语义是「设置**容器元素绘制区域内**子元素的对齐方式」，
       * 只对 Stack / FolderStack / Button / Text 这类容器自身生效，挂在 Row 上不起任何作用
       * ——之前写成 `Row(...).align(Alignment.TopEnd)`，结果两个按钮落在了页面正中。
       * 所以这里用一个铺满整屏的 Stack 当容器，把对齐写进它的 `alignContent`。
       *
       * `hitTestBehavior(HitTestMode.Transparent)`：这一层只负责定位，不能挡住下面
       * 登录卡片与输入框的触摸（Transparent = 自身与子节点可响应，且不阻塞兄弟节点）。
       *
       * 按钮本身走 IconCircleButton：它内部用 ToggleType.Button 承载沉浸光感材质，
       * 是本工程唯一能在内容区吃到 systemMaterial 的写法，因此这两个按钮的
       * 玻璃质感、按压形变与主题色流光都与全局其它圆形按钮完全一致。
       *
       * 位置排在内容 Column **之后**：Stack 里后画的在上层，页面主体又是满屏 Column，
       * 排在后面才能保证按钮压在内容之上、触摸先落到按钮上。
       */
      Stack({ alignContent: Alignment.TopEnd }) {
        // 左：跳过登录直接进首页（游客态）；右：进外观设置（换背景/字体不需要账号）
        Row({ space: HwSpace.sm }) {
          IconCircleButton({
            symbol: $r('sys.symbol.chevron_forward'),
            buttonSize: this.isWearable ? 34 : 40,
            iconSize: this.isWearable ? 16 : 20,
            tint: HwColor.textPrimary,
            onAction: (): void => {
              this.skipLogin();
            }
          })
          IconCircleButton({
            symbol: $r('sys.symbol.paintpalette'),
            buttonSize: this.isWearable ? 34 : 40,
            iconSize: this.isWearable ? 16 : 20,
            tint: HwColor.textPrimary,
            onAction: (): void => {
              this.openAppearanceSettings();
            }
          })
        }
        // 穿戴设备是圆屏：右上角本身就是圆的边界，往里收一些按钮才不会被表框切掉
        .margin({
          top: this.statusBarHeight + (this.isWearable ? HwSpace.lg : HwSpace.sm),
          right: this.isWearable ? HwSpace.xl : HwSpace.md
        })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
