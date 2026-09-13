/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 鸿米家（miha）项目开发者
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * 按压流光的「光源广播」。
 *
 * 为什么需要它：光要照到**别的卡片**上，而卡片之间互相看不见。
 * 被按住的那张卡把自己的位置广播出来，附近的卡各自读这个位置、判断自己离光有多近，
 * 再在自己的边缘上画一圈高光——这才是液态玻璃的「边缘反光」。
 *
 * 为什么不用「把光画到卡片外面」这种更直接的做法（试过，不行）：
 *   - 画在相邻卡片**下面**：沉浸光感材质不透光，邻卡内部完全看不到，等于没画；
 *   - 画在相邻卡片**上面**：邻卡内部被照亮，变成「糊了一层主题色」，不是反光。
 *   只有让每张卡自己画自己的边缘，才能做到「亮在边上、不亮在里面」。
 *
 * 广播频率：手指滑动时触摸事件约 8ms 一个，全量转发会让所有卡片每帧重绘多次。
 * 发布端按 `PRESS_GLOW_PUBLISH_MS` 节流，位置变化对这个观感来说 25Hz 足够。
 */

/** 光源在窗口坐标系中的 X（vp）。空串以外的值都表示「有光」 */
export const PRESS_GLOW_X_KEY: string = 'pressGlowX';
/** 光源在窗口坐标系中的 Y（vp） */
export const PRESS_GLOW_Y_KEY: string = 'pressGlowY';
/** 光源颜色（`#RRGGBB`）。空串表示没有光，邻卡据此收起高光 */
export const PRESS_GLOW_COLOR_KEY: string = 'pressGlowColor';

/** 发布节流间隔（毫秒） */
export const PRESS_GLOW_PUBLISH_MS: number = 40;
/** 光源熄灭后写入的哨兵值：远在屏幕之外，任何卡片算出来的距离都超出范围 */
const OFF_POSITION: number = -100000;

/**
 * 点亮光源。`color` 传空串表示熄灭。
 */
export function publishPressGlow(x: number, y: number, color: string): void {
  try {
    AppStorage.setOrCreate(PRESS_GLOW_X_KEY, color.length > 0 ? x : OFF_POSITION);
    AppStorage.setOrCreate(PRESS_GLOW_Y_KEY, color.length > 0 ? y : OFF_POSITION);
    AppStorage.setOrCreate(PRESS_GLOW_COLOR_KEY, color);
  } catch (err) {
    // AppStorage 不可用时静默降级：流光少一层，不影响其它功能
  }
}
