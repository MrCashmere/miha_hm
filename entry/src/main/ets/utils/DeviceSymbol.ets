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

/**
 * 设备图标映射（全局唯一实现）。
 *
 * 首页与设备管理页曾各写一份，结果同一台设备在两个页面显示不同图标。
 * 这里统一成一份，两页都调用它，保证图标完全对应。
 *
 * 全部使用系统符号（不使用云端下发图）：云端图风格不一（尺寸、留白、配色
 * 都不同），混排会让整列卡片参差不齐。
 */
export function deviceSymbolFor(model: string, name: string): Resource {
  const text = `${model} ${name}`.toLowerCase();
  if (text.includes('airconditioner') || text.includes('air_conditioner') ||
    text.includes('aircondition') || text.includes('空调')) {
    return $r('sys.symbol.snowflake');
  }
  if (text.includes('curtain') || text.includes('窗帘') || text.includes('motor')) {
    return $r('sys.symbol.rectangle_split_2x1');
  }
  if (isLightDeviceText(text)) {
    return $r('sys.symbol.lightbulb');
  }
  if (text.includes('humidifier') || text.includes('humid') || text.includes('加湿')) {
    return $r('sys.symbol.drop');
  }
  if (text.includes('purifier') || text.includes('airfresh') || text.includes('fresh') ||
    text.includes('净化') || text.includes('fan') || text.includes('风扇')) {
    return $r('sys.symbol.wind');
  }
  if (text.includes('camera') || text.includes('摄像') || text.includes('doorbell') ||
    text.includes('tv') || text.includes('projector')) {
    return $r('sys.symbol.video');
  }
  if (text.includes('router') || text.includes('路由') || text.includes('wifi') ||
    text.includes('.ap.')) {
    return $r('sys.symbol.wifi');
  }
  if (text.includes('socket') || text.includes('plug') || text.includes('插座') ||
    text.includes('switch')) {
    return $r('sys.symbol.power');
  }
  if (text.includes('vacuum') || text.includes('robot') || text.includes('scavenger') ||
    text.includes('sensor') || text.includes('传感') || text.includes('gateway')) {
    return $r('sys.symbol.bolt');
  }
  return $r('sys.symbol.gearshape');
}

/** 灯具判定：一键关灯与图标映射共用同一套关键字 */
export function isLightDeviceText(text: string): boolean {
  const lower = text.toLowerCase();
  return lower.includes('lamp') || lower.includes('light') || lower.includes('yeelight') ||
    lower.includes('bulb') || lower.includes('灯');
}
