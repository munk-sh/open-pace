# Domain: ios-run-interaction

跑步页的「交互接线」子域：把上游已冻结的会话契约（`RunStartCountdown` / `prepareFinish`+`saveFinished`+`discard` / `RunLocationReadiness`）接到视图，并把展示决策收敛为单一纯值真源 `RunInteractionPlan`。视图只按 plan 渲染（不再各自 `switch` controls / 提示 / 恢复动作），因此「每态唯一主操作、无断头路、提示单条、恢复两态、动效取 token」全部能在 L1 断言。状态机、文案键与门禁脚本一律不改；三个主操作的 identifier 按门禁「冻结 33 项只增不改」契约补齐（规则正本见域 `design-token-gates`）。

## 范围

- `ios/PurePace/Run/RunInteractionPlan.swift`（新增）：`struct RunInteractionPlan: Equatable` 纯值类型，由 `(state, isCountingDown, countdownText, didSave, hasError, hasDecisionError, readiness, hasBackgroundDegradation, metrics, reduceMotion)` 派生；暴露 `items`（`Action` × `Emphasis`，仅既有 8 动作）、`countdownText`、`showsMetrics`、`notice`、`recovery`、`transitionDuration`、`metrics`（5 个文本字段）；附 `init(viewModel:reduceMotion:)` 便捷构造。不含 View / 闭包 / ViewBuilder，不持有文案。
- `ios/PurePace/Run/RunView.swift`：控制区、提示层、恢复入口全部改为 plan 驱动；倒计时态底部由描边次操作改为填充主操作「取消」（同一锚点、同一高度），读数仍留在提示层不覆盖 hero/指标卡；状态与 `didSave` 变化用 `.animation` 配合 `DesignTokens.Motion.duration(_:reduceMotion:)`，`reduceMotion` 取自 `@Environment(\.accessibilityReduceMotion)`。
- `ios/PurePaceTests/RunInteractionPlanTests.swift`（新增）：XCTest（禁 `import Testing`），穷举 6 个展示状态 × `reduceMotion` 两值，含 primary 缺失/重复、破坏性升格、reduceMotion 下时长非 0 的反例。

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

## 非目标

- 不改 `RunCore` 任何契约：`RunSessionState` 仍 4 态、`RunSessionMachine` 迁移仍 5 条、`RunStartCountdown` / `RunSessionOrchestrator` / 归档 / checkpoint / GPX / `RunRecord` 零改动。
- 不改 `L10n.swift` 与 `Localizable.xcstrings`（零新增键、零改文案）；不改 `DesignTokens.swift` / `ContrastPolicy.swift` 取值。
- 不改 `scripts/**`、`.munk/code-gates.json`、`ios/project.yml`、CI、`android/`、`shared/`、`VERSION`。
- 不改 History / Settings 页面与文案；不新增 Tab、屏、路由或 App 级状态。
- 不改 `RunFlowUITests` / 既有 UI 用例断言；不重做 Run 三态五层视觉与指标三行结构（仅补倒计时主操作填充与动效接线）。
- 不做截图归档、不做真机或模拟器观感验收：可达可退由 L1 钉住，屏幕观感 `pending: 待人现场`。

## 实现约束

- identifier 冲突裁决（已解除）：本域落地时 PRD 写「只增不改」而门禁是 33 项等值、且禁改脚本，故当时收窄为**集合 33 项完全不变**；门禁随后改为「冻结 33 项只增不改 + 必需新增 + 计数下限」，本域三主操作 identifier 现由门禁必需清单钉住，旧裁决作废。
- `RunView` 门禁锚点原文保留：`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }`；继续使用 `DesignTokens.minTapTarget` 与底部 `safeAreaInset`；等宽数字处数不少于 3；`run.backgroundDegraded` 标识与 DEBUG `run.telemetry` 覆盖层行为不变。
- 倒计时仍由视图 `.task(id: viewModel.isCountingDown)` 驱动 `advanceCountdown()`，不引入真实计时器；倒计时态与 start 共用同一锚点与高度，使每态恰一个填充主操作。
- 动效只允许 `withAnimation` / `.animation(_:value:)` 配 `DesignTokens.Motion.duration(...)`；`reduceMotion` 由 SwiftUI 环境取，不用 `UIAccessibility` 单例；时长归零即无动画，不做额外补偿。
- `Run/` 目录被门禁按目录纳入受管面：plan 文件内不得出现字面色值 / 字体修饰符 / 时长数字 / 裸英文文案。
- 测试纪律：XCTest，`@testable import PurePace`；只断言展示决策，不重复 VM 层已有转移断言；反例必须判红。
- 基线不回退：`test-ios --unit-only` ≥199 例、`test-ios-run-core` ≥152 例、`check-ios-shell --self-test` ≥91 项。

## 最近交付证明

- workItemId: wi_ws_42e0654f761029c3（2026-11-11，pass）
- 交付：`RunView` 三个主操作补齐可及 identifier（`run.cancelCountdown` / `run.save` / `run.discard`，各带非空 `L10n` 可读 label），既有 33 项逐字未变，仓库总数 36；门禁 identifier 契约同步改为「冻结 33 项只增不改 + 必需新增 3 + 计数单调」（规则正本见域 `design-token-gates`）。`RunInteractionPlan` 与文案键零改动。
- 验证：`bash scripts/check-ios-shell.sh` 30 项 / `--self-test` 91 项断言 0 失败，pass 行打印 `identifier: 36（冻结 33 + 新增 3）；demo/示例入口: 0`；`code_gates` 22 门全绿（attempt 001）。
- 偏差/有意未做：只加标识、不改既有 identifier 名与视图结构；未新增 `Localizable.xcstrings` 键；真机/模拟器观感仍 `pending: 待人现场`。
