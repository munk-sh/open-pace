import Foundation

/// 音频会话类别（纯数据镜像，不依赖平台音频框架）。
public enum AudioCategory: String, CaseIterable, Sendable {
    case playback
    case playAndRecord
}

/// 音频会话模式（纯数据镜像）。
public enum AudioMode: String, CaseIterable, Sendable {
    case `default`
    case spokenAudio
}

/// 音频会话选项（纯数据镜像）。既有 case 的 rawValue 与顺序不变，新 case 追加在末尾。
public enum AudioCategoryOption: String, CaseIterable, Sendable {
    case mixWithOthers
    case duckOthers
    case interruptSpokenAudioAndMixWithOthers
    case allowBluetoothA2DP
    case notifyOthersOnDeactivation
}

/// 音频会话配置契约。只承载数据，不激活会话、不读回状态。
public struct AudioSessionSettings: Hashable, Sendable {
    public let category: AudioCategory
    public let mode: AudioMode
    public let options: Set<AudioCategoryOption>
    public let deactivationOptions: Set<AudioCategoryOption>

    public init(
        category: AudioCategory,
        mode: AudioMode,
        options: Set<AudioCategoryOption>,
        deactivationOptions: Set<AudioCategoryOption>
    ) {
        self.category = category
        self.mode = mode
        self.options = options
        self.deactivationOptions = deactivationOptions
    }

    /// 冻结的公告音频配置：`.playback` + `.spokenAudio`，激活时 duck 且允许混音，
    /// 停用时通知其它音频会话恢复。只是纯数据契约，不激活或不读回真实会话。
    public static let defaultAnnouncement = AudioSessionSettings(
        category: .playback,
        mode: .spokenAudio,
        options: [.duckOthers, .mixWithOthers],
        deactivationOptions: [.notifyOthersOnDeactivation]
    )
}
