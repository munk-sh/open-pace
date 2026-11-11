# Domain: ios-run-session-contract

跑步会话的「开始前 / 结束后 / 定位不可用」三条路径的状态契约子域：倒计时是记录态之前的瞬态（**不进** `RunSessionState`，该枚举保持 4 态冻结）；结束先进「已结束 + 待决策」，只有保存（归档恰一次）或丢弃（零归档回到可再跑的 `ready`）两条出口；定位授权按可恢复两态拆分（权限被拒 → 去设置 / 定位不可用 → 重试）。纯逻辑与值类型在 `ios/RunCore`，接线与渲染在 `ios/PurePace/Run`；状态机迁移表、checkpoint JSONL 字段、归档命名与 `RunRecord` 校验、GPX 导出、identifier 集合一律不改。

## 范围

- `ios/RunCore/Sources/PurePaceRunCore/RunStartCountdown.swift`（新增）：`struct` + `Sendable`，`static let defaultDuration: TimeInterval`（仅此一处时长常量，UI 目录零字面量）、`startedAt`、`deadline`、`remaining(at:)`（恒不为负、随注入时钟单调递减）、`isComplete(at:)`；不持定时器、不读系统时钟，非正/非有限时长归零为「立刻可完成」。
- `ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift`（additive）：`prepareFinish(at:)`（迁移 `finished` + 停表 + 生成并持有结束快照 + 清 checkpoint，**不归档**）、`saveFinished()`（`RunArchiveStore.save` 恰一次，重复调用返回同一记录）、`discard()`（重建全新 `ready`，归档文件不动）、只读 `finishedSnapshot` / `savedRecord` / `isAwaitingDecision`；既有 `finish(at:)` 保留「归档一次且幂等」语义，无待决策快照时自动补一次 `prepareFinish`。
- `ios/PurePace/Run/RunLocationReadiness.swift`（新增）：`RunLocationReadiness`（`ready` / `awaitingAuthorization` / `permissionDenied` / `unavailable`）+ `NextAction`（`openSettings` / `retry`）+ `messageKey` / `message`（经 `L10n`）；由既有 `RunLocationAuthorization` 派生，`RunLocationAuthorization` 取值与 `clRawValue` 不变。
- `ios/PurePace/Run/RunSessionViewModel.swift`：`isCountingDown` / `countdownRemaining` / `countdownText` / `cancelCountdown()` / `advanceCountdown()` / `saveFinished()` / `discardFinished()` / `decisionErrorMessage` / `locationReadiness` / `retryLocation()` / `locationSettingsURL` / `acceptedSamples`；`start()` 语义改为「进入倒计时」，`-autoStartRecording` 一次性越过（零 sleep）；定位 delegate 采样门改为 `guard state == .running`。
- `ios/PurePace/Run/RunView.swift`：倒计时态显示剩余读数 + 取消次操作；结束态保存为唯一填充主操作、丢弃为弱化破坏性次操作；就绪态按 `readinessAction` 渲染「去设置」/「重试」入口。新增控件带 `L10n` 可读 label；取消 / 保存 / 丢弃三个主操作的 identifier 由后续 WI 按门禁「只增不改」契约补齐（`run.cancelCountdown` / `run.save` / `run.discard`，见域 `ios-run-interaction`），本域逻辑不依赖其名称。
- `ios/PurePace/Design/L10n.swift` + `ios/PurePace/Resources/Localizable.xcstrings`：新增 10 键（`run.action.cancel|save|discard|openSettings|retryLocation`、`run.a11y.cancelCountdown|saveRun|discardRun`、`run.status.saveFailed|locationUnavailable`），仅 zh-Hans、单一 catalog。
- 测试落点：`ios/RunCore/Tests/PurePaceRunCoreTests/RunSessionDecisionTests.swift`（11 例）、`ios/PurePaceTests/RunSessionContractTests.swift`（15 例）；既有 `RunSessionViewModelTests` / `RunTelemetryTests` / 锁屏与恢复用例仅按新语义补倒计时注入与待决策路径。

## 验收

- ac-countdown-before-running: 点击开始后进入倒计时而非记录态；该阶段 `metrics`（distance/elapsed/splits/currentPace/averagePace）与开始前逐项相等（全零）、`acceptedSamples` 空、checkpoint 0 行、归档 0 条；剩余时间按注入时钟单调递减；仅到达 deadline 后 `state == running` 且 elapsed/distance 为 0。
- ac-countdown-cancel-zero: 倒计时任意时刻取消 → `state == ready`、倒计时清空、metrics 全零、`acceptedSamples` 空、checkpoint 0 行、归档 0 条、本跑次采样计数 0；取消后可立即再次进入倒计时（可重入）。
- ac-countdown-no-samples: 倒计时期间定位源持续产出采样 → 不摄入引擎、不进归档序列、不写 checkpoint、metrics 不变、采样计数不增。
- ac-countdown-no-early-complete: 早于 deadline 调用 `advanceCountdown()` → 保持倒计时，`state` 仍 `ready`、零记录零采样（反例判红）。
- ac-finish-awaits-decision: 从 `running` 与从 `paused` 结束均进入待决策：`state == finished`、归档 0 条、不再追加 checkpoint；快照 startedAt/endedAt/distance/activeDuration/splits/samples 与结束时刻 metrics 逐项相等。
- ac-discard-no-archive: 待决策丢弃 → 归档仍 0 条、`state` 回 `ready`、metrics 全零；随后新会话从 0 累计，不残留度量/采样/checkpoint。
- ac-save-once: 待决策保存 → 归档恰 1 条且与快照逐项相等；再次保存不新增、不重写、返回同一记录；VM 侧 `savedCount` 恒为 1。
- ac-save-failure-retry: 归档目录路径被同名普通文件占用 → 首次保存失败、归档 0 条、`state` 仍 `finished` 且决策仍在；清障后重试成功且归档恰 1 条；提示为 zh-Hans 可读文案（`run.status.saveFailed`）带重试语义。
- ac-decision-guards: 未结束（ready/running/paused）调用保存或丢弃 → 抛 `RunCoreError.invalidStateTransition`，state/metrics/归档/checkpoint 不变；已结束后重复结束不重复生成快照、不重复归档（反例判红）。
- ac-location-two-recoverable-states: `denied` → `permissionDenied` + `openSettings` + `run.status.locationDenied`；`restricted` → `unavailable` + `retry` + `run.status.locationUnavailable`；两者状态/动作/提示键三者互不相等；`authorizedWhenInUse`/`authorizedAlways` → `ready` 无提示；`notDetermined` → `awaitingAuthorization` 沿用既有键。
- ac-location-retry-restarts: 「不可用」态触发重试 → 定位源 `start` 次数 +1；重试后源报告 `authorizedWhenInUse` → readiness 立即变 `ready` 且提示消失（同会话内恢复，无需重启）；非 `retry` 态调用重试被忽略。
- ac-l10n-single-catalog: 本项新增文案只存在于 `Localizable.xcstrings` 的 zh-Hans，全部经 `L10n` 暴露；受管 UI 面零裸字面量（`validate_localization` 与裸英文扫描保持绿）。
- ac-identifier-frozen-then-appended: 既定 33 项 accessibility identifier 逐项不变（不改名 / 不删除）；本域落地时新增控件只带 `L10n` label，后续 WI 已补 `run.cancelCountdown` / `run.save` / `run.discard`，门禁按「冻结 33 + 必需新增 3」计数下限断言。
- ac-existing-contracts-intact: `RunSessionState` 仍恰 4 态、`RunSessionMachine` 合法迁移仍恰 5 条；checkpoint JSONL 字段、归档格式/命名、`RunRecord` 校验、GPX 导出契约零改动；`RunCore` 既有测试除本项显式改变语义的用例外零回归。
- ac-gates-green: `.munk/code-gates.json` 全部 22 门退 0（含 `check-ios-run-core` / `test-ios-run-core` / `test-ios --unit-only` / `check-ios-shell` 及 `--self-test`）；新增用例为纯增量，不含睡眠、真实时钟或网络。

## 非目标

- 不改 `RunSessionState` 取值集合与 `RunSessionMachine` 迁移表，不给 checkpoint 增加新状态值。
- 不改 checkpoint JSONL 字段、归档目录/文件命名、`RunRecord` 结构、GPX 导出契约；不做「待决策」跨进程恢复（决策前崩溃即丢失该跑次，明确不做）。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`、`scripts/**`、`.munk/code-gates.json`、`ios/project.yml`、CI、`android/`、`shared/`、`VERSION`。
- 不改 History / Settings 页面与文案；不新增 Tab、屏或路由；不重做 Run 三态四层视觉结构，只在结束决策态补必要控件、倒计时态补取消控件。
- 不接动画与 Reduce Motion 到视图层；不改既有 33 项 accessibility identifier（只增不改由域 `design-token-gates` 约束）。
- 不做真机验收、不归档新截图、不改 UI 腿断言；真机/模拟器观感项一律 `pending: 待人现场`。

## 实现约束

- 倒计时不进状态机：`RunSessionState` 逐值冻结为 4 态、`RunSessionMachine` 合法迁移恰 5 条，任何倒计时状态值都会连带改 checkpoint 状态空间。
- 采样门由构造保证而非提示：delegate 内 `guard state == .running`，`ready` / 倒计时 / 暂停 / 已结束的采样整条丢弃（不计数、不写 `sampleSources`、不转发 ingest）。
- 保存失败不得留半条文件、不得提前清空草稿；重试走同一条 `saveFinished()` 路径。
- 失败注入必须确定性、无桩协议：把归档目录路径建成同名普通文件 → `RunArchiveStore.save` 抛 `RunArchiveError.ioFailure`；测试内删除后重试必须成功。
- `RunView` 门禁锚点原文保留：`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }`；`Run/` 内无 `duration:` 字面量、无字面色值/零散字体修饰符，继续使用 `DesignTokens.minTapTarget` 与底部 `safeAreaInset`。
- 时间与证据纪律：XCTest（禁 `import Testing`）；`Date(timeIntervalSince1970:)` 合成 + 注入时钟，禁真实 sleep / `Date()` 现时；临时目录 `temporaryDirectory + UUID()` 并 `defer` 清理；归档断言用新建 store 实例从磁盘读回。
- 基线不回退：`test-ios-run-core` ≥ 141 例、`test-ios --unit-only` ≥ 182 例、`check-ios-shell --self-test` ≥ 84 项；本项交付时实测 152 / 199。

## 最近交付证明

- workItemId: wi_ws_dfff3bb3517c6e1c（2026-11-11，pass）
- 交付：新增 `RunStartCountdown` 纯值类型（deadline + 注入时钟，无定时器）与 `RunLocationReadiness`（4 态 + 2 个下一步动作 + 文案键）；`RunSessionOrchestrator` additive 出 `prepareFinish` / `saveFinished` / `discard` / `finishedSnapshot` / `savedRecord` / `isAwaitingDecision`，`finish` 收敛为「必要时自动 prepare + 归档一次」；VM 暴露倒计时/待决策/定位读数与动作，`start()` 改为进入倒计时、采样门收紧到 `state == .running`；`RunView` 增倒计时取消读数与结束态保存/丢弃控件、就绪态按 readiness 渲染去设置/重试；10 个新文案键只进单一 catalog。
- 验证：`code_gates` 22 门全绿——`test-ios-run-core` 152 例 0 失败（+11 `RunSessionDecisionTests`）、`test-ios --unit-only` 199 例 0 失败（+15 `RunSessionContractTests`）、`check-ios-shell` 含 `--self-test` 全 PASS、`build-ios` BUILD SUCCEEDED；identifier 33 项不变；`scripts/**`、`.munk/code-gates.json`、`ios/project.yml`、`shared/**`、`android/`、`VERSION` 零改动。
- 偏差/有意未做：本域落地时 PRD 写「identifier 只增不改」而门禁仍为 33 项等值，故当时裁决为集合完全不变；该契约已由 wi_ws_42e0654f761029c3 改为「冻结 33 项只增不改 + 计数下限」，三主操作 identifier 已补齐（见域 `ios-run-interaction`）。待决策跨进程恢复明确不做；真机/模拟器观感 `pending: 待人现场`。
