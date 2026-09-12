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

import { AppSettingsStore } from './AppSettingsStore';

const ROOM_ORDER_KEY: string = 'roomDisplayOrder';

/** 排序只依赖房间 id，用命名接口而不是匿名对象类型（ArkTS 对匿名类型约束更严格） */
interface OrderableRoom {
  id: string;
}

/**
 * 房间展示顺序。
 *
 * 为什么单独存一份顺序，而不是直接用 `RoomStore` 里的数组次序：
 * 房间列表是「米家云端已有房间 + 本应用自建房间」合并出来的（见 RoomsPage.rebuildRooms），
 * 每次合并都会重新排序。如果只依赖 `RoomStore` 的数组顺序，用户拖动后的排列
 * 在下次合并时就被冲掉了。这里把「房间 id 的展示顺序」独立持久化，
 * 合并时按它排前面，没记录过的房间按名称排在后面。
 */
export class RoomOrderStore {
  static load(): string[] {
    return AppSettingsStore.getStringArray(ROOM_ORDER_KEY, []);
  }

  static save(order: string[]): void {
    AppSettingsStore.setStringArray(ROOM_ORDER_KEY, order);
  }

  /**
   * 按已保存顺序重排房间：有记录的按记录顺序在前，未记录的按原顺序追加在后。
   * 这样新增的房间不会插到中间，用户排好的部分也不会被打乱。
   */
  static apply<T extends OrderableRoom>(rooms: T[]): T[] {
    const order = RoomOrderStore.load();
    if (order.length === 0) {
      return rooms;
    }
    const rank = new Map<string, number>();
    for (let i = 0; i < order.length; i++) {
      rank.set(order[i], i);
    }
    return rooms.slice().sort((a: T, b: T): number => {
      const ra = rank.has(a.id) ? rank.get(a.id) as number : Number.MAX_SAFE_INTEGER;
      const rb = rank.has(b.id) ? rank.get(b.id) as number : Number.MAX_SAFE_INTEGER;
      if (ra !== rb) {
        return ra - rb;
      }
      return 0;
    });
  }
}
