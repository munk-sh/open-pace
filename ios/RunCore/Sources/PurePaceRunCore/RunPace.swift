import Foundation

/// 配速（秒/公里）。只接受有限且严格为正的数值。
public struct RunPace: Hashable, Comparable, Sendable {
    public let secondsPerKilometer: Double

    public init?(secondsPerKilometer: Double) {
        guard secondsPerKilometer.isFinite, secondsPerKilometer > 0 else {
            return nil
        }
        self.secondsPerKilometer = secondsPerKilometer
    }

    /// 由已完成距离与耗时派生配速；距离或耗时不合法时返回 `nil`。
    public init?(distance: RunDistance, duration: TimeInterval) {
        guard distance.meters > 0, duration.isFinite, duration > 0 else {
            return nil
        }
        let pace = duration / (distance.meters / 1000)
        guard pace.isFinite, pace > 0 else {
            return nil
        }
        self.secondsPerKilometer = pace
    }

    public static func < (lhs: RunPace, rhs: RunPace) -> Bool {
        lhs.secondsPerKilometer < rhs.secondsPerKilometer
    }
}
