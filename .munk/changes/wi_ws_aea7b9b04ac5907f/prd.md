# RunView 交互接线：倒计时/暂停继续结束/保存丢弃/权限态

> 第 4 波（交互闭环）的视图接线子项。上游已交付：`DesignTokens`（含 `Motion` 三常量，视图侧接线为 0）、`scripts/check-ios-shell.sh`（33 项 identifier 逐项等值冻结）、`RunView` 三态五层视觉、`run-session-contract`（`RunStartCountdown` / `prepareFinish`+`saveFinished`+`discard` / `RunLocationReadiness` + VM 公开面）。本项只把已存在的契约接到视图并补齐可断言的展示决策，**不重写状态机、不新增文案键**。

## 范围

1. **展示决策单一真源**：新增一个纯值类型（建议 `ios/PurePace/Run/RunInteractionPlan.swift`）由 `RunSessionViewModel` 的既有公开面派生「本态显示哪些操作 / 谁是唯一主操作 / 倒计时读数 / 提示优先级 / 恢复动作 / 过渡时长」。`RunView` 只按 plan 渲染，不再各自 `switch` 三处（controls / statusMessage / readinessAction）。这是让下面五条路径「可达可退」能在 L1 被断言、而不用依赖模拟器的最小手段。
2. **倒计时态可取消且不遮挡主信息**：倒计时读数仍显示在提示层（不覆盖 hero 与指标卡），同一底部锚点给出唯一填充主操作「取消」——修掉当前倒计时态底部只有一个描边次要按钮、没有填充主操作的状态。
3. **跑步中暂停 / 继续 / 结束**：沿用既有接线，改为 plan 驱动；每态唯一填充主操作，结束保持「内在宽度 + warning 描边」的弱化破坏性形态。
4. **结束保存 / 丢弃**：待决策态保存为唯一填充主操作、丢弃为弱化次操作；保存失败后决策仍在——错误提示与重试入口都留在同一屏，指标与结束快照不清零；保存成功后切到「已保存 + 查看历史」。
5. **定位拒绝 / 不可用**：沿用 `RunLocationReadiness`，两态各给一条可执行动作（去设置 / 重试），只在未开始、非倒计时、未保存态出现，记录中不打断。
6. **动效接线（首次）**：状态切换过渡只允许取 `DesignTokens.Motion`（经 `Motion.duration(_:reduceMotion:)` 解析），并读 Reduce Motion：打开时时长归零（无动画），不得在视图里出现任何时长数字字面量。
7. **无断头路**：plan 的穷举状态逐态断言「至少一个能离开当前态的动作」，任何路径（含倒计时、暂停、待决策、保存失败、权限拒绝）都不得只能靠重启脱困。

## Acceptance Criteria

- ac-plan-single-primary: 对 plan 的穷举状态（ready 空闲 / ready 倒计时 / running / paused / finished 待决策 / finished 已保存）断言 `items` 恰含 **1 个** `primary`；ready 空闲=start、倒计时=cancelCountdown、running=pause、paused=resume、待决策=save、已保存=viewHistory（反例：把倒计时态主操作判为 secondary 必须判红）。
- ac-plan-no-dead-end: 上述每个状态的 `items` 非空，且至少包含一个离开该态的动作（start/cancelCountdown/pause/resume/finish/save/discard/viewHistory 之一）；不存在「只有提示没有动作」的状态（反例必须判红）。
- ac-plan-destructive-secondary: 结束类动作（running/paused 的 finish、待决策的 discard）恒为 `secondary`，且与同 state 唯一 `primary` 不相等；待决策态同时存在 save(primary) 与 discard(secondary)。
- ac-countdown-visible-metrics: 倒计时态 `countdownText` 非 nil（取 VM `countdownText` 读数）、`showsMetrics == true`，且四组指标文本字段仍由 plan 暴露、内容与进入倒计时前一致（读数为独立字段，不替换 hero/指标）——即倒计时不以覆盖方式遮挡主信息。
- ac-notice-priority: 提示同屏只出一条，优先级固定为 记录错误 > 决策失败 > 定位状态（拒绝/不可用/等待授权）> 后台降级；保存失败（`decisionErrorMessage != nil`）时 notice == decisionFailed，且此时 items 仍为 save+discard、metrics 文本非空（失败不吞已完成数据）。
- ac-recovery-two-actions: 授权 `denied` → recovery == openSettings 且 notice == locationDenied；`restricted` → recovery == retryLocation 且 notice == locationUnavailable；两者互不相等；`authorizedWhenInUse`/`authorizedAlways` → recovery == nil；recovery 仅在 state == ready 且非倒计时且非已保存时出现，running/paused/finished 恒为 nil。
- ac-motion-token-reduce-motion: `transitionDuration` 在 reduceMotion == true 时恒为 0（`DesignTokens.Motion.reducedMotionDuration`），false 时等于 `DesignTokens.Motion.durationState`；plan 内不出现任何时长数字字面量（反例：硬编码 0.32 必须判红）。
- ac-identifiers-unchanged: `ios/PurePace` 下可及 identifier 集合与门禁冻结的 33 项逐项相等（不新增、不改名、不删除）；倒计时取消 / 保存 / 丢弃 / 去设置 / 重试只带 `L10n` 可读 label，不新增 identifier。
- ac-gates-green: `.munk/code-gates.json` 全部 22 门退 0，其中 `lint-ios-shell`（含 `--self-test` ≥84 项）、`test-ios --unit-only`（≥199 例）、`test-ios-run-core`（≥152 例）无退化；新增用例为纯增量、无 sleep / 真实时钟 / 网络 / 模拟器。
- ac-l10n-and-tokens-only: 受管 UI 面（含新 plan 文件）零字面色值、零散字体修饰符、零动效时长字面量；本项不新增任何 `Localizable.xcstrings` 键，视图文案全部来自既有 `L10n` 入口。

## 非目标

- 不改 `RunCore` 任何契约：`RunSessionState` 4 态、`RunSessionMachine` 5 条迁移、`RunStartCountdown`、`RunSessionOrchestrator`、归档/checkpoint/GPX 格式与 `RunRecord` 结构一律零改动。
- 不改 `L10n.swift` 与 `Localizable.xcstrings`（零新增键，零改文案）；不改 `DesignTokens.swift` / `ContrastPolicy.swift` 取值。
- 不改 `scripts/**`、`.munk/code-gates.json`、`ios/project.yml`、CI、`android/`、`shared/`、`VERSION`。
- 不改 History / Settings 页面与文案；不新增 Tab、屏、路由或 App 级状态。
- 不改 `RunFlowUITests` / 既有 UI 用例断言（本机 UI 腿存在环境级信号崩溃，不作为本项验收依据）。
- 不做截图归档、不做真机或模拟器观感验收：可达可退由 L1 断言钉住，屏幕观感 `pending: 待人现场`。
- 不重做 Run 三态五层视觉与指标三行结构；只允许为「倒计时态主操作补填充」和「动效接线」做局部改动。

## 实现约束

**1. 预算与收口纪律（开工第一件事）**
预算：改动约 2 个源文件（新增 plan 纯类型 + 改写 `RunView` 渲染分支）＋ 1 个单测文件，不新增依赖、不改工程文件；门跑 3–4 次（`lint-ios-shell` + `--self-test`、`test-ios --unit-only`、`test-ios-run-core`，收口前 22 门全跑一次）。期望收口时刻：开工后 **90 分钟**；**120 分钟**到点未收口即停手，在 digest 写明做到哪一步、哪条 ac 未绿、下一手建议，不用长会话补绿。

**2. identifier 冲突裁决（必须按此执行）**
本项说明写「identifier 只增不改」，但 `scripts/check-ios-shell.sh` 以 33 项固定清单逐项等值比对，且 `--self-test` 明确把「追加一项 identifier」判红（`identifier 追加反例`），本项又禁止改门禁脚本。三者不能同时成立，裁决：**集合保持 33 项完全不变**。倒计时取消 / 保存 / 丢弃 / 去设置 / 重试一律只给 `L10n` 可读 label，不给 identifier；行为由 L1 断言覆盖。这是本项对「只增不改」唯一的有意收窄，需人复核时可单独回滚（回滚才需同时改门禁计数与自检反例）。

**3. plan 的落点与边界（避免过度抽象）**
- 仿既有 `RunDetailContent` / `RunFormatting` 的纯值类型做法：`struct RunInteractionPlan: Equatable`，由 `(state, isCountingDown, countdownText, didSave, hasError, hasDecisionError, readiness, reduceMotion)` 派生；视图再提供 `init(viewModel:reduceMotion:)` 便捷构造。只暴露枚举与 Bool/文本字段，**不放 View / 闭包 / ViewBuilder**，不做通用渲染框架。
- 动作枚举只覆盖既有 8 个动作；文案映射留在 `RunView`（`L10n` 既有键），plan 不持有文案。
- plan 文件位于 `ios/PurePace/Run/`，会被门禁按目录自动纳入受管面，因此文件内不得出现字面色值 / 字体修饰符 / 时长数字 / 裸英文文案。

**4. RunView 必须原样保留的门禁锚点**
`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }` 三行原文不得改写；继续使用 `DesignTokens.minTapTarget` 与底部 `safeAreaInset`；等宽数字处数不得少于 3；`run.backgroundDegraded` 标识与 DEBUG `run.telemetry` 覆盖层行为不变。

**5. 倒计时态修法**
倒计时仍由视图 `.task(id: viewModel.isCountingDown)` 驱动 `advanceCountdown()` 刷新（沿用现实现，勿引入真实计时器）；底部控制区在倒计时态用 `primaryControl(L10n.runActionCancel, ...)`（accent 填充）替换 `secondaryControl`，保持与 start 同一锚点、同一高度，使每态恰有一个填充主操作。读数位置维持提示层，不得改为覆盖 hero/指标卡的浮层。

**6. 动效接线口径**
只允许 `withAnimation` / `.animation(_:value:)` 配合 `DesignTokens.Motion.duration(...)`；reduceMotion 由 SwiftUI `@Environment(\.accessibilityReduceMotion)` 取，不用 `UIAccessibility` 单例读取（便于纯函数断言）。时长归零时必须真的无动画（不做「时长为 0 的动画」以外的补偿逻辑）。

**7. 测试落点与纪律**
`ios/PurePaceTests/RunInteractionPlanTests.swift`（`@testable import PurePace`，XCTest，禁 `import Testing`）：穷举 6 个展示状态 × reduceMotion 两值；反例（primary 缺失/重复、破坏性动作升格、reducedMotion 下时长非 0）必须判红。VM 层既有 `RunSessionContractTests` 覆盖的转移不再重复断言，plan 测试只断言展示决策。基线不回退：`test-ios --unit-only` ≥199 例、`test-ios-run-core` ≥152 例、`check-ios-shell --self-test` ≥84 项。
