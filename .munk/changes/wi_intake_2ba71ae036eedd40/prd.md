# 播报停用：不吞错 + 状态提交后置 + 返回值取真实结果 + 错误落容器诊断文件

## Scope

来源：`wi_intake_f76b858c0c2376f5` verdict 3 / digest（`.munk/changes/wi_intake_f76b858c0c2376f5/digest.md`）；本项已由公司裁决 `owe_5d52d1f604c57d11` 重定修法，**不接受**「盲重试一次 + 失败回滚 `.active`」。

已成立的代码缺陷（三条，均在本仓当前代码上可读）：

1. **吞错**：`SpeechAnnouncementSpeaker.speak` 的 `onFinish`（`ios/PurePace/Audio/AnnouncementSpeaker.swift` 126-143 行）`catch { sessionDeactivated = false }` 丢弃错误对象；`duckRevoked: sessionDeactivated`（141 行）同源派生，失败原因完全不可观测。
2. **状态先于平台调用提交**：`AudioSessionCoordinator.deactivate()`（`ios/RunCore/Sources/PurePaceRunCore/AudioSessionCoordinator.swift` 47-51 行）先把 `state = .inactive` 再返回 `.deactivate` 动作。
3. **返回值语义错**：`AudioSessionAdapter.endAnnouncement()`（`ios/PurePace/Audio/AudioSessionAdapter.swift` 146-152 行）用「动作非 `.none`」而非平台调用执行结果决定返回值。

**证据边界（必须原样保留的表述）**：设备侧成因未排他、缺 OSStatus。上一版方案被否决的事实依据：状态一旦提交 `.inactive`，再经协调器只会拿到 `.none`（重试必须绕过协调器）；`.active` 回滚无平台读回能力（`AudioSessionCoordinator` 明写不读回），等于再造一次状态不一致；还可能在系统已停用会话后再发一次 `setActive(false)`。盲重试与补偿策略待拿到真实 OSStatus 再定，另派项。

本项只做第一版最小修改（四条）与三条回归断言。**顺序：本项先落，不等 222ccb。**

## Acceptance Criteria

### 第一版四条修改

- ac-no-silent-catch: 停用失败时 `onFinish` 的 `catch` 不得静默：必须写出结构化诊断记录（含错误域、错误码、协调器状态、是否真实下发平台调用），同时 `sessionDeactivated=false`、`duckRevoked=false`（不得伪造 true）；`finishedAt` / `cancelled` 仍如实写入。
- ac-commit-after-platform-success: `AudioSessionCoordinator` 的停用状态提交发生在平台调用成功之后 —— `deactivate()` 只做纯动作推导、**不改变 `state`**；新增独立的纯状态提交方法（锚点命名 `mutating func commitDeactivation()`）仅在解析到 `.deactivate` 且 `setActive(false, …)` 真实成功后置 `state = .inactive`。平台调用抛错时 `state` 保持 `.active`（不提交，也不存在「先提交再回滚」代码路径）。
- ac-end-returns-real-result: `endAnnouncement()` 返回 `true` 当且仅当 `setActive(false, [.notifyOthersOnDeactivation])` 真实执行成功；协调器动作 `.none`（如 `.interrupted` / 已 `.inactive`）时返回 `false` 且不发起任何平台调用；平台调用抛错时把错误抛出（不得吞成返回值）。
- ac-no-retry-no-compensation: 一次结束路径最多下发 1 次 `setActive(false)`；不得引入重试、回滚 API（`rollbackFailedDeactivation` 之类）或任何补偿性状态改写。工作区里上一版草稿实现必须整体丢弃，不得在其上增补。

### 错误可观测性（容器可拉取）

- ac-diagnostics-file-path: 诊断记录写入 App 数据容器内的**固定路径** `Documents/Diagnostics/announcement-deactivation.json`（相对 `appDataContainer`；测试可注入临时目录，生产默认由 `FileManager` 的 Documents 目录拼出，不写死绝对路径）；写入为 JSON、追加保留历史、原子替换、线程安全；写盘失败必须被吞掉且不打断播报，不得抛到播报路径。
- ac-diagnostics-schema: 文件结构为 `{"version": 1, "outcomes": [ … ]}`，每条记录字段固定为 `splitIndex`、`occurredAt`（epoch 秒）、`outcome`（`"failed"` | `"not-applicable"`）、`errorDomain`（string 或 null）、`errorCode`（int 或 null）、`coordinatorStateBefore`、`coordinatorStateAfter`（`"inactive"|"active"|"interrupted"`）、`platformCallIssued`（bool）。成功路径不写记录。
- ac-diagnostics-pullable: 该路径可由 `xcrun devicectl device copy from --domain-type appDataContainer --source Documents/Diagnostics/announcement-deactivation.json`（或 `xcrun simctl get_app_container <udid> <bundle-id> data` 后直接读）取出；不修改任何采集/CI 脚本，仅保证路径固定可拉取。

### 回归断言 A / B / C（替换上一版三条）

- ac-success-path: **A 成功路径** —— 协调器 `.active` 时结束播报，返回值 `true`，落盘 `sessionDeactivated=true`、`duckRevoked=true`，平台 `setActive` 序列恰为 `[true, false]`（激活 1 次、停用 1 次，正常路径调用次数不变），协调器 `.inactive`，诊断文件不新增记录。
- ac-throw-path: **B 抛错路径** —— 首次 `setActive(false)` 抛错时：`deactivations.count == 1`（无重试）、协调器 `state` 保持 `.active`（未提交）、`sessionDeactivated=false`、`duckRevoked=false`、诊断文件新增 1 条 `outcome="failed"` 记录且 `errorDomain` / `errorCode` 与注入错误一致、`coordinatorStateBefore == "active"`、`coordinatorStateAfter == "active"`、`platformCallIssued == true`；同一播报器下一次播报的激活序列正确（协调器仍 `.active` → `beginAnnouncement()` 返回 `false`、不再下发 `setActive(true)`，其结束后仍下发 `setActive(false)` 并落盘 `sessionDeactivated=true`）。
- ac-interrupted-path: **C `.interrupted` 路径** —— 播报中进入 `.interrupted` 后结束播报：`deactivate()` 动作 `.none`、无平台停用调用、`sessionDeactivated=false`、`duckRevoked=false`；诊断文件新增 1 条 `outcome="not-applicable"` 记录（`errorDomain == null`、`errorCode == null`、`platformCallIssued == false`），且**不存在** `outcome="failed"` 记录。该用例专用于区分「两个 false」的两种来源。

### 契约不变

- ac-telemetry-contract-unchanged: 遥测 JSON 字段契约不变 —— `telemetry.announcements[]` 字段名、类型与语义均不增不改（不新增 not-applicable / 错误码字段），`ios/PurePace/Run/RunTelemetry.swift` 的 `RunTelemetryAnnouncement` 保持原样；`not-applicable` 只体现在诊断文件，不回灌遥测。
- ac-config-unchanged: 播报 category/mode/options 仍为 `playback` / `spokenAudio` / `[duckOthers, mixWithOthers]`，停用选项仍为 `[.notifyOthersOnDeactivation]`；每公里播报调度、文案模板、GPX 导出/持久化/定位契约端到端不变；不改 `ios/project.yml` / `Info.plist` / bundle id / 签名 / `VERSION`。
- ac-gates-green: `bash scripts/test-ios.sh --unit-only`、`swift test --package-path ios/RunCore` 与 `.munk/code-gates.json` 全部既有门本地全绿；不新增 CI 腿、不改 600s 预算、不改 `.github/workflows/**`、不改门列表。
- ac-tests-not-weakened: 已有测试不得删除或放宽。语义随本次变更的既有断言按新语义改写并注明（`AudioSessionCoordinatorTests.testDeactivateCarriesNotifyOthersOption` 改为 deactivate→commit 两段；`AnnouncementSpeakerTests.testThrownDeactivationProducesObservedFalseFingerprintAndNextActivation` 改写为 B 且不降级）；机制② 中断用例（`testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates`）保留并加 C 的诊断断言。

## Non-Goals

- 不做任何重试（含「仅对 isBusy/resourceNotAvailable 重试一次」）、不做状态回滚/补偿；真实 OSStatus 到手后另派项决定策略。
- 不改遥测 JSON 契约（不加错误码/not-applicable 字段）。
- 不重构 `AudioSessionCoordinator` 其余转移（`activate()` / 中断 began/ended 的提交顺序保持现状，本次只改停用提交时机）。
- 不改 `Info.plist` / `ios/project.yml` / bundle id / 签名 / 根 `VERSION`。
- 不跑真机、不出候选包、不改 CI workflow 与预算、不新增 CI 腿、不改 `scripts/verify-*.sh` 采集脚本。
- 不改主 App 的 AudioSession category/options 配置。
- 不处理 `beginAnnouncement()` 激活失败分支的日志与状态一致性（另一条线）。

## Implementation Constraints

裁决已定方案（`owe_5d52d1f604c57d11`），needPm / needDesign / needArchitect / needChangePackReview 全为 `false`，Coding 直接落地。**工作区当前未提交的草稿（`git diff` 可见的 `isRetryableDeactivationError` / `rollbackFailedDeactivation` / os_log 日志）整体丢弃后重写。**

1. `ios/RunCore/Sources/PurePaceRunCore/AudioSessionCoordinator.swift`
   - `deactivate()` 改为非 mutating 的纯动作推导：`state == .active` 时返回 `.deactivate(options: settings.deactivationOptions)`，否则 `.none`；**任何情况下不改 `state`**。
   - 新增 `public mutating func commitDeactivation()`：`guard state == .active else { return }` 然后 `state = .inactive`；不产生/返回动作、不触碰平台。唯一调用方是 `AudioSessionAdapter.endAnnouncement()` 的平台调用成功分支。
2. `ios/PurePace/Audio/AudioSessionAdapter.swift`
   - `endAnnouncement()`：`let action = coordinator.deactivate()`；动作 `.none` → 直接 `return false`（无平台调用、无状态变更）；否则 `try perform(action)`（抛错直接向上抛，`state` 不变）→ 成功后 `coordinator.commitDeactivation()` → `return true`。
   - 不引入重试谓词与回滚 API。
3. `ios/PurePace/Audio/AnnouncementSpeaker.swift`
   - `onFinish`：`do { sessionDeactivated = try audioSession.endAnnouncement(); outcome = sessionDeactivated ? .success : .notApplicable } catch { outcome = .failed(error, 前状态/后状态 = audioSession.state, platformCallIssued: true) }`；然后 `diagnostics.record(outcome)` 与 `telemetry.recordFinished(..., sessionDeactivated:, duckRevoked: sessionDeactivated)`；`catch` 内**不再只写 false 就结束**。
   - 注入接缝：`init` 增加带默认值的诊断写入器参数（默认生产实现写固定路径文件），既有调用点（`ContentView.swift:52`、`RunSessionViewModel.swift:63`）零改动。
4. 新增 `ios/PurePace/Audio/AnnouncementDeactivationDiagnostics.swift`（XcodeGen 按目录收源，`project.yml` 不动）
   - `AnnouncementDeactivationOutcome`（`.success` / `.notApplicable(...)` / `.failed(...)`）、`AnnouncementDeactivationDiagnosing` 协议、文件写入实现（可注入目录 `URL` + `FileManager`；默认 Documents 下固定相对路径 `Diagnostics/announcement-deactivation.json`；JSON 编码 + `NSLock` + 原子写 `Data.write(options: .atomic)`；读旧文件不存在/损坏时重置为空并把错误吞掉）。
5. 测试落点（全部在既有门内，不改门列表）
   - `ios/PurePaceTests/AnnouncementSpeakerTests.swift`（`scripts/test-ios.sh --unit-only` 的 `PurePaceTests` 腿）：
     - A：既有 `testActiveSessionDeactivationWritesTrueDerivationsAndSinglePlatformCall` 保留并补 `deactivations.count == 1`（正常路径调用次数不变的断言位置即此处 `activationCalls.map(\.active) == [true, false]`）。
     - B：改写 `testThrownDeactivationProducesObservedFalseFingerprintAndNextActivation` 为 `testThrownDeactivationKeepsActiveStateWritesFailureDiagnosticsAndRetriesNone`（读临时目录 JSON 断言 domain/code/state/platformCallIssued 与下一次激活序列）。
     - C：扩展 `testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates`，断言 `outcome="not-applicable"`、错误字段为 null、`platformCallIssued=false`、无 `failed` 记录。
     - 诊断文件断言用 `FileManager` 临时目录注入，不读真实容器。
   - `ios/RunCore/Tests/PurePaceRunCoreTests/AudioSessionCoordinatorTests.swift`：`deactivate()` 纯推导（`.active` 返回动作但 state 不变；`.inactive`/`.interrupted` 返回 `.none` 且不变）、`commitDeactivation()`（`.active → .inactive`；`.inactive`/`.interrupted` 不变；不返回动作）。
6. 回执必须写清：四条修改的落点（文件+方法）与「失败不提交、无重试、无回滚」的证据；诊断文件固定路径与 JSON 字段；A/B/C 三条用例名与实跑结果；「正常路径平台调用次数不变」的断言位置；`bash scripts/test-ios.sh --unit-only` 与 `swift test --package-path ios/RunCore` 的实跑结论。

## 证据与措辞边界

- 允许写：**代码缺陷（吞错 / 状态先于平台调用提交 / 返回值语义错）成立**。
- 必须写：**设备侧成因未排他、缺 OSStatus**。
- 禁止写：**根因已定位**（或任何等价断言）。
- 引用 digest 数字必须标口径，例如：三条播报条目（**播报条数口径 = 3**，不是测试用例数）、`2c7c4f3` 窗口 `trun_fa2b41fa85283565`、同文件既有停用边界复现用例 **4 例（用例数口径）**、`AnnouncementSpeakerTests` 单文件用例数需按实跑 `Executed N tests` 口径记录；口径缺失按证据缺陷处理。
