import Foundation

/// 公里分段契约。序号从 1 开始，耗时必须有限且为正。
public struct RunSplit: Equatable, Sendable {
    public let index: Int
    public let distance: RunDistance
    public let duration: TimeInterval

    public init?(index: Int, distance: RunDistance, duration: TimeInterval) {
        guard index >= 1, duration.isFinite, duration > 0 else {
            return nil
        }
        self.index = index
        self.distance = distance
        self.duration = duration
    }

    /// 由本段距离与耗时派生的配速；数据不足时为 `nil`。
    public var pace: RunPace? {
        RunPace(distance: distance, duration: duration)
    }
}
