# Domain: ios-audio-session

播报音频会话子域：`ios/PurePace/Audio/**` 的激活/停用执行与 `ios/RunCore` 内 `AudioSessionCoordinator` 的停用片段。只管会话激活/停用语义、失败可观测性与平台调用真实结果；每公里播报调度、文案模板与遥测 JSON 契约仍归 `ios-run-telemetry` / `ios-runcore`。

## Scope

- `ios/RunCore/Sources/PurePaceRunCore/AudioSessionCoordinator.swift`：`deactivate()` 改为非 mutating 纯动作推导（`state == .active` 返回 `.deactivate(options: settings.deactivationOptions)`，否则 `.none`，任何情况下不改 `state`）；新增 `commitDeactivation()`（`guard state == .active` → `.inactive`，不产生/返回动作、不触碰平台）。
- `ios/PurePace/Audio/AudioSessionAdapter.swift`：`endAnnouncement()` 语义改为「动作 `.none` → 返回 `false` 且不调平台；否则 `perform(action)`（抛错上抛、`state` 不变）→ 成功后 `commitDeactivation()` → 返回 `true`」。
- `ios/PurePace/Audio/AnnouncementSpeaker.swift`：`onFinish` 停用失败不再静默，构造 `.failed` 诊断并 `record`，`sessionDeactivated` / `duckRevoked` 如实 `false`，`finishedAt` / `cancelled` 照常写入；`init` 增加带默认值的诊断写入器参数（既有调用点零改动）。
- `ios/PurePace/Audio/AnnouncementDeactivationDiagnostics.swift`（新增）：`AnnouncementDeactivationOutcome`（`success` / `notApplicable` / `failed`）、`AnnouncementDeactivationDiagnosing`、文件写入实现（可注入基目录 + `FileManager`，生产默认 Documents 下固定相对路径）。
- 测试落点：`ios/PurePaceTests/AnnouncementSpeakerTests.swift`、`ios/RunCore/Tests/PurePaceRunCoreTests/AudioSessionCoordinatorTests.swift`，均在既有门内，不新增门。
- `ios/PurePace.xcodeproj/project.pbxproj` 由 XcodeGen 按目录收源重生成（仅新增该源文件的 PBXBuildFile / PBXFileReference / group / Sources 条目）；`ios/project.yml` 零改动。

## Acceptance

- ac-no-silent-catch: 停用失败时 `onFinish` 的 `catch` 不得静默：必须写出结构化诊断记录（含错误域、错误码、协调器状态、是否真实下发平台调用），同时 `sessionDeactivated=false`、`duckRevoked=false`（不得伪造 true）；`finishedAt` / `cancelled` 仍如实写入。
- ac-commit-after-platform-success: 停用状态提交发生在平台调用成功之后 —— `deactivate()` 只做纯动作推导、不改变 `state`；`commitDeactivation()` 仅在解析到 `.deactivate` 且 `setActive(false, …)` 真实成功后置 `state = .inactive`；平台调用抛错时 `state` 保持 `.active`（不提交，也不存在「先提交再回滚」代码路径）。
- ac-end-returns-real-result: `endAnnouncement()` 返回 `true` 当且仅当 `setActive(false, [.notifyOthersOnDeactivation])` 真实执行成功；协调器动作 `.none`（如 `.interrupted` / 已 `.inactive`）时返回 `false` 且不发起任何平台调用；平台调用抛错时把错误抛出（不得吞成返回值）。
- ac-no-retry-no-compensation: 一次结束路径最多下发 1 次 `setActive(false)`；不得引入重试、回滚 API 或任何补偿性状态改写（「盲重试一次 + 失败回滚 `.active`」方案已被公司裁决否决，不得复活）。
- ac-diagnostics-file-path: 诊断记录写入 App 数据容器内固定路径 `Documents/Diagnostics/announcement-deactivation.json`（相对 `appDataContainer`；生产由 `FileManager` 的 Documents 目录拼出，不写死绝对路径；测试可注入临时目录）；JSON、追加保留历史、原子替换、线程安全；写盘失败必须被吞掉且不打断播报，不得抛到播报路径。
- ac-diagnostics-schema: 文件结构为 `{"version": 1, "outcomes": [ … ]}`，每条记录字段固定为 `splitIndex`、`occurredAt`（epoch 秒）、`outcome`（`"failed"` | `"not-applicable"`）、`errorDomain`（string 或 null）、`errorCode`（int 或 null）、`coordinatorStateBefore`、`coordinatorStateAfter`（`"inactive"|"active"|"interrupted"`）、`platformCallIssued`（bool）；成功路径不写记录。
- ac-diagnostics-pullable: 该路径可由 `xcrun devicectl device copy from --domain-type appDataContainer --source Documents/Diagnostics/announcement-deactivation.json`（或 `xcrun simctl get_app_container <udid> <bundle-id> data` 后直接读）取出；不修改任何采集/CI 脚本，仅保证路径固定可拉取。
- ac-success-path: A 成功路径 —— 协调器 `.active` 时结束播报，返回值 `true`，落盘 `sessionDeactivated=true`、`duckRevoked=true`，平台 `setActive` 序列恰为 `[true, false]`（激活 1 次、停用 1 次，正常路径调用次数不变），协调器 `.inactive`，诊断文件不新增记录。
- ac-throw-path: B 抛错路径 —— 首次 `setActive(false)` 抛错时：`deactivations.count == 1`（无重试）、协调器 `state` 保持 `.active`（未提交）、`sessionDeactivated=false`、`duckRevoked=false`、诊断文件新增 1 条 `outcome="failed"` 记录且 `errorDomain` / `errorCode` 与注入错误一致、`coordinatorStateBefore == "active"`、`coordinatorStateAfter == "active"`、`platformCallIssued == true`；同一播报器下一次播报的激活序列正确（协调器仍 `.active` → `beginAnnouncement()` 返回 `false`、不再下发 `setActive(true)`，其结束后仍下发 `setActive(false)` 并落盘 `sessionDeactivated=true`）。
- ac-interrupted-path: C `.interrupted` 路径 —— 播报中进入 `.interrupted` 后结束播报：`deactivate()` 动作 `.none`、无平台停用调用、`sessionDeactivated=false`、`duckRevoked=false`；诊断文件新增 1 条 `outcome="not-applicable"` 记录（`errorDomain == null`、`errorCode == null`、`platformCallIssued == false`），且**不存在** `outcome="failed"` 记录。
- ac-telemetry-contract-unchanged: 遥测 JSON 字段契约不变 —— `telemetry.announcements[]` 字段名、类型与语义均不增不改（不新增 not-applicable / 错误码字段），`RunTelemetryAnnouncement` 保持原样；`not-applicable` 只体现在诊断文件，不回灌遥测。
- ac-config-unchanged: 播报 category/mode/options 仍为 `playback` / `spokenAudio` / `[duckOthers, mixWithOthers]`，停用选项仍为 `[.notifyOthersOnDeactivation]`；每公里播报调度、文案模板、GPX 导出/持久化/定位契约端到端不变；不改 `ios/project.yml` / `Info.plist` / bundle id / 签名 / `VERSION`。
- ac-gates-green: `bash scripts/test-ios.sh --unit-only`、`swift test --package-path ios/RunCore` 与 `.munk/code-gates.json` 全部既有门本地全绿；不新增 CI 腿、不改 600s 预算、不改 `.github/workflows/**`、不改门列表。
- ac-tests-not-weakened: 已有测试不得删除或放宽；语义随本次变更的既有断言按新语义改写并注明（协调器停用用例改为 deactivate→commit 两段；原抛错指纹用例改写为 B 且不降级）；播报中中断用例保留并加 C 的诊断断言。

## Non-Goals

- 不做任何重试（含「仅对 `isBusy` / `resourceNotAvailable` 重试一次」）、不做状态回滚/补偿；真实 OSStatus 到手后另派项决定策略。
- 不改遥测 JSON 契约（不加错误码 / not-applicable 字段）。
- 不重构 `AudioSessionCoordinator` 其余转移（`activate()` / 中断 began/ended 的提交顺序保持现状，本次只改停用提交时机）。
- 不处理 `beginAnnouncement()` 激活失败分支的日志与状态一致性（另一条线）。
- 不改 `Info.plist` / `ios/project.yml` / bundle id / 签名 / 根 `VERSION`；不跑真机、不出候选包、不改 CI workflow 与预算、不新增 CI 腿、不改 `scripts/verify-*.sh`。
- 不改主 App 的 AudioSession category/options 配置。

## Implementation Constraints

- 停用提交唯一入口：`commitDeactivation()` 只由 `AudioSessionAdapter.endAnnouncement()` 的平台调用成功分支调用；不得在别处直接改 `AudioSessionState` 绕开该入口。
- 一次结束最多 1 次平台停用：动作 `.none` 直接返回 `false`，不做「先停用再判类型」；错误原样上抛，不转成布尔返回值，不引入重试谓词或回滚 API。
- 诊断写入：固定相对路径 `Diagnostics/announcement-deactivation.json`，拼在注入基目录（生产 = Documents）下；`NSLock` 串行 + `Data.write(options: .atomic)`；读旧文件不存在/损坏时重置为空；读或写失败一律吞掉，绝不抛到播报路径。
- 注入接缝保持既有调用点零改动：`SpeechAnnouncementSpeaker.init` 的诊断写入参数必须带默认值，`ContentView` / `RunSessionViewModel` 不新增传参。
- 证据口径：设备侧成因未排他、缺 OSStatus；可写「代码缺陷（吞错 / 状态先于平台调用提交 / 返回值语义错）成立」，禁止写「根因已定位」；引用 digest 数字须标口径（播报条数 = 3、同文件既有停用边界复现用例数 = 4、单文件用例数按 `Executed N tests` 实跑口径）。

## Latest Delivery Proof

- workItemId: wi_intake_2ba71ae036eedd40（2026-11-10，pass，只取代码层与模拟器单测腿证据）
- 交付：`AudioSessionCoordinator.deactivate()` 改纯动作推导 + 新增 `commitDeactivation()`；`AudioSessionAdapter.endAnnouncement()` 改为「`.none` → false / 平台成功提交后 true / 抛错上抛」；`SpeechAnnouncementSpeaker.onFinish` 失败写结构化诊断、两派生字段如实 false；新增 `AnnouncementDeactivationDiagnostics`（固定路径 JSON、`version: 1` + `outcomes[]` 八字段、`NSLock` + 原子写、写盘失败吞掉）；XcodeGen 重生成 `project.pbxproj` 新增 4 条条目，`ios/project.yml` 零改动。
- 验证：`code_gates` 22 门全绿（attempt 002）—— `bash scripts/test-ios.sh --unit-only` exit 0（`PurePaceTests` 104 例 0 失败 + RunCore `Executed 125 tests` 0 失败）；`AnnouncementSpeakerTests` 12 例（A/B/C 新语义 + 既有用例未删未放宽）、`AudioSessionCoordinatorTests` 9 例（`deactivate()` 纯推导 / `commitDeactivation()` 两组）；`swift test --package-path ios/RunCore` 125 例 0 失败。设备侧窄场复验与真实 OSStatus 仍 `pending: 待人现场`。
