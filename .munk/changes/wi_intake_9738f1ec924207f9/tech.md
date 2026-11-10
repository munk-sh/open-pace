# tech.md — 阶段 2 断言补齐 A：后台定位策略 + 锁屏/重启状态恢复

无 `ux/**`（本项零 UI）。本文件只描述**增量**：3 处 App 层小改 + 2 处 RunCore 增量 API + 测试与矩阵表；不改状态迁移表、度量公式、checkpoint 字段/版本、归档契约、identifier、`ios/project.yml`、`Info.plist`、`.munk/code-gates.json`。

## 1. 结论（可直接开工的最小改动面）

| # | 文件 | 改动性质 | 目的 |
|---|---|---|---|
| 1 | `ios/PurePace/Location/RunLocationSource.swift` | 1 行生产改动 | `endUpdating()` 补 `pausesLocationUpdatesAutomatically = false`（ac-loc-bg-flags-running / counterexample 要求 stop 后两者都复位） |
| 2 | `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift` | 增量只读计数 | `public private(set) var duplicateSampleCount`，仅在「时间倒退/等时样本整条丢弃」分支 +1 |
| 3 | `ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift` | 增量初始化器 + 只读暴露 | `init(restoring:checkpointStore:archiveStore:announcementsEnabled:)`；`duplicateSampleCount` 转发；恢复时以 `lastSample` 重建归档单调守卫并派生 `startedAt` |
| 4 | `ios/PurePace/Run/RunSessionViewModel.swift` | 增量可观测 + 注入点 | 注入 `NotificationCenter` + `restoringCheckpoint`；生产注册两条 protected-data 通知→`isProtectedDataLocked`/`protectedDataUnavailableSince`；发布 `duplicateSampleCount`；新增 `makeRestored(...) throws` 应用级恢复入口 |
| 5 | 3 个新 RunCore 测试文件 + 2 个新 App 测试文件 + 扩展 `RunLocationSourceTests.swift` | 测试资产 | 正例 + 独立反例同 commit |
| 6 | `docs/verification-matrix.md` | 新建纯表格 | 10 条接缝单一真源，本项 4 行实测、另 6 行 `pending: 待对应 item 回填` |

**不做**：不把恢复入口接进 `ContentView`/启动流程（那会改变产品行为与归档语义）；不改 UI/文案/identifier/GPX/音频；不新增真机或 XCUITest 用例；不新增 gate。

## 2. 结构 / 导航 / 数据流

### 2.1 锁屏（B）数据流（全部经现有唯一摄入路径）

```
NotificationCenter(注入) --willBecomeUnavailable--> RunProtectedDataObservation(新 shim) --> ViewModel.applyProtectedDataLock(true)
ViewModel.ingest / delegate(didProduce:) --> RunSessionOrchestrator.ingest --> RunMetricsEngine.ingest
                                                                    └─ 等时/倒退样本 → duplicateSampleCount += 1，度量不变
```

- 通知 handler **只写** `isProtectedDataLocked` / `protectedDataUnavailableSince`（用注入 `now()`），**不**调用 `pause`/`resume`/`finish`、不停定位、不补样本、不写 checkpoint。度量继续完全由样本时间戳驱动，因此「解锁不重算计时」是结构性成立而非靠断言兜底。
- `RunProtectedDataObservation` 是新增的极小 shim（通知名→`Bool` 映射，`deinit` 移除 token），避免 `@MainActor` 类的 deinit 触碰非 Sendable token；回调在主线程同步执行：
  ```swift
  onChange: { [weak self] isLocked in
      if Thread.isMainThread {
          MainActor.assumeIsolated { self?.applyProtectedDataLock(isLocked) }   // 测试/UIKit 主线程：同步、确定
      } else {
          Task { @MainActor in self?.applyProtectedDataLock(isLocked) }         // 防御：非主线程投递不崩
      }
  }
  ```
  （XCUITest/单测里 `center.post` 在主线程，走同步分支，断言即时确定，不依赖 run loop 泵。）

### 2.2 重启恢复（C）数据流

```
RunCheckpointStore.loadLatest()  ── 尾行坏→静默丢；中间行坏→throw corruptedCheckpoint
        └─ RunSessionOrchestrator(restoring:)  ── machine(restoring:)=paused；engine(restoring:) 重建距离/时长/分段/锚点
                └─ RunSessionViewModel.makeRestored(...) throws  ── state/metrics 直接来自恢复态编排器
                        └─ resume(at: tR) → engine.resume 置 needsPositionAnchor → 下一样本仅重建位置锚点、只累加 Δ 时间
```

- 恢复后 `state == .paused`（沿用既有 machine/engine 语义），必须显式 `resume(at:)`。
- **必须**把 `lastArchivedSampleTimestamp = checkpoint.lastSample?.timestamp`：否则新进程第一条早于锚点的样本会被 `isArchiveAcceptable` 无条件接受并写进 `archivedSamples`+checkpoint（引擎虽拒收，但归档序列会被污染）。这是本项唯一容易漏的正确性点。

### 2.3 `startedAt` 取舍（PRD 显式交给 Architect）

`RunCheckpoint` 不含 `startedAt`，且不允许改格式。恢复态 `finish()` 仍要求 `startedAt`，否则会抛既有 `RunArchiveError.invalidRecord`（属于「新增用户可见错误」，禁止）。

**决定**：恢复时按 `checkpoint.lastSample.timestamp - checkpoint.elapsed` 派生 `startedAt`；无锚点（旧格式）时保持 `nil`（沿用既有报错路径，不新增语义）。
- 断言：`testRestoredFinishUsesDerivedStartedAt` 固定 `record.startedAt == anchor - elapsed`。
- 已知偏差：若有暂停空档，派生值晚于真实开始时间（按活跃时长反推的下界）；仅在「恢复后结束会话」时影响 `startedAt`，不影响距离/时长/分段。由于本项不把恢复接入启动流程，生产不产生该路径。
- 已知偏差 2：恢复后 `archivedSamples` 只有重启后样本（checkpoint 不存全量样本）。断言 `record.samples.count == 重启后被接受样本数`，并在 digest/矩阵中标注，不改归档契约。

## 3. 新增/变更公开契约（additive，零破坏）

```swift
// RunMetricsEngine
public private(set) var duplicateSampleCount: Int   // 仅「等时/倒退被丢弃」+1；paused 下 drop 不计

// RunSessionOrchestrator
public init(restoring checkpoint: RunCheckpoint,
            checkpointStore: RunCheckpointStore,
            archiveStore: RunArchiveStore,
            announcementsEnabled: Bool = true)      // state 由 machine(restoring:) 决定；scheduler(announcedSplitIndex:)
public var duplicateSampleCount: Int                // 转发 engine

// RunSessionViewModel
init(..., now: @escaping () -> Date = { Date() },
     restoringCheckpoint: RunCheckpoint? = nil,
     notificationCenter: NotificationCenter = .default)
@Published private(set) var duplicateSampleCount: Int
@Published private(set) var isProtectedDataLocked: Bool
@Published private(set) var protectedDataUnavailableSince: Date?
@Published private(set) var didRestoreFromCheckpoint: Bool
static func makeRestored(checkpointStore:archiveStore:locationSource:announcements:notificationCenter:now:) throws -> RunSessionViewModel
```

## 4. Code Anchors Table for Coding（行号基于当前工作树，动手前用 read(offset,limit) 抽样复核即可）

| Target File Path | Edit/Insert Line Range (Lxxx-Lyyy) | Target Function/Symbol Signature & Reusable Helpers | Single-Slice Edit Key Points |
|---|---|---|---|
| `ios/PurePace/Location/RunLocationSource.swift` | 改 L196-L200（插 L198） | `private func endUpdating()` | 在 `manager.allowsBackgroundLocationUpdates = false` 后补 `manager.pausesLocationUpdatesAutomatically = false`。只加这一行，不改 `beginUpdating()`(L188-194)、不改 `apply(_:)`(L174-186)；`stop()`(L170-172) 直通。 |
| 同上（只读锚点） | L128-L135 / L137-L150 / L152-L168 | `init(manager:)` / `retainedManager`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically` / `start()` | 反例：`init` 后手工把 `allows`+`pauses` 置脏再 `stop()`，两值必须 false；`retainedManager` 是弱引用断言的唯一入口。 |
| `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift` | 插 L37（字段块 L24-L36 之后） | `public private(set) var duplicateSampleCount: Int = 0` | 带注释「仅在非递增样本被整条丢弃时 +1；暂停/未开始的 drop 不计」。加默认值不影响 `public init()` / `init(restoring:)`。 |
| `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift` | 改 L135-L138（现有 `if hasAnySample, let lastTimestamp, sample.timestamp <= lastTimestamp` 分支内，插 L137） | `public mutating func ingest(_ sample: RunSample) -> RunMetricsUpdate` | 在 `return update(newlyCompletedSplits: [])` 之前 `duplicateSampleCount += 1`。不得改动 drop 语义、公式、`RunMetrics`。**注释禁止出现 `CoreLocation|UIKit|SwiftUI|Timer|URLSession` 等词**（`check-ios-run-core.sh:191-204` 全文扫描 Sources）。 |
| `ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift` | 插 L60（现有 `init` L44-L59 之后） | `public init(restoring checkpoint: RunCheckpoint, checkpointStore: RunCheckpointStore, archiveStore: RunArchiveStore, announcementsEnabled: Bool = true)` | 逐字段：`state = RunSessionMachine(restoring:).state`；`machine`/`engine` 用 restoring 版；`scheduler = AnnouncementScheduler(announcedSplitIndex: checkpoint.announcedSplitIndex ?? 0)`；`archivedSamples = []`；`lastArchivedSampleTimestamp = checkpoint.lastSample?.timestamp`（关键）；`startedAt = checkpoint.lastSample.map { $0.timestamp.addingTimeInterval(-checkpoint.elapsed) }`。不 append checkpoint、不改文件。 |
| 同上 | 插 L65（`metrics` L61-L64 之后） | `public var duplicateSampleCount: Int { engine.duplicateSampleCount }` | 只读转发，不参与 `RunSessionUpdate`（避免改 Equatable/Sendable 契约面）。 |
| `ios/PurePace/Run/RunSessionViewModel.swift` | 插 L19（`@Published` 块 L11-L18 之后） | 四个 `@Published private(set) var`：`duplicateSampleCount: Int = 0`、`isProtectedDataLocked: Bool = false`、`protectedDataUnavailableSince: Date?`、`didRestoreFromCheckpoint: Bool` | 顺序/类型与测试断言一一对应；不新增用户可见文案。 |
| 同上 | 插 L32（stored props L20-L36 内） | `private let lockObservation: RunProtectedDataObservation` | 必须是非可选 `let`（init 末尾最后一个赋值），保证 token 生命周期跟随 ViewModel。 |
| 同上 | 改 L38-L76（签名末追加 L52 之后；orchestrator 构造 L53-L57；seed L59-L61；注册 L75 之后） | `init(..., now:restoringCheckpoint:notificationCenter:)` | 参数追加在 `now` 之后（全部带默认值，现有 4 处调用零改动）。`let orchestrator = restoringCheckpoint.map { RunSessionOrchestrator(restoring: $0, checkpointStore:…, archiveStore:…, announcementsEnabled:…) } ?? RunSessionOrchestrator(…)`；`didRestoreFromCheckpoint = restoringCheckpoint != nil`；`state/metrics` 仍取 orchestrator；全部 stored props 赋值完成后再建 `lockObservation`（`[weak self]` + 双路径 `MainActor.assumeIsolated`/`Task{@MainActor}`）；恢复态额外 `updateLifecycleSnapshot()`。 |
| 同上 | 插 L77（init 之后、`// MARK: - 生命周期` 之前） | `static func makeRestored(checkpointStore:archiveStore:locationSource:announcements:notificationCenter:now:) throws -> RunSessionViewModel` | 首行 `let checkpoint = try checkpointStore.loadLatest()`（尾行坏静默丢、中间坏抛 `corruptedCheckpoint`，原样上抛，**禁止 `try?`**）；再调指定 init 传 `restoringCheckpoint`。这是 ac-restart-middle-corruption 的唯一应用级入口。 |
| 同上 | 改 L94-L105（`start()` 内 L96 附近） | `func start()` | `runSampleCount = 0` 旁加 `duplicateSampleCount = 0`（新跑次计数归零）。 |
| 同上 | 改 L144-L150 | `func ingest(_ sample: RunSample)` | `apply(try orchestrator.ingest(sample))` 之后 `duplicateSampleCount = orchestrator.duplicateSampleCount`；catch 分支不动。 |
| 同上 | 插 L196（`apply(state:metrics:)` L191-L195 之后） | `private func applyProtectedDataLock(_ isLocked: Bool)` | `isProtectedDataLocked = isLocked`；`protectedDataUnavailableSince = isLocked ? now() : nil`。**绝对不调用** orchestrator 的任何动作。 |
| 同上 | 追加 L279+（文件尾 `extension RunSessionViewModel: RunLocationSourceDelegate` L267-L278 之后） | `final class RunProtectedDataObservation: @unchecked Sendable`（`init(center:onChange:)` + `deinit` 移除 token） | 只映射 `UIApplication.protectedDataWillBecomeUnavailableNotification`→`true`、`UIApplication.protectedDataDidBecomeAvailableNotification`→`false`；`queue: nil`（同步投递）；无 Timer/无 DispatchQueue.asyncAfter（`check-ios-shell.sh:1152` 扫 `ios/PurePace/Run`）。文件名沿用 `RunSessionViewModel.swift`，不新增 App 源文件。 |
| `ios/PurePaceTests/RunLocationSourceTests.swift`（扩展，勿重写） | 插 L203（`testDeniedAndRestricted…` L182-L202 之后、`// MARK: - ac-bg-ingest-continuous` L204 之前） | 新增 4 个 `func test…`；复用 `StubLocationManager`(L11-L44)、`Recorder`(L46-L60)、`sample(latitude:timestamp:)`(L264-L273) | ①`testStopResetsDirtyBackgroundFlagsIncludingAutoPause`（预置 allows=true/pauses=true→`stop()`→双 false）；②`testManagerAndDelegateWeakReferencesDieWithSource`（`weak var` 取 `underlyingManager` 与 `delegate`，作用域退出后 `XCTAssertNil`，并断 `source.retainedManager === manager`、`isDelegateAttached`）；③`testAlwaysUpgradeClearsDegradedHint`（已有 L155-L180 覆盖，这里只补 `XCTAssertNotEqual` 交叉护栏）；④`testWhenInUseDegradedCounterexample`（同判定器对 `authorizedWhenInUse` 与 `authorizedAlways` 的 capable/hint 交叉不等）。 |
| `ios/RunCore/Tests/PurePaceRunCoreTests/OrchestratorRestoreTests.swift` | 新文件 L1-L230 | `final class OrchestratorRestoreTests: XCTestCase`；夹具复用 `RunCheckpointStore(fileURL:)` + 既有 `makeResumeStream` 风格自建 1 Hz 流 | L1 覆盖：restore 后 metrics/state；`resume` 后 elapsed = 恢复值+Δ、distance 继续；`<=` 锚点样本被拒；`announcedSplitIndex` 恢复不重复播报；坏尾回退上一行；中间行损坏 throws；`startedAt` 派生 + `finish()` 成功且 `samples.count` 只含恢复后样本。**禁止字面量 `0.1.0`/`shared/fixtures`**（`check_no_version_literal`/`check_no_fixture_tokens` 扫整个包目录）。 |
| `ios/RunCore/Tests/PurePaceRunCoreTests/RunSampleDedupTests.swift` | 新文件 L1-L120 | `final class RunSampleDedupTests: XCTestCase` | L1 覆盖：等时/倒退样本 +1 且 `metrics` 逐项不变；严格递增流计数恒 0（反例护栏）；paused 下 drop 不计数；经 orchestrator 暴露同值。 |
| `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift` | 新文件 L1-L140 | `final class DocsVerificationMatrixTests: XCTestCase` | 从 `#filePath` 上溯到含 `VERSION` 的祖先作仓库根，读 `docs/verification-matrix.md`：表头逐字等于 `\| 接缝 \| 现状 \| 断言名 \| 反例 \| 证据路径 \| 归属项 \|`；恰 10 行接缝；无正文段落（除空行外每行 `\|` 开头且 6 列）；本项 4 行不含 `pending`；其余 6 行含 `pending: 待对应 item 回填`。 |
| `ios/PurePaceTests/RunSessionLockTests.swift` | 新文件 L1-L260 | `@MainActor final class RunSessionLockTests: XCTestCase`；自建 `FakeLocationSource`（照抄 `RunSessionViewModelTests.swift:8-25` 形态）、`Clock`(L372-377 形态)、`makeStores`(L387-395 形态) | 顶部先落阈值常量：`static let fixtureSampleInterval: TimeInterval = 1.0`、`static let maximumSampleGapSeconds: TimeInterval = 2.0`（注释：「fixture 固定 1.0 s 采样 × 2 倍系统调度抖动容差；先定后测，不构成真机采样频率承诺」，digest 记录 commit/时间）。注入 `NotificationCenter()` 构造 VM；用 `source.delegate?.locationSource(source,didProduce:)` 走生产摄入路径；采样单调/空洞证据用 `try stores.checkpoint.loadAll().compactMap(\.lastSample?.timestamp)`；解锁不增行用文件 `\n` 计数。 |
| `ios/PurePaceTests/RunSessionRestoreTests.swift` | 新文件 L1-L300 | `@MainActor final class RunSessionRestoreTests: XCTestCase`；复用 temp `RunCheckpointStore`/`RunArchiveStore`、`RunSessionViewModel.makeRestored` | 用真实 VM 跑到 ≥2 个完整分段（约 70 个 30 m/1 s 样本）→ 丢弃全部内存实例 → 同一文件全新 store + `makeRestored`（全新 orchestrator/VM）→ 断言 paused/距离/时长/分段/锚点；坏尾与中间损坏直接往文件写坏行；`resume(at:)` 用注入 Clock；`finish` 派生 startedAt 断言。 |
| `docs/verification-matrix.md` | 新文件 L1-L13 | 纯 Markdown 表格，无正文 | 表头 1 行 + 分隔行 + 10 行。本项实测 4 行：后台定位会话与更新策略、锁屏 protectedData 锚点、进程重启恢复、Info.plist 能力（证据 `ios/PurePaceTests/BackgroundModesPlistTests.swift:28-76` + `RunLocationSourceTests.swift`）；其余 6 行 pending：TTS 每公里调度与中断恢复、duck 撤销/去激活/categoryOptions、GPX 导出、竖屏+iPhone-only 静态、Dynamic Type、设计 token / hero 间距（`现状` 填已知结论，`证据路径` 填现存脚本/测试文件，`断言名`/`反例` 填 `pending: 待对应 item 回填`）。 |

## 5. 测试金字塔落位（哪些 ac 下推到哪一层）

| ac / 接缝 | 层 | 落点 | 可确定验证手段 |
|---|---|---|---|
| ac-loc-bg-flags-running / counterexample | L2（进程内、注入 `RunLocationManaging` 桩，`scripts/test-ios.sh --unit-only`） | `RunLocationSourceTests` | 桩直接读 manager 属性，无系统弹窗/无模拟器定位依赖 |
| ac-loc-manager-delegate-retained | L2 | 同上（`RunLocationSource()` 真包装 + 弱引用） | 弱引用置 nil 即证强引用链；不停保证「只在断言时临时取到」 |
| ac-plist-built-app-readback | L2（已存在，不改） | `BackgroundModesPlistTests:28-76` | `Data`+`PropertyListSerialization` 读构建产物本体；负向自检用临时 plist 夹具走同一路径 |
| ac-auth-always-upgrade / ac-auth-wheninuse-degraded | L2 | `RunLocationSourceTests`（补交叉护栏） | 纯值属性 + 桩请求计数，零真实授权 |
| ac-lock-running-continues / sample-cadence / dedup / unlock-no-replay / handler-observable | L2（注入 `NotificationCenter` + 注入 `now` + fake 采样源） | `RunSessionLockTests` | 同步 `post` + 注入时钟；阈值先定；证据读 checkpoint 行 |
| 去重计数引擎语义 | L1（`swift test --package-path ios/RunCore`） | `RunSampleDedupTests` | 纯值，无 IO |
| ac-restart-restores-metrics / last-sample / timer-continues / bad-tail / middle-corruption / announcedSplitIndex / startedAt | L1 | `OrchestratorRestoreTests` | 真实临时文件 JSONL，无 UI/无模拟器 |
| ac-restart-viewmodel-e2e / viewmodel 级恢复与坏行 | L2 | `RunSessionRestoreTests` | 应用级 VM + 新 store/orchestrator，fake 采样源继续供点 |
| ac-verification-matrix | L1 | `DocsVerificationMatrixTests` | 机械断言表格结构，随 `test-ios-run-core` gate 长期守护 |
| 真机后台锁屏连续定位 / 音频实听 | L3 | 不做（`pending: 待人现场`） | 本项不得出现「真机已验证」字样 |

**反例纪律（与正例同 commit，长期资产）**：每个接缝一个独立反例测试，采用仓库既有 `BackgroundModesPlistTests` 的「同一判定器 + 回归夹具必须被判红」写法：
- A：`testStopResetsDirtyBackgroundFlagsIncludingAutoPause`（脏值预置即回归夹具）、`testWhenInUseDegradedCounterexample`（capable/hint 交叉不等）。
- B：`testLockMustNotPauseCounterexample`（锁屏后 `XCTAssertNotEqual(state, .paused)` 且判定器把 `.paused` 判为违规）、`testDuplicateTimestampSampleIsDroppedAndCounted` + `testFullDuplicateSequenceIsDroppedAndCountMatches`（重复注入即回归夹具）、`testUnlockMustNotResetElapsedCounterexample`（elapsed 非 0 且增量恰为样本 Δ，非按 `tUnlock` 重算）、`testLockStateMissingCounterexample`（未锁时 false→锁后必 true）。
- C：`testMidCorruptionThrowsInsteadOfZeroMetricRestore`（抛错 + 负向自检「零度量会话不得被接受」）、`testRestoreRejectsSampleAtOrBeforeAnchorCounterexample`、`testRestoreMustNotResetTimerCounterexample`、`testBadTailFallsBackToPreviousValidRecord`。
- 取证补充：coding 可对 1-2 个关键反例做**一次性本地变异**（改一行→跑单测→`git checkout --` 还原）截取真实红灯输出写入 digest；最终 `git diff` 必须零残留。测试资产本身不依赖变异即可判红。

## 6. 冻结与门禁（零 diff 项）

- 33 项 identifier：不改任何 `*.swift` 的 `accessibilityIdentifier` / `identifier:`；`bash scripts/check-ios-shell.sh` 的清单段 `L468-L489` 不动。
- 22 个 gate：`.munk/code-gates.json` 一字不改；`ios/project.yml`、`ios/PurePace/Info.plist`（`check-ios-shell.sh:1479` 的 SHA 常量）不动。
- RunCore 边界：新增 `Sources` 代码只 `import Foundation`，注释不含平台词（`check_no_platform_symbols`）；包目录不出现 `0.1.0` 字面量（`check_no_version_literal` 扫源+测试）与夹具令牌。
- `ios/PurePace/Run` 无 `Timer|DispatchQueue.asyncAfter|CADisplayLink`（`check-ios-shell.sh:1152`）。
- 交付前命令：`bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-run-core.sh`、`swift test --package-path ios/RunCore`、`bash scripts/test-ios.sh --unit-only`；digest 用「接缝 → 断言名 → 文件:行 → 反例是否判红」，用例数与断言数分口径，xcodebuild `Executed` 与 XCTest 断言数不混写。

## 7. Testability by Design（绕过系统对话框的直接入口）

- 恢复链路全程走**文件路径注入**：`RunCheckpointStore(fileURL:)` 指向测试临时目录；`RunSessionViewModel.makeRestored(checkpointStore:…)` 直接吃 store 实例。没有 `UIDocumentPicker`/系统弹窗，单窗口后台自动化可全自动跑通；坏尾/中间损坏通过直接写文件字节构造。
- 锁屏链路走**注入 `NotificationCenter` + 注入 `now` + fake 采样源**：不依赖真实锁屏、不依赖 UIKit 投递时序，可在 CI 单测腿高频重复。
- 矩阵表由 `#filePath` 直接读仓库文件，不需要任何选择器。

## 8. 风险与缓解

1. **弱引用断言可能受 CoreLocation 内部持有影响**：`weakUnderlying` 释放后若非 nil，先判 `weakDelegate == nil`（证明包装对象已释放、delegate 弱引用链成立），并把 `underlyingManager` 断言拆成独立用例；两个断言同 commit，避免相互掩盖。
2. **非主线程投递 protected-data 通知**：双路径（主线程 `MainActor.assumeIsolated` / 其它 `Task{@MainActor}`）防崩；测试只走主线程同步分支，避免变成 async 竞态。
3. **`startedAt` 派生是下界**：有暂停空档时偏晚；只影响恢复后 `finish` 的归档时间，不影响度量。已在用例里显式断言并在矩阵/ digest 标注。
4. **恢复后归档只含重启后样本**：checkpoint 不存全量样本；不改契约、不接生产启动流程，digest 明确列为已知缺口。
5. **`duplicateSampleCount` 口径**：仅统计「running 下等时/倒退样本」；paused 下 drop 不计数。必须写进注释与 digest，防止被误读成「所有被丢样本计数」。
6. **既有 `testLifecycleNotificationsDoNotChangeSessionStateOrStartLocation`** 之后会顺带把 VM 锁状态置位；它只断言 state/startCount/metrics，仍绿；不要顺手改它。
7. **`NotificationCenter` 观察泄漏**：token 由 `RunProtectedDataObservation` 持有并在 `deinit` 移除，`@unchecked Sendable` 与仓库既有 `RunLifecycleTelemetryRecorder` 同构。
