import XCTest
import PurePaceRunCore
@testable import PurePace

/// 只断言展示决策：VM / 状态机转移由 `RunSessionContractTests` 覆盖，这里不重复。
final class RunInteractionPlanTests: XCTestCase {
    private let sampleMetrics = RunInteractionPlan.Metrics(
        distance: "1.23",
        elapsed: "00:12",
        currentPace: "5:00",
        averagePace: "5:10",
        splitCount: "1"
    )

    private struct DisplayState {
        let name: String
        let plan: RunInteractionPlan
        let expectedPrimary: RunInteractionPlan.Action
    }

    private func makePlan(
        state: RunSessionState,
        isCountingDown: Bool = false,
        countdownText: String? = nil,
        didSave: Bool = false,
        hasError: Bool = false,
        hasDecisionError: Bool = false,
        readiness: RunLocationReadiness = .ready,
        hasBackgroundDegradation: Bool = false,
        metrics: RunInteractionPlan.Metrics? = nil,
        reduceMotion: Bool = false
    ) -> RunInteractionPlan {
        RunInteractionPlan(
            state: state,
            isCountingDown: isCountingDown,
            countdownText: countdownText,
            didSave: didSave,
            hasError: hasError,
            hasDecisionError: hasDecisionError,
            readiness: readiness,
            hasBackgroundDegradation: hasBackgroundDegradation,
            metrics: metrics ?? sampleMetrics,
            reduceMotion: reduceMotion
        )
    }

    /// 穷举 6 个展示状态，逐态给出唯一主操作期望。
    private func displayStates(reduceMotion: Bool) -> [DisplayState] {
        [
            DisplayState(
                name: "ready idle",
                plan: makePlan(state: .ready, reduceMotion: reduceMotion),
                expectedPrimary: .start
            ),
            DisplayState(
                name: "ready countdown",
                plan: makePlan(
                    state: .ready,
                    isCountingDown: true,
                    countdownText: "3",
                    reduceMotion: reduceMotion
                ),
                expectedPrimary: .cancelCountdown
            ),
            DisplayState(
                name: "running",
                plan: makePlan(state: .running, reduceMotion: reduceMotion),
                expectedPrimary: .pause
            ),
            DisplayState(
                name: "paused",
                plan: makePlan(state: .paused, reduceMotion: reduceMotion),
                expectedPrimary: .resume
            ),
            DisplayState(
                name: "finished pending",
                plan: makePlan(state: .finished, reduceMotion: reduceMotion),
                expectedPrimary: .save
            ),
            DisplayState(
                name: "finished saved",
                plan: makePlan(state: .finished, didSave: true, reduceMotion: reduceMotion),
                expectedPrimary: .viewHistory
            )
        ]
    }

    // MARK: - ac-plan-single-primary

    func testEveryDisplayStateHasExactlyOnePrimaryAction() {
        for reduceMotion in [false, true] {
            for state in displayStates(reduceMotion: reduceMotion) {
                let primaries = state.plan.items.filter { $0.emphasis == .primary }
                XCTAssertEqual(
                    primaries.count,
                    1,
                    "\(state.name) 必须恰有一个 primary（reduceMotion=\(reduceMotion)）"
                )
                XCTAssertEqual(
                    primaries.first?.action,
                    state.expectedPrimary,
                    "\(state.name) 的 primary 动作不符（reduceMotion=\(reduceMotion)）"
                )
            }
        }
    }

    func testCountdownPrimaryIsNotSecondary() {
        let plan = makePlan(state: .ready, isCountingDown: true, countdownText: "3")
        XCTAssertEqual(plan.items, [.init(action: .cancelCountdown, emphasis: .primary)])
    }

    // MARK: - ac-plan-no-dead-end

    func testEveryDisplayStateHasAnExitAction() {
        let exitActions: Set<RunInteractionPlan.Action> = [
            .start, .cancelCountdown, .pause, .resume, .finish, .save, .discard, .viewHistory
        ]
        for reduceMotion in [false, true] {
            for state in displayStates(reduceMotion: reduceMotion) {
                XCTAssertFalse(state.plan.items.isEmpty, "\(state.name) 不能只有提示没有动作")
                XCTAssertTrue(
                    state.plan.items.contains { exitActions.contains($0.action) },
                    "\(state.name) 至少要有能离开当前态的动作"
                )
            }
        }
    }

    // MARK: - ac-plan-destructive-secondary

    func testDestructiveActionsStaySecondary() {
        let running = makePlan(state: .running)
        let paused = makePlan(state: .paused)
        let pending = makePlan(state: .finished)

        for plan in [running, paused] {
            let finish = plan.items.first { $0.action == .finish }
            XCTAssertEqual(finish?.emphasis, .secondary)
            let primary = plan.items.first { $0.emphasis == .primary }
            XCTAssertNotEqual(primary?.action, .finish)
        }

        let discard = pending.items.first { $0.action == .discard }
        let save = pending.items.first { $0.action == .save }
        XCTAssertEqual(discard?.emphasis, .secondary)
        XCTAssertEqual(save?.emphasis, .primary)
        XCTAssertNotEqual(discard?.action, save?.action)
        XCTAssertEqual(pending.items.count, 2)
    }

    // MARK: - ac-countdown-visible-metrics

    func testCountdownKeepsMetricsAndExposesReadoutSeparately() {
        let idle = makePlan(state: .ready)
        let counting = makePlan(state: .ready, isCountingDown: true, countdownText: "3")

        XCTAssertNil(idle.countdownText)
        XCTAssertEqual(counting.countdownText, "3")
        XCTAssertTrue(counting.showsMetrics)
        XCTAssertEqual(counting.metrics, idle.metrics)
        XCTAssertEqual(counting.metrics, sampleMetrics)

        let metrics = counting.metrics
        for value in [
            metrics.distance, metrics.elapsed, metrics.currentPace,
            metrics.averagePace, metrics.splitCount
        ] {
            XCTAssertFalse(value.isEmpty)
        }
    }

    // MARK: - ac-notice-priority

    func testNoticePriorityPrefersErrorThenDecisionThenLocationThenBackground() {
        let denied = RunLocationReadiness.permissionDenied

        XCTAssertEqual(
            makePlan(
                state: .finished,
                hasError: true,
                hasDecisionError: true,
                readiness: denied,
                hasBackgroundDegradation: true
            ).notice,
            .recordingError
        )
        XCTAssertEqual(
            makePlan(
                state: .finished,
                hasDecisionError: true,
                readiness: denied,
                hasBackgroundDegradation: true
            ).notice,
            .decisionFailed
        )
        XCTAssertEqual(
            makePlan(state: .ready, readiness: denied, hasBackgroundDegradation: true).notice,
            .locationDenied
        )
        XCTAssertEqual(
            makePlan(state: .ready, readiness: .unavailable, hasBackgroundDegradation: true).notice,
            .locationUnavailable
        )
        XCTAssertEqual(
            makePlan(state: .ready, readiness: .awaitingAuthorization).notice,
            .waitingAuthorization
        )
        XCTAssertEqual(
            makePlan(state: .ready, hasBackgroundDegradation: true).notice,
            .backgroundDegraded
        )
        XCTAssertNil(makePlan(state: .ready).notice)
    }

    func testSaveFailureKeepsDecisionAndMetrics() {
        let plan = makePlan(state: .finished, hasDecisionError: true)

        XCTAssertEqual(plan.notice, .decisionFailed)
        XCTAssertEqual(plan.items, [
            .init(action: .save, emphasis: .primary),
            .init(action: .discard, emphasis: .secondary)
        ])
        XCTAssertEqual(plan.metrics, sampleMetrics)
    }

    // MARK: - ac-recovery-two-actions

    func testRecoveryActionsPerReadiness() {
        let settings = makePlan(
            state: .ready,
            readiness: RunLocationReadiness(authorization: .denied)
        )
        let retry = makePlan(
            state: .ready,
            readiness: RunLocationReadiness(authorization: .restricted)
        )
        let authorizedWhenInUse = makePlan(
            state: .ready,
            readiness: RunLocationReadiness(authorization: .authorizedWhenInUse)
        )
        let authorizedAlways = makePlan(
            state: .ready,
            readiness: RunLocationReadiness(authorization: .authorizedAlways)
        )

        XCTAssertEqual(settings.recovery, .openSettings)
        XCTAssertEqual(settings.notice, .locationDenied)
        XCTAssertEqual(retry.recovery, .retryLocation)
        XCTAssertEqual(retry.notice, .locationUnavailable)
        XCTAssertNotEqual(settings.recovery, retry.recovery)
        XCTAssertNil(authorizedWhenInUse.recovery)
        XCTAssertNil(authorizedAlways.recovery)
    }

    func testRecoveryOnlyAppearsInIdleReadyState() {
        let denied = RunLocationReadiness.permissionDenied

        XCTAssertNil(makePlan(state: .ready, isCountingDown: true, readiness: denied).recovery)
        XCTAssertNil(makePlan(state: .running, readiness: denied).recovery)
        XCTAssertNil(makePlan(state: .paused, readiness: denied).recovery)
        XCTAssertNil(makePlan(state: .finished, readiness: denied).recovery)
        XCTAssertNil(makePlan(state: .finished, didSave: true, readiness: denied).recovery)
        XCTAssertEqual(makePlan(state: .ready, readiness: denied).recovery, .openSettings)
    }

    // MARK: - ac-motion-token-reduce-motion

    func testTransitionDurationFollowsMotionTokens() {
        for reduceMotion in [false, true] {
            for state in displayStates(reduceMotion: reduceMotion) {
                let expected = DesignTokens.Motion.duration(
                    DesignTokens.Motion.durationState,
                    reduceMotion: reduceMotion
                )
                XCTAssertEqual(state.plan.transitionDuration, expected)
            }
        }

        let animated = makePlan(state: .ready, reduceMotion: false)
        XCTAssertEqual(animated.transitionDuration, DesignTokens.Motion.durationState)
        XCTAssertNotEqual(animated.transitionDuration, DesignTokens.Motion.reducedMotionDuration)

        let reduced = makePlan(state: .ready, reduceMotion: true)
        XCTAssertEqual(reduced.transitionDuration, DesignTokens.Motion.reducedMotionDuration)
        XCTAssertEqual(reduced.transitionDuration, 0)
    }
}
