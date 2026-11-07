import Foundation

/// 会话状态机。只持有状态并做迁移校验，不负责计时、距离或持久化。
///
/// 合法迁移恰为 5 条：`ready→running`、`running→paused`、`running→finished`、
/// `paused→running`、`paused→finished`。其余组合（含自迁移与 `finished→*`）一律非法。
public struct RunSessionMachine: Equatable, Sendable {
    /// 当前状态。
    public private(set) var state: RunSessionState

    /// 由 checkpoint 恢复时保留的原始记录；全新构造的机器为 `nil`。
    public let restoredCheckpoint: RunCheckpoint?

    /// 构造一个全新会话状态机，默认处于 `ready`。
    public init(state: RunSessionState = .ready) {
        self.state = state
        self.restoredCheckpoint = nil
    }

    /// 由 checkpoint 恢复。`running`/`paused` 一律恢复为 `paused`（中断后必须显式 `resume()`），
    /// `ready`/`finished` 原样恢复；checkpoint 中的距离、耗时与分段原样保留。
    public init(restoring checkpoint: RunCheckpoint) {
        switch checkpoint.state {
        case .running, .paused:
            self.state = .paused
        case .ready, .finished:
            self.state = checkpoint.state
        }
        self.restoredCheckpoint = checkpoint
    }

    /// 当前状态是否允许迁移到 `newState`。
    public func canTransition(to newState: RunSessionState) -> Bool {
        switch (state, newState) {
        case (.ready, .running),
             (.running, .paused),
             (.running, .finished),
             (.paused, .running),
             (.paused, .finished):
            return true
        default:
            return false
        }
    }

    /// 执行迁移；非法迁移抛出 `RunCoreError.invalidStateTransition`，且状态保持不变。
    public mutating func transition(to newState: RunSessionState) throws {
        guard canTransition(to: newState) else {
            throw RunCoreError.invalidStateTransition(from: state, to: newState)
        }
        state = newState
    }

    /// 开始跑步：仅 `ready` 合法。
    public mutating func start() throws {
        guard state == .ready else {
            throw RunCoreError.invalidStateTransition(from: state, to: .running)
        }
        try transition(to: .running)
    }

    /// 暂停：仅 `running` 合法。
    public mutating func pause() throws {
        try transition(to: .paused)
    }

    /// 继续：仅 `paused` 合法。
    public mutating func resume() throws {
        guard state == .paused else {
            throw RunCoreError.invalidStateTransition(from: state, to: .running)
        }
        try transition(to: .running)
    }

    /// 结束：仅 `running`/`paused` 合法。
    public mutating func finish() throws {
        try transition(to: .finished)
    }
}
