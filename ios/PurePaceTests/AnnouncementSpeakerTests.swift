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
    }
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

    // MARK: - helpers

    private func makeSpeaker(
        session: AudioSessionSpy,
        synthesizer: SpeechSynthesizerSpy,
        telemetry: AnnouncementTelemetryRecording? = nil,
        now: @escaping () -> Date = { Date() }
    ) -> SpeechAnnouncementSpeaker {
        SpeechAnnouncementSpeaker(
            audioSession: AudioSessionAdapter(controller: session, observesInterruptions: false),
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
