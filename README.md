# 鸿米家（miha）

基于 HarmonyOS NEXT 原生 ArkTS / ArkUI 开发的小米家庭 / 米家（MIoT）控制应用。目标是在手机、平板、2in1 与穿戴设备上，通过小米云 / 米家 API 管理家庭、房间与设备，并尽可能打通局域网与 MQTT 通道。

> 当前版本：1.1.1-OS（bundleName `com.miha.harmony`）

## 更新日志

| 版本 | 主要内容 |
| --- | --- |
| **1.1.1-OS** | 修复部分设备启动闪退、超大照片背景裁切不出图、折叠屏裁剪框比例、主题色与页面底色不同步等问题；卡片在沉浸光感不可用时降级为毛玻璃 —— [完整说明](docs/1.1.1.md) |
| [1.1.0-OS](docs/1.1.0.md) | 新增全局主题色、耗材中心、本地智能（场景）、设备管理、家庭消息；沉浸光感覆盖卡片 / 按钮 / 弹窗；修复登录、云端接口与局域网的多处问题 |
| 1.0.7-OS | 首个开源版本 |

每个版本的完整说明放在 `docs/<版本号>.md`，发版时在这里补一行即可。

## 功能特性

- **米家扫码登录**：基于 `serviceLogin` 的二维码登录流程，长期轮询票据，自动组装授权数据。
- **家庭 / 房间 / 设备管理**：拉取家庭列表、房间与设备数据，支持设备在线 / 缓存 / 离线状态区分。
- **动态设备控制**：按 MIoT-Spec V2 实例解析设备能力，动态生成属性与动作控件，无需为每个设备型号写死 UI；支持带参数的 action 输入。
- **设备能力翻译**：服务类型与设备能力显示名翻译，覆盖常见米家设备类型。
- **局域网发现**：基于 mDNS 发现 `_miot-central._tcp.local.` 的 MIPS 服务。
- **LAN 传输层**：`LanCrypto`（AES-CBC / MD5 / PKCS7 / 报文分帧）+ UDP Socket + `LanDeviceTransport`，为局域网直连控制做准备。
- **MQTT 抽象**：状态机、订阅管理，保留私有服务器 / 证书参数接入位。
- **通知与后台能力**：通过 `DeviceEventBus` 驱动原生通知；仅声明系统允许的后台通知能力。
- **外观设置**：自定义背景（含裁切）与字体管理，全局沉浸光感开关。
- **备份与恢复**：导出为 ZIP 压缩包，可选附带自定义背景与字体，恢复时同步还原资源，并按设备比对过滤不适用设置项。
- **反馈与日志**：完整日志模式，导出日志时对 Token、密钥等敏感参数脱敏；支持教程与选择保存位置。
- **悬浮底栏与主页优化**：主页平滑切换、隐藏离线设备实时生效、音箱播放 / 麦克风控制与音量阶梯调节。
- **本地智能（场景）**：`LocalSceneStore` 保存仅在本机执行的场景与定时（不同步米家云端），`SceneCreatePage` 编辑。
- **耗材与消息**：`MijiaApiClient` 拉取耗材余量与家庭消息，`ConsumablesPage` 汇总展示。
- **设备整理**：`DeviceOverrideStore`（改名 / 换房 / 置顶）、`DeviceRemovalStore`（本地移除记录），`DeviceManagePage` 管理。

## 页面一览

| 页面 | 说明 |
| --- | --- |
| LoginPage | 米家二维码登录 |
| FamilySelectPage | 家庭选择 |
| HomePage / RoomsPage | 家庭概览与房间设备列表 |
| DeviceDetailPage | 设备详情，按 MIoT-Spec 动态渲染属性 / 动作控件 |
| DeviceManagePage | 设备管理（移除记录 / 批量整理） |
| ScenePage | 智能：本地智能列表、云端自动化 / 手动场景执行 |
| SceneCreatePage | 本地智能（场景）创建与定时编辑 |
| ConsumablesPage | 耗材余量总览 |
| SettingsPage | 设置入口 |
| AppearanceSettingsPage / BackgroundCropPage / FontManagePage | 外观、背景裁切、字体管理 |
| BackupRestorePage | 备份导出 / 恢复 |
| FeedbackPage | 反馈与日志导出 |
| AboutPage / AboutDevicePage | 关于应用与设备信息 |

## 项目结构

```text
.
├── AppScope/                 # 应用级配置（bundleName、图标、版本）
├── entry/                    # entry 模块
│   └── src/main/ets/
│       ├── entryability/     # EntryAbility、深链（xiaomihome://oauth）
│       ├── pages/            # 页面
│       ├── components/       # 可复用组件
│       ├── models/           # 家庭 / 房间 / 设备 / MIoT-Spec 模型
│       ├── repositories/     # 数据仓库与缓存
│       ├── services/         # OAuth、数据、通知、备份恢复、反馈日志
│       ├── cloud/            # XiaomiCloudClient、MijiaApiClient、Spec 解析
│       ├── oauth/            # OAuth / 米家扫码登录
│       ├── lan/              # mDNS 发现、UDP、LAN 加密与传输
│       ├── mqtt/             # MQTT 客户端抽象
│       ├── network/          # HTTP 客户端
│       ├── storage/          # 安全存储与本地缓存
│       ├── events/           # DeviceEventBus
│       ├── controllers/      # DeviceController 等控制层
│       ├── utils/            # 工具函数
│       └── generated/        # 生成代码
├── build-profile.json5       # SDK 版本、产品配置（签名需自行配置）
├── hvigor/                   # hvigor 构建配置
├── oh-package.json5          # 工程依赖
├── .gitignore
├── LICENSE                   # GPL v3
└── README.md
```

## 技术要点

- **框架**：HarmonyOS NEXT，ArkTS + ArkUI 声明式开发。
- **SDK**：compileSdkVersion / targetSdkVersion 26.0.0，compatibleSdkVersion 6.1.1(24)。
- **设备形态**：phone、tablet、2in1、wearable。
- **数据流**：`Repository / Service` → `DeviceController` → 多 Transport（Cloud / LAN / MQTT）→ `DeviceEventBus` 分发属性变化、上下线、动作结果与错误。
- **能力渲染**：`CapabilityRenderer` 将 MIoT-Spec 描述转换为控件描述，避免硬编码设备型号。
- **缓存**：`JsonCache` 等本地缓存区分 online / cached / stale 状态。
- **沉浸光感材质**：见下节「沉浸光感（API 26）」。
- **安全**：Token 等敏感信息使用系统安全存储；日志导出对敏感参数脱敏。

## 沉浸光感（API 26）

HarmonyOS API 26 引入 `uiMaterial`（系统材质）与 `systemMaterial()`，应用可把「沉浸光感」材质挂在组件上。本项目的实现要点：

- `utils/SystemMaterial.ets`：材质构造、系统开关判定与降级逻辑。
- `components/MaterialCard.ets`：卡片统一容器，内部叠一层**透明 Toggle** 承载材质。

### 失效的两个真实原因

**1）应用级状态没配（主因）。** `uiMaterial.getMaterialInfo().state` 读的不是用户设置，而是 entry 模块
`module.json5` 里的 metadata：

| 配置值 | 枚举值 | 表现 |
| --- | --- | --- |
| `default` | `MaterialState.DEFAULT` | 系统按默认规则处理部分组件，普通组件可主动设置材质 |
| `enable` | `MaterialState.ENABLE` | 更多系统组件自动使用材质，普通组件仍可主动设置 |
| `disable` | `MaterialState.DISABLE` | 关闭整个应用的沉浸材质，**主动设置的材质也一并失效** |

本工程此前**完全没有配置这一项**，一旦解析为 `disable`，材质就永远不会渲染，且这是代码绕不过的——
必须改 `module.json5` 并**重新构建安装**（该值打进安装包，页面上的开关改不了它）。
现已显式配置为 `enable`。

**2）生效范围与组件类型约束。** 官方《组件适配沉浸光感》规定：

- **按钮与选择类组件**（`Button` / `Select` / `Toggle` / `Slider` / `ChipGroup` / `SegmentButton`）
  **可在页面内全部区域生效**；
- **其余组件**（布局容器、滚动容器等）的通用属性 `systemMaterial`
  **只在 Navigation / NavDestination 标题栏，或 `barPosition` 为 `BarPosition.End` 的底部 TabBar 中生效**，
  在其他区域设置无效。

卡片位于 NavDestination 内容区，所以把 `systemMaterial` 直接挂在 `Column` / `Row` 上必然无效。

### 各 ToggleType 的差异（决定承载方式的关键）

| ToggleType | 官方行为 |
| --- | --- |
| `Checkbox` | **当前未适配沉浸光感效果，设置后无效果**（中间那个圈是 Checkbox 自己的图形，不是材质） |
| `Switch` | 材质参数**仅作为开启标记**，实际使用组件内部预设视觉参数，只影响滑块大小/样式/阴影——永远只覆盖开关本体那片区域 |
| `Button` | 效果与 `Button` 组件相同，影响背景色、边框、阴影 |

因此：

- **卡片**（需要覆盖整块矩形）→ `MaterialCard` 用 `ToggleType.Button` 作承载层；
- **圆形按钮** → `IconCircleButton` 直接把材质挂在 `Button` 上（官方明确 Button 支持 `systemMaterial`），
  不需要任何承载层。

材质生效时其样式优先级**高于组件原有的背景色、模糊、阴影与边框**，所以承载层/按钮要让出自身底色。

承载层尺寸用 `LayoutPolicy.matchParent` 而不是 `height('100%')`：卡片高度由内容撑开，
父容器 `Stack` 自身没有确定高度，百分比高度在「先撑开容器、再适配子组件」的场景里语义不明确，
`matchParent` 才能保证承载层与卡片等大（见 `LayoutPolicy` 文档中 wrapContent 容器与 matchParent 子组件的规则）。

### 历史上的自锁（已移除）

旧实现把 `getMaterialInfo().state === DISABLE` 当成「本应用不能渲染」，直接 `return uiMaterial.Material.empty`，
又拿同一个状态作为降级条件——等于应用自己把光感关掉。现在 `MaterialState` **只用于诊断展示**，
材质只要构造成功就下发，画不画由系统按生效范围决定；材质改为惰性构造，构造失败返回 `null`
（绝不返回 `Material.empty`，那等于「显式不画」，会把失败伪装成静默失效）并降级为毛玻璃。

> 注意：`enable` 会让系统组件（Select / Toggle / Slider / 菜单 / 弹窗）自动使用沉浸材质，
> 且材质样式优先级高于组件原有背景色、模糊、阴影与边框。若发现这些组件观感异常，
> 可把 `module.json5` 的值改回 `default`（仍允许主动设置材质），重新构建即可。

### 排查工具

「外观设置 → 全局沉浸光感」下方会显示一行诊断（`materialDiagnostics()`），形如
`API=26 材质=已构造 状态=非DISABLE 开关=开 承载=下发材质`。

- `材质=构造失败`、`状态=DISABLE`、或 `API` 小于 26 → 回到上面第 1 条查 `module.json5` / `ImmersiveMaterial` 构造；
- 全部正常但界面无光感 → 检查承载组件的类型是否符合上表（`Checkbox` 必然无效）。

### 卡片迁移约定（MaterialCard 参数）

ArkTS 不允许在「尾随闭包初始化的自定义组件」后面继续链式调用属性——
`MaterialCard({...}) { ... }.onClick(...)` 会直接报 `Cannot find name 'onClick'`。
因此旧卡片容器 `Row` / `Column` 上的属性必须改写成 `MaterialCard` 的构造参数：

| 旧写法 | 现写法 |
| --- | --- |
| `Row({ space: 12 })` / `Column({ space: 6 })` | `cardDirection` + `cardSpace` |
| `.padding(...)` / `.borderRadius(...)` / `.backgroundColor(...)` | `cardPadding` / `cardRadius` / `cardBackground` |
| `.hoverEffect(...)` / `.focusable(...)` / `.enabled(...)` / `.opacity(...)` | `cardHoverEffect` / `cardFocusable` / `cardEnabled` / `cardOpacity` |
| `.onClick(...)` / `.bindMenu(...)` | `cardOnClick` / `cardMenuItems` |
| `.alignItems(HorizontalAlign.Start)` | `cardAlignItems: ItemAlign.Start` |

几条容易踩的约定：

- **padding 挂在内部内容容器上**，卡片外层不再有 padding，承载层才能铺满整张卡片（含原 padding 区域）。
- **`cardAlignItems` 默认 `ItemAlign.Center`**：内部用 `Flex` 承载内容，而 `Flex` 的交叉轴默认值是
  `ItemAlign.Start`，与 `Row`（`VerticalAlign.Center`）和 `Column`（`HorizontalAlign.Center`）的默认行为不同，
  不显式指定会让卡片内容贴顶/贴左。
- **需要 `bindSheet()` 的卡片**在 `MaterialCard` 外面再包一层 `.width('100%')` 的 `Column`，
  sheet 绑在这一层上（`$$` 双向绑定与 `@Builder` 参数无法作为普通属性传进自定义组件），
  sheet 的锚点仍是卡片本身的大小。
- **卡片高度写进内容容器**，不再有 `.height()` 挂在卡片上的写法；原来固定高度的信息卡把高度和
  `justifyContent(FlexAlign.Center)` 放到内部 `Column` 上。

### 半模态弹窗（向上弹出的卡片）

弹窗面板和普通卡片遇到的是同一堵墙：`bindSheet` 的 `systemMaterial` 挂在**面板本身**，
而非选择类组件在内容区不生效。所以弹窗内容统一用 `MaterialSheetPanel` 包一层，
由 Toggle 承载层渲染材质，与 `MaterialCard` 完全同源。

```ts
.bindSheet($$this.showXxxSheet, this.xxxSheet(), {
  height: SheetSize.MEDIUM,
  dragBar: true,
  showClose: false,
  // 必须显式透明：BindOptions.backgroundColor 的默认值是 Color.White，
  // 而沉浸光感的视觉层级位于 backgroundColor **之下**，白底会把材质整块盖住。
  backgroundColor: Color.Transparent,
  blurStyle: sheetBlurStyle(),
})
```

两个非直觉点，改弹窗时务必保留：

- **`backgroundColor: Color.Transparent` 不能省。** `SheetOptions extends BindOptions`，
  而 `BindOptions.backgroundColor` 官方标注 `Default value: Color.White`。
  只设 `systemMaterial` 而不放开底色，材质会被白底完全遮住——表现为「弹窗一点光感都没有」。
- **弹窗内容根节点不能自带不透明底色。** 它是承载层的兄弟节点、渲染在其之上，
  写 `.backgroundColor(...)` 同样会盖掉材质。

### 按钮的沉浸光感

按钮统一走 **Toggle 承载层 + 静态材质**，两条都不能少：

```ts
Stack() {
  MaterialCardLayer({ layerRadius: HwRadius.pill })   // 与卡片同源的 Toggle 承载
  Button('确定', { type: ButtonType.Capsule, stateEffect: false })
    .width('100%')                                    // 点击区要铺满，否则只有文字附近可点
    .backgroundColor(Color.Transparent)               // 不透明底色会盖住材质
    .onClick(...)
}
```

- **材质必须是静态的**（只传 `style`）。`ImmersiveMaterial({ style, interactive: true, lightEffect: {} })`
  这个组合实测在 HarmonyOS 7.0.0.105 / API 26 上**完全不渲染**——
  历史上 `applyButtonMaterial` 硬编码了 `interactive: true`，导致「卡片有光感、按钮没有」，
  排查时容易误判成组件类型的问题。`applyButtonMaterial` 现已改为下发静态材质。
- **按钮外面要包 Toggle 承载层。** 普通 `Button` 直接挂 `systemMaterial` 在真机上不稳定，
  包一层 `MaterialCardLayer` 就与卡片走同一条已验证的路径。
- 带 `layoutWeight` 的按钮要把它移到外层 `Stack` 上（`Stack` 内 `layoutWeight` 不生效），
  同时给 `Button` 补 `width('100%')`。

### 降级行为

沉浸光感不可用时（API < 26、应用内开关关闭、材质构造失败，或用户在系统设置里关闭材质总开关），
`MaterialCard` 自动回退为 `backgroundBlurStyle(BlurStyle.Thin)` 毛玻璃，界面不会空白。

「外观设置 → 全局沉浸光感」下方会显示一行诊断信息（`materialDiagnostics()`），
形如 `API=26 材质=已构造 系统状态=ENABLE 应用开关=开 承载=生效`，便于真机排查材质为何未生效。

### 已知未覆盖

`FeedbackPage` 的半模态弹窗（`showTutorialSheet`）尚未包 `MaterialSheetPanel`，
面板本身没有光感。其余弹窗均已覆盖。

## 主题色

主题色（全局强调色）的实现方式、生效链路、**必须跟随主题色的组件清单**与移植步骤，
见 [`docs/ThemeColor.md`](docs/ThemeColor.md)。

要点：颜色常量集中在可变对象 `HwColor` 里，靠 `AppStorage['accentColor']` 广播刷新；
`Toggle` / `Slider` 的 `selectedColor` 默认是系统强调色，必须显式覆盖。

## 环境要求

- DevEco Studio（含 HarmonyOS SDK，建议 6.x / API 26）。
- 可选的命令行构建需要 `DEVECO_SDK_HOME` 指向 DevEco Studio 的 SDK 目录。

## 构建

> 仓库不包含签名配置。首次构建请在 DevEco Studio 中通过
> `File > Project Structure > Signing Configs` 生成并配置你的签名，否则只能产出未签名 HAP。

### 方式一：DevEco Studio

用 DevEco Studio 打开本项目根目录，同步工程后选择 `entry` 模块构建 HAP。

### 方式二：命令行 hvigor

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
```

产物路径：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/default/entry-default-signed.hap   # 配置签名后
```

## 测试

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p product=default -p module=entry@default -p buildMode=debug test
```

单元测试使用 `@ohos/hypium` 与 `@ohos/hamock`。

## 权限说明

应用声明了以下权限：

- `ohos.permission.INTERNET`：访问小米云 / 米家 API。
- `ohos.permission.STORE_PERSISTENT_DATA`：持久化存储。
- `ohos.permission.VIBRATE`：`utils/Haptic.ets` 的按键触感反馈。

## 已知限制与验证状态

- 米家扫码登录与云 API 路径基于公开的 `Do1e/mijia-api` 仓库实现，算法与端点已落地，但**尚未使用真实账号 / 真实设备响应做过端到端校准**。
- LAN 加密控制（AES / MD5 分组、token/key/iv 派生）与 UDP 协议需要真实设备 token 联调。
- MQTT 事件订阅需要 MIPS 服务地址、端口与证书流程。
- HarmonyOS NEXT 不提供违规的常驻后台通道，后台能力仅限系统允许的原生通知。
- **沉浸光感的 Toggle 承载层依赖系统内部行为**：开关类控件当前不受 `systemMaterial()` 生效约束管控，
  但该行为由系统实现决定，系统更新后可能变化。`MaterialCard` 已内置降级路径，届时会退回毛玻璃而非异常。
- **切换 Tab 后列表不回顶部**：已多轮排查仍未跑通，现象、试过的方案、
  已排除的原因与下一步切入点都记在 [`docs/待研究问题.md`](docs/待研究问题.md)。
  首页顶栏的「列表回正」按钮可用作临时手段。

## 合规说明

本项目为 **clean-room 独立实现**：本仓库不包含上游源码。实现仅基于公开的协议事实与公开仓库（如 `XiaoMi/ha_xiaomi_home`）记录的 API 信息编写，未复制上游代码。上游许可证对将 Licensed Work 用于开发 App / Web 服务等场景有限制，请在使用、分发前自行确认相关授权。

## 免责声明

本项目仅用于学习与技术研究。使用本项目访问小米云 / 米家服务前，请确保遵守小米相关服务条款，并对由此产生的账号、设备与数据安全风险自行负责。

## 许可证

Copyright (C) 2026 鸿米家（miha）项目开发者

本项目基于 **GNU General Public License v3.0（GPL v3）** 发布。

你可以自由地使用、复制、修改与分发本项目，但任何分发或修改后的作品必须同样以 GPL v3 许可，并保留版权声明与本许可文本。GPL v3 不提供任何担保，详见 `LICENSE` 文件。

```text
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
