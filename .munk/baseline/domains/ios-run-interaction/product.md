# Domain: ios-run-interaction

跑步页的「交互接线」子域：把上游已冻结的会话契约（`RunStartCountdown` / `prepareFinish`+`saveFinished`+`discard` / `RunLocationReadiness`）接到视图，并把展示决策收敛为单一纯值真源 `RunInteractionPlan`。视图只按 plan 渲染（不再各自 `switch` controls / 提示 / 恢复动作），因此「每态唯一主操作、无断头路、提示单条、恢复两态、动效取 token」全部能在 L1 断言。状态机、文案键与门禁脚本一律不改；三个主操作的 identifier 按门禁「冻结 33 项只增不改」契约补齐（规则正本见域 `design-token-gates`）。

## 范围

- `ios/PurePace/Run/RunInteractionPlan.swift`（新增）：`struct RunInteractionPlan: Equatable` 纯值类型，由 `(state, isCountingDown, countdownText, didSave, hasError, hasDecisionError, readiness, hasBackgroundDegradation, metrics, reduceMotion)` 派生；暴露 `items`（`Action` × `Emphasis`，仅既有 8 动作）、`countdownText`、`showsMetrics`、`notice`、`recovery`、`transitionDuration`、`metrics`（5 个文本字段）；附 `init(viewModel:reduceMotion:)` 便捷构造。不含 View / 闭包 / ViewBuilder，不持有文案。
- `ios/PurePace/Run/RunView.swift`：控制区、提示层、恢复入口全部改为 plan 驱动；倒计时态底部由描边次操作改为填充主操作「取消」（同一锚点、同一高度），读数仍留在提示层不覆盖 hero/指标卡；状态与 `didSave` 变化用 `.animation` 配合 `DesignTokens.Motion.duration(_:reduceMotion:)`，`reduceMotion` 取自 `@Environment(\.accessibilityReduceMotion)`。
- `ios/PurePaceTests/RunInteractionPlanTests.swift`（新增）：XCTest（禁 `import Testing`），穷举 6 个展示状态 × `reduceMotion` 两值，含 primary 缺失/重复、破坏性升格、reduceMotion 下时长非 0 的反例。
- `ios/PurePace/Design/TabBarVisibilityPolicy.swift`（新增）：纯判定 `hidesTabBar(state:didSave:)` / `expectedTabBarCount(state:didSave:)` / `evaluate(state:didSave:observedTabBarCount:)`；输入只有 `RunSessionState` + `didSave`，输出期望 Tab 数（隐藏 0 / 可见 1）与问题串，实测数量由调用方注入。
- `ios/PurePace/ContentView.swift`：三 Tab 容器按 `TabBarVisibilityPolicy` 显式 `.toolbar(.hidden/.visible, for: .tabBar)`；Tab 数量、顺序、`tabItem` 标识与既有 `onChange` 接线不变。
- `ios/PurePace/Run/RunView.swift`：`.backgroundDegraded` 提示由整行 warning 胶囊改为指标卡后的紧凑 `caption` 次级行（`Colors.secondary` 前景，无胶囊底、无整宽弱底），identifier 与文案不变。
- `ios/PurePaceTests/TabBarVisibilityPolicyTests.swift`（新增）：L1 单测，覆盖 running/paused 与 `finished && !didSave` 隐藏、`ready` 与已保存恢复，含 2 个判红反例。
- `ios/PurePaceUITests/RunFlowUITests.swift`：各态实测 `tabBars.count` 与「跑步/历史/设置」三按钮存在性并打印 `ac-tabbar-hidden`；记录态 Tab 收起时主操作锚定改用「窗口底边扣除 Home Indicator 安全区」等价锚点；降级提示 frame 断言（`hint.minY > run.distance.maxY`）。
- `ios/project.yml`：`TabBarVisibilityPolicy.swift` 列入 `PurePaceUITests` sources，并为 UITests 显式声明 `PurePaceRunCore` 包依赖；工程仍由 XcodeGen 重新生成。

## 验收

- ac-plan-single-primary: 对 6 个展示状态（ready 空闲 / ready 倒计时 / running / paused / finished 待决策 / finished 已保存）断言 `items` 恰含 1 个 `primary`；映射为 ready 空闲=start、倒计时=cancelCountdown、running=pause、paused=resume、待决策=save、已保存=viewHistory（反例：倒计时主操作判为 secondary 必须判红）。
- ac-plan-no-dead-end: 每个状态 `items` 非空且至少含一个离开该态的动作（start/cancelCountdown/pause/resume/finish/save/discard/viewHistory）；不存在「只有提示没有动作」的状态（反例判红）。
- ac-plan-destructive-secondary: 结束类动作（running/paused 的 finish、待决策的 discard）恒为 `secondary` 且不等于同状态唯一 `primary`；待决策态同时存在 save(primary) 与 discard(secondary)。
- ac-countdown-visible-metrics: 倒计时态 `countdownText` 非 nil（取 VM 读数）、`showsMetrics == true`，5 组指标文本仍由 plan 暴露且与进入倒计时前逐项一致——倒计时不以覆盖方式遮挡主信息。
- ac-notice-priority: 同屏只出一条提示，优先级固定 记录错误 > 决策失败 > 定位状态（拒绝/不可用/等待授权）> 后台降级；`decisionErrorMessage != nil` 时 `notice == decisionFailed`，且 items 仍为 save+discard、指标文本非空（失败不吞已完成数据）。
- ac-recovery-two-actions: `denied` → `recovery == openSettings` 且 `notice == locationDenied`；`restricted` → `recovery == retryLocation` 且 `notice == locationUnavailable`；两者互不相等；`authorizedWhenInUse`/`authorizedAlways` → `recovery == nil`；recovery 仅在 `state == ready` 且非倒计时且非已保存时出现，running/paused/finished 恒为 nil。
- ac-motion-token-reduce-motion: `transitionDuration` 在 reduceMotion == true 时恒为 `DesignTokens.Motion.reducedMotionDuration`（0），false 时等于 `DesignTokens.Motion.durationState`；plan 内无任何时长数字字面量（反例：硬编码 0.32 判红）。
- ac-identifiers-append-only: 既有 33 项可及 identifier 逐项不变（不改名 / 不删除）；倒计时取消、结束保存、结束丢弃三个主操作分别带 `run.cancelCountdown` / `run.save` / `run.discard` 且 `accessibilityLabel` 为非空 `L10n` 键，仓库 identifier 总数 36（冻结 33 + 新增 3）；其余控件（去设置 / 重试）只带 `L10n` 可读 label。
- ac-gates-green: `.munk/code-gates.json` 全部 22 门退 0，`lint-ios-shell`（含 `--self-test` ≥84 项）、`test-ios --unit-only`（≥199 例）、`test-ios-run-core`（≥152 例）无退化；新增用例纯增量，无 sleep / 真实时钟 / 网络 / 模拟器。
- ac-l10n-and-tokens-only: 受管 UI 面（含新 plan 文件）零字面色值、零散字体修饰符、零动效时长字面量；本项不新增 `Localizable.xcstrings` 键，视图文案全部来自既有 `L10n`。
- ac-tabbar-hidden-recording: 记录态（`running` 与 `paused` 均实测）`XCUIApplication().tabBars.count == 0`，且「跑步 / 历史 / 设置」三个 Tab 按钮均不可见、不可点；`run.pause` / `run.resume` 仍可点，距离与用时继续增长。
- ac-tabbar-hidden-finished-pending: 结束待保存态（`finished && !didSave`）`tabBars.count == 0` 且无 Tab 按钮，`run.save` 与 `run.discard` 均可达。
- ac-tabbar-restore-no-deadend: 同一进程内保存或丢弃后回到 idle / 保存总结态时 `tabBars.count == 1` 且三 Tab 可点，再经历史、设置回到跑步页 TabBar 始终可见可点；全程不重新 launch，不存在只能杀进程脱困的断头路。
- ac-tabbar-red-proof: Tab 数量判定是由可注入实测数量驱动、不依赖 UI 的纯函数（期望值：记录态/待保存态 = 0，其余 = 1）；单测至少两个反例真实判红——记录态喂 `tabBarCount=1`、idle 喂 `tabBarCount=0`；反例只喂不同输入，不得靠改 `ios/PurePace/**` 生产代码才变红。
- ac-permission-banner-demoted: `WhenInUse` 降级态下后台定位提示不再是指标列上的整行 warning 胶囊，而以 `caption` 字号渲染为指标卡内的紧凑次级行（无 `Capsule` 底、无整宽弱底）；`run.backgroundDegraded` identifier 与文案不变，其 frame `minY` 大于 `run.distance` frame `maxY`（机器证明不压在距离 hero 上，也不插在 hero 与指标卡之间）。
- ac-primary-action-anchor-equivalent: TabBar 收起后主操作锚定断言改为「距窗口底边（扣除 Home Indicator 安全区）」，`PrimaryActionLayoutPolicy` 的 44 / 24 阈值与单测零改动，断言不得删除；idle / 已保存仍用 TabBar frame 原锚点。`RunLayoutBalancePolicy` 四阈值（`maximumTopGap/maximumBottomGap/maximumGap = 80`、`maximumImbalance = 16`）源码零改动。
- ac-uitest-target-wiring: 新纯判定被 UITests 复用时显式列入 `PurePaceUITests` sources 并在该 target 声明 `PurePaceRunCore` 依赖，`xcodegen generate --spec project.yml` 可重复生成；`.xcodeproj` 已 gitignore，diff 不含工程文件。

## 非目标

- 不改 `RunCore` 任何契约：`RunSessionState` 仍 4 态、`RunSessionMachine` 迁移仍 5 条、`RunStartCountdown` / `RunSessionOrchestrator` / 归档 / checkpoint / GPX / `RunRecord` 零改动。
- 不改 `L10n.swift` 与 `Localizable.xcstrings`（零新增键、零改文案）；不改 `DesignTokens.swift` / `ContrastPolicy.swift` 取值。
- 不改 `scripts/**`、`.munk/code-gates.json`、`ios/project.yml`、CI、`android/`、`shared/`、`VERSION`。
- 不改 History / Settings 页面与文案；不新增 Tab、屏、路由或 App 级状态。
- 不改 `RunFlowUITests` / 既有 UI 用例断言；不重做 Run 三态五层视觉与指标三行结构（仅补倒计时主操作填充与动效接线）。
- 不做截图归档、不做真机或模拟器观感验收：可达可退由 L1 钉住，屏幕观感 `pending: 待人现场`。
- 不动任何颜色 / 字号 / 间距 token 取值（三套色板待人拍板）；Tab 收起与提示降级只复用既有 `Typography.caption` / `Colors.secondary`，零 token 改动。
- 不改错误类提示（`recordingError` / `decisionFailed`）与定位拒绝 / 不可用提示的渲染位置与样式，只调 `.backgroundDegraded`；`notice` 优先级语义不变。
- 不改 `RunSessionState` / `RunSessionMachine` / `RunSessionViewModel` / `RunLocationSource` / 音频 / 持久化 / 归档 / GPX 契约。
- 不改历史页、设置页、详情页视觉，不做地图 / `TrackMapView` / 结束总结 / 分段明细；不新增 Tab、屏或路由。
- 不新增、不改名、不删除任何 `accessibilityIdentifier`，不新增本地化键，不做任何分发动作。

## 实现约束

- identifier 冲突裁决（已解除）：本域落地时 PRD 写「只增不改」而门禁是 33 项等值、且禁改脚本，故当时收窄为**集合 33 项完全不变**；门禁随后改为「冻结 33 项只增不改 + 必需新增 + 计数下限」，本域三主操作 identifier 现由门禁必需清单钉住，旧裁决作废。
- `RunView` 门禁锚点原文保留：`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }`；继续使用 `DesignTokens.minTapTarget` 与底部 `safeAreaInset`；等宽数字处数不少于 3；`run.backgroundDegraded` 标识与 DEBUG `run.telemetry` 覆盖层行为不变。
- 倒计时仍由视图 `.task(id: viewModel.isCountingDown)` 驱动 `advanceCountdown()`，不引入真实计时器；倒计时态与 start 共用同一锚点与高度，使每态恰一个填充主操作。
- 动效只允许 `withAnimation` / `.animation(_:value:)` 配 `DesignTokens.Motion.duration(...)`；`reduceMotion` 由 SwiftUI 环境取，不用 `UIAccessibility` 单例；时长归零即无动画，不做额外补偿。
- `Run/` 目录被门禁按目录纳入受管面：plan 文件内不得出现字面色值 / 字体修饰符 / 时长数字 / 裸英文文案。
- 测试纪律：XCTest，`@testable import PurePace`；只断言展示决策，不重复 VM 层已有转移断言；反例必须判红。
- 基线不回退：`test-ios --unit-only` ≥199 例、`test-ios-run-core` ≥152 例、`check-ios-shell --self-test` ≥91 项。
- Tab 收起口径：隐藏必须让 tab 栏从可及树消失（`tabBars.count == 0`），不得只做视觉遮挡；判定只读 `runModel.state` + `didSave`，**禁**重建 `RunSessionViewModel`、重新 `launch`、重走 `onAppear`（`onAppear` 会 `locationSource.start()`，可能重启采样或重复计数）；`.toolbar(_:for: .tabBar)` 必须同时写隐藏分支与显式恢复分支。
- 锚定断言适配边界：TabBar 收起时只允许把 UI 辅助改成「距窗口底边扣除 Home Indicator 安全区」的等价检查，不得删除断言、不得放宽 `PrimaryActionLayoutPolicy` 阈值或单测；死白断言 `RunLayoutBalancePolicy` 属硬约束，源码与阈值零改动，重排后 hero→提示、提示→主操作之间不得出现 >80pt 新空洞（|top − bottom| ≤16）。
- 提示分区单一决策：提示数据仍由 `RunInteractionPlan` 决定，只改 `.backgroundDegraded` 的渲染位置与样式，不改 VM 行为与 `notice` 优先级。
- 工程真源：`ios/project.yml` 手工新增文件必须同步（纯判定被 UITests 复用按既有 `VisibleTextPolicy` 做法显式列入 `PurePaceUITests` sources），再 `xcodegen generate --spec project.yml`；禁手改 `project.pbxproj`。

## 最近交付证明

- workItemId: wi_intake_c1a670784196dbd8（2026-11-11，pass）
- 交付：记录态（`running` / `paused`）与结束待保存态（`finished && !didSave`）收起底部三 Tab，`ready` / 保存总结 / 历史 / 设置显式恢复；判定收在新增纯函数 `TabBarVisibilityPolicy`（期望 Tab 数 0/1 + `evaluate` 注入实测值），`ContentView` 只按 `.toolbar(.hidden/.visible, for: .tabBar)` 两分支落地，不重建 ViewModel、不重走 `onAppear`。`RunView` 的 `.backgroundDegraded` 提示由整行 warning 胶囊降为指标卡后的 `caption` 次级行（`Colors.secondary`，无胶囊底/整宽弱底），identifier 与文案不变。`RunFlowUITests` 增加逐态 `tabBars.count` 与三 Tab 按钮存在性断言、降级提示 frame 断言，并在 Tab 收起时把主操作锚定改为「窗口底边扣除 Home Indicator 安全区」等价锚点（44/24 阈值未动）。`project.yml` 把纯判定列入 `PurePaceUITests` sources 并显式声明 `PurePaceRunCore` 依赖。
- 验证：`code_gates` 22 门 attempt 001 全绿（含 `build-ios`、`test-ios`、`test-ios-core`、`test-ios-run-core`）；`check-ios-shell` 30 项与 `--self-test` 0 失败；`test-ios --unit-only` 223 例 0 失败，`TabBarVisibilityPolicyTests` 5/5（两个反例真实判红：`["Tab 栏数量 1 ≠ 期望 0"]` / `["Tab 栏数量 0 ≠ 期望 1"]`）；`swift test --package-path ios/RunCore` 152 例 0 失败。
- 偏差/未闭合：定向 UI 用例在「未开始」态几何断言判红——提示由胶囊降为 caption 行后四等权 Spacer 各增 2pt，`未开始` hero→指标卡文本空洞 88.58pt > 80pt（`RunLayoutBalancePolicy` 阈值源码零改动，属布局回归而非阈值放宽）；因此 running / paused / 待保存 / 恢复链的 `tabBars.count` 实跑证据未取得，判定层只由 L1 覆盖。截图（`docs/screenshots/run-running*.png` / `run-finished*.png`）与 a11y 树（`docs/evidence/a11y/02`、`03`）按冻结令未重出，`SHA256SUMS` 未更新，`pending: 待人现场`。裸露取色/文案零新增，identifier 集合 diff 为 0。
