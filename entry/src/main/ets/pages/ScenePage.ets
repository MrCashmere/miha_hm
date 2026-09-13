/*
 * 鸿米家（miha）— 智能（场景）页。
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
import { HwColor, HwRadius, HwSpace, reloadAppTheme, resolvePageBackground, withAlpha } from '../utils/DesignTokens';
import { MaterialCard, MaterialCardLayer, AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppBackground } from '../components/AppBackground';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { localSceneService, SceneRunResult } from '../services/LocalSceneService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { LocalScene, LocalSceneAction, XiaomiHome, XiaomiScene, ALL_HOMES_ID } from '../models/XiaomiHomeModels';
import { LocalSceneStore } from '../storage/LocalSceneStore';
import { Logger } from '../utils/Logger';

const CATEGORY_LOCAL: string = 'local';
const CATEGORY_AUTO: string = 'auto';
const CATEGORY_MANUAL: string = 'manual';

@Entry
@Component
struct ScenePage {
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('currentWidthBreakpoint') @Watch('onBreakpointChange')
  widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;

  @State isWideScreen: boolean = false;
  @State category: string = CATEGORY_LOCAL;
  @State localScenes: LocalScene[] = [];
  @State cloudScenes: XiaomiScene[] = [];
  @State loading: boolean = false;
  @State running: boolean = false;
  @State errorMessage: string = '';

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

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }

  /** 当前主题色。读 accentColor 建立依赖，否则切色后会停留在旧色 */
  private accent(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('智能页');
    this.onBreakpointChange();
    this.localScenes = localSceneService.scenes();
    this.loadCloudScenes();
  }

  onPageShow(): void {
    // 从创建页返回时刷新列表
    this.localScenes = localSceneService.scenes();
  }

  onBreakpointChange(): void {
    this.isWideScreen = this.widthBp === WidthBreakpoint.WIDTH_LG ||
      this.widthBp === WidthBreakpoint.WIDTH_MD;
  }

  private topOffset(): number {
    return 56 + this.statusBarHeight;
  }

  private contentPadding(): number {
    return this.isWideScreen ? 24 : 16;
  }

  private maxContentWidth(): Length {
    return this.isWideScreen ? 840 : '100%';
  }

  // ==================== 数据 ====================

  /**
   * 拉取云端场景（自动化 + 手动）。
   * 选中「全部家庭」时逐个家庭拉取并按 sceneId 去重——共享家庭的场景会在多个家庭里重复出现。
   */
  private async loadCloudScenes(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      const selectedHomeId = AppStorage.get<string>('selectedHomeId') ?? ALL_HOMES_ID;
      const homes: XiaomiHome[] = await xiaomiDataService.getHomes();
      const targets: XiaomiHome[] = [];
      for (let i = 0; i < homes.length; i++) {
        if (selectedHomeId === ALL_HOMES_ID || homes[i].homeId === selectedHomeId) {
          targets.push(homes[i]);
        }
      }
      const list: XiaomiScene[] = [];
      const seen: string[] = [];
      for (let i = 0; i < targets.length; i++) {
        const scenes = await xiaomiDataService.getScenes(targets[i].homeId);
        for (let j = 0; j < scenes.length; j++) {
          if (seen.indexOf(scenes[j].sceneId) < 0) {
            seen.push(scenes[j].sceneId);
            list.push(scenes[j]);
          }
        }
      }
      this.cloudScenes = list;
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '加载场景失败';
      Logger.error('load cloud scenes failed, %{public}s', this.errorMessage);
    } finally {
      this.loading = false;
    }
  }

  private reload(): void {
    this.localScenes = localSceneService.scenes();
    this.loadCloudScenes();
  }

  /** 广播一条提示 */
  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ==================== 执行 ====================

  /** 执行本地智能：逐条动作下发，最后汇报失败条数 */
  private async runLocalScene(scene: LocalScene): Promise<void> {
    if (this.running) {
      return;
    }
    if (scene.actions.length === 0) {
      this.toast('该智能没有可执行的动作');
      return;
    }
    this.running = true;
    FeedbackLogService.recordOperation('UI', `执行本地智能 ${scene.name}`);
    const result: SceneRunResult = await localSceneService.execute(scene);
    this.running = false;
    if (result.failed < 0) {
      this.toast(`执行「${scene.name}」失败`);
    } else if (result.failed === 0) {
      this.toast(`已执行「${scene.name}」`);
    } else {
      this.toast(`执行「${scene.name}」失败 ${result.failed} 项`);
    }
  }

  private async runCloudScene(scene: XiaomiScene): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    FeedbackLogService.recordOperation('UI', `执行场景 ${scene.name}`);
    try {
      await xiaomiDataService.runScene(scene.sceneId, scene.homeId);
      this.toast(`已执行「${scene.name}」`);
    } catch (err) {
      const message = err instanceof Error ? err.message : '执行失败';
      Logger.error('run scene failed, %{public}s', message);
      this.toast(message);
    } finally {
      this.running = false;
    }
  }

  private toggleTimer(scene: LocalScene, enabled: boolean): void {
    LocalSceneStore.update({
      sceneId: scene.sceneId,
      name: scene.name,
      actions: scene.actions,
      timerEnabled: enabled,
      timerHour: scene.timerHour,
      timerMinute: scene.timerMinute,
      timerDays: scene.timerDays,
      lastFireDay: scene.lastFireDay
    });
    this.localScenes = localSceneService.scenes();
    FeedbackLogService.recordOperation('UI',
      `${enabled ? '开启' : '关闭'}本地智能定时 ${scene.name}`);
  }

  /** 打开编辑页并带上 sceneId，创建页据此进入编辑模式 */
  private openSceneEditor(scene: LocalScene): void {
    FeedbackLogService.recordOperation('UI', `编辑本地智能 ${scene.name}`);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/SceneCreatePage',
      params: { sceneId: scene.sceneId }
    });
  }

  private confirmDeleteLocalScene(scene: LocalScene): void {
    this.getUIContext().showAlertDialog({
      title: '删除智能',
      message: `确定删除「${scene.name}」吗？该操作只影响本机。`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: HwColor.danger,
        action: (): void => {
          LocalSceneStore.delete(scene.sceneId);
          this.localScenes = localSceneService.scenes();
          FeedbackLogService.recordOperation('UI', `删除本地智能 ${scene.name}`);
        }
      }
    });
  }

  // ==================== 文案 ====================

  /** 定时摘要：未开定时只报动作数，开了定时报「每天 23:00 · N 个动作」 */
  private sceneTimerText(scene: LocalScene): string {
    const actionText = `${scene.actions.length} 个动作`;
    if (!scene.timerEnabled) {
      return actionText;
    }
    const hour = scene.timerHour < 10 ? `0${scene.timerHour}` : `${scene.timerHour}`;
    const minute = scene.timerMinute < 10 ? `0${scene.timerMinute}` : `${scene.timerMinute}`;
    let days = '每天';
    if (scene.timerDays !== '1111111') {
      const names: string[] = ['一', '二', '三', '四', '五', '六', '日'];
      days = '周';
      for (let i = 0; i < 7; i++) {
        if (scene.timerDays.charAt(i) === '1') {
          days += names[i];
        }
      }
    }
    return `${days} ${hour}:${minute} · ${actionText}`;
  }

  /** 动作摘要：设备名 + 动作名，超出两条折成「等 N 项」 */
  private actionSummary(scene: LocalScene): string {
    if (scene.actions.length === 0) {
      return '暂无动作';
    }
    const parts: string[] = [];
    const limit = scene.actions.length > 2 ? 2 : scene.actions.length;
    for (let i = 0; i < limit; i++) {
      const action: LocalSceneAction = scene.actions[i];
      const value = action.valueText !== undefined && action.valueText.length > 0
        ? action.valueText : String(action.value);
      parts.push(`${action.deviceName} ${action.label} ${value}`);
    }
    const head = parts.join(' · ');
    return scene.actions.length > limit ? `${head} 等 ${scene.actions.length} 项` : head;
  }

  // ==================== 视图 ====================

  /** 分类芯片：与首页排序芯片同一套结构（底层自绘选中色 + Toggle 承载材质） */
  @Builder
  categoryChip(key: string, label: string) {
    Stack() {
      Row()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(HwRadius.pill)
        .backgroundColor(this.category === key ? this.accent() : withAlpha(HwColor.textPrimary, 0.06))

      MaterialCardLayer({ layerRadius: HwRadius.pill })

      Text(label)
        .fontFamily(this.appFontFamily(label))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontColor(this.category === key ? '#FFFFFF' : HwColor.textPrimary)
        .padding({ left: 16, right: 16, top: 7, bottom: 7 })
        .hitTestBehavior(HitTestMode.None)
    }
    .onClick((): void => {
      this.category = key;
    })
  }

  /**
   * 「执行」胶囊按钮的外观：实心主题色，与设备卡片的选中态同一语言。
   *
   * 刻意不接收回调参数：本仓库既有的 @Builder 都只接数据（字符串/对象），
   * 没有函数参数的先例，这里保持一致以规避 ArkTS 的按值传参限制。
   * 点击行为由调用方在展开后的 Stack 上挂载。
   */
  @Builder
  runButtonSkin() {
    Row()
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .borderRadius(HwRadius.pill)
      .backgroundColor(this.accent())

    Text('执行')
      .fontFamily(this.appFontFamily('执行'))
      .fontWeight(this.appFontWeight())
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .padding({ left: 16, right: 16 })
      .hitTestBehavior(HitTestMode.None)
  }

  /** 本地智能卡片 */
  @Builder
  localSceneCard(scene: LocalScene) {
    MaterialCard({
      cardPadding: HwSpace.lg,
      cardRadius: HwRadius.card,
      cardSpace: HwSpace.sm
    }) {
      Row({ space: HwSpace.sm }) {
        // 符号只从「本工程已验证可用」的集合里取：clock / arrow_up_arrow_down /
        // bell_fill / bolt_fill 在当前 SDK 都不存在（编译器只报 unknown resource，不给候选）。
        // 与 DeviceDetailPage 的做法一致，靠已验证符号 + 文案表达语义。
        SymbolGlyph(scene.timerEnabled ? $r('sys.symbol.moon_fill') : $r('sys.symbol.bolt'))
          .fontSize(20)
          .fontColor([this.accent()])
        Column({ space: 2 }) {
          Text(scene.name)
            .fontFamily(this.appFontFamily(scene.name))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.sceneTimerText(scene))
            .fontFamily(this.appFontFamily(this.sceneTimerText(scene)))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: scene.timerEnabled })
          .selectedColor(this.accent())
          .onChange((isOn: boolean): void => {
            this.toggleTimer(scene, isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: HwSpace.sm }) {
        Text(this.actionSummary(scene))
          .fontFamily(this.appFontFamily(this.actionSummary(scene)))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        IconCircleButton({
          symbol: $r('sys.symbol.square_and_pencil'),
          buttonSize: 30,
          iconSize: 15,
          tint: HwColor.textSecondary,
          onAction: (): void => {
            this.openSceneEditor(scene);
          }
        })
        IconCircleButton({
          symbol: $r('sys.symbol.trash'),
          buttonSize: 30,
          iconSize: 15,
          tint: HwColor.danger,
          onAction: (): void => {
            this.confirmDeleteLocalScene(scene);
          }
        })
        Stack() {
          this.runButtonSkin()
        }
        .height(30)
        .enabled(!this.running)
        .opacity(this.running ? 0.5 : 1)
        .onClick((): void => {
          this.runLocalScene(scene);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 云端场景卡片（自动化 / 手动） */
  @Builder
  cloudSceneCard(scene: XiaomiScene) {
    MaterialCard({
      cardPadding: HwSpace.lg,
      cardRadius: HwRadius.card,
      cardSpace: HwSpace.sm
    }) {
      Row({ space: HwSpace.sm }) {
        // 自动化/手动的区分交给上方分类芯片与副标题，图标统一用「一键执行」的语义
        SymbolGlyph($r('sys.symbol.power'))
          .fontSize(20)
          .fontColor([this.accent()])
        Column({ space: 2 }) {
          Text(scene.name)
            .fontFamily(this.appFontFamily(scene.name))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontColor(HwColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(scene.isEnabled ? '已启用 · 云端场景' : '已停用 · 云端场景')
            .fontFamily(this.appFontFamily(scene.isEnabled ? '已启用 · 云端场景' : '已停用 · 云端场景'))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Stack() {
          this.runButtonSkin()
        }
        .height(30)
        .enabled(!this.running)
        .opacity(this.running ? 0.5 : 1)
        .onClick((): void => {
          this.runCloudScene(scene);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 空态：图标 + 主副文案 */
  @Builder
  emptyState(title: string, hint: string) {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(30)
        .fontColor([HwColor.textSecondary])
      Text(title)
        .fontFamily(this.appFontFamily(title))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontColor(HwColor.textPrimary)
      Text(hint)
        .fontFamily(this.appFontFamily(hint))
        .fontWeight(this.appFontWeight())
        .fontSize(12)
        .fontColor(HwColor.textSecondary)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  @Builder
  localSection() {
    // 用 MaterialCard 而不是自绘底色：卡片自带 Toggle 材质承载层，
    // 这样「创建智能」这块才有与全站一致的沉浸光感。
    MaterialCard({
      cardDirection: FlexDirection.Row,
      cardSpace: HwSpace.sm,
      cardPadding: HwSpace.lg,
      cardRadius: HwRadius.card,
      cardHoverEffect: HoverEffect.Highlight,
      cardFocusable: true,
      cardOnClick: (): void => {
        FeedbackLogService.recordOperation('UI', '进入创建智能页');
        this.getUIContext().getRouter().pushUrl({ url: 'pages/SceneCreatePage' });
      }
    }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([this.accent()])
      Text('创建智能')
        .fontFamily(this.appFontFamily('创建智能'))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontColor(HwColor.textPrimary)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([HwColor.textSecondary])
    }

    if (this.localScenes.length > 0) {
      Text(`我的智能（${this.localScenes.length}）`)
        .fontFamily(this.appFontFamily(`我的智能（${this.localScenes.length}）`))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontColor(HwColor.textSecondary)
        .width('100%')
        .padding({ left: 4, top: 4 })
      ForEach(this.localScenes, (scene: LocalScene) => {
        this.localSceneCard(scene)
      }, (scene: LocalScene) => `${scene.sceneId}_${scene.timerEnabled ? 1 : 0}_${scene.lastFireDay}`)
    } else {
      this.emptyState('还没有本地智能', '点击上方「创建智能」新建定时或批量动作')
    }
  }

  @Builder
  cloudSection() {
    if (this.loading && this.cloudScenes.length === 0) {
      Row({ space: 6 }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(HwColor.textSecondary)
        Text('加载中…')
          .fontFamily(this.appFontFamily('加载中…'))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(HwColor.textSecondary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 40, bottom: 40 })
    } else if (this.filteredCloudScenes().length > 0) {
      ForEach(this.filteredCloudScenes(), (scene: XiaomiScene) => {
        this.cloudSceneCard(scene)
      }, (scene: XiaomiScene) => `${scene.sceneId}_${scene.isEnabled ? 1 : 0}`)
    } else {
      this.emptyState(this.category === CATEGORY_AUTO ? '没有自动化' : '没有手动场景',
        '在米家 App 里创建后会同步到这里')
    }
  }

  /** 当前分类下的云端场景 */
  private filteredCloudScenes(): XiaomiScene[] {
    const wanted = this.category === CATEGORY_AUTO ? 'auto' : 'manual';
    const list: XiaomiScene[] = [];
    for (let i = 0; i < this.cloudScenes.length; i++) {
      if (this.cloudScenes[i].type === wanted) {
        list.push(this.cloudScenes[i]);
      }
    }
    return list;
  }

  @Builder
  pageContent() {
    Column({ space: HwSpace.md }) {
      Blank().height(this.topOffset() + (this.cardsFromTop ? 0 : 4))

      Row({ space: HwSpace.sm }) {
        this.categoryChip(CATEGORY_LOCAL, '本地')
        this.categoryChip(CATEGORY_AUTO, '自动化')
        this.categoryChip(CATEGORY_MANUAL, '手动')
      }
      .width('100%')

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontFamily(this.appFontFamily(this.errorMessage))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(HwColor.danger)
          .width('100%')
          .padding({ left: 4, right: 4 })
      }

      if (this.category === CATEGORY_LOCAL) {
        this.localSection()
      } else {
        this.cloudSection()
      }

      Blank().height(24)
    }
    .width('100%')
    .constraintSize({ maxWidth: this.maxContentWidth() })
    .padding({ left: this.contentPadding(), right: this.contentPadding() })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      AccentColorSentinel()
      AppBackground()

      Column() {
        Scroll() {
          Column() {
            this.pageContent()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        // align 必须挂在 Scroll 上：通用 align 属性的默认值是 Alignment.Center，
        // 挂在内层 Column 上不起作用，内容就会被垂直居中而不是从顶部排。
        .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      // 标题栏：与全站其余页面一致的浅色毛玻璃
      Row() {
        IconCircleButton({
          symbol: $r('sys.symbol.chevron_left'),
          buttonSize: 40,
          iconSize: 20,
          onAction: (): void => {
            router.back();
          }
        })
        Text('智能')
          .fontFamily(this.appFontFamily('智能'))
          .fontWeight(this.appFontWeight())
          .margin({ left: HwSpace.md })
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(HwColor.textPrimary)
        Blank()
        IconCircleButton({
          symbol: $r('sys.symbol.arrow_counterclockwise'),
          buttonSize: 40,
          iconSize: 20,
          buttonEnabled: !this.loading,
          spinning: this.loading,
          onAction: (): void => {
            this.reload();
          }
        })
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
