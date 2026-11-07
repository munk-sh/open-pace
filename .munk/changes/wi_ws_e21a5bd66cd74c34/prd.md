# 每公里播报调度与 AudioSession 配置/中断恢复契约

## 范围

在既有 `ios/RunCore`（SwiftPM 包 `PurePaceRunCore`，纯 `Foundation`、零第三方依赖、显式 `Sendable`）内补齐两块**纯逻辑契约**，不接平台框架、不接 UI、不实际发声：

1. `AnnouncementScheduler`（值类型 `struct`，`Sendable`，位于 `Sources/PurePaceRunCore/`）
   - 输入：`RunMetricsUpdate` / `RunMetrics`（复用 `newlyCompletedSplits`、`splits`、`completedKilometers`、`elapsed`）+ 调用方传入的 `RunSessionState`；输出：按序的 `[AnnouncementCommand]`（复用既有 `AnnouncementTrigger` / `AnnouncementCommand`，不新增播报数据类型）。
   - 规则：公里边界 → 播报队列「一次且仅一次」；重复 tick 去抖；`paused` 不播；`finished` 停止并只补一条收尾；`paused→running` 恢复时对未播公里**最多补播一次**。
2. `AudioSessionCoordinator` + 契约常量（值类型 `struct`/`enum`，`Sendable`，不 `import AVFoundation`）
   - 冻结公告音频配置：`category == .playback`、`mode == .spokenAudio`、激活选项恰为 `{duckOthers, mixWithOthers}`、停用选项恰为 `{notifyOthersOnDeactivation}`。
   - 冻结 interruption 状态机：`began` / `ended(shouldResume:)` 的状态与动作序列，停用时动作携带 `.notifyOthersOnDeactivation`。
   - `AudioSessionSettings` / `AudioCategory` / `AudioMode` / `AudioCategoryOption` 为既有纯数据镜像，本项只补齐 `notifyOthersOnDeactivation` 的表示与默认公告配置，不改其原始值。

测试落在 `Tests/PurePaceRunCoreTests/`（XCTest），新增用例覆盖下述 `ac-*`；`.munk/code-gates.json` 沿用既有 `lint-ios-run-core` / `build-ios-run-core` / `test-ios-run-core` 三门，本项默认不改门禁与 `scripts/**`。

对齐检查点：`cp-tts-audio-contract`（本项直接关闭）、`cp-stage2-exit`（本项只提供代码层证据，不关闭该检查点）。

## 验收

- ac-announcement-exactly-once-per-km: 连续 tick 覆盖第 1..N 个整公里时，每个 `splitIndex` 恰好产生 1 条 `trigger == .kilometerCompleted` 的命令；全程命令序列中任何 `splitIndex` 都不重复出现，且序号严格递增。
- ac-announcement-duplicate-tick-debounced: 用**完全相同**的 `RunMetricsUpdate`（含 `newlyCompletedSplits` 非空）连续 tick 两次，第二次返回空数组；重复 tick 10 次仍只有首次那批命令，`metrics.completedKilometers` 不变时不再产出任何命令。
- ac-announcement-paused-suppressed: 状态为 `.paused` 时 tick 恒返回空数组；即使同一 tick 携带 `newlyCompletedSplits` 也不产出；`.ready` 状态同样恒返回空数组。
- ac-announcement-finished-stops: 进入 `.finished` 时最多产出 1 条 `trigger == .finished` 命令（`splitIndex == 已完成公里数`，`elapsed == metrics.elapsed`）；若已完成公里数为 0 则不产出（`AnnouncementCommand` 不允许 `splitIndex == 0`）；此后任意 tick（含再次传入 `finished` 或新分段）恒返回空数组，不再出现 `.kilometerCompleted`。
- ac-announcement-resume-catch-up-once: `paused → running` 后的首次 tick，对「已完成但未播报」的公里最多产出 1 条 `trigger == .resumedAfterPause` 命令，其 `splitIndex` 为未播报的最大公里序号；同一恢复期再次 tick（无新公里）返回空；第二次 `paused → running` 若无新的未播公里亦返回空；未播的中间公里不得逐条补播（命令总数 ≤ 1）。
- ac-announcement-command-fields: 所有产出命令均非空校验通过（`splitIndex >= 1`、`elapsed` 有限非负），`distance.meters == splitIndex * 1000 ± 1e-9`，`pace` 与该分段 `RunSplit.pace` 一致，且 `elapsed` 单调不减；未满 1 公里时全程无命令。
- ac-audiosession-settings-values: 默认公告配置断言 `category == .playback`、`mode == .spokenAudio`、`options == Set([.duckOthers, .mixWithOthers])`（**恰好两项**，不多不少）、`deactivationOptions == Set([.notifyOthersOnDeactivation])`（**恰好一项**）。
- ac-audiosession-deactivate-option: `deactivate()` 返回的动作携带 `.notifyOthersOnDeactivation`（spy/动作值断言，而非注释或日志）；从 `.active` 停用后状态为 `.inactive`，从 `.inactive` 再次停用返回 `.none` 且状态不变。
- ac-audiosession-interruption-lifecycle: `.active` 收到 `interruptionBegan` → 状态 `.interrupted` 且不再产生激活动作；`interruptionEnded(shouldResume: true)` → 状态 `.active` 且动作等于按默认公告配置重新激活；`interruptionEnded(shouldResume: false)` → 状态 `.inactive` 且动作为 `.none`；重复 `began` 幂等（状态仍 `.interrupted`，不重复产生激活动作）；未处于 `.interrupted` 时收到 `ended` 返回 `.none` 且状态不变。
- ac-audiosession-activation-idempotent: `.inactive → activate()` 产出 1 次激活动作且状态 `.active`；`.active` 再次 `activate()` 返回 `.none`，状态仍 `.active`。
- ac-runcore-purity-preserved: `ios/RunCore/Sources/**` 仍只 `import Foundation`，不出现 `AVFoundation|AVAudioSession|AVSpeechSynthesizer|CoreLocation|UIKit|SwiftUI|Timer` 等平台符号，不新增 `class` / `actor` / 全局可变状态 / `@unchecked`，新增公开类型显式 `Sendable`，包依赖仍为空。
- ac-existing-contracts-unchanged: `RunSessionState` / `RunMetrics` / `RunSplit` / `RunMetricsEngine` 的既有公开签名、枚举 `allCases` 顺序与 rawValue、5 条合法迁移、阈值常量均不变；既有 34+10 个 RunCore 用例继续通过（若因新增 `notifyOthersOnDeactivation` 而更新 `AudioCategoryOption.allCases.count` 断言，只允许改该断言的数量与包含关系，不得删除既有用例）。
- ac-gates-green: 仓库根 `bash scripts/check-ios-run-core.sh`、`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore` 全部退出码 0 且无失败用例；`.munk/code-gates.json` 19 个既有 `id`/command 不变（本项不减少、不新增门）。
- ac-evidence-wording: 交付结论只允许写「配置与调度契约通过」；音乐是否真的只降不暂停、TTS 与音乐实听、锁屏后台连续定位一律记 `pending: 待人现场`，全文不得出现「已验证」「实听通过」「真机通过」。

## 非目标

- 不实现真实语音播放（`AVSpeechSynthesizer` / TTS 引擎）、不做音频路由与音量控制、不接 `AVAudioSession` 真实读回（读回属波 2 的 App target 适配子项）。
- 不接 UI、不改 `ios/project.yml` / `.xcodeproj` / `ios/PurePace/**`，不新增可执行 target。
- 不修改 `RunMetricsEngine` / `RunCheckpoint` / `RunCheckpointStore` / `RunSessionMachine` 的算法与语义；调度器只消费它们的输出，不反向依赖。
- 不做跨进程播报状态持久化（`checkpoint` 不新增「已播公里」字段）；`terminate→relaunch` 后不重播已播公里属波 2 编排，本项只保证单进程内 `paused/resume` 语义。
- 不把 AudioSession 中断与播报队列耦合（中断期间是否丢弃/重排命令不在本项定义），不新增节拍器、提示音、震动。
- 不触发真机/签名/CI 运行，不据此关闭 `cp-stage2-exit`。

## 实现约束

- 落点：`ios/RunCore/Sources/PurePaceRunCore/AnnouncementScheduler.swift`、`AudioSessionCoordinator.swift`（如新增 `AudioSessionAction` / `AudioSessionState` 可同文件或独立文件），测试落 `Tests/PurePaceRunCoreTests/AnnouncementSchedulerTests.swift`、`AudioSessionCoordinatorTests.swift`；不新建包、不新建 target。
- 纯逻辑红线：全 `struct`/`enum` 值语义 + `mutating` tick，无 `class`/`actor`/锁/全局状态；不引入时间源（不使用 `Date()`），时间统一取 `metrics.elapsed`，保证用例可确定。
- 输入口唯一：调度器签名建议 `mutating func tick(_ update: RunMetricsUpdate, state: RunSessionState) -> [AnnouncementCommand]`；调用方（波 2 Harness / 阶段 3 App）负责把 `RunSessionMachine` 状态与 `RunMetricsEngine` 输出喂进来。不新增第二套增量接口，不复刻分段判定逻辑（分段边界以 `newlyCompletedSplits` 为准，`distance`/`pace` 取 `RunSplit`）。
- 去抖与幂等靠内部 `lastAnnouncedSplitIndex`（或等价有序集合）实现；禁止依赖调用方去重，禁止用「距上次播报时间间隔」判定（无时钟源）。
- `notifyOthersOnDeactivation` 的表示：优先在既有 `AudioCategoryOption` 增加 `case notifyOthersOnDeactivation`，并同步把 `AnnouncementAndAudioTests.testAudioEnumCases` 的 `allCases.count == 4` 改为 5、断言包含该 case；若实现选择独立 `AudioDeactivationOption` 枚举，必须保留 `deactivationOptions` 的可断言能力且不破坏既有 `AudioSessionSettings` 相等性用例。两条路二选一，不得同时改 `AudioCategoryOption` 的既有 rawValue。
- 既有契约红线：`AnnouncementCommand` 校验（`splitIndex >= 1`、`elapsed` 有限非负）不得放宽；不新增 `AnnouncementTrigger` case；不改 `RunSessionState` case 顺序与 rawValue。
- 证据口径：`swift test` 只报真实用例数与失败数；`check-ios-run-core.sh` 只报 PASS 计数；不得写「已验证」「实听通过」「真机通过」「音乐不打断已验证」，真机项统一 `pending: 待人现场`。
