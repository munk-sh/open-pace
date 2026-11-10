# 定性真机播报遥测矛盾：`sessionDeactivated` / `duckRevoked` 恒为 false（window-2c7c4f3）

## 范围

只做「定性 + 可复现测试 + 最小修法建议」，**不在本项内改生产业务语义**（公司裁决 `owe_ad57c85dda3ddb10`）。
交付三件，顺序不可颠倒：

1. **定性结论落盘** `.munk/changes/wi_intake_f76b858c0c2376f5/digest.md`：把 window `trun_fa2b41fa85283565`（Release 候选 2c7c4f3，证据 `artifacts/evidence/window-2c7c4f3/`）暴露的矛盾归入 `①遥测派生字段写错` / `②回调时序导致状态机已非 active` / `③停用调用抛出被吞（错误未落盘）` 之一，并逐条给出代码位置（文件 + 函数 + 分支条件，含行号）、可复现测试名、证据读数。
2. **确定性复现**：用既有可注入桩（`AudioSessionControlling` / `SpeechSynthesizing` / `AudioSessionAdapter(observesInterruptions: false)` + `handleInterruption`）写单测，把「字段写 false 的分支」与「字段写 true 的分支」各复现至少一次，并断言 `sessionDeactivated` / `duckRevoked` / `isOtherAudioPlaying` / `secondaryAudioShouldBeSilencedHint` 的落盘值与平台调用序列；测试不依赖真机、不依赖真实音频。
3. **最小修法 + 影响面**：若定性判定为产品缺陷（播完 duck 未真正撤销 / 音量不恢复），在 digest 的「最小修法」段写清最小改动文件与影响面，**交 Owner 另派写项**；仅修遥测的结论同样只写建议，不落地。

本项允许新增/扩展测试代码；不修改 `ios/PurePace/Audio/**`、`ios/RunCore/Sources/**` 的生产行为与遥测 JSON 契约。

## 验收

- ac-verdict-single-cause: `digest.md` 顶部含 `verdict: 1|2|3`（三选一），且结论段不出现「需进一步观察 / 可能 / 猜测 / 待现场判定」作为结论；被排除的两个机制各自给出排除依据（对应测试名或证据读数）。
- ac-writer-branch-mapping: digest 给出写入方与分支表，至少覆盖：`AnnouncementTelemetryRecorder.recordFinished` 写入 `sessionDeactivated`/`duckRevoked`；取值来自 `SpeechAnnouncementSpeaker.speak` 的 `onFinish` 闭包（`sessionDeactivated = try audioSession.endAnnouncement()`，`duckRevoked: sessionDeactivated`）；`AudioSessionAdapter.endAnnouncement` 的 `performed = action != .none`；`AudioSessionCoordinator.deactivate` 的 `guard state == .active`；并明确什么条件写 false、什么条件写 true。
- ac-repro-true-branch: 存在测试证明「播报期间协调器保持 `.active` → didFinish → 下发恰好一次 `setActive(false, .notifyOthersOnDeactivation)` → `sessionActivated=true`、`sessionDeactivated=true`、`duckRevoked=true`、`finishedAt != nil`、`cancelled=false`」。
- ac-repro-false-branch-interruption: 存在测试证明「播报中收到 `interruption began` → 状态转 `.interrupted` → didFinish 时 `deactivate` 返回 `.none`、无 `setActive(false)`、`sessionDeactivated=false`、`duckRevoked=false`」；并断言随后 `interruptionEnded(shouldResume: false)` 后下一次播报重新下发激活（`sessionActivated=true`）。
- ac-repro-false-branch-throw: 存在测试证明「`setActive(false)` 从注入控制器抛出 → 异常被 `speak` 的 catch 吞掉 → `sessionDeactivated=false`、`duckRevoked=false`，但协调器状态已先转为 `.inactive`，因此下一次播报仍 `sessionActivated=true`」；该用例必须能同时出现 `sessionActivated=true` + `sessionDeactivated=false` + `finishedAt != nil` + `cancelled=false`（即真机观测到的字段指纹）。
- ac-fingerprint-discrimination: digest 含指纹矩阵，逐条列出三种机制在「三条播报均 `sessionActivated=true`」「`finishedAt` 均已回调且 `cancelled=false`」「真机播报时长 4.49s/4.15s/4.47s 未被截断」上的预测与观测，并据此说明为何只有一种机制自洽；矩阵不得只给结论而无逐格预测。
- ac-derived-fields-provenance: digest 说明 `isOtherAudioPlaying` / `secondaryAudioShouldBeSilencedHint` 的写入方与读取时机（`AudioSessionAdapter.announcementContext`，在 `beginAnnouncement` 之后、`synthesizer.speak` 之前读取，经 `recordStarted` 落盘），并判定其与 `sessionDeactivated`/`duckRevoked` 是否同一类问题；测试需覆盖注入 `true/true` 与 `false/false` 两值透传，证明未被写死或从旧快照取值。
- ac-no-production-semantic-change: `git diff` 不触碰 `ios/PurePace/Audio/**`、`ios/RunCore/Sources/**`、`ios/PurePace/Run/RunTelemetry.swift` 的生产行为；遥测 JSON 字段集合与含义不变；仅新增/扩展 `ios/PurePaceTests/**`。
- ac-minimal-fix-proposal: digest 的「最小修法」段给出：改动文件与函数、为何是最小、对现有调用序列/遥测契约/旧记录解码的影响面；若结论为「仅遥测语义」则明确写出「不修真实音频行为」；若为产品缺陷则明确写出「需另派写项，本项未修」。
- ac-evidence-refs: digest 引用 `artifacts/evidence/window-2c7c4f3/evidence/container-runs-B/20261110T024456Z-04AB2F11-3785-49F8-A266-BE92CD3C7CDD.json` 与 `.../analysis-B.txt` 的具体字段值与时间戳，不写「见证据目录」这类空引用。
- ac-gates-green-no-weakening: `.munk/code-gates.json` 门 id 与 command 均不变（不新增、不放宽）；`test-ios`（`bash scripts/test-ios.sh --unit-only`）、`test-ios-core`、`test-ios-run-core`、`build-ios`、`lint-ios-*` 全绿；不删既有断言、不加 skip / continue-on-error。
- ac-budget-stop: 90 分钟或 10M token 触顶时立即停手，回执写明已完成到哪一步（定性 / 复现 / 修法建议）、未完成项与原因。

## 非目标

- **不修产品行为**：不改 `AnnouncementSpeaker` / `AudioSessionAdapter` / `AudioSessionCoordinator` / `AnnouncementTelemetryRecorder` 的任何生产逻辑与默认值；不改 `.duckOthers`/`.mixWithOthers` 配置、播报文案与调度。
- **不改遥测 JSON 契约**：本项不新增字段、不改字段语义（如需新增「错误码/结束时状态」字段，只写进修法建议，另派写项）。
- 不改 Info.plist / bundle id / 签名与 `ios/project.yml` / `VERSION`。
- 不改定位、持久化、GPX 导出契约；不改 `.github/workflows`；不新增门腿。
- 不跑真机窗口、不排人耳、不装音频源（设备侧窄场复验由 Owner 另行排）。
- 不做 UI / Android / `shared/`；不为了面板好看弱化或改写真实音频行为。
- 不重构现有状态机、不顺手清理既有测试。

## 实现约束

### 证据基线（Intake 已读，Coding 需复核）

- 三条播报落盘值完全同构：`category=playback`、`mode=spokenAudio`、`categoryOptions=[duckOthers,mixWithOthers]`、`sessionActivated=true`、`sessionDeactivated=false`、`duckRevoked=false`、`isOtherAudioPlaying=true`、`secondaryAudioShouldBeSilencedHint=true`、`cancelled=false`、`finishedAt` 均已写入。
- 时间戳（UTC）：`02:45:47.67→02:45:52.16`（4.49s）、`02:46:37.51→02:46:41.66`（4.15s）、`02:47:28.52→02:47:32.97`（4.46s）；播报前 02:45:29 有 `didEnterBackground`、02:45:32 `willEnterForeground` 一次抖动（该 pair 早于第一条播报 15s）。
- 判据：`finishedAt` 存在 ⇒ `onFinish` 闭包执行，`endAnnouncement()` 必被调用；`sessionDeactivated=false` 只可能来自「`deactivate()` 返回 `.none`」或「`perform` 抛出后被 catch」。因此 ①（陈旧快照）需先被证伪，②/③ 必须二选一。
- Intake 侧的初步判据（Coding 必须用测试确认或推翻，不得直接抄写）：真机 TTS 时长与文本长度匹配且 `cancelled=false`，说明播报期间会话未被中断截断；而 ② 要在「每条播报都 `sessionActivated=true`」的同时成立，需要每次播报中都出现 `began` 且在下一条播报前以 `shouldResume=false` 结束，与「音频未被打断」矛盾；③ 则天然满足三条全为 `sessionActivated=true`（`deactivate()` 先把状态改为 `.inactive`，随后 `perform` 抛错）。若测试推翻该判据，digest 必须写清推翻依据并改判。

### 代码锚点（HEAD 与 2c7c4f3 对 `ios/PurePace/Audio`、`ios/PurePace/Run` 无差异，已用 `git diff` 核对）

- `ios/PurePace/Audio/AnnouncementSpeaker.swift:104-144`：`speak`；`:109-114` 激活（失败只记 `sessionActivated=false`，不打断）；`:117` 取快照；`:126-143` `onFinish`；`:130-135` `do/catch`，catch 里写 `sessionDeactivated = false`（**错误对象被丢弃**）；`:136-142` 写 `sessionDeactivated` 与 `duckRevoked: sessionDeactivated`（派生字段同源）。
- `ios/PurePace/Audio/AudioSessionAdapter.swift:124-133`：`announcementContext`（两个只读布尔在此读取，位于激活之后）；`:136-142` `beginAnnouncement`；`:146-152` `endAnnouncement`（先取 `action` 再 `perform`，`performed` 由 `action` 决定）；`:216-230` `perform`（`.deactivate` → `setActive(false, options)`，可抛）；`:232-238` `performIgnoringErrors`（中断路径吞错）。
- `ios/RunCore/Sources/PurePaceRunCore/AudioSessionCoordinator.swift:39-51`：`activate` 仅在 `.inactive` 生效；`deactivate` 仅在 `.active` 生效，且**先改状态后返回 action**；`:55-60` `interruptionBegan`；`:66-74` `interruptionEnded`（`shouldResume=true` 会重激活，`false` 回 `.inactive` 且无动作）。
- `ios/PurePace/Audio/AnnouncementTelemetry.swift:39-64`：`recordStarted` 以 `sessionDeactivated=false`/`duckRevoked=false` 建条目；`:88-135` `recordFinished` 覆写两字段；`:143-151` 按 `splitIndex` + `finishedAt == nil` 定位条目。
- `ios/PurePace/Run/RunTelemetry.swift:20-121`：`RunTelemetryAnnouncement` 的 Codable 契约（本项不改）。
- 既有测试落点：`ios/PurePaceTests/AnnouncementSpeakerTests.swift:163-205`（正常路径已断言 true）、`ios/PurePaceTests/AudioSessionAdapterTests.swift:47-180`（中断映射、幂等）。
- 新增测试建议集中于一个新文件（如 `ios/PurePaceTests/AnnouncementDeactivationBoundaryTests.swift`），避免改动既有断言。

### 测试口径

- 只用既有接缝：`AudioSessionControlling` 桩（可注入 `throw` 的 `setActive`）、`SpeechSynthesizing` 桩、`AudioSessionAdapter(controller:observesInterruptions: false)` + `handleInterruption(_:)`，以及 `AnnouncementTelemetryRecorder`。
- 断言「下发了什么调用、调用顺序/次数、遥测落盘值」，不断言真实听感、不启动模拟器音频、不读真实 `AVAudioSession` 状态作为判据（`AudioSessionAdapterTests` 既有的真会话回读用例保持原样）。
- 每条 AC 的断言落点写进回执（文件 + 用例名 + 断言项），并附一次 `test-ios` 实跑摘要（`** TEST SUCCEEDED **` 或仅相关用例的单跑输出）。

### 定性写作口径

- 先写「字段写入链路 → 分支条件表」，再写「证据指纹矩阵」，最后才是 `verdict`；`verdict` 必须唯一。
- 每条被排除机制给出「证伪测试名 / 证据读数」；不得用「设备上无法观测」代替证伪。
- 定性与修法建议分离成两节；修法建议不得暗示本项已改动生产代码。
