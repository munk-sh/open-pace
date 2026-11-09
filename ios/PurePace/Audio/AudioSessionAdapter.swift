import AVFoundation
import Foundation
import PurePaceRunCore

/// 真实 `AVAudioSession` 的最小可测接缝：只暴露适配器需要的读写能力。
///
/// 生产实现包装 `AVAudioSession.sharedInstance()`；测试用 spy 记录下发的平台调用，
/// 从而在模拟器内断言「下发了什么调用」而不依赖真实音频路由或真实来电。
protocol AudioSessionControlling: AnyObject {
    var category: AVAudioSession.Category { get }
    var mode: AVAudioSession.Mode { get }
    var categoryOptions: AVAudioSession.CategoryOptions { get }
    /// 是否有其它 App 正在播放音频（只读，如实记录，不做断言）。
    var isOtherAudioPlaying: Bool { get }
    /// 系统是否建议压低次要音频（只读，如实记录，不做断言）。
    var secondaryAudioShouldBeSilencedHint: Bool { get }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

/// 包装进程共享音频会话的真实实现。
final class AVAudioSessionController: AudioSessionControlling {
    private let session: AVAudioSession

    init(session: AVAudioSession = AVAudioSession.sharedInstance()) {
        self.session = session
    }

    var category: AVAudioSession.Category { session.category }
    var mode: AVAudioSession.Mode { session.mode }
    var categoryOptions: AVAudioSession.CategoryOptions { session.categoryOptions }
    var isOtherAudioPlaying: Bool { session.isOtherAudioPlaying }
    var secondaryAudioShouldBeSilencedHint: Bool { session.secondaryAudioShouldBeSilencedHint }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        try session.setCategory(category, mode: mode, options: options)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(active, options: options)
    }
}

/// 平台中断的一次映射（纯 Sendable 数据，便于把通知解析与平台状态机解耦）。
enum AudioInterruptionEvent: Equatable, Sendable {
    case began
    case ended(shouldResume: Bool)

    init?(notification: Notification) {
        guard
            notification.name == AVAudioSession.interruptionNotification,
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return nil
        }

        switch type {
        case .began:
            self = .began
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                .contains(.shouldResume)
            self = .ended(shouldResume: shouldResume)
        @unknown default:
            return nil
        }
    }
}

/// 把 `AudioSessionSettings.defaultAnnouncement` 与中断生命周期落到真实平台的薄适配层。
///
/// 只做「导出 `AudioSessionAction`」这一件事：状态机与幂等语义全部复用
/// `AudioSessionCoordinator`，App 侧不再自带状态。播报开始激活、结束停用；
/// 系统中断 began/ended 映射为协调器调用并执行其返回动作。
final class AudioSessionAdapter: NSObject {
    private let controller: AudioSessionControlling
    private let notificationCenter: NotificationCenter
    private var coordinator: AudioSessionCoordinator
    private var isObservingInterruptions = false

    init(
        controller: AudioSessionControlling = AVAudioSessionController(),
        settings: AudioSessionSettings = .defaultAnnouncement,
        notificationCenter: NotificationCenter = .default,
        observesInterruptions: Bool = true
    ) {
        self.controller = controller
        self.notificationCenter = notificationCenter
        self.coordinator = AudioSessionCoordinator(settings: settings)
        super.init()

        guard observesInterruptions else { return }
        notificationCenter.addObserver(
            self,
            selector: #selector(interruptionDidOccur(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        isObservingInterruptions = true
    }

    deinit {
        if isObservingInterruptions {
            notificationCenter.removeObserver(self)
        }
    }

    /// 当前纯逻辑会话状态（供测试与调试读取，不参与平台调用）。
    var state: AudioSessionState { coordinator.state }

    /// 播报时刻的音频环境快照（`sessionActivated` 由调用方按真实下发结果传入）。
    func announcementContext(sessionActivated: Bool) -> AnnouncementAudioContext {
        AnnouncementAudioContext(
            category: Self.categoryLiteral(controller.category),
            mode: Self.modeLiteral(controller.mode),
            categoryOptions: Self.optionLiterals(controller.categoryOptions),
            isOtherAudioPlaying: controller.isOtherAudioPlaying,
            secondaryAudioShouldBeSilencedHint: controller.secondaryAudioShouldBeSilencedHint,
            sessionActivated: sessionActivated
        )
    }

    /// 播报开始：幂等激活（重复调用只产生一次 `setActive(true)`）。返回是否真实下发平台调用。
    @discardableResult
    func beginAnnouncement() throws -> Bool {
        let action = coordinator.activate()
        let performed = Self.performsPlatformCall(action)
        try perform(action)
        return performed
    }

    /// 播报结束：仅在确实处于激活态时停用一次，选项取自配置的 `deactivationOptions`。
    /// 返回是否真实下发平台调用（即 duck 撤销/会话恢复是否发生）。
    @discardableResult
    func endAnnouncement() throws -> Bool {
        let action = coordinator.deactivate()
        let performed = Self.performsPlatformCall(action)
        try perform(action)
        return performed
    }

    /// 测试与系统通知共用的处理入口：投递真实 `AVAudioSession.interruptionNotification`。
    func handleInterruption(notification: Notification) {
        guard let event = AudioInterruptionEvent(notification: notification) else { return }
        handleInterruption(event)
    }

    func handleInterruption(_ event: AudioInterruptionEvent) {
        switch event {
        case .began:
            performIgnoringErrors(coordinator.interruptionBegan())
        case let .ended(shouldResume):
            performIgnoringErrors(coordinator.interruptionEnded(shouldResume: shouldResume))
        }
    }

    @objc private func interruptionDidOccur(_ notification: Notification) {
        handleInterruption(notification: notification)
    }

    private static func performsPlatformCall(_ action: AudioSessionAction) -> Bool {
        if case .none = action { return false }
        return true
    }

    private static func categoryLiteral(_ category: AVAudioSession.Category) -> String {
        switch category {
        case .playback: return "playback"
        case .playAndRecord: return "playAndRecord"
        case .ambient: return "ambient"
        case .soloAmbient: return "soloAmbient"
        case .multiRoute: return "multiRoute"
        case .record: return "record"
        default: return category.rawValue
        }
    }

    private static func modeLiteral(_ mode: AVAudioSession.Mode) -> String {
        switch mode {
        case .default: return "default"
        case .spokenAudio: return "spokenAudio"
        case .measurement: return "measurement"
        case .moviePlayback: return "moviePlayback"
        case .videoRecording: return "videoRecording"
        case .voiceChat: return "voiceChat"
        case .voicePrompt: return "voicePrompt"
        case .gameChat: return "gameChat"
        case .videoChat: return "videoChat"
        default: return mode.rawValue
        }
    }

    private static func optionLiterals(_ options: AVAudioSession.CategoryOptions) -> [String] {
        var literals: [String] = []
        if options.contains(.duckOthers) { literals.append("duckOthers") }
        if options.contains(.mixWithOthers) { literals.append("mixWithOthers") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) {
            literals.append("interruptSpokenAudioAndMixWithOthers")
        }
        if options.contains(.allowBluetoothA2DP) { literals.append("allowBluetoothA2DP") }
        return literals
    }

    private func perform(_ action: AudioSessionAction) throws {
        switch action {
        case let .activate(settings):
            try controller.setCategory(
                AVAudioSession.Category(settings.category),
                mode: AVAudioSession.Mode(settings.mode),
                options: AVAudioSession.CategoryOptions(settings.options)
            )
            try controller.setActive(true, options: [])
        case let .deactivate(options):
            try controller.setActive(false, options: AVAudioSession.SetActiveOptions(options))
        case .none:
            break
        }
    }

    private func performIgnoringErrors(_ action: AudioSessionAction) {
        do {
            try perform(action)
        } catch {
            // 系统中断回调没有调用方可以处理错误；失败时保持纯逻辑状态，交由下一次系统事件重试。
        }
    }
}

// MARK: - 纯数据契约到平台类型的显式全量映射

extension AVAudioSession.Category {
    init(_ category: AudioCategory) {
        switch category {
        case .playback: self = .playback
        case .playAndRecord: self = .playAndRecord
        }
    }
}

extension AVAudioSession.Mode {
    init(_ mode: AudioMode) {
        switch mode {
        case .default: self = .default
        case .spokenAudio: self = .spokenAudio
        }
    }
}

extension AVAudioSession.CategoryOptions {
    init(_ option: AudioCategoryOption) {
        switch option {
        case .mixWithOthers: self = .mixWithOthers
        case .duckOthers: self = .duckOthers
        case .interruptSpokenAudioAndMixWithOthers: self = .interruptSpokenAudioAndMixWithOthers
        case .allowBluetoothA2DP: self = .allowBluetoothA2DP
        case .notifyOthersOnDeactivation:
            // 只对 setActive 生效，对 setCategory 无对应语义。
            self = []
        }
    }

    init(_ options: Set<AudioCategoryOption>) {
        var result: AVAudioSession.CategoryOptions = []
        for option in options {
            result.insert(AVAudioSession.CategoryOptions(option))
        }
        self = result
    }
}

extension AVAudioSession.SetActiveOptions {
    init(_ option: AudioCategoryOption) {
        switch option {
        case .notifyOthersOnDeactivation:
            self = .notifyOthersOnDeactivation
        case .mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers, .allowBluetoothA2DP:
            // 这四项只对 setCategory 生效，对 setActive 无对应语义。
            self = []
        }
    }

    init(_ options: Set<AudioCategoryOption>) {
        var result: AVAudioSession.SetActiveOptions = []
        for option in options {
            result.insert(AVAudioSession.SetActiveOptions(option))
        }
        self = result
    }
}
