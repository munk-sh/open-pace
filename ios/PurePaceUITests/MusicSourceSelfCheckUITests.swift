import AVFoundation
import XCTest

/// 模拟器可跑的音源自证：资产 / UITests bundle 后台音频声明 / 策略解析 / runner 播放器状态。
///
/// 该用例不进 `DeviceFlowUITests`（`scripts/test-ios.sh` 只跳过 DeviceFlow 真机套件），
/// 默认 UI 腿会执行。模拟器无法观测的 app 侧语义（`isOtherAudioPlaying` 归因、真实 duck、
/// `duckRevoked`、`sessionDeactivated`）一律记 `simulatorNotApplicable`，不伪绿。
final class MusicSourceSelfCheckUITests: XCTestCase {
    private static let expectedAssetMaxBytes = 204_800

    func testDefaultStrategyAndBundleDeclarations() {
        let bundle = Bundle(for: RunnerMusicSource.self)
        let modes = (bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]) ?? []
        let assetURL = RunnerMusicSource.locateAsset(in: bundle)
        let assetBytes = assetURL.flatMap { try? Data(contentsOf: $0) }?.count ?? 0

        let evidence: [String: Any] = [
            "test": "testDefaultStrategyAndBundleDeclarations",
            "bundleIdentifier": bundle.bundleIdentifier ?? NSNull(),
            "uiBackgroundModes": modes,
            "assetName": RunnerMusicSource.assetName,
            "assetPresent": assetURL != nil,
            "assetBytes": assetBytes,
            "defaultStrategy": MusicStrategy.default.rawValue,
            "defaultStrategyFromEmptyEnvironment": MusicStrategy.from(environment: [:]).strategy.rawValue,
            "defaultBundleIdentifierConstant": MusicStrategy.defaultBundleIdentifier,
            "simulatorNotApplicable": Self.simulatorNotApplicable(),
        ]
        attachJSON(evidence, name: "music-source-selfcheck-declarations.json")

        // 常量断言：目标音源 id 钉死为 com.apple.Music（改动即红）。
        XCTAssertEqual(MusicStrategy.defaultBundleIdentifier, "com.apple.Music")
        XCTAssertEqual(MusicStrategy.default, .runner)
        XCTAssertEqual(
            MusicStrategy.from(environment: [:]).strategy,
            .runner,
            "缺省策略必须解析为 runner"
        )
        XCTAssertNil(MusicStrategy.from(environment: [:]).invalidRequested)
        XCTAssertEqual(
            MusicStrategy.from(environment: ["TEST_RUNNER_MUSIC_STRATEGY": "app"]).strategy,
            .app
        )
        XCTAssertEqual(
            MusicStrategy.from(environment: ["TEST_RUNNER_MUSIC_STRATEGY": "bogus"]).strategy,
            .runner,
            "非法值回落 runner"
        )
        XCTAssertEqual(
            MusicStrategy.from(environment: ["TEST_RUNNER_MUSIC_STRATEGY": "bogus"]).invalidRequested,
            "bogus",
            "非法值必须在证据里保留原值"
        )
        XCTAssertEqual(
            MusicStrategy.bundleIdentifier(environment: [:]),
            "com.apple.Music",
            "app 策略缺省 bundle id 取常量"
        )

        XCTAssertNotNil(assetURL, "UITests bundle 缺少 \(RunnerMusicSource.assetName)")
        XCTAssertGreaterThan(assetBytes, 0)
        XCTAssertLessThanOrEqual(assetBytes, Self.expectedAssetMaxBytes)
        XCTAssertTrue(
            modes.contains("audio"),
            "UITests bundle Info.plist 的 UIBackgroundModes 必须含 audio，实际 \(modes)"
        )
    }

    func testRunnerPlaysAndNoneIsSilent() {
        var evidence: [String: Any] = [
            "test": "testRunnerPlaysAndNoneIsSilent",
            "simulatorNotApplicable": Self.simulatorNotApplicable(),
        ]

        // 正例：runner 策略创建并起播合成循环音。
        let runnerSource = MusicStrategy.runner.makeRunnerSource()
        XCTAssertNotNil(runnerSource, "runner 策略必须创建自播音源")
        let runnerStarted = runnerSource?.start() ?? false
        evidence["runner"] = runnerSource?.evidence() ?? [:]
        evidence["runnerStarted"] = runnerStarted
        XCTAssertTrue(runnerStarted, "runner 播放器未起播")
        XCTAssertEqual(runnerSource?.isPlaying, true, "runner 播放器起播后 isPlaying 应为 true")
        XCTAssertEqual(runnerSource?.hasPlayer, true)
        let isPlayingBeforeStop = runnerSource?.isPlaying ?? false
        runnerSource?.stop()
        evidence["runnerIsPlayingBeforeStop"] = isPlayingBeforeStop
        XCTAssertEqual(runnerSource?.isPlaying, false, "stop 后 isPlaying 应为 false")

        // 负例：none 策略不创建任何播放器（负对照语义）。
        let noneSource = MusicStrategy.none.makeRunnerSource()
        XCTAssertNil(noneSource, "none 策略不得创建播放器")
        evidence["none"] = [
            "strategy": MusicStrategy.none.rawValue,
            "hasPlayer": noneSource?.hasPlayer ?? false,
            "playerStarted": noneSource != nil,
            "isPlaying": noneSource?.isPlaying ?? false,
        ]
        XCTAssertEqual(noneSource?.hasPlayer ?? false, false)
        XCTAssertEqual(noneSource?.isPlaying ?? false, false)

        // app 策略由 XCTest 侧启动外部 App，本 runner 不自建播放器。
        XCTAssertNil(MusicStrategy.app.makeRunnerSource(), "app 策略不由 runner 创建自播音源")

        attachJSON(evidence, name: "music-source-selfcheck-runner.json")
    }

    /// 模拟器诚实能力声明：这些 app 侧语义只能真机断言，此处不记 pass、不写 true。
    private static func simulatorNotApplicable() -> [String: Any] {
        let reason = "模拟器音频栈无真实他路音频/duck，真机可跑"
        return [
            "isOtherAudioPlayingAttribution": [
                "status": "not-applicable",
                "reason": reason,
            ],
            "duckOthersSemantics": [
                "status": "not-applicable",
                "reason": reason,
            ],
            "duckRevoked": [
                "status": "not-applicable",
                "reason": reason,
            ],
            "sessionDeactivated": [
                "status": "not-applicable",
                "reason": reason,
            ],
        ]
    }

    private func attachJSON(_ payload: [String: Any], name: String) {
        let data: Data
        if JSONSerialization.isValidJSONObject(payload),
           let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            data = encoded
        } else {
            data = Data("{\"error\":\"unserializable\"}".utf8)
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
