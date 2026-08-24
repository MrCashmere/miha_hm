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

export const HwColor: HwColorPalette = {
  primary: '#0A59F7',
  background: '#F1F3F5',
  backgroundDark: '#000000',
  surface: '#FFFFFF',
  textPrimary: '#182431',
  textSecondary: '#8A8F99',
  danger: '#D94838',
  online: '#00AA72'
};

export interface HwRadiusScale {
  card: number;
  control: number;
  pill: number;
}

export const HwRadius: HwRadiusScale = {
  card: 24,
  control: 16,
  pill: 999
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
  surface: '#B3FFFFFF',
  border: '#1AFFFFFF'
};
