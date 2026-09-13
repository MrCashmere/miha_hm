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

import { LengthMetrics } from '@kit.ArkUI';
import { applyMaterialCarrier, isApi26OrAbove, pressLightColor } from '../utils/SystemMaterial';
import { HwGlassCardColor, HwRadius, withAlpha } from '../utils/DesignTokens';

/**
 * 流光光晕的半径（vp）。
 *
 * 流光不是描边：它是**跟着手指走的一小团柔光**（HdsTab 那种），
 * 手指滑到哪、光就落在哪。半径必须收着给：130 那种尺寸会盖住大半张卡片，
 * 看起来像「整卡高亮选中」而不是一点光；64 大致是一枚指腹的范围。
 */
const PRESS_GLOW_RADIUS: number = 64;
/**
 * 光晕中心浓度。
 *
 * 光本身不该是一块实色。压到 0.3 出头是「照亮玻璃表面」，
 * 再浓就变成往卡片上刷了一层主题色。
 */
const PRESS_GLOW_ALPHA: number = 0.32;
/**
 * 溢出光晕的半径与浓度（vp）。
 *
 * 这层是**卡片外**那圈光：它铺到相邻卡片的边缘上，隔着对方的玻璃透出来，
 * 看起来就是「光打在邻卡边缘的反光」。刻意**不抬高 zIndex**，
 * 让后画的相邻卡片盖住它——盖住之后只剩透过玻璃的一点亮度，
 * 不会把邻卡内部照亮（这是抽掉「描边式外发光」的原因）。
 */
const PRESS_SPILL_RADIUS: number = 110;
/** 比手指光斑淡得多：它是溢出到别人身上的光，不该抢主角 */
const PRESS_SPILL_ALPHA: number = 0.14;
/** 溢出光晕的画布边长，理由同 §7.9：必须 ≥ 2×半径，否则光斑被画布直边切断 */
const PRESS_SPILL_SIZE: number = PRESS_SPILL_RADIUS * 2;

/**
 * 卡片沉浸光感承载层。
 *
 * 官方文档《组件适配沉浸光感》规定：其余组件（布局容器等）的通用属性
 * systemMaterial **只在 Navigation / NavDestination 标题栏或底部 TabBar 生效**，
 * 内容区不生效；而按钮与选择类组件（Button / Select / Toggle / Slider 等）
 * 可在页面内全部区域生效。
 *
 * 因此卡片不能用 Column/Row 挂材质，必须是选择类组件。各 ToggleType 的差异
 * （官方原文）：
 *   - Checkbox：**当前未适配沉浸光感效果，设置后无效果**；
 *   - Switch  ：材质参数只是「开启标记」，实际用组件内部预设视觉参数，
 *               只影响滑块大小/样式/阴影 —— 永远只覆盖开关本体那片区域；
 *   - Button  ：效果与 Button 组件相同，影响背景色、边框、阴影。
 *
 * 卡片需要的是「覆盖整块矩形」的形态，所以用 ToggleType.Button。
 *
 * 底色与顺序（官方《沉浸光感常见问题》）：
 *   - 「沉浸光感的视觉层级位于组件的 backgroundColor、backgroundBlurStyle 等属性
 *     之下」，不透明背景会盖住材质 → 承载层显式设 `Color.Transparent`；
 *   - 「将 systemMaterial 放在其他样式属性（如背景色、边框、阴影等）之后设置」
 *     → 用 attributeModifier 挂在属性链最末（见下方 Toggle 的写法）。
 *
 * 材质渲染区域由组件布局区域决定，所以承载层用 matchParent 铺满整卡。
 *
 * 圆角：**承载层必须沿用卡片自身的圆角**。ToggleType.Button 会画出自己的按钮图形
 * （自带一圈圆角 + 描边），如果它用默认的小圆角、而外壳按 cardRadius 裁切，
 * 卡片里就会出现一个「更小圆角的内嵌边框」。所以把 cardRadius 透传下来统一。
 */
@Component
export struct MaterialCardLayer {
  /** 与 MaterialCard 的 cardRadius 保持一致，避免出现内嵌的小圆角边框 */
  @Prop layerRadius: Length = 20;
  /**
   * 是否让材质自带投影。
   *
   * 材质的 applyShadow 默认为 true。卡片尺寸大、这层投影是加分项；
   * 但小尺寸芯片（房间筛选等）上它看起来就像「按钮背后顶了一层影子」，
   * 这类地方传 false。
   */
  @Prop layerShadow: boolean = true;

  build() {
    Toggle({ type: ToggleType.Button, isOn: false })
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .borderRadius(this.layerRadius)
      // 必须显式透明：不透明背景色会盖在材质层之上
      .backgroundColor(Color.Transparent)
      .enabled(false)
      .focusable(false)
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
      // systemMaterial 放在所有样式属性之后
      .attributeModifier({
        applyNormalAttribute: (instance: ToggleAttribute): void => {
          applyMaterialCarrier(instance, false, false, this.layerShadow);
        }
      })
  }
}
/**
 * 沉浸光感卡片容器。
 *
 * 属性与用法对齐旧的「.backgroundColor + .attributeModifier(immersiveMaterialModifier)」
 * 写法，迁移时把卡片容器的这些属性搬到 MaterialCard 上即可，内部内容放进尾随闭包。
 *
 * 注意：ArkTS 不允许在「尾随闭包初始化的自定义组件」后面继续链式调用属性
 * （`MaterialCard({...}) { ... }.onClick(...)` 会报 “Cannot find name 'onClick'”），
 * 所以点击、菜单、置灰、透明度、对齐这些原先写在卡片容器上的属性，都必须通过下面的
 * card* 参数传入。padding 也不再挂在卡片外层，而是挂到内部内容容器上，
 * 这样承载层才能铺满整张卡片（含 padding 区域）。
 * 需要 `bindSheet()` 的卡片请在本组件外面再包一层 `.width('100%')` 的 Column。
 */
@Component
export struct MaterialCard {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  /**
   * 主题色依赖。
   *
   * HwColor 是模块级对象，改属性不会触发任何刷新；卡片内大量元素用 HwColor.primary，
   * 如果组件不引用 accentColor，切主题色时页面不会重新求值，配色会停留在旧值。
   * 卡片遍布所有页面且始终在渲染树里，挂在这里能保证「切色即生效」。
   */
  @StorageProp('accentColor') accentColor: string = '';

  /**
   * 主题色流光开关（只用来建立依赖）。
   *
   * 真正取色走 `pressLightColor()`，它读的是 AppStorage。ArkUI 按表达式登记依赖：
   * 不声明这个订阅键，拨动开关时已经画出来的卡片不会重新求值，
   * 光晕要等下一次重建才生效。
   */
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
  /**
   * 卡片流光触感（默认关）。
   *
   * 关：只画溢出到卡间缝隙的环境光；开：再叠一层手指底下的跟手光斑。
   * 底栏的流光与它无关，不受影响。
   */
  @StorageProp('cardGlowTouch') glowTouchEnabled: boolean = false;

  /**
   * 卡片底色（含可选的「卡片沾色」）。
   *
   * 必须走订阅键：`HwGlassCardColor.surface` 是模块级对象的属性，
   * 直接读它不会被依赖追踪，开关沾色时已经画出来的卡片不会更新。
   * 原先这里是 `@Prop cardBackground = HwGlassCardColor.surface`，
   * 默认值只在组件构造时求值一次，同样跟不上开关变化。
   */
  @StorageProp('cardSurface') cardSurface: string = '';
  /**
   * 卡片沾色叠加层的颜色（空串表示不沾色）。
   *
   * 沾色**必须叠在材质之上**，不能混进卡片底色：材质生效时外壳底色是透明的
   * （见 shellBackground），混进去的主题色根本不会被画出来。
   */
  @StorageProp('cardTintColor') cardTint: string = '';
  @Prop cardBorderColor: ResourceColor = HwGlassCardColor.border;
  @Prop cardBorderWidth: number = 1;
  @Prop cardRadius: Length = 20;
  /**
   * 卡片内边距 / 外边距。
   *
   * 刻意**不用 `Padding | Length` 这类联合类型**：ArkTS 无法为联合类型中的
   * 对象字面量定类型，传 `{ top: 12, bottom: 12 }` 会报
   * `arkts-no-untyped-obj-literals`。收窄成 Padding/Margin 后调用方两种写法都合法。
   */
  @Prop cardPadding: Length = 0;
  @Prop cardMargin: Margin = { top: 0, right: 0, bottom: 0, left: 0 };
  @Prop cardWidth: Length = '100%';
  /** 是否保留卡片底色。沉浸光感生效时置 false 可获得更通透的观感。 */
  @Prop cardOpaqueBackground: boolean = true;
  /** 卡片是否可被点击/聚焦（由调用方通过 cardOnClick 等挂载具体行为）。 */
  @Prop cardHoverEffect: HoverEffect = HoverEffect.None;
  @Prop cardFocusable: boolean = false;
  /** 该卡片是否需要承载沉浸光感。滚动列表等长列表内可主动关闭以省性能。 */
  @Prop cardMaterialEnabled: boolean = true;
  /**
   * 卡片内容的主轴方向。原卡片容器是 Row 时必须传 FlexDirection.Row，
   * 否则内容会被压成竖向排列（Column 语义会改变布局）。
   */
  @Prop cardDirection: FlexDirection = FlexDirection.Column;
  /** 子元素主轴间距（vp），对应原容器 Row/Column 的 space 参数。 */
  @Prop cardSpace: number = 0;
  /** 对应原卡片容器上的 .enabled()。 */
  @Prop cardEnabled: boolean = true;
  /** 对应原卡片容器上的 .opacity()。 */
  @Prop cardOpacity: number = 1;
  /** 对应原卡片容器上的 .bindMenu()，为空数组时不绑定菜单。 */
  @Prop cardMenuItems: MenuElement[] = [];
  /**
   * 子元素在交叉轴上的对齐方式。默认 ItemAlign.Center，对齐原 Row(VerticalAlign.Center)
   * 与 Column(HorizontalAlign.Center) 的默认行为——Flex 的默认值是 ItemAlign.Start，
   * 不显式指定会让卡片内容贴顶/贴左对齐。
   */
  @Prop cardAlignItems: ItemAlign = ItemAlign.Center;

  /**
   * 流光状态。
   *
   * `glowOn` 手指是否落在卡片上，`glowX/glowY` 光斑中心（相对卡片左上角，vp）。
   * 用 `@State`：它们是渲染属性，必须触发重绘才会出现、移动、消失。
   */
  @State glowOn: boolean = false;
  @State glowX: number = 0;
  @State glowY: number = 0;
  /**
   * 坐标换算用的一组普通字段（不参与渲染，所以不用 @State）。
   *
   * 光要**跟着手指在屏幕上走**，而触摸事件给的是窗口坐标：必须减去卡片自身
   * 在窗口中的原点才能换算成卡片内坐标。
   *   - `cardWinX/Y`：卡片左上角在窗口中的位置。按下那一瞬由
   *     `windowX - x` 反推得到（这时组件内坐标一定是准的），之后靠
   *     `onAreaChange` 的**位移增量**维护——列表滚动时卡片在动，增量必须跟上，
   *     否则手指不动、页面滚动，光斑就会黏在卡片原处不动。
   *   - `lastTouchWinX/Y`：最近一次触摸的窗口坐标，卡片位置变了要拿它重算。
   *   - `lastAreaX/Y` + `areaReady`：上一次 onAreaChange 报的全局坐标，用来求增量。
   *     只取增量、不用绝对值：`globalPosition` 的原点与 `windowX/Y` 未必是同一套，
   *     但两者在滚动中的**变化量**必然一致。
   */
  private cardWinX: number = 0;
  private cardWinY: number = 0;
  private lastTouchWinX: number = 0;
  private lastTouchWinY: number = 0;
  private lastAreaX: number = 0;
  private lastAreaY: number = 0;
  private areaReady: boolean = false;

  /** 对应原卡片容器上的 .onClick()。 */
  cardOnClick: () => void = (): void => {
  };

  /**
   * 对应原卡片容器上的 .onLongPress()：长按触发。
   *
   * 为什么不继续用 `cardMenuItems`（bindMenu）：bindMenu 在触摸屏上默认由**点击**
   * 触发，会出现「点一下卡片就弹出菜单」的意外行为，且 bindMenu 本身无法区分
   * 点击与长按。需要长按菜单的卡片请改用本回调自行拉起 ActionSheet/弹窗。
   */
  cardOnLongPress: () => void = (): void => {
  };

  @BuilderParam cardContent: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  /** 沉浸光感是否生效：API 26 以上 + 应用开关打开 + 本卡允许承载 */
  private materialActive(): boolean {
    return this.cardMaterialEnabled && this.immersiveLightEnabled && isApi26OrAbove();
  }

  /**
   * 是否用「主题色流光」替代系统的白色按压高亮。
   *
   * 要求三件事同时成立：本卡承载材质、开了主题色流光开关、能取到主题色。
   * 任一条不成立就完全沿用原来的行为（系统 HoverEffect.Highlight 白光），
   * 所以这个开关关掉时观感与改动前一致。
   */
  private themedLightAvailable(): boolean {
    return this.materialActive()
      && pressLightColor(this.pressGlowSwitch, this.accentColor).length > 0;
  }

  /** 主题色流光当前是否可用（主题色 + 开关 + 材质都在）。空串表示不可用 */
  private glowAccent(): string {
    if (!this.cardEnabled || !this.themedLightAvailable()) {
      return '';
    }
    return pressLightColor(this.pressGlowSwitch, this.accentColor);
  }

  /** 是否有光可画（按下 + 主题色流光可用） */
  private glowVisible(): boolean {
    return this.glowOn && this.glowAccent().length > 0;
  }

  /**
   * 「卡片流光触感」关闭时，按压卡片**一点光都不出现**——跟手光斑和溢出到
   * 卡间缝隙的环境光都不画。
   *
   * 这条是踩出来的：第一版只关掉跟手光斑、留着环境光，但环境光的圆心
   * 本来就跟着手指走，看起来仍是「触碰反馈的流光」，等于开关没生效。
   * 两层要么一起亮，要么一起不亮。
   */
  private spillVisible(): boolean {
    return this.glowVisible() && this.glowTouchEnabled;
  }

  /** 是否画手指底下的跟手光斑：同样要求「卡片流光触感」打开 */
  private touchGlowVisible(): boolean {
    return this.glowVisible() && this.glowTouchEnabled;
  }

  /**
   * 实际下发的悬停/按压效果。
   *
   * 主题色流光可用时**必须把 HoverEffect.Highlight 摘掉**：
   * 那是系统画的一层白光，会和主题色流光同时出现，颜色对不上。
   * 判定只看「流光可不可用」，不能掺进按压状态——否则按下的瞬间
   * 状态一变、白光又会闪一下。
   */
  private effectiveHoverEffect(): HoverEffect {
    return this.themedLightAvailable() ? HoverEffect.None : this.cardHoverEffect;
  }

  /**
   * 跟手滑动的流光。
   *
   * 触摸坐标用的是 `touches[0].x/y`——它相对**绑定 onTouch 的组件**（卡片外壳），
   * 正好就是光晕层要用的坐标系（光晕锚点就贴在卡片左上角）。
   *
   * Move 也要处理：流光之所以像「光」而不像「按下高亮」，
   * 就在于手指在卡片上滑动时它会跟着走。
   * 抬起与取消都必须熄灭，否则会在卡片上留一块不会消失的光斑。
   */
  private updatePressGlow(event: TouchEvent): void {
    if (this.glowAccent().length === 0) {
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.glowOn = false;
      return;
    }
    if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
      return;
    }
    if (event.touches.length === 0) {
      return;
    }
    const touch = event.touches[0];
    if (event.type === TouchType.Down) {
      // 按下这一瞬 `x/y` 一定是相对当前卡片位置的准确值，用它反推卡片原点
      this.cardWinX = touch.windowX - touch.x;
      this.cardWinY = touch.windowY - touch.y;
    }
    this.lastTouchWinX = touch.windowX;
    this.lastTouchWinY = touch.windowY;
    this.syncGlowPosition();
    this.glowOn = true;
  }

  /**
   * 用最近一次触摸的窗口坐标重算光斑位置。
   *
   * 手指不动、页面在滚（惯性滑动、或手指按住后列表继续走）时也要调用它，
   * 所以 `onAreaChange` 里同样会调——这正是「光效追随手指而不是留在卡片原处」
   * 与「卡片自己移动了但手指没动」这两种情况的分界。
   */
  private syncGlowPosition(): void {
    this.glowX = this.lastTouchWinX - this.cardWinX;
    this.glowY = this.lastTouchWinY - this.cardWinY;
  }

  /**
   * 光晕的径向渐变色标。
   *
   * 由内到外三档淡出：中心最亮、中段已经散开、到半径处完全透明。
   * 只用一档实色会得到一个硬边圆盘，看着像贴纸而不是光。
   */
  private glowGradientColors(): Array<[ResourceColor, number]> {
    const accent = this.glowAccent();
    return [
      [withAlpha(accent, PRESS_GLOW_ALPHA), 0],
      [withAlpha(accent, PRESS_GLOW_ALPHA * 0.55), 0.42],
      [withAlpha(accent, PRESS_GLOW_ALPHA * 0.18), 0.72],
      [Color.Transparent, 1]
    ];
  }

  /**
   * 溢出光晕的径向渐变色标。比手指光斑更柔、更淡。
   */
  private spillGradientColors(): Array<[ResourceColor, number]> {
    const accent = this.glowAccent();
    return [
      [withAlpha(accent, PRESS_SPILL_ALPHA), 0],
      [withAlpha(accent, PRESS_SPILL_ALPHA * 0.72), 0.35],
      [withAlpha(accent, PRESS_SPILL_ALPHA * 0.28), 0.68],
      [Color.Transparent, 1]
    ];
  }

  /**
   * 溢出到卡片之外的那圈光。
   *
   * 画布比卡片大得多、以手指为圆心，靠一个 **0 尺寸锚点** 甩到卡片外面去
   * （见 §7.9：直接放一个比父容器大的子节点会把卡片撑大）。
   * 它在 cardBody 里排在最前面，卡内那半被上面的材质层盖住，
   * 只有漏到卡片外的部分看得见——于是相邻卡片边缘会透出一点亮，
   * 而邻卡内部不会被照亮。
   */
  @Builder
  glowSpillLayer() {
    if (this.spillVisible()) {
      Stack() {
        Column()
          .width(PRESS_SPILL_SIZE)
          .height(PRESS_SPILL_SIZE)
          .position({
            x: this.glowX - PRESS_SPILL_RADIUS,
            y: this.glowY - PRESS_SPILL_RADIUS
          })
          .radialGradient({
            center: [PRESS_SPILL_RADIUS, PRESS_SPILL_RADIUS],
            radius: PRESS_SPILL_RADIUS,
            colors: this.spillGradientColors()
          })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
      .width(0)
      .height(0)
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    }
  }

  @Builder
  cardBody() {
    // 溢出光晕在最底层：卡内部分由上面的材质层盖住，只留卡片外那圈
    this.glowSpillLayer()
    if (this.materialActive()) {
      MaterialCardLayer({ layerRadius: this.cardRadius })
    }
    if (this.cardTint.length > 0) {
      // 沾色层：叠在材质之上、内容之下。
      //
      // 尺寸必须用 matchParent 而不是 width/height('100%')：百分比在 Stack 内按
      // **父级可用尺寸**解析，高度会被撑到容器满高，卡片跟着胀大；
      // matchParent 按父级实测尺寸解析，随内容走（与 MaterialCardLayer 同一写法）。
      //
      // 圆角**必须自己给**：外壳为了让溢出光晕漏出去已经不设 clip(true)，
      // 裁切责任下移到每一层。这一层是整块方形底色，不给圆角就会在卡片四角露出直角。
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(this.cardRadius)
        .backgroundColor(this.cardTint)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    // 流光压在材质之上、内容之下：光打在玻璃表面，文字仍然压在光上面保持清晰
    this.pressGlowLayer()
    Flex({
      direction: this.cardDirection,
      space: { main: LengthMetrics.vp(this.cardSpace) },
      alignItems: this.cardAlignItems
    }) {
      this.cardContent()
    }
    .width('100%')
    .padding(this.cardPadding)
  }

  /**
   * 卡片外壳底色。
   *
   * 材质生效时必须让出底色：外壳底色会垫在承载层的材质之下，
   * 叠出灰感（玻璃底色 #B3FFFFFF 叠在材质下同样是「发灰」）。
   * 让出后由承载层自己负责底色 + 材质。
   */
  private shellBackground(): ResourceColor {
    if (this.materialActive()) {
      // 材质生效时必须让出底色，否则底色会垫在材质之下叠出灰感
      return Color.Transparent;
    }
    if (!this.cardOpaqueBackground) {
      return Color.Transparent;
    }
    return this.cardSurface.length > 0 ? this.cardSurface : HwGlassCardColor.surface;
  }

  /**
   * 不承载沉浸光感时的降级：毛玻璃。
   *
   * 之前降级路径只是把不透明底色画上去，卡片变成一块死板色块；
   * 这里补上 `backgroundBlurStyle`，配合 HwGlassCardColor.surface 的 70% 透明度
   * （见 DesignTokens.applyAppTheme），得到与沉浸光感同一观感的磨砂玻璃。
   * 材质生效时用 BlurStyle.NONE 关掉，避免与材质叠加。
   */
  private shellBlurStyle(): BlurStyle {
    return this.materialActive() ? BlurStyle.NONE : BlurStyle.Thin;
  }

  /**
   * 跟手流光层。
   *
   * 三点约束（都是真机调出来的）：
   *   1. **尺寸跟随卡片**（matchParent）：光斑只落在卡片里，绝不溢到相邻卡片内部；
   *      超出卡片的部分由外壳的 `clip(true)` 连同圆角一起裁掉——
   *      这一点与底部 HdsTab 的流光一致，它在滑动时同样不会漏到栏外。
   *   2. **压在材质之上、内容之下**：光打在玻璃表面上，到卡片圆角边缘被裁断，
   *      接上材质自己那圈边缘折射，才是液态玻璃的观感。
   *      实测**不能放在材质之下**：沉浸光感材质不采样同一 Stack 里的兄弟节点，
   *      光会被整层盖住，真机上完全看不见。
   *   3. **只覆盖手指周围一小片**：见 PRESS_GLOW_RADIUS，光斑大了就成了整卡高亮。
   *
   * `hitTestBehavior(None)` 保证它不吃触摸。
   */
  @Builder
  pressGlowLayer() {
    if (this.touchGlowVisible()) {
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        // 外壳不再 clip（要放行溢出光晕），所以这一层自己带圆角，
        // 光斑到卡片圆角处收住，接上材质边缘的折射
        .borderRadius(this.cardRadius)
        .radialGradient({
          center: [this.glowX, this.glowY],
          radius: PRESS_GLOW_RADIUS,
          colors: this.glowGradientColors()
        })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
  }

  /**
   * 卡片外壳（无菜单）。
   *
   * 与下面的 `cardShellWithMenu` 只差末尾一个 `.bindMenu`：**改属性时两处都要改**。
   * ArkTS 不能在 @Builder 调用后面继续链式加属性，也没法条件绑定 bindMenu，
   * 所以这段重复躲不掉。
   */
  @Builder
  cardShell() {
    Stack() {
      this.cardBody()
    }
    .width(this.cardWidth)
    .margin(this.cardMargin)
    .borderRadius(this.cardRadius)
    .backgroundColor(this.shellBackground())
    .backgroundBlurStyle(this.shellBlurStyle())
    .border({ width: this.cardBorderWidth, color: this.cardBorderColor })
    // 刻意**不设 clip(true)**：溢出光晕要漏到卡片外面去，clip 会把它整圈切掉。
    // 需要裁切的每一层都自己带圆角（材质层、沾色层、手指光斑），效果等价。
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const gx: number = typeof newArea.globalPosition.x === 'number' ? newArea.globalPosition.x : this.lastAreaX;
      const gy: number = typeof newArea.globalPosition.y === 'number' ? newArea.globalPosition.y : this.lastAreaY;
      if (this.areaReady) {
        // 只取增量：卡片被滚动带走时光斑要跟着手指重算，不然会黏在卡片原处
        this.cardWinX += gx - this.lastAreaX;
        this.cardWinY += gy - this.lastAreaY;
        if (this.glowOn) {
          this.syncGlowPosition();
        }
      }
      this.lastAreaX = gx;
      this.lastAreaY = gy;
      this.areaReady = true;
    })
    .hoverEffect(this.effectiveHoverEffect())
    .onTouch((event: TouchEvent): void => {
      this.updatePressGlow(event);
    })
    .focusable(this.cardFocusable)
    .enabled(this.cardEnabled)
    .opacity(this.cardOpacity)
    .onClick(() => {
      this.cardOnClick();
    })
    .gesture(
      LongPressGesture()
        .onAction((): void => {
          this.cardOnLongPress();
        })
    )
  }

  build() {
    // 两个分支只差一个 bindMenu：bindMenu 不能条件绑定，只能分开写。
    // 属性全部收在 cardShell 里，这里只补 bindMenu，避免两份属性列表各自漂移。
    if (this.cardMenuItems.length > 0) {
      this.cardShellWithMenu()
    } else {
      this.cardShell()
    }
  }

  @Builder
  cardShellWithMenu() {
    Stack() {
      this.cardBody()
    }
    .width(this.cardWidth)
    .margin(this.cardMargin)
    .borderRadius(this.cardRadius)
    .backgroundColor(this.shellBackground())
    .backgroundBlurStyle(this.shellBlurStyle())
    .border({ width: this.cardBorderWidth, color: this.cardBorderColor })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const gx: number = typeof newArea.globalPosition.x === 'number' ? newArea.globalPosition.x : this.lastAreaX;
      const gy: number = typeof newArea.globalPosition.y === 'number' ? newArea.globalPosition.y : this.lastAreaY;
      if (this.areaReady) {
        this.cardWinX += gx - this.lastAreaX;
        this.cardWinY += gy - this.lastAreaY;
        if (this.glowOn) {
          this.syncGlowPosition();
        }
      }
      this.lastAreaX = gx;
      this.lastAreaY = gy;
      this.areaReady = true;
    })
    .hoverEffect(this.effectiveHoverEffect())
    .onTouch((event: TouchEvent): void => {
      this.updatePressGlow(event);
    })
    .focusable(this.cardFocusable)
    .enabled(this.cardEnabled)
    .opacity(this.cardOpacity)
    .onClick(() => {
      this.cardOnClick();
    })
    .gesture(
      LongPressGesture()
        .onAction((): void => {
          this.cardOnLongPress();
        })
    )
    .bindMenu(this.cardMenuItems)
  }
}

/**
 * 半模态弹窗（向上弹出的卡片）的沉浸光感面板。
 *
 * 为什么不能只靠 `bindSheet` 的 `systemMaterial`：那个材质挂在**弹窗面板本身**上，
 * 和卡片遇到的是同一堵墙——非选择类组件的 systemMaterial 在内容区不生效，
 * 真机表现就是弹窗面板完全没有光感（内层的 MaterialCard 有，面板是平的）。
 * 所以这里沿用与 MaterialCard 完全一致的解法：用 ToggleType.Button 承载层
 * 铺满整个面板，材质由承载层渲染，弹窗面板自然整块透出光感。
 *
 * 与 MaterialCard 只有两点差别：
 *   1. 强制铺满父容器。弹窗面板是固定高度（SheetSize.MEDIUM 等），材质必须裹住
 *      整块面板；只裹内容高度会让面板下半截露出系统底色。
 *   2. 圆角只切上方两角。半模态从底部升起，下方两角贴着屏幕边缘。
 *      承载层仍按统一圆角绘制（它自己会画按钮图形），再靠外层的 clip 把下两角切平，
 *      避免出现 MaterialCard 注释里提到的「内嵌小圆角边框」。
 */
@Component
export struct MaterialSheetPanel {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  /** 主题色依赖：面板内容大量使用 HwColor.primary，切色时需要重绘 */
  @StorageProp('accentColor') accentColor: string = '';
  /** 面板底色：与卡片同源，跟随「卡片沾色」开关 */
  @StorageProp('cardSurface') cardSurface: string = '';

  /** 面板上方两角的圆角 */
  @Prop panelRadius: number = HwRadius.card;
  /** 内容内边距。传 0 则由内容自己控制留白 */
  @Prop panelPadding: Length = 0;

  @BuilderParam panelContent: () => void = this.emptyPanel;

  @Builder
  emptyPanel() {
  }

  private materialActive(): boolean {
    return this.immersiveLightEnabled && isApi26OrAbove();
  }

  @Builder
  panelBody() {
    if (this.materialActive()) {
      MaterialCardLayer({ layerRadius: this.panelRadius })
    }
    Column() {
      this.panelContent()
    }
    .width('100%')
    .height('100%')
    .padding(this.panelPadding)
  }

  build() {
    Stack() {
      this.panelBody()
    }
    .width('100%')
    .height('100%')
    .borderRadius({
      topLeft: this.panelRadius,
      topRight: this.panelRadius,
      bottomLeft: 0,
      bottomRight: 0
    })
    // 材质生效时必须让出底色，否则底色会垫在材质之下叠出灰感
    .backgroundColor(this.materialActive() ? Color.Transparent
      : (this.cardSurface.length > 0 ? this.cardSurface : HwGlassCardColor.surface))
    .clip(true)
  }
}

/**
 * 主题色依赖标记。
 *
 * HwColor 是模块级对象，改属性不会触发任何组件刷新。把本组件放在页面的
 * Stack 里（零尺寸，不参与布局），它读取 accentColor，从而在切换主题色时
 * 让整个页面重新求值，页面内所有 HwColor.primary 才会取到新颜色。
 *
 * 为什么需要它：@StorageProp + @Watch 只触发回调、不重新求值组件；必须有一个
 * 始终渲染的表达式真正读到该值，ArkUI 才会把页面标记为脏并重建。
 */
@Component
export struct AccentColorSentinel {
  @StorageProp('accentColor') accentColor: string = '';

  build() {
    // 尺寸为 0、不参与命中测试：纯粹用来建立数据依赖
    Row()
      .width(0)
      .height(0)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
      .backgroundColor(this.accentColor.length > 0 ? this.accentColor : Color.Transparent)
  }
}
