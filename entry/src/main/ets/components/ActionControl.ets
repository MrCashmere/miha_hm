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

import { ActionControlDescriptor } from './CapabilityRenderer';
import { PressableButton } from './PressableButton';

@Component
export struct ActionControl {
  @Prop control: ActionControlDescriptor;
  @Prop loading: boolean;
  onAction: () => void = (): void => {
  };

  build() {
    PressableButton({
      label: this.loading ? '执行中...' : this.control.label,
      emphasized: true,
      loading: this.loading,
      fullWidth: true,
      buttonHeight: 44,
      role: ButtonRole.NORMAL,
      onAction: () => {
        this.onAction();
      }
    })
  }
}
