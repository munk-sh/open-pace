import Foundation

/// 一次编排动作或采样摄入后的快照。
public struct RunSessionUpdate: Equatable, Sendable {
    /// 动作完成后的会话状态。
    public let state: RunSessionState
    /// 动作完成后的度量快照。
    public let metrics: RunMetrics
    /// 本次对外暴露的播报命令（播报关闭时恒为空）。
    public let announcements: [AnnouncementCommand]

    public init(
        state: RunSessionState,
        metrics: RunMetrics,
        announcements: [AnnouncementCommand]
    ) {
        self.state = state
        self.metrics = metrics
        self.announcements = announcements
    }
}

/// 面向 UI 的跑步会话编排器。
///
/// 只负责把既有的 `RunSessionMachine`、`RunMetricsEngine`、`AnnouncementScheduler`
/// 与 `RunCheckpointStore` / `RunArchiveStore` 按固定顺序串起来，本身不持有
/// 状态迁移表、距离/配速/分段公式或播报去抖逻辑。所有时间由调用方以 `Date` 注入。
public struct RunSessionOrchestrator: Sendable {
    /// 当前会话状态，与内部状态机保持一致。
    public private(set) var state: RunSessionState

    /// 是否对外暴露播报命令；默认开启。关闭时调度器仍前进但命令被吞掉，重新开启不补播。
    public var announcementsEnabled: Bool

    private var machine: RunSessionMachine
    private var engine: RunMetricsEngine
    private var scheduler: AnnouncementScheduler
    private let checkpointStore: RunCheckpointStore
    private let archiveStore: RunArchiveStore
    private var archivedSamples: [RunSample]
    private var startedAt: Date?
    private var lastArchivedSampleTimestamp: Date?
    /// 结束快照：`prepareFinish` 生成并持有，保存成功前不落盘。
    private var pendingRecord: RunRecord?
    /// 已成功归档的结束快照：重复保存直接复用它，保证恰写一次。
    private var archivedRecord: RunRecord?

    public init(
        checkpointStore: RunCheckpointStore,
        archiveStore: RunArchiveStore,
        announcementsEnabled: Bool = true
    ) {
        self.state = .ready
        self.announcementsEnabled = announcementsEnabled
        self.machine = RunSessionMachine()
        self.engine = RunMetricsEngine()
        self.scheduler = AnnouncementScheduler()
        self.checkpointStore = checkpointStore
        self.archiveStore = archiveStore
        self.archivedSamples = []
        self.startedAt = nil
        self.lastArchivedSampleTimestamp = nil
        self.pendingRecord = nil
        self.archivedRecord = nil
    }

    /// 由 checkpoint 恢复：状态机/度量引擎按既有 additive 恢复语义重建，不追加、不改写文件。
    ///
    /// 状态由 `RunSessionMachine(restoring:)` 决定（`running`/`paused` 一律恢复为 `paused`，
    /// 必须显式 `resume(at:)`）；已播报公里序号从 checkpoint 还原，避免恢复后重复播报。
    /// `lastArchivedSampleTimestamp` 必须回填锚点时间，否则新进程里早于锚点的样本仍会被
    /// 归档序列接受并污染 checkpoint。`startedAt` 按「锚点时间 − 活跃时长」派生（下界）。
    public init(
        restoring checkpoint: RunCheckpoint,
        checkpointStore: RunCheckpointStore,
        archiveStore: RunArchiveStore,
        announcementsEnabled: Bool = true
    ) {
        let machine = RunSessionMachine(restoring: checkpoint)
        self.state = machine.state
        self.announcementsEnabled = announcementsEnabled
        self.machine = machine
        self.engine = RunMetricsEngine(restoring: checkpoint)
        self.scheduler = AnnouncementScheduler(announcedSplitIndex: checkpoint.announcedSplitIndex ?? 0)
        self.checkpointStore = checkpointStore
        self.archiveStore = archiveStore
        self.archivedSamples = []
        self.startedAt = checkpoint.lastSample.map {
            $0.timestamp.addingTimeInterval(-checkpoint.elapsed)
        }
        self.lastArchivedSampleTimestamp = checkpoint.lastSample?.timestamp
        self.pendingRecord = nil
        self.archivedRecord = nil
    }

    /// 结束快照（待决策）；未结束或已丢弃时为 `nil`。
    public var finishedSnapshot: RunRecord? {
        pendingRecord
    }

    /// 已成功归档的结束快照；重复保存返回同一记录。
    public var savedRecord: RunRecord? {
        archivedRecord
    }

    /// 是否处于「已结束 + 待决策」：已有快照但尚未归档。
    public var isAwaitingDecision: Bool {
        state == .finished && pendingRecord != nil && archivedRecord == nil
    }

    /// 当前度量快照（距离/时长/配速/分段全部来自 `RunMetricsEngine`）。
    public var metrics: RunMetrics {
        engine.metrics
    }

    /// 运行态下被单调守卫整条丢弃的等时/倒退采样条数（只读转发）。
    public var duplicateSampleCount: Int {
        engine.duplicateSampleCount
    }

    /// 运行期已接受的采样序列，按时间严格递增；结束归档与 GPX 导出共用这一批数据。
    public var acceptedSamples: [RunSample] {
        archivedSamples
    }

    // MARK: - 会话动作

    /// 开始跑步；仅 `ready` 合法，非法迁移由状态机抛出 `invalidStateTransition`。
    @discardableResult
    public mutating func start(at date: Date) throws -> RunSessionUpdate {
        try machine.start()
        engine.start(at: date)
        startedAt = date
        state = machine.state
        let commands = scheduler.tick(
            RunMetricsUpdate(metrics: engine.metrics, newlyCompletedSplits: []),
            state: .running
        )
        try appendCheckpoint(recordedAt: date)
        return snapshot(announcements: exposed(commands))
    }

    /// 暂停；仅 `running` 合法。
    @discardableResult
    public mutating func pause(at date: Date) throws -> RunSessionUpdate {
        try machine.pause()
        engine.pause(at: date)
        state = machine.state
        let commands = scheduler.tick(
            RunMetricsUpdate(metrics: engine.metrics, newlyCompletedSplits: []),
            state: .paused
        )
        try appendCheckpoint(recordedAt: date)
        return snapshot(announcements: exposed(commands))
    }

    /// 恢复；仅 `paused` 合法。
    @discardableResult
    public mutating func resume(at date: Date) throws -> RunSessionUpdate {
        try machine.resume()
        engine.resume(at: date)
        state = machine.state
        let commands = scheduler.tick(
            RunMetricsUpdate(metrics: engine.metrics, newlyCompletedSplits: []),
            state: .running
        )
        try appendCheckpoint(recordedAt: date)
        return snapshot(announcements: exposed(commands))
    }

    /// 结束会话并归档一次（既有语义，幂等）：无待决策快照时自动补一次 `prepareFinish`。
    ///
    /// 已结束（无论已保存还是待决策）一律返回 `nil`，不重复生成快照、不重复归档。
    @discardableResult
    public mutating func finish(at date: Date) throws -> RunRecord? {
        guard state != .finished else { return nil }
        _ = try prepareFinish(at: date)
        return try saveFinished()
    }

    /// 结束会话并生成结束快照，**不落盘**：迁移到 `finished`、停表、清 checkpoint。
    ///
    /// 已结束时直接返回既有快照（已保存优先），保证重复「结束」不重复生成。
    @discardableResult
    public mutating func prepareFinish(at date: Date) throws -> RunRecord? {
        if state == .finished {
            return archivedRecord ?? pendingRecord
        }
        try machine.finish()
        engine.finish(at: date)
        state = machine.state
        let metrics = engine.metrics
        _ = scheduler.tick(
            RunMetricsUpdate(metrics: metrics, newlyCompletedSplits: []),
            state: .finished
        )
        guard let startDate = startedAt else {
            throw RunArchiveError.invalidRecord("缺少会话开始时间")
        }
        guard let record = RunRecord(
            startedAt: startDate,
            endedAt: date,
            distance: metrics.distance,
            activeDuration: metrics.elapsed,
            splits: metrics.splits,
            samples: archivedSamples
        ) else {
            throw RunArchiveError.invalidRecord("编排器组装的跑次记录不满足契约")
        }
        try checkpointStore.reset()
        pendingRecord = record
        return record
    }

    /// 保存待决策的结束快照：归档恰一次，重复保存返回同一记录且不新增/不重写文件。
    ///
    /// 失败时不改动快照，调用方可原地重试；不会留下半条文件（由 `RunArchiveStore` 保证）。
    @discardableResult
    public mutating func saveFinished() throws -> RunRecord {
        if let archivedRecord {
            return archivedRecord
        }
        guard let record = pendingRecord else {
            throw RunCoreError.invalidStateTransition(from: state, to: .finished)
        }
        try archiveStore.save(record)
        archivedRecord = record
        return record
    }

    /// 丢弃待决策的结束快照并重建为全新 `ready`；归档文件不动，内存草稿全部清空。
    public mutating func discard() throws {
        guard state == .finished else {
            throw RunCoreError.invalidStateTransition(from: state, to: .ready)
        }
        machine = RunSessionMachine()
        engine = RunMetricsEngine()
        scheduler = AnnouncementScheduler()
        archivedSamples = []
        startedAt = nil
        lastArchivedSampleTimestamp = nil
        pendingRecord = nil
        archivedRecord = nil
        state = .ready
    }

    // MARK: - 采样摄入

    /// 摄入一个采样点。
    ///
    /// 仅 `running` 状态转调 `RunMetricsEngine.ingest`；`ready`/`paused`/`finished`
    /// 下只返回当前快照，绝不能把未开始/已结束的会话偷偷启动或推进。
    @discardableResult
    public mutating func ingest(_ sample: RunSample) throws -> RunSessionUpdate {
        guard state == .running else {
            return snapshot(announcements: [])
        }
        let update = engine.ingest(sample)
        let accepted = isArchiveAcceptable(sample)
        if accepted {
            archivedSamples.append(sample)
            lastArchivedSampleTimestamp = sample.timestamp
        }
        let commands = scheduler.tick(update, state: .running)
        if accepted {
            try appendCheckpoint(recordedAt: sample.timestamp)
        }
        return snapshot(announcements: exposed(commands))
    }

    // MARK: - 播报开关

    /// 设置是否对外暴露播报命令；关闭即时生效且被抑制的公里不会在重新开启时补播。
    public mutating func setAnnouncementsEnabled(_ enabled: Bool) {
        announcementsEnabled = enabled
    }

    // MARK: - 内部

    /// 唯一新增判定：运行期归档序列只做单调性守卫（首条无条件接受）。
    private func isArchiveAcceptable(_ sample: RunSample) -> Bool {
        guard let last = lastArchivedSampleTimestamp else { return true }
        return sample.timestamp > last
    }

    private func exposed(_ commands: [AnnouncementCommand]) -> [AnnouncementCommand] {
        announcementsEnabled ? commands : []
    }

    private func snapshot(announcements: [AnnouncementCommand]) -> RunSessionUpdate {
        RunSessionUpdate(state: state, metrics: engine.metrics, announcements: announcements)
    }

    private func appendCheckpoint(recordedAt: Date) throws {
        guard let checkpoint = RunCheckpoint(
            state: state,
            completedDistance: engine.metrics.distance,
            elapsed: engine.metrics.elapsed,
            splits: engine.metrics.splits,
            recordedAt: recordedAt,
            lastSample: engine.lastAcceptedSample,
            announcedSplitIndex: scheduler.announcedSplitIndex
        ) else {
            throw RunCoreError.corruptedCheckpoint("编排器组装的 checkpoint 不满足契约")
        }
        try checkpointStore.append(checkpoint)
    }
}
