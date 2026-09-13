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
import { applyMaterialCarrier, isApi26OrAbove } from '../utils/SystemMaterial';
import { HwGlassCardColor, HwRadius } from '../utils/DesignTokens';

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
          applyMaterialCarrier(instance, false);
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

  /** 卡片底色。API 26 沉浸光感生效时会被材质覆盖，保留作为降级底色。 */
  @Prop cardBackground: ResourceColor = HwGlassCardColor.surface;
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

  @Builder
  cardBody() {
    if (this.materialActive()) {
      MaterialCardLayer({ layerRadius: this.cardRadius })
    }
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
    return this.cardOpaqueBackground ? this.cardBackground : Color.Transparent;
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

  build() {
    // 两个分支只差一个 bindMenu，合并成一处以免后续改属性时漏改一个分支
    if (this.cardMenuItems.length > 0) {
      Stack() {
        this.cardBody()
      }
      .width(this.cardWidth)
      .margin(this.cardMargin)
      .borderRadius(this.cardRadius)
      .backgroundColor(this.shellBackground())
      .backgroundBlurStyle(this.shellBlurStyle())
      .border({ width: this.cardBorderWidth, color: this.cardBorderColor })
      .clip(true)
      .hoverEffect(this.cardHoverEffect)
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
    } else {
      Stack() {
        this.cardBody()
      }
      .width(this.cardWidth)
      .margin(this.cardMargin)
      .borderRadius(this.cardRadius)
      .backgroundColor(this.shellBackground())
      .backgroundBlurStyle(this.shellBlurStyle())
      .border({ width: this.cardBorderWidth, color: this.cardBorderColor })
      .clip(true)
      .hoverEffect(this.cardHoverEffect)
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
    .backgroundColor(this.materialActive() ? Color.Transparent : HwGlassCardColor.surface)
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
