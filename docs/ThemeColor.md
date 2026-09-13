# 主题色（Theme Color）实现与移植指南

本文记录「主题色」这一功能的完整实现方式，以及**哪些组件必须跟随主题色、各自要用什么属性**，
目的是让这套机制能整体搬到别的 HarmonyOS 工程里。

参考实现：`entry/src/main/ets/utils/DesignTokens.ets`（核心）、
`entry/src/main/ets/components/MaterialCard.ets`（依赖标记）、
`entry/src/main/ets/pages/AppearanceSettingsPage.ets`（设置界面）。

---

## 1. 设计目标与核心难点

目标：用户在「外观设置」里选一个颜色（或输入任意 `RRGGBB`），**全应用立即变色**，无需重启。

难点有三个，这套实现全部围绕它们展开：

| 难点 | 说明 |
| --- | --- |
| **ArkUI 不会因为普通对象属性变化而刷新** | 颜色集中放在模块级可变对象 `HwColor` 里，改 `HwColor.primary` 不触发任何重建。 |
| **`@StorageProp` + `@Watch` 只触发回调，不重新求值组件** | 光声明 `@StorageProp('accentColor')` 不够；必须有一个**真正渲染出来的表达式读它**，ArkUI 才会把页面标记为脏。 |
| **控件自带 SDK 默认选中色** | `Toggle` / `Slider` 的 `selectedColor` 默认是 `$r('sys.color.ohos_id_color_emphasize')`，不显式覆盖就永远是系统蓝。 |

---

## 2. 数据模型

### 2.1 持久化（`AppSettingsStore` / `preferences`）

| 键 | 类型 | 含义 |
| --- | --- | --- |
| `accentKey` | `string` | 当前选中项。预设命中时为预设 `key`；选中自定义色时为固定字符串 `'custom'` |
| `accentCustom` | `string` | 当前选中的自定义色，`RRGGBB`（**不含 `#`**） |
| `accentCustomList` | `string[]` | 用户新增过的自定义色列表，顺序即界面展示顺序 |

`accentKey` 与 `accentCustom` 是**两个键**而不是一个：预设值本身写在代码常量里，
只有 `custom` 才需要额外的色值。任何时刻 `resolveAccentColor()` 都能只靠这两个值算出最终颜色。

### 2.2 运行时（`AppStorage`）

| 键 | 说明 |
| --- | --- |
| `accentColor` | **最终解析好的颜色**（`#RRGGBB`）。所有 UI 依赖的是它，不是上面三个持久化键 |
| `accentKey` / `accentCustom` | 用 `@StorageLink` 与设置页双向绑定，写入即同步 |
| `isDarkMode` | 与主题色同一条广播链，一起下发 |

---

## 3. 核心代码（可直接复制）

### 3.1 预设表

```ts
export interface AccentPreset {
  key: string;
  label: string;
  value: string;
}

export const ACCENT_PRESETS: AccentPreset[] = [
  { key: 'harmony', label: '鸿蒙蓝', value: '#0A59F7' },
  { key: 'rose',    label: '昔涟粉', value: '#E86A92' },
];
```

### 3.2 校验与派生工具

```ts
/** 只接受 6 位十六进制（可带 #），返回规范化的 `#RRGGBB`，非法返回空串 */
export function normalizeAccentHex(input: string): string { /* ... */ }

/** 逐项过滤非法值并去重，用于读入持久化列表时兜底 */
export function normalizeAccentList(raw: string[]): string[] { /* ... */ }

/**
 * 给 `#RRGGBB` 叠加透明度，返回 `#AARRGGBB`。
 * 凡是「主题色的浅色底」都用它，不要写字面量（见第 7 节）。
 */
export function withAlpha(color: string, alpha: number): string { /* ... */ }

/** 两个颜色线性混合：ratio=0 取 base，ratio=1 取 tint。用于把主题色调成很淡的底色 */
export function mixHex(base: string, tint: string, ratio: number): string { /* ... */ }

/** 是否是内置预设主题色。页面背景只跟随预设，自定义色不参与（见 §3.3） */
export function isPresetAccent(color: string): boolean { /* ... */ }

/** 按设置解析出最终颜色；预设未命中时用自定义值，非法则回落鸿蒙蓝 */
export function resolveAccentColor(accentKey: string, customHex: string): string {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === accentKey) {
      return ACCENT_PRESETS[i].value;
    }
  }
  const normalized = normalizeAccentHex(customHex);
  return normalized.length > 0 ? normalized : '#0A59F7';
}
```

### 3.3 可变 token 容器 + 应用主题

这是整套机制的支点：**颜色常量必须是可变对象的属性**，才能在运行时被改写。

```ts
export const HwColor: HwColorPalette = {
  primary: '#3379B7',        // ← 主题色就写在这里
  background: '#DCEAF8',
  surface: '#FFFFFF',
  textPrimary: '#1A1A1A',
  textSecondary: '#7A8089',
  danger: '#D94838',
  online: '#1AAB6A'
};

export function applyAppTheme(isDark: boolean, accentColor: string = ''): void {
  if (accentColor.length > 0) {
    HwColor.primary = accentColor;
  }
  // 默认背景跟随**预设**主题色，且刻意压得很淡：
  // 浅色 = 主题色与白色按 12% 混合，深色 = 与深底按 18% 混合。
  // 页面用的是 `isDarkMode ? backgroundDark : background`，所以两个都要跟着染。
  const backgroundBaseDark = '#1A2D44';
  const followed = accentColor.length > 0 && isPresetAccent(accentColor);
  const tintedLight = followed ? mixHex('#FFFFFF', accentColor, 0.12) : '#DCEAF8';
  const tintedDark = followed ? mixHex(backgroundBaseDark, accentColor, 0.18) : backgroundBaseDark;
  HwColor.background = isDark ? tintedDark : tintedLight;
  HwColor.backgroundDark = tintedDark;

  HwColor.surface       = isDark ? '#22334F' : '#FFFFFF';
  HwColor.textPrimary   = isDark ? '#EDF1F7' : '#1A1A1A';
  HwColor.textSecondary = isDark ? '#9BA8BC' : '#7A8089';

  // 卡片底色留 70% 透明度：沉浸光感不可用时要降级为毛玻璃，
  // 不透明底色会把模糊整个盖住，等于没有降级效果（见 §7.5）。
  HwGlassCardColor.surface = isDark ? '#B326364F' : '#B3E8F0F8';
  // 卡片描边跟主题色走，不要写死旧米家蓝
  HwGlassCardColor.border = withAlpha(HwColor.primary, 0.1);
}

/** 从持久化设置重建主题并广播 */
export function reloadAppTheme(): void {
  let isDark = false;
  let accentKey = 'harmony';
  let accentCustom = '';
  try { isDark = AppStorage.get<boolean>('isDarkMode') === true; } catch (err) { isDark = false; }
  try {
    const stored = AppStorage.get<string>('accentKey');
    if (stored !== undefined && stored.length > 0) { accentKey = stored; }
    const custom = AppStorage.get<string>('accentCustom');
    if (custom !== undefined) { accentCustom = custom; }
  } catch (err) { /* 存储不可用时用默认预设 */ }

  const resolved = resolveAccentColor(accentKey, accentCustom);
  applyAppTheme(isDark, resolved);
  AppStorage.setOrCreate('accentColor', resolved);   // ← 关键：这一步才触发界面刷新
}
```

**调用时机**（本仓库的实际做法）：

- **应用启动**：`EntryAbility.onCreate` 里从 `AppSettingsStore` 读 `accentKey` / `accentCustom`，
  `resolveAccentColor()` 解析后写入 `AppStorage['accentColor']` 并调 `applyAppTheme(...)`。
  不在这里做的话首屏会用默认蓝，切到别的页面才变色。
  持久化键要先 `AppStorage.setOrCreate('accentKey' | 'accentCustom', ...)` 建好，
  后续 `@StorageLink` 才有初值。
- **切换主题色**：设置页每次改色后调一次 `reloadAppTheme()`。
- **页面重建时**：每个页面的 `@Watch('onAccentColorChanged')` 回调里也调 `reloadAppTheme()`，
  保证从任意页面切换暗色/主题色都能自洽。

注意这里为什么不会死循环：`@Watch` 回调里再次 `reloadAppTheme()` 时算出的值相同，
`setOrCreate` 写入等值不会触发变更通知。

### 3.4 依赖标记组件（`AccentColorSentinel`）

```ts
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
```

**为什么需要它**：`@StorageProp` + `@Watch` 只会调回调，**不会**让组件重新求值。
必须有一个始终在渲染树里的表达式真正读到 `accentColor`，ArkUI 才会把页面标记为脏并重建。
把它放在页面根 `Stack` 的第一个子节点即可（零尺寸，不影响布局）：

```ts
build() {
  Stack({ alignContent: Alignment.TopStart }) {
    AccentColorSentinel()      // ← 放在最前面
    AppBackground()
    // ...页面内容
  }
}
```

### 3.5 页面侧的取色辅助函数

页面自己的代码里**不要再直接写 `HwColor.primary`**，而是走一个读 `accentColor` 的辅助函数，
这样即使没有 `AccentColorSentinel`，页面本身也建立了依赖：

```ts
/** 当前主题色。读 accentColor 建立依赖，否则会停留在旧色 */
private accentOrPrimary(): string {
  return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
}
```

两种命名在仓库里都存在（`accent()` 与 `accentOrPrimary()`），语义相同。
`accent()` 用于组件内部（如 `PropertyControl` / `PressableButton`），
`accentOrPrimary()` 用于页面。

---

## 4. 生效链路（从点击到全应用变色）

```
用户点色块 / 输入 RRGGBB
        │
        ▼
设置页写 @StorageLink('accentKey' | 'accentCustom')  ──► 同步进 AppStorage
        │
        ▼
AppSettingsStore.setString(...)                      ──► 落盘持久化
        │
        ▼
applyAccentNow() → reloadAppTheme()
        │
        ├─ resolveAccentColor() 算出 #RRGGBB
        ├─ applyAppTheme() 改写 HwColor.primary（模块级对象，静默）
        └─ AppStorage.setOrCreate('accentColor', resolved)
        │
        ▼
所有 @StorageProp('accentColor') 的页面/组件被标记为脏并重建
        │
        ▼
重建时读取 HwColor.primary（已是新值）+ accentColor（用于 Toggle/Slider 的选中色）
```

**结论**：`HwColor.primary` 负责「值」，`accentColor` 负责「通知」。两者缺一不可。

### 4.1 深色模式：与主题色共用同一条广播链

深色模式和主题色不是两套机制，而是**同一条链上的两个键**：`applyAppTheme(isDark, accent)`
一次同时改写 `HwColor.primary` 与 `HwColor.background / surface / textPrimary / textSecondary /
HwGlassCardColor.*`，再由 `isDarkMode` + `accentColor` 两个键一起广播出去。
所以加主题色时顺手就把深色模式接了，反过来也一样。

**当前策略：设置过就以开关为准，没设置过就跟随系统。**

```ts
// EntryAbility：启动时决定用哪个值
const darkModeEnabled = EntryAbility.resolveDarkMode(this.context);
this.context.getApplicationContext().setColorMode(EntryAbility.resolveColorMode(darkModeEnabled));
// 主题色在启动时就要生效，否则首屏会用默认色、切到别的页面才变
const accentColor = resolveAccentColor(accentKey, accentCustom);
AppStorage.setOrCreate('accentKey', accentKey);
AppStorage.setOrCreate('accentCustom', accentCustom);
AppStorage.setOrCreate('accentColor', accentColor);
applyAppTheme(darkModeEnabled, accentColor);
```

```ts
/** 切换过就以应用内开关为准；从未切换过则跟随系统 */
private static resolveDarkMode(context: common.UIAbilityContext): boolean {
  try {
    if (AppSettingsStore.has('darkModeEnabled')) {
      return AppSettingsStore.getBoolean('darkModeEnabled', false);
    }
  } catch (err) {
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

/** 显式选过就下发明确模式，没选过则交还给系统 */
private static resolveColorMode(darkModeEnabled: boolean): ConfigurationConstant.ColorMode {
  try {
    if (!AppSettingsStore.has('darkModeEnabled')) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
  } catch (err) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
  return darkModeEnabled
    ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
}
```

**「是否显式设置过」用 `AppSettingsStore.has()` 判断，而不是给布尔值加第三个状态。**
存储里没有这个键 = 用户没选过 = 跟随系统；有这个键 = 用户选过 = 以键值为准。

三个必须同时做对的点：

1. **平台配色要和自绘颜色一起下发。** `setColorMode()` 管的是系统控件（弹窗、输入法、滚动条），
   `applyAppTheme()` 管的是自绘颜色。只做后者会出现「自绘是浅色、系统弹窗是深色」的错配。
2. **`COLOR_MODE_NOT_SET` 表示交还给系统。** 用户没选过时下发这个值，系统切深浅色应用会自动跟；
   一旦用户选了明确值，就不再跟随。
3. **`onConfigurationUpdate` 里也要走 `resolveDarkMode()`。** 这个回调会被 `setColorMode()`
   同步触发，所以它内部**不能再调 `setColorMode()`**，否则会自激。

### 4.2 主题色开关必须是双向绑定

给用户提供「深色模式」这类开关时，承载它的状态变量必须是 `@StorageLink`，不能是 `@StorageProp`：

```ts
@StorageLink('isDarkMode') isDarkMode: boolean = false;   // ✓ 可写，赋值即写回 AppStorage

private setDarkMode(enabled: boolean): void {
  AppSettingsStore.setBoolean('darkModeEnabled', enabled);   // 记住「用户选过了」
  applyAppTheme(enabled);                                    // 改 HwColor（静默）
  this.isDarkMode = enabled;                                 // 广播，其余页面重建
  AppStorage.setOrCreate('accentColor', this.accentColor);   // 与 isDarkMode 同一条链
  try {
    (getContext(this) as common.UIAbilityContext).getApplicationContext().setColorMode(
      enabled ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
              : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    );
  } catch (err) {
  }
}
```

`@StorageProp` 是单向只读的，**对它赋值不会生效**，开关会表现成「点一下弹回去」。
详见 §7.6。

---

## 5. 必须跟随主题色的组件清单

移植时按下表逐项核对。当前仓库的覆盖数量一并列出，便于对照。

### 5.1 直接用颜色常量的地方

| 位置 | 写法 | 说明 |
| --- | --- | --- |
| 文字 / 图标 / 边框色 | `HwColor.primary` | 全仓 **116 处，22 个文件**。只要所属页面重建就会取到新值 |
| 选中态文字 | `selected ? HwColor.primary : HwColor.textSecondary` | 列表项、选项、页签 |
| 进度条轨道 | `withAlpha(HwColor.primary, 0.1)` | 例：`DeviceDetailPage` 耗材条底槽 |
| 选项按钮浅底 | `withAlpha(HwColor.primary, 0.15)` | 例：`PropertyControl` 枚举选项 |
| 图标图形 | `SymbolGlyph(x).fontColor([HwColor.primary])` | **注意 ForEach key，见 5.5** |

### 5.2 控件自带的选中色（**最容易漏**）

SDK 默认值一律是 `$r('sys.color.ohos_id_color_emphasize')`（系统蓝），**不显式覆盖就永远是蓝的**：

| 控件 | 属性 | 当前覆盖数 |
| --- | --- | --- |
| `Toggle`（Switch / Checkbox / Button） | `.selectedColor(色值)` | 24 处（21 处取主题色，3 处刻意 `Color.Transparent`） |
| `Slider` | `.selectedColor(色值)`，可配 `.trackColor()` / `.blockColor()` | 4 处 |
| `Button` + `ButtonStyleMode.EMPHASIZED` | 底色由 SDK 固定 → 显式 `.backgroundColor(主题色)` | `PressableButton`、`RoomsPage` |

```ts
Toggle({ type: ToggleType.Switch, isOn: this.value })
  .selectedColor(this.accent())      // ← 不写就永远是蓝的
  .switchPointColor(Color.White)

Slider({ value: v, min: 0, max: 100, style: SliderStyle.OutSet })
  .selectedColor(this.accent())
  .trackColor('#1A000000')
  .blockColor(Color.White)
```

> `MaterialCardLayer` / `IconCircleButton` 里的 `Toggle` 是材质承载层，不是开关，
> 它们的 `selectedColor(Color.Transparent)` 是刻意的，**不要**改成主题色。

### 5.3 输入框光标

```ts
TextInput({ ... }).caretColor(this.accentOrPrimary())
```

### 5.4 承载层不是控件本身的情况

`MaterialCard` / `MaterialSheetPanel` / `IconCircleButton` 这类自定义组件内部，
材质承载层用 `ToggleType.Button` 实现。这些组件都自行声明了
`@StorageProp('accentColor')`，保证卡片内容里的 `HwColor.primary` 会跟着变。

### 5.5 `ForEach` 的 key（**第二个最容易漏的点**）

`ForEach` 会**复用 key 相同的项**：键不变就不会重建子节点，
子节点里那些不依赖状态变量的表达式（如直接写的 `HwColor.primary`）**永远不会被重新求值**。

所以凡是「列表项里含主题色元素」的 `ForEach`，key 都必须带上 `accentColor`：

```ts
ForEach(this.filteredDevices, (device: XiaomiDevice) => {
  this.deviceCard(device)
}, (device: XiaomiDevice) =>
  `${device.did}_${this.favoriteDevices.indexOf(device.did) >= 0 ? 1 : 0}_${this.accentColor}`)
//                                                              ^^^^^^^^^^^^^^^^^^ 必须带
```

当前 5 处已带：设备列表、房间筛选 chip、排序 chip、收藏设备列表、排除设备列表。
新增列表时请照做。

**同一个坑还有第二种表现：选中态本身就是状态。**
主题色选择器里的色块就是例子——色块内容没变，但「哪个带对号」变了：

```ts
// ✗ 对号永远停在上一个被点的色块上
ForEach(ACCENT_PRESETS, (preset: AccentPreset) => {
  this.accentSwatch(preset.key, preset.value, preset.label, this.accentKey === preset.key, false)
}, (preset: AccentPreset) => `preset_${preset.key}`)

// ✓ 把选中态编进 key，被选中/被取消的两项都会重建
}, (preset: AccentPreset) =>
`preset_${preset.key}_${this.accentKey === preset.key ? 1 : 0}`)
```

判断方法很简单：**问自己「这个列表项的外观会不会在数据不变的情况下改变」**。
只要会（选中、展开、加载中、禁用），key 就必须把它编进去。

### 5.6 选中态芯片（分段控件）的标准写法

首页的房间筛选、排序方式，智能页的分类切换，都长这样——
**三层结构：底层自绘底色 / 中层材质承载 / 顶层文字穿透**。
新增任何「一组互斥选项」的控件都照这个抄：

```ts
@Builder
categoryChip(key: string, label: string) {
  Stack() {
    // 1) 底色层：选中为主题色实底，未选中给一层很淡的中性底，
    //    这样芯片始终有形状，观感是分段控件而不是一行裸文字
    Row()
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .borderRadius(HwRadius.pill)
      .backgroundColor(this.category === key
        ? this.accent() : withAlpha(HwColor.textPrimary, 0.06))

    // 2) 材质承载层：常驻开启，叠在底色之上 → 得到「主题色玻璃」的高亮
    MaterialCardLayer({ layerRadius: HwRadius.pill })

    // 3) 文字层：必须让触摸穿透，否则点不到下面的承载层
    Text(label)
      .fontColor(this.category === key ? '#FFFFFF' : HwColor.textPrimary)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .hitTestBehavior(HitTestMode.None)
  }
  .onClick((): void => {
    this.category = key;
  })
}
```

三个容易做错的地方：

- **选中时不要关掉材质。** 早先的写法是「选中就跳过材质，让主题色实底直接显示」，
  结果高亮是**纯色块**；把承载层做成常驻，高亮才是**主题色玻璃**，与卡片观感统一。
- **尺寸用 `LayoutPolicy.matchParent` 而不是 `width('100%')`。**
  百分比在 `Stack` 内会按父级满宽解析，把芯片撑成一整行；`matchParent` 按父级实测尺寸解析，随内容走。
- **外层包一层 `Column` + `constraintSize({ minWidth: 64 })`**（内容宽度会变的芯片）：
  既不会塌成 0（那样材质画不出来、点击也收不到），也不会撑满整行。

### 5.7 默认背景色（页面底色）

页面底色也跟随主题色，但有两条**刻意加的限制**，不要顺手去掉：

| 限制 | 原因 |
| --- | --- |
| **只跟随预设色** | 自定义色是用户随手输的，拿它铺满整页很容易脏，也可能与正文对比度不足 |
| **混得非常淡** | 浅色只混 12%、深色只混 18%；直接铺主题色会压过正文，页面看着像报错页 |

```ts
const followed = accentColor.length > 0 && isPresetAccent(accentColor);
const tintedLight = followed ? mixHex('#FFFFFF', accentColor, 0.12) : '#DCEAF8';
const tintedDark = followed ? mixHex('#1A2D44', accentColor, 0.18) : '#1A2D44';
HwColor.background = isDark ? tintedDark : tintedLight;
HwColor.backgroundDark = tintedDark;   // ← 别漏：页面读的是 isDarkMode ? backgroundDark : background
```

实际效果（浅色模式）：鸿蒙蓝 `#0A59F7` → `#E2EBFE`；昔涟粉 `#E86A92` → `#FCEDF2`。

页面侧**必须通过 `resolvePageBackground()` 取这个值**，不能直接读 `HwColor.background`：

```ts
.backgroundColor(resolvePageBackground(this.accentColor, this.isDarkMode))
```

原因见 §7.8 —— 直接读 `HwColor.background` 不会被 ArkUI 登记为依赖，
切主题色时已打开的页面不会重算底色。两个入参必须是页面自己声明的订阅变量。

**`background` 和 `backgroundDark` 必须同时染。** 页面里的写法是
`this.isDarkMode ? HwColor.backgroundDark : HwColor.background`，
只改前者的话暗色模式下背景纹丝不动。

---

## 6. 移植步骤清单

1. **复制 `DesignTokens.ets` 的主题色部分**：`AccentPreset` / `ACCENT_PRESETS` /
   三个存储键常量 / `normalizeAccentHex` / `normalizeAccentList` / `withAlpha` /
   `resolveAccentColor` / `applyAppTheme` / `reloadAppTheme`。
2. **确认颜色常量是可变对象**（`export const XxxColor = { primary: ... }`），
   不能是 `const PRIMARY = '#...'` 这种字符串常量——后者无法在运行时改写。
3. **在 `EntryAbility.onCreate` 里做启动初始化**：把三个持久化键写进 `AppStorage`
   （`accentKey` / `accentCustom` 供 `@StorageLink` 取初值），
   解析出颜色后写 `accentColor` 并调 `applyAppTheme(...)`。
4. **每个页面加上**：
   ```ts
   @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
   onAccentColorChanged(): void { reloadAppTheme(); }
   ```
   并在根 `Stack` 里挂一个 `AccentColorSentinel()`。
5. **逐项核对第 5 节**，重点是所有 `Toggle` / `Slider` 的 `selectedColor`，
   以及含主题色元素的 `ForEach` key。
6. **做设置页**：预设色块 + 自定义输入。参考 `AppearanceSettingsPage`：
   色块统一走 `MaterialCard`（沉浸光感），自定义色右上角叠删除角标，
   删除当前选中色时回落到第一个预设，避免 `accentCustom` 指向列表外的值。
7. **兼容旧数据**：`loadAccentList()` 里要把历史遗留的单个 `accentCustom`
   补进 `accentCustomList`，否则升级后用户原有的自定义色会凭空消失。
8. **深色模式顺手一起接**（见 §4.1）：它和主题色共用 `applyAppTheme()` 与同一条广播链，
   分开做会得到两套互不知情的机制。启动时用 `AppSettingsStore.has('darkModeEnabled')`
   区分「用户选过」与「跟随系统」，并用 `setColorMode()` 让系统控件与自绘颜色保持一致。

---

## 7. 踩坑记录

### 7.1 不要在代码里写死带主题色含义的字面量

仓库里曾有 `'#263379B7'`、`'#1A3379B7'` 这类把旧米家蓝硬编进去的半透明色，
切主题色后选中态会露出蓝底。一律改用 `withAlpha(HwColor.primary, α)`。

注意 **`const` 对象也要在 `applyAppTheme()` 里重新赋值**，否则同样不会跟着变：

```ts
export const HwGlassCardColor: HwGlassCardPalette = { surface: '#E8F0F8', border: '#1A3379B7' };

export function applyAppTheme(isDark: boolean, accentColor: string = ''): void {
  // ...
  HwGlassCardColor.border = withAlpha(HwColor.primary, 0.1);   // ← 卡片描边跟主题色
}
```

排查方法：

```bash
grep -rn "'#[0-9A-Fa-f]\{8\}'" entry/src/main/ets/   # 半透明字面量
```

命中的不全是问题（`'#1A000000'` 这种中性半透明黑是刻意的），
但凡是**带色相**的（如 `#1A3379B7`）都需要改成 `withAlpha(主题色, α)`。

### 7.2 `@Watch` 不负责刷新

写成下面这样**不会**生效——回调被调用了，但组件没有重新求值：

```ts
@StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
```

必须配合「在 `build()` 里真正读一次 `accentColor`」（`accentOrPrimary()` 或 `AccentColorSentinel`）。

### 7.3 自定义组件的参数不要用联合类型

`@Prop accentColor: string` 没问题；但像 `Padding | Length` 这类联合类型会让 ArkTS
在传对象字面量时报 `arkts-no-untyped-obj-literals`。同理，`@Prop` 的默认值要写具体类型。

### 7.4 自定义组件尾随闭包后不能链式挂属性

```ts
MaterialCard({ ... }) { ... }.margin({ top: 8 })   // ✗ 编译错误
MaterialCard({ cardMargin: { top: 8 } }) { ... }   // ✓ 用 card* 参数
```

涉及主题色的自定义组件（`MaterialCard` / `MaterialSheetPanel` / `PressableButton` 等）
大多如此，改样式请走参数。

### 7.5 材质层的层级在 `backgroundColor` 之下

沉浸光感的视觉层级位于组件的 `backgroundColor` 之下：任何不透明底色都会盖住材质。
材质承载层必须显式 `Color.Transparent`，半透明弹窗面板还要补
`bindSheet({ backgroundColor: Color.Transparent })`（默认值是 `Color.White`）。
细节见 README 的「沉浸光感（API 26）」章节。

**同一条规则也决定了降级路径必须补毛玻璃。**
沉浸光感不可用时（API < 26、开关关闭），只把不透明底色画上去，卡片会变成一块死板色块。
正确的降级是三件事一起做：

```ts
// 1) 外壳底色在半透明与透明之间切换（材质生效时让位，不生效时作为玻璃底色）
private shellBackground(): ResourceColor {
  return this.materialActive() ? Color.Transparent : this.cardBackground;
}

// 2) 不生效时补一层模糊；生效时用 NONE 关掉，避免与材质叠加
private shellBlurStyle(): BlurStyle {
  return this.materialActive() ? BlurStyle.NONE : BlurStyle.Thin;
}
```

```ts
// 3) 底色本身必须带透明度，否则模糊被完全盖住 —— 这一步最容易漏
HwGlassCardColor.surface = isDark ? '#B326364F' : '#B3E8F0F8';   // 约 70% 不透明
```

**三条缺一不可**：只加 `backgroundBlurStyle` 而底色不透明，模糊根本看不见；
只调透明而不加模糊，卡片变成一层薄纱但背后什么都没有。

### 7.6 `@StorageProp` 只能读，要写回必须用 `@StorageLink`

两者都订阅同一个 `AppStorage` 键，但方向不同：

| 装饰器 | 方向 | 能赋值吗 |
| --- | --- | --- |
| `@StorageProp('k')` | 存储 → 组件，**单向** | ✗ 赋值不生效 |
| `@StorageLink('k')` | 存储 ⇄ 组件，**双向** | ✓ 赋值即写回存储 |

需要用户操作的开关（深色模式、全局沉浸光感、各项设置）必须用 `@StorageLink`，
否则表现为「点一下弹回去」。只用来建立刷新依赖的（`accentColor`）用 `@StorageProp` 就够了。

一个页面把 `@StorageLink('isDarkMode')` 改了，其余 14 个用 `@StorageProp('isDarkMode')`
订阅同一键的页面会一起重建 —— 读用 Prop、写用 Link，是这套机制最常见的组合。

---

### 7.7 调 `applyAppTheme()` 一定要带上当前主题色

`applyAppTheme(isDark, accentColor = '')` 的第二个参数一旦省略，背景染色就会被重置回默认值
——因为它内部要靠 `accentColor` 判断「要不要跟随主题色」。

```ts
applyAppTheme(enabled);                      // ✗ 背景染色被重置
applyAppTheme(enabled, this.currentAccent()); // ✓
```

容易漏的两处（都已修）：
- **切换深色模式**时只想着 `isDark` 变了，忘了主题色没变但必须一起传；
- **`onConfigurationUpdate`**（系统深浅色变化）里同样要重新读一次已保存的主题色再传进去。

排查方式：切一下深色模式开关，如果页面背景从「主题色淡染」变回固定浅蓝，就是这里漏了。

### 7.8 读 `HwColor` 的属性不会建立依赖 —— 页面底色必须走 `resolvePageBackground()`

ArkUI 的局部更新是**按表达式**记录依赖的，而 `HwColor` 只是个模块级普通对象：
读它的属性**不会被登记**，属性变了也不会让任何表达式重新求值。

所以下面这种写法是坏的：

```ts
// ✗ 只登记了 isDarkMode；切主题色时这个表达式不会被重新求值
.backgroundColor(this.isDarkMode ? HwColor.backgroundDark : HwColor.background)
```

表现就是**已打开的页面底色不跟着切**，而新建/重进的页面又是对的——很容易误判成"刷新不及时"。

正确写法是让 `accentColor` 出现在表达式里（§5.7）：

```ts
.backgroundColor(resolvePageBackground(this.accentColor, this.isDarkMode))
```

`resolvePageBackground(accentColor, isDark)` 内部返回的仍是 `HwColor` 的对应属性，
但它把 `accentColor` 变成了**入参**——调用点在 build 期间真正读了这个订阅键，依赖才登记得上。

**这条规则对 `HwColor` 的每个属性都成立**，不只是背景色：

| 场景 | 正确做法 |
| --- | --- |
| 取主题色 | `this.accentOrPrimary()` / `this.accent()`（内部读 `accentColor`） |
| 页面底色 | `resolvePageBackground(this.accentColor, this.isDarkMode)` |
| 直接写 `HwColor.primary` | 只在**不依赖主题色变化**的地方可接受（如按压态等瞬时样式，每次应用时重新读取） |

顺带一提，历史上有 `MaterialCard` 挂一个零尺寸的 `AccentColorSentinel` 来"提供依赖"的做法。
它能让**卡片内部**的表达式重算，但**不会**让页面根节点的属性重新求值——
页面自己的底色还是得走 `resolvePageBackground()`。

---

## 8. 关键文件一览

| 文件 | 职责 |
| --- | --- |
| `utils/DesignTokens.ets` | 主题色全部核心逻辑 + `HwColor` 可变 token 容器 |
| `components/MaterialCard.ets` | `MaterialCard` / `MaterialSheetPanel` / `MaterialCardLayer` / `AccentColorSentinel` |
| `pages/AppearanceSettingsPage.ets` | 主题色选择 UI（预设 + 自定义 + 删除）+ 深色模式开关 |
| `entryability/EntryAbility.ets` | 启动时解析并下发主题色与深色模式（`resolveDarkMode` / `resolveColorMode`） |
| `storage/AppSettingsStore.ets` | `preferences` 读写（`has` / `getStringArray` / `setStringArray`） |

绑定了主题色 / 深色模式的页面，统一在这个位置建立依赖：

```ts
@StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
@StorageProp('isDarkMode') isDarkMode: boolean = false;
onAccentColorChanged(): void { reloadAppTheme(); }
// 根 Stack 里再挂一个零尺寸的 AccentColorSentinel()
```

