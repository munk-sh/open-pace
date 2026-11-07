import XCTest
import PurePaceRunCore

final class AudioSessionCoordinatorTests: XCTestCase {
    // MARK: - ac-audiosession-settings-values

    func testDefaultAnnouncementSettingsValues() {
        let settings = AudioSessionSettings.defaultAnnouncement
        XCTAssertEqual(settings.category, .playback)
        XCTAssertEqual(settings.mode, .spokenAudio)
        XCTAssertEqual(
            settings.options,
            Set([AudioCategoryOption.duckOthers, AudioCategoryOption.mixWithOthers])
        )
        XCTAssertEqual(settings.options.count, 2)
        XCTAssertEqual(
            settings.deactivationOptions,
            Set([AudioCategoryOption.notifyOthersOnDeactivation])
        )
        XCTAssertEqual(settings.deactivationOptions.count, 1)
    }

    // MARK: - ac-audiosession-activation-idempotent

    func testActivationIsIdempotent() {
        var coordinator = AudioSessionCoordinator()
        XCTAssertEqual(coordinator.state, .inactive)

        XCTAssertEqual(coordinator.activate(), .activate(settings: .defaultAnnouncement))
        XCTAssertEqual(coordinator.state, .active)

        XCTAssertEqual(coordinator.activate(), .none)
        XCTAssertEqual(coordinator.state, .active)
    }

    // MARK: - ac-audiosession-deactivate-option

    func testDeactivateCarriesNotifyOthersOption() {
        var coordinator = AudioSessionCoordinator()
        _ = coordinator.activate()

        XCTAssertEqual(
            coordinator.deactivate(),
            .deactivate(options: [AudioCategoryOption.notifyOthersOnDeactivation])
        )
        XCTAssertEqual(coordinator.state, .inactive)

        XCTAssertEqual(coordinator.deactivate(), .none)
        XCTAssertEqual(coordinator.state, .inactive)
    }

    // MARK: - ac-audiosession-interruption-lifecycle

    func testInterruptionBeganThenResumeReactivatesWithDefaultSettings() {
        var coordinator = AudioSessionCoordinator()
        _ = coordinator.activate()

        XCTAssertEqual(coordinator.interruptionBegan(), .none)
        XCTAssertEqual(coordinator.state, .interrupted)

        XCTAssertEqual(
            coordinator.interruptionEnded(shouldResume: true),
            .activate(settings: .defaultAnnouncement)
        )
        XCTAssertEqual(coordinator.state, .active)
    }

    func testInterruptionEndedWithoutResumeStaysInactive() {
        var coordinator = AudioSessionCoordinator()
        _ = coordinator.activate()
        _ = coordinator.interruptionBegan()

        XCTAssertEqual(coordinator.interruptionEnded(shouldResume: false), .none)
        XCTAssertEqual(coordinator.state, .inactive)
    }

    func testRepeatedInterruptionBeganIsIdempotent() {
        var coordinator = AudioSessionCoordinator()
        _ = coordinator.activate()

        XCTAssertEqual(coordinator.interruptionBegan(), .none)
        XCTAssertEqual(coordinator.state, .interrupted)
        XCTAssertEqual(coordinator.interruptionBegan(), .none)
        XCTAssertEqual(coordinator.state, .interrupted)

        // 重复 began 后仍能正常恢复。
        XCTAssertEqual(
            coordinator.interruptionEnded(shouldResume: true),
            .activate(settings: .defaultAnnouncement)
        )
        XCTAssertEqual(coordinator.state, .active)
    }

    func testInterruptionEndedOutsideInterruptionIsNoop() {
        var active = AudioSessionCoordinator()
        _ = active.activate()
        XCTAssertEqual(active.interruptionEnded(shouldResume: true), .none)
        XCTAssertEqual(active.state, .active)

        var inactive = AudioSessionCoordinator()
        XCTAssertEqual(inactive.interruptionEnded(shouldResume: false), .none)
        XCTAssertEqual(inactive.state, .inactive)
    }
}
