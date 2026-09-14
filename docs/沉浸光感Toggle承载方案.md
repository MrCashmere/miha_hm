# 沉浸光感：用 Toggle 绕过生效范围限制

鸿蒙 API 26 的沉浸光感（`systemMaterial`）有一条生效范围限制：**普通组件在页面内容区挂材质不会渲染**。
本文记录如何用 `Toggle` 绕过它 —— 这是本仓库所有卡片、按钮、弹窗光感的共同基础。

参考实现：`entry/src/main/ets/utils/SystemMaterial.ets`（材质与下发）、
`entry/src/main/ets/components/MaterialCard.ets`（承载层与三种外壳）。

---

## 1. 限制是什么

官方《组件适配沉浸光感》把组件分成两类：

| 类别 | 生效范围 |
| --- | --- |
| **按钮与选择类**：`Button` / `Select` / `Toggle` / `Slider` / `ChipGroup` / `SegmentButton` | 页面内**全部区域**都可生效 |
| **其余组件**：`Column` / `Row` / `Text` / `TextInput` 等 | 只在 **Navigation / NavDestination 标题栏**或 `barPosition: BarPosition.End` 的**底部 TabBar** 中生效 |

也就是说，内容区里这样写是**没有任何效果**的：

```ts
Column()
  .backgroundColor(Color.Transparent)
  .systemMaterial(material)      // ✗ 布局容器在内容区不生效
```

最坑的地方是**它不报错、也不警告**，只是安静地什么都不画 —— 看起来和"材质没配好"一模一样。

---

## 2. 为什么 Toggle 能绕过

`Toggle` 属于第一类，可以在任意位置生效。于是思路是：

> **把 Toggle 当成一块"看不见的画布"，让它去画材质，内容画在它上面。**

承载层本身不参与交互、不显示文字，只负责渲染材质矩形。内容作为兄弟节点叠在它之上。

### 为什么不用普通 Button

官方明确 `Button` 也支持 `systemMaterial`，但**真机实测（HarmonyOS 7.0.0.105 / API 26）
普通 `Button` 挂材质不渲染**，同尺寸的 `ToggleType.Button` 则正常。
本仓库因此统一只走 Toggle：连圆形按钮 `IconCircleButton` 也是用
`ToggleType.Button` 作承载层 + `SymbolGlyph` 叠图标，而不是直接给 `Button` 挂材质。

---

## 3. 用哪种 ToggleType

官方对各 `ToggleType` 的说明（原文要点）：

| ToggleType | 行为 |
| --- | --- |
| `Checkbox` | **当前未适配沉浸光感效果，设置后无效果** |
| `Switch` | 材质参数**仅作为开启标记**，实际使用组件内部预设视觉参数，只影响滑块大小/样式/阴影 —— 永远只覆盖开关本体那片区域 |
| `Button` | 效果与 `Button` 组件相同，影响背景色、边框、阴影 |

**要的是一整块矩形材质，所以只能用 `ToggleType.Button`。**
`Switch` 只会渲染开关那一小片，`Checkbox` 完全无效。

---

## 4. 承载层模板（可直接抄）

```ts
@Component
export struct MaterialCardLayer {
  /** 与外壳圆角保持一致，见第 6 节 */
  @Prop layerRadius: Length = 20;
  /** 是否让材质自带投影，见第 8 节 */
  @Prop layerShadow: boolean = true;

  build() {
    Toggle({ type: ToggleType.Button, isOn: false })
      // ① 尺寸：跟随父级实测尺寸，不能用百分比（见第 6 节）
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      // ② 圆角：必须与外壳一致，否则会出现内嵌的小圆角边框
      .borderRadius(this.layerRadius)
      // ③ 必须显式透明：不透明背景色会盖在材质之上（见第 5 节）
      .backgroundColor(Color.Transparent)
      // ④ 只是画布，不参与交互与无障碍
      .enabled(false)
      .focusable(false)
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
      // ⑤ systemMaterial 必须放在所有样式属性之后
      .attributeModifier({
        applyNormalAttribute: (instance: ToggleAttribute): void => {
          applyMaterialCarrier(instance, false, false, this.layerShadow);
        }
      })
  }
}
```

五条缺一不可，逐条原因：

| # | 属性 | 少了会怎样 |
| --- | --- | --- |
| ① | `LayoutPolicy.matchParent` | 尺寸塌成 0，材质画不出来 |
| ② | `borderRadius` | Toggle 会画自己的按钮图形（自带小圆角 + 描边），卡片里出现内嵌边框 |
| ③ | `backgroundColor(Color.Transparent)` | 底色垫在材质之下，叠出灰感甚至完全遮住 |
| ④ | `enabled(false)` 等 | 承载层抢走焦点与点击，内容点不动 |
| ⑤ | `attributeModifier` 放末尾 | 材质被后面的样式属性覆盖 |

### 用法：Stack 里分层

```ts
Stack() {
  this.glowSpillLayer()                                // ① 溢出光晕（见第 9 节，卡内部分被材质盖住）
  MaterialCardLayer({ layerRadius: HwRadius.card })    // ② 材质
  Column() { /* 沾色层 */ }                             // ③ 可选：卡片沾色
  this.pressGlowLayer()                                // ④ 跟手光斑（见第 9 节）
  Column() { /* 内容 */ }                               // ⑤ 内容
}
.width(this.cardWidth)
.borderRadius(this.cardRadius)
// 刻意**不设 clip(true)**：溢出光晕要漏到卡片外面去，clip 会把它整圈切掉
```

> ⚠️ **外壳一旦不 clip，需要裁切的每一层都要自己带圆角。**
> `MaterialCardLayer` 一直有 `borderRadius`；沾色层与跟手光斑层也要各给一个
> `borderRadius(this.cardRadius)`，否则它们会在卡片四角露出直角。
> 只有半模态面板（`MaterialSheetPanel`）仍然用 `clip(true)`，它不需要往外溢光。

---

## 5. 四条层级规则

官方《沉浸光感常见问题》里三条硬规则，踩过每一条：

1. **材质的视觉层级位于 `backgroundColor`、`backgroundBlurStyle` 等属性之下。**
   → 承载层必须显式 `Color.Transparent`；任何不透明底色都会把材质盖住。

2. **`systemMaterial` 要放在其他样式属性（背景色、边框、阴影）之后设置。**
   → 所以用 `attributeModifier` 挂在属性链最末，而不是直接 `.systemMaterial(...)` 写在中间。

3. **材质不采样同一 `Stack` 里的兄弟节点。** 把内容画在材质**之下**（更早的兄弟节点），
   真机上完全看不见——`systemMaterial` 采样的是组件背后的窗口内容，不是同层兄弟。
   所以流光只能压在材质**之上**，不能指望穿过去被玻璃折射。

4. **弹窗面板也不例外。** `bindSheet` 的 `backgroundColor` 默认值是 `Color.White`，
   不显式放开的话材质同样被白底盖住：

   ```ts
   .bindSheet($$this.showXxx, this.xxxSheet(), {
     backgroundColor: Color.Transparent,   // ← 不能省
     blurStyle: sheetBlurStyle(),
   })
   ```

---

## 6. 尺寸：为什么必须 `matchParent`

**不要写 `width('100%')` / `height('100%')`。**

`Stack` 子节点的百分比尺寸按**父级可用尺寸**解析，而不是 Stack 最终测量出的尺寸。
卡片在纵向列表里时"可用高度"往往是整列剩余空间 —— 承载层会把自己撑满，
**连带把卡片一起顶大**。

`LayoutPolicy.matchParent` 按父级**实测尺寸**解析，随内容走，是这里唯一正确的选择。

同理，同一个 `Stack` 内的兄弟层（材质层、沾色层、内容层）**必须用同一种尺寸写法**，
不然一个撑大、另一个没撑，圆角和覆盖范围全对不上。

> 例外：如果外层 `Stack` 自己有确定尺寸（例如 `.width('100%').height('100%')` 的弹窗面板），
> 里面用百分比是可以的 —— 因为它确实有"父级可用尺寸"。

---

## 7. 降级路径：材质不可用时给毛玻璃

材质不可用有三种情况：API < 26、应用内开关关闭、用户在系统设置里关了材质总开关。
这时**不能让卡片变成一块死板色块**，要降级为磨砂玻璃。

三件事**缺一不可**：

```ts
// 1) 材质生效与否的判定，集中一处
private materialActive(): boolean {
  return this.cardMaterialEnabled && this.immersiveLightEnabled && isApi26OrAbove();
}

// 2) 外壳模糊：生效时 NONE 关掉，不生效时 Thin
private shellBlurStyle(): BlurStyle {
  return this.materialActive() ? BlurStyle.NONE : BlurStyle.Thin;
}

// 3) 底色必须带透明度，否则模糊被完全盖住 —— 这一步最容易漏
HwGlassCardColor.surface = isDark ? '#B326364F' : '#B3E8F0F8';   // 约 70% 不透明
```

下发侧的对应写法：

```ts
export function applyMaterialCarrier(
  instance: CommonAttribute,
  fallbackBlur: boolean = true,
  interactive: boolean = false,
  withShadow: boolean = true,
  lightColor: string = ''      // 流光颜色，空串 = 系统默认白光（见第 9 节）
): void {
  const material = getImmersiveMaterial(interactive, withShadow, lightColor);
  if (immersiveEnabled() && material !== null) {
    instance.systemMaterial(material);
  } else if (fallbackBlur) {
    instance.backgroundBlurStyle(BlurStyle.Thin);
  }
}
```

---

## 8. 阴影：材质自带投影，小尺寸要关

`ImmersiveMaterial` 的 **`applyShadow` 默认为 `true`**，材质会自带一层投影。

- **大卡片**：这层投影是加分项，保留。
- **小尺寸芯片**（房间筛选、排序、分类切换）：会显得像"按钮背后顶了一层影子"，要关掉。

实现上不要关全局阴影，而是**单独缓存一档不带阴影的材质**：

```ts
new uiMaterial.ImmersiveMaterial({ style: materialStyle(), applyShadow: false })
```

调用侧：

```ts
MaterialCardLayer({ layerRadius: HwRadius.pill, layerShadow: false })
```

`MaterialCard` 也透出了这个开关：**成排的小卡片**（选择家庭页那类上下只隔 10 点的列表卡）
传 `cardMaterialShadow: false` 即可，材质照常渲染、只是不带投影；
只有需要自己写承载层的地方（房间 chip、分类芯片等）才直接用 `MaterialCardLayer`。

---

## 9. 流光：按压时的光效

沉浸光感的按压反馈有两处，颜色都由设置页的**「主题色流光」**开关
（`immersivePressGlow`，默认开）统一控制：开 = 主题色，关 = 系统默认白光。

卡片上还多一个**「卡片流光触感」**开关（`cardGlowTouch`，**默认关**）：
**关 = 按压卡片一点光都不出现**，开 = 跟手光斑与溢出到卡间缝隙的环境光一起画。
它**只作用于卡片**，底栏那一处不读这个键。

> ⚠️ 两层必须一起开关。只关跟手光斑、留着环境光是不行的：
> 环境光的圆心本来就是手指坐标，它自己就是个跟手的光斑，
> 看起来仍是触碰反馈，开关等于没生效。

### 9.1 卡片上的跟手光晕

分两层，都在 `MaterialCard.cardBody` 里：

| 层 | 尺寸 | 层级 | 作用 |
| --- | --- | --- | --- |
| 跟手光斑 | `matchParent` + 自带圆角 | 材质之上、内容之下 | 手指底下那团光，被卡片圆角收住 |
| 溢出光晕 | 比卡片大一圈（0 尺寸锚点放置） | 最底层 | 卡与卡之间的缝隙里能看到一点辉光 |

要点：

- **坐标走窗口坐标系。** 触摸事件给的是 `windowX/windowY`，要减去卡片自身在窗口中的
  原点才能换算成卡片内坐标。卡片原点在 `Down` 那一瞬由 `windowX - x` 反推
  （这时组件内坐标一定准），之后靠 `onAreaChange` 报的 `globalPosition`
  **位移增量**维护。
  > 直接用 `touches[0].x/y`（组件内坐标）在**页面滚动**时会有问题：列表被滚动带走、
  > 手指没动，组件内坐标却跟着变，光斑看着就黏在卡片原处。
- `Down` / `Move` 都要处理（滑动时跟着走），`Up` / `Cancel` 必须熄灭。
- 光斑是一层 `radialGradient`，由内到外三档淡出；只用一档实色会得到硬边圆盘。
- **溢出光晕不能抬 `zIndex`**：让后画的相邻卡片盖住它，只留透过玻璃的一点亮度；
  抬起来就变成给邻卡糊了一层主题色。

### 9.2 流光颜色必须由调用方传进来

```ts
/** 纯函数：空串 = 不指定颜色、用系统默认白光 */
export function pressLightColor(themedLightOn: boolean, accentColor: string): string
```

**刻意做成纯函数、由调用方把订阅值传进来**，和 `resolvePageBackground()` 同一个理由：
ArkUI 的局部更新按表达式记录依赖，函数里直接 `AppStorage.get(...)` 是登记不上的，
拨开关或切主题色时已经画出来的按钮 / 卡片不会重新求值，流光会停在旧颜色上。

### 9.3 可交互材质按流光颜色缓存

`lightEffect.color` 默认是 `Color.White`。要换成主题色，只能在
`interactive: true` 那一档材质上带 `lightEffect`：

```ts
const lightOptions: uiMaterial.LightEffectOptions = {};   // 必须带类型标注，不能写成三元里的对象字面量
if (lightColor.length > 0) {
  lightOptions.color = lightColor;
}
new uiMaterial.ImmersiveMaterial({
  style: materialStyle(),
  interactive: true,
  lightEffect: lightOptions
});
```

颜色随主题色变，一个固定变量装不下，所以这一档材质用 `Map` **按颜色缓存**。

### 9.4 底部 HdsTab 悬浮栏的流光

这个光由 `HdsTabs` 自己绘制，不归应用的材质管，必须**单独下发**：

```ts
.barFloatingStyle({
  // ...
  lightColor: this.tabLightColor()      // 读订阅变量后由 pressLightColor() 决定
})
```

底栏的触摸被 `HdsTabs` 整段吃掉，挂在页面根节点上的 `onTouch` 一个事件都收不到；
要监听底栏上的手势，只能在底栏那一条带子上另盖一层
`HitTestMode.Transparent` 的透明层（自己也响应、但不阻塞下面的兄弟节点）。

---

## 10. 常见坑清单

| 坑 | 表现 | 正确做法 |
| --- | --- | --- |
| **`interactive: true` + `lightEffect: {}`** | 材质**完全不渲染** | 用静态材质（只传 `style`）。实测 HarmonyOS 7.0.0.105 上这个组合不生效 |
| **材质在模块加载期构造** | 低版本设备**启动即闪退** | 惰性求值。`export const X = uiMaterial.ImmersiveStyle.THIN` 这种写法会在模块加载期解引用 API 26 才有的接口，抛出的异常在任何 `try/catch` 之外，直接让模块加载失败 |
| **不透明底色** | 材质看不见 | 承载层与外层外壳都用 `Color.Transparent` |
| **内容层不设 `hitTestBehavior`** | 承载层收不到点击、按压流光不响应 | 内容层加 `.hitTestBehavior(HitTestMode.None)` |
| **圆角不透传** | 卡片里出现内嵌的小圆角边框 | 承载层 `borderRadius` 与外壳一致；外壳不 clip 时，沾色层 / 光斑层也要各带一个圆角 |
| **多档材质共用一个缓存** | 关掉阴影的那档把带阴影的覆盖了 | 各自缓存：静态 `materialCache`、去阴影 `flatMaterialCache`、可交互按流光颜色存 `Map` |
| **`attributeModifier` 写成内联对象字面量** | 切主题色 / 拨开关后已画出来的组件不更新 | 写成方法调用（`this.carrierModifier()`）并在里面读订阅变量：读发生在渲染期才登记得上依赖，闭包体不在渲染期执行，读什么都登记不上 |
| **溢出的层直接当卡片子节点** | 比卡片大的子节点会把卡片**撑大**（`Stack` 尺寸取最大子节点，`position` 不改布局尺寸） | 放进 `.width(0).height(0)` 的锚点容器，或用「同尺寸层 + 挪渐变圆心」的写法 |
| **把量尺寸的节点放进条件渲染里** | 条件依赖它量出来的尺寸 → 永远不成立，效果一次都不出现 | 负责测量的节点**必须无条件渲染**，只把「画什么」放进条件里 |
| **`Material.empty`** | 失败被伪装成静默失效 | 构造失败返回 `null`，让调用方走降级路径 |

---

## 11. 应用级前置条件

```json5
// entry/src/main/module.json5 —— 只有写在 entry 类型的 module 中才生效
"metadata": [
  {
    // default：普通组件可主动设置材质
    // enable ：更多系统组件自动使用材质
    // disable：关闭整个应用的沉浸材质，连主动设置的材质也一并失效
    "name": "ohos.arkui.UIMaterial.state",
    "value": "enable"
  }
]
```

`uiMaterial.getMaterialInfo().state` 读的就是这里。**改动后必须重新构建安装**才会生效。

---

## 12. 怎么验证

**诊断文案**：「外观设置 → 全局沉浸光感」下方会显示一行，形如：

```
API=26 材质=已构造 状态=非DISABLE 开关=开 流光=#0A59F7 承载=下发材质
```

把各段判定条件摊开，一眼能看出卡在哪一环（API 版本、材质构造、系统总开关、
应用开关、当前流光颜色）。

> ⚠️ 这两个入参（开关与主题色）也要由调用方把**订阅值**传进来，
> 函数内部直接读 `AppStorage` 的话，这行诊断不会随切色 / 拨开关刷新，
> 会停在上一档，看着像没生效。

**判定「承载层是否真的挂上了材质」**：材质生效时无法直接读回，
但可以看视觉结果 —— 承载层区域应该出现通透的玻璃质感，而不是纯色。

---

## 13. 复用清单

把光感搬到别的工程时，只需要这四个文件：

| 文件 | 职责 |
| --- | --- |
| `utils/SystemMaterial.ets` | `applyMaterialCarrier` / `getImmersiveMaterial` / `isApi26OrAbove` / `pressLightColor` / `sheetSystemMaterial` / `sheetBlurStyle` / `materialDiagnostics` |
| `components/MaterialCard.ets` | `MaterialCardLayer`（承载层）、`MaterialCard`（卡片外壳 + 跟手流光）、`MaterialSheetPanel`（弹窗面板）、`AccentColorSentinel` |
| `components/IconCircleButton.ets` | 圆形按钮：Toggle 承载 + `SymbolGlyph` 叠加 + 主题色流光 |
| `entry/src/main/module.json5` | 应用级 `metadata` 开关 |

移植时按顺序做：

1. 复制 `SystemMaterial.ets`，确认 `MATERIAL_STYLE` 是**函数内惰性求值**，不是模块级常量；
2. 复制 `MaterialCardLayer`，五条属性一条都别删；
3. 把现有卡片的 `Column` + `backgroundColor` 换成 `Stack { MaterialCardLayer + Column }`；
4. 检查每个 `bindSheet` 都设了 `backgroundColor: Color.Transparent`；
5. 给降级路径补 `backgroundBlurStyle` + 半透明底色；
6. 需要按压流光的话，照第 9 节加 `pressLightColor` 与两层光斑，
   并给底栏单独下发 `lightColor`。
