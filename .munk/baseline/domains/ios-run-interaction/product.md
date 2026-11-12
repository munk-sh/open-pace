# Domain: ios-run-interaction

跑步页的「交互接线」子域：把上游已冻结的会话契约（`RunStartCountdown` / `prepareFinish`+`saveFinished`+`discard` / `RunLocationReadiness`）接到视图，并把展示决策收敛为单一纯值真源 `RunInteractionPlan`。视图只按 plan 渲染（不再各自 `switch` controls / 提示 / 恢复动作），因此「每态唯一主操作、无断头路、提示单条、恢复两态、动效取 token」全部能在 L1 断言。状态机、文案键与门禁脚本一律不改；三个主操作的 identifier 按门禁「冻结 33 项只增不改」契约补齐（规则正本见域 `design-token-gates`）。

## 范围

- `ios/PurePace/Run/RunInteractionPlan.swift`（新增）：`struct RunInteractionPlan: Equatable` 纯值类型，由 `(state, isCountingDown, countdownText, didSave, hasError, hasDecisionError, readiness, hasBackgroundDegradation, metrics, reduceMotion)` 派生；暴露 `items`（`Action` × `Emphasis`，10 动作：`start` / `cancelCountdown` / `pause` / `resume` / `finish` / `save` / `discardRequest` / `discard` / `cancel` / `viewHistory`）、`discardConfirmation`（`cancel`=text / `confirm`=discard@danger 实心，仅 `finished && !didSave` 非 nil）、`heroTint`（running/paused/ready/finished=primary、saved=success）、`countdownText`、`showsMetrics`、`notice`、`recovery`、`transitionDuration`、`metrics`（5 个文本字段）；`Item.tint` / `Item.style` 由 `Emphasis` 机械派生到 palette 键与样式枚举（`primaryAccent` / `accentOutline` / `neutralOutline` / `textSecondary` / `dangerFilled`），视图不再各自取色。附 `init(viewModel:reduceMotion:)` 便捷构造。不含 View / 闭包 / ViewBuilder，不持有文案。
- `ios/PurePace/Run/RunView.swift`：控制区、提示层、恢复入口全部改为 plan 驱动；倒计时态底部由描边次操作改为填充主操作「取消」（同一锚点、同一高度），读数仍留在提示层不覆盖 hero/指标卡；状态与 `didSave` 变化用 `.animation` 配合 `DesignTokens.Motion.duration(_:reduceMotion:)`，`reduceMotion` 取自 `@Environment(\.accessibilityReduceMotion)`。记录态 `finish` 取 plan 的 accent 族（不再 warning 描边）；结束待保存屏只出 `run.discardRequest` 入口，`run.discard` / `run.discardCancel` 仅存在于 `.sheet` 确认层（danger 实心唯一填充 + 无填充文字次操作；高度由 `onGeometryChange` 实测内容驱动 detent），取消回结束待保存态且不动会话状态；`.toolbar(.hidden, for: .tabBar)` 由本页 `NavigationStack` 承担。
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
- ac-plan-primary-family-accent: 记录态主操作族 `start` / `pause` / `resume` / `finish` / `save` 经 `Item.tint` 解析出的 tint 均为 `accent`（`primary` 与 `accent` 两档 emphasis 同源到 `Tint.accent`）；任一解析为 `warning` / `secondary` / `primary` 中性色即判红。`items` 保持「每展示态恰一个填充主操作」不变量（ready 空闲=start、倒计时=cancelCountdown、running=pause、paused=resume、待保存=save、已保存=viewHistory）。
- ac-plan-finish-accent: `running` / `paused` 的 `finish` 不再属于 `secondary`，emphasis 归入主操作 accent 族且不与同态唯一 `primary` 同档；L1 断言 `finish` 的 accent 解析结果，旧口径（`finish == .secondary` 或 warning）反例必须判红。
- ac-plan-discard-confirm-only: 待保存态 `items` 只含 `save`(primary) + `discardRequest`(text)，破坏性 `discard` 不出现在 `items`；`discardConfirmation` 仅在 `finished && !didSave` 非 nil，载荷为 `cancel`(text / `Style.textSecondary`，不填充) + `discard`(danger / `Style.dangerFilled`，`fillsWithTint == true`)，`danger` 解析为 `Tint.danger` 且非 accent 填充；其余态 `discardConfirmation == nil`（反例：待保存态直接塞 `discard` 进 `items` 判红）。
- ac-plan-hero-tint-single-source: `heroTint` 为 hero 主值色唯一真源（running/paused/ready/finished=primary、saved=success，永不 warning；浅色 accent 只作填充，不作数字 / 正文前景）；`RunView` 只消费 `valueTint: color(for: plan.heroTint)`，视图内零 `switch` 取色；把 paused 改回 warning 或 hero 回退 accent 的反例必须判红。
- ac-countdown-visible-metrics: 倒计时态 `countdownText` 非 nil（取 VM 读数）、`showsMetrics == true`，5 组指标文本仍由 plan 暴露且与进入倒计时前逐项一致——倒计时不以覆盖方式遮挡主信息。
- ac-finished-summary-blocks: `state == .finished` 同屏含 距离 / 时长 / 平均配速 三数值 + 轨迹预览卡（共用 `TrackMapView`）+ 分段明细（每段「序号 + 配速」，标识 `run.finished.splitRow`，标题 `run.finished.splits`）；无分段给 `L10n` 替代文案 `run.finished.splitsEmpty`，不留空卡；running / paused / ready 不出现这些块（门脚本断言 `viewModel.state == .finished` 门控）。保存仍是同屏唯一填充主操作（accent 实底、`Radius.control`），`discard` 仍只在确认层，语义重映射与既有 plan 单测不动。反例：删任一块、把地图放进记录态、保存改弱底，必须判红。
- ac-notice-priority: 同屏只出一条提示，优先级固定 记录错误 > 决策失败 > 定位状态（拒绝/不可用/等待授权）> 后台降级；`decisionErrorMessage != nil` 时 `notice == decisionFailed`，且 items 仍为 save+discard、指标文本非空（失败不吞已完成数据）。
- ac-recovery-two-actions: `denied` → `recovery == openSettings` 且 `notice == locationDenied`；`restricted` → `recovery == retryLocation` 且 `notice == locationUnavailable`；两者互不相等；`authorizedWhenInUse`/`authorizedAlways` → `recovery == nil`；recovery 仅在 `state == ready` 且非倒计时且非已保存时出现，running/paused/finished 恒为 nil。
- ac-motion-token-reduce-motion: `transitionDuration` 在 reduceMotion == true 时恒为 `DesignTokens.Motion.reducedMotionDuration`（0），false 时等于 `DesignTokens.Motion.durationState`；plan 内无任何时长数字字面量（反例：硬编码 0.32 判红）。
- ac-identifiers-append-only: 既有 33 项可及 identifier 逐项不变（不改名 / 不删除）；倒计时取消、结束保存、结束丢弃、丢弃入口、确认层取消分别带 `run.cancelCountdown` / `run.save` / `run.discard` / `run.discardRequest` / `run.discardCancel` 且 `accessibilityLabel` 为非空 `L10n` 键；仓库 identifier 总数单调不减（当前 42：冻结 33 + 地图/分段 5 + 主操作 4）；其余控件（去设置 / 重试）只带 `L10n` 可读 label。
- ac-gates-green: `.munk/code-gates.json` 全部 22 门退 0，`lint-ios-shell`（含 `--self-test` ≥84 项）、`test-ios --unit-only`（≥199 例）、`test-ios-run-core`（≥152 例）无退化；新增用例纯增量，无 sleep / 真实时钟 / 网络 / 模拟器。
- ac-l10n-and-tokens-only: 受管 UI 面（含 plan 文件与确认层）零字面色值、零散字体修饰符、零动效时长字面量；确认层四键（标题 / 说明 / 确认 / 取消）只落在 `Localizable.xcstrings`（`sourceLanguage=zh-Hans` 单语）与 `L10n` 入口，视图零裸英文字面量；其余文案仍全部来自既有 `L10n`。
- ac-tabbar-hidden-recording: 记录态（`running` 与 `paused` 均实测）`XCUIApplication().tabBars.count == 0`，且「跑步 / 历史 / 设置」三个 Tab 按钮均不可见、不可点；`run.pause` / `run.resume` 仍可点，距离与用时继续增长。
- ac-tabbar-hidden-finished-pending: 结束待保存态（`finished && !didSave`）`tabBars.count == 0` 且无 Tab 按钮，`run.save` 与 `run.discardRequest` 均可达；`run.discard` 此刻在屏上不存在。
- ac-tabbar-restore-no-deadend: 同一进程内保存或丢弃后回到 idle / 保存总结态时 `tabBars.count == 1` 且三 Tab 可点，再经历史、设置回到跑步页 TabBar 始终可见可点；全程不重新 launch，不存在只能杀进程脱困的断头路。
- ac-tabbar-red-proof: Tab 数量判定是由可注入实测数量驱动、不依赖 UI 的纯函数（期望值：记录态/待保存态 = 0，其余 = 1）；单测至少两个反例真实判红——记录态喂 `tabBarCount=1`、idle 喂 `tabBarCount=0`；反例只喂不同输入，不得靠改 `ios/PurePace/**` 生产代码才变红。
- ac-permission-banner-demoted: `WhenInUse` 降级态下后台定位提示不再是指标列上的整行 warning 胶囊，而以 `caption` 字号渲染为指标卡内的紧凑次级行（无 `Capsule` 底、无整宽弱底）；`run.backgroundDegraded` identifier 与文案不变，其 frame `minY` 大于 `run.distance` frame `maxY`（机器证明不压在距离 hero 上，也不插在 hero 与指标卡之间）。
- ac-primary-action-anchor-equivalent: TabBar 收起后主操作锚定断言改为「距窗口底边（扣除 Home Indicator 安全区）」，`PrimaryActionLayoutPolicy` 的 44 / 24 阈值与单测零改动，断言不得删除；idle / 已保存仍用 TabBar frame 原锚点。`RunLayoutBalancePolicy` 四阈值（`maximumTopGap/maximumBottomGap/maximumGap = 80`、`maximumImbalance = 16`）源码零改动。
- ac-uitest-target-wiring: 新纯判定被 UITests 复用时显式列入 `PurePaceUITests` sources 并在该 target 声明 `PurePaceRunCore` 依赖，`xcodegen generate --spec project.yml` 可重复生成；`.xcodeproj` 已 gitignore，diff 不含工程文件。
- ac-metrics-centered-without-infinite-frame: `RunView.balancedMetrics` 与结束总结不得用 `.frame(maxHeight: .infinity)` 吞掉垂直余量；居中由语义间距、等权 `Spacer(minLength:)` 与 `GeometryReader` + `ScrollView(minHeight:)` 分布承担，视图层不新增裸 magic number（样式字面量静态门仍为 0）。
- ac-metrics-centered-thresholds-green: 未开始 / 运行中 / 暂停三态四判据同时成立——顶部留白 ≤ 80、底部留白 ≤ 80、最大单一垂直空洞 ≤ 80、|顶部−底部| ≤ 16（逐态四元组以 `ac-run-metrics-balanced` 日志为准；曾红：运行中 top=73.42 / bottom=81.33 / largest=81.5，并命中「底部留白 > 80」「最大单一垂直空洞 > 80」两条 problems），保存态三判据全过——底部留白 ≤ 80、最大单一垂直空洞 ≤ 80、|顶部−底部| ≤ 16；保存态两种 canonical 内容实测（iPhone 16 / iOS 18.6）：0 行（400m）map=97.0 / top=20.0 / bottom=29.33 / largest=29.33 / imbalance=9.33，1 行（1200m）map=97.0 / top=20.0 / bottom=8.0 / largest=20.0 / imbalance=12.0；`RunLayoutBalancePolicy` 的 80 / 80 / 16 阈值与四条反例源码零改动。
- ac-metrics-top-chrome-equalized: 非结束态 `balancedMetrics` 容器的固定留白必须等权到 20pt——顶部 hero 上呼吸 `sm=12`、指标卡下 `cardPadding 16 + metricCardBottomPadding 4 = 20`、底部提示层尾隙 + 操作条内边距实测合计 20，故顶部只补一档 `DesignTokens.Spacing.xs`（8），使四层等权 `Spacer(minLength:)` 才能把 top / bottom / largest 同时压进 80；取值只允许落在既有 `Spacing` 档位（`xxs`/`xs`/`sm`），不得新增字面量、不得改阈值或采样口径，未开始态复用同一容器不得回归。
- ac-counterexample-shift-red: `LocalizationPolicyTests.testFourStatesShiftedUpBy24Fails` 取四态判绿代表帧（未开始 / 运行中 / 暂停 / 已保存）整体上移 24pt 后，`RunLayoutBalancePolicy.evaluate().passes == false`，且 `problems` 至少覆盖「底部留白 / 最大单一垂直空洞 / 上下留白差」之一；反例只喂合成帧，不依赖回退生产代码才红；既有反例（legacy 顶对齐、截图旧布局、缺地图卡、非对称留白）全部保留并继续判红。
- ac-metric-unit-line-reachable: `metricBlock` 的单位行保留在可及树（不得 `accessibilityHidden(true)`）：单位行占真实垂直空间，隐藏会把「数值 → 下一块」的间距虚增一整行（曾实测 89.9pt 误报），使首屏居中判据失真。
- ac-finished-budget-compressed-standard: 标准字号档可用内容区 < `RunFinishedSummaryLayoutPolicy.uncompressedFinishedContentHeight`（688pt；实测未压缩溢出 75.3pt）时结束总结走压缩档——地图 96pt（`finishedMapFloor` = 3 × `Spacing.xl`，与 AX5 档同值；曾于 `2d40bc0` 压到 32pt 形成细条，已回退）、区块间距 `xxs`、卡内边距 `xs`、行距 `xxs`；预算充足保 180pt，辅助字号档恒 96pt。三件套（实测溢出值 → 命名参数 → 复用点）只写在策略内，视图只读策略属性。
- ac-finished-map-floor-96: 标准字号档压缩分支地图高度 ≥ 96pt，与 AX5 档同值（96 = 3 × `Spacing.xl`）；判据由 `RunFinishedSummaryLayoutPolicy.meetsMapFloor(_:)` 承载，UI 断言取 iPhone 16 竖屏标准字号保存态 `run.mapPreview` 实测 frame 高度（打印实测值，断言数值下限而非复述生产常量）；把历史值 32 喂给同一判据必须判红（反例 `testHistoricStripHeightIsRejectedByMapFloor`）。
- ac-map-height-three-branches: 结束态地图高度只出现 180 / 96 两个值——未压缩标准档 180、标准档压缩 96、AX5（无论是否传预算）96；三组合由 `testMapHeightOnlyHasUncompressedAndCompressedBranches` 逐一断言，禁止再出现第三档（如 32 / 64）。
- ac-nonmap-slack-parameterized: 为地图 +64pt 让位的非地图垂直槽位（结束态顶部呼吸位 `topBreathing`、hero 上呼吸位 `heroTopPadding`、hero→指标间距 `heroMetricsGap`、指标卡内边距 / 底部补白 / 组间距、区块间距、分段卡内边距与行距）全部以命名参数落在 `RunFinishedSummaryLayoutPolicy`，注释写明「实测值 → 参数 → 复用点」，压缩档回收总量 60pt（余 4pt 有意留在顶部使两种 canonical 内容同过 16pt 上下差）；`RunView` 结束态路径零裸数字，只读策略属性或既有 `DesignTokens.Spacing`。
- ac-balance-audit-counts-map-card: 保存态居中审计把 `run.mapPreview` 当可见内容块纳入采样（不再只采 staticTexts），96pt 地图不被计成「最大单一垂直空洞」；单测 `testSavedStateWithMapCardPasses` 用同构保存态帧（含地图卡）固定该口径，反例 `testSavedStateWithoutMapCardFailsLargestGap`（去掉地图卡帧 → largestGap=120 > 80）必须判红；阈值 80 / 16 不变。
- ac-saved-content-canonical: 保存态 UI 用例的分段行数只由 `-uiTestLocationTargetMeters` 参数决定（0 行 = 400m、1 行 = 1200m，行数 = floor(累计距离/1000)），不随 runner 墙钟 1Hz tick 数漂移；`testSavedStateWithoutSplitsKeepsMapFloorAndBalance` 覆盖 0 行分支，反例 `testUnpinnedWallClockTicksChangeSplitRowsCounterexample` 证明不冻结距离时行数会变。
- ac-paused-tabbar-count-expected: 暂停态 `tabBars.count == 0`（曾实测 1 ≠ 0，修后 0），与 `TabBarVisibilityPolicy.expectedTabBarCount` 逐态一致（记录 / 暂停 / 待保存 0；`ready` / 已保存 1）；断言不放宽为 `>= 0`、不跳过，反例只喂不同输入。

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
- `RunView` 门禁锚点原文保留（本轮再改口径：hero 恒 primary）：`case .running, .paused: return .primary` / `case .ready, .finished: return .primary` / `if didSave { return .success }` 在 `RunInteractionPlan.heroTint`，`valueTint: color(for: plan.heroTint)` 在 `RunView`；`RunView` 内不再出现 `case .paused: return DesignTokens.Colors.warning`；继续使用 `DesignTokens.minTapTarget` 与底部 `safeAreaInset`；等宽数字处数不少于 3；`run.backgroundDegraded` 标识与 DEBUG `run.telemetry` 覆盖层行为不变。
- 倒计时仍由视图 `.task(id: viewModel.isCountingDown)` 驱动 `advanceCountdown()`，不引入真实计时器；倒计时态与 start 共用同一锚点与高度，使每态恰一个填充主操作。
- 动效只允许 `withAnimation` / `.animation(_:value:)` 配 `DesignTokens.Motion.duration(...)`；`reduceMotion` 由 SwiftUI 环境取，不用 `UIAccessibility` 单例；时长归零即无动画，不做额外补偿。
- `Run/` 目录被门禁按目录纳入受管面：plan 文件内不得出现字面色值 / 字体修饰符 / 时长数字 / 裸英文文案。
- 测试纪律：XCTest，`@testable import PurePace`；只断言展示决策，不重复 VM 层已有转移断言；反例必须判红。
- 基线不回退：`test-ios --unit-only` ≥199 例、`test-ios-run-core` ≥152 例、`check-ios-shell --self-test` ≥91 项。
- Tab 收起口径：隐藏必须让 tab 栏从可及树消失（`tabBars.count == 0`），不得只做视觉遮挡；判定只读 `runModel.state` + `didSave`，**禁**重建 `RunSessionViewModel`、重新 `launch`、重走 `onAppear`（`onAppear` 会 `locationSource.start()`，可能重启采样或重复计数）；`.toolbar(_:for: .tabBar)` 必须同时写隐藏分支与显式恢复分支，且修饰符挂在 `RunView` 的 `NavigationStack` 上（`ContentView` 的 `TabView` 外层不再重复同名修饰符，避免层级冲突使记录态 Tab 不收起）。
- 锚定断言适配边界：TabBar 收起时只允许把 UI 辅助改成「距窗口底边扣除 Home Indicator 安全区」的等价检查，不得删除断言、不得放宽 `PrimaryActionLayoutPolicy` 阈值或单测；死白断言 `RunLayoutBalancePolicy` 属硬约束，源码与阈值零改动，重排后 hero→提示、提示→主操作之间不得出现 >80pt 新空洞（|top − bottom| ≤16）。
- 提示分区单一决策：提示数据仍由 `RunInteractionPlan` 决定，只改 `.backgroundDegraded` 的渲染位置与样式，不改 VM 行为与 `notice` 优先级。
- 工程真源：`ios/project.yml` 手工新增文件必须同步（纯判定被 UITests 复用按既有 `VisibleTextPolicy` 做法显式列入 `PurePaceUITests` sources），再 `xcodegen generate --spec project.yml`；禁手改 `project.pbxproj`。

## 最近交付证明

- workItemId: wi_intake_10c7544ba84ffde4（2026-11-13，pass）
- 交付：`RunView.balancedMetrics` 容器补一档 `.padding(.top, DesignTokens.Spacing.xs)`（8pt）——把顶部固定 chrome 补齐到与指标卡下（`cardPadding 16 + 4`）、底部尾隙合计（20）等权的 20pt，运行中与暂停态四判据重新判绿，未开始态复用同一容器不回归，结束态预算不变；`LocalizationPolicyTests` 新增 `testFourStatesShiftedUpBy24Fails`（四态合成帧整体上移 24pt 必红，problems 覆盖底部留白 / 最大空洞 / 上下差之一）。
- 判定与证据：改前红原始事实保留在 PRD（CI run `43234566773`，head `a677e17`，`RunFlowUITests.swift:890`，top=73.42 / bottom=81.33 / largest=81.5）；`code_gates` 22 门 attempt 001 全绿（`lint-ios-shell` / `build-ios` / `test-ios` / `test-ios-core` 等）；`RunLayoutBalancePolicy` 80/80/80/16 阈值与 `evaluate` 采样口径零改动，`RunFinishedSummaryLayoutPolicy` 691/360/68/32 未动，`ios.yml` 与 `.munk/code-gates.json` 零 diff。
- 偏离与边界：只修布局、不重做视觉；不动 `docs/screenshots` / `docs/evidence`；`ios.yml` 权威腿结论与真机观感 `pending: 待人现场`。
