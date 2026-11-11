# 跑步会话契约：倒计时、结束保存/丢弃、定位不可用态

> 第 4 波（交互闭环）会话契约子项。上游已冻结：`DesignTokens`（第 2 波）、`scripts/check-ios-shell.sh` 门禁与 33 项 identifier（第 3 波加固）、`RunView` 三态四层视觉（`run-screens` 已交付）。本项只补「开始前 / 结束后 / 定位不可用」这三条路径的状态语义与可断言转移，不做视觉重做。

## 范围

1. **开始倒计时**：点击开始后不立刻进入记录态，先进入可取消的倒计时阶段；倒计时期间不产生任何度量、checkpoint、归档采样与采样计数。倒计时到点才真正 `start`（elapsed/distance 从 0 起算）。取消回到 `ready`，可立即重新开始。
2. **结束即决策**：结束（`running` 或 `paused`）先进入「已结束 + 待决策」：生成结束快照并停止记录，但**不落盘**。随后只有两条路径：`丢弃`（不写归档、回到可立刻再跑的 `ready`）与 `保存`（归档恰一次；失败可重试且不产生半条记录）。
3. **定位两态**：把「用户拒绝定位」与「定位不可用」拆成两种可恢复状态，各自带明确的下一步语义（去设置 / 重试），而不是一句合并提示。
4. **文案**：本项独占本波新增文案，只向单一 String Catalog 增加 zh-Hans 键并经 `L10n` 暴露，视图零裸字面量。
5. **断言**：以上全部转移在 L1（`ios/RunCore/Tests` + `ios/PurePaceTests`）用正例钉住，并至少给出能判红的反例。

## Acceptance Criteria

- ac-countdown-before-running: 点击开始后进入倒计时阶段而非记录态。该阶段内 `metrics`（distance/elapsed/splits/currentPace/averagePace）与开始前完全相等（全零）、`acceptedSamples` 为空、checkpoint 0 行、归档 0 条；剩余时间按注入时钟单调递减；仅当到达 deadline 完成倒计时后 state == running 且 elapsed == 0、distance == 0。
- ac-countdown-cancel-zero: 倒计时任意时刻取消 → state == ready、倒计时阶段清空、metrics 全零、`acceptedSamples` 空、checkpoint 0 行、归档 0 条、本跑次采样计数为 0；取消后立刻再次开始仍能进入倒计时（可重入，无断头路）。
- ac-countdown-no-samples: 倒计时期间定位源持续产出采样 → 不摄入引擎、不进归档序列、不写 checkpoint、metrics 不变、采样计数不增。
- ac-countdown-no-early-complete: 早于 deadline 尝试完成倒计时 → 被拒绝（抛错或保持倒计时），state 仍为 ready、零记录、零采样（反例必须判红）。
- ac-finish-awaits-decision: 从 `running` 与从 `paused` 结束时均进入「已结束 + 待决策」：state == finished，归档目录 0 条、不再追加 checkpoint；结束快照的 startedAt/endedAt/distance/activeDuration/splits/samples 与结束时刻 metrics 逐项相等。
- ac-discard-no-archive: 待决策态丢弃 → 归档仍 0 条、state 回到 ready、metrics 全零；随后新建会话正常从 0 累计（不残留上一跑次的度量、采样或 checkpoint）。
- ac-save-once: 待决策态保存 → 归档恰 1 条且内容与结束快照逐项相等；再次保存不新增文件、不重写文件、返回同一记录；VM 侧保存成功计数恒为 1。
- ac-save-failure-retry: 归档不可写（归档目录路径被同名普通文件占用）→ 首次保存失败、归档 0 条、state 仍 finished 且决策仍在；清障后再次保存成功且归档恰 1 条；失败提示为 zh-Hans 可读文案并带重试语义，不回显英文错误描述。
- ac-decision-guards: 未结束（ready/running/paused）时调用保存或丢弃 → 抛 `invalidStateTransition`，state/metrics/归档/checkpoint 均不变；已结束后重复「结束」不重复生成快照、不重复归档（反例必须判红）。
- ac-location-two-recoverable-states: 授权为 `denied` → 定位状态为「权限被拒」、下一步动作为「去设置」、提示键为 `run.status.locationDenied`；授权为 `restricted` → 定位状态为「不可用」、下一步动作为「重试」、提示键为 `run.status.locationUnavailable`；两者状态/动作/提示键三者互不相等；`authorizedWhenInUse`/`authorizedAlways` → 就绪无提示；`notDetermined` → 等待授权提示（沿用既有键）。
- ac-location-retry-restarts: 在「不可用」态触发重试 → 定位源 start 次数 +1；重试后源报告 `authorizedWhenInUse` → 定位状态立即变就绪且提示消失（同一会话内可恢复，不需要重启）。
- ac-l10n-single-catalog: 本项新增文案只存在于 `ios/PurePace/Resources/Localizable.xcstrings` 这一份 catalog 的 zh-Hans 本地化，全部经 `L10n` 类型化入口暴露；受管 UI 面零裸字面量（`validate_localization` 与裸英文扫描保持绿）。
- ac-identifier-set-frozen: 既有 33 项 accessibility identifier 逐项保持不变；本项不新增、不改名、不删除任何 identifier；新增控件只带 `L10n` 可读 label（与门禁的 33 项等值断言一致）。
- ac-existing-contracts-intact: `RunSessionState` 仍恰为 4 态、`RunSessionMachine` 合法迁移仍恰 5 条、checkpoint JSONL 字段与归档文件格式/命名、`RunRecord` 校验、GPX 导出契约零改动；`RunCore` 既有测试除本项显式改变语义的用例外零回归。
- ac-gates-green: `.munk/code-gates.json` 全部 22 门退 0（含 `check-ios-run-core` / `test-ios-run-core` / `test-ios --unit-only` / `check-ios-shell` 及其 `--self-test`）；新增用例为纯增量，不含睡眠、真实时钟或网络。

## Non-Goals

- 不改 `RunSessionState` 取值集合与 `RunSessionMachine` 迁移表，不给 checkpoint 增加新状态值。
- 不改 checkpoint JSONL 字段、归档目录/文件命名、`RunRecord` 结构与 GPX 导出契约；不做「待决策」跨进程恢复（决策前崩溃即可丢失本次跑次，明确不做）。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`、不改 `scripts/**`、`.munk/code-gates.json`、`ios/project.yml`、CI、`android/`、`shared/`、`VERSION`。
- 不改 History / Settings 页面与其文案；不新增 Tab、屏或路由；不重做 Run 三态四层视觉结构（沿用第 3 波），只在结束决策态补必要控件与倒计时态补取消控件。
- 不接动画与 Reduce Motion 到视图层（`Motion` 已存在但本项不接线）。
- 不新增 / 改名 / 删除 accessibility identifier（见「实现约束 · 决策 3」）。
- 不做真机验收、不做新截图归档、不改 UI 腿断言；真机/模拟器观感项一律 `pending: 待人现场`。

## 实现约束

**1. 预算与收口纪律（开工第一件事）**
先写预算（预计改动文件数、预计门跑次数/时长）与期望收口时刻；到点未收口即停手，在 digest 写明做到哪一步、哪条 ac 未绿、下一手建议，不用长会话补绿。

**2. 倒计时放哪：纯值类型 + VM 阶段，不扩状态机**
决策：倒计时不进 `RunSessionState`（保持 4 态），因为 `RunSessionStateTests` 逐值冻结 `allCases == [ready, running, paused, finished]`、`SessionMachineTests` 冻结合法迁移恰 5 条，改它会连带改 checkpoint 状态空间与既有契约。
落点：`ios/RunCore/Sources/PurePaceRunCore/` 新增一个基于 deadline 的纯值类型（建议名 `RunStartCountdown`，含总时长常量、`remaining(at:)`/`isComplete(at:)`、注入 `Date`、无定时器），`RunSessionViewModel` 持有其可选实例 + `isCountingDown` / `countdownRemaining`。到点完成由可注入时钟推进（测试直接推进时钟调用 `advanceCountdown()`），**禁止真实 sleep/真实 `Date()`**。

**3. identifier 冲突裁决（必须按此执行）**
本项说明写「既有 identifier 只增不改」，但 `scripts/check-ios-shell.sh` 现以 33 项固定集合逐项等值比对，且 `--self-test` 把「追加一项」判红；本项非目标又禁止改门禁脚本。三者不能同时成立，裁决：**集合保持 33 项完全不变（不增、不改、不删）**；新增控件（倒计时取消 / 保存 / 丢弃 / 去设置 / 重试）只给 `L10n` 可读 label，不给 identifier；行为由 VM/RunCore 的 L1 断言覆盖，不靠 identifier 定位。这是本项对「只增不改」唯一的有意收窄，需人复核时可单独回滚（回滚时才需要同时改门禁计数）。

**4. 结束契约：最小破坏面（强烈建议照做）**
在 `RunSessionOrchestrator` 上新增 `prepareFinish(at:)`（迁移到 finished、停表、生成并持有结束快照、清 checkpoint、**不归档**），新增 `discard()`（清空内存草稿、重建为全新 `ready`，归档不动），并保留既有 `finish(at:)` = 「归档一次且幂等」的语义（无待决策快照时允许自动补一次 prepare，使既有 `start → finish` 测试零改动）。失败可重试的唯一要求：`save` 失败不得留下半条文件、不得提前清空草稿；重试走同一条路径。
可判红的失败注入（确定性、无需桩协议）：把归档目录路径先建成同名**普通文件** → `RunArchiveStore.save` 抛 `RunArchiveError.ioFailure`；测试里删掉该文件后再保存必须成功。

**5. 采样门**
`RunSessionViewModel` 的定位 delegate 只在 `state == .running` 时计数与转发；`ready` / 倒计时 / 已结束期间到达的采样直接丢弃（不增 `runSampleCount`、不写 `sampleSources`、不进 ingest）。这样「倒计时期间零采样」由构造保证，而不是靠提示。

**6. 定位两态落点**
新增纯策略类型（建议 `ios/PurePace/Run/RunLocationReadiness.swift`：`enum` + 由 `RunLocationAuthorization` 派生的 readiness、下一步动作、提示文案键），VM 暴露 `locationReadiness` / `retryLocation()` / `locationSettingsURL`。`RunView` 只负责按 readiness 渲染提示与下一步按钮。`RunLocationAuthorization` 既有取值与 `clRawValue` 不变。

**7. 文案键（可用作锚点，具体命名允许微调，但必须单一 catalog + `L10n`）**
`run.action.cancel`（取消）/ `run.a11y.cancelCountdown` / `run.action.save`（保存）/ `run.a11y.saveRun` / `run.action.discard`（丢弃）/ `run.a11y.discardRun` / `run.status.saveFailed`（保存失败，请重试）/ `run.status.locationUnavailable`（定位暂不可用，请重试）/ `run.action.openSettings`（去设置）/ `run.action.retryLocation`（重试）。既有键 `run.status.locationDenied` / `run.status.waitingAuthorization` 原文不改（其 zh-Hans 值已含「请在系统设置中允许」语义，正好承载「去设置」）。

**8. 必须原样保留的门禁锚点（`RunView` 被真实扫描）**
`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }` 三行原文不得改写；`Run/` 目录内不得出现 `duration:` 字面量（倒计时时长常量放 RunCore）、不得出现字面色值/零散字体修饰符；继续使用 `DesignTokens.minTapTarget` 与底部 `safeAreaInset`。结束时每态仍恰好一个填充主操作：保存为主操作，丢弃为弱化的破坏性次操作（内在宽度 + warning 描边，沿用既有 `secondaryControl` 形态）。

**9. VM 公开面（供后续波次消费，名称尽量贴此）**
保留 `state` / `metrics` / `didSave` / `errorMessage` / `authorization` / `savedCount`；新增 `isCountingDown` / `countdownRemaining` / `cancelCountdown()` / `advanceCountdown()` / `saveFinished()` / `discardFinished()` / `locationReadiness` / `retryLocation()` / `locationSettingsURL` / `decisionErrorMessage`。`start()` 语义变为「进入倒计时」；`-autoStartRecording` 调试路径允许立即越过倒计时（不得引入 sleep，而是一次性把倒计时置为完成），此路径仅由 DEBUG launch argument 驱动。

**10. 测试落点与纪律**
`RunCore` 新值类型/编排器契约 → `ios/RunCore/Tests/PurePaceRunCoreTests/`；VM、定位策略、保存重试 → `ios/PurePaceTests/`。XCTest（禁 `import Testing`）；时间用 `Date(timeIntervalSince1970:)` 合成与注入时钟；归档断言用新建 store 实例从磁盘读回，不用内存桩；临时目录用 `temporaryDirectory + UUID()` 并 `defer` 清理。既有基线不回退：`test-ios-run-core` ≥ 141 例、`test-ios --unit-only` ≥ 182 例、`check-ios-shell --self-test` ≥ 84 项。
