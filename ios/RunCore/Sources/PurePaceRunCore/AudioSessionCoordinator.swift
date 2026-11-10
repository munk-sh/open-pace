import Foundation

/// 音频会话协调器的纯逻辑状态。
public enum AudioSessionState: String, CaseIterable, Sendable {
    case inactive
    case active
    case interrupted
}

/// 协调器一次状态转移应执行的动作（纯数据，不含真实调用）。
public enum AudioSessionAction: Equatable, Sendable {
    /// 按给定配置激活会话。
    case activate(settings: AudioSessionSettings)
    /// 按给定选项停用会话。
    case deactivate(options: Set<AudioCategoryOption>)
    /// 无需任何平台调用。
    case none
}

/// AudioSession 配置与中断恢复契约协调器。
///
/// 只做状态机与动作推导，不依赖平台音频框架、不真实激活/停用会话、不读回状态。
/// 默认配置为 `AudioSessionSettings.defaultAnnouncement`
/// （`.playback` / `.spokenAudio` / `[.duckOthers, .mixWithOthers]`，
/// 停用选项 `[.notifyOthersOnDeactivation]`）。
public struct AudioSessionCoordinator: Equatable, Sendable {
    public let settings: AudioSessionSettings
    public private(set) var state: AudioSessionState

    public init(
        settings: AudioSessionSettings = .defaultAnnouncement,
        state: AudioSessionState = .inactive
    ) {
        self.settings = settings
        self.state = state
    }

    /// 激活会话：仅 `.inactive` 产生一次激活动作，其余状态幂等返回 `.none`。
    public mutating func activate() -> AudioSessionAction {
        guard state == .inactive else { return .none }
        state = .active
        return .activate(settings: settings)
    }

    /// 停用会话：纯动作推导，任何情况下都不改变 `state`。
    /// 仅 `.active` 产生停用动作并携带配置的停用选项；其余状态返回 `.none`。
    /// 状态提交由 `commitDeactivation()` 在平台调用真实成功后完成。
    public func deactivate() -> AudioSessionAction {
        guard state == .active else { return .none }
        return .deactivate(options: settings.deactivationOptions)
    }

    /// 停用状态提交：仅在平台 `setActive(false, …)` 真实成功后调用。
    ///
    /// 只做 `.active -> .inactive` 的纯状态转移；不产生/返回动作、不触碰平台。
    /// `.inactive` / `.interrupted` 调用后状态不变。
    public mutating func commitDeactivation() {
        guard state == .active else { return }
        state = .inactive
    }

    /// 中断开始：仅 `.active` 进入 `.interrupted`，且不产生任何激活动作；
    /// 重复 `began` 幂等。
    public mutating func interruptionBegan() -> AudioSessionAction {
        if state == .active {
            state = .interrupted
        }
        return .none
    }

    /// 中断结束：仅在 `.interrupted` 时生效。
    /// `shouldResume == true` 按默认公告配置重新激活并回到 `.active`；
    /// `shouldResume == false` 回到 `.inactive` 且不产生动作。
    /// 未处于 `.interrupted` 时返回 `.none` 且状态不变。
    public mutating func interruptionEnded(shouldResume: Bool) -> AudioSessionAction {
        guard state == .interrupted else { return .none }
        guard shouldResume else {
            state = .inactive
            return .none
        }
        state = .active
        return .activate(settings: settings)
    }
}
