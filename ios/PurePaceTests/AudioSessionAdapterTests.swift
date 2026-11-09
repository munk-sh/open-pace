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

final class AudioSessionAdapterTests: XCTestCase {
    private let session = AVAudioSession.sharedInstance()

    override func setUpWithError() throws {
        continueAfterFailure = false
        resetSession()
    }

    override func tearDownWithError() throws {
        resetSession()
    }

    // MARK: - ac-simulator-readback-configured

    func testApplyingDefaultConfigurationReadsBackFromRealSession() throws {
        let adapter = AudioSessionAdapter(controller: AVAudioSessionController())

        try adapter.beginAnnouncement()

        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers))
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))

        try adapter.endAnnouncement()
    }

    // MARK: - ac-deactivate-options-spy

    func testEndAnnouncementDeactivatesWithNotifyOthersExactlyOnce() throws {
        let spy = AudioSessionSpy()
        let adapter = AudioSessionAdapter(controller: spy, observesInterruptions: false)

        try adapter.beginAnnouncement()
        try adapter.endAnnouncement()
        try adapter.endAnnouncement()

        XCTAssertEqual(spy.deactivations.count, 1)
        XCTAssertEqual(spy.deactivations.first?.options, [.notifyOthersOnDeactivation])
    }

    // MARK: - ac-activation-idempotent-on-device-path

    func testRepeatedBeginAnnouncementActivatesOnce() throws {
        let spy = AudioSessionSpy()
        let adapter = AudioSessionAdapter(controller: spy, observesInterruptions: false)

        try adapter.beginAnnouncement()
        try adapter.beginAnnouncement()

        XCTAssertEqual(spy.activations.count, 1)
        XCTAssertEqual(
            spy.categoryCalls,
            [
                AudioSessionSpy.CategoryCall(
                    category: .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers, .mixWithOthers]
                )
            ]
        )
    }

    // MARK: - ac-interruption-mapping

    func testInterruptionBeganThenResumeReappliesDefaultConfiguration() throws {
        let spy = AudioSessionSpy()
        let adapter = AudioSessionAdapter(controller: spy, observesInterruptions: false)
        try adapter.beginAnnouncement()
        spy.reset()

        adapter.handleInterruption(notification: interruptionNotification(type: .began))
        XCTAssertEqual(adapter.state, .interrupted)
        XCTAssertTrue(spy.activations.isEmpty)
        XCTAssertTrue(spy.categoryCalls.isEmpty)

        adapter.handleInterruption(
            notification: interruptionNotification(type: .ended, options: [.shouldResume])
        )
        XCTAssertEqual(adapter.state, .active)
        XCTAssertEqual(
            spy.categoryCalls,
            [
                AudioSessionSpy.CategoryCall(
                    category: .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers, .mixWithOthers]
                )
            ]
        )
        XCTAssertEqual(spy.activations.count, 1)
        XCTAssertEqual(spy.activations.first?.options, [])
    }

    func testInterruptionEndedWithoutResumeReturnsToInactiveWithoutActivation() throws {
        let spy = AudioSessionSpy()
        let adapter = AudioSessionAdapter(controller: spy, observesInterruptions: false)
        try adapter.beginAnnouncement()
        spy.reset()

        adapter.handleInterruption(notification: interruptionNotification(type: .began))
        adapter.handleInterruption(notification: interruptionNotification(type: .ended))

        XCTAssertEqual(adapter.state, .inactive)
        XCTAssertTrue(spy.activations.isEmpty)
        XCTAssertTrue(spy.categoryCalls.isEmpty)
    }

    func testObservedInterruptionNotificationIsMappedByNotificationCenter() throws {
        let spy = AudioSessionSpy()
        let center = NotificationCenter()
        let adapter = AudioSessionAdapter(controller: spy, notificationCenter: center)
        try adapter.beginAnnouncement()
        spy.reset()

        center.post(interruptionNotification(type: .began))
        XCTAssertEqual(adapter.state, .interrupted)
        XCTAssertTrue(spy.activations.isEmpty)

        center.post(interruptionNotification(type: .ended, options: [.shouldResume]))
        XCTAssertEqual(adapter.state, .active)
        XCTAssertEqual(spy.activations.count, 1)
    }

    // MARK: - helpers

    private func resetSession() {
        try? session.setActive(false, options: [])
        try? session.setCategory(.ambient, mode: .default, options: [])
    }

    private func interruptionNotification(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions = []
    ) -> Notification {
        Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: type.rawValue,
                AVAudioSessionInterruptionOptionKey: options.rawValue,
            ]
        )
    }
}

private extension AudioSessionSpy {
    func reset() {
        categoryCalls.removeAll()
        activationCalls.removeAll()
    }
}
