import Foundation

/// 度量快照。纯值语义，不含格式化、IO 或平台框架依赖。
public struct RunMetrics: Equatable, Sendable {
    /// 累计距离（未满整公里的尾巴也计入）。
    public let distance: RunDistance
    /// 活跃时长（秒），暂停区间不计入。
    public let elapsed: TimeInterval
    /// 平均配速；距离或时长为 0 时为 `nil`。
    public let averagePace: RunPace?
    /// 当前配速（滑动窗口）；预热未完成或暂停中为 `nil`。
    public let currentPace: RunPace?
    /// 已完成的整公里分段，按序号递增。
    public let splits: [RunSplit]
    /// 已跨过的整公里计数，等于 `splits.count`。
    public let completedKilometers: Int

    public init(
        distance: RunDistance,
        elapsed: TimeInterval,
        averagePace: RunPace?,
        currentPace: RunPace?,
        splits: [RunSplit],
        completedKilometers: Int
    ) {
        self.distance = distance
        self.elapsed = elapsed
        self.averagePace = averagePace
        self.currentPace = currentPace
        self.splits = splits
        self.completedKilometers = completedKilometers
    }

    /// 尚未开始时的空快照。
    public static let initial = RunMetrics(
        distance: RunDistance(meters: 0) ?? RunMetrics.zeroDistance,
        elapsed: 0,
        averagePace: nil,
        currentPace: nil,
        splits: [],
        completedKilometers: 0
    )

    private static let zeroDistance: RunDistance = {
        // 0 米必然合法：RunDistance 只拒绝负数与非有限值。
        guard let value = RunDistance(meters: 0) else {
            preconditionFailure("RunDistance(meters: 0) 必须合法")
        }
        return value
    }()
}

/// 单次 `ingest` 的结果：最新快照与本条采样新完成的整公里分段。
public struct RunMetricsUpdate: Equatable, Sendable {
    public let metrics: RunMetrics
    public let newlyCompletedSplits: [RunSplit]

    public init(metrics: RunMetrics, newlyCompletedSplits: [RunSplit]) {
        self.metrics = metrics
        self.newlyCompletedSplits = newlyCompletedSplits
    }
}
