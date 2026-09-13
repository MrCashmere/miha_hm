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
| `cardTintEnabled` | `boolean` | **卡片沾色**：卡片底色是否混入 10% 主题色 |
| `customAccentFullAccess` | `boolean` | **高权限自定义主题色**：自定义色是否也参与页面背景染色 |

`accentKey` 与 `accentCustom` 是**两个键**而不是一个：预设值本身写在代码常量里，
只有 `custom` 才需要额外的色值。任何时刻 `resolveAccentColor()` 都能只靠这两个值算出最终颜色。

### 2.2 运行时（`AppStorage`）

| 键 | 说明 |
| --- | --- |
| `accentColor` | **最终解析好的颜色**（`#RRGGBB`）。所有 UI 依赖的是它，不是上面三个持久化键 |
| `pageBackground` | 算好的页面底色，由 `applyAppTheme()` 发布。页面订阅它，见 §5.7 |
| `cardSurface` | 算好的卡片底色（含沾色），由 `applyAppTheme()` 发布。卡片订阅它，见 §5.8 |
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

**默认主题色就是预设首位的「鸿蒙蓝」**，另有两个常量固定这一档的含义：

```ts
export const DEFAULT_ACCENT_KEY: string = 'harmony';
export const DEFAULT_ACCENT_VALUE: string = '#0A59F7';
```

> ⚠️ **不要为「默认色」单列一个预设。** 曾经试过在预设首位插一个名为「默认色」的色块
> （值是应用早期的米家蓝 `#3379B7`），结果是设置页同时出现「默认色」和「鸿蒙蓝」两个蓝，
> 用户分不清哪个才是默认，主色还与应用其它部分的配色对不上。
> 「默认」是一个**语义**，不是一个颜色：它就该等于预设首位那一档，直接复用即可。
> 米家蓝 `#3379B7` 及其各种透明变体（`#1A3379B7` 等）已全部从代码中移除。

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
  primary: DEFAULT_ACCENT_VALUE,   // 鸿蒙蓝；切色后由 applyAppTheme 覆盖
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

**当前策略：三态偏好 —— 跟随系统 / 浅色 / 深色，默认跟随系统。**

> **为什么是字符串三态而不是布尔开关：** 布尔一旦被用户拨动过就永久生效，
> 再也没法回到「跟随系统」（表现为「深色模式不跟随系统」，只能靠重置设置救回来）。
> 三态让「跟随系统」始终是一个能选回来的状态。
> 1.1.0/1.1.1 存的旧布尔 `darkModeEnabled` 会在启动时迁移成 `dark` / `light` 并删除。

```ts
// EntryAbility：启动时决定用哪个值
const darkModePref = EntryAbility.resolveDarkModePref();   // system / light / dark（含旧键迁移）
AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, darkModePref);
const darkModeEnabled = EntryAbility.resolveDarkMode(this.context, darkModePref);
this.context.getApplicationContext().setColorMode(EntryAbility.resolveColorMode(darkModePref));
// 主题色在启动时就要生效，否则首屏会用默认色、切到别的页面才变
const accentColor = resolveAccentColor(accentKey, accentCustom);
AppStorage.setOrCreate('accentKey', accentKey);
AppStorage.setOrCreate('accentCustom', accentCustom);
AppStorage.setOrCreate('accentColor', accentColor);
applyAppTheme(darkModeEnabled, accentColor);
```

```ts
/** 读偏好，顺带把旧布尔键迁移成三态字符串 */
private static resolveDarkModePref(): string {
  try {
    const stored = AppSettingsStore.getString(DARK_MODE_PREF_STORAGE, '');
    if (stored === DARK_MODE_SYSTEM || stored === DARK_MODE_LIGHT || stored === DARK_MODE_DARK) {
      return stored;
    }
    if (AppSettingsStore.has('darkModeEnabled')) {          // 旧版本残留
      const legacy = AppSettingsStore.getBoolean('darkModeEnabled', false);
      const migrated = legacy ? DARK_MODE_DARK : DARK_MODE_LIGHT;
      AppSettingsStore.setString(DARK_MODE_PREF_STORAGE, migrated);
      AppSettingsStore.delete('darkModeEnabled');
      return migrated;
    }
  } catch (err) {
  }
  return DARK_MODE_SYSTEM;                                   // 全新安装：跟随系统
}

/** 偏好为「跟随系统」时读系统，其余按偏好取值 */
private static resolveDarkMode(context: common.UIAbilityContext, pref: string): boolean {
  if (pref === DARK_MODE_DARK) { return true; }
  if (pref === DARK_MODE_LIGHT) { return false; }
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

/** 跟随系统时下发 NOT_SET 交还配色权；选了明确值才固定 */
private static resolveColorMode(pref: string): ConfigurationConstant.ColorMode {
  if (pref === DARK_MODE_DARK) { return ConfigurationConstant.ColorMode.COLOR_MODE_DARK; }
  if (pref === DARK_MODE_LIGHT) { return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT; }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
}
```

**「跟随系统」必须真的把配色权交还系统**：`setColorMode(COLOR_MODE_NOT_SET)`。
只要下发过 `COLOR_MODE_DARK` / `COLOR_MODE_LIGHT`，系统再切深浅色应用也不会跟。

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
// 默认只让内置预设色参与；「高权限自定义主题色」开关打开后自定义色也放行
const fullAccess = readFlag(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, false);
const followed = accentColor.length > 0 && (isPresetAccent(accentColor) || fullAccess);
const tintedLight = followed ? mixHex('#FFFFFF', accentColor, 0.12) : '#DCEAF8';
const tintedDark = followed ? mixHex('#1A2D44', accentColor, 0.18) : '#1A2D44';
HwColor.background = isDark ? tintedDark : tintedLight;
HwColor.backgroundDark = tintedDark;   // ← 别漏：页面读的是 isDarkMode ? backgroundDark : background
```

> 「高权限自定义主题色」开关**只是把 `isPresetAccent()` 这个门槛去掉**，淡染算法完全一样
> （自定义色照样与白/深底按 12% / 18% 混合）。所以它不影响观感上限，只是把选择权交回用户。

实际效果（浅色模式）：鸿蒙蓝 `#0A59F7` → `#E2EBFE`；昔涟粉 `#E86A92` → `#FCEDF2`。

页面侧**必须订阅 `pageBackground` 广播键**，不能直接读 `HwColor.background`：

```ts
// 页面里
@StorageProp('pageBackground') pageBackground: string = '';
...
.backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
```

`applyAppTheme()` 每次跑完都会把算好的底色发布到 `pageBackground`，
所以**主题色、深浅色、两个开关**里任何一个变化，页面都会收到通知。

原因见 §7.8 —— 直接读 `HwColor.background` 不会被 ArkUI 登记为依赖，
切主题色时已打开的页面不会重算底色。

### 5.8 卡片底色与「卡片沾色」开关

卡片底色同理，走 `cardSurface` 广播键：

```ts
// MaterialCard / MaterialSheetPanel 里
@StorageProp('cardSurface') cardSurface: string = '';
...
.backgroundColor(this.cardSurface.length > 0 ? this.cardSurface : HwGlassCardColor.surface)
```

打开「卡片沾色」后，`applyAppTheme()` 发布的是**一层 10% 主题色叠加层**，不是混进底色：

```ts
AppStorage.setOrCreate(CARD_TINT_KEY,
  accentColor.length > 0 && readFlag(CARD_TINT_STORAGE, false)
    ? withAlpha(accentColor, 0.1) : '');
```

卡片把它画在**材质之上、内容之下**：

```ts
@Builder
cardBody() {
  if (this.materialActive()) {
    MaterialCardLayer({ layerRadius: this.cardRadius })
  }
  if (this.cardTint.length > 0) {
    Column()
      // 必须 matchParent，不能写 width/height('100%')：百分比在 Stack 内按
      // **父级可用尺寸**解析，高度会撑到容器满高、把卡片顶大。
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .backgroundColor(this.cardTint)          // ← 沾色层
      .hitTestBehavior(HitTestMode.None)
  }
  Flex({ ... }) { this.cardContent() }         // 内容在最上层
}
```

**沾色层与 `MaterialCardLayer` 必须用同一种尺寸写法（`LayoutPolicy.matchParent`）。**
两者是 Stack 里的兄弟节点、要盖住同一块区域；一个用 `matchParent`、另一个用百分比，
后者会按父级可用尺寸把自己撑大，连带把卡片顶大。

> ⚠️ **为什么不能把沾色混进卡片底色：** 材质生效时 `shellBackground()` 返回的是
> `Color.Transparent` —— 外壳底色**根本不画**。把主题色混进 `HwGlassCardColor.surface`
> 在 API 26 设备上完全看不到效果（第一版就是这么写的，表现为「开关点了没反应」）。
> 沾色与底色是两层不同的东西：底色可以被材质让位，沾色必须在材质之上。

> **为什么卡片底色不能沿用 `@Prop cardBackground = HwGlassCardColor.surface` 的默认值：**
> `@Prop` 的默认值只在**组件构造时**求值一次，之后开关怎么变都不会重新取。
> 必须订阅一个真正的 AppStorage 键。

这两个开关**都不改变主题色本身**，所以不能指望 `accentColor` 变化来触发刷新 ——
`applyAppTheme()` 把结果分别发布到 `pageBackground` / `cardSurface`，
订阅它们的元素才会更新。这是 §7.8 那条依赖规则的直接应用。

**`background` 和 `backgroundDark` 必须同时染。** 页面里的写法是
`this.isDarkMode ? HwColor.backgroundDark : HwColor.background`，
只改前者的话暗色模式下背景纹丝不动。

### 5.9 「主题色流光」：按压时的跟手光晕

沉浸光感的按压反馈有两处，颜色都由设置页的**「主题色流光」**开关（`immersivePressGlow`，默认开）
统一控制：开启时用主题色，关闭时回到系统默认的白光。

**（1）卡片上的跟手光晕**（`MaterialCard`）。分三层：

| 层 | 尺寸 | 位置 | 作用 |
| --- | --- | --- | --- |
| 手指光斑 | `matchParent` + 自带圆角 | 材质之上、内容之下 | 手指底下那团光，被卡片圆角收住 |
| 溢出光晕 | 比卡片大一圈（0 尺寸锚点放置） | 卡内被材质盖住，只留卡外 | 卡与卡之间的缝隙里能看到一点辉光 |
| 边缘高光 | `matchParent`，逐边画一小段 | 最上层 | 光照到的那**一段**边上亮起来，玻璃棱的反光 |

**边缘高光必须各卡画各卡的。** 光要照到别的卡片上，而卡片之间互相看不见：
被按住的那张卡把光源位置广播出去（`utils/PressGlowBeacon.ets`），
附近的卡读这个位置、算出自己哪条边被照到，再在自己边上画一段高光。
另外两条路都试过，都不行：

- 把光画在相邻卡片**下面**：沉浸光感材质不透光，邻卡内部完全看不到，等于没画；
- 把光画在相邻卡片**上面**：邻卡内部被照亮，成了「糊一层主题色」，不是反光。

> ⚠️ **只画被照到的那一小片，绝不给整张卡描边。** 光源只落在离它最近的边框上，
> 整圈都亮就变成「选中态」了。`PressRim` 的做法是：取「光到卡片矩形最近的那个点」，
> 在那里放一个圆形柔光，半径随距离变化（34~108vp），超过 120vp 完全不亮。

> ⚠️ **高光要用「渐变圆心」摆位置，不要拿一个小方块挪过去。** 高光层跟卡片同尺寸
> （`matchParent`）、圆角与卡片一致，光斑靠 `radialGradient` 的 `center` 落在边框上。
> 曾经把光斑写成一个位置可正可负的小方块，为了不让它把卡片撑大又套了一层 0 尺寸锚点——
> 结构复杂且没验证过是否真的渲染。同尺寸层 + 挪圆心既没有撑大的风险，也不用锚点。

> ⚠️ **R 角上要有光，就不能用沿边铺的直条。** 直条在圆角处拐不过弯，R 角会完全没有光效。
> 圆形光斑落在角上时被卡片自己的圆角裁成一段弧，正好沿弧包过去——这是选圆形而不是直条的原因。

> ⚠️ **广播的坐标必须和邻卡量自己矩形用的坐标是同一套。** 邻卡用
> `onAreaChange` 的 `Area.globalPosition` 量自己，广播就得发这一套
> （光源位置 = 卡片 `globalPosition` + 卡片内坐标）。
> 曾经把触摸事件的窗口坐标 `windowX/Y` 直接广播出去，两套原点差着一个常量，
> 距离全算错——真机上表现为**该亮上边、亮的却是右边**。

- **坐标必须走窗口坐标系。** 触摸事件给的是 `windowX/windowY`，要减去卡片自身
  在窗口中的原点才能换算成卡片内坐标。卡片原点在 `Down` 那一瞬由 `windowX - x`
  反推（这时组件内坐标一定准），之后靠 `onAreaChange` 报的 `globalPosition`
  **位移增量**维护。
  > ⚠️ 直接用 `touches[0].x/y`（组件内坐标）在**页面滚动**时会有问题：
  > 列表被滚动带走、手指没动，组件内坐标却跟着变，光斑看着就黏在卡片原处。
  > 只取 `globalPosition` 的增量、不用其绝对值，是因为它的原点与 `windowX/Y`
  > 未必同一套，但滚动中的变化量必然一致。
- `Down` / `Move` 都要处理：流光之所以像「光」而不像「按下高亮」，
  就在于手指在卡片上滑动时它跟着走。`Up` / `Cancel` 必须熄灭，
  否则会留一块不会消失的光斑。
- 光斑是一层 `radialGradient`，由内到外三档淡出；只用一档实色会得到一个硬边圆盘。
- **溢出光晕刻意不抬 `zIndex`**：让后画的相邻卡片盖住它，盖住之后只剩透过玻璃的
  一点亮度——这才是「光在邻卡边缘的反光」，而不是把邻卡内部照亮。
  第一版做成 `shadow()` 外发光正是错的：那是给卡片描了一圈边。

```ts
@Builder
cardBody() {
  if (this.materialActive()) {
    MaterialCardLayer({ layerRadius: this.cardRadius })
  }
  if (this.cardTint.length > 0) { /* 沾色层，见 §5.8 */ }
  this.pressGlowLayer()          // ← 流光：材质之上、内容之下
  Flex({ ... }) { this.cardContent() }
}
```

**（2）底部 HdsTab 悬浮栏的流光。** 这个光由 `HdsTabs` 自己绘制，
不归应用的材质管，必须**单独下发**：

```ts
.barFloatingStyle({
  // ...
  lightColor: this.tabLightColor()      // 读订阅变量后由 pressLightColor() 决定
})
```

底栏的光同样要**洒到附近卡片的边上**，但它归系统画，我们只知道手指在哪：

- 触摸被悬浮栏整段吃掉，挂在页面根节点上的 `onTouch` **一个事件都收不到**（真机验证过）；
- 于是在底栏那一条带子上盖一层透明层专门收触摸，`HitTestMode.Transparent`
  表示「自己也响应、但不阻塞下面的兄弟节点」，底栏的点击与滑动照常可用；
- 判定带要**给足余量**：底栏实际高度由系统决定，不等于 `BOTTOM_BAR_HEIGHT`。
  第一版按 `BOTTOM_BAR_HEIGHT` 卡得太紧，手指落在底栏上半截时全部漏掉，表现为「按了没反应」；
- 只有「按下就落在底栏里」的那一次手势才广播，否则手指在卡片上按时，
  这里会因为「不在底栏」而把卡片刚点亮的流光清掉。

> ⚠️ `pressLightColor(themedLightOn, accentColor)` 刻意做成**纯函数、由调用方把订阅值传进来**，
> 和 `resolvePageBackground()` 同一个理由：函数里直接 `AppStorage.get()` 登记不上依赖，
> 拨开关或切主题色时已经画出来的按钮 / 卡片 / 底栏不会重新求值，流光会停在旧颜色上（见 §7.8）。

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
（这类字面量现已全部清出仓库，`grep -rn '3379B7' entry/src/main/ets/` 应为空。）

注意 **`const` 对象也要在 `applyAppTheme()` 里重新赋值**，否则同样不会跟着变：

```ts
// 只留一个与默认主题色同色的占位值，真实值由 applyAppTheme 派生
export const HwGlassCardColor: HwGlassCardPalette = { surface: '#E8F0F8', border: '#1A0A59F7' };

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
但凡是**带色相**的（如 `#1A0A59F7`）都需要改成 `withAlpha(主题色, α)`。

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

### 7.5.1 材质自带投影，小尺寸芯片要关掉

`ImmersiveMaterial` 的 `applyShadow` **默认为 `true`**，材质会自带一层投影。
大卡片上这是加分项，但小尺寸芯片（房间筛选、排序、分类切换）上会显得像
「按钮背后顶了一层影子」。这类地方把 `MaterialCardLayer` 的 `layerShadow` 传 `false`：

```ts
MaterialCardLayer({ layerRadius: HwRadius.pill, layerShadow: false })
```

实现上是在 `SystemMaterial` 里单独缓存了一档不带阴影的材质
（`applyShadow: false`），而不是关掉全局阴影 —— 卡片的投影要保留。

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

> **`@Prop` 的默认值也属于这一类。** `@Prop cardBackground = HwGlassCardColor.surface`
> 只在**组件构造时**求值一次，之后 token 怎么变都不会重新取。
> 卡片底色因此改成订阅 `cardSurface`（见 §5.8）。
> 判断标准一样：**这个值会不会在组件存活期间变化？会，就不能用 `@Prop` 默认值。**

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

### 7.9 比父容器大的子节点会把父容器撑大

流光最初写成一个比卡片大一圈的层、用 `.position()` 甩到卡片外面，想让它溢出去照亮相邻卡片。
结果是**按下时卡片自己变大**：`Stack` 的尺寸取最大子节点，`position` 只改摆放位置、
不改布局尺寸，多出来的那一圈全算进了卡片。

正确做法有两条路，按需求选：

- **光要留在卡片里**（本项目最终采用，见 §5.9）：光斑层用 `LayoutPolicy.matchParent`，
  超出部分交给外壳的 `clip(true)` 连同圆角一起裁掉。既然不越界，就不存在撑大问题。
- **光必须溢出到卡片外**：把溢出内容放进一个 `.width(0).height(0)` 的锚点容器，
  再在锚点里用 `position` 摆放。锚点自身不占地方，卡片量尺寸时不会被带大。

### 7.10 沉浸光感材质不采样同一 `Stack` 里的兄弟节点

流光的层级一度放在材质**之下**，想让材质那层玻璃滤镜把它折射开。
真机结果是**完全看不见**：`systemMaterial` 采样的是组件背后的窗口内容，
并不会把同一 `Stack` 里先画的兄弟节点当成背景。

结论：压在材质之上的层才看得见。想让光有「液态玻璃」的观感，
靠的是卡片圆角的裁切加上材质自身的边缘折射，而不是把光塞到材质底下。

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

