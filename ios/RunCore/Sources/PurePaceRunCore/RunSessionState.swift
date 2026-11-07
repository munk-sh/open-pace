import Foundation

/// 跑步会话状态。本层只冻结状态取值与派生只读属性，不含迁移规则。
public enum RunSessionState: String, CaseIterable, Sendable {
    case ready
    case running
    case paused
    case finished

    /// 会话是否处于计时进行中的状态（`running` 或 `paused`）。
    public var isActive: Bool {
        switch self {
        case .running, .paused:
            return true
        case .ready, .finished:
            return false
        }
    }

    /// 会话是否已到达终态。
    public var isTerminal: Bool {
        self == .finished
    }
}
