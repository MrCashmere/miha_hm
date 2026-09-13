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

import { applyMaterialCarrier, pressLightColor } from '../utils/SystemMaterial';

/**
 * 圆形沉浸光感图标按钮。
 *
 * 载体必须是 `ToggleType.Button`：真机实测（HarmonyOS 7.0.0.105 / API 26）
 * **普通 `Button` 挂 systemMaterial 不渲染**，而同尺寸的 `ToggleType.Button`
 * 正常出材质（卡片用的就是它）。这是本组件唯一可用的承载形态。
 *
 * 结构：`ToggleType.Button` 作为交互层承载材质并接收触摸，
 * 图标用 `Stack` 叠在它上面、设 `hitTestBehavior(HitTestMode.None)` 让触摸穿透，
 * 这样按压与流光都由 Toggle 本体响应。
 *
 * 灵动反馈（类 HdsTab）来自《沉浸式系统材质视效》：
 *   - `interactive: true`：按压弹性形变，松手自动恢复；
 *   - `lightEffect`：手指触摸时流光跟随，颜色默认白、可按主题色下发。
 * 由 `buttonInteractive` 控制，默认开启。
 *
 * 两条硬要求（《沉浸光感常见问题》）：
 *   - 材质层级在 `backgroundColor` 之下 → 必须显式设 `Color.Transparent`；
 *   - `systemMaterial` 要放在其他样式属性之后 → 用 attributeModifier 挂链尾。
 */
@Component
export struct IconCircleButton {
  @Prop buttonSize: number = 40;
  @Prop iconSize: number = 20;
  @Prop buttonEnabled: boolean = true;
  @Prop tint: string = '#182431';
  /**
   * 是否开启交互形变 + 流光（类 HdsTab 的灵动反馈）。
   *
   * 该能力依赖设备算力档位对 `ImmersiveOptions.interactive` / `lightEffect`
   * 的支持。若开启后发现材质整块消失，说明该设备不支持，把这里改回 `false`。
   */
  @Prop buttonInteractive: boolean = true;
  /**
   * 主题色流光依赖。
   *
   * 流光的颜色由 `applyMaterialCarrier` 在挂载材质时按主题色下发，
   * 而属性修饰器只在组件重建时才会重新执行。这里订阅主题色与流光开关，
   * 拨动开关或切色时本组件重建一次，流光颜色才会跟着换。
   */
  @StorageProp('accentColor') accentColor: string = '';
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
  /**
   * 是否为刷新类按钮：为 true 时图标持续旋转，表示「正在加载」。
   *
   * 用 animateTo 迭代旋转而不是 symbolEffect：SDK 的 SymbolEffect 只有
   * Appear / Bounce / Disappear / Hierarchical / Pulse / Replace / Scale，
   * 没有 Rotate，写 RotateSymbolEffect 会直接编译不过。
   */
  @Prop @Watch('onSpinningChanged') spinning: boolean = false;
  symbol: Resource = $r('sys.symbol.house');
  onAction: () => void = (): void => {
  };
  @State private spinAngle: number = 0;
  private spinTimer: number = -1;

  aboutToAppear(): void {
    this.syncSpinTimer();
  }

  aboutToDisappear(): void {
    this.stopSpin();
  }

  /** spinning 变化时起停定时器。定时器只负责推进角度，避免依赖动画回调递归。 */
  private syncSpinTimer(): void {
    if (this.spinning) {
      this.startSpin();
    } else {
      this.stopSpin();
    }
  }

  onSpinningChanged(): void {
    this.syncSpinTimer();
  }

  private startSpin(): void {
    if (this.spinTimer !== -1) {
      return;
    }
    this.spinTimer = setInterval((): void => {
      // 每 900ms 转一整圈：分 3 段推进，避免单次大角度动画在中低端机上掉帧
      this.getUIContext().animateTo({ duration: 300, curve: Curve.Linear }, (): void => {
        this.spinAngle += 120;
      });
    }, 300);
  }

  private stopSpin(): void {
    if (this.spinTimer !== -1) {
      clearInterval(this.spinTimer);
      this.spinTimer = -1;
    }
    this.spinAngle = 0;
  }

  /**
   * 材质承载修饰器。
   *
   * **必须写成方法并在 build 里调用**，不能把对象字面量直接塞进
   * `.attributeModifier({...})`：流光的颜色要在这里现读订阅变量
   * （主题色 + 主题色流光开关），读发生在渲染期才会被登记成依赖，
   * 拨开关或切主题色时本组件才会重建、重新下发带色材质。
   * 写成内联字面量的话闭包体不在渲染期执行，读什么都登记不上。
   */
  private carrierModifier(): AttributeModifier<ToggleAttribute> {
    const lightColor = pressLightColor(this.pressGlowSwitch, this.accentColor);
    return {
      applyNormalAttribute: (instance: ToggleAttribute): void => {
        applyMaterialCarrier(instance, false, this.buttonInteractive, true, lightColor);
      }
    };
  }

  build() {
    Stack() {
      // 材质 + 交互层：ToggleType.Button
      Toggle({ type: ToggleType.Button, isOn: false })
        .width(this.buttonSize)
        .height(this.buttonSize)
        .borderRadius(this.buttonSize / 2)
        .clip(true)
        // 必须显式透明：不透明背景会盖在材质层之上
        .backgroundColor(Color.Transparent)
        // 关掉按压/选中的主题色填充。ToggleType.Button 的选中态默认取主题强调色，
        // 按下时会闪一层蓝底；isOn 恒为 false 也挡不住这个按压填充。
        .selectedColor(Color.Transparent)
        .enabled(this.buttonEnabled)
        // systemMaterial 放在所有样式属性之后
        .attributeModifier(this.carrierModifier())
        .onChange(() => {
          this.onAction();
        })

      // 图标层：触摸穿透到下面的 Toggle，保证按压与流光响应在材质上
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize)
        .fontColor([this.tint])
        .rotate({ angle: this.spinAngle })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .onAppear((): void => {
      this.syncSpinTimer();
    })
  }
}
