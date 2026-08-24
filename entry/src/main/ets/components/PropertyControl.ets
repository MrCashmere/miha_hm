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

import {
  CapabilityControlType,
  PropertyControlDescriptor
} from './CapabilityRenderer';
import { HwColor, HwRadius, HwSpace, HwGlassCardColor } from '../utils/DesignTokens';
import { isCelsiusUnit, celsiusToFahrenheit, fahrenheitToCelsius } from '../utils/TemperatureDisplay';
import { isApi26OrAbove, immersiveMaterialModifier, legacyMaterialModifier } from '../utils/SystemMaterial';
import { IconCircleButton } from './IconCircleButton';

@Component
export struct PropertyControl {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageLink('fontMode') fontMode: string = 'system';
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
  @Prop control: PropertyControlDescriptor;
  @Prop @Watch('onValuePropChanged') value: Object | undefined;
  @StorageProp('temperatureFahrenheit') temperatureFahrenheit: boolean = false;
  @StorageProp('temperatureShowUnit') temperatureShowUnit: boolean = false;
  onChanged: (value: Object) => void = (): void => {
  };
  @State private lastValue: Object | undefined = undefined;
  @State private userGesture: boolean = false;
  @State private draft: string = '';

  aboutToAppear(): void {
    this.lastValue = this.value;
    this.draft = this.stringOf(this.value);
  }

  onValuePropChanged(): void {
    this.lastValue = this.value;
    this.draft = this.stringOf(this.value);
  }

  private boolOf(input: Object | undefined): boolean {
    return input === true || input === 1 || input === 'true' || input === '1';
  }

  private numberOf(input: Object | undefined): number {
    const num = Number(input);
    return Number.isNaN(num) ? 0 : num;
  }

  private stringOf(input: Object | undefined): string {
    return String(input ?? '');
  }

  private readoutText(): string {
    const value = this.value;
    if (value === undefined || value === null) {
      return '--';
    }
    if (this.control.options.length > 0) {
      const idx = this.control.optionValues.indexOf(value);
      if (idx >= 0) {
        return this.control.options[idx];
      }
    }
    if (this.isTemperatureReadout()) {
      const number = this.numberOf(value);
      return `${this.formatNumber(this.fahrenheitMode() ? celsiusToFahrenheit(number) : number)}${this.valueUnitText()}`;
    }
    if (this.control.format === 'bool') {
      return this.boolOf(value) ? '开启' : '关闭';
    }
    return String(value);
  }

  private commitText(): void {
    if (this.draft !== this.stringOf(this.lastValue)) {
      this.onChanged(this.draft);
    }
  }

  private hasValue(): boolean {
    return this.value !== undefined && this.value !== null;
  }

  private steppedText(): string {
    if (!this.hasValue()) {
      return '--';
    }
    return `${this.formatNumber(this.displayValue())}${this.valueUnitText()}`;
  }

  private sliderText(): string {
    if (!this.hasValue()) {
      return '--';
    }
    return this.formatNumber(this.numberOf(this.value));
  }

  private stepSteppedValue(direction: number): void {
    if (!this.control.writable || !this.hasValue()) {
      return;
    }
    const step = this.controlStep() > 0 ? this.controlStep() : 1;
    const next = this.clampTemperature(
      this.roundStepValue(this.displayValue() + direction * step)
    );
    this.onChanged(this.commitDisplayValue(next));
  }

  private clampTemperature(value: number): number {
    return Math.max(this.controlMin(), Math.min(this.controlMax(), value));
  }

  private roundStepValue(value: number): number {
    return Math.round(value * 1000) / 1000;
  }

  private fahrenheitMode(): boolean {
    return this.temperatureFahrenheit && isCelsiusUnit(this.control.unit);
  }

  private unitText(): string {
    return this.fahrenheitMode() ? '°F' : this.control.unit;
  }

  private valueUnitText(): string {
    if (this.isSteppedControl()) {
      return this.unitText();
    }
    return this.temperatureShowUnit ? this.unitText() : '';
  }

  private displayValue(): number {
    const number = this.numberOf(this.value);
    return this.fahrenheitMode() ? celsiusToFahrenheit(number) : number;
  }

  private lastDisplayValue(): number {
    const number = this.numberOf(this.lastValue);
    return this.fahrenheitMode() ? celsiusToFahrenheit(number) : number;
  }

  private commitDisplayValue(value: number): Object {
    return this.fahrenheitMode() ? this.roundStepValue(fahrenheitToCelsius(value)) : value;
  }

  private controlMin(): number {
    return this.fahrenheitMode() ? celsiusToFahrenheit(this.control.min) : this.control.min;
  }

  private controlMax(): number {
    return this.fahrenheitMode() ? celsiusToFahrenheit(this.control.max) : this.control.max;
  }

  private controlStep(): number {
    return this.fahrenheitMode() ? this.control.step * 9 / 5 : this.control.step;
  }

  private formatNumber(value: number): string {
    return Number.isInteger(value) ? String(value) : value.toFixed(1);
  }

  private isTemperatureReadout(): boolean {
    const unit = this.control.unit.trim().toLowerCase();
    return isCelsiusUnit(this.control.unit) || unit === '°f';
  }

  private isSteppedControl(): boolean {
    return this.control.type === CapabilityControlType.TEMPERATURE ||
      this.control.type === CapabilityControlType.VOLUME;
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.control.label)
          .fontFamily(this.appFontFamily(this.control.label))
          .fontWeight(this.appFontWeight())
          .fontSize(15)
          .fontColor(HwColor.textPrimary)
        Blank()
        if (this.unitText().length > 0 &&
          !this.isSteppedControl()) {
          Text(this.unitText())
            .fontFamily(this.appFontFamily(this.unitText()))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(HwColor.textSecondary)
        }
      }
      .width('100%')

      if (this.control.type === CapabilityControlType.TOGGLE) {
        Toggle({ type: ToggleType.Switch, isOn: this.boolOf(this.value) })
          .enabled(this.control.writable)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.userGesture = true;
            }
          })
          .onChange((isOn: boolean) => {
            if (!this.userGesture) {
              return;
            }
            this.userGesture = false;
            if (isOn === this.boolOf(this.lastValue)) {
              return;
            }
            this.onChanged(isOn);
          })
      }

      if (this.control.type === CapabilityControlType.SLIDER) {
        Slider({
          value: this.numberOf(this.value),
          min: this.control.min,
          max: this.control.max,
          step: this.control.step,
          style: SliderStyle.OutSet
        })
          .enabled(this.control.writable)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.userGesture = true;
            }
          })
          .onChange((value: number, mode: SliderChangeMode) => {
            if (!this.userGesture) {
              return;
            }
            if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) {
              return;
            }
            this.userGesture = false;
            if (value === this.numberOf(this.lastValue)) {
              return;
            }
            this.onChanged(value);
          })

        Text(this.sliderText())
          .fontFamily(this.appFontFamily(this.sliderText()))
          .fontWeight(this.appFontWeight())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
      }

      if (this.isSteppedControl()) {
        Row({ space: 8 }) {
          IconCircleButton({
            symbol: $r('sys.symbol.minus'),
            buttonSize: 36,
            iconSize: 18,
            buttonEnabled: this.control.writable && this.hasValue() &&
              this.displayValue() > this.controlMin(),
            onAction: () => {
              this.stepSteppedValue(-1);
            }
          })
          Slider({
            value: this.displayValue(),
            min: this.controlMin(),
            max: this.controlMax(),
            step: this.controlStep(),
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .enabled(this.control.writable)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.userGesture = true;
              }
            })
            .onChange((value: number, mode: SliderChangeMode) => {
              if (!this.userGesture) {
                return;
              }
              if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) {
                return;
              }
              this.userGesture = false;
              if (value === this.lastDisplayValue()) {
                return;
              }
              this.onChanged(this.commitDisplayValue(value));
            })
          IconCircleButton({
            symbol: $r('sys.symbol.plus'),
            buttonSize: 36,
            iconSize: 18,
            buttonEnabled: this.control.writable && this.hasValue() &&
              this.displayValue() < this.controlMax(),
            onAction: () => {
              this.stepSteppedValue(1);
            }
          })
        }
        .width('100%')

        Text(this.steppedText())
          .fontFamily(this.appFontFamily(this.steppedText()))
          .fontWeight(this.appFontWeight())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
      }

      if (this.control.type === CapabilityControlType.TEXT) {
        TextInput({ text: this.draft })
          .enabled(this.control.writable)
          .onChange((value: string) => {
            this.draft = value;
          })
          .onSubmit(() => {
            this.commitText();
          })
          .onBlur(() => {
            this.commitText();
          })
      }

      if (this.control.type === CapabilityControlType.SELECT) {
        Flex({
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.Start,
          alignItems: ItemAlign.Center
        }) {
          ForEach(this.control.options, (option: string, index?: number) => {
            Button(option, {
              type: ButtonType.Capsule,
              buttonStyle: this.value === this.control.optionValues[index ?? 0]
                ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL,
              controlSize: ControlSize.SMALL
            })
              .enabled(this.control.writable)
              .fontColor(this.value === this.control.optionValues[index ?? 0] ? '#FFFFFF' : HwColor.textPrimary)
              .stateEffect(true)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.onChanged(this.control.optionValues[index ?? 0]);
              })
          }, (option: string) => option)
        }
        .width('100%')
      }

      if (this.control.type === CapabilityControlType.READOUT) {
        Text(this.readoutText())
          .fontFamily(this.appFontFamily(this.readoutText()))
          .fontWeight(this.appFontWeight())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(HwColor.textPrimary)
      }
    }
    .width('100%')
    .padding(HwSpace.md)
    .borderRadius(HwRadius.control)
    .backgroundColor(HwGlassCardColor.surface)
    .attributeModifier(this.immersiveLightEnabled && isApi26OrAbove() ? immersiveMaterialModifier : legacyMaterialModifier)
    .border({ width: 1, color: HwGlassCardColor.border })
    .clip(true)
  }
}
