/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 鸿米家（miha）项目开发者
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * 米家官方浅蓝白主题色板
 * - 页面背景：浅蓝
 * - 卡片：白色 / 深灰概览卡
 * - 顶栏：深蓝渐变
 */

export interface HwColorPalette {
  primary: string;
  background: string;
  backgroundDark: string;
  surface: string;
  textPrimary: string;
  textSecondary: string;
  danger: string;
  online: string;
}

/** 主题色预设 */
export interface AccentPreset {
  key: string;
  label: string;
  value: string;
}

/**
 * 默认主题色（= 预设首位的鸿蒙蓝）。
 *
 * 未设置过主题色、存储读失败、自定义色非法，一律落到这一档。
 * 刻意只留 `key`/`value` 两个常量而**不再单列一个「默认色」预设**：
 * 默认色本身就该是鸿蒙蓝，多摆一个同名不同色的色块只会让人分不清
 * 到底哪个才是默认。「鸿蒙蓝」这个名字保持不变。
 */
export const DEFAULT_ACCENT_KEY: string = 'harmony';
/** 默认主题色的值：鸿蒙蓝 */
export const DEFAULT_ACCENT_VALUE: string = '#0A59F7';

/**
 * 主题色预设。
 * - harmony：鸿蒙默认蓝（HarmonyOS 品牌色），也是默认值
 * - rose   ：昔涟粉
 * - ripple ：涟漪粉（浅色）
 * - firefly：流萤绿（浅色）
 * - custom ：用户在设置里输入 RRGGBB
 *
 * 注意 `ripple` / `firefly` 是**浅色**：压在它们上面的文字不能用白色，
 * 凡是「主题色底 + 文字」的地方都要走 `onAccentColor()` 取前景色。
 */
export const ACCENT_PRESETS: AccentPreset[] = [
  { key: 'harmony', label: '鸿蒙蓝', value: '#0A59F7' },
  { key: 'rose', label: '昔涟粉', value: '#E86A92' },
  { key: 'ripple', label: '涟漪粉', value: '#FAD6E4' },
  { key: 'firefly', label: '流萤绿', value: '#88E4D4' },
];

/** 主题色设置键：存预设 key 或 'custom' */
export const ACCENT_KEY_STORAGE: string = 'accentKey';
/** 自定义主题色设置键：存 RRGGBB（不含 #） */
export const ACCENT_CUSTOM_STORAGE: string = 'accentCustom';
/** 自定义主题色列表设置键：存 RRGGBB（不含 #）字符串数组，顺序即展示顺序 */
export const ACCENT_CUSTOM_LIST_STORAGE: string = 'accentCustomList';

/**
 * 深色模式偏好：'system'（跟随系统）/ 'light' / 'dark'。
 *
 * 刻意用三态字符串而不是布尔量：布尔量一旦被用户拨动过就永久生效，
 * **再也没法回到「跟随系统」**——这正是「深色模式不跟随系统」的原因。
 * 三态让「跟随系统」始终是一个可以选回来的状态。
 */
export const DARK_MODE_PREF_STORAGE: string = 'darkModePreference';
/** 深色模式偏好取值 */
export const DARK_MODE_SYSTEM: string = 'system';
export const DARK_MODE_LIGHT: string = 'light';
export const DARK_MODE_DARK: string = 'dark';

/** 卡片沾色开关：打开后所有卡片底色混入 10% 主题色 */
export const CARD_TINT_STORAGE: string = 'cardTintEnabled';
/** 高权限自定义主题色：打开后自定义色也参与页面背景染色（默认只允许内置预设色） */
export const CUSTOM_ACCENT_FULL_ACCESS_STORAGE: string = 'customAccentFullAccess';
/**
 * 卡片「流光触感」开关（默认关闭）。
 *
 * 关：按压卡片只保留**溢出到卡间缝隙的环境光**（映照）；
 * 开：手指底下那团跟手光斑一起亮，也就是完整的「触碰反馈的流光」。
 * 只作用于卡片，**不影响底部 HdsTab 悬浮栏的流光**。
 */
export const CARD_GLOW_TOUCH_STORAGE: string = 'cardGlowTouch';

/**
 * 沉浸光感「主题色流光」开关。
 *
 * 开启：按压卡片 / 圆形图标按钮的流光与光晕用主题色；
 * 关闭：回到系统默认的白色流光（即改动前的观感）。
 */
export const PRESS_GLOW_STORAGE: string = 'immersivePressGlow';
/** 页面底色广播键：由 applyAppTheme 写入，页面订阅它（见 resolvePageBackground） */
export const PAGE_BACKGROUND_KEY: string = 'pageBackground';
/** 卡片底色广播键：由 applyAppTheme 写入，卡片订阅它（见 MaterialCard） */
export const CARD_SURFACE_KEY: string = 'cardSurface';
/** 卡片沾色叠加层广播键：空串表示不沾色。沾色必须叠在材质之上，混进底色看不见 */
export const CARD_TINT_KEY: string = 'cardTintColor';

/** 读一个布尔开关，读取失败时用默认值 */
function readFlag(key: string, fallback: boolean): boolean {
  try {
    const value = AppStorage.get<boolean>(key);
    return value === undefined ? fallback : value;
  } catch (err) {
    return fallback;
  }
}

/**
 * 规范化自定义主题色列表：逐项过滤非法值并去重。
 * 持久化内容可能被外部改坏或残留旧版本数据，读入时统一兜底。
 */
export function normalizeAccentList(raw: string[]): string[] {
  const list: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    const hex = normalizeAccentHex(String(raw[i])).replace('#', '');
    if (hex.length === 6 && list.indexOf(hex) < 0) {
      list.push(hex);
    }
  }
  return list;
}

/**
 * 给 `#RRGGBB` 叠加透明度，返回 `#AARRGGBB`。
 *
 * 用来做「主题色的浅色底」这类半透明填充：以前这些位置写的是
 * `#263379B7`、`#1A3379B7` 这种把旧米家蓝硬编进去的字面量，
 * 切主题色后它们不会跟着变，选中态会露出蓝底。
 */
export function withAlpha(color: string, alpha: number): string {
  const normalized = normalizeAccentHex(color);
  if (normalized.length === 0) {
    return color;
  }
  const clamped = Math.max(0, Math.min(1, alpha));
  const channel = Math.round(clamped * 255).toString(16).toUpperCase().padStart(2, '0');
  return `#${channel}${normalized.substring(1)}`;
}

/**
 * 页面底色。**所有页面统一走这个函数，不要直接读 `HwColor.background`。**
 *
 * 为什么要绕一层函数：ArkUI 的局部更新按**表达式**记录依赖，而 `HwColor` 是模块级对象
 * ——读它的属性不会被登记。直接写 `this.isDarkMode ? HwColor.backgroundDark : HwColor.background`
 * 只登记了 `isDarkMode`，于是切换主题色时底色不会重新求值，已打开的页面会停在旧色上。
 * 把 `accentColor` 作为入参传进来，调用点就真正读到了这个订阅键，依赖才登记得上。
 *
 * 两个参数都必须是调用方声明的订阅变量（`@StorageProp` / `@StorageLink`），
 * 传字面量或普通字段没有意义。
 */
export function resolvePageBackground(isDark: boolean, background: string): string {
  if (background.length > 0) {
    return background;
  }
  // 兜底：applyAppTheme 尚未跑过时（理论上不会）退回当前 token
  return isDark ? HwColor.backgroundDark : HwColor.background;
}

/**
 * 两个 `#RRGGBB` 线性混合：ratio=0 取 base，ratio=1 取 tint。
 * 用于把主题色调成「很淡的底色」——直接铺主题色会盖过正文。
 * 任一输入非法时原样返回 base，绝不返回半成品颜色。
 */
export function mixHex(base: string, tint: string, ratio: number): string {
  const a = normalizeAccentHex(base);
  const b = normalizeAccentHex(tint);
  if (a.length === 0 || b.length === 0) {
    return a.length > 0 ? a : base;
  }
  const clamped = Math.max(0, Math.min(1, ratio));
  let out = '#';
  for (let i = 1; i < 7; i += 2) {
    const ca = parseInt(a.substring(i, i + 2), 16);
    const cb = parseInt(b.substring(i, i + 2), 16);
    const mixed = Math.round(ca + (cb - ca) * clamped);
    out += mixed.toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

/**
 * 压在主题色上的前景色。
 *
 * 主题色不都是深色：涟漪粉 `#FAD6E4`、流萤绿 `#88E4D4` 都很浅，
 * 上面再压白字基本看不清。统一按**相对亮度**决定用黑字还是白字，
 * 新增浅色预设时不必再去逐个调用点改字色。
 *
 * 阈值 0.62 偏保守（宁可早一点切黑字）：按 sRGB 加权亮度算，
 * 鸿蒙蓝 0.33、昔涟粉 0.58 走白字，涟漪粉 0.89、流萤绿 0.78 走黑字。
 */
export function onAccentColor(accentColor: string): string {
  const normalized = normalizeAccentHex(accentColor);
  if (normalized.length === 0) {
    return '#FFFFFF';
  }
  const r = parseInt(normalized.substring(1, 3), 16);
  const g = parseInt(normalized.substring(3, 5), 16);
  const b = parseInt(normalized.substring(5, 7), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.62 ? '#1A1A1A' : '#FFFFFF';
}

/**
 * 是否是内置预设的 key（`custom` 不是预设，返回 false）。
 *
 * 与按颜色判定的 `isPresetAccent` 不同：这里判的是设置里存的那个 key，
 * 用来给存储兜底——旧版本或异常写入可能留下一个已经不存在的 key。
 */
export function isPresetAccentKey(key: string): boolean {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === key) {
      return true;
    }
  }
  return false;
}

/**
 * 是否是内置预设主题色。
 *
 * 页面背景只跟随预设色：自定义色是用户随手输的，
 * 拿它铺满整页底色很容易脏，也可能与正文对比度不足。
 */
export function isPresetAccent(color: string): boolean {
  const normalized = normalizeAccentHex(color);
  if (normalized.length === 0) {
    return false;
  }
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (normalizeAccentHex(ACCENT_PRESETS[i].value) === normalized) {
      return true;
    }
  }
  return false;
}

/**
 * 校验自定义主题色输入：只接受 6 位十六进制（可带 #），大小写均可。
 * 返回规范化后的 `#RRGGBB`，非法时返回空串。
 */
export function normalizeAccentHex(input: string): string {
  const raw = input.trim().replace('#', '');
  if (raw.length !== 6) {
    return '';
  }
  for (let i = 0; i < raw.length; i++) {
    const c = raw.charAt(i).toLowerCase();
    const isDigit = c >= '0' && c <= '9';
    const isHex = c >= 'a' && c <= 'f';
    if (!isDigit && !isHex) {
      return '';
    }
  }
  return `#${raw.toUpperCase()}`;
}

/**
 * 按当前设置解析主题色。
 * 预设命中则用预设值；未命中（custom）时用自定义值，自定义非法则回落到默认主题色。
 */
export function resolveAccentColor(accentKey: string, customHex: string): string {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === accentKey) {
      return ACCENT_PRESETS[i].value;
    }
  }
  const normalized = normalizeAccentHex(customHex);
  return normalized.length > 0 ? normalized : DEFAULT_ACCENT_VALUE;
}

export const HwColor: HwColorPalette = {
  primary: DEFAULT_ACCENT_VALUE, // 鸿蒙蓝（默认主题色，切色后由 applyAppTheme 覆盖）
  background: '#DCEAF8',      // 浅蓝主背景
  backgroundDark: '#1A2D44',  // 深色背景（暗色模式）
  surface: '#FFFFFF',         // 白卡
  textPrimary: '#1A1A1A',     // 主文深
  textSecondary: '#7A8089',   // 副文灰
  danger: '#D94838',          // 警示红
  online: '#1AAB6A'           // 绿开
};

/** 首页顶栏深蓝渐变（自上而下：深→亮） */
export const MijiaHeaderGradient: string[] = ['#2F658C', '#3B7094', '#46789C'];

/** 概览/设备卡（灰色卡，浅蓝背景） */
export const MijiaOverviewCard: string = '#4E5A68';
export const MijiaOverviewCardPressed: string = '#414D59';
export const MijiaOverviewCardText: string = '#FFFFFF';
export const MijiaOverviewCardValue: string = '#A9D4FF';

/** 深色背景上的浅灰辅助文字 */
export const MijiaDarkSubText: string = '#A9B4C4';

/** 弹窗背景：浅蓝灰 */
export let MijiaSheetBackground: string = '#E3EAF4';

/**
 * 应用主题：把暗/浅色值写入 DesignTokens 的可变 token。
 * 页面已普遍 @StorageProp('isDarkMode')，翻转该键会触发整页重建，
 * 重建时读取到的是这里写入的最新值。
 */
/**
 * 按已保存的设置重建主题并广播。
 *
 * 主题色切换要「实时生效」：HwColor 是模块级对象，直接改属性不会触发刷新，
 * 所以这里把新值写进 AppStorage 的 accentColor / isDarkMode，
 * 页面用 @StorageProp + @Watch 监听并重建，颜色立即切换。
 */
export function reloadAppTheme(): void {
  let isDark = false;
  let accentKey = DEFAULT_ACCENT_KEY;
  let accentCustom = '';
  try {
    isDark = AppStorage.get<boolean>('isDarkMode') === true;
  } catch (err) {
    isDark = false;
  }
  try {
    const stored = AppStorage.get<string>('accentKey');
    if (stored !== undefined && stored.length > 0) {
      accentKey = stored;
    }
    const custom = AppStorage.get<string>('accentCustom');
    if (custom !== undefined) {
      accentCustom = custom;
    }
  } catch (err) {
    // 存储不可用时用默认预设
  }
  const resolved = resolveAccentColor(accentKey, accentCustom);
  applyAppTheme(isDark, resolved);
  AppStorage.setOrCreate('accentColor', resolved);
}

export function applyAppTheme(isDark: boolean, accentColor: string = ''): void {
  if (accentColor.length > 0) {
    HwColor.primary = accentColor;
  }
  // 默认背景跟随预设主题色，且刻意压得很淡：
  // 浅色 = 主题色与白色按 12% 混合，深色 = 与深底按 18% 混合。
  // 页面用的是 `isDarkMode ? backgroundDark : background`，所以两个都要跟着染。
  const backgroundBaseDark = '#1A2D44';
  // 默认只让内置预设色参与背景染色；打开「高权限自定义主题色」后自定义色也放行
  const fullAccess = readFlag(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, false);
  const followed = accentColor.length > 0 && (isPresetAccent(accentColor) || fullAccess);
  const tintedLight = followed ? mixHex('#FFFFFF', accentColor, 0.12) : '#DCEAF8';
  const tintedDark = followed ? mixHex(backgroundBaseDark, accentColor, 0.18) : backgroundBaseDark;
  HwColor.background = isDark ? tintedDark : tintedLight;
  HwColor.backgroundDark = tintedDark;
  HwColor.surface = isDark ? '#22334F' : '#FFFFFF';
  HwColor.textPrimary = isDark ? '#EDF1F7' : '#1A1A1A';
  HwColor.textSecondary = isDark ? '#9BA8BC' : '#7A8089';
  MijiaSheetBackground = isDark ? '#2A3B58' : '#E3EAF4';
  // 卡片底色留 70% 透明度：沉浸光感不可用时会降级为毛玻璃（backgroundBlurStyle），
  // 不透明的底色会把模糊整个盖住，等于没有降级效果。
  // 刻意**不把沾色混进这里**：材质生效时外壳底色是透明的（见 MaterialCard.shellBackground），
  // 混进去的颜色根本不会被画出来。沾色改为叠在材质之上的一层（见 cardTintColor）。
  HwGlassCardColor.surface = isDark ? '#B326364F' : '#B3E8F0F8';
  // 卡片描边也跟着主题色走：原先写死的是把**米家蓝**按 10% 透明硬编进去的字面量，
  // 切主题色后会露出旧蓝边；卡片描边本来就该是同色系的淡描边。
  // 这里只留一个与默认主题色同色的占位值，真实值由 applyAppTheme 派生。
  HwGlassCardColor.border = withAlpha(HwColor.primary, 0.1);

  // 发布两个广播键。页面与卡片必须订阅它们而不是直接读 HwColor：
  // ArkUI 按表达式记录依赖，模块级对象的属性读取不会被登记，
  // 开关沾色或切主题色时已经画出来的元素不会重新求值（见文档 §7.8）。
  AppStorage.setOrCreate(PAGE_BACKGROUND_KEY, HwColor.background);
  AppStorage.setOrCreate(CARD_SURFACE_KEY, HwGlassCardColor.surface);
  AppStorage.setOrCreate(CARD_TINT_KEY,
    accentColor.length > 0 && readFlag(CARD_TINT_STORAGE, false)
      ? withAlpha(accentColor, 0.1) : '');
}

/** 兼容旧引用（深色主题已回退，保留符号避免遗留编译失败） */
export const MijiaSkyGradient: string[] = MijiaHeaderGradient;
export const MijiaDarkCard: string = MijiaOverviewCard;
export const MijiaDarkCardPressed: string = MijiaOverviewCardPressed;
export const MijiaDarkCardText: string = MijiaOverviewCardText;
export const MijiaDarkCardSub: string = '#A0AAB8';
export const MijiaDarkCardIcon: string = MijiaOverviewCardValue;
export const MijiaWhiteCard: string = '#FFFFFF';
export const MijiaWhiteCardText: string = '#1A1A1A';
export const MijiaWhiteCardSub: string = '#7A8089';
export const MijiaOnButton: string = HwColor.online;
export const MijiaOffButton: string = '#4A5666';
export const MijiaTabBar: string = '#1A2D44';
export const MijiaTabBarActive: string = '#FFFFFF';
export const MijiaTabBarInactive: string = '#7A8493';
export const MijiaRoomPill: string = '#FFFFFF';
export const MijiaRoomPillActive: string = '#FFFFFF';
export const MijiaRoomPillText: string = '#FFFFFF';
export const MijiaRoomPillTextActive: string = '#2A4A6E';

export interface HwRadiusScale {
  card: number;
  control: number;
  pill: number;
  small: number;
  large: number;
}

export const HwRadius: HwRadiusScale = {
  card: 14,
  control: 12,
  pill: 999,
  small: 8,
  large: 18
};

export interface HwSpaceScale {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

export const HwSpace: HwSpaceScale = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24
};

export interface HwGlassCardPalette {
  surface: string;
  border: string;
}

export const HwGlassCardColor: HwGlassCardPalette = {
  surface: '#E8F0F8',
  // 占位值（默认主题色 10% 透明），真实值由 applyAppTheme 按主题色派生（见下）
  border: '#1A0A59F7'
};
