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
    }

    /// 当前度量快照（距离/时长/配速/分段全部来自 `RunMetricsEngine`）。
    public var metrics: RunMetrics {
        engine.metrics
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

    /// 结束会话：归档一次并清空 checkpoint；已结束后返回 `nil` 且不重复归档。
    @discardableResult
    public mutating func finish(at date: Date) throws -> RunRecord? {
        guard state != .finished else { return nil }
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
        try archiveStore.save(record)
        try checkpointStore.reset()
        return record
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
