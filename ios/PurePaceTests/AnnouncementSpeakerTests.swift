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
    private var onFinish: ((Bool) -> Void)?

    func speak(_ text: String, onFinish: @escaping (Bool) -> Void) {
        spoken.append(text)
        self.onFinish = onFinish
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

    // MARK: - helpers

    private func makeSpeaker(
        session: AudioSessionSpy,
        synthesizer: SpeechSynthesizerSpy
    ) -> SpeechAnnouncementSpeaker {
        SpeechAnnouncementSpeaker(
            audioSession: AudioSessionAdapter(controller: session, observesInterruptions: false),
            synthesizer: synthesizer
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
