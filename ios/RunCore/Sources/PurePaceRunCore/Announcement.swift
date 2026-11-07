import Foundation

/// 播报触发原因。
public enum AnnouncementTrigger: String, CaseIterable, Sendable {
    case kilometerCompleted
    case resumedAfterPause
    case finished
}

/// 一条播报命令的纯数据契约。本层不生成、不去重、不排序。
public struct AnnouncementCommand: Equatable, Sendable {
    public let trigger: AnnouncementTrigger
    public let splitIndex: Int
    public let distance: RunDistance
    public let pace: RunPace
    public let elapsed: TimeInterval

    public init?(
        trigger: AnnouncementTrigger,
        splitIndex: Int,
        distance: RunDistance,
        pace: RunPace,
        elapsed: TimeInterval
    ) {
        guard splitIndex >= 1, elapsed.isFinite, elapsed >= 0 else {
            return nil
        }
        self.trigger = trigger
        self.splitIndex = splitIndex
        self.distance = distance
        self.pace = pace
        self.elapsed = elapsed
    }
}
