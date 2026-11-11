import Foundation

/// 开始记录前的可取消倒计时。纯值类型：不持有定时器、不读系统时钟，
/// 剩余时间与「到点」判定全部由调用方注入的 `Date` 决定。
///
/// 倒计时不属于 `RunSessionState`（该枚举保持 4 态冻结），只是「开始前」的
/// 一个瞬态：到点前不产生任何度量、采样或 checkpoint。
public struct RunStartCountdown: Equatable, Sendable {
    /// 默认倒计时总时长（秒）。时长常量只允许出现在本层，UI 目录不得写字面量。
    public static let defaultDuration: TimeInterval = 3

    /// 总时长（秒）；负数与非有限值一律归零，归零即「立刻可完成」。
    public let duration: TimeInterval

    /// 倒计时开始时刻（由调用方注入）。
    public let startedAt: Date

    public init(duration: TimeInterval = RunStartCountdown.defaultDuration, startedAt: Date) {
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        self.startedAt = startedAt
    }

    /// 到点时刻。
    public var deadline: Date {
        startedAt.addingTimeInterval(duration)
    }

    /// 相对 `date` 的剩余秒数，恒不为负；随注入时钟单调递减。
    public func remaining(at date: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(date))
    }

    /// 是否已到点（恰好在 deadline 时视为完成）。
    public func isComplete(at date: Date) -> Bool {
        date >= deadline
    }
}
