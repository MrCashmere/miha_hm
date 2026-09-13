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

import { router, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HwColor, reloadAppTheme, resolvePageBackground } from '../utils/DesignTokens';
import { IconCircleButton } from '../components/IconCircleButton';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';

const MIN_CROP_WIDTH: number = 80;

/**
 * 解码长边上限。
 *
 * 相册里的原图动辄上亿像素（实测遇到过 15011×11258 ≈ 1.69 亿），
 * 按原始尺寸解码要么直接失败、要么把内存吃光——表现为**预览一片空白**，
 * 因为 getImageInfo() 只读文件头，尺寸看起来完全正常，很容易误判成路径问题。
 * 背景最终只需要屏幕分辨率，所以解码时先降到长边 2560 再处理。
 */
const MAX_DECODE_LONG_SIDE: number = 2560;

@Entry
@Component
struct BackgroundCropPage {
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
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  /** 深浅色。原先底色写死 HwColor.background，改用 resolvePageBackground 后必须订阅该键 */
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 页面底色（由 applyAppTheme 发布）。订阅它而不是读 HwColor 属性，见 docs/ThemeColor.md §7.8 */
  @StorageProp('pageBackground') pageBackground: string = '';
  /**
   * 窗口尺寸（vp），由 EntryAbility 从 windowRect 写入并随 windowSizeChange 更新。
   *
   * 裁剪比例必须用**窗口**而不是物理屏幕：折叠屏展开/折叠、模拟器、PC 分屏下，
   * 窗口尺寸与屏幕尺寸并不一致，用屏幕比例裁出来的图放到只占窗口大小的背景上
   * 就会被 Cover 再裁一刀，出现「框住的区域没被保住」。
   */
  @StorageProp('screenWidthVp') @Watch('onWindowSizeChanged') screenWidthVp: number = 0;
  @StorageProp('screenHeightVp') @Watch('onWindowSizeChanged') screenHeightVp: number = 0;
  @State sourceUri: string = '';
  @State errorMessage: string = '';
  @State saving: boolean = false;
  @State imageWidth: number = 0;
  @State imageHeight: number = 0;
  /**
   * 降采样后的解码尺寸：预览与裁剪都基于它，保证「所见即所裁」。
   * 必须是 @State —— 预览图的 sourceSize 依赖它，普通字段变化不会让 Image 重新求值。
   */
  @State decodedWidth: number = 0;
  @State decodedHeight: number = 0;
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  @State cropX: number = 0;
  @State cropY: number = 0;
  @State cropWidth: number = 0;
  private cropAspectRatio: number = 1;
  private displayScale: number = 1;
  private displayX: number = 0;
  private displayY: number = 0;
  private displayWidth: number = 0;
  private displayHeight: number = 0;
  private workingUri: string = '';
  private uriSourceValid: boolean = false;
  private resolvedFd: number = -1;
  private gestureStartX: number = 0;
  private gestureStartY: number = 0;
  private gestureStartWidth: number = 0;

  /** 主题色变了：HwColor 是模块级对象，改属性不会触发刷新，靠这里重建页面 */
  onAccentColorChanged(): void {
    reloadAppTheme();
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('背景裁剪页');
    const params = router.getParams() as Record<string, Object>;
    this.sourceUri = String(params['sourceUri'] ?? '');
    this.resolveAspectRatio();
    this.resolveImageInfo();
  }

  /**
   * 解析裁剪框的长宽比。
   *
   * 优先用窗口尺寸；拿不到时退回物理屏幕。宽高比与单位无关，
   * 所以 vp 和 px 混用不影响结果，关键是**尺寸来源**要和背景实际覆盖的区域一致。
   */
  private resolveAspectRatio(): void {
    let displayWidth = 0;
    let displayHeight = 0;
    try {
      const screen = display.getDefaultDisplaySync();
      displayWidth = screen.width;
      displayHeight = screen.height;
    } catch (err) {
      displayWidth = -1;
      displayHeight = -1;
    }
    if (this.screenWidthVp > 0 && this.screenHeightVp > 0) {
      this.cropAspectRatio = this.screenWidthVp / this.screenHeightVp;
    } else if (displayWidth > 0 && displayHeight > 0) {
      this.cropAspectRatio = displayWidth / displayHeight;
    }
    // 诊断日志：折叠屏/模拟器上窗口与屏幕尺寸可能不一致，出问题时这行能直接定位
    Logger.info('crop ratio=%{public}s window=%{public}sx%{public}s display=%{public}sx%{public}s',
      this.cropAspectRatio.toFixed(4),
      this.screenWidthVp.toFixed(1), this.screenHeightVp.toFixed(1),
      `${displayWidth}`, `${displayHeight}`);
  }

  /**
   * 窗口尺寸变化（折叠屏展开/折叠、旋转、PC 拖拽分屏）时重算比例并复位裁剪框。
   * resetCrop 会写入 @State 字段，从而触发重绘——@Watch 本身只负责调用回调，
   * 光改 cropAspectRatio 这个普通字段是不会让界面更新的。
   */
  onWindowSizeChanged(): void {
    this.resolveAspectRatio();
    this.resetCrop();
  }

  private async resolveImageInfo(): Promise<void> {
    const candidates: string[] = [];
    if (this.sourceUri.startsWith('file://')) {
      candidates.push(this.sourceUri, this.sourceUri.slice('file://'.length));
    } else {
      candidates.push(this.sourceUri);
    }
    for (let i = 0; i < candidates.length; i++) {
      try {
        const source = image.createImageSource(candidates[i]);
        if (source === undefined) {
          continue;
        }
        const info = await source.getImageInfo();
        this.imageWidth = info.size.width;
        this.imageHeight = info.size.height;
        this.computeDecodedSize();
        this.workingUri = candidates[i];
        this.uriSourceValid = true;
        source.release();
        this.onImageInfoReady();
        return;
      } catch (err) {
      }
    }
    try {
      const file = await fs.open(this.sourceUri, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      if (source === undefined) {
        await fs.close(file.fd);
      } else {
        const info = await source.getImageInfo();
        this.imageWidth = info.size.width;
        this.imageHeight = info.size.height;
        this.computeDecodedSize();
        this.resolvedFd = file.fd;
        this.uriSourceValid = false;
        source.release();
        this.onImageInfoReady();
        return;
      }
    } catch (err) {
    }
    this.errorMessage = '无法读取图片，请重新选择';
  }

  /** 按长边上限等比算出解码尺寸；原图不超限时就是原尺寸 */
  private computeDecodedSize(): void {
    const longSide = Math.max(this.imageWidth, this.imageHeight);
    if (longSide <= MAX_DECODE_LONG_SIDE) {
      this.decodedWidth = this.imageWidth;
      this.decodedHeight = this.imageHeight;
      return;
    }
    const ratio = MAX_DECODE_LONG_SIDE / longSide;
    this.decodedWidth = Math.max(1, Math.round(this.imageWidth * ratio));
    this.decodedHeight = Math.max(1, Math.round(this.imageHeight * ratio));
    Logger.info('oversized image %{public}dx%{public}d downscaled to %{public}dx%{public}d',
      this.imageWidth, this.imageHeight, this.decodedWidth, this.decodedHeight);
  }

  /**
   * 预览用的 URI。
   * resolveImageInfo 可能只验证通过 fd 那条路（uriSourceValid=false），
   * 那种情况下用原始 sourceUri 交给 Image 组件同样读不出来，得用验证过的那一个。
   */
  private previewUri(): string {
    return this.uriSourceValid && this.workingUri.length > 0 ? this.workingUri : this.sourceUri;
  }

  private openCropSource(): image.ImageSource {
    if (this.uriSourceValid && this.workingUri.length > 0) {
      const source = image.createImageSource(this.workingUri);
      if (source !== undefined) {
        return source;
      }
    }
    return image.createImageSource(this.resolvedFd);
  }

  private async closeResolvedSource(): Promise<void> {
    if (this.resolvedFd >= 0) {
      try {
        await fs.close(this.resolvedFd);
      } catch (err) {
      }
      this.resolvedFd = -1;
    }
  }

  private async cleanupOldBackgrounds(context: common.UIAbilityContext, keepPath: string): Promise<void> {
    try {
      const names = await fs.listFile(context.filesDir);
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (!name.startsWith('background_image')) {
          continue;
        }
        const fullPath = `${context.filesDir}/${name}`;
        if (fullPath === keepPath) {
          continue;
        }
        try {
          await fs.unlink(fullPath);
        } catch (err) {
        }
      }
    } catch (err) {
    }
  }

  private cropHeight(): number {
    return this.cropWidth / this.cropAspectRatio;
  }

  private resetCrop(): void {
    if (this.decodedWidth <= 0 || this.decodedHeight <= 0 ||
      this.areaWidth <= 0 || this.areaHeight <= 0) {
      return;
    }
    // 用解码尺寸而非原图尺寸：预览就是按这个尺寸解码出来的，
    // 两边用同一套坐标，「框住哪里就裁哪里」才成立。
    this.displayScale = Math.min(this.areaWidth / this.decodedWidth,
      this.areaHeight / this.decodedHeight);
    this.displayWidth = this.decodedWidth * this.displayScale;
    this.displayHeight = this.decodedHeight * this.displayScale;
    this.displayX = (this.areaWidth - this.displayWidth) / 2;
    this.displayY = (this.areaHeight - this.displayHeight) / 2;
    const maxWidth = Math.min(this.displayWidth, this.displayHeight * this.cropAspectRatio);
    this.cropWidth = Math.max(MIN_CROP_WIDTH, maxWidth);
    this.cropX = this.displayX + (this.displayWidth - this.cropWidth) / 2;
    this.cropY = this.displayY +
      (this.displayHeight - this.cropWidth / this.cropAspectRatio) / 2;
  }

  private maxCropWidth(): number {
    return Math.min(this.displayWidth, this.displayHeight * this.cropAspectRatio);
  }

  private onImageInfoReady(): void {
    if (this.areaWidth > 0 && this.areaHeight > 0) {
      this.resetCrop();
    }
  }

  onPreviewAreaChange(oldValue: Area, newValue: Area): void {
    const rawWidth = newValue.width;
    const rawHeight = newValue.height;
    const width = typeof rawWidth === 'number' ? rawWidth : parseFloat(String(rawWidth));
    const height = typeof rawHeight === 'number' ? rawHeight : parseFloat(String(rawHeight));
    if (Number.isNaN(width) || Number.isNaN(height) || width <= 0 || height <= 0) {
      return;
    }
    this.areaWidth = width;
    this.areaHeight = height;
    this.resetCrop();
  }

  onCropBoxGestureStart(event: GestureEvent): void {
    this.gestureStartX = this.cropX;
    this.gestureStartY = this.cropY;
  }

  onCropBoxGestureUpdate(event: GestureEvent): void {
    const maxX = this.displayX + this.displayWidth - this.cropWidth;
    const maxY = this.displayY + this.displayHeight - this.cropHeight();
    this.cropX = Math.min(Math.max(this.gestureStartX + event.offsetX, this.displayX),
      Math.max(maxX, this.displayX));
    this.cropY = Math.min(Math.max(this.gestureStartY + event.offsetY, this.displayY),
      Math.max(maxY, this.displayY));
  }

  onHandleGestureStart(event: GestureEvent): void {
    this.gestureStartWidth = this.cropWidth;
  }

  onHandleGestureUpdate(event: GestureEvent): void {
    const maxWidth = this.maxCropWidth();
    const minWidth = Math.min(MIN_CROP_WIDTH, maxWidth);
    this.cropWidth = Math.min(Math.max(this.gestureStartWidth + event.offsetX, minWidth),
      maxWidth);
    const cropHeight = this.cropHeight();
    if (this.cropX + this.cropWidth > this.displayX + this.displayWidth) {
      this.cropX = this.displayX + this.displayWidth - this.cropWidth;
    }
    if (this.cropY + cropHeight > this.displayY + this.displayHeight) {
      this.cropY = this.displayY + this.displayHeight - cropHeight;
    }
  }

  private async confirmCrop(): Promise<void> {
    if (this.saving || this.cropWidth <= 0) {
      return;
    }
    this.saving = true;
    this.errorMessage = '';
    try {
      const scale = this.displayScale;
      const ix = Math.max(0, Math.round((this.cropX - this.displayX) / scale));
      const iy = Math.max(0, Math.round((this.cropY - this.displayY) / scale));
      const iw = Math.max(1, Math.min(Math.round(this.cropWidth / scale),
        this.decodedWidth - ix));
      const ih = Math.max(1, Math.min(Math.round(this.cropHeight() / scale),
        this.decodedHeight - iy));
      const source = this.openCropSource();
      if (source === undefined) {
        throw new Error('无法读取图片');
      }
      // 关键：按降采样后的尺寸解码，不要用原始尺寸。
      // 1.69 亿像素的图按原尺寸解码会失败或耗尽内存，而且背景本来也不需要那么大。
      const decodeSize: image.Size = { width: this.decodedWidth, height: this.decodedHeight };
      const decodeOptions: image.DecodingOptions = { desiredSize: decodeSize };
      const pixelMap = await source.createPixelMap(decodeOptions);
      const cropSize: image.Size = { width: iw, height: ih };
      const cropRegion: image.Region = { size: cropSize, x: ix, y: iy };
      await pixelMap.crop(cropRegion);
      const packer = image.createImagePacker();
      const data = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 95
      });
      const context = getContext(this) as common.UIAbilityContext;
      const destPath = `${context.filesDir}/background_image_${Date.now()}`;
      const file = await fs.open(destPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);
      await this.cleanupOldBackgrounds(context, destPath);
      const uri = `file://${destPath}`;
      AppSettingsStore.setString('backgroundImage', uri);
      AppStorage.setOrCreate('backgroundImage', uri);
      await this.closeResolvedSource();
      router.back();
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '裁剪保存失败';
      await this.closeResolvedSource();
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        IconCircleButton({
          symbol: $r('sys.symbol.chevron_left'),
          onAction: () => {
            router.back();
          }
        })
        Text('裁剪背景')
          .fontFamily(this.appFontFamily('裁剪背景'))
          .fontWeight(this.appFontWeight())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(HwColor.textPrimary)
          .layoutWeight(1)
        Text(this.saving ? '保存中...' : '完成')
          .fontFamily(this.appFontFamily(this.saving ? '保存中...' : '完成'))
          .fontWeight(this.appFontWeight())
          .fontSize(16)
          .fontColor(this.saving ? HwColor.textSecondary : HwColor.primary)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.confirmCrop();
          })
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .backgroundEffect({ radius: 12, color: '#66FFFFFF' })

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontFamily(this.appFontFamily(this.errorMessage))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(HwColor.danger)
          .padding(8)
      }

      Stack({ alignContent: Alignment.TopStart }) {
        // 等解码尺寸就绪再渲染：首帧 decodedWidth 还是 0，此时给 sourceSize 传 0
        // 会让解码器无从下手，图照样出不来。
        if (this.decodedWidth > 0 && this.decodedHeight > 0) {
          // sourceSize 让解码器直接按目标尺寸解码，避免为了显示而把上亿像素整张解进内存
          Image(this.previewUri())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .sourceSize({ width: this.decodedWidth, height: this.decodedHeight })
        }

        Column()
          .width('100%')
          .height(this.cropY)
          .backgroundColor('#66000000')

        Column()
          .width('100%')
          .height(Math.max(0, this.areaHeight - this.cropY - this.cropHeight()))
          .position({ x: 0, y: this.cropY + this.cropHeight() })
          .backgroundColor('#66000000')

        Column()
          .width(this.cropX)
          .height(this.cropHeight())
          .position({ x: 0, y: this.cropY })
          .backgroundColor('#66000000')

        Column()
          .width(Math.max(0, this.areaWidth - this.cropX - this.cropWidth))
          .height(this.cropHeight())
          .position({ x: this.cropX + this.cropWidth, y: this.cropY })
          .backgroundColor('#66000000')

        Column()
          .width(this.cropWidth)
          .height(this.cropHeight())
          .position({ x: this.cropX, y: this.cropY })
          .border({ width: 2, color: Color.White })
          .gesture(
            PanGesture({ fingers: 1, distance: 1 })
              .onActionStart((event: GestureEvent) => {
                this.onCropBoxGestureStart(event);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.onCropBoxGestureUpdate(event);
              })
          )

        Column()
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(Color.White)
          .border({ width: 3, color: HwColor.primary })
          .position({
            x: this.cropX + this.cropWidth - 16,
            y: this.cropY + this.cropHeight() - 16
          })
          .gesture(
            PanGesture({ fingers: 1, distance: 1 })
              .onActionStart((event: GestureEvent) => {
                this.onHandleGestureStart(event);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.onHandleGestureUpdate(event);
              })
          )
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.onPreviewAreaChange(oldValue, newValue);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      router.back();
    })
  }
}
