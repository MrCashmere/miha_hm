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
 * 主题色预设。
 * - harmony：鸿蒙默认蓝（HarmonyOS 品牌色）
 * - rose   ：昔涟粉
 * - custom ：用户在设置里输入 RRGGBB
 */
export const ACCENT_PRESETS: AccentPreset[] = [
  { key: 'harmony', label: '鸿蒙蓝', value: '#0A59F7' },
  { key: 'rose', label: '昔涟粉', value: '#E86A92' },
];

/** 主题色设置键：存预设 key 或 'custom' */
export const ACCENT_KEY_STORAGE: string = 'accentKey';
/** 自定义主题色设置键：存 RRGGBB（不含 #） */
export const ACCENT_CUSTOM_STORAGE: string = 'accentCustom';
/** 自定义主题色列表设置键：存 RRGGBB（不含 #）字符串数组，顺序即展示顺序 */
export const ACCENT_CUSTOM_LIST_STORAGE: string = 'accentCustomList';

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
 * 预设命中则用预设值；未命中（custom）时用自定义值，自定义非法则回落到鸿蒙蓝。
 */
export function resolveAccentColor(accentKey: string, customHex: string): string {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === accentKey) {
      return ACCENT_PRESETS[i].value;
    }
  }
  const normalized = normalizeAccentHex(customHex);
  return normalized.length > 0 ? normalized : '#0A59F7';
}

export const HwColor: HwColorPalette = {
  primary: '#3379B7',         // 米家蓝
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
  let accentKey = 'harmony';
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
  HwColor.background = isDark ? '#1A2D44' : '#DCEAF8';
  HwColor.surface = isDark ? '#22334F' : '#FFFFFF';
  HwColor.textPrimary = isDark ? '#EDF1F7' : '#1A1A1A';
  HwColor.textSecondary = isDark ? '#9BA8BC' : '#7A8089';
  MijiaSheetBackground = isDark ? '#2A3B58' : '#E3EAF4';
  HwGlassCardColor.surface = isDark ? '#26364F' : '#E8F0F8';
  // 卡片描边也跟着主题色走：写死 '#1A3379B7'（旧米家蓝 10% 透明）在切色后会露出蓝边，
  // 而卡片描边本来就该是同色系的淡描边。
  HwGlassCardColor.border = withAlpha(HwColor.primary, 0.1);
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
  // 占位值，真实值由 applyAppTheme 按主题色派生（见下）
  border: '#1A3379B7'
};
