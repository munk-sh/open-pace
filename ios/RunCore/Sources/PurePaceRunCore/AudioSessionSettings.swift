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

/// 音频会话选项（纯数据镜像）。
public enum AudioCategoryOption: String, CaseIterable, Sendable {
    case mixWithOthers
    case duckOthers
    case interruptSpokenAudioAndMixWithOthers
    case allowBluetoothA2DP
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
}
