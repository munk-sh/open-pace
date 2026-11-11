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
            .start, .cancelCountdown, .pause, .resume, .finish, .save, .discardRequest, .discard, .viewHistory
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

    /// 旧口径（finish=secondary / warning 描边）已废弃：finish 归主操作 accent 族，
    /// 同屏唯一填充主操作仍是 pause/resume；破坏性 discard 只在确认层且为 danger。
    func testDestructiveActionsStaySecondary() {
        let running = makePlan(state: .running)
        let paused = makePlan(state: .paused)
        let pending = makePlan(state: .finished)

        for plan in [running, paused] {
            let finish = plan.items.first { $0.action == .finish }
            XCTAssertEqual(finish?.emphasis, .accent)
            XCTAssertEqual(finish?.tint, .accent)
            XCTAssertEqual(finish?.style, .accentOutline)
            XCTAssertFalse(finish?.fillsWithTint ?? true)
            let filled = plan.items.filter { $0.fillsWithTint }
            XCTAssertEqual(filled.count, 1)
            XCTAssertTrue(filled.first?.action == .pause || filled.first?.action == .resume)
            XCTAssertNotEqual(filled.first?.action, .finish)
        }

        let entry = pending.items.first { $0.action == .discardRequest }
        let save = pending.items.first { $0.action == .save }
        XCTAssertEqual(entry?.emphasis, .secondary)
        XCTAssertEqual(entry?.tint, .secondary)
        XCTAssertEqual(save?.emphasis, .primary)
        XCTAssertEqual(save?.tint, .accent)
        XCTAssertNotEqual(entry?.action, save?.action)
        XCTAssertEqual(pending.items.count, 2)
        XCTAssertNil(pending.items.first { $0.action == .discard }, "破坏性 discard 不得直接出现在待保存屏")

        let confirmation = pending.discardConfirmation
        XCTAssertEqual(confirmation?.cancel.emphasis, .secondary)
        XCTAssertEqual(confirmation?.confirm.action, .discard)
        XCTAssertEqual(confirmation?.confirm.emphasis, .danger)
        XCTAssertEqual(confirmation?.confirm.tint, .danger)
        XCTAssertFalse(confirmation?.confirm.fillsWithTint ?? true)
        XCTAssertNil(running.discardConfirmation)
        XCTAssertNil(paused.discardConfirmation)

        // 旧口径反例：finish 若回退 secondary，tint 不再是 accent，必须判红。
        let legacyFinish = RunInteractionPlan.Item(action: .finish, emphasis: .secondary)
        XCTAssertNotEqual(legacyFinish.tint, .accent)
        XCTAssertNotEqual(legacyFinish.style, .accentOutline)
    }

    // MARK: - ac-primary-family-accent

    func testPrimaryActionFamilyResolvesAccent() {
        let plans: [(String, RunInteractionPlan, [RunInteractionPlan.Action])] = [
            ("ready", makePlan(state: .ready), [.start]),
            ("running", makePlan(state: .running), [.pause, .finish]),
            ("paused", makePlan(state: .paused), [.resume, .finish]),
            ("finished pending", makePlan(state: .finished), [.save])
        ]
        for (name, plan, expected) in plans {
            for action in expected {
                let item = plan.items.first { $0.action == action }
                XCTAssertEqual(item?.tint, .accent, "\(name).\(action) 必须解析为 accent")
                XCTAssertNotEqual(item?.tint, .warning, "\(name).\(action) 不得解析为 warning")
                XCTAssertNotEqual(item?.tint, .secondary, "\(name).\(action) 不得解析为 secondary")
            }
        }
    }

    // MARK: - ac-warning-inline-only

    func testWarningOnlyServesInlineNotices() {
        let notices: [RunInteractionPlan.Notice] = [
            .recordingError, .decisionFailed, .locationDenied,
            .locationUnavailable, .waitingAuthorization, .backgroundDegraded
        ]
        for notice in notices {
            XCTAssertEqual(notice.tint, .warning, "\(notice) 必须只解析为 warning 内联提示")
        }

        for reduceMotion in [false, true] {
            for state in displayStates(reduceMotion: reduceMotion) {
                for item in state.plan.items {
                    XCTAssertNotEqual(item.tint, .warning, "\(state.name).\(item.action) 不得解析为 warning")
                }
                XCTAssertNotEqual(state.plan.heroTint, .warning, "\(state.name) hero 主值色不得为 warning")
            }
        }

        // hero 主值：记录中 / 暂停取 accent（暂停不切 warning），已保存取 success，未开始中性 primary。
        XCTAssertEqual(makePlan(state: .running).heroTint, .accent)
        XCTAssertEqual(makePlan(state: .paused).heroTint, .accent)
        XCTAssertEqual(makePlan(state: .ready).heroTint, .primary)
        XCTAssertEqual(makePlan(state: .finished, didSave: true).heroTint, .success)
        // 反例：若 hero 回退到旧 warning 口径必须判红。
        XCTAssertNotEqual(makePlan(state: .paused).heroTint, .warning)
        XCTAssertNotEqual(makePlan(state: .running).heroTint, .warning)

        // 反例：warning 填充主按钮必须判红。
        let warningFill = RunInteractionPlan.Item(action: .pause, emphasis: .primary)
        XCTAssertNotEqual(warningFill.tint, .warning)
        XCTAssertTrue(warningFill.fillsWithTint)
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
            .init(action: .discardRequest, emphasis: .secondary)
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
