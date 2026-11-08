# Domain: ios-runcore-session

`ios/RunCore`（模块 `PurePaceRunCore`）内的面向 UI 的会话编排器子域：以值类型 `RunSessionOrchestrator` 把阶段 2/3 已冻结的 `RunSessionMachine`（状态迁移）、`RunMetricsEngine`（计时/距离/配速/分段）、`AnnouncementScheduler`（每公里播报）、`RunCheckpointStore`（JSONL 落盘）与 `RunRecord`/`RunArchiveStore`（结束归档）组装成 UI 可直接驱动的单一入口。只委托、不复制任何算法或规则；纯逻辑 + `Foundation`，不接 App target / 平台框架。

## Scope

- 全部新增，不改既有文件：`ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift`；测试 `ios/RunCore/Tests/PurePaceRunCoreTests/RunSessionOrchestratorTests.swift`。不改阶段 2/3 源文件、既有测试、`Package.swift`、`scripts/**`、`.munk/code-gates.json`。
- `RunSessionOrchestrator`：`struct` + 显式 `Sendable`；`init(checkpointStore:archiveStore:announcementsEnabled: Bool = true)`；`public private(set) var state: RunSessionState`、`public var metrics: RunMetrics`、`public var announcementsEnabled: Bool`。
- 会话动作：`start(at:)`/`pause(at:)`/`resume(at:)`/`finish(at:)` 与 `ingest(_:)` 均 `mutating` + `throws`；时间一律由调用方以 `Date` 注入，不使用时钟/定时器/`Date()` 现时；状态合法性只看 `RunSessionMachine`。
- 返回值：小型值类型 `RunSessionUpdate { state, metrics, announcements }`；`finish` 返回 `RunRecord?`。
- 采样摄入：`ingest(_:)` 仅在 `running` 下把度量语义交给 `RunMetricsEngine.ingest`；同时维护按时间严格递增的归档采样序列（`altitude`/`heartRate`/`cadence` 全保留），结束归档与后续 GPX 导出共用同一批数据。
- checkpoint 追加：每次成功迁移（start/pause/resume）后追加一条，每个被接受的运行期采样后追加一条；内容由 `RunMetricsEngine.metrics` + `lastAcceptedSample` + `AnnouncementScheduler.announcedSplitIndex` 组装 `RunCheckpoint`（`recordedAt` 用本次注入的 `Date`），不另造字段。
- 播报开关：`setAnnouncementsEnabled(_:)` 控制是否对外暴露 `AnnouncementCommand`；关闭时仍推进调度器（吞掉命令），重新开启不补播被抑制的公里。
- `finish` 顺序：机器迁移 → 引擎 `finish(at:)` → 调度器收尾命令 → 组装 `RunRecord`（`startedAt` 用本会话 `start` 注入日期）→ `RunArchiveStore.save` → `RunCheckpointStore.reset()` → 返回记录；重复 `finish` 直接返回 `nil`。

## Acceptance

- ac-start-ready-to-running: `ready` 上 `start(at: t0)` → `state == .running`，`metrics.distance == 0`、`elapsed == 0`、`splits` 空、`currentPace == nil`；checkpoint 文件真实存在且 `loadAll()` 恰 1 条（`state == .running`、`completedDistance == 0`、`elapsed == 0`）。
- ac-ingest-accumulates: `start` 后喂入 3 个时间/坐标递增采样 → `distance` 等于按 `GeoDistance` 逐段累加期望值（容差 1e-6）、`elapsed` 等于首末时间差、运行期归档序列恰为这 3 个采样（顺序与字段一致）。
- ac-pause-zero-growth: 运行中 `pause(at: tP)` 后继续喂入坐标大幅跳变采样 → `distance`/`elapsed`/`splits` 与暂停快照完全相等，`currentPace == nil`，`announcements` 空，且暂停期采样不进入归档序列。
- ac-resume-continues: `resume(at: tR)` 后首个采样只重建锚点（距离不增），`elapsed` 增量为 `sample.timestamp - tR`；其后采样正常累加，跨整公里产出对应 `splitIndex` 播报。
- ac-finish-archives-once: 首次 `finish(at: tF)` 返回非空 `RunRecord`，归档目录恰 1 个 `.json` 且新 store 实例可 `list()` 读回；再次 `finish` 返回 `nil`、不抛错、文件数仍 1、记录内容不变。
- ac-finish-record-matches-session: 归档记录 `startedAt`/`endedAt` 等于注入日期，`distance`/`activeDuration`/`splits` 与 `finish` 时刻 `metrics` 逐项相等，`samples` 与运行期归档序列逐项相等。
- ac-finish-resets-checkpoint: `finish` 成功后 `RunCheckpointStore.loadAll()` 返回空数组，归档文件仍在。
- ac-sample-monotonic-gate: 时间戳等于或早于上一条已接受采样 → 度量/分/归档序列不变且不违反 `RunRecord` 采样非递减；`ready`/`finished` 下 `ingest` → 状态、度量、checkpoint、归档一律不变（不转调引擎）。
- ac-announce-toggle-off: 默认开启，跨第 1 公里恰 1 条 `splitIndex == 1`；关闭后跨第 2 公里命令空；重启后下一次摄入仍空（不补播）；再跨第 3 公里恰 1 条 `splitIndex == 3`。
- ac-invalid-transitions: `ready` 上 `pause`/`resume`/`finish`、`running` 上重复 `start`、`finished` 上任意动作 → 抛 `RunCoreError.invalidStateTransition`（`from`/`to` 与调用一致），状态不变，checkpoint 行数与归档文件数不增。
- ac-existing-contracts-intact: `git diff` 中 `ios/RunCore` 只出现新增文件；`RunSessionMachine`/`RunMetricsEngine`/`AnnouncementScheduler`/`RunCheckpoint*`/`RunRecord`/`RunArchiveStore`/`RunCoreError` 既有 public 契约与语义不变；既有 110 例测试全部通过。
- ac-gates-green: `bash scripts/check-ios-run-core.sh`、`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore` 均退 0；`swift test` 失败 0、执行数 ≥ 110，新增用例覆盖全部 ac-*。

## Non-Goals

- 不做跨进程恢复编排（不新增 restoring 初始化器）：checkpoint 只存最后锚点，无法还原完整采样序列，恢复会静默丢轨迹，留给后续子项。
- 不接 App target：不改 `ios/project.yml`、不改 App 源码、不做 SwiftUI View/ViewModel/首屏跑步页。
- 不接平台框架：无 CoreLocation/AVFoundation/AVAudioSession/SwiftUI/UIKit/URLSession/Timer/数据库；不做 TTS 实际播放与 AudioSession 配置，只产出既有 `AnnouncementCommand` 值。
- 不做播报开关持久化（`UserDefaults` 键名归 App 侧）；本域只保存内存布尔开关。
- 不做历史列表/详情、GPX 导出与系统分享的调用（`RunGPXExporter` 不动，只保证归档采样即导出可用数据）。
- 不重写阶段 2/3 契约：状态迁移表、度量阈值与当前配速窗口、播报去抖与每公里一次、checkpoint JSONL 字段、`RunRecord` 校验、归档命名与排序一律不改。
- 不新增 gate、不改 `scripts/**`/`.munk/code-gates.json`/`Package.swift`、不碰 `android/`/`shared/`/CI/`VERSION`/`AGENTS.md`。
- 不做夹具引用、真机/模拟器运行与签名；不写「真机已验证」类结论。

## Implementation Constraints

- 委托而非复制：状态合法性只看 `RunSessionMachine`，距离/时长/配速/分段只看 `RunMetricsEngine.ingest`，播报序号与去抖只看 `AnnouncementScheduler.tick`；编排器内不得出现新的距离/配速/分段/去抖公式或迁移表。
- `ready`/`finished` 下 `ingest` 必须不转调 `RunMetricsEngine.ingest`（该引擎未开始时会置内部已启动标记），只返回当前快照。
- 归档采样唯一新增判定只做单调性守卫：状态 `running` 且 `timestamp` 严格大于上一条已记录采样（首条无条件接受）才追加；暂停期不记录。
- 先完成内存迁移再落盘；落盘失败原样抛错，不静默吞错、不做内存回滚。
- Swift 6 严格并发：只用 `struct`/`enum` + 显式 `Sendable`，不引入 `actor`/`class`/全局可变状态/`@unchecked`；不做自有文件 IO，全部经既有两个 store。
- 门禁红线（`check-ios-run-core.sh` 真实扫描）：`Sources` 只 `import Foundation`；不得出现 `CoreLocation|AVFoundation|AVAudioSession|SwiftUI|UIKit|URLSession|CoreData|SQLite|SwiftData|Timer` 字样（含注释与命名）；不得出现夹具令牌与根 `VERSION` 字面值。
- 测试纪律：XCTest（禁 `import Testing`）；临时目录用 `FileManager.default.temporaryDirectory` + `UUID()` 子目录并 `defer` 清理；时间统一 `Date(timeIntervalSince1970: n)` 合成，坐标固定步长生成，不读夹具、不用 `Date()` 现时；真实落盘断言必须用新建 store 实例从磁盘读回，不用内存桩。
- 证据口径：只报 `swift build`/`swift test` 真实输出与用例数、`check-ios-run-core.sh` PASS 计数；不写「已验证」「真机通过」。

## Latest Delivery Proof

- workItemId: wi_ws_059a3ab432533de2（2026-11-08，pass，面向 UI 的会话编排器；只取代码层证据）
- 交付：新增 `RunSessionOrchestrator`（值类型 + `Sendable`，持有并委托既有状态机/度量引擎/播报调度器/checkpoint store/归档 store），提供 `start/pause/resume/ingest/finish` 与 `RunSessionUpdate`；`ready`/`finished` 下 `ingest` 不转调引擎；运行期维护严格递增归档采样序列；每次成功迁移与被接受采样写真实 checkpoint，`finish` 归档一次并 `reset` checkpoint，重复 `finish` 返回 `nil`；播报开关关闭时吞命令、重开不补播。既有源文件与既有测试未改。
- 验证：`code_gates` 22 门全绿——`lint-ios-run-core` PASS、`build-ios-run-core` PASS、`test-ios-run-core` 123 例 0 失败（既有 110 + 新增 13：`RunSessionOrchestratorTests`）；未改 `scripts/**`、`.munk/code-gates.json`、`Package.swift`、`project.yml`、`shared/`、`android/`、CI、`VERSION`。App 侧接入（首屏跑步页、开关持久化、跨进程恢复编排）仍 `pending`（归后续 Wave 2 子项）。
