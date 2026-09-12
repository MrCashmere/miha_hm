/*
 * 鸿米家（miha）— 本地智能（场景）执行与定时调度。
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

import { LocalScene, XiaomiDevice } from '../models/XiaomiHomeModels';
import { LocalSceneStore } from '../storage/LocalSceneStore';
import { xiaomiDataService } from './XiaomiDataService';
import { Logger } from '../utils/Logger';

/**
 * 定时心跳间隔。
 * 匹配精度是「整分钟」，30 秒轮询保证任何一分钟都能被命中，
 * 同时不会像每秒轮询那样持续唤醒。
 */
const TICK_INTERVAL_MS: number = 30000;

/** 一次执行的失败条目数，-1 表示整条智能都没能执行 */
export interface SceneRunResult {
  total: number;
  failed: number;
}

/**
 * 本地智能的执行与定时。
 *
 * 只在本机执行：动作直接下发到设备，不同步米家云端，也不依赖云端场景。
 * 心跳挂在首页的生命周期上（`start()` / `stop()`），因此只要应用在前台，
 * 定时就会触发；应用退到后台后不再执行——HarmonyOS 不提供违规的常驻后台通道。
 */
export class LocalSceneService {
  private tickerId: number = -1;
  /** 定时触发后的回调，用于让界面提示「已执行某某智能」 */
  onFired: (scene: LocalScene) => void = (): void => {
  };

  /** 开始心跳。重复调用安全，会先停掉旧的。 */
  start(): void {
    this.stop();
    this.tickerId = setInterval((): void => {
      this.checkDueTimers();
    }, TICK_INTERVAL_MS);
  }

  stop(): void {
    if (this.tickerId >= 0) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  /** 当前保存的全部本地智能 */
  scenes(): LocalScene[] {
    return LocalSceneStore.load();
  }

  /**
   * 执行一条本地智能。
   *
   * 控制器只需要取一次：它内部会按设备自动在局域网与云端之间降级，
   * 拿到之后可以连续给多台设备下发属性（与创建页里逐个动作执行的口径一致）。
   */
  async execute(scene: LocalScene): Promise<SceneRunResult> {
    const result: SceneRunResult = { total: scene.actions.length, failed: 0 };
    if (scene.actions.length === 0) {
      result.failed = -1;
      return result;
    }
    try {
      const device = await this.findDevice(scene.actions[0].did);
      const controller = await xiaomiDataService.getDeviceController(device);
      for (let i = 0; i < scene.actions.length; i++) {
        const action = scene.actions[i];
        try {
          await controller.setProperty(action.did, action.siid, action.piid, action.value);
        } catch (err) {
          result.failed++;
          Logger.error('local scene action failed, %{public}s',
            err instanceof Error ? err.message : String(err));
        }
      }
      Logger.info('local scene executed name=%{public}s total=%{public}d failed=%{public}d',
        scene.name, result.total, result.failed);
    } catch (err) {
      result.failed = -1;
      Logger.error('execute local scene failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
    return result;
  }

  /**
   * 按 did 找到设备对象。
   * 设备对象里带着 token 与局域网地址，控制器据此优先走局域网，失败再回落云端；
   * 找不到时就退回纯云端，不至于让整条智能报错。
   */
  private async findDevice(did: string): Promise<XiaomiDevice | undefined> {
    try {
      const devices = await xiaomiDataService.getDevices();
      const device = devices[did];
      if (device !== undefined) {
        return device;
      }
      const keys = Object.keys(devices);
      for (let i = 0; i < keys.length; i++) {
        if (devices[keys[i]].did === did) {
          return devices[keys[i]];
        }
      }
    } catch (err) {
      Logger.warn('find device for scene failed, %{public}s',
        err instanceof Error ? err.message : String(err));
    }
    return undefined;
  }

  /**
   * 心跳：整分钟匹配 + 重复日掩码 + lastFireDay 防同日重复触发。
   *
   * `lastFireDay` 必须在执行**之前**落盘：执行是异步的，
   * 若等执行完再写，下一次心跳会在同分钟内再次命中并重复执行。
   */
  private checkDueTimers(): void {
    const now = new Date();
    const today = this.todayKey(now);
    // JS 的 getDay() 里 0 是周日，而掩码下标 0 是周一，这里换算一次
    const weekday = (now.getDay() + 6) % 7;
    const scenes = LocalSceneStore.load();
    for (let i = 0; i < scenes.length; i++) {
      const scene = scenes[i];
      if (!scene.timerEnabled || scene.lastFireDay === today) {
        continue;
      }
      if (scene.timerDays.length === 7 && scene.timerDays.charAt(weekday) !== '1') {
        continue;
      }
      if (scene.timerHour !== now.getHours() || scene.timerMinute !== now.getMinutes()) {
        continue;
      }
      LocalSceneStore.update({
        sceneId: scene.sceneId,
        name: scene.name,
        actions: scene.actions,
        timerEnabled: scene.timerEnabled,
        timerHour: scene.timerHour,
        timerMinute: scene.timerMinute,
        timerDays: scene.timerDays,
        lastFireDay: today
      });
      this.execute(scene).then((result: SceneRunResult): void => {
        Logger.info('local scene timer fired name=%{public}s failed=%{public}d',
          scene.name, result.failed);
      });
      this.onFired(scene);
    }
  }

  /** YYYY-MM-DD */
  private todayKey(now: Date): string {
    const month = now.getMonth() + 1;
    const day = now.getDate();
    return `${now.getFullYear()}-${month < 10 ? '0' + month : month}-${day < 10 ? '0' + day : day}`;
  }
}

/** 全局单例：首页负责 start/stop，智能页直接读数据 */
export const localSceneService: LocalSceneService = new LocalSceneService();
