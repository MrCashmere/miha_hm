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

import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸光感（systemMaterial）实现说明
 * ==================================
 *
 * 一、应用级状态
 * uiMaterial.getMaterialInfo().state 读的是 entry 模块 module.json5 里的 metadata
 * `ohos.arkui.UIMaterial.state`：
 *   - default：普通组件可主动设置材质
 *   - enable ：更多系统组件自动使用材质，普通组件仍可主动设置
 *   - disable：关闭整个应用的沉浸材质，**主动设置的材质也一并失效**
 * 本工程显式配置为 enable。若这里读到 DISABLE，材质不会渲染——这不是代码能绕过的，
 * 必须先改 module.json5 并重新构建安装。
 *
 * 二、生效范围（targetSdkVersion >= 26 时的系统行为变更）
 * 按钮与选择类组件（Slider / Toggle / Select）与弹窗类，仍可在页面内全部区域生效；
 * 其他组件（Column / Row 等）只在 Navigation / NavDestination 标题栏，
 * 或 BarPosition.End 的底部 TabBar 中生效。
 * 因此卡片不能把 systemMaterial 直接挂在 Column/Row 上，必须由 Toggle 承载。
 *
 * 三、历史坑
 * 旧实现把「state === DISABLE」当成「本应用不能渲染」，直接返回 Material.empty，
 * 又把这个状态用作降级条件——等于应用自己把光感关掉，是自锁。现已全部移除：
 * 状态只用于诊断展示，材质只要构造成功就下发，画不画由系统按上述规则决定。
 */

/**
 * 当前运行系统 API 是否 >= 26。
 * API >= 26：使用沉浸光感（systemMaterial）；
 * API < 26：回退到毛玻璃样式（backgroundBlurStyle(Thin) / blurStyle: Thin）。
 */
export function isApi26OrAbove(): boolean {
  try {
    return deviceInfo.sdkApiVersion >= 26;
  } catch (err) {
    return false;
  }
}

/**
 * 系统材质状态：只读一次并缓存。它是安装包里写死的配置，
 * 运行期不会变化，反复查询没有意义。
 */
let materialStateCache: uiMaterial.MaterialState | null = null;
let materialStateResolved: boolean = false;
let materialStateError: string = '';

export function systemMaterialState(): uiMaterial.MaterialState | null {
  if (!materialStateResolved) {
    materialStateResolved = true;
    try {
      materialStateCache = uiMaterial.getMaterialInfo().state;
    } catch (err) {
      materialStateCache = null;
      materialStateError = String((err as Error)?.message ?? err);
    }
  }
  return materialStateCache;
}

/** getMaterialInfo() 调用失败时的错误信息，空串表示没失败过。 */
export function systemMaterialError(): string {
  systemMaterialState();
  return materialStateError;
}

/**
 * 系统材质总开关是否为 DISABLE。
 *
 * **仅用于诊断展示，不用于降级判断。**
 * disable 时确实画不出材质，但那是配置问题（要改 module.json5 重装），
 * 而不是应用该主动放弃渲染的理由。
 */
export function isSystemMaterialDisabled(): boolean {
  return systemMaterialState() === uiMaterial.MaterialState.DISABLE;
}

let materialError: string = '';
let materialCache: uiMaterial.Material | null = null;
let materialResolved: boolean = false;
let interactiveMaterialCache: uiMaterial.Material | null = null;
let interactiveMaterialResolved: boolean = false;
let flatMaterialCache: uiMaterial.Material | null = null;
let flatMaterialResolved: boolean = false;

/**
 * 材质厚薄档位，集中一处便于按真机观感调档。
 *
 * **必须惰性求值，不能写成模块级常量。**
 * 曾经写的是 `export const MATERIAL_STYLE = uiMaterial.ImmersiveStyle.THIN`，
 * 这行会在**模块加载期**就解引用 `uiMaterial`。而 uiMaterial 是 API 26 才有的接口
 * （SDK 标注 `@since 26.0.0`），在 API 24 设备上 `uiMaterial.ImmersiveStyle` 是 undefined，
 * 取 `.THIN` 抛出的 TypeError 发生在**任何 try/catch 之外**，
 * 结果不只是没有光感，而是整个模块加载失败、**应用启动即闪退**。
 * 本文件其它部分都遵守了「不在模块加载期构造」的原则，唯独这里漏了。
 *
 * **调档只用类型断言，不要写类型标注**：本工程 compileSdkVersion 是 26，
 * 能用全部档位；而一旦写成 `const X: uiMaterial.ImmersiveStyle = ...` 这种
 * 带类型标注的写法，低版本 SDK 上会出现类型不相容的编译错误。
 */
function materialStyle(): uiMaterial.ImmersiveStyle {
  return uiMaterial.ImmersiveStyle.THIN as uiMaterial.ImmersiveStyle;
}

/**
 * 材质构造。
 *
 * 官方《沉浸光感常见问题》要点（都踩过坑）：
 *   - 「沉浸光感的视觉层级位于组件的 backgroundColor、backgroundBlurStyle 等
 *     属性之下」→ 不透明背景色会盖住材质，承载组件必须显式设 Color.Transparent；
 *   - 「将 systemMaterial 放在其他样式属性（如背景色、边框、阴影等）之后设置」；
 *   - materialColor 必须带透明度，纯不透明色会完全遮挡材质滤镜；
 *   - applyShadow 默认 true，优先于通用属性 shadow。
 *
 * 刻意**不传 materialColor**：材质的通透感来自它自身的滤镜，
 * 额外赋色会把卡片叠成灰色。
 *
 * 注意 lightEffect 的取舍：实测（HarmonyOS 7.0.0.105 / API 26）单独给按钮材质
 * 加 interactive + lightEffect 会让材质**完全不渲染**，所以按钮默认走静态材质，
 * 由调用方通过按钮组件的 `buttonInteractive` 参数按设备情况开启。
 *
 * @param interactive 是否开启交互形变 + 手指流光（HdsTab 那种灵动反馈）
 */
function buildImmersiveMaterial(interactive: boolean = false,
                               withShadow: boolean = true): uiMaterial.Material | null {
  try {
    if (interactive) {
      // 《沉浸式系统材质视效》：interactive 开启按压弹性形变；
      // lightEffect 传入有效对象即启用流光跟随，color 缺省为 Color.White。
      return new uiMaterial.ImmersiveMaterial({
        style: materialStyle(),
        interactive: true,
        lightEffect: {}
      });
    }
    if (!withShadow) {
      // applyShadow 默认 true，材质会自带一层投影。小尺寸芯片上这层投影
      // 会显得像「背后顶了一层影子」，所以单独开一档不带阴影的。
      return new uiMaterial.ImmersiveMaterial({
        style: materialStyle(),
        applyShadow: false
      });
    }
    // 静态材质只传 style，避免可选字段影响材质本身。
    return new uiMaterial.ImmersiveMaterial({
      style: materialStyle()
    });
  } catch (err) {
    materialError = String((err as Error)?.message ?? err);
    return null;
  }
}

/**
 * 沉浸光感材质（惰性构造）。
 *
 * 不在模块加载期构造：那时 getMaterialInfo() 未必就绪，构造异常也无从反馈。
 * 构造失败返回 null，调用方统一降级为毛玻璃——**绝不返回 Material.empty**，
 * 那等于「显式不画」，会把失败伪装成静默失效。
 *
 * @param interactive 传 true 取「可交互」材质（按压形变 + 流光），按钮类用
 */
export function getImmersiveMaterial(interactive: boolean = false,
                                     withShadow: boolean = true): uiMaterial.Material | null {
  if (!isApi26OrAbove()) {
    return null;
  }
  if (!withShadow && !interactive) {
    if (!flatMaterialResolved) {
      flatMaterialResolved = true;
      flatMaterialCache = buildImmersiveMaterial(false, false);
    }
    return flatMaterialCache;
  }
  if (interactive) {
    if (!interactiveMaterialResolved) {
      interactiveMaterialResolved = true;
      interactiveMaterialCache = buildImmersiveMaterial(true);
    }
    return interactiveMaterialCache;
  }
  if (!materialResolved) {
    materialResolved = true;
    materialCache = buildImmersiveMaterial();
  }
  return materialCache;
}

/** 材质构造失败时的错误信息，空串表示没失败过。 */
export function immersiveMaterialError(): string {
  return materialError;
}

function immersiveEnabled(): boolean {
  try {
    const enabled = AppStorage.get<boolean>('immersiveLightEnabled');
    return enabled !== false;
  } catch (err) {
    return true;
  }
}

/**
 * 应用侧沉浸光感是否应当启用：API >= 26、应用内开关开启、材质构造成功。
 * 刻意不看 MaterialState——它曾导致应用自己把光感降级掉（自锁）。
 */
export function immersiveMaterialActive(): boolean {
  return isApi26OrAbove() && immersiveEnabled() && getImmersiveMaterial() !== null;
}

/**
 * 沉浸光感修饰器。
 *
 * 注意：受生效范围约束，把 systemMaterial 直接挂在 Column/Row 卡片上**不会生效**，
 * 卡片请使用 MaterialCard（内部由 Toggle 承载）。此修饰器保留给
 * 标题栏、底部 TabBar、弹窗，以及确实能生效的轻量节点。
 */
export class ImmersiveMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    const material: uiMaterial.Material | null = getImmersiveMaterial();
    if (immersiveEnabled() && material !== null) {
      instance.systemMaterial(material);
    } else {
      instance.backgroundBlurStyle(BlurStyle.Thin);
    }
  }
}

export const immersiveMaterialModifier: ImmersiveMaterialModifier = new ImmersiveMaterialModifier();

/**
 * 旧毛玻璃修饰器（API 24 渲染效果）。
 */
export class LegacyMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundBlurStyle(BlurStyle.Thin);
  }
}

export const legacyMaterialModifier: LegacyMaterialModifier = new LegacyMaterialModifier();

export function sheetSystemMaterial(): uiMaterial.Material | undefined {
  const material: uiMaterial.Material | null = getImmersiveMaterial();
  if (immersiveEnabled() && material !== null) {
    return material;
  }
  return undefined;
}

export function sheetBlurStyle(): BlurStyle | undefined {
  return immersiveMaterialActive() ? undefined : BlurStyle.Thin;
}

/**
 * 把沉浸光感材质挂在承载组件上。
 *
 * 官方文档《组件适配沉浸光感》要点：
 *   - 按钮与选择类组件（Button / Select / Toggle / Slider / ChipGroup /
 *     SegmentButton）可在页面内**全部区域**生效；
 *   - 其余组件（布局容器、滚动容器等）的通用属性 systemMaterial **只在
 *     Navigation / NavDestination 标题栏，或 barPosition 为 BarPosition.End
 *     的底部 TabBar 中生效**，内容区设置无效。
 *
 * 各 ToggleType 的差异（官方原文）：
 *   - Checkbox：当前未适配沉浸光感效果，设置后无效果；
 *   - Switch  ：材质参数仅作为开启标记，实际使用组件内部预设视觉参数，
 *               主要影响滑块大小/样式/阴影；
 *   - Button  ：效果与 Button 组件设置沉浸光感相同，影响背景色、边框、阴影。
 *
 * 因此卡片承载层用 ToggleType.Button（见 MaterialCard），
 * 圆形按钮也用 ToggleType.Button 作底衬（见 IconCircleButton）——
 * 真机实测普通 Button 挂 systemMaterial 不渲染。
 *
 * @param instance 承载组件的属性实例
 * @param fallbackBlur 材质不可用时是否补一层毛玻璃兜底
 * @param interactive 是否启用交互形变 + 手指流光（HdsTab 那种灵动反馈）。
 *                    注意：**流光只在组件自身收到触摸时触发**，启用时承载层
 *                    不能再设 hitTestBehavior(HitTestMode.None)。
 */
export function applyMaterialCarrier(
  instance: CommonAttribute,
  fallbackBlur: boolean = true,
  interactive: boolean = false,
  withShadow: boolean = true
): void {
  const material: uiMaterial.Material | null = getImmersiveMaterial(interactive, withShadow);
  if (immersiveEnabled() && material !== null) {
    instance.systemMaterial(material);
  } else if (fallbackBlur) {
    instance.backgroundBlurStyle(BlurStyle.Thin);
  }
}

/**
 * 给文本按钮（`Button('确定')` 这类胶囊按钮）挂上沉浸光感。
 *
 * **必须用静态材质。** 这里此前传的是 `interactive: true`，即
 * `ImmersiveMaterial({ style, interactive: true, lightEffect: {} })`——
 * 而 `buildImmersiveMaterial` 上方的实测结论写得很清楚：这个组合在
 * HarmonyOS 7.0.0.105 / API 26 上会让材质**完全不渲染**。
 * 卡片走的是静态材质，所以卡片有光感、按钮没有，长期表现为「按钮就是不发光」。
 *
 * @param instance 按钮的属性实例
 * @param fallbackBlur 材质不可用时是否补一层毛玻璃兜底
 */
export function applyButtonMaterial(instance: CommonAttribute, fallbackBlur: boolean = true): void {
  applyMaterialCarrier(instance, fallbackBlur, false);
}

/**
 * 承载层是否处于「已挂上材质」状态，用于诊断与开发期排查。
 */
export function materialCarrierActive(): boolean {
  return immersiveMaterialActive();
}

/**
 * 诊断文案：把沉浸光感的各段判定条件摊开，便于真机排查「为什么没生效」。
 */
export function materialDiagnostics(): string {
  const api = deviceInfo.sdkApiVersion;
  const state = systemMaterialState();
  const stateText = state === null
    ? 'null(接口不可用)'
    : (state === uiMaterial.MaterialState.DISABLE ? 'DISABLE(全局关闭)' : '非DISABLE');
  const material = getImmersiveMaterial();
  const materialText = material === null ? '构造失败' : '已构造';
  const err = systemMaterialError().length > 0 ? systemMaterialError() : immersiveMaterialError();
  const errText = err.length > 0 ? ` 错误=${err}` : '';
  return `API=${api} 材质=${materialText} 状态=${stateText} 开关=${immersiveEnabled() ? '开' : '关'} 承载=${materialCarrierActive() ? '下发材质' : '降级毛玻璃'}${errText}`;
}
