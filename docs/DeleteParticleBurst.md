# DeleteParticleBurst —— 卡片粒子消散动效（可移植实现）

本文是「删除卡片 → 卡片打成粒子吹散」这条动效的**完整实现与移植说明**：含全部相关源码、
参数表、接入步骤与踩坑清单。目标读者是把它搬到**另一个 ArkTS / ArkUI 工程**的人 ——
照 §7 的步骤做即可，除 ArkUI 自带的 `Particle` 外不依赖本仓库的任何其它模块。

- 效果：触发删除后，卡片轻微收拢淡出，同时从**整个卡面**炸出一片粒子向外飘散、淡出、缩小。
- 分档：**鸿蒙 7 / API 26+ 走粒子消散**；其它版本走标准缩放淡出（另有总开关可关）。
- 参数：半径 / 数量 / 发射速率 / 生命周期 / 寿命抖动 / 初速 / 加速度 / 缩放 / 透明度 / 时长
  共 16 项，全部可在设置页实时调整并预览。

> **许可提醒**：本文源码取自鸿米家（miha）工程，该工程以 **GPL-3.0-or-later** 发布。
> 移植到别的项目时请遵守 GPL v3：派生作品需同样以 GPL v3 分发、保留版权声明与许可文本。
> 若你的项目不能接受 GPL，请只把本文当作算法与踩坑记录参考，另行独立实现。
> 下面贴出的源码省略了文件头的 GPL 注释块（省篇幅），完整版本见仓库对应文件。

---

## 1. 实现由三层组成

```text
DeleteEffectPrefs        参数层：所有可调值（键 / 默认值 / 区间 / 时长换算），落盘 + AppStorage 广播
      │
      ├── DeleteDissolve      动效外壳：卡片缩放淡出 + 粒子层挂载 + 起手时机 + 尺寸实测
      │        └── DeleteParticleBurst   粒子层：一个 ArkUI Particle，按参数发射
      │
      ├── ParticleParamRow    （仅设置页）一行「名称 + 滑杆 + 当前值」
      │
      └── 调用方（删除流程）用同一个时长算式决定「动画播完多久摘卡」
```

依赖是**单向**的：粒子层与外壳不引用调用方，只读 AppStorage 里的键。
调用方要做的事只有这几件：

| 要做的事 | 位置 |
| --- | --- |
| 卡片外面套一层 `DeleteDissolve` | 列表项构建处（本文以首页设备卡为例） |
| 触发删除时置位「正在删除的 id」，并把它写进 `ForEach` 的键 | 列表页 |
| 动画播完再落库、摘卡（时长走 `deleteTotalMs()`） | 列表页 |
| 启动时把参数从 preferences 搬进 AppStorage | Ability 的 `onCreate` |
| （可选）设置页滑杆 + 预览 | 设置页 |

---

## 2. 运行前提

| 项 | 要求 | 说明 |
| --- | --- | --- |
| ArkUI `Particle` 组件 | API 12+ | 粒子层本身只要 API 12；**是否启用粒子动效按 API 26+ 判定** |
| `ParticleUpdater.CURVE` / `ParticlePropertyAnimation` | API 12+ | 用曲线驱动透明度与缩放 |
| `animateTo` / `onAreaChange` / `Area` / `Length` | API 10+ | 外壳的动画与尺寸实测 |
| `AppStorage` + `@StorageProp` / `@StorageLink` | API 9+ | 参数下发；不需要设置页可整层去掉（见 §7.2 / §7.3） |
| 鸿蒙 7 判定 | `deviceInfo.sdkApiVersion >= 26` | 本仓库封装为 `SystemMaterial.isApi26OrAbove()`，移植时自己写三行即可 |

用到的 ArkUI 全局符号（无需 import）：`Particle`、`ParticleType`、`ParticleEmitterShape`、
`ParticleUpdater`、`Curve`、`Area`、`Length`、`HitTestMode`、`AppStorage`、`Slider`、
`SliderStyle`、`SliderChangeMode`、`Toggle`、`ToggleType`、`ItemAlign`、`TextAlign`、`VerticalAlign`。

---

## 3. 核心源码

### 3.1 `components/DeleteParticleBurst.ets` —— 粒子层

整个动效的主角：一个 `Particle` 组件，发射窗口铺满卡片，粒子从卡面随机位置冒出、
带随机初速与加速度向外飘、按曲线先亮后灭并缩小。

两个关键点：

1. 尺寸由调用方传入**实测数字**（`burstWidth` / `burstHeight`），不要用 `100%` / `matchParent`
   —— 它和卡片是兄弟节点、父 Stack 的尺寸由卡片撑出，百分比在这种「父尺寸待定」的场景里
   解析不到，粒子层会塌成 0 高、什么都画不出来（§8.3）。
2. 纯装饰层，必须 `hitTestBehavior(HitTestMode.None)`，否则会吃掉卡片的点击 / 长按。

```ets
import { DELETE_PARTICLE_DEFAULTS, DELETE_PARTICLE_PLAIN_COLOR } from '../storage/DeleteEffectPrefs';

/**
 * 卡片「粒子消散」层。
 *
 * 鸿蒙 7（API 26）在删除卡片时不是简单淡出，而是把卡片打成粒子再吹散，
 * 系统没有把这个动效开放成单一接口，这里用 ArkUI 的 `Particle` 组件复刻：
 * 发射窗口铺满整张卡片，粒子在卡面随机位置生成，带初速与加速度向外飘散，
 * 同时按曲线淡出、缩小。
 *
 * **只在 API 26+ 挂载它**（由调用方判断，见 `DeleteDissolve`）：
 * 低版本要的是「标准删除动画」，不能因为 Particle 组件本身从 API 12 就有
 * 就把粒子动效漏下去。
 *
 * 每个可调参数都走 `@StorageProp` 订阅 `DeleteEffectPrefs` 的键：
 * 「外观设置 → 粒子消散」里拖一下滑杆，这里立刻重建、按新参数重新发射，
 * 设置页的预览块就是这个数据流的第一现场。默认值统一取自
 * `DELETE_PARTICLE_DEFAULTS`，不在这里另写一套数字。
 *
 * 尺寸**必须由调用方传入实测数字**（vp），不要用 `100%` / `matchParent`：
 * 它和卡片是兄弟节点，卡片又是父 Stack 的尺寸来源，百分比 / matchParent
 * 在这种「父尺寸由兄弟撑出」的场景里解析不到，粒子层会塌成 0 高。
 */
@Component
export struct DeleteParticleBurst {
  /** 粒子颜色：跟随主题色时用这个（调用方传当前主题色） */
  @Prop burstColor: ResourceColor = '#0A59F7';
  /** 粒子层宽度（vp，来自卡片实测宽） */
  @Prop burstWidth: number = 0;
  /** 粒子层高度（vp，来自卡片实测高） */
  @Prop burstHeight: number = 0;

  // ---- 以下全部来自「外观设置 → 粒子消散」，不再有写死的观感 ----
  @StorageProp('deleteParticleFollowAccent') followAccent: boolean =
    DELETE_PARTICLE_DEFAULTS.followAccent;
  @StorageProp('deleteParticleRadius') particleRadius: number =
    DELETE_PARTICLE_DEFAULTS.radius;
  @StorageProp('deleteParticleCount') particleCount: number =
    DELETE_PARTICLE_DEFAULTS.count;
  @StorageProp('deleteParticleEmitRate') particleEmitRate: number =
    DELETE_PARTICLE_DEFAULTS.emitRate;
  @StorageProp('deleteParticleLifetime') particleLifetime: number =
    DELETE_PARTICLE_DEFAULTS.lifetime;
  @StorageProp('deleteParticleLifetimeRange') particleLifetimeRange: number =
    DELETE_PARTICLE_DEFAULTS.lifetimeRange;
  @StorageProp('deleteParticleSpeedMin') particleSpeedMin: number =
    DELETE_PARTICLE_DEFAULTS.speedMin;
  @StorageProp('deleteParticleSpeedMax') particleSpeedMax: number =
    DELETE_PARTICLE_DEFAULTS.speedMax;
  @StorageProp('deleteParticleAccelMin') particleAccelMin: number =
    DELETE_PARTICLE_DEFAULTS.accelMin;
  @StorageProp('deleteParticleAccelMax') particleAccelMax: number =
    DELETE_PARTICLE_DEFAULTS.accelMax;
  @StorageProp('deleteParticleScaleFrom') particleScaleFrom: number =
    DELETE_PARTICLE_DEFAULTS.scaleFrom;
  @StorageProp('deleteParticleScaleTo') particleScaleTo: number =
    DELETE_PARTICLE_DEFAULTS.scaleTo;
  @StorageProp('deleteParticleOpacity') particleOpacity: number =
    DELETE_PARTICLE_DEFAULTS.opacity;

  /** 实际用的颜色：不跟随主题色时固定白光，浅色卡面上可能偏淡（设置页有说明） */
  private burstTint(): ResourceColor {
    return this.followAccent ? this.burstColor : DELETE_PARTICLE_PLAIN_COLOR;
  }

  /** 初速区间：两个滑杆可能被拖成反的，这里兜一下，别把非法区间喂给 Particle */
  private speedMin(): number {
    return Math.min(this.particleSpeedMin, this.particleSpeedMax);
  }

  private speedMax(): number {
    return Math.max(this.particleSpeedMin, this.particleSpeedMax);
  }

  private accelMin(): number {
    return Math.min(this.particleAccelMin, this.particleAccelMax);
  }

  private accelMax(): number {
    return Math.max(this.particleAccelMin, this.particleAccelMax);
  }

  /** 生命周期上下界：抖动是双向的，写 walker 里避免出现负寿命 */
  private lifetimeFloor(): number {
    return Math.max(1, this.particleLifetime - this.particleLifetimeRange);
  }

  build() {
    Particle({
      particles: [
        {
          emitter: {
            particle: {
              type: ParticleType.POINT,
              // 半径默认 2.4vp：卡片尺度上大致是「碎成粉末」，也保证浅色卡面看得见
              config: { radius: this.particleRadius },
              count: Math.round(this.particleCount),
              lifetime: this.lifetimeFloor(),
              // 生命周期抖动：粒子分批消失，不会整片同时熄掉
              lifetimeRange: this.particleLifetimeRange
            },
            emitRate: Math.round(this.particleEmitRate),
            shape: ParticleEmitterShape.RECTANGLE,
            position: [0, 0],
            // 发射窗口铺满卡片：粒子从整个卡面冒出来，而不是从一个点喷出
            size: ['100%', '100%']
          },
          color: {
            range: [this.burstTint(), this.burstTint()]
          },
          opacity: {
            range: [this.particleOpacity, this.particleOpacity],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [
                // 先亮相，再整体淡出：纯淡出会像「渐隐」，先亮一下才有「炸开」的感觉
                {
                  from: 0.0,
                  to: this.particleOpacity,
                  startMillis: 0,
                  endMillis: 100,
                  curve: Curve.EaseIn
                },
                {
                  from: this.particleOpacity,
                  to: 0.0,
                  startMillis: 100,
                  endMillis: this.particleLifetime,
                  curve: Curve.EaseOut
                }
              ]
            }
          },
          scale: {
            range: [this.particleScaleFrom, this.particleScaleFrom],
            updater: {
              type: ParticleUpdater.CURVE,
              config: [
                {
                  from: this.particleScaleFrom,
                  to: this.particleScaleTo,
                  startMillis: 0,
                  endMillis: this.particleLifetime,
                  curve: Curve.EaseOut
                }
              ]
            }
          },
          velocity: {
            // 慢速起步、方向随机：粒子先「浮」起来再被吹散
            speed: [this.speedMin(), this.speedMax()],
            angle: [0, 360]
          },
          acceleration: {
            // 持续加速：越到后面飞得越快，收尾才干净
            speed: { range: [this.accelMin(), this.accelMax()] },
            angle: { range: [0, 360] }
          }
        }
      ]
    })
      // 显式数字尺寸：见文件头说明，百分比 / matchParent 在这个父 Stack 里解析不到
      .width(this.burstWidth)
      .height(this.burstHeight)
      // 纯装饰层：绝不能吃掉卡片上的点击/长按
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}

```

### 3.2 `components/DeleteDissolve.ets` —— 动效外壳

包住卡片，负责三件事：**卡片淡出 / 收缩**、**挂载粒子层**、**决定动画起手时机**。

结构是两层 Stack：

```text
Stack()                              // 外层：不参与淡出，只负责放粒子
├── Stack()                          // 内层：真正的卡片，删除时缩放 + 淡出
│     └── this.content()             // 调用方传进来的卡片
└── DeleteParticleBurst(...)         // 仅「需要粒子」且这张卡正在删除时挂载
```

- **为什么要一个外壳组件**（而不是让父组件改自己的 `@State`）：列表项在 `ForEach` 里，
  `ForEach` 对**键不变**的项会复用旧组件，父组件改一个没进键的状态时，卡片的
  `if` / `.opacity()` 未必重新求值 —— 粒子层不会挂上、淡出也不会播（§8.1）。
  把动效收进自治组件，并让调用方把「删除态」写进键，两条语义都覆盖。
- **为什么动画挂在第一次 `onAreaChange` 上**：组件刚建出来时节点还没以
  `scale=1 / opacity=1` 画过，在 `aboutToAppear` 里直接 `animateTo` 没有起始值可比，
  动画会被吃掉（表现就是卡片直接消失、粒子也没机会画）（§8.2）。
- **为什么粒子层在外层**：`.opacity()` 作用于整个子树，粒子若和卡片同层，
  会跟着一起被透明掉（§8.4）。

```ets
import { FeedbackLogService } from '../services/FeedbackLogService';
import { DELETE_PARTICLE_DEFAULTS, DELETE_STANDARD_TARGET_SCALE, deleteFadeMs }
  from '../storage/DeleteEffectPrefs';
import { DeleteParticleBurst } from './DeleteParticleBurst';

/**
 * 删除动效的外壳。
 *
 * 为什么不做成「父组件改 @State、卡片被动跟」：设备卡在 `ForEach` 里，
 * 而 `ForEach` 对**键不变**的项会复用旧组件（本仓库房间 chips / 设备卡的
 * accentColor 键注释都踩过这个坑）。父组件改一个没进键的状态，卡片的
 * `if`/`.opacity()` 未必重新求值，粒子层就不会挂上、淡出也不会播。
 *
 * 所以动效收进这个自治组件，两条路都能起效：
 *   1. 调用方把「删除态」写进 `ForEach` 的键 → 本组件被**重建**，
 *      首次布局回调里起动画；
 *   2. 键没变、组件被复用 → `dissolving` 变化触发 `@Watch`，同样起动画。
 *
 * 动画必须等**首帧带上初始值**再起：组件刚建出来时直接 `animateTo` 的话，
 * 节点还没以 scale=1 / opacity=1 画过，没有可动的起始值，动画会被吃掉
 * （表现就是卡片直接消失、粒子也没机会画），所以起手式挂在第一次
 * `onAreaChange` 上，再推一个宏任务等这帧落地。
 *
 * 粒子层单独放在**不参与淡出**的外层 Stack：`.opacity()` 作用于整个子树，
 * 粒子若和卡片同层，会跟着一起被透明掉。
 */
@Component
export struct DeleteDissolve {
  /** 是否处于删除态 */
  @Prop @Watch('onDissolvingChanged') dissolving: boolean = false;
  /** 是否叠加粒子消散（鸿蒙 7 / API 26+ 且外观设置里开着；否则只做缩放淡出） */
  @Prop particleEnabled: boolean = false;
  /** 粒子颜色：跟随主题色 */
  @Prop burstColor: ResourceColor = '#0A59F7';

  // ---- 时长与收缩比例来自「外观设置 → 粒子消散」，两档各取一套 ----
  /** 粒子档的淡出时长（毫秒） */
  @StorageProp('deleteParticleFadeMs') particleFadeMs: number =
    DELETE_PARTICLE_DEFAULTS.fadeMs;
  /** 粒子档结束时的缩放：默认几乎不动（粒子才是主角） */
  @StorageProp('deleteParticleTargetScale') particleTargetScale: number =
    DELETE_PARTICLE_DEFAULTS.targetScale;

  @BuilderParam content: () => void = this.emptyContent;

  @State contentScale: number = 1;
  @State contentOpacity: number = 1;
  /**
   * 卡片实测尺寸（vp）。
   *
   * 粒子层必须拿到**确定的数字**：它和卡片是兄弟节点，卡片又是这个 Stack 的
   * 尺寸来源，用 `100%` / `matchParent` 在这种「父尺寸由兄弟撑出」的场景里
   * 解析不到，粒子层会塌成 0 高、什么都不画。
   */
  @State layerWidth: number = 0;
  @State layerHeight: number = 0;
  /**
   * 起手式只允许跑一次：
   *   - 重建路径（ForEach 键带上删除态）→ 首次 onAreaChange；
   *   - 复用路径（键没变、组件被复用）→ dissolving 的 @Watch。
   */
  private started: boolean = false;
  private alive: boolean = true;

  @Builder
  emptyContent() {
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  onDissolvingChanged(): void {
    if (this.dissolving) {
      // 复用路径：组件早就以 scale=1 / opacity=1 渲染过，直接起动画即可
      this.startDissolve();
      return;
    }
    // 落回非删除态就复位。真实删除时这一步无关紧要（卡片马上被摘掉），
    // 但设置页的预览块是同一张卡反复播，不复位就只有第一次能动。
    this.started = false;
    this.contentScale = 1;
    this.contentOpacity = 1;
  }

  /** 这一次动效用多久 */
  private fadeMs(): number {
    return deleteFadeMs(this.particleEnabled, this.particleFadeMs);
  }

  /** 这一次动效收缩到多少：粒子档可调，标准档固定 */
  private targetScaleValue(): number {
    return this.particleEnabled ? this.particleTargetScale : DELETE_STANDARD_TARGET_SCALE;
  }

  /** 首次完成布局时调用：这一帧节点才真正带上 scale=1 / opacity=1 */
  private onLaidOut(dissolving: boolean): void {
    if (!dissolving || this.started) {
      return;
    }
    // 为什么不在 aboutToAppear 里起动画：那时节点还没建出来，没有 scale=1/opacity=1
    // 这个「起始值」，animateTo 会被吃掉（卡片直接消失、粒子也没机会画）。
    // 布局回调说明首帧已经带上初始值，再推一个宏任务等这帧落地，动画才有得可比。
    setTimeout((): void => {
      this.startDissolve();
    }, 0);
  }

  private startDissolve(): void {
    if (this.started || !this.alive || !this.dissolving) {
      return;
    }
    this.started = true;
    const ms: number = this.fadeMs();
    FeedbackLogService.recordOperation('UI',
      `删除动效: ${this.particleEnabled ? '粒子消散' : '标准缩放淡出'} ${ms}ms`);
    this.getUIContext().animateTo({
      duration: ms,
      curve: this.particleEnabled ? Curve.EaseInOut : Curve.FastOutSlowIn
    }, (): void => {
      this.contentScale = this.targetScaleValue();
      this.contentOpacity = 0;
    });
  }

  /**
   * Area 的宽高声明类型是 Length，真机上传的是 vp 数字，但字符串形式（`'384.00vp'`）
   * 也见过。粒子层要的是能算的数字，这里统一转一次，转不出来就回 0（宁可不画也不塌）。
   */
  private toVp(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed: number = Number.parseFloat(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  build() {
    Stack() {
      // 内层：真正的卡片，删除时缩放 + 淡出
      Stack() {
        this.content()
      }
      .width('100%')
      .scale({ x: this.contentScale, y: this.contentScale })
      .opacity(this.contentOpacity)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const w: number = this.toVp(newArea.width);
        const h: number = this.toVp(newArea.height);
        if (w > 0 && h > 0 && (w !== this.layerWidth || h !== this.layerHeight)) {
          this.layerWidth = w;
          this.layerHeight = h;
        }
        // 布局完成 = 节点已经带上初始的 scale/opacity，可以起删除动效了
        this.onLaidOut(this.dissolving);
      })

      // 外层：粒子层，不参与上面的淡出
      if (this.dissolving && this.particleEnabled && this.layerWidth > 0 && this.layerHeight > 0) {
        DeleteParticleBurst({
          burstColor: this.burstColor,
          burstWidth: this.layerWidth,
          burstHeight: this.layerHeight
        })
      }
    }
    .width('100%')
  }
}

```

### 3.3 `storage/DeleteEffectPrefs.ets` —— 参数层

参数键、默认值、滑杆区间、时长换算集中在这一个模块，**默认值只有一份**
（`DELETE_PARTICLE_DEFAULTS`）：组件字段初值与「恢复默认」的目标值都取它，
所以不存在「默认值和设置页对不上」。

> 移植提示：目标工程没有 preferences 落盘时，把 `publishDeleteEffectPrefs()` 换成
> 「直接用默认值 `AppStorage.setOrCreate(键, 默认值)`」，其余代码一行不用改（§7.3）。

```ets
import { AppSettingsStore } from './AppSettingsStore';

/**
 * 「删除卡片粒子消散」的全部可调参数。
 *
 * 为什么单开一个模块：这些值有**三个消费方**，必须共用一套键与一套默认值——
 *   - `DeleteParticleBurst` 画粒子时要读；
 *   - `DeleteDissolve` 要按「淡出时长 / 收缩比例」演卡片；
 *   - `HomePage` 要用同一个时长决定「动画播完多久再把卡片摘掉」。
 * 任何一处自己写死，都会出现「设置里改了、删除时没变」。
 *
 * 存取惯例与其它外观开关一致（见 AppearanceSettingsPage 的 setCardTint 等）：
 *   - `preferences`（`miha_settings`）是落盘的真身，键名与 AppStorage 键完全同名；
 *   - 启动时 `publishDeleteEffectPrefs()` 把落盘值搬进 AppStorage；
 *   - 组件用 `@StorageProp` / `@StorageLink` 订阅，设置页改一处、订阅方立刻重建。
 *
 * **不要在模块加载期读 AppSettingsStore**：那时 preferences 还没 init（本仓库
 * `check_ets.py` 的「模块级初始化」一项专门拦这个），所以这里只有常量和函数。
 */

// ---- 开关与颜色 ----

/** 删除卡片时是否播放粒子消散（仅在鸿蒙 7 / API 26+ 有意义） */
export const DELETE_PARTICLE_ENABLED_KEY: string = 'deleteParticleEnabled';
/** 粒子是否跟随主题色；关闭固定用白光 */
export const DELETE_PARTICLE_FOLLOW_ACCENT_KEY: string = 'deleteParticleFollowAccent';

// ---- 卡片侧（粒子档） ----

/** 卡片淡出时长（毫秒），粒子档专用；标准档固定 260ms */
export const DELETE_PARTICLE_FADE_KEY: string = 'deleteParticleFadeMs';
/** 淡出结束时卡片收缩到多少（1 = 不收缩，粒子才是主角） */
export const DELETE_PARTICLE_TARGET_SCALE_KEY: string = 'deleteParticleTargetScale';

// ---- 粒子侧 ----

/** 点粒子半径（vp） */
export const DELETE_PARTICLE_RADIUS_KEY: string = 'deleteParticleRadius';
/** 粒子数量上限 */
export const DELETE_PARTICLE_COUNT_KEY: string = 'deleteParticleCount';
/** 每秒发射粒子数 */
export const DELETE_PARTICLE_EMIT_RATE_KEY: string = 'deleteParticleEmitRate';
/** 单个粒子生命周期（毫秒） */
export const DELETE_PARTICLE_LIFETIME_KEY: string = 'deleteParticleLifetime';
/** 生命周期抖动（毫秒），让粒子分批消失 */
export const DELETE_PARTICLE_LIFETIME_RANGE_KEY: string = 'deleteParticleLifetimeRange';
/** 初速下限（vp/s） */
export const DELETE_PARTICLE_SPEED_MIN_KEY: string = 'deleteParticleSpeedMin';
/** 初速上限（vp/s） */
export const DELETE_PARTICLE_SPEED_MAX_KEY: string = 'deleteParticleSpeedMax';
/** 加速度下限（vp/s²） */
export const DELETE_PARTICLE_ACCEL_MIN_KEY: string = 'deleteParticleAccelMin';
/** 加速度上限（vp/s²） */
export const DELETE_PARTICLE_ACCEL_MAX_KEY: string = 'deleteParticleAccelMax';
/** 粒子起始缩放 */
export const DELETE_PARTICLE_SCALE_FROM_KEY: string = 'deleteParticleScaleFrom';
/** 粒子结束缩放 */
export const DELETE_PARTICLE_SCALE_TO_KEY: string = 'deleteParticleScaleTo';
/** 粒子峰值透明度（先亮一下再淡出的那个「亮」） */
export const DELETE_PARTICLE_OPACITY_KEY: string = 'deleteParticleOpacity';

/** 每个参数的取值范围与步长，设置页滑杆直接用（避免两处写不一致） */
export interface DeleteParticleRange {
  min: number;
  max: number;
  step: number;
}

export interface DeleteParticleRanges {
  fadeMs: DeleteParticleRange;
  targetScale: DeleteParticleRange;
  radius: DeleteParticleRange;
  count: DeleteParticleRange;
  emitRate: DeleteParticleRange;
  lifetime: DeleteParticleRange;
  lifetimeRange: DeleteParticleRange;
  speedMin: DeleteParticleRange;
  speedMax: DeleteParticleRange;
  accelMin: DeleteParticleRange;
  accelMax: DeleteParticleRange;
  scaleFrom: DeleteParticleRange;
  scaleTo: DeleteParticleRange;
  opacity: DeleteParticleRange;
}

export const DELETE_PARTICLE_RANGES: DeleteParticleRanges = {
  fadeMs: { min: 200, max: 1500, step: 20 },
  targetScale: { min: 0.5, max: 1, step: 0.02 },
  radius: { min: 0.5, max: 6, step: 0.1 },
  count: { min: 20, max: 600, step: 20 },
  emitRate: { min: 20, max: 1200, step: 20 },
  lifetime: { min: 100, max: 1500, step: 20 },
  lifetimeRange: { min: 0, max: 500, step: 10 },
  speedMin: { min: 0, max: 300, step: 10 },
  speedMax: { min: 0, max: 400, step: 10 },
  accelMin: { min: 0, max: 300, step: 10 },
  accelMax: { min: 0, max: 500, step: 10 },
  scaleFrom: { min: 0.2, max: 2, step: 0.05 },
  scaleTo: { min: 0.05, max: 1.5, step: 0.05 },
  opacity: { min: 0.1, max: 1, step: 0.05 }
};

/**
 * 出厂默认值 = 1.1.3 里调出来的那一套。
 * 改这里等于改「恢复默认」的目标，也等于改新装用户的观感。
 */
export interface DeleteParticleDefaults {
  enabled: boolean;
  followAccent: boolean;
  fadeMs: number;
  targetScale: number;
  radius: number;
  count: number;
  emitRate: number;
  lifetime: number;
  lifetimeRange: number;
  speedMin: number;
  speedMax: number;
  accelMin: number;
  accelMax: number;
  scaleFrom: number;
  scaleTo: number;
  opacity: number;
}

export const DELETE_PARTICLE_DEFAULTS: DeleteParticleDefaults = {
  enabled: true,
  followAccent: true,
  fadeMs: 620,
  targetScale: 0.94,
  radius: 2.4,
  count: 200,
  emitRate: 420,
  lifetime: 560,
  lifetimeRange: 140,
  speedMin: 30,
  speedMax: 170,
  accelMin: 0,
  accelMax: 150,
  scaleFrom: 1,
  scaleTo: 0.3,
  opacity: 1
};

/**
 * 标准删除动效（非鸿蒙 7）的淡出时长。刻意不开放：低版本没有粒子，
 * 这条路径要的是「系统感」，让用户调它没有意义。
 */
export const DELETE_FADE_STANDARD_MS: number = 260;
/**
 * 标准删除动效的收缩比例。同样不开放：低版本没有粒子，
 * 「缩小消失」是这条路径唯一的语义承载，调小了会显得没删掉。
 */
export const DELETE_STANDARD_TARGET_SCALE: number = 0.82;
/** 动效播完到真正摘卡之间的余量：留给起手等首帧、以及最后一帧落地 */
export const DELETE_SETTLE_MS: number = 80;

/** 粒子颜色不跟随主题色时的固定色（系统默认白光） */
export const DELETE_PARTICLE_PLAIN_COLOR: string = '#FFFFFF';

/** 把值夹进合法区间：滑杆范围可能随版本收窄，落盘的老值要能兜住 */
export function clampDeleteParticleValue(value: number, range: DeleteParticleRange): number {
  if (!Number.isFinite(value)) {
    return range.min;
  }
  return Math.min(range.max, Math.max(range.min, value));
}

/** 这一次删除实际用的淡出时长（毫秒） */
export function deleteFadeMs(particle: boolean, particleFadeMs: number): number {
  return particle ? Math.max(1, Math.round(particleFadeMs)) : DELETE_FADE_STANDARD_MS;
}

/**
 * 这一次删除「从起手到摘卡」的总时长。
 *
 * 动画与改数据之间必须隔这么久（见 docs/已删除卡片.md §2.3），
 * HomePage 与 DeleteDissolve 都从这里取，避免两边各写一套算式。
 */
export function deleteTotalMs(particle: boolean, particleFadeMs: number): number {
  return deleteFadeMs(particle, particleFadeMs) + DELETE_SETTLE_MS;
}

/**
 * 把落盘值搬进 AppStorage（启动时调一次）。
 *
 * 必须在首帧渲染前完成：卡片与粒子层都是**首帧就读**这些键，
 * 晚一步就会出现「第一次删除用的是默认参数」。
 */
export function publishDeleteEffectPrefs(): void {
  const d: DeleteParticleDefaults = DELETE_PARTICLE_DEFAULTS;
  AppStorage.setOrCreate(DELETE_PARTICLE_ENABLED_KEY,
    AppSettingsStore.getBoolean(DELETE_PARTICLE_ENABLED_KEY, d.enabled));
  AppStorage.setOrCreate(DELETE_PARTICLE_FOLLOW_ACCENT_KEY,
    AppSettingsStore.getBoolean(DELETE_PARTICLE_FOLLOW_ACCENT_KEY, d.followAccent));
  AppStorage.setOrCreate(DELETE_PARTICLE_FADE_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_FADE_KEY, d.fadeMs), DELETE_PARTICLE_RANGES.fadeMs));
  AppStorage.setOrCreate(DELETE_PARTICLE_TARGET_SCALE_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_TARGET_SCALE_KEY, d.targetScale),
      DELETE_PARTICLE_RANGES.targetScale));
  AppStorage.setOrCreate(DELETE_PARTICLE_RADIUS_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_RADIUS_KEY, d.radius), DELETE_PARTICLE_RANGES.radius));
  AppStorage.setOrCreate(DELETE_PARTICLE_COUNT_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_COUNT_KEY, d.count), DELETE_PARTICLE_RANGES.count));
  AppStorage.setOrCreate(DELETE_PARTICLE_EMIT_RATE_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_EMIT_RATE_KEY, d.emitRate),
      DELETE_PARTICLE_RANGES.emitRate));
  AppStorage.setOrCreate(DELETE_PARTICLE_LIFETIME_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_LIFETIME_KEY, d.lifetime),
      DELETE_PARTICLE_RANGES.lifetime));
  AppStorage.setOrCreate(DELETE_PARTICLE_LIFETIME_RANGE_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_LIFETIME_RANGE_KEY, d.lifetimeRange),
      DELETE_PARTICLE_RANGES.lifetimeRange));
  AppStorage.setOrCreate(DELETE_PARTICLE_SPEED_MIN_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_SPEED_MIN_KEY, d.speedMin),
      DELETE_PARTICLE_RANGES.speedMin));
  AppStorage.setOrCreate(DELETE_PARTICLE_SPEED_MAX_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_SPEED_MAX_KEY, d.speedMax),
      DELETE_PARTICLE_RANGES.speedMax));
  AppStorage.setOrCreate(DELETE_PARTICLE_ACCEL_MIN_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_ACCEL_MIN_KEY, d.accelMin),
      DELETE_PARTICLE_RANGES.accelMin));
  AppStorage.setOrCreate(DELETE_PARTICLE_ACCEL_MAX_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_ACCEL_MAX_KEY, d.accelMax),
      DELETE_PARTICLE_RANGES.accelMax));
  AppStorage.setOrCreate(DELETE_PARTICLE_SCALE_FROM_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_SCALE_FROM_KEY, d.scaleFrom),
      DELETE_PARTICLE_RANGES.scaleFrom));
  AppStorage.setOrCreate(DELETE_PARTICLE_SCALE_TO_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_SCALE_TO_KEY, d.scaleTo),
      DELETE_PARTICLE_RANGES.scaleTo));
  AppStorage.setOrCreate(DELETE_PARTICLE_OPACITY_KEY,
    clampDeleteParticleValue(
      AppSettingsStore.getNumber(DELETE_PARTICLE_OPACITY_KEY, d.opacity),
      DELETE_PARTICLE_RANGES.opacity));
}

/** 把某个数值参数写成「落盘 + 广播」：设置页滑杆与「恢复默认」共用 */
export function setDeleteParticleNumber(key: string, value: number, range: DeleteParticleRange): number {
  const clamped = clampDeleteParticleValue(value, range);
  AppSettingsStore.setNumber(key, clamped);
  AppStorage.setOrCreate(key, clamped);
  return clamped;
}

/** 同上，布尔档 */
export function setDeleteParticleBoolean(key: string, value: boolean): void {
  AppSettingsStore.setBoolean(key, value);
  AppStorage.setOrCreate(key, value);
}

/** 恢复默认：全部写回落盘并重新广播 */
export function resetDeleteEffectPrefs(): void {
  const d: DeleteParticleDefaults = DELETE_PARTICLE_DEFAULTS;
  setDeleteParticleBoolean(DELETE_PARTICLE_ENABLED_KEY, d.enabled);
  setDeleteParticleBoolean(DELETE_PARTICLE_FOLLOW_ACCENT_KEY, d.followAccent);
  setDeleteParticleNumber(DELETE_PARTICLE_FADE_KEY, d.fadeMs, DELETE_PARTICLE_RANGES.fadeMs);
  setDeleteParticleNumber(DELETE_PARTICLE_TARGET_SCALE_KEY, d.targetScale,
    DELETE_PARTICLE_RANGES.targetScale);
  setDeleteParticleNumber(DELETE_PARTICLE_RADIUS_KEY, d.radius, DELETE_PARTICLE_RANGES.radius);
  setDeleteParticleNumber(DELETE_PARTICLE_COUNT_KEY, d.count, DELETE_PARTICLE_RANGES.count);
  setDeleteParticleNumber(DELETE_PARTICLE_EMIT_RATE_KEY, d.emitRate,
    DELETE_PARTICLE_RANGES.emitRate);
  setDeleteParticleNumber(DELETE_PARTICLE_LIFETIME_KEY, d.lifetime,
    DELETE_PARTICLE_RANGES.lifetime);
  setDeleteParticleNumber(DELETE_PARTICLE_LIFETIME_RANGE_KEY, d.lifetimeRange,
    DELETE_PARTICLE_RANGES.lifetimeRange);
  setDeleteParticleNumber(DELETE_PARTICLE_SPEED_MIN_KEY, d.speedMin,
    DELETE_PARTICLE_RANGES.speedMin);
  setDeleteParticleNumber(DELETE_PARTICLE_SPEED_MAX_KEY, d.speedMax,
    DELETE_PARTICLE_RANGES.speedMax);
  setDeleteParticleNumber(DELETE_PARTICLE_ACCEL_MIN_KEY, d.accelMin,
    DELETE_PARTICLE_RANGES.accelMin);
  setDeleteParticleNumber(DELETE_PARTICLE_ACCEL_MAX_KEY, d.accelMax,
    DELETE_PARTICLE_RANGES.accelMax);
  setDeleteParticleNumber(DELETE_PARTICLE_SCALE_FROM_KEY, d.scaleFrom,
    DELETE_PARTICLE_RANGES.scaleFrom);
  setDeleteParticleNumber(DELETE_PARTICLE_SCALE_TO_KEY, d.scaleTo,
    DELETE_PARTICLE_RANGES.scaleTo);
  setDeleteParticleNumber(DELETE_PARTICLE_OPACITY_KEY, d.opacity,
    DELETE_PARTICLE_RANGES.opacity);
}

```

### 3.4 `components/ParticleParamRow.ets` —— 设置页的滑杆行（可选）

一行「名称 + 滑杆 + 当前值」。**它不是 `@Builder`，而是一个组件**，原因见 §8.15：
ArkUI 的 `@Builder` 按值传参时**没有响应式**，用它写参数行会出现
「拖滑杆时灰字读数不动、点恢复默认滑杆也不回位」——这是踩过的坑，不是理论问题。
组件化之后值通过 `@Prop` 从父级流入，父级重建 → 组件重建 → 读数与滑块位置都跟着走，
与仓库里设备详情页的 `PropertyControl` 是同一套做法。

不接设置页的移植可以不拷这个文件。

```ets
import { DeleteParticleRange, setDeleteParticleNumber } from '../storage/DeleteEffectPrefs';
import { HwColor, HwSpace } from '../utils/DesignTokens';

/**
 * 一行「名称 + 滑杆 + 当前值」，用于「外观设置 → 粒子消散」的参数调节。
 *
 * **为什么是 `@Component` 而不是页面里的 `@Builder`**：
 * ArkUI 的 `@Builder` **按值传参时不具备响应式** —— 官方文档明确写了
 * 「按值传递时，状态变量的改变不会引起 @Builder 方法内的 UI 刷新」。
 * 之前这一行就是 `@Builder particleParamRow(label, value, ...)`，
 * 症状正是「拖滑杆时灰字读数不动、点恢复默认滑杆也不回位」：
 * 写进 AppStorage 的值确实变了，页面也重建了，但**这个 builder 内部的
 * 滑块与读数不会跟着重算**。
 *
 * 换成组件后，值通过 `@Prop value` 从父级流入，父级重建 → 本组件重建 →
 * 读数与滑块位置都跟着走。这与仓库里设备详情页的 `PropertyControl` 是同一套做法
 * （它的滑杆行也是组件内 `this.value`，而不是 builder 入参）。
 *
 * 写回走 `setDeleteParticleNumber()`：夹区间 → 落盘 → 广播，一步都不少；
 * 松手（`SliderChangeMode.End` / `Click`）再通过 `onSettle` 通知页面播一次预览。
 */
@Component
export struct ParticleParamRow {
  /** 左侧名称 */
  @Prop label: string = '';
  /** 当前值（父级从 AppStorage 订阅后传入） */
  @Prop value: number = 0;
  @Prop rangeMin: number = 0;
  @Prop rangeMax: number = 1;
  @Prop step: number = 1;
  /** 读数保留几位小数（个数 / 速率这类整数参数传 0） */
  @Prop digits: number = 0;
  /** 读数单位，可为空串 */
  @Prop unit: string = '';
  /** AppStorage / preferences 里的键名 */
  storageKey: string = '';
  /** 松手回调：页面用它触发一次预览 */
  onSettle: () => void = (): void => {
  };

  // 字体跟随全局设置：组件不能调页面的 appFontFamily，按 PropertyControl 的做法自己订阅
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;

  private appFontFamily(content: string): string {
    if (this.fontMode !== 'custom') {
      return '';
    }
    const family = this.hasCjk(content) ? this.fontFamilyZh : this.fontFamilyEn;
    return family === 'system' || family.length === 0 ? '' : family;
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

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }

  /** 滑杆是浮点的，落盘前按小数位削掉尾巴（0.30000000000000004 这种） */
  private roundTo(value: number, digits: number): number {
    const factor: number = Math.pow(10, digits);
    return Math.round(value * factor) / factor;
  }

  build() {
    Row({ space: HwSpace.sm }) {
      Text(this.label)
        .fontFamily(this.appFontFamily(this.label))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontColor(HwColor.textPrimary)
        .width(84)
      Slider({
        value: this.value,
        min: this.rangeMin,
        max: this.rangeMax,
        step: this.step,
        style: SliderStyle.OutSet
      })
        .layoutWeight(1)
        .onChange((v: number, mode: SliderChangeMode): void => {
          const range: DeleteParticleRange = {
            min: this.rangeMin,
            max: this.rangeMax,
            step: this.step
          };
          setDeleteParticleNumber(this.storageKey, this.roundTo(v, this.digits), range);
          // 松手（含直接点轨道）才播预览：拖动过程中每帧都播会把动画一直按在开头
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.onSettle();
          }
        })
      // 固定列宽：'vp/s²' 这类单位比数字宽，不定宽会让各行右边缘参差不齐
      Text(`${this.roundTo(this.value, this.digits)}${this.unit}`)
        .fontFamily(this.appFontFamily(`${this.value}`))
        .fontWeight(this.appFontWeight())
        .fontSize(12)
        .fontColor(HwColor.textSecondary)
        .width(66)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
```

---

## 4. 接入：调用方要做什么

以本仓库首页设备卡为例。共六段代码。

### 4.1 （1）import

```ets
import { DELETE_PARTICLE_DEFAULTS, deleteTotalMs } from '../storage/DeleteEffectPrefs';
```

### 4.2 （2）时长说明

粒子的可调参数都搬进了 `DeleteEffectPrefs`，列表页只留一个换算入口。

```ets
/**
 * 删除卡片的动效时长现在由两部分组成，**全部在 `DeleteEffectPrefs` 里**：
 *   - 淡出多久、收缩到多少 → 外观设置里可调（粒子档），标准档固定；
 *   - 播完到摘卡之间再留一点余量，避免「粒子还在飞、卡片先没了」。
 * 换算统一走 `deleteTotalMs()`：这里与 `DeleteDissolve` 必须用同一个算式，
 * 各写一套就会出现「动画还没播完卡就没了」或「卡片空等一截」。
 */
```

### 4.3 （3）状态：正在消散的 id + 订阅开关与时长

只订阅「开关」与「淡出时长」两项 —— 其余粒子参数由粒子层自己订阅，
拖动「粒子半径」不该让整个列表页重建。

```ets
  // ---- 删除卡片：正在消散的 did ----
  /**
   * 正在播放删除动效的卡片 did。空串表示没有卡片在删。
   * 同一时刻只允许一张卡：动效期间的列表位移会让第二张卡的位置突然跳一下。
   *
   * 缩放/透明度不在这里：它们收在 DeleteDissolve 内部（自治组件），
   * 否则会踩到 ForEach 复用旧组件、父级状态改不动卡片的坑。
   */
  @State dissolvingDid: string = '';
  /**
   * 粒子消散开关与时长：订阅「外观设置 → 粒子消散」。
   * 只订阅这两个——其余粒子参数由 DeleteParticleBurst 自己订阅，
   * 首页不该因为「粒子半径」被拖动就重建整张卡片。
   */
  @StorageProp('deleteParticleEnabled') deleteParticleEnabled: boolean =
    DELETE_PARTICLE_DEFAULTS.enabled;
  @StorageProp('deleteParticleFadeMs') deleteParticleFadeMs: number =
    DELETE_PARTICLE_DEFAULTS.fadeMs;
```

### 4.4 （4）删除流程：置位 → 等动画 → 落库摘卡

顺序不能反：先移除列表项，卡片会在动画开始前就消失，只剩一块空白；
先落库也不行 —— 可见列表一变，`ForEach` 立刻拆掉这张卡（§8.5）。

```ets
  private particleEffectOn(): boolean {
    return isApi26OrAbove() && this.deleteParticleEnabled;
  }

  private deleteDeviceCard(device: XiaomiDevice): void {
    if (this.dissolvingDid.length > 0) {
      // 上一张还在消散：直接忽略，避免两张卡同时位移、动画互相打架
      return;
    }
    const displayName = this.homeDisplayName(device);
    const particle = this.particleEffectOn();
    // 置位即触发重排：ForEach 键里带上删除态，这张卡会被重建，
    // DeleteDissolve 在「首次布局回调」里起手动画（复用路径则由 @Watch 兜底）
    this.dissolvingDid = device.did;
    FeedbackLogService.recordOperation('UI',
      `删除设备卡片 ${displayName} (${device.did})，动效=${particle ? '粒子消散' : '标准删除'}`);

    this.cancelDeleteTimer();
    this.deleteTimer = setTimeout((): void => {
      this.deleteTimer = -1;
      if (!this.pageAlive) {
        return;
      }
      this.finishDeleteDeviceCard(device, displayName);
    }, deleteTotalMs(particle, this.deleteParticleFadeMs));
  }

  /** 动效收尾：写入删除记录、把卡片从列表摘掉，并提示恢复入口 */
  private finishDeleteDeviceCard(device: XiaomiDevice, displayName: string): void {
    const record: RemovedDeviceRecord = {
      did: device.did,
      name: displayName,
      model: device.model,
      roomName: device.roomName,
      homeId: device.homeId,
      removedAt: Date.now()
    };
    DeviceRemovalStore.removeWithRecord(record);

    // 只重算「过滤后的可见列表」，**不要动 allHomeDevices**：
    // 它是本次本地移除过滤之前的底表，留着这台设备，恢复时才能不联网就把它放回列表。
    this.allVisibleDevices = DeviceRemovalStore.filter(this.allHomeDevices);

    // 先让数据生效，再清 dissolvingDid：同一批状态更新里卡片已被移除，
    // 不会出现「动画复位后卡片又闪一下」。
    this.applyDeviceVisibility();
    this.dissolvingDid = '';
    this.removedCardCount = DeviceRemovalStore.load().length;
    // 本页自己已经改完了列表，不用广播：这里不再 bump 版本号，
    // 免得白跑一次 @Watch 重算（其它页面由「已删除卡片」页与设备管理页各自负责）。
    this.getUIContext().getPromptAction().showToast({
      message: `已删除「${displayName}」，可在「我的 > 已删除卡片」中恢复`
    });
  }
```

### 4.5 （5）列表项：卡片外面套一层外壳

```ets
    DeleteDissolve({
      dissolving: this.dissolvingDid === device.did,
      // 粒子档的时长与收缩比例由 DeleteDissolve 自己读外观设置，这里只要给档位
      particleEnabled: this.particleEffectOn(),
      burstColor: this.accent()
    }) {
```

### 4.6 （6）`ForEach` 的键必须带上「是否正在删除」

这是整条动效最容易漏、也最致命的一步（§8.1）。

```ets
        // key 里必须带上 accentColor：ForEach 复用同 key 的项，键不变就不会重建卡片，
        // 卡内写死的 HwColor.primary（图标、快捷开关）在切主题色后会停在旧色。
        //
        // 也要带上「是否正在删除」：删除动效的缩放/粒子层挂在卡片上，
        // 若键不变、ForEach 复用旧组件，动效不会重新求值（见 DeleteDissolve 文件头）。
        // 让键在删除开始时变化，这张卡被重建，DeleteDissolve 才会起手动画。
        ForEach(this.filteredDevices, (device: XiaomiDevice) => {
          this.deviceCard(device)
        }, (device: XiaomiDevice) =>
        `${device.did}_${this.favoriteDevices.indexOf(device.did) >= 0 ? 1 : 0}_${this.accentColor}`
          + `_${this.dissolvingDid === device.did ? 'del' : 'idle'}`)
```

### 4.7 启动时发布参数（Ability `onCreate`）

必须在**首帧渲染前**把参数搬进 AppStorage：卡片与粒子层都是首帧就读这些键，
晚一步就会出现「第一次删除用的是默认参数」。注意 `publishDeleteEffectPrefs()` 内部会读
preferences，所以只能在偏好存储 `init()` **之后**调用，不能在模块加载期调用（§8.10）。

```ets
import { publishDeleteEffectPrefs } from '../storage/DeleteEffectPrefs';
import { loadCustomFonts } from '../utils/CustomFonts';
import { applyAppTheme, CARD_GLOW_TOUCH_STORAGE, CARD_TINT_STORAGE, CUSTOM_ACCENT_FULL_ACCESS_STORAGE, DARK_MODE_DARK, DARK_MODE_LIGHT, DARK_MODE_PREF_STORAGE, DARK_MODE_SYSTEM, DEFAULT_ACCENT_KEY, isPresetAccentKey, PRESS_GLOW_STORAGE, resolveAccentColor } from '../utils/DesignTokens';
```

```ets
    // 删除卡片粒子消散的全部可调参数：同样首帧就要读（首页设备卡与粒子层都订阅它们），
    // 晚一步就会出现「第一次删除用的是默认参数」
    publishDeleteEffectPrefs();
```

### 4.8 设置页（可选）

**（1）import 与状态订阅**：16 个参数各一个 `@StorageLink`。滑杆需要「改完立刻回到自己身上」，
而 `@StorageLink` 是双向的，写入 AppStorage 的同时订阅方（粒子层）也重建。

```ets
import { DELETE_PARTICLE_ACCEL_MAX_KEY, DELETE_PARTICLE_ACCEL_MIN_KEY,
  DELETE_PARTICLE_COUNT_KEY, DELETE_PARTICLE_DEFAULTS, DELETE_PARTICLE_EMIT_RATE_KEY,
  DELETE_PARTICLE_ENABLED_KEY, DELETE_PARTICLE_FADE_KEY, DELETE_PARTICLE_FOLLOW_ACCENT_KEY,
  DELETE_PARTICLE_LIFETIME_KEY, DELETE_PARTICLE_LIFETIME_RANGE_KEY,
  DELETE_PARTICLE_OPACITY_KEY, DELETE_PARTICLE_RADIUS_KEY, DELETE_PARTICLE_RANGES,
  DELETE_PARTICLE_SCALE_FROM_KEY, DELETE_PARTICLE_SCALE_TO_KEY,
  DELETE_PARTICLE_SPEED_MAX_KEY, DELETE_PARTICLE_SPEED_MIN_KEY,
  DELETE_PARTICLE_TARGET_SCALE_KEY, DeleteParticleRange, deleteTotalMs,
  resetDeleteEffectPrefs, setDeleteParticleBoolean, setDeleteParticleNumber,
  } from '../storage/DeleteEffectPrefs';
```

```ets
  // ---- 删除卡片粒子消散：全部参数都可在本页调整（仅鸿蒙 7 生效） ----
  // 每一个都用 @StorageLink 订阅：滑动条需要「改完立刻回到自己身上」，
  // 而 @StorageLink 是双向的，写入 AppStorage 的同时订阅方（粒子层）也重建。
  // 键名与 storage/DeleteEffectPrefs.ets 里的 *_KEY 常量一致——装饰器参数
  // 必须是字面量，不能用常量拼接，改键时两边都要动。
  @StorageLink('deleteParticleEnabled') deleteParticleEnabled: boolean =
    DELETE_PARTICLE_DEFAULTS.enabled;
  @StorageLink('deleteParticleFollowAccent') deleteParticleFollowAccent: boolean =
    DELETE_PARTICLE_DEFAULTS.followAccent;
  @StorageLink('deleteParticleFadeMs') deleteParticleFadeMs: number =
    DELETE_PARTICLE_DEFAULTS.fadeMs;
  @StorageLink('deleteParticleTargetScale') deleteParticleTargetScale: number =
    DELETE_PARTICLE_DEFAULTS.targetScale;
  @StorageLink('deleteParticleRadius') deleteParticleRadius: number =
    DELETE_PARTICLE_DEFAULTS.radius;
  @StorageLink('deleteParticleCount') deleteParticleCount: number =
    DELETE_PARTICLE_DEFAULTS.count;
  @StorageLink('deleteParticleEmitRate') deleteParticleEmitRate: number =
    DELETE_PARTICLE_DEFAULTS.emitRate;
  @StorageLink('deleteParticleLifetime') deleteParticleLifetime: number =
    DELETE_PARTICLE_DEFAULTS.lifetime;
  @StorageLink('deleteParticleLifetimeRange') deleteParticleLifetimeRange: number =
    DELETE_PARTICLE_DEFAULTS.lifetimeRange;
  @StorageLink('deleteParticleSpeedMin') deleteParticleSpeedMin: number =
    DELETE_PARTICLE_DEFAULTS.speedMin;
  @StorageLink('deleteParticleSpeedMax') deleteParticleSpeedMax: number =
    DELETE_PARTICLE_DEFAULTS.speedMax;
  @StorageLink('deleteParticleAccelMin') deleteParticleAccelMin: number =
    DELETE_PARTICLE_DEFAULTS.accelMin;
  @StorageLink('deleteParticleAccelMax') deleteParticleAccelMax: number =
    DELETE_PARTICLE_DEFAULTS.accelMax;
  @StorageLink('deleteParticleScaleFrom') deleteParticleScaleFrom: number =
    DELETE_PARTICLE_DEFAULTS.scaleFrom;
  @StorageLink('deleteParticleScaleTo') deleteParticleScaleTo: number =
    DELETE_PARTICLE_DEFAULTS.scaleTo;
  @StorageLink('deleteParticleOpacity') deleteParticleOpacity: number =
    DELETE_PARTICLE_DEFAULTS.opacity;

  /** 预览块是否正在播放（喂给 DeleteDissolve 的 dissolving） */
  @State previewDissolving: boolean = false;
  /**
   * 两张「调数字」的卡片是否展开。
   *
   * 默认收起：16 个滑杆铺开有近千 vp，把上面的总开关与预览块挤到屏幕外，
   * 而多数人只调其中一两个值。收起态把当前取值写进副标题，不展开也知道现状。
   * 刻意不落盘：这是「临时看一眼」的展开态，不是设置项。
   */
  @State cardParamsExpanded: boolean = false;
  @State particleParamsExpanded: boolean = false;
  /** 预览结束定时器 */
  private previewTimer: number = -1;
  /** 重播定时器：见 previewParticle 的「正在播就重来一次」分支 */
  private previewRestartTimer: number = -1;
```

**（2）落值与预览**：拖滑杆每次都「落盘 + 广播」，松手（`SliderChangeMode.End` / `Click`）
自动播一次预览；「正在播就重来一次」要先落回非删除态再拉起（§8.12）。

```ets
  // ==================== 删除卡片粒子消散 ====================

  /**
   * 滑杆落值：夹区间 → 落盘 → 广播。
   *
   * 落盘与广播都在 `setDeleteParticleNumber` 里，这里只多做两件事：
   * 按步长把浮点尾巴削掉（0.30000000000000004 这种值写进 preferences 只会脏数据），
   * 以及把「个数 / 速率」这类必须是整数的参数取整。
   */
  private setParticleNumber(storageKey: string, value: number, range: DeleteParticleRange,
                            digits: number): void {
    setDeleteParticleNumber(storageKey, this.roundTo(value, digits), range);
  }

  /** 开关档：两个开关都只是行为开关，不需要重算任何颜色 token */
  private setParticleEnabled(enabled: boolean): void {
    setDeleteParticleBoolean(DELETE_PARTICLE_ENABLED_KEY, enabled);
    FeedbackLogService.recordOperation('UI', `粒子消散 ${enabled ? '开' : '关'}`);
  }

  private setParticleFollowAccent(enabled: boolean): void {
    setDeleteParticleBoolean(DELETE_PARTICLE_FOLLOW_ACCENT_KEY, enabled);
    FeedbackLogService.recordOperation('UI', `粒子跟随主题色 ${enabled ? '开' : '关'}`);
  }

  /** 按小数位取整，避免滑杆的浮点尾巴落盘 */
  private roundTo(value: number, digits: number): number {
    const factor: number = Math.pow(10, digits);
    return Math.round(value * factor) / factor;
  }

  /**
   * 恢复默认：全部参数写回 `DELETE_PARTICLE_DEFAULTS`。
   * 只改本页自己的参数，不动主题色 / 字体等其它外观项。
   */
  private resetParticlePrefs(): void {
    resetDeleteEffectPrefs();
    FeedbackLogService.recordOperation('UI', '粒子消散参数恢复默认');
    this.getUIContext().getPromptAction().showToast({ message: '粒子消散参数已恢复默认' });
  }

  /**
   * 播放一次预览。
   *
   * 走的是和首页删除**同一套**组件与配置（`DeleteDissolve` + 同一批 AppStorage 键），
   * 所以这里看到什么，删除卡片时就是什么——预览不是另画一份示意动画。
   * 时长按 `deleteTotalMs()` 算，与首页「多久后摘卡」是同一个算式。
   */
  private previewParticle(): void {
    const particle: boolean = isApi26OrAbove() && this.deleteParticleEnabled;
    const total: number = deleteTotalMs(particle, this.deleteParticleFadeMs);
    this.clearPreviewTimers();
    if (!this.previewDissolving) {
      this.startPreviewWindow(total);
      return;
    }
    // 正在播就重来一次：拖完一个滑杆松手、动画还没结束就又拖下一个，
    // 直接忽略的话会让人以为「这个参数改了没反应」。
    // 注意必须先落到非删除态：DeleteDissolve 只在 dissolving 由 false 变 true 时才起手，
    // 同一个状态批里 false→true 会被合并成「没变化」，动画不会重播。
    this.previewDissolving = false;
    this.previewRestartTimer = setTimeout((): void => {
      this.previewRestartTimer = -1;
      this.startPreviewWindow(total);
    }, 0);
  }

  private startPreviewWindow(total: number): void {
    this.previewDissolving = true;
    this.previewTimer = setTimeout((): void => {
      this.previewTimer = -1;
      this.previewDissolving = false;
    }, total);
  }

  private clearPreviewTimers(): void {
    if (this.previewTimer >= 0) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    if (this.previewRestartTimer >= 0) {
      clearTimeout(this.previewRestartTimer);
      this.previewRestartTimer = -1;
    }
  }
```

**（3）页面退出清理 + 折叠头**：参数行本身就是组件（§3.4），页面这边只需要
「一行标签 + 一个 `ParticleParamRow`」，以及一个可点的折叠头。

两张「调数字」的卡默认收起：14 个滑杆铺开有近千 vp，会把总开关与预览块挤出屏幕。
折叠态把当前取值写进副标题，不展开也知道现状；展开态刻意不落盘（它是「临时看一眼」）。

**折叠头只挂在那一行 `Row` 上，卡片本体不挂 `cardOnClick`** ——
否则拖滑杆会被冒泡成「点卡片」，一碰就收起。

```ets
  aboutToDisappear(): void {
    // 预览定时器必须清掉：页面销毁后回调里再 setState 会打到一个没了的组件上
    this.clearPreviewTimers();
  }
```

```ets
                // 折叠头：只有这一行可点，卡片本体不挂 cardOnClick——
                // 否则拖滑杆会被冒泡成「点卡片」，一碰就收起。
                Row({ space: HwSpace.sm }) {
                  Column({ space: 4 }) {
                    Text('粒子消散 · 卡片')
                      .fontFamily(this.appFontFamily('粒子消散 · 卡片'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(this.cardParamsExpanded
                      ? '卡片这一侧的动作：多久淡出、收到多小'
                      : `淡出 ${this.deleteParticleFadeMs}ms · 收缩 ${this.deleteParticleTargetScale}x`)
                      .fontFamily(this.appFontFamily('粒子消散 · 卡片'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  // 展开态用 chevron 旋转表达：arrow_up_arrow_down 在部分 SDK 上不存在
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([HwColor.textSecondary])
                    .rotate({ angle: this.cardParamsExpanded ? 90 : 0 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.cardParamsExpanded = !this.cardParamsExpanded;
                })
```

**（4）三张卡：总开关与预览 / 卡片 / 粒子**。预览块用的就是 `DeleteDissolve` **本体**
和同一批 AppStorage 键 —— 预览里什么样，删除卡片时就是什么样，不是另画的示意图。

```ets
            // 粒子动效的两个「大件」：卡片本身的时长/收缩，以及粒子的形状参数。
            // 与上面的总开关拆成两张卡：开关是「用不用」，这里是「长什么样」。
            //
            // 两张卡默认**收起**：14 个滑杆铺开有近千 vp，会把上面的总开关与预览块
            // 挤到屏幕外，而多数人只调其中一两个值。收起态把当前取值写进副标题，
            // 不展开也知道现状。展开态刻意不落盘——它是「临时看一眼」，不是设置项。
            if (isApi26OrAbove()) {
              MaterialCard({
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: HwSpace.md,
                cardAlignItems: ItemAlign.Start
              }) {
                // 折叠头：只有这一行可点，卡片本体不挂 cardOnClick——
                // 否则拖滑杆会被冒泡成「点卡片」，一碰就收起。
                Row({ space: HwSpace.sm }) {
                  Column({ space: 4 }) {
                    Text('粒子消散 · 卡片')
                      .fontFamily(this.appFontFamily('粒子消散 · 卡片'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(this.cardParamsExpanded
                      ? '卡片这一侧的动作：多久淡出、收到多小'
                      : `淡出 ${this.deleteParticleFadeMs}ms · 收缩 ${this.deleteParticleTargetScale}x`)
                      .fontFamily(this.appFontFamily('粒子消散 · 卡片'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  // 展开态用 chevron 旋转表达：arrow_up_arrow_down 在部分 SDK 上不存在
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([HwColor.textSecondary])
                    .rotate({ angle: this.cardParamsExpanded ? 90 : 0 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.cardParamsExpanded = !this.cardParamsExpanded;
                })

                if (this.cardParamsExpanded) {
                  Divider()
                    .color('#14000000')

                  ParticleParamRow({
                    label: '淡出时长',
                    value: this.deleteParticleFadeMs,
                    rangeMin: DELETE_PARTICLE_RANGES.fadeMs.min,
                    rangeMax: DELETE_PARTICLE_RANGES.fadeMs.max,
                    step: DELETE_PARTICLE_RANGES.fadeMs.step,
                    digits: 0,
                    unit: 'ms',
                    storageKey: DELETE_PARTICLE_FADE_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '收缩比例',
                    value: this.deleteParticleTargetScale,
                    rangeMin: DELETE_PARTICLE_RANGES.targetScale.min,
                    rangeMax: DELETE_PARTICLE_RANGES.targetScale.max,
                    step: DELETE_PARTICLE_RANGES.targetScale.step,
                    digits: 2,
                    unit: 'x',
                    storageKey: DELETE_PARTICLE_TARGET_SCALE_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                }
              }
            }

            if (isApi26OrAbove()) {
              MaterialCard({
                cardPadding: HwSpace.lg,
                cardRadius: HwRadius.card,
                cardSpace: HwSpace.md,
                cardAlignItems: ItemAlign.Start
              }) {
                Row({ space: HwSpace.sm }) {
                  Column({ space: 4 }) {
                    Text('粒子消散 · 粒子')
                      .fontFamily(this.appFontFamily('粒子消散 · 粒子'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(15)
                      .fontColor(HwColor.textPrimary)
                    Text(this.particleParamsExpanded
                      ? '半径与数量决定「碎成什么样」，速度与加速度决定「吹得多散」'
                      : `半径 ${this.deleteParticleRadius}vp · 数量 ${this.deleteParticleCount} · 速率 ${this.deleteParticleEmitRate}/s · 寿命 ${this.deleteParticleLifetime}ms`)
                      .fontFamily(this.appFontFamily('粒子消散 · 粒子'))
                      .fontWeight(this.appFontWeight())
                      .fontSize(12)
                      .fontColor(HwColor.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([HwColor.textSecondary])
                    .rotate({ angle: this.particleParamsExpanded ? 90 : 0 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.particleParamsExpanded = !this.particleParamsExpanded;
                })

                if (this.particleParamsExpanded) {
                  Divider()
                    .color('#14000000')

                  ParticleParamRow({
                    label: '粒子半径',
                    value: this.deleteParticleRadius,
                    rangeMin: DELETE_PARTICLE_RANGES.radius.min,
                    rangeMax: DELETE_PARTICLE_RANGES.radius.max,
                    step: DELETE_PARTICLE_RANGES.radius.step,
                    digits: 1,
                    unit: 'vp',
                    storageKey: DELETE_PARTICLE_RADIUS_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '粒子数量',
                    value: this.deleteParticleCount,
                    rangeMin: DELETE_PARTICLE_RANGES.count.min,
                    rangeMax: DELETE_PARTICLE_RANGES.count.max,
                    step: DELETE_PARTICLE_RANGES.count.step,
                    digits: 0,
                    unit: '',
                    storageKey: DELETE_PARTICLE_COUNT_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '发射速率',
                    value: this.deleteParticleEmitRate,
                    rangeMin: DELETE_PARTICLE_RANGES.emitRate.min,
                    rangeMax: DELETE_PARTICLE_RANGES.emitRate.max,
                    step: DELETE_PARTICLE_RANGES.emitRate.step,
                    digits: 0,
                    unit: '/s',
                    storageKey: DELETE_PARTICLE_EMIT_RATE_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '生命周期',
                    value: this.deleteParticleLifetime,
                    rangeMin: DELETE_PARTICLE_RANGES.lifetime.min,
                    rangeMax: DELETE_PARTICLE_RANGES.lifetime.max,
                    step: DELETE_PARTICLE_RANGES.lifetime.step,
                    digits: 0,
                    unit: 'ms',
                    storageKey: DELETE_PARTICLE_LIFETIME_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '寿命抖动',
                    value: this.deleteParticleLifetimeRange,
                    rangeMin: DELETE_PARTICLE_RANGES.lifetimeRange.min,
                    rangeMax: DELETE_PARTICLE_RANGES.lifetimeRange.max,
                    step: DELETE_PARTICLE_RANGES.lifetimeRange.step,
                    digits: 0,
                    unit: 'ms',
                    storageKey: DELETE_PARTICLE_LIFETIME_RANGE_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '初速下限',
                    value: this.deleteParticleSpeedMin,
                    rangeMin: DELETE_PARTICLE_RANGES.speedMin.min,
                    rangeMax: DELETE_PARTICLE_RANGES.speedMin.max,
                    step: DELETE_PARTICLE_RANGES.speedMin.step,
                    digits: 0,
                    unit: 'vp/s',
                    storageKey: DELETE_PARTICLE_SPEED_MIN_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '初速上限',
                    value: this.deleteParticleSpeedMax,
                    rangeMin: DELETE_PARTICLE_RANGES.speedMax.min,
                    rangeMax: DELETE_PARTICLE_RANGES.speedMax.max,
                    step: DELETE_PARTICLE_RANGES.speedMax.step,
                    digits: 0,
                    unit: 'vp/s',
                    storageKey: DELETE_PARTICLE_SPEED_MAX_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '加速下限',
                    value: this.deleteParticleAccelMin,
                    rangeMin: DELETE_PARTICLE_RANGES.accelMin.min,
                    rangeMax: DELETE_PARTICLE_RANGES.accelMin.max,
                    step: DELETE_PARTICLE_RANGES.accelMin.step,
                    digits: 0,
                    unit: 'vp/s²',
                    storageKey: DELETE_PARTICLE_ACCEL_MIN_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '加速上限',
                    value: this.deleteParticleAccelMax,
                    rangeMin: DELETE_PARTICLE_RANGES.accelMax.min,
                    rangeMax: DELETE_PARTICLE_RANGES.accelMax.max,
                    step: DELETE_PARTICLE_RANGES.accelMax.step,
                    digits: 0,
                    unit: 'vp/s²',
                    storageKey: DELETE_PARTICLE_ACCEL_MAX_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '起始缩放',
                    value: this.deleteParticleScaleFrom,
                    rangeMin: DELETE_PARTICLE_RANGES.scaleFrom.min,
                    rangeMax: DELETE_PARTICLE_RANGES.scaleFrom.max,
                    step: DELETE_PARTICLE_RANGES.scaleFrom.step,
                    digits: 2,
                    unit: 'x',
                    storageKey: DELETE_PARTICLE_SCALE_FROM_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '结束缩放',
                    value: this.deleteParticleScaleTo,
                    rangeMin: DELETE_PARTICLE_RANGES.scaleTo.min,
                    rangeMax: DELETE_PARTICLE_RANGES.scaleTo.max,
                    step: DELETE_PARTICLE_RANGES.scaleTo.step,
                    digits: 2,
                    unit: 'x',
                    storageKey: DELETE_PARTICLE_SCALE_TO_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })
                  ParticleParamRow({
                    label: '峰值透明度',
                    value: this.deleteParticleOpacity,
                    rangeMin: DELETE_PARTICLE_RANGES.opacity.min,
                    rangeMax: DELETE_PARTICLE_RANGES.opacity.max,
                    step: DELETE_PARTICLE_RANGES.opacity.step,
                    digits: 2,
                    unit: '',
                    storageKey: DELETE_PARTICLE_OPACITY_KEY,
                    onSettle: (): void => {
                      this.previewParticle();
                    }
                  })

                  Text('提示：生命周期明显长于淡出时长时，粒子会被「摘卡」提前截断；把两者调成接近的一对最自然。初速/加速的上限小于下限时会自动对调。')
                    .fontFamily(this.appFontFamily('提示'))
                    .fontWeight(this.appFontWeight())
                    .fontSize(11)
                    .fontColor(HwColor.textSecondary)
                    .width('100%')
                }
              }
            }
```

---

## 5. 参数总表

| 参数 | 键 | 默认 | 区间 | 步长 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 删除时播放粒子消散 | `deleteParticleEnabled` | 开 | 开/关 | — | 关掉走标准删除动效 |
| 粒子跟随主题色 | `deleteParticleFollowAccent` | 开 | 开/关 | — | 关掉固定白光 `#FFFFFF` |
| 淡出时长 | `deleteParticleFadeMs` | 620ms | 200–1500 | 20 | 卡片淡出多久；也是摘卡时机的基数 |
| 收缩比例 | `deleteParticleTargetScale` | 0.94x | 0.5–1.0 | 0.02 | 1 = 完全不缩，粒子才是主角 |
| 粒子半径 | `deleteParticleRadius` | 2.4vp | 0.5–6 | 0.1 | 太细会在浅色卡面上看不见 |
| 粒子数量 | `deleteParticleCount` | 200 | 20–600 | 20 | 同时存在的粒子上限（取整） |
| 发射速率 | `deleteParticleEmitRate` | 420/s | 20–1200 | 20 | 每秒生成多少（取整） |
| 生命周期 | `deleteParticleLifetime` | 560ms | 100–1500 | 20 | 单颗粒子活多久 |
| 寿命抖动 | `deleteParticleLifetimeRange` | 140ms | 0–500 | 10 | 让粒子分批消失，不会整片同熄 |
| 初速下限 / 上限 | `deleteParticleSpeedMin` / `deleteParticleSpeedMax` | 30 / 170 vp/s | 0–300 / 0–400 | 10 | 拖反了自动对调 |
| 加速下限 / 上限 | `deleteParticleAccelMin` / `deleteParticleAccelMax` | 0 / 150 vp/s² | 0–300 / 0–500 | 10 | 同上 |
| 起始 / 结束缩放 | `deleteParticleScaleFrom` / `deleteParticleScaleTo` | 1.0x / 0.3x | 0.2–2 / 0.05–1.5 | 0.05 | 粒子由大变小 |
| 峰值透明度 | `deleteParticleOpacity` | 1.0 | 0.1–1 | 0.05 | 「先亮一下再淡出」的那个亮 |

**刻意不开放的**：发射形状 / 发射窗口 / 粒子类型 / 角度范围（它们是这条动效的**结构**：
矩形满卡发射、点粒子、360° 随机），以及低版本的淡出时长与收缩比例
（没有粒子时「缩小消失」是唯一的语义承载）。

调参经验：**生命周期明显长于淡出时长时，粒子会被「摘卡」提前截断**，
把两者调成接近的一对最自然。

---

## 6. 想改观感时改哪里

| 想要的效果 | 改哪里 |
| --- | --- |
| 粒子更密 / 更疏 | `count`、`emitRate` |
| 粒子更大 / 更小 | `radius`、`scaleFrom` / `scaleTo` |
| 吹得更散 / 更收敛 | `speedMax`、`accelMax` |
| 停留更久 | `lifetime`、`fadeMs`（一起调） |
| 更「炸」还是更「飘」 | `opacity`（峰值越高越像炸开）、`accelMin`（起步慢＝飘） |
| 卡片几乎不动 | `targetScale` → 1 |
| 整条动效关掉 | `deleteParticleEnabled` → 关 |

---

## 7. 移植步骤

### 7.1 从零到跑起来（最小闭环）

1. 拷三个文件进目标工程（路径随意，记得改 import 相对路径）：
   - `components/DeleteParticleBurst.ets`（粒子层，必需）
   - `components/DeleteDissolve.ets`（动效外壳，必需）
   - `storage/DeleteEffectPrefs.ets`（参数层，必需）
   - `components/ParticleParamRow.ets`（滑杆行，只有做设置页才需要）
2. 把 `DeleteEffectPrefs` 里对 `AppSettingsStore` 的依赖换成目标工程的偏好存储；
   没有偏好存储就删掉落盘，只留 `AppStorage.setOrCreate(键, 默认值)`
   （即把 `publishDeleteEffectPrefs()` 改成全用默认值写一遍）。
3. 在 Ability 的 `onCreate` 里、**首帧之前**调用一次 `publishDeleteEffectPrefs()`。
4. 把列表项的卡片包进 `DeleteDissolve`，`particleEnabled` 传 `isApi26OrAbove() && 开关`。
5. 删除时置位「正在删除的 id」，**并把它写进 `ForEach` 的键**；
   延时 `deleteTotalMs()` 后再落库、摘卡。
6. 自测：触发删除 → 卡片淡出 + 粒子炸开 → 卡片被摘掉、后面的卡上移。
   日志里应看到 `删除动效: 粒子消散 620ms`（或标准档）。

### 7.2 只想要粒子，不想要设置页

把 `DeleteParticleBurst` 里的 13 个 `@StorageProp` 换成普通字段即可，例如
`@StorageProp('deleteParticleRadius') particleRadius: number = DELETE_PARTICLE_DEFAULTS.radius;`
换成 `private particleRadius: number = 2.4;`，然后删掉对 `DeleteEffectPrefs` 的 import。
`DeleteDissolve` 同理（`fadeMs` 直接写 620、`targetScale` 写 0.94）。
设置页那一段整块跳过，列表页把 `deleteTotalMs(particle, 620)` 的第二个参数写成常量。

### 7.3 用别的参数下发方式

`DeleteParticleBurst` 只认「这些键在 AppStorage 里」这一件事。也可以：

- 用 `@Prop` 从调用方传（注意 `@Prop` 变化会重建 `Particle`，会重新发射一次）；
- 用目标工程自己的全局配置对象 + `@StorageLink`；
- 或者直接把参数写在组件字段里（§7.2）。

---

## 8. 踩坑清单（每条都是实际踩过的）

### 8.1 `ForEach` 键不变 → 动效整个不生效（最致命）

- **现象**：点删除后卡片呆一下直接被摘掉，既没有淡出也没有粒子。
- **原因**：卡片在 `ForEach` 里，键是「id + 收藏态 + 主题色」。删除态没进键，
  `ForEach` 复用旧组件，卡片的 `if` / `.opacity()` 不会重新求值，粒子层根本没挂上。
- **解法**：把删除态写进键（`..._${dissolving ? 'del' : 'idle'}`，见 §4.6），
  让这张卡在删除开始时**被重建**；外壳同时用 `@Watch` 兜底，两种 `ForEach` 语义都覆盖。
- **副作用**：卡片会在删除瞬间被销毁重建，卡片内部状态（如高亮）会重置 ——
  只在删除态切换时发生，无感。

### 8.2 动画起手太早 → 没有起始值，动画被吃掉

- **现象**：卡片直接消失 / 直接透明，没有过渡；或粒子一闪而过。
- **原因**：在 `aboutToAppear` 里 `animateTo` 时节点还没建出来，
  没有 `scale=1 / opacity=1` 这个「起始值」可比。
- **解法**：起手式挂在**第一次 `onAreaChange`**（说明首帧已带上初始值）上，
  再推一个宏任务（`setTimeout(..., 0)`）等这帧落地，然后才 `animateTo`。
- **状态复位**：`dissolving` 落回 false 时把 `contentScale` / `contentOpacity` / `started`
  复位，否则同一个组件第二次删（或设置页预览重播）不会动。

### 8.3 粒子层塌成 0 高 → 什么都画不出来

- **现象**：淡出正常，但完全没有粒子。
- **原因**：粒子层与卡片是兄弟节点，父 Stack 的尺寸由卡片撑出；
  `width('100%')` / `LayoutPolicy.matchParent` 在这种「父尺寸待定」的场景里解析不到。
- **解法**：在卡片外层 `onAreaChange` 量出实测宽高（vp），**以数字**传给粒子层；
  `Area` 的宽高声明类型是 `Length`，做一次 `number` / 字符串兼容转换更稳。
- **连带**：量不到数字时宁可不挂粒子层，也不要退回百分比（会得到 0 高，白费）。

### 8.4 淡出把粒子一起透明掉

- **现象**：粒子「应该有」但看不见，或只看到卡片在淡。
- **原因**：`.opacity()` 作用于整个子树；粒子若和卡片同层，会跟着一起淡。
- **解法**：两层 Stack —— 内层卡片淡出 / 缩放，外层只放粒子（§3.2）。

### 8.5 摘卡时机错位

- **A**：先摘卡 → 动画还没开始卡片就没了，只剩空白。
- **B**：先落库 → 可见列表一变，`ForEach` 立刻拆卡，同样看不到动画。
- **C**：动画 620ms、摘卡也 620ms → 最后一帧被截断，像「卡走了粒子还在」。
- **解法**：动画与改数据之间隔一个总时长，且**总时长只有一个算式**
  （`deleteTotalMs() = 淡出 + 80ms 余量`），列表页与外壳共用，别各写一套。

### 8.6 同时删两张卡 → 列表位移跳动

同一时刻只允许一张卡在动效中（用一个「正在删除的 id」做闸，非空即忽略后续请求），
否则第一张卡还没摘掉、第二张也开始缩，两张卡的位置会互相挤。

### 8.7 自定义组件的成员名不能叫 `scale` / `opacity`

- **现象**：编译报
  `Property 'scale' in type 'X' is not assignable to the same property in base type 'CustomComponent'`。
- **原因**：`scale` / `opacity` 等名称与 `CustomComponent` 基类成员冲突。
- **解法**：改名成 `contentScale` / `contentOpacity` 之类。

### 8.8 `.scale()` 只接受 `ScaleOptions`

`.scale(0.94)` 编译不过，要写成 `.scale({ x: v, y: v })`。

### 8.9 装饰器参数必须是字符串字面量

`@StorageProp('key')` / `@StorageLink('key')` 的键写**字面量**。用常量虽然能编过，
但运行时解析出的键名不可验证（可能解析成变量名），会出现「设置页改了、动效没变」
这种极难排查的问题。键名与 `DeleteEffectPrefs` 里的 `*_KEY` 常量保持一一对应。

### 8.10 参数落盘的时机

- **不能在模块加载期读 preferences**（那时还没 `init`）——只能在 Ability `onCreate` 里发布。
- 滑杆 `onChange` 每次都「落盘 + 广播」：不广播订阅方不会重建，不落盘重启就丢。
- 数值落盘前按步长取整（`0.30000000000000004` 这种尾巴写进 preferences 只会脏数据），
  `count` / `emitRate` 必须是整数。

### 8.11 组件卸载要清定时器

摘卡延时、预览结束、预览重播三个定时器都要在 `aboutToDisappear` / 页面退出时清掉，
否则回调里的 `setState` 会打到一个已经销毁的组件上。

### 8.12 预览重播要先复位

`DeleteDissolve` 只在 `dissolving` **由 false 变 true** 时才起手。
同一个状态批里 `false → true` 会被合并成「没变化」，动画不会重播 ——
所以「正在播就重来一次」要先落回 false、下个宏任务再拉起。

### 8.13 `Particle` 的参数范围与合法性

- `count` / `emitRate` 传整数。
- 生命周期抖动是**双向**的：`lifetime` 要减去 `lifetimeRange` 作为下限，别喂出负数。
- 速度 / 加速度的上下限被拖反时自动对调，不要直接把非法区间交给 `Particle`。
- `radius` 单位是 vp；默认 2.4vp 是「碎成粉末」与「浅色卡面看得见」之间的折中。

### 8.14 一个工具误报（本仓库特有，移植可忽略）

`scripts/check_ets.py` 的「组件参数」检查会把组件入参里的**裸标识符 + 冒号**
误认成参数名（例如 `fadeDuration: cond ? A : B` 里的 `A :`）。
规避办法是把三元表达式用括号包起来（括号内的不算顶层键）。

### 8.15 `@Builder` 按值传参没有响应式（设置页滑杆读数不动的元凶）

- **现象**：拖滑杆时旁边的灰字读数不动；点「恢复默认」滑杆也不回位。
  AppStorage 里的值其实**已经变了**（粒子动效用的就是新值），只是那一行 UI 没重算。
- **原因**：ArkUI 官方文档明确写了——`@Builder` **按值传递**参数时，
  「状态变量的改变不会引起 @Builder 方法内的 UI 刷新」。写成
  `@Builder particleParamRow(label: string, value: number, ...)` 就正好踩中：
  父级重建了、AppStorage 也广播了，但这个 builder 内部不会重算。
- **解法**：把这一行做成 `@Component`（§3.4），值用 `@Prop` 从父级流入，父级重建即刷新。
  实测佐证：同一张卡上的两个 `Toggle` 是直接读 `this.xxx` 的，一直正常；
  出问题的只有走 builder 入参的那 14 行。
- **另一个可行解**：官方推荐的「按引用传递」——builder 只收**一个对象字面量**参数
  （`this.row({ value: this.x, ... })`），此时状态变化会引起 builder 内 UI 刷新。
  本仓库选了组件方案，因为它与 `PropertyControl` 一致、也不需要记住这条特例。
- **顺带**：仓库里 `ForEach` 的键里塞满状态（`accentColor`、选中态、`_del/_idle`）
  也是同一个坑的另一种绕法——键变了才会重建，builder 才会重跑。

---

## 9. 验收清单（真机）

1. 鸿蒙 7 上触发删除：卡片轻微收拢淡出，同时**整个卡面**炸出粒子向外飘散。
2. 日志两条：`删除设备卡片 X (did)，动效=粒子消散` 与 `删除动效: 粒子消散 620ms`。
   若第一条是「标准删除」，说明 `deviceInfo.sdkApiVersion` 没到 26，与渲染无关。
3. 动效结束后卡片被摘掉、后面的卡平滑上移，无空白、无重叠。
4. 非鸿蒙 7 设备 / 关掉开关：只有缩放淡出，没有粒子，时长 260ms。
5. 设置页：**拖动滑杆时右侧读数实时跟着变**；松手后预览块立刻按新参数播一次。
   读数不实时更新＝又踩了 §8.15（`@Builder` 按值传参无响应式）。
6. 设置页：两张「调数字」的卡默认收起，点标题行展开 / 再点收起；
   收起态的副标题显示当前取值。「恢复默认」后滑杆位置、读数与副标题**同时**回默认值。
7. 杀进程重进：设置页滑杆位置与之前一致（落盘生效）。
8. 连点两次删除：第二次被忽略，不会出现两张卡同时位移。

---

## 10. 随附源码快照：`docs/sample.tar.gz`

与本文档一起放在 `docs/` 下的 `docs/sample.tar.gz`，是本次「删除卡片（粒子消散 + 已删除卡片页）」
全部改动的**源码快照**，内容就是工作区的当前文件（与 git 历史无关，不需要 checkout 任何分支）。
工具误报、踩坑清单这些「知识」在本文档里，压缩包里则是可直接落地的代码。

```bash
# 只看内容（不落地）
tar -tzf docs/sample.tar.gz

# 解到临时目录翻看 / 对比
mkdir -p /tmp/miha-sample && tar -xzf docs/sample.tar.gz -C /tmp/miha-sample

# 直接套到另一个工程：包内是**仓库相对路径**，解包即落位
tar -xzf docs/sample.tar.gz -C /path/to/your-project
```

### 10.1 包内清单

包内路径与仓库一致（`entry/src/main/ets/...`）。「新增」= 本功能新写的文件，
「改动」= 为了接上本功能而动过的既有文件。

| 文件 | 状态 | 作用 |
| --- | --- | --- |
| `entry/src/main/ets/components/DeleteParticleBurst.ets` | 新增 | 粒子层（一个 `Particle`，§3.1） |
| `entry/src/main/ets/components/DeleteDissolve.ets` | 新增 | 动效外壳：卡片淡出 + 挂粒子 + 起手时机（§3.2） |
| `entry/src/main/ets/components/ParticleParamRow.ets` | 新增 | 设置页的滑杆行组件（§3.4） |
| `entry/src/main/ets/storage/DeleteEffectPrefs.ets` | 新增 | 参数键 / 默认值 / 区间 / 时长换算（§3.3） |
| `entry/src/main/ets/pages/DeletedCardsPage.ets` | 新增 | 「我的 > 已删除卡片」页：单张恢复 / 全部恢复 |
| `entry/src/main/ets/pages/HomePage.ets` | 改动 | 删除流程、`DeleteDissolve` 接入、`ForEach` 键、已删除卡片入口 |
| `entry/src/main/ets/pages/AppearanceSettingsPage.ets` | 改动 | 外观设置里的总开关、预览、两张折叠参数卡 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 改动 | 启动时把参数从 preferences 发布到 AppStorage |
| `entry/src/main/ets/storage/DeviceRemovalStore.ets` | 改动 | 删除记录落盘（did 清单 + 展示信息）、恢复、过滤 |
| `entry/src/main/ets/pages/DeviceManagePage.ets` | 改动 | 设备管理页的删除也留档（与首页同源） |
| `entry/src/main/ets/models/NavRouteParams.ets` | 改动 | `DeletedCardsRouteParam` 路由参数 |
| `entry/src/main/resources/base/profile/route_map.json` | 改动 | 注册 `deletedCards` 路由 |
| `README.md` | 改动 | 功能说明与文档索引 |
| `docs/已删除卡片.md` | 新增 | 本仓库里这条功能的落地说明（业务侧） |
| `docs/DeleteParticleBurst.md` | 新增 | 本文档（包内是打包那一刻的快照） |

**包里刻意不含的两样**：

- `AppScope/app.json5`：工作区里它有一处 `versionCode` 本地改动，与动效无关，不属于本次改动；
- 签名物料与 `/build-profile.json5`：见仓库 `.gitignore`，本来就不入库。

### 10.2 只想要动效时怎么取

压缩包里大部分是**业务接线**（删除记录、恢复页、路由）。真正常驻的只有四个文件，按 §7.1 做即可：

```text
components/DeleteParticleBurst.ets     必需
components/DeleteDissolve.ets          必需
storage/DeleteEffectPrefs.ets          必需（§7.2 可去掉 preferences 依赖）
components/ParticleParamRow.ets        仅做设置页时需要
```

### 10.3 重新打包

文档更新后要同步包内快照，重新执行（`docs/sample.tar.gz` 自身不在列表里，避免自引用）：

```bash
tar --no-mac-metadata -czf docs/sample.tar.gz \
  README.md \
  docs/DeleteParticleBurst.md \
  docs/已删除卡片.md \
  entry/src/main/ets/components/DeleteDissolve.ets \
  entry/src/main/ets/components/DeleteParticleBurst.ets \
  entry/src/main/ets/components/ParticleParamRow.ets \
  entry/src/main/ets/entryability/EntryAbility.ets \
  entry/src/main/ets/models/NavRouteParams.ets \
  entry/src/main/ets/pages/AppearanceSettingsPage.ets \
  entry/src/main/ets/pages/DeletedCardsPage.ets \
  entry/src/main/ets/pages/DeviceManagePage.ets \
  entry/src/main/ets/pages/HomePage.ets \
  entry/src/main/ets/storage/DeleteEffectPrefs.ets \
  entry/src/main/ets/storage/DeviceRemovalStore.ets \
  entry/src/main/resources/base/profile/route_map.json
```

`--no-mac-metadata` 是 macOS 自带 bsdtar 的参数，用来避免把 `._*` 扩展属性写进包；
GNU tar 没有这个参数，若在 Linux 上重打，改成 `tar --exclude='._*' -czf ...` 即可。

> 包内源码是 GPL-3.0-or-later（见文首「许可提醒」），移植义务照旧。
> 包里的 `.ets` 是仓库原文件，**带完整 GPL 版权头**；只有本文档内嵌的代码片段为省篇幅省略了头部，
> 别把「文档里没有头部」误当成「代码可以不带头部」。

