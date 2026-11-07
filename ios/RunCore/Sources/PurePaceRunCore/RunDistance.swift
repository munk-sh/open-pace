import Foundation

/// 跑步距离（米）。只接受有限且非负的数值。
public struct RunDistance: Hashable, Comparable, Sendable {
    public let meters: Double

    public init?(meters: Double) {
        guard meters.isFinite, meters >= 0 else {
            return nil
        }
        self.meters = meters
    }

    public static func < (lhs: RunDistance, rhs: RunDistance) -> Bool {
        lhs.meters < rhs.meters
    }
}
