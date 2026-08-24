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
 * 当前运行系统 API 是否 >= 26。
 * API >= 26：使用沉浸光感（systemMaterial）；
 * API < 26：回退到 main 分支的毛玻璃样式（backgroundBlurStyle(Thin) / blurStyle: Thin）。
 */
export function isApi26OrAbove(): boolean {
  try {
    return deviceInfo.sdkApiVersion >= 26;
  } catch (err) {
    return false;
  }
}

function buildImmersiveMaterial(): uiMaterial.Material | null {
  try {
    const instance = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      applyShadow: true,
      lightEffect: { color: Color.White }
    });
    if (uiMaterial.getMaterialInfo().state === uiMaterial.MaterialState.DISABLE) {
      return uiMaterial.Material.empty;
    }
    return instance;
  } catch (err) {
    try {
      return uiMaterial.Material.empty;
    } catch (err2) {
      return null;
    }
  }
}

/**
 * 沉浸光感材质。uiMaterial 为 API 26 新增，低版本设备上为 null，
 * 调用方必须通过 isApi26OrAbove() / MaterialFallbackModifier 降级。
 */
export const immersiveLightMaterial: uiMaterial.Material | null =
  isApi26OrAbove() ? buildImmersiveMaterial() : null;

function immersiveEnabled(): boolean {
  try {
    const enabled = AppStorage.get<boolean>('immersiveLightEnabled');
    return enabled !== false;
  } catch (err) {
    return true;
  }
}

/**
 * 沉浸光感修饰器：API >= 26 且全局开关开启时应用 systemMaterial，
 * 否则回退到旧毛玻璃。与 legacyMaterialModifier 配合，通过切换实例实现实时生效。
 */
export class ImmersiveMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    if (isApi26OrAbove() && immersiveEnabled() && immersiveLightMaterial !== null) {
      instance.systemMaterial(immersiveLightMaterial);
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
  if (isApi26OrAbove() && immersiveEnabled() && immersiveLightMaterial !== null) {
    return immersiveLightMaterial;
  }
  return undefined;
}

export function sheetBlurStyle(): BlurStyle | undefined {
  return isApi26OrAbove() && immersiveEnabled() ? undefined : BlurStyle.Thin;
}
