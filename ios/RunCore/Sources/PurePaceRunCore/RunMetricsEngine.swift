import Foundation

/// 坐标/时间流驱动的计时、距离、配速与公里分段账本。
///
/// 对外唯一数据入口是 `ingest(_:)`；`start` / `pause` / `resume` / `finish`
/// 只调整时间锚点与记录状态，幂等且不做状态机合法性辩论。
/// 全部状态为值类型，无锁、无 actor、无全局可变状态。
public struct RunMetricsEngine: Sendable {
    /// 整公里分段长度（米）。
    public static let splitDistanceMeters: Double = 1000.0
    /// 当前配速滑动窗口（活跃秒数）。
    public static let currentPaceWindowSeconds: TimeInterval = 10.0
    /// 窗口内产生有效配速所需的最小路径距离（米）。
    public static let currentPaceMinimumDistanceMeters: Double = 5.0
    /// 窗口内产生有效配速所需的最小活跃时长（秒）。
    public static let currentPaceMinimumDurationSeconds: TimeInterval = 3.0

    private struct WindowEntry: Sendable {
        let elapsed: TimeInterval
        let latitude: Double
        let longitude: Double
    }

    private var isStarted = false
    private var isPaused = false
    private var isFinished = false
    private var hasAnySample = false
    private var needsPositionAnchor = false
    private var lastTimestamp: Date?
    private var lastLatitude: Double?
    private var lastLongitude: Double?
    private var activeElapsed: TimeInterval = 0
    private var accumulatedMeters: Double = 0
    private var lastSplitElapsed: TimeInterval = 0
    private var completedSplits: [RunSplit] = []
    private var windowEntries: [WindowEntry] = []

    /// 运行态下因时间戳未前进而被整条丢弃的采样条数。
    ///
    /// 只统计「已开始且未暂停」时命中单调守卫的样本；暂停/未开始/已结束路径的
    /// 直接返回不计入，避免被误读成「所有被丢样本计数」。恢复态同样从 0 起算。
    public private(set) var duplicateSampleCount: Int = 0

    public init() {}

    /// 由 checkpoint 恢复累计账本、已完成分段与时间/位置锚点。
    ///
    /// 与 `RunSessionMachine(restoring:)` 一致：`running`/`paused` 一律恢复为暂停态，
    /// 必须显式 `resume(at:)` 才能继续累计；`finished` 恢复为已结束；`ready` 恢复为未开始。
    public init(restoring checkpoint: RunCheckpoint) {
        accumulatedMeters = checkpoint.completedDistance.meters
        activeElapsed = checkpoint.elapsed
        completedSplits = checkpoint.splits
        // 分段计时基准由已完成分段的 `duration` 累加还原。
        lastSplitElapsed = checkpoint.splits.reduce(0) { $0 + $1.duration }

        switch checkpoint.state {
        case .ready:
            break
        case .running, .paused:
            isStarted = true
            isPaused = true
        case .finished:
            isStarted = true
            isFinished = true
        }

        if let anchor = checkpoint.lastSample {
            hasAnySample = true
            lastTimestamp = anchor.timestamp
            lastLatitude = anchor.latitude
            lastLongitude = anchor.longitude
        }
    }

    // MARK: - 最后采样点

    /// 最后一次被接受的采样点；未接受任何样本或恢复自无锚点的旧 checkpoint 时为 `nil`。
    public var lastAcceptedSample: RunSampleAnchor? {
        guard hasAnySample, let lastTimestamp, let lastLatitude, let lastLongitude else {
            return nil
        }
        return RunSampleAnchor(
            latitude: lastLatitude,
            longitude: lastLongitude,
            timestamp: lastTimestamp
        )
    }

    // MARK: - 快照

    public var metrics: RunMetrics {
        RunMetrics(
            distance: distanceValue,
            elapsed: activeElapsed,
            averagePace: averagePaceValue,
            currentPace: currentPaceValue,
            splits: completedSplits,
            completedKilometers: completedSplits.count
        )
    }

    // MARK: - 时间锚点

    public mutating func start(at date: Date) {
        guard !isFinished, !isStarted else { return }
        isStarted = true
        advanceAnchor(to: date)
    }

    public mutating func pause(at date: Date) {
        guard isStarted, !isFinished, !isPaused else { return }
        isPaused = true
        needsPositionAnchor = true
        windowEntries.removeAll()
        advanceAnchor(to: date)
    }

    public mutating func resume(at date: Date) {
        guard isStarted, !isFinished, isPaused else { return }
        isPaused = false
        needsPositionAnchor = true
        windowEntries.removeAll()
        advanceAnchor(to: date)
    }

    public mutating func finish(at date: Date) {
        guard !isFinished else { return }
        isFinished = true
        advanceAnchor(to: date)
    }

    // MARK: - 采样输入

    /// 喂入单个采样点，返回最新快照与本条新完成的分段。
    public mutating func ingest(_ sample: RunSample) -> RunMetricsUpdate {
        guard !isFinished else { return update(newlyCompletedSplits: []) }
        if !isStarted { isStarted = true }
        guard !isPaused else { return update(newlyCompletedSplits: []) }

        // 时间倒退或等时的样本整条丢弃：不回退距离/时长/分段。
        if hasAnySample, let lastTimestamp, sample.timestamp <= lastTimestamp {
            duplicateSampleCount += 1
            return update(newlyCompletedSplits: [])
        }

        // 首个被接受的样本只建立锚点：距离与活跃时长保持 0。
        if !hasAnySample {
            hasAnySample = true
            // 锚点已由该样本建立，无需再为暂停/恢复单独做一次位置重锚。
            needsPositionAnchor = false
            lastTimestamp = sample.timestamp
            lastLatitude = sample.latitude
            lastLongitude = sample.longitude
            resetWindow(at: sample)
            return update(newlyCompletedSplits: [])
        }

        if let lastTimestamp {
            activeElapsed += sample.timestamp.timeIntervalSince(lastTimestamp)
        }
        lastTimestamp = sample.timestamp

        // 暂停/恢复后的首个样本只重建位置锚点，不跨越空档累计位移。
        if needsPositionAnchor {
            needsPositionAnchor = false
            lastLatitude = sample.latitude
            lastLongitude = sample.longitude
            resetWindow(at: sample)
            return update(newlyCompletedSplits: [])
        }

        if let lastLatitude, let lastLongitude {
            accumulatedMeters += GeoDistance.meters(
                latitude1: lastLatitude,
                longitude1: lastLongitude,
                latitude2: sample.latitude,
                longitude2: sample.longitude
            )
        }
        lastLatitude = sample.latitude
        lastLongitude = sample.longitude

        windowEntries.append(
            WindowEntry(
                elapsed: activeElapsed,
                latitude: sample.latitude,
                longitude: sample.longitude
            )
        )
        pruneWindow()

        return update(newlyCompletedSplits: completeSplits())
    }

    // MARK: - 内部

    private mutating func advanceAnchor(to date: Date) {
        if let lastTimestamp, date <= lastTimestamp { return }
        lastTimestamp = date
    }

    private mutating func resetWindow(at sample: RunSample) {
        windowEntries = [
            WindowEntry(
                elapsed: activeElapsed,
                latitude: sample.latitude,
                longitude: sample.longitude
            )
        ]
    }

    private mutating func pruneWindow() {
        guard let newest = windowEntries.last else { return }
        let cutoff = newest.elapsed - Self.currentPaceWindowSeconds
        // 保留一个窗口外的边界点，使跨度不短于窗口长度；总长度仍受窗口约束。
        while windowEntries.count > 1, windowEntries[1].elapsed <= cutoff {
            windowEntries.removeFirst()
        }
    }

    private mutating func completeSplits() -> [RunSplit] {
        var created: [RunSplit] = []
        while accumulatedMeters >= Double(completedSplits.count + 1) * Self.splitDistanceMeters {
            let index = completedSplits.count + 1
            let duration = activeElapsed - lastSplitElapsed
            guard let splitDistance = RunDistance(meters: Self.splitDistanceMeters),
                  let split = RunSplit(index: index, distance: splitDistance, duration: duration)
            else { return created }
            completedSplits.append(split)
            lastSplitElapsed = activeElapsed
            created.append(split)
        }
        return created
    }

    private var distanceValue: RunDistance {
        RunDistance(meters: accumulatedMeters) ?? RunMetrics.initial.distance
    }

    private var averagePaceValue: RunPace? {
        guard accumulatedMeters > 0, activeElapsed > 0 else { return nil }
        return RunPace(secondsPerKilometer: activeElapsed / (accumulatedMeters / 1000.0))
    }

    private var currentPaceValue: RunPace? {
        guard !isPaused, windowEntries.count >= 2,
              let first = windowEntries.first, let last = windowEntries.last
        else { return nil }

        let span = last.elapsed - first.elapsed
        guard span >= Self.currentPaceMinimumDurationSeconds else { return nil }

        var meters = 0.0
        for index in 1..<windowEntries.count {
            let previous = windowEntries[index - 1]
            let current = windowEntries[index]
            meters += GeoDistance.meters(
                latitude1: previous.latitude,
                longitude1: previous.longitude,
                latitude2: current.latitude,
                longitude2: current.longitude
            )
        }
        guard meters >= Self.currentPaceMinimumDistanceMeters else { return nil }
        return RunPace(secondsPerKilometer: span / (meters / 1000.0))
    }

    private func update(newlyCompletedSplits: [RunSplit]) -> RunMetricsUpdate {
        RunMetricsUpdate(metrics: metrics, newlyCompletedSplits: newlyCompletedSplits)
    }
}
