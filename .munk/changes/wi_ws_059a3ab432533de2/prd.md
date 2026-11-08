# 面向 UI 的跑步会话编排器（RunCore 纯逻辑）

## 范围

在既有 `ios/RunCore`（模块 `PurePaceRunCore`）内**纯增量**新增一个会话编排器，把阶段 2/3 已冻结的四个原语组装成可供 UI 直接驱动的单一入口，不复制它们的任何算法與规则：

1. **编排器**：新增 `RunSessionOrchestrator`（值类型 `struct` + 显式 `Sendable`），持有并委托既有 `RunSessionMachine`（状态迁移）、`RunMetricsEngine`（计时/距离/配速/分段）、`AnnouncementScheduler`（每公里播报命令）、`RunCheckpointStore`（JSONL 真实落盘），并在结束时用既有 `RunRecord` + `RunArchiveStore` 归档一次。
2. **会话动作**：`start(at:)` / `pause(at:)` / `resume(at:)` / `finish(at:)`——全部时间由调用方以 `Date` 注入（不使用任何时钟、定时器或 `Date()` 现时），状态合法性完全由 `RunSessionMachine` 判定。
3. **采样摄入**：`ingest(_:)` 只在 `running` 状态下把采样真正的度量语义交给 `RunMetricsEngine`；同时在运行期维护一条按时间严格递增的归档采样序列（含 `altitude`/`heartRate`/`cadence`），供结束归档与后续 GPX 导出共用同一批数据。
4. **播报开关**：`setAnnouncementsEnabled(_:)` 控制是否对外暴露 `AnnouncementCommand`；关闭时立即不再产出命令，且被抑制的公里不会在重新开启时补播。
5. **checkpoint 追加与结束归档**：每次成功的状态迁移与每个被接受的运行期采样都向 `RunCheckpointStore` 追加一条真实 checkpoint；`finish` 成功后写一条真实归档记录并清空 checkpoint，重复 `finish` 不产生第二条归档。

只新增源文件与测试文件；不改阶段 2/3 的既有源文件、既有测试、`Package.swift`、`scripts/**`、`.munk/code-gates.json`。

## Acceptance Criteria

- ac-start-ready-to-running: 在 `ready` 上 `start(at: t0)` → `state == .running`，`metrics.distance == 0`、`metrics.elapsed == 0`、`splits` 为空、`currentPace == nil`；checkpoint 文件真实存在且 `loadAll()` 恰好 1 条、`state == .running`、`completedDistance == 0`、`elapsed == 0`。
- ac-ingest-accumulates: `start` 后按固定步长喂入 3 个时间递增、坐标递增的采样 → `metrics.distance` 等于按 `GeoDistance` 公式逐段累加的期望值（浮点容差 1e-6）、`metrics.elapsed` 等于首末采样时间差、运行期归档采样序列恰为这 3 个采样（顺序与字段一致，含 `altitude`/`heartRate`/`cadence`）。
- ac-pause-zero-growth: 运行中 `pause(at: tP)` 后继续喂入坐标大幅跳变的采样（时间晚于 `tP`）→ `distance`、`elapsed`、`splits` 与暂停时刻快照完全相等，`currentPace == nil`，返回的 `announcements` 为空，且这些暂停期采样**不进入**归档采样序列（结束归档的 `samples` 不含它们）。
- ac-resume-continues: `resume(at: tR)` 后第一个采样只重建锚点（`distance` 不增加），其 `elapsed` 增量为 `sample.timestamp - tR`；其后的采样正常累加距离与时长，且跨整公里时会产出对应 `splitIndex` 的播报命令。
- ac-finish-archives-once: 首次 `finish(at: tF)` 返回非空 `RunRecord`，归档目录恰好 1 个 `.json` 文件且可被新 `RunArchiveStore` 实例 `list()` 读回；再次 `finish(at:)` 返回 `nil`、不抛错、归档目录文件数仍为 1、返回记录内容不变。
- ac-finish-record-matches-session: 归档记录 `startedAt` == `start` 时注入的日期、`endedAt` == `finish` 注入的日期、`distance`/`activeDuration`/`splits` 与 `finish` 时刻 `metrics` 逐个相等、`samples` 与运行期归档采样序列逐个相等（同一批数据可直接交给既有 `RunGPXExporter`，本项不调用它）。
- ac-finish-resets-checkpoint: `finish` 成功后 `RunCheckpointStore.loadAll()` 返回空数组（证明下一个会话不会被恢复成上一次的已结束会话），且归档文件仍然存在。
- ac-sample-monotonic-gate: 运行中喂入时间戳等于或早于上一条已接受采样的采样 → 不改变 `distance`/`elapsed`/`splits`，不进入归档采样序列，且不使归档记录的 `samples` 违反 `RunRecord` 的非递减约束；`start` 之前（`ready`）或 `finish` 之后（`finished`）喂入采样 → 状态、度量、checkpoint、归档文件一律不变。
- ac-announce-toggle-off: 默认开启；跨过第 1 公里时恰好产出 1 条 `splitIndex == 1` 的命令；关闭后跨过第 2 公里 → 命令为空；重新开启后下一次摄入 → 命令仍为空（被抑制的公里不补播）；再跨过第 3 公里 → 恰好产出 1 条 `splitIndex == 3` 的命令。
- ac-invalid-transitions: `ready` 上 `pause`/`resume`/`finish`、`running` 上重复 `start`、`finished` 上任意动作 → 抛出 `RunCoreError.invalidStateTransition`（`from`/`to` 与调用一致），状态保持原值，checkpoint 行数不增加，归档文件数不增加。
- ac-existing-contracts-intact: `git diff` 中 `ios/RunCore` 只出现新增文件；`RunSessionMachine`/`RunMetricsEngine`/`AnnouncementScheduler`/`RunCheckpoint*`/`RunRecord`/`RunArchiveStore`/`RunCoreError` 的既有 public 契约与语义不变；既有 110 例测试全部仍通过。
- ac-gates-green: `bash scripts/check-ios-run-core.sh`、`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore` 均退出 0；`swift test` 失败 0 例、执行数 ≥ 110 且新增用例覆盖上述全部 ac-*。

## 非目标

- **不做跨进程恢复编排**：不新增 restoring 初始化器。checkpoint 只存最后锚点、无法还原完整采样序列，此时恢复会让归档只含恢复后的采样（静默丢轨迹）；恢复链路需先解决采样补齐，留给后续子项。
- 不接 App target：不改 `ios/PurePace/project.yml`、不改 App 源码、不做 SwiftUI View/ViewModel、不做首屏跑步页。
- 不接平台框架：不出现 CoreLocation / AVFoundation / AVAudioSession / SwiftUI / UIKit / URLSession / Timer / 数据库；不做 TTS 实际播放、不配置 AudioSession（只产出既有 `AnnouncementCommand` 值）。
- 不做播报开关的持久化（`UserDefaults` 键名归 App 侧子项）；本项只接收并保存内存中的布尔开关。
- 不做历史列表/详情、不做 GPX 导出与系统分享的调用（`RunGPXExporter` 保持不动，本项只保证归档采样即导出可用的同一批数据）。
- 不重写/不调整阶段 2、3 的既有契约：状态迁移表、度量阈值与当前配速窗口、播报去抖与「每公里恰好一次」、checkpoint JSONL 字段与语义、`RunRecord` 校验规则、归档文件命名与排序一律不改。
- 不新增 gate、不改 `scripts/**` 与 `.munk/code-gates.json`、不改 `Package.swift`、不碰 `android/`、`shared/`、CI workflow、`VERSION`、`AGENTS.md` 与 Host 托管文件。
- 不做 fixture 引用、不做真机/模拟器运行与签名；不写「真机已验证」类结论。

## Implementation Constraints

- 落点（全部新增）：`ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift`；测试 `ios/RunCore/Tests/PurePaceRunCoreTests/RunSessionOrchestratorTests.swift`。既有文件一律不改。
- 对外锚点（命名可按实现微调，行为契约不得变）：`public struct RunSessionOrchestrator: Sendable`；`init(checkpointStore: RunCheckpointStore, archiveStore: RunArchiveStore, announcementsEnabled: Bool = true)`；`public private(set) var state: RunSessionState`；`public var metrics: RunMetrics`；`public var announcementsEnabled: Bool`；`start/pause/resume/ingest/finish` 均 `mutating` 且 `throws`，`finish` 返回 `RunRecord?`；动作与摄入返回一个小型值类型 `RunSessionUpdate { state, metrics, announcements }`。
- 委托而非复制：状态合法性只看 `RunSessionMachine`，距离/时长/配速/分段只看 `RunMetricsEngine.ingest`，播报序号与去抖只看 `AnnouncementScheduler.tick`；编排器内不得出现新的距离/配速/分段/去抖公式或状态迁移表。
- `ready` 与 `finished` 下调用 `ingest` 必须不转调 `RunMetricsEngine.ingest`（该引擎在未开始时会把内部标记置为已启动，直接转调会让「未开始」的会话被采样偷偷启动），只返回当前快照。
- 归档采样规则（唯一新增判定，且只做单调性守卫）：状态为 `running` 且 `timestamp` 严格大于上一条已记录采样（首条无条件接受）时追加到运行期序列；暂停期采样不记录。这样归档 `samples` 天然满足 `RunRecord` 的非递减约束，并与引擎「时间倒退/等时样本丢弃」的口径一致。
- checkpoint 追加时机与内容：每次成功迁移（start/pause/resume）后追加一条，且每个被接受的运行期采样后追加一条；内容由 `RunMetricsEngine.metrics` + `lastAcceptedSample` + `AnnouncementScheduler.announcedSplitIndex` 组装成 `RunCheckpoint`（`recordedAt` 用本次注入的 `Date`），不另造字段。先完成内存迁移再落盘；落盘失败把错误原样抛给调用方，不静默吞错、不做内存回滚。
- `finish` 顺序：机器迁移 → 引擎 `finish(at:)` → 调度器 `tick(state: .finished)` 取收尾命令 → 组装 `RunRecord`（`startedAt` 用本会话 `start` 注入的日期）→ `RunArchiveStore.save` → `RunCheckpointStore.reset()` → 返回记录。已 `finished` 时直接返回 `nil`，不重写归档、不清空二次。
- 播报开关：关闭时仍推进 `AnnouncementScheduler`（吞掉命令），只把对外命令置空，从而「关闭即时生效且不补播」；开关默认 `true`。
- Swift 6 严格并发：只用 `struct`/`enum` + 显式 `Sendable`，不引入 `actor`/`class`/全局可变状态/`@unchecked`；不做自己的文件 IO，全部经既有两个 store。
- 门禁红线（`scripts/check-ios-run-core.sh` 真实扫描）：`Sources` 只 `import Foundation`；不得出现 `CoreLocation|AVFoundation|AVAudioSession|SwiftUI|UIKit|URLSession|CoreData|SQLite|SwiftData|Timer` 字样（含注释与命名）；不得出现夹具令牌与根 `VERSION` 字面值。
- 测试纪律：XCTest（禁 `import Testing`）；临时目录用 `FileManager.default.temporaryDirectory` + `UUID()` 子目录并 `defer` 清理；时间统一 `Date(timeIntervalSince1970: n)` 合成、坐标用固定步长公式生成，不读夹具、不用 `Date()` 现时；「真实落盘」断言必须用新构造的 store 实例从磁盘读回，不用内存桩。
- 文档：`ios-runcore/product.md` 已达 28.9KB/171 行（上限 32KB/200 行），本项的编排契约写新子域 `ios-runcore-session`（或新开一节独立子域文档），最多在 `ios-runcore/product.md` 留一行指针，禁止回填细节。
- 证据口径：交付只报 `swift build`/`swift test` 真实输出与用例数、`check-ios-run-core.sh` 的 PASS 计数；不写「已验证」「真机通过」。
