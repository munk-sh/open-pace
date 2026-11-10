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

    // ac-deactivate-option / ac-commit-after-platform-success

    /// 改写：`deactivate()` 只做纯动作推导（`state` 不变），提交由 `commitDeactivation()` 承担。
    func testDeactivateCarriesNotifyOthersOption() {
        var coordinator = AudioSessionCoordinator()
        _ = coordinator.activate()

        XCTAssertEqual(
            coordinator.deactivate(),
            .deactivate(options: [AudioCategoryOption.notifyOthersOnDeactivation])
        )
        XCTAssertEqual(coordinator.state, .active, "纯动作推导不得改变状态")

        coordinator.commitDeactivation()
        XCTAssertEqual(coordinator.state, .inactive)

        XCTAssertEqual(coordinator.deactivate(), .none)
        XCTAssertEqual(coordinator.state, .inactive)
    }

    /// ac-commit-after-platform-success：`deactivate()` 对非 `.active` 状态只返回 `.none` 且不改状态。
    func testDeactivateDerivesActionWithoutCommittingState() {
        var interrupted = AudioSessionCoordinator()
        _ = interrupted.activate()
        _ = interrupted.interruptionBegan()
        XCTAssertEqual(interrupted.deactivate(), .none)
        XCTAssertEqual(interrupted.state, .interrupted)

        var inactive = AudioSessionCoordinator()
        XCTAssertEqual(inactive.deactivate(), .none)
        XCTAssertEqual(inactive.state, .inactive)
    }

    /// commitDeactivation 只在 `.active` 生效，且是纯状态提交（不产生动作）。
    func testCommitDeactivationOnlyAppliesFromActive() {
        var active = AudioSessionCoordinator()
        _ = active.activate()
        active.commitDeactivation()
        XCTAssertEqual(active.state, .inactive)

        var interrupted = AudioSessionCoordinator()
        _ = interrupted.activate()
        _ = interrupted.interruptionBegan()
        interrupted.commitDeactivation()
        XCTAssertEqual(interrupted.state, .interrupted)

        var inactive = AudioSessionCoordinator()
        inactive.commitDeactivation()
        XCTAssertEqual(inactive.state, .inactive)
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
