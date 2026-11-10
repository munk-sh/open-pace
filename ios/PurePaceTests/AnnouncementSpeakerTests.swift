import AVFoundation
import PurePaceRunCore
import XCTest
@testable import PurePace

/// 记录下发到平台层的调用序列，替代真实 `AVAudioSession`。
private final class AudioSessionSpy: AudioSessionControlling {
    struct CategoryCall: Equatable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    struct ActivationCall: Equatable {
        let active: Bool
        let options: AVAudioSession.SetActiveOptions
    }

    private(set) var categoryCalls: [CategoryCall] = []
    private(set) var activationCalls: [ActivationCall] = []

    var category: AVAudioSession.Category = .ambient
    var mode: AVAudioSession.Mode = .default
    var categoryOptions: AVAudioSession.CategoryOptions = []
    var isOtherAudioPlaying: Bool = false
    var secondaryAudioShouldBeSilencedHint: Bool = false
    /// 仅停用调用（`active == false`）抛错的注入点，用于复现真机上的迟到失败分支。
    var deactivationError: Error?

    var activations: [ActivationCall] { activationCalls.filter(\.active) }
    var deactivations: [ActivationCall] { activationCalls.filter { !$0.active } }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        categoryCalls.append(CategoryCall(category: category, mode: mode, options: options))
        self.category = category
        self.mode = mode
        self.categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activationCalls.append(ActivationCall(active: active, options: options))
        if !active, let deactivationError {
            throw deactivationError
        }
    }
}

private enum InjectedAudioError: Error {
    case setActiveFalseFailed
}

private final class SpeechSynthesizerSpy: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    private(set) var startedCount = 0
    private var onStart: (() -> Void)?
    private var onFinish: ((Bool) -> Void)?

    func speak(
        _ text: String,
        onStart: @escaping () -> Void,
        onFinish: @escaping (_ cancelled: Bool) -> Void
    ) {
        spoken.append(text)
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func start() {
        startedCount += 1
        let callback = onStart
        onStart = nil
        callback?()
    }

    func finish(cancelled: Bool = false) {
        let callback = onFinish
        onFinish = nil
        callback?(cancelled)
    }
}

final class AnnouncementSpeakerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOneSpeakPerDeliveredCommandWithKilometerIndex() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)
        let command = makeCommand(splitIndex: 1)

        speaker.speak(command)
        speaker.speak(command)

        XCTAssertEqual(synthesizer.spoken.count, 1)
        XCTAssertTrue(synthesizer.spoken[0].contains("第 1 公里"))
        XCTAssertTrue(synthesizer.spoken[0].contains("05:30"))
    }

    func testSessionSequenceActivatesSpeaksThenDeactivatesOnFinish() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)

        speaker.speak(makeCommand(splitIndex: 2))

        XCTAssertEqual(
            session.categoryCalls,
            [
                AudioSessionSpy.CategoryCall(
                    category: .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers, .mixWithOthers]
                )
            ]
        )
        XCTAssertEqual(session.activations.count, 1)
        XCTAssertEqual(session.activations.first?.options, [])
        XCTAssertEqual(synthesizer.spoken.count, 1)
        XCTAssertTrue(session.deactivations.isEmpty)

        synthesizer.finish()

        XCTAssertEqual(session.deactivations.count, 1)
        XCTAssertEqual(session.deactivations.first?.options, [.notifyOthersOnDeactivation])
    }

    func testCancelledSpeechStillDeactivatesOnce() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)

        speaker.speak(makeCommand(splitIndex: 3))
        synthesizer.finish(cancelled: true)
        synthesizer.finish(cancelled: true)

        XCTAssertEqual(session.activations.count, 1)
        XCTAssertEqual(session.deactivations.count, 1)
    }

    func testNoCommandProducesNoAudioSessionCalls() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        _ = makeSpeaker(session: session, synthesizer: synthesizer)

        XCTAssertTrue(session.categoryCalls.isEmpty)
        XCTAssertTrue(session.activationCalls.isEmpty)
        XCTAssertTrue(synthesizer.spoken.isEmpty)
    }

    func testDistinctSplitIndexesSpeakAgain() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.finish()
        speaker.speak(makeCommand(splitIndex: 2))

        XCTAssertEqual(synthesizer.spoken.count, 2)
        XCTAssertTrue(synthesizer.spoken[1].contains("第 2 公里"))
    }

    // MARK: - 音频遥测自证

    func testTelemetryRecordsDuckContractStartFinishAndDeactivation() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer, telemetry: recorder)

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(synthesizer.startedCount, 1, "起始回调必须被调用")
        let entries = recorder.snapshot()
        XCTAssertEqual(entries.count, 1)
        guard let entry = entries.first else { return }
        XCTAssertEqual(entry.splitIndex, 1)
        XCTAssertTrue(entry.text.contains("第 1 公里"))
        XCTAssertEqual(entry.category, "playback")
        XCTAssertEqual(entry.mode, "spokenAudio")
        XCTAssertTrue(entry.categoryOptions.contains("duckOthers"))
        XCTAssertTrue(entry.sessionActivated, "起播时下发了会话激活")
        XCTAssertTrue(entry.sessionDeactivated, "结束后恰好一次会话停用")
        XCTAssertTrue(entry.duckRevoked, "结束后 duck 撤销")
        XCTAssertFalse(entry.cancelled)
        XCTAssertNotNil(entry.finishedAt)
        XCTAssertLessThanOrEqual(entry.startedAt, entry.finishedAt ?? .greatestFiniteMagnitude)
    }

    func testTelemetryMarksCancelledButStillDeactivates() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer, telemetry: recorder)

        speaker.speak(makeCommand(splitIndex: 2))
        synthesizer.start()
        synthesizer.finish(cancelled: true)

        let entries = recorder.snapshot()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.cancelled, true)
        XCTAssertEqual(entries.first?.sessionDeactivated, true)
        XCTAssertEqual(session.deactivations.count, 1)
    }

    // MARK: - 停用边界：true / 中断 / 抛错三分支

    /// 机制① 证伪基线：协调器保持 `.active` 时结束播报，派生值唯一来自真实平台调用。
    func testActiveSessionDeactivationWritesTrueDerivationsAndSinglePlatformCall() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let adapter = AudioSessionAdapter(controller: session, observesInterruptions: false)
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder
        )

        speaker.speak(makeCommand(splitIndex: 1))
        XCTAssertEqual(adapter.state, .active)
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(adapter.state, .inactive)
        XCTAssertEqual(session.activations.count, 1)
        XCTAssertEqual(session.deactivations.count, 1)
        XCTAssertEqual(session.deactivations.first?.options, [.notifyOthersOnDeactivation])
        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, false],
            "didFinish 后必须恰好下发一次 setActive(false)"
        )

        guard let entry = recorder.snapshot().first else {
            return XCTFail("缺少播报遥测条目")
        }
        XCTAssertTrue(entry.sessionActivated)
        XCTAssertTrue(entry.sessionDeactivated)
        XCTAssertTrue(entry.duckRevoked)
        XCTAssertFalse(entry.cancelled)
        XCTAssertNotNil(entry.finishedAt)
    }

    /// 机制② 复现：播报中出现 interruption began，didFinish 时协调器已非 `.active`，
    /// `deactivate()` 返回 `.none`，因此没有平台停用调用、两个派生字段均为 false；
    /// 随后 `shouldResume == false` 让状态回到 `.inactive`，下一次播报重新激活。
    func testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let adapter = AudioSessionAdapter(controller: session, observesInterruptions: false)
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder
        )

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.start()
        adapter.handleInterruption(.began)
        XCTAssertEqual(adapter.state, .interrupted)

        synthesizer.finish()

        XCTAssertEqual(adapter.state, .interrupted, "非 active 状态下 deactivate 不改变状态")
        XCTAssertTrue(session.deactivations.isEmpty, "协调器非 active 时不得下发 setActive(false)")

        guard let first = recorder.snapshot().first else {
            return XCTFail("缺少首条播报遥测条目")
        }
        XCTAssertTrue(first.sessionActivated)
        XCTAssertFalse(first.sessionDeactivated)
        XCTAssertFalse(first.duckRevoked)
        XCTAssertFalse(first.cancelled)
        XCTAssertNotNil(first.finishedAt)

        adapter.handleInterruption(.ended(shouldResume: false))
        XCTAssertEqual(adapter.state, .inactive)
        XCTAssertTrue(session.deactivations.isEmpty)

        speaker.speak(makeCommand(splitIndex: 2))
        XCTAssertEqual(session.activations.count, 2, "下一次播报必须重新下发激活")
        XCTAssertEqual(adapter.state, .active)
        guard let second = recorder.snapshot().last else {
            return XCTFail("缺少第二条播报遥测条目")
        }
        XCTAssertTrue(second.sessionActivated)
    }

    /// 机制③ 复现：`setActive(false)` 抛出后 `speak` 的 catch 吞错，协调器状态已先转
    /// `.inactive`；落盘指纹恰为真机观测到的 `sessionActivated=true` +
    /// `sessionDeactivated=false` + `finishedAt != nil` + `cancelled=false`。
    func testThrownDeactivationProducesObservedFalseFingerprintAndNextActivation() {
        let session = AudioSessionSpy()
        session.deactivationError = InjectedAudioError.setActiveFalseFailed
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let adapter = AudioSessionAdapter(controller: session, observesInterruptions: false)
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder
        )

        speaker.speak(makeCommand(splitIndex: 1))
        XCTAssertEqual(adapter.state, .active)
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(session.deactivations.count, 1, "平台停用调用已发起但抛出")
        XCTAssertEqual(adapter.state, .inactive, "deactivate 先改状态、后执行平台调用")

        guard let first = recorder.snapshot().first else {
            return XCTFail("缺少首条播报遥测条目")
        }
        XCTAssertTrue(first.sessionActivated)
        XCTAssertFalse(first.sessionDeactivated)
        XCTAssertFalse(first.duckRevoked)
        XCTAssertFalse(first.cancelled)
        XCTAssertNotNil(first.finishedAt)

        speaker.speak(makeCommand(splitIndex: 2))
        XCTAssertEqual(session.activations.count, 2, "状态已转 inactive，下一次播报仍能重新激活")
        XCTAssertEqual(adapter.state, .active)
        guard let second = recorder.snapshot().last else {
            return XCTFail("缺少第二条播报遥测条目")
        }
        XCTAssertTrue(second.sessionActivated)
    }

    /// ac-derived-fields-provenance：音频环境布尔在 `beginAnnouncement` 之后实时读取，
    /// 注入两组相反值都应原样落入遥测，证明未被写死或复用旧快照。
    func testAnnouncementContextPassesThroughInjectedAudioEnvironmentBooleans() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer, telemetry: recorder)

        session.isOtherAudioPlaying = true
        session.secondaryAudioShouldBeSilencedHint = true
        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.finish()

        session.isOtherAudioPlaying = false
        session.secondaryAudioShouldBeSilencedHint = false
        speaker.speak(makeCommand(splitIndex: 2))
        synthesizer.finish()

        let entries = recorder.snapshot()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].isOtherAudioPlaying, true)
        XCTAssertEqual(entries[0].secondaryAudioShouldBeSilencedHint, true)
        XCTAssertEqual(entries[1].isOtherAudioPlaying, false)
        XCTAssertEqual(entries[1].secondaryAudioShouldBeSilencedHint, false)
    }

    // MARK: - helpers

    private func makeSpeaker(
        session: AudioSessionSpy,
        synthesizer: SpeechSynthesizerSpy,
        telemetry: AnnouncementTelemetryRecording? = nil,
        now: @escaping () -> Date = { Date() }
    ) -> SpeechAnnouncementSpeaker {
        makeSpeaker(
            adapter: AudioSessionAdapter(controller: session, observesInterruptions: false),
            synthesizer: synthesizer,
            telemetry: telemetry,
            now: now
        )
    }

    private func makeSpeaker(
        adapter: AudioSessionAdapter,
        synthesizer: SpeechSynthesizerSpy,
        telemetry: AnnouncementTelemetryRecording? = nil,
        now: @escaping () -> Date = { Date() }
    ) -> SpeechAnnouncementSpeaker {
        SpeechAnnouncementSpeaker(
            audioSession: adapter,
            synthesizer: synthesizer,
            telemetry: telemetry,
            now: now
        )
    }

    private func makeCommand(splitIndex: Int) -> AnnouncementCommand {
        AnnouncementCommand(
            trigger: .kilometerCompleted,
            splitIndex: splitIndex,
            distance: RunDistance(meters: Double(splitIndex) * 1000)!,
            pace: RunPace(secondsPerKilometer: 330)!,
            elapsed: TimeInterval(splitIndex) * 330
        )!
    }
}
