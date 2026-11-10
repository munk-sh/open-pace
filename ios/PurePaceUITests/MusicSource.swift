import AVFoundation
import CryptoKit
import Foundation

/// 真机 audio 阶段的音源策略：`runner` = UITests runner 自播合成循环音（默认、无人操作），
/// `app` = 启动外部 App（`--music-bundle-id` 指定，缺省 `com.apple.Music`），`none` = 不产生任何音源。
///
/// 策略经 `scripts/verify-ios-device-flow.sh --music-strategy=…` 以 `TEST_RUNNER_MUSIC_STRATEGY`
/// 环境变量传入；非法值回落 `runner` 并在证据里记 `invalidRequested`（不静默）。
enum MusicStrategy: String, CaseIterable {
    case runner
    case app
    case none

    static let `default`: MusicStrategy = .runner

    /// `app` 策略的缺省目标 bundle id；`MusicSourceSelfCheckUITests` 用常量断言钉死该值。
    static let defaultBundleIdentifier = "com.apple.Music"

    struct Resolution {
        let strategy: MusicStrategy
        /// 环境变量原始值（缺省时为 nil）。
        let rawValue: String?
        /// 请求了但非法时保留原值，证据里如实记录。
        let invalidRequested: String?
    }

    /// 解析策略：缺省 `runner`；大小写不敏感；非法值回落 `runner` 并标记 `invalidRequested`。
    static func from(environment: [String: String]) -> Resolution {
        let raw = environment["TEST_RUNNER_MUSIC_STRATEGY"] ?? environment["MUSIC_STRATEGY"]
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Resolution(strategy: .default, rawValue: nil, invalidRequested: nil)
        }
        if let parsed = MusicStrategy(rawValue: raw.lowercased()) {
            return Resolution(strategy: parsed, rawValue: raw, invalidRequested: nil)
        }
        return Resolution(strategy: .default, rawValue: raw, invalidRequested: raw)
    }

    /// `app` 策略目标 bundle id：`TEST_RUNNER_MUSIC_BUNDLE_ID` → `MUSIC_BUNDLE_ID` → 常量。
    static func bundleIdentifier(environment: [String: String]) -> String {
        let raw = environment["TEST_RUNNER_MUSIC_BUNDLE_ID"] ?? environment["MUSIC_BUNDLE_ID"]
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultBundleIdentifier
        }
        return raw
    }

    /// 只有 `runner` 策略才创建 runner 自播音源；`app` / `none` 返回 nil（不产生任何播放器）。
    func makeRunnerSource() -> RunnerMusicSource? {
        guard self == .runner else { return nil }
        return RunnerMusicSource()
    }
}

/// audio 阶段的确定性定位 launch-arg：按构建配置选择，Release 不得用 `-uiTestLocation`。
///
/// Debug UI-test 构建用 `-uiTestLocation`（`#if DEBUG` 门控的确定性源，可清空归档）；
/// Release 候选包用 `-releaseDeterministicLocation km-crossing`（默认关，必须显式传）。
enum AudioLaunchArguments {
    static var current: [String] {
#if DEBUG
        return ["-uiTestLocation", "-uiTestResetArchive"]
#else
        return ["-releaseDeterministicLocation", "km-crossing"]
#endif
    }

    static var configurationName: String {
#if DEBUG
        return "Debug"
#else
        return "Release"
#endif
    }
}

/// `app` 策略的曲目元数据探针：只读解析系统 Music 的可及树，标题/时长/本地文件三态 + 判定依据。
///
/// 解析是纯函数（输入 = `XCUIApplication.debugDescription` 文本），读不到标题/时长时返回空值，
/// 脚本侧据此判 FAIL（不用 `unknown` 空过）。`isLocalFile` 无下载/云端标识时一律 `unknown`。
enum MusicAppProbe {
    static let durationPattern = #"\b\d{1,2}:\d{2}\b"#
    static let labelPattern = #"label: '([^']+)'"#

    private static let chromeLabels: Set<String> = [
        "播放", "暂停", "上一首", "下一首", "随机播放", "重复", "AirPlay", "正在播放",
        "Play", "Pause", "Next", "Previous", "Shuffle", "Repeat", "Now Playing",
        "主页", "资料库", "广播", "搜索", "Home", "Library", "Radio", "Search",
        "歌词", "Lyrics", "音量", "Volume",
    ]
    private static let downloadedMarkers = ["已下载", "Downloaded", "已经下载"]
    private static let cloudMarkers = ["iCloud", "下载", "Download", "云端"]

    static func parse(axDump: String, capturedAt: Double = Date().timeIntervalSince1970) -> [String: Any] {
        var labels: [String] = []
        for line in axDump.split(separator: "\n") {
            let text = String(line)
            guard let match = text.range(of: labelPattern, options: .regularExpression) else { continue }
            let raw = String(text[match]).replacingOccurrences(of: "label: '", with: "")
            let label = raw.hasSuffix("'") ? String(raw.dropLast()) : raw
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                labels.append(trimmed)
            }
        }

        let durationText = labels.first { $0.range(of: durationPattern, options: .regularExpression) != nil }
        let durationSeconds = durationText.flatMap { value -> Double? in
            let parts = value.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        let title = labels.first { label in
            !chromeLabels.contains(label)
                && label.range(of: durationPattern, options: .regularExpression) == nil
                && label.count >= 1
        }

        var localValue = "unknown"
        var localBasis = "可及树未见下载/云端标识，无法判定是否本地文件（不据此宣称本地文件已验证）"
        if downloadedMarkers.contains(where: { axDump.contains($0) }) {
            localValue = "true"
            localBasis = "可及树含下载态标识（已下载/Downloaded）"
        } else if cloudMarkers.contains(where: { axDump.contains($0) }) {
            localValue = "false"
            localBasis = "可及树含云端/下载标识，判定非本地文件"
        }

        var payload: [String: Any] = [
            "probe": "XCUIApplication(com.apple.Music) 可及树 + 截图",
            "capturedAt": capturedAt,
            "isLocalFile": localValue,
            "localFileBasis": localBasis,
            "titleBasis": "可及树 label 首个非控件文案",
        ]
        if let title { payload["nowPlayingTitle"] = title }
        if let durationText { payload["durationText"] = durationText }
        if let durationSeconds { payload["durationSeconds"] = durationSeconds }
        return payload
    }
}

/// runner 进程侧 `isOtherAudioPlaying` 快照：用于判定「播报期 true 是否可能来自自身 TTS 自污染」。
///
/// 注意：runner 自己的播放不算 runner 的「他路音频」，所以此读数不能替代被测 App 的遥测字段；
/// 它只作为「同一时刻系统里是否有其它进程在播音」的旁证。
enum OtherAudioSnapshot {
    static let source = "AVAudioSession.sharedInstance().isOtherAudioPlaying @ UITests runner 进程"

    static func capture(label: String) -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        return [
            "label": label,
            "at": Date().timeIntervalSince1970,
            "isOtherAudioPlaying": session.isOtherAudioPlaying,
        ]
    }
}

/// runner 自播音源：从 UITests bundle 载入 `Fixtures/runner-music-loop.wav`，`AVAudioPlayer` 循环播放。
///
/// 只在 runner 进程内运行——它播出的音频对被测 App 而言是「他路音频」，是 `isOtherAudioPlaying`
/// 可归因的证据来源；`none` 策略下不创建播放器（负对照）。
final class RunnerMusicSource: NSObject {
    static let assetName = "runner-music-loop.wav"
    static let assetResourceName = "runner-music-loop"
    static let assetExtension = "wav"
    static let maxAssetBytes = 204_800

    private(set) var assetURL: URL?
    private(set) var assetBytes: Int?
    private(set) var assetSHA256: String?
    private(set) var playbackStartedAt: Double?
    private(set) var playbackStoppedAt: Double?
    private(set) var isPlayingAtStart = false
    private(set) var currentTimeAtStart: Double?
    private(set) var sessionSetActiveTrueCalled = false
    private(set) var lastError: String?

    private let bundle: Bundle
    private var player: AVAudioPlayer?

    init(bundle: Bundle = Bundle(for: RunnerMusicSource.self)) {
        self.bundle = bundle
        super.init()
    }

    /// 资产定位：UITests bundle 资源根目录。
    static func locateAsset(in bundle: Bundle) -> URL? {
        bundle.url(forResource: assetResourceName, withExtension: assetExtension)
    }

    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }
    var hasPlayer: Bool { player != nil }

    /// 起播：先载入资产与 AudioSession（`.playback` + `setActive(true)`），再循环播放。
    /// 任一步失败如实返回 false 并写入 `lastError`，不伪造「在播」。
    @discardableResult
    func start() -> Bool {
        guard let url = Self.locateAsset(in: bundle) else {
            lastError = "asset-missing: \(Self.assetName)"
            return false
        }
        assetURL = url

        let data = (try? Data(contentsOf: url)) ?? Data()
        assetBytes = data.count
        assetSHA256 = Self.sha256Hex(data)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            sessionSetActiveTrueCalled = true
        } catch {
            lastError = "audio-session: \(error.localizedDescription)"
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.prepareToPlay()
            playbackStartedAt = Date().timeIntervalSince1970
            let started = player.play()
            self.player = player
            isPlayingAtStart = started && player.isPlaying
            currentTimeAtStart = player.currentTime
            return isPlayingAtStart
        } catch {
            lastError = "player: \(error.localizedDescription)"
            return false
        }
    }

    /// 停止播放：记录停止时刻，保留最后一次 `currentTime` 前由调用方读取。
    func stop() {
        playbackStoppedAt = Date().timeIntervalSince1970
        player?.stop()
    }

    /// 结构化证据：字段存在性/类型/实测值先于任何语义结论落盘。
    func evidence() -> [String: Any] {
        var payload: [String: Any] = [
            "strategy": MusicStrategy.runner.rawValue,
            "assetName": Self.assetName,
            "hasPlayer": hasPlayer,
            "playerStarted": player != nil,
            "isPlayingAtStart": isPlayingAtStart,
            "isPlayingAtFinish": isPlaying,
            "currentTimeAtFinish": currentTime,
            "sessionSetActiveTrueCalled": sessionSetActiveTrueCalled,
        ]
        if let assetBytes { payload["assetBytes"] = assetBytes }
        if let assetSHA256 { payload["assetSHA256"] = assetSHA256 }
        if let playbackStartedAt { payload["playbackStartedAt"] = playbackStartedAt }
        if let playbackStoppedAt { payload["playbackStoppedAt"] = playbackStoppedAt }
        if let currentTimeAtStart { payload["currentTimeAtStart"] = currentTimeAtStart }
        if let lastError { payload["playerError"] = lastError }
        return payload
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
