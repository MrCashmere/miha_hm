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

import { router, uiAppearance } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { text } from '@kit.ArkGraphics2D';
import { ACCENT_CUSTOM_LIST_STORAGE, ACCENT_CUSTOM_STORAGE, ACCENT_KEY_STORAGE, ACCENT_PRESETS, AccentPreset, CARD_TINT_STORAGE, CUSTOM_ACCENT_FULL_ACCESS_STORAGE, DARK_MODE_DARK, DARK_MODE_LIGHT, DARK_MODE_PREF_STORAGE, DARK_MODE_SYSTEM, DEFAULT_ACCENT_KEY, HwColor, HwRadius, HwSpace, PRESS_GLOW_STORAGE, applyAppTheme, normalizeAccentHex, normalizeAccentList, onAccentColor, reloadAppTheme, resolveAccentColor, resolvePageBackground,
  withAlpha } from '../utils/DesignTokens';
import { isApi26OrAbove, materialDiagnostics, sheetBlurStyle } from '../utils/SystemMaterial';
import { loadCustomFonts } from '../utils/CustomFonts';
import { MaterialCard, MaterialCardLayer, MaterialSheetPanel, AccentColorSentinel } from '../components/MaterialCard';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppBackground } from '../components/AppBackground';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { FeedbackLogService } from '../services/FeedbackLogService';

@Entry
@Component
struct AppearanceSettingsPage {
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
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  /** 主题色变化时触发重建，让 HwColor.primary 的新值生效 */
  @StorageProp('accentColor') @Watch('onAccentColorChanged') accentColor: string = '';
  /** 深色模式。用 @StorageLink 而非 @StorageProp：开关需要写回 AppStorage，
   *  其余页面订阅同一个键，切一下全应用跟着变。 */
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  /** 深色模式偏好（三态）：跟随系统 / 浅色 / 深色。默认跟随系统 */
  @StorageLink('darkModePreference') darkModePref: string = 'system';
  /** 页面底色（由 applyAppTheme 发布）。订阅它而不是读 HwColor 属性，见 docs/ThemeColor.md §7.8 */
  @StorageProp('pageBackground') pageBackground: string = '';
  @StorageLink('backgroundImage') wallpaperImage: string = '';
  @StorageLink('autoMultiColumn') autoMultiColumn: boolean = false;
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';
  @StorageLink('fontSizeMode') fontSizeMode: string = 'system';
  @StorageLink('fontSizeValue') fontSizeValue: number = 16;
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  /** 卡片沾色：打开后所有卡片底色混入 10% 主题色 */
  @StorageLink('cardTintEnabled') cardTintEnabled: boolean = false;
  /** 高权限自定义主题色：打开后自定义色也参与页面背景染色 */
  @StorageLink('customAccentFullAccess') customAccentFullAccess: boolean = false;
  /** 沉浸光感主题色流光：打开后按压的流光/光晕用主题色，关闭回到系统白光 */
  @StorageLink('immersivePressGlow') pressGlowEnabled: boolean = true;
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  @StorageLink('customFonts') customFonts: string[] = [];
  /** 主题色：预设 key（default/harmony/rose/custom） */
  @StorageLink('accentKey') accentKey: string = DEFAULT_ACCENT_KEY;
  /** 自定义主题色（RRGGBB，不含 #） */
  @StorageLink('accentCustom') accentCustom: string = '';
  /** 用户新增的自定义主题色列表（RRGGBB，不含 #），顺序即展示顺序 */
  @State accentList: string[] = [];
  /** 自定义主题色的输入弹窗 */
  @State showAccentSheet: boolean = false;
  /** 自定义输入框草稿与校验提示 */
  @State accentDraft: string = '';
  @State accentError: string = '';
  @State backgroundMessage: string = '';
  @State fontMessage: string = '';
  @State availableFonts: string[] = [];

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  /**
   * 开关的选中色。
   * 读 accentColor 建立依赖：直接写 HwColor.primary 在切主题色后不会重新求值，
   * 开关会停留在旧色。
   */
  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : HwColor.primary;
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('外观设置页');
    this.loadAccentList();
    this.loadCustomFonts();
    this.refreshAvailableFonts();
    this.applyFontSizeScale();
  }

  /**
   * 读入自定义主题色列表。
   *
   * 兼容旧版本：早期只有一个 accentCustom，没有列表，这里把它补进列表，
   * 否则升级后用户原有那个自定义色会在界面上凭空消失。
   */
  private loadAccentList(): void {
    const stored = AppSettingsStore.getStringArray(ACCENT_CUSTOM_LIST_STORAGE, []);
    const list = normalizeAccentList(stored);
    const current = normalizeAccentHex(this.accentCustom).replace('#', '');
    if (current.length === 6 && list.indexOf(current) < 0) {
      list.push(current);
      AppSettingsStore.setStringArray(ACCENT_CUSTOM_LIST_STORAGE, list);
    }
    this.accentList = list;
  }

  onPageShow(): void {
    this.refreshAvailableFonts();
  }

  private fontDir(): string {
    const context = getContext(this) as common.UIAbilityContext;
    return `${context.filesDir}/custom_fonts`;
  }

  loadCustomFonts(): void {
    const context = getContext(this) as common.UIAbilityContext;
    loadCustomFonts(context.filesDir, this.customFonts);
  }

  async refreshAvailableFonts(): Promise<void> {
    const names: string[] = [];
    for (let i = 0; i < this.customFonts.length; i++) {
      const fileName = this.customFonts[i];
      const alias = fileName.substring(0, fileName.length - 4);
      if (names.indexOf(alias) < 0) {
        names.push(alias);
      }
    }
    try {
      const systemFonts = await text.getSystemFontFullNamesByType(text.SystemFontType.ALL);
      for (let i = 0; i < systemFonts.length; i++) {
        const family = systemFonts[i];
        if (names.indexOf(family) < 0) {
          names.push(family);
        }
      }
    } catch (err) {
    }
    this.availableFonts = names;
  }

  async pickBackgroundImage(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const imagePicker = new photoAccessHelper.PhotoViewPicker();
      const result = await imagePicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris.length === 0) {
        return;
      }
      const sourceUri = result.photoUris[0];
      const tempPath = `${context.filesDir}/background_source`;
      let cropUri = sourceUri;
      try {
        try {
          fs.unlinkSync(tempPath);
        } catch (ignored) {
        }
        await fs.copyFile(sourceUri, tempPath);
        cropUri = `file://${tempPath}`;
      } catch (copyErr) {
        // Keep the picker URI when the sandbox copy is unavailable.
      }
      router.pushUrl({
        url: 'pages/BackgroundCropPage',
        params: { sourceUri: cropUri }
      });
    } catch (err) {
      this.backgroundMessage = '选择图片失败';
    }
  }

  clearBackground(): void {
    this.wallpaperImage = '';
    AppSettingsStore.delete('backgroundImage');
    this.backgroundMessage = '背景已清空';
  }

  showClearBackgroundDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '清空背景',
      message: '确定要清空当前自定义背景吗？清空后无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: HwColor.danger,
        action: () => {
          this.clearBackground();
        }
      }
    });
  }

  async uploadFont(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const result = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.ttf', '.otf']
      });
      if (result.length === 0) {
        return;
      }
      const sourceUri = result[0];
      let srcFile: fs.File | undefined = undefined;
      let fileName = '';
      try {
        srcFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
        fileName = srcFile.name;
      } catch (openErr) {
        this.fontMessage = '无法读取所选字体文件';
        return;
      }
      if (fileName.length === 0) {
        try {
          const rawName = sourceUri.split('/').pop() ?? '';
          fileName = decodeURIComponent(rawName);
        } catch (nameErr) {
          this.fontMessage = '无法识别字体文件名';
          return;
        }
      }
      if (srcFile === undefined) {
        this.fontMessage = '无法读取所选字体文件';
        return;
      }
      const lowerName = fileName.toLowerCase();
      if (!lowerName.endsWith('.ttf') && !lowerName.endsWith('.otf')) {
        fs.closeSync(srcFile);
        this.fontMessage = '仅支持 ttf / otf 字体文件';
        return;
      }
      const dir = this.fontDir();
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      const ext = lowerName.endsWith('.ttf') ? '.ttf' : '.otf';
      const base = fileName.substring(0, fileName.length - 4);
      let targetName = fileName;
      let index = 1;
      while (fs.accessSync(`${dir}/${targetName}`)) {
        targetName = `${base}_${index}${ext}`;
        index++;
      }
      const targetPath = `${dir}/${targetName}`;
      const dstFile = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const buffer = new ArrayBuffer(1024 * 1024);
        while (true) {
          const readLen = fs.readSync(srcFile.fd, buffer);
          if (readLen <= 0) {
            break;
          }
          fs.writeSync(dstFile.fd, buffer, { length: readLen });
        }
      } finally {
        fs.closeSync(dstFile);
        fs.closeSync(srcFile);
      }
      const alias = targetName.substring(0, targetName.length - 4);
      try {
        text.FontCollection.getGlobalInstance().loadFontSyncWithCheck(alias, `file://${targetPath}`);
      } catch (verifyErr) {
        try {
          fs.unlinkSync(targetPath);
        } catch (ignored) {
        }
        this.fontMessage = '字体文件无效，请上传有效的 ttf / otf 文件';
        return;
      }
      const nextFonts: string[] = this.customFonts.slice();
      nextFonts.push(targetName);
      this.customFonts = nextFonts;
      AppSettingsStore.setStringArray('customFonts', nextFonts);
      this.refreshAvailableFonts();
      this.fontMessage = '字体上传成功';
    } catch (err) {
      this.fontMessage = '上传字体失败';
    }
  }

  setFontMode(mode: string): void {
    this.fontMode = mode;
    AppSettingsStore.setString('fontMode', mode);
  }

  setFontFamily(isEnglish: boolean, family: string): void {
    if (isEnglish) {
      this.fontFamilyEn = family;
      AppSettingsStore.setString('fontFamilyEn', family);
    } else {
      this.fontFamilyZh = family;
      AppSettingsStore.setString('fontFamilyZh', family);
    }
  }

  setFontSizeMode(mode: string): void {
    this.fontSizeMode = mode;
    AppSettingsStore.setString('fontSizeMode', mode);
    this.applyFontSizeScale();
  }

  setFontWeightMode(mode: string): void {
    this.fontWeightMode = mode;
    AppSettingsStore.setString('fontWeightMode', mode);
  }

  onFontSizeChange(value: number): void {
    const rounded = Math.round(value);
    this.fontSizeValue = rounded;
    AppSettingsStore.setNumber('fontSizeValue', rounded);
    this.applyFontSizeScale();
  }

  onFontWeightChange(value: number): void {
    const weight = Math.round(value / 100) * 100;
    this.fontWeightValue = weight;
    AppSettingsStore.setNumber('fontWeightValue', weight);
  }

  // ==================== 主题色 ====================

  /** 选择预设主题色并立即生效 */
  private selectAccentPreset(key: string): void {
    this.accentKey = key;
    AppSettingsStore.setString(ACCENT_KEY_STORAGE, key);
    this.applyAccentNow();
    FeedbackLogService.recordOperation('UI', `切换主题色预设 ${key}`);
  }

  /**
   * 新增自定义主题色。
   * 只接受 6 位十六进制；非法输入不入列表也不改主题，避免把配色改成不可读的颜色。
   * 新色追加到列表末尾——也就是「新增」按钮的前面——并立即选中生效。
   */
  private addCustomAccent(): void {
    const normalized = normalizeAccentHex(this.accentDraft);
    if (normalized.length === 0) {
      this.accentError = '请输入 6 位十六进制颜色，例如 1A2B3C';
      return;
    }
    this.accentError = '';
    const hex = normalized.replace('#', '');
    if (this.accentList.indexOf(hex) < 0) {
      this.accentList.push(hex);
      AppSettingsStore.setStringArray(ACCENT_CUSTOM_LIST_STORAGE, this.accentList);
    }
    this.accentDraft = '';
    this.showAccentSheet = false;
    this.selectCustomAccent(hex);
    FeedbackLogService.recordOperation('UI', `新增自定义主题色 ${normalized}`);
  }

  /** 选中列表里的某个自定义主题色 */
  private selectCustomAccent(hex: string): void {
    this.accentKey = 'custom';
    this.accentCustom = hex;
    AppSettingsStore.setString(ACCENT_KEY_STORAGE, 'custom');
    AppSettingsStore.setString(ACCENT_CUSTOM_STORAGE, hex);
    this.applyAccentNow();
  }

  /** 该自定义色当前是否被选中 */
  private isCustomSelected(hex: string): boolean {
    return this.accentKey === 'custom' && this.accentCustom.toUpperCase() === hex.toUpperCase();
  }

  /**
   * 删除一个自定义主题色。
   * 删掉的正好是当前选中色时，回落到第一个预设色——否则 accentCustom 会指向
   * 一个已经不在列表里的值，界面看上去「选中态凭空消失」。
   */
  private removeCustomAccent(hex: string): void {
    const index = this.accentList.indexOf(hex);
    if (index < 0) {
      return;
    }
    const wasSelected = this.isCustomSelected(hex);
    this.accentList.splice(index, 1);
    AppSettingsStore.setStringArray(ACCENT_CUSTOM_LIST_STORAGE, this.accentList);
    if (wasSelected) {
      this.selectAccentPreset(ACCENT_PRESETS[0].key);
    }
    FeedbackLogService.recordOperation('UI', `删除自定义主题色 #${hex}`);
  }

  /**
   * 主题色实时生效。
   *
   * 把新值写进 AppStorage（accentKey/accentCustom/isDarkMode 已是 @StorageLink，
   * 写入即同步）后，再广播 accentColor；各页面的 @Watch 会重建并读到新色值。
   * 只改 HwColor 属性不会触发刷新，所以必须走这条广播链。
   */
  private applyAccentNow(): void {
    AppStorage.setOrCreate('accentKey', this.accentKey);
    AppStorage.setOrCreate('accentCustom', this.accentCustom);
    AppStorage.setOrCreate('isDarkMode', this.isDarkMode);
    reloadAppTheme();
  }

  /** 当前选中色，用于选择器上的对勾与色块 */
  private currentAccent(): string {
    return resolveAccentColor(this.accentKey, this.accentCustom);
  }

  /** 卡片沾色开关 */
  private setCardTint(enabled: boolean): void {
    AppSettingsStore.setBoolean(CARD_TINT_STORAGE, enabled);
    AppStorage.setOrCreate(CARD_TINT_STORAGE, enabled);
    // 这两个开关只改 token、不改主题色本身，不能指望 accentColor 变化来触发刷新：
    // applyAppTheme 会把卡片底色与页面底色分别发布到 cardSurface / pageBackground，
    // 订阅了这两个键的元素才会跟着更新。
    reloadAppTheme();
    FeedbackLogService.recordOperation('UI', `卡片沾色 ${enabled ? '开' : '关'}`);
  }

  /** 高权限自定义主题色开关 */
  private setCustomAccentFullAccess(enabled: boolean): void {
    AppSettingsStore.setBoolean(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, enabled);
    AppStorage.setOrCreate(CUSTOM_ACCENT_FULL_ACCESS_STORAGE, enabled);
    reloadAppTheme();
    FeedbackLogService.recordOperation('UI', `高权限自定义主题色 ${enabled ? '开' : '关'}`);
  }

  /**
   * 主题色流光开关。
   *
   * 只影响沉浸光感的按压流光/光晕取色，不动任何颜色 token，
   * 所以不需要 reloadAppTheme——重新写一次 pressGlow 订阅键即可：
   * 卡片与圆形按钮都订阅了它，重建时会重新构造带色材质与光晕。
   */
  private setPressGlow(enabled: boolean): void {
    AppSettingsStore.setBoolean(PRESS_GLOW_STORAGE, enabled);
    AppStorage.setOrCreate(PRESS_GLOW_STORAGE, enabled);
    FeedbackLogService.recordOperation('UI', `主题色流光 ${enabled ? '开' : '关'}`);
  }

  /**
   * 切换深色模式。
   *
   * 三态偏好：`system` 跟随系统、`light` / `dark` 固定。
   * 同时要把平台配色一起下发，否则系统控件（弹窗、输入法等）会和自绘颜色一深一浅 ——
   * **跟随系统时必须下发 `COLOR_MODE_NOT_SET`**，下发明确值会被钉死在当前深浅色上。
   */
  private setDarkModePref(pref: string): void {
    this.darkModePref = pref;
    AppSettingsStore.setString(DARK_MODE_PREF_STORAGE, pref);
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, pref);
    // 跟随系统时读一次系统当前值，否则直接用偏好
    const enabled = pref === DARK_MODE_DARK ? true
      : (pref === DARK_MODE_LIGHT ? false : this.systemDarkMode());
    this.applyDarkMode(enabled, pref);
  }

  /** 读系统当前深浅色（偏好为「跟随系统」时用） */
  private systemDarkMode(): boolean {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const config = ctx.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  private applyDarkMode(enabled: boolean, pref: string): void {
    // HwColor 是模块级对象，改属性不会触发任何刷新，所以改完必须广播订阅键。
    // 必须把当前主题色一并传入：背景色是按主题色染的，只传 isDark 会把染色重置回默认。
    applyAppTheme(enabled, this.currentAccent());
    // isDarkMode 是 @StorageLink，赋值会同步写回 AppStorage，
    // 其余 14 个订阅该键的页面随即重建、取到新的 HwColor 值。
    this.isDarkMode = enabled;
    // accentColor 与 isDarkMode 同属一条广播链，一并重发一次
    AppStorage.setOrCreate('accentKey', this.accentKey);
    AppStorage.setOrCreate('accentCustom', this.accentCustom);
    AppStorage.setOrCreate('accentColor', this.accentColor);
    try {
      // 跟随系统必须下发 NOT_SET 把配色权交还系统，否则会被钉死在当前值上
      const mode = pref === DARK_MODE_DARK
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : (pref === DARK_MODE_LIGHT
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      (getContext(this) as common.UIAbilityContext).getApplicationContext().setColorMode(mode);
    } catch (err) {
    }
    FeedbackLogService.recordOperation('UI', `深色模式偏好 ${pref}`);
  }

  /**
   * 一个主题色色块按钮。
   *
   * 与预设色块完全同构（圆点 + 名称），差别只在：
   *   - 自定义色的 `removable` 为 true，右上角叠一个删除角标；
   *   - 角标是 MaterialCard 的**兄弟节点**而不是子节点。ArkUI 的点击会向父级冒泡，
   *     做成子节点的话点删除会连带触发一次选中；做成兄弟节点后两者互不干扰。
   */
  /** 深色模式三态芯片：结构与首页排序芯片一致（自绘底色 + 材质承载 + 文字穿透） */
  @Builder
  darkModeChip(mode: string, label: string) {
    Stack() {
      Row()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(HwRadius.pill)
        .backgroundColor(this.darkModePref === mode
          ? this.accentOrPrimary() : withAlpha(HwColor.textPrimary, 0.06))

      // 小尺寸芯片关掉材质自带投影
      MaterialCardLayer({ layerRadius: HwRadius.pill, layerShadow: false })

      Text(label)
        .fontFamily(this.appFontFamily(label))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontColor(this.darkModePref === mode ? '#FFFFFF' : HwColor.textPrimary)
        .padding({ left: 16, right: 16, top: 7, bottom: 7 })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    .onClick((): void => {
      this.setDarkModePref(mode);
    })
  }

  @Builder
  accentSwatch(key: string, color: string, label: string, selected: boolean, removable: boolean) {
    Stack({ alignContent: Alignment.TopEnd }) {
      MaterialCard({
        cardWidth: 64,
        cardPadding: 8,
        cardRadius: HwRadius.control,
        cardSpace: 6,
        cardHoverEffect: HoverEffect.Highlight,
        cardFocusable: true,
        cardOnClick: (): void => {
          if (removable) {
            this.selectCustomAccent(key);
          } else {
            this.selectAccentPreset(key);
          }
        }
      }) {
        Column({ space: 6 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(34)
              .height(34)
              .fill(color)
            if (selected) {
              // 对勾压在这个色块自己的颜色上：浅色预设（涟漪粉 / 流萤绿）上白勾看不见，
              // 按亮度自动切黑勾
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([onAccentColor(color)])
            }
          }
          .width(34)
          .height(34)

          Text(label)
            .fontFamily(this.appFontFamily(label))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(selected ? HwColor.primary : HwColor.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      if (removable) {
        // 删除角标：半透明黑底保证在浅色/深色材质上都看得清
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(20)
            .height(20)
            .fill('#99000000')
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(11)
            .fontColor([Color.White])
        }
        .width(20)
        .height(20)
        .margin({ top: 4, right: 4 })
        .onClick((): void => {
          this.removeCustomAccent(key);
        })
      }
    }
    .margin({ right: HwSpace.md, bottom: HwSpace.md })
  }

  /** 「新增自定义色」按钮：与色块同尺寸同排版，只把圆点换成加号 */
  @Builder
  addAccentSwatch() {
    MaterialCard({
      cardWidth: 64,
      cardPadding: 8,
      cardRadius: HwRadius.control,
      cardSpace: 6,
      cardHoverEffect: HoverEffect.Highlight,
      cardFocusable: true,
      cardMargin: { right: HwSpace.md, bottom: HwSpace.md },
      cardOnClick: (): void => {
        this.accentDraft = '';
        this.accentError = '';
        this.showAccentSheet = true;
      }
    }) {
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(34)
            .height(34)
            .fill('#14000000')
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([HwColor.textSecondary])
        }
        .width(34)
        .height(34)

        Text('自定义')
          .fontFamily(this.appFontFamily('自定义'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.textSecondary)
          .maxLines(1)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 输入 RRGGBB 的弹窗（底部面板），沿用全站一致的沉浸光感材质 */
  @Builder
  accentInputSheet() {
    MaterialSheetPanel() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text('自定义主题色')
            .fontFamily(this.appFontFamily('自定义主题色'))
            .fontWeight(this.appFontWeight())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(HwColor.textPrimary)
            .layoutWeight(1)
          IconCircleButton({
            symbol: $r('sys.symbol.xmark'),
            buttonSize: 36,
            iconSize: 18,
            onAction: (): void => {
              this.showAccentSheet = false;
            }
          })
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .padding({ left: HwSpace.lg, right: HwSpace.lg })

        Column({ space: HwSpace.md }) {
          Text('输入 6 位十六进制色值（RRGGBB），例如 1A2B3C')
            .fontFamily(this.appFontFamily('输入 6 位十六进制色值（RRGGBB），例如 1A2B3C'))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
            .width('100%')

          Row({ space: HwSpace.sm }) {
            TextInput({ text: this.accentDraft, placeholder: 'RRGGBB' })
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .maxLength(7)
              .backgroundColor(Color.Transparent)
              .padding({ left: HwSpace.md, right: HwSpace.md })
              .fontColor(HwColor.textPrimary)
              .placeholderColor(HwColor.textSecondary)
              .caretColor(this.accentOrPrimary())
              .onChange((value: string) => {
                this.accentDraft = value;
                this.accentError = '';
              })
            // 实时预览：非法时回落到当前主题色，避免闪成透明
            Circle()
              .width(28)
              .height(28)
              .fill(normalizeAccentHex(this.accentDraft).length > 0
                ? normalizeAccentHex(this.accentDraft) : this.currentAccent())
          }
          .width('100%')

          if (this.accentError.length > 0) {
            Text(this.accentError)
              .fontFamily(this.appFontFamily(this.accentError))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(HwColor.danger)
              .width('100%')
          }

          Stack() {
            // 材质承载层：与 MaterialCard 同源的 Toggle 承载。
            // 普通 Button 直接挂 systemMaterial 在真机上不渲染，这里统一走已验证的路径。
            MaterialCardLayer({ layerRadius: HwRadius.pill })
            Button('添加到主题色', { type: ButtonType.Capsule, stateEffect: false })
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor(HwColor.primary)
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.addCustomAccent();
              })
          }
        }
        .width('100%')
        .padding({ left: HwSpace.lg, right: HwSpace.lg, bottom: HwSpace.lg })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private applyFontSizeScale(): void {
    try {
      const appContext = (getContext(this) as common.UIAbilityContext).getApplicationContext();
      let scale: number = 1;
      if (this.fontSizeMode === 'custom') {
        scale = this.fontSizeValue / 16;
      } else {
        scale = uiAppearance.getFontScale();
      }
      appContext.setFontSizeScale(scale);
    } catch (err) {
    }
  }

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }

  fontModeMenu(): MenuElement[] {
    return [
      {
        value: '跟随系统',
        action: () => {
          this.setFontMode('system');
        }
      },
      {
        value: '自定义字体',
        action: () => {
          this.setFontMode('custom');
        }
      }
    ];
  }

  fontFamilyMenu(isEnglish: boolean): MenuElement[] {
    const items: MenuElement[] = [
      {
        value: '跟随系统',
        action: () => {
          this.setFontFamily(isEnglish, 'system');
        }
      }
    ];
    for (let i = 0; i < this.availableFonts.length; i++) {
      const family = this.availableFonts[i];
      items.push({
        value: family,
        action: () => {
          this.setFontFamily(isEnglish, family);
        }
      });
    }
    return items;
  }

  fontSizeModeMenu(): MenuElement[] {
    return [
      {
        value: '跟随系统',
        action: () => {
          this.setFontSizeMode('system');
        }
      },
      {
        value: '自定义',
        action: () => {
          this.setFontSizeMode('custom');
        }
      }
    ];
  }

  fontWeightModeMenu(): MenuElement[] {
    return [
      {
        value: '跟随系统',
        action: () => {
          this.setFontWeightMode('system');
        }
      },
      {
        value: '自定义',
        action: () => {
          this.setFontWeightMode('custom');
        }
      }
    ];
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主题色依赖：切色时让整页重新求值（零尺寸，不参与布局）
      AccentColorSentinel()
      // 自定义主题色输入弹窗：挂在零尺寸 Column 上，不影响布局
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAccentSheet, this.accentInputSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          blurStyle: sheetBlurStyle(),
        })
      AppBackground()
      Column() {
        Scroll() {
          Column({ space: 0 }) {
            Blank().height(56 + this.statusBarHeight)
            Column({ space: 12 }) {
              if (this.backgroundMessage.length > 0) {
                Text(this.backgroundMessage)
                  .fontFamily(this.appFontFamily(this.backgroundMessage))
                  .fontWeight(this.appFontWeight())
                  .fontSize(13)
                  .fontColor(HwColor.primary)
                  .width('100%')
                  .padding({ left: 4, right: 4 })
              }
              if (this.fontMessage.length > 0) {
                Text(this.fontMessage)
                  .fontFamily(this.appFontFamily(this.fontMessage))
                  .fontWeight(this.appFontWeight())
                  .fontSize(13)
                  .fontColor(HwColor.primary)
                  .width('100%')
                  .padding({ left: 4, right: 4 })
              }

              // 深色模式：三态而不是开关。开关一旦拨动就永久生效、再也回不到
              // 「跟随系统」——那正是「深色模式不跟随系统」的原因。
              MaterialCard({
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: HwSpace.md,
                cardAlignItems: ItemAlign.Start
              }) {
                Column({ space: 4 }) {
                  Text('深色模式')
                    .fontFamily(this.appFontFamily('深色模式'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text('选择「跟随系统」时随系统深浅色自动切换')
                    .fontFamily(this.appFontFamily('选择「跟随系统」时随系统深浅色自动切换'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')

                Row({ space: HwSpace.sm }) {
                  this.darkModeChip(DARK_MODE_SYSTEM, '跟随系统')
                  this.darkModeChip(DARK_MODE_LIGHT, '浅色')
                  this.darkModeChip(DARK_MODE_DARK, '深色')
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }

              if (isApi26OrAbove()) {
                MaterialCard({ cardDirection: FlexDirection.Row, cardPadding: HwSpace.lg, cardRadius: HwRadius.card, cardSpace: 12 }) {
                  Column({ space: 4 }) {
                    Text('全局沉浸光感')
                      .fontFamily(this.appFontFamily('全局沉浸光感'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text('开启后使用沉浸光感材质，关闭后回退为毛玻璃效果')
                      .fontFamily(this.appFontFamily('开启后使用沉浸光感材质，关闭后回退为毛玻璃效果'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                    if (this.immersiveLightEnabled) {
                      Text(materialDiagnostics(this.pressGlowEnabled, this.accentColor))
                        .fontFamily('HarmonyOS Sans')
                        .fontWeight(this.appFontWeight())
                        .fontSize(11)
                        .fontColor(HwColor.textSecondary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.immersiveLightEnabled })
                    .selectedColor(this.accentOrPrimary())
                    .onChange((isOn: boolean) => {
                      this.immersiveLightEnabled = isOn;
                      AppSettingsStore.setBoolean('immersiveLightEnabled', isOn);
                    })
                }
            }

            // 主题色：预设 + 自定义 RRGGBB
            MaterialCard({
              cardPadding: HwSpace.lg,
              cardRadius: HwRadius.card,
              cardSpace: HwSpace.md,
              cardAlignItems: ItemAlign.Start
            }) {
              Column({ space: 4 }) {
                Text('主题色')
                  .fontFamily(this.appFontFamily('主题色'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(15)
                  .fontColor(HwColor.textPrimary)
                Text('影响开关、选中态、链接与高亮文字等全局配色')
                  .fontFamily(this.appFontFamily('影响开关、选中态、链接与高亮文字等全局配色'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(12)
                  .fontColor(HwColor.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              // 色块统一走 MaterialCard：和首页卡片同一套沉浸光感载体，
              // 换行排列——预设在前，用户新增的自定义色在后，末尾固定是「新增」按钮。
              Flex({ wrap: FlexWrap.Wrap }) {
                // key 必须带上选中态：ForEach 复用同 key 的项，
                // 键不变就不会重建子节点，对号会一直停在上一个色块上。
                ForEach(ACCENT_PRESETS, (preset: AccentPreset) => {
                  this.accentSwatch(preset.key, preset.value, preset.label,
                    this.accentKey === preset.key, false)
                }, (preset: AccentPreset) =>
                `preset_${preset.key}_${this.accentKey === preset.key ? 1 : 0}`)

                ForEach(this.accentList, (hex: string) => {
                  this.accentSwatch(hex, `#${hex}`, hex, this.isCustomSelected(hex), true)
                }, (hex: string) => `custom_${hex}_${this.isCustomSelected(hex) ? 1 : 0}`)

                this.addAccentSwatch()
              }
              .width('100%')
            }

            // 主题色的延伸选项：两个开关都只改 token，不动主题色本身
            MaterialCard({
              cardPadding: HwSpace.lg,
              cardRadius: HwRadius.card,
              cardSpace: HwSpace.md,
              cardAlignItems: ItemAlign.Start
            }) {
              Row({ space: HwSpace.md }) {
                Column({ space: 4 }) {
                  Text('卡片沾色')
                    .fontFamily(this.appFontFamily('卡片沾色'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text('开启后所有卡片底色混入 10% 主题色')
                    .fontFamily(this.appFontFamily('开启后所有卡片底色混入 10% 主题色'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.cardTintEnabled })
                  .selectedColor(this.accentOrPrimary())
                  .onChange((isOn: boolean): void => {
                    this.setCardTint(isOn);
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Divider()
                .color('#14000000')

              Row({ space: HwSpace.md }) {
                Column({ space: 4 }) {
                  Text('高权限自定义主题色')
                    .fontFamily(this.appFontFamily('高权限自定义主题色'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text('默认只有内置主题色会染到页面背景；开启后自定义颜色也会')
                    .fontFamily(this.appFontFamily('默认只有内置主题色会染到页面背景；开启后自定义颜色也会'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.customAccentFullAccess })
                  .selectedColor(this.accentOrPrimary())
                  .onChange((isOn: boolean): void => {
                    this.setCustomAccentFullAccess(isOn);
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Divider()
                .color('#14000000')

              Row({ space: HwSpace.md }) {
                Column({ space: 4 }) {
                  Text('主题色流光')
                    .fontFamily(this.appFontFamily('主题色流光'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text('按压沉浸光感卡片的流光与光晕改用主题色，光会映照到相邻卡片；关闭后为系统默认白光')
                    .fontFamily(this.appFontFamily('按压沉浸光感卡片的流光与光晕改用主题色，光会映照到相邻卡片；关闭后为系统默认白光'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.pressGlowEnabled })
                  .selectedColor(this.accentOrPrimary())
                  .onChange((isOn: boolean): void => {
                    this.setPressGlow(isOn);
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }

            MaterialCard({ cardDirection: FlexDirection.Row, cardPadding: HwSpace.lg, cardRadius: HwRadius.card, cardSpace: 12 }) {
              Column({ space: 4 }) {
                Text('所有页面卡片从顶部开始排列')
                  .fontFamily(this.appFontFamily('所有页面卡片从顶部开始排列'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(15)
                  .fontColor(HwColor.textPrimary)
                Text('开启后首页、设备详情、信息、我的、房间等页面内容从顶部开始排列')
                  .fontFamily(this.appFontFamily('开启后首页、设备详情、信息、我的、房间等页面内容从顶部开始排列'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(12)
                  .fontColor(HwColor.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.cardsFromTop })
                .selectedColor(this.accentOrPrimary())
                .onChange((isOn: boolean) => {
                  this.cardsFromTop = isOn;
                  AppSettingsStore.setBoolean('cardsFromTop', isOn);
                })
            }

            MaterialCard({
              cardDirection: FlexDirection.Row,
              cardPadding: HwSpace.lg,
              cardRadius: HwRadius.card,
              cardSpace: 12,
              cardMenuItems: this.fontModeMenu()
            }) {
              Column({ space: 4 }) {
                Text('更换字体')
                    .fontFamily(this.appFontFamily('更换字体'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text(this.fontMode === 'custom' ? '自定义字体' : '跟随系统')
                    .fontFamily(this.appFontFamily(this.fontMode === 'custom' ? '自定义字体' : '跟随系统'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([HwColor.textSecondary])
            }

              if (this.fontMode === 'custom') {
                MaterialCard({
                  cardDirection: FlexDirection.Row,
                  cardPadding: HwSpace.lg,
                  cardRadius: HwRadius.card,
                  cardSpace: 12,
                  cardMenuItems: this.fontFamilyMenu(true)
                }) {
                  Column({ space: 4 }) {
                    Text('英文/数字字体')
                      .fontFamily(this.appFontFamily('英文/数字字体'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(this.fontFamilyEn === 'system' ? '跟随系统' : this.fontFamilyEn)
                      .fontFamily(this.appFontFamily(this.fontFamilyEn === 'system' ? '跟随系统' : this.fontFamilyEn))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([HwColor.textSecondary])
                }

                MaterialCard({
                  cardDirection: FlexDirection.Row,
                  cardPadding: HwSpace.lg,
                  cardRadius: HwRadius.card,
                  cardSpace: 12,
                  cardMenuItems: this.fontFamilyMenu(false)
                }) {
                  Column({ space: 4 }) {
                    Text('中文字体')
                      .fontFamily(this.appFontFamily('中文字体'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(this.fontFamilyZh === 'system' ? '跟随系统' : this.fontFamilyZh)
                      .fontFamily(this.appFontFamily(this.fontFamilyZh === 'system' ? '跟随系统' : this.fontFamilyZh))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([HwColor.textSecondary])
                }

                MaterialCard({
                  cardDirection: FlexDirection.Row,
                  cardPadding: HwSpace.lg,
                  cardRadius: HwRadius.card,
                  cardSpace: 12,
                  cardOnClick: () => {
                    this.uploadFont();
                  }
                }) {
                  Column({ space: 4 }) {
                    Text('上传字体')
                      .fontFamily(this.appFontFamily('上传字体'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(`支持 ttf / otf，已上传 ${this.customFonts.length} 个`)
                      .fontFamily(this.appFontFamily(`支持 ttf / otf，已上传 ${this.customFonts.length} 个`))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.plus'))
                    .fontSize(18)
                    .fontColor([HwColor.primary])
                }
              }

              if (this.customFonts.length > 0) {
                MaterialCard({
                  cardDirection: FlexDirection.Row,
                  cardPadding: HwSpace.lg,
                  cardRadius: HwRadius.card,
                  cardSpace: 12,
                  cardOnClick: () => {
                    router.pushUrl({ url: 'pages/FontManagePage' });
                  }
                }) {
                  Column({ space: 4 }) {
                    Text('管理字体')
                      .fontFamily(this.appFontFamily('管理字体'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(`改名、删除已上传的 ${this.customFonts.length} 个字体`)
                      .fontFamily(this.appFontFamily(`改名、删除已上传的 ${this.customFonts.length} 个字体`))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([HwColor.textSecondary])
                }
              }

              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: 12,
                cardMenuItems: this.fontSizeModeMenu()
              }) {
                Column({ space: 4 }) {
                  Text('字体大小')
                    .fontFamily(this.appFontFamily('字体大小'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text(this.fontSizeMode === 'custom' ? `自定义(${this.fontSizeValue})` : '跟随系统')
                    .fontFamily(this.appFontFamily(this.fontSizeMode === 'custom' ? `自定义(${this.fontSizeValue})` : '跟随系统'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([HwColor.textSecondary])
              }

              if (this.fontSizeMode === 'custom') {
                MaterialCard({ cardDirection: FlexDirection.Row, cardPadding: HwSpace.lg, cardRadius: HwRadius.card, cardSpace: 12 }) {
                  Text('字体大小')
                    .fontFamily(this.appFontFamily('字体大小'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Slider({
                    value: this.fontSizeValue,
                    min: 12,
                    max: 28,
                    step: 1,
                    style: SliderStyle.OutSet
                  })
                    .layoutWeight(1)
                    .showSteps(true)
                    .onChange((value: number) => {
                      this.onFontSizeChange(value);
                    })
                  Text(`${this.fontSizeValue}`)
                    .fontFamily(this.appFontFamily(`${this.fontSizeValue}`))
                    .fontWeight(this.appFontWeight())
                    .fontSize(14)
                    .fontColor(HwColor.textSecondary)
                }
              }

              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: 12,
                cardMenuItems: this.fontWeightModeMenu()
              }) {
                Column({ space: 4 }) {
                  Text('字体粗细')
                    .fontFamily(this.appFontFamily('字体粗细'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text(this.fontWeightMode === 'custom' ? `自定义(${this.fontWeightValue})` : '跟随系统')
                    .fontFamily(this.appFontFamily(this.fontWeightMode === 'custom' ? `自定义(${this.fontWeightValue})` : '跟随系统'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([HwColor.textSecondary])
              }

              if (this.fontWeightMode === 'custom') {
                MaterialCard({ cardDirection: FlexDirection.Row, cardPadding: HwSpace.lg, cardRadius: HwRadius.card, cardSpace: 12 }) {
                  Text('字体粗细')
                    .fontFamily(this.appFontFamily('字体粗细'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Slider({
                    value: this.fontWeightValue,
                    min: 100,
                    max: 900,
                    step: 100,
                    style: SliderStyle.OutSet
                  })
                    .layoutWeight(1)
                    .showSteps(true)
                    .onChange((value: number) => {
                      this.onFontWeightChange(value);
                    })
                  Text(`${this.fontWeightValue}`)
                    .fontFamily(this.appFontFamily(`${this.fontWeightValue}`))
                    .fontWeight(this.appFontWeight())
                    .fontSize(14)
                    .fontColor(HwColor.textSecondary)
                }
              }

              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: 12,
                cardEnabled: !this.autoMultiColumn,
                cardOpacity: this.autoMultiColumn ? 0.4 : 1,
                cardOnClick: () => {
                  this.pickBackgroundImage();
                }
              }) {
                Column({ space: 4 }) {
                  Text('更换背景')
                    .fontFamily(this.appFontFamily('更换背景'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(15)
                    .fontColor(HwColor.textPrimary)
                  Text(this.autoMultiColumn
                    ? '自动多栏开启时不可用'
                    : (this.wallpaperImage.length > 0 ? '已设置背景' : '未设置背景'))
                    .fontFamily(this.appFontFamily(this.autoMultiColumn
                    ? '自动多栏开启时不可用'
                    : (this.wallpaperImage.length > 0 ? '已设置背景' : '未设置背景')))
                    .fontWeight(this.appFontWeight())
                    .fontSize(12)
                    .fontColor(HwColor.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.picture'))
                  .fontSize(18)
                  .fontColor([HwColor.textSecondary])
              }

              MaterialCard({
                cardDirection: FlexDirection.Row,
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: 12,
                cardEnabled: !this.autoMultiColumn,
                cardOpacity: this.autoMultiColumn ? 0.4 : 1,
                cardOnClick: () => {
                  this.showClearBackgroundDialog();
                }
              }) {
                Text('清空背景')
                  .fontFamily(this.appFontFamily('清空背景'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(15)
                  .fontColor(HwColor.danger)
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([HwColor.danger])
              }
            }
            .width('100%')
            .padding({ left: HwSpace.lg, right: HwSpace.lg, top: HwSpace.lg, bottom: HwSpace.xl })
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      Row() {
        IconCircleButton({
          symbol: $r('sys.symbol.chevron_left'),
          buttonSize: 40,
          iconSize: 20,
          onAction: () => {
            router.back();
          }
        })
        Text('外观设置')
          .fontFamily(this.appFontFamily('外观设置'))
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
