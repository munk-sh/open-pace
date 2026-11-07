import XCTest
@testable import PurePaceRunCore

final class SessionMachineTests: XCTestCase {
    private let legalTransitions: [(RunSessionState, RunSessionState)] = [
        (.ready, .running),
        (.running, .paused),
        (.running, .finished),
        (.paused, .running),
        (.paused, .finished)
    ]

    private func isLegal(from: RunSessionState, to: RunSessionState) -> Bool {
        legalTransitions.contains { $0.0 == from && $0.1 == to }
    }

    private func makeCheckpoint(
        state: RunSessionState,
        meters: Double = 0,
        elapsed: TimeInterval = 0,
        splits: [RunSplit] = []
    ) -> RunCheckpoint {
        RunCheckpoint(
            state: state,
            completedDistance: RunDistance(meters: meters)!,
            elapsed: elapsed,
            splits: splits,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )!
    }

    func testLegalTransitionsSucceedAndLandCorrectly() {
        XCTAssertEqual(legalTransitions.count, 5)
        for (from, to) in legalTransitions {
            var machine = RunSessionMachine(state: from)
            XCTAssertTrue(machine.canTransition(to: to))
            XCTAssertNoThrow(try machine.transition(to: to))
            XCTAssertEqual(machine.state, to)
        }
    }

    func testCanTransitionMatchesTransitionForAllSixteenCombinations() {
        var legalCount = 0
        for from in RunSessionState.allCases {
            for to in RunSessionState.allCases {
                let expected = isLegal(from: from, to: to)
                if expected { legalCount += 1 }
                var machine = RunSessionMachine(state: from)
                XCTAssertEqual(machine.canTransition(to: to), expected, "canTransition \(from)→\(to)")

                if expected {
                    XCTAssertNoThrow(try machine.transition(to: to))
                    XCTAssertEqual(machine.state, to)
                } else {
                    XCTAssertThrowsError(try machine.transition(to: to)) { error in
                        guard case let RunCoreError.invalidStateTransition(errorFrom, errorTo) = error else {
                            return XCTFail("期望 invalidStateTransition，实际 \(error)")
                        }
                        XCTAssertEqual(errorFrom, from)
                        XCTAssertEqual(errorTo, to)
                    }
                    XCTAssertEqual(machine.state, from, "非法迁移后状态必须保持不变")
                }
            }
        }
        XCTAssertEqual(legalCount, 5)
    }

    func testIllegalTransitionsRejectedWithStateUnchanged() {
        var rejected = 0
        for from in RunSessionState.allCases {
            for to in RunSessionState.allCases where !isLegal(from: from, to: to) {
                rejected += 1
                var machine = RunSessionMachine(state: from)
                XCTAssertThrowsError(try machine.transition(to: to)) { error in
                    guard case let RunCoreError.invalidStateTransition(errorFrom, errorTo) = error else {
                        return XCTFail("期望 invalidStateTransition，实际 \(error)")
                    }
                    XCTAssertEqual(errorFrom, from)
                    XCTAssertEqual(errorTo, to)
                }
                XCTAssertEqual(machine.state, from)
            }
        }
        XCTAssertEqual(rejected, 11)
    }

    func testEventEntrypointsOnlyAcceptDocumentedStates() {
        var machine = RunSessionMachine(state: .ready)
        XCTAssertNoThrow(try machine.start())
        XCTAssertEqual(machine.state, .running)

        XCTAssertThrowsError(try machine.start())
        XCTAssertEqual(machine.state, .running)

        XCTAssertNoThrow(try machine.pause())
        XCTAssertEqual(machine.state, .paused)

        XCTAssertThrowsError(try machine.pause())
        XCTAssertEqual(machine.state, .paused)

        XCTAssertNoThrow(try machine.resume())
        XCTAssertEqual(machine.state, .running)

        XCTAssertThrowsError(try machine.resume())
        XCTAssertEqual(machine.state, .running)

        XCTAssertNoThrow(try machine.finish())
        XCTAssertEqual(machine.state, .finished)

        XCTAssertThrowsError(try machine.finish())
        XCTAssertThrowsError(try machine.start())
        XCTAssertThrowsError(try machine.pause())
        XCTAssertThrowsError(try machine.resume())
        XCTAssertEqual(machine.state, .finished)
    }

    func testStartRejectedFromPausedEvenThoughMatrixPairIsLegal() {
        var machine = RunSessionMachine(state: .paused)
        XCTAssertThrowsError(try machine.start()) { error in
            guard case let RunCoreError.invalidStateTransition(from, to) = error else {
                return XCTFail("期望 invalidStateTransition，实际 \(error)")
            }
            XCTAssertEqual(from, .paused)
            XCTAssertEqual(to, .running)
        }
        XCTAssertEqual(machine.state, .paused)
    }

    func testRecoveryFromRunningAndPausedLandsOnPaused() {
        for original in [RunSessionState.running, .paused] {
            let split = RunSplit(index: 1, distance: RunDistance(meters: 1000)!, duration: 360)!
            let checkpoint = makeCheckpoint(state: original, meters: 1000, elapsed: 360, splits: [split])
            var machine = RunSessionMachine(restoring: checkpoint)
            XCTAssertEqual(machine.state, .paused)
            XCTAssertEqual(machine.restoredCheckpoint, checkpoint)
            XCTAssertNoThrow(try machine.resume())
            XCTAssertEqual(machine.state, .running)
        }
    }

    func testRecoveryPreservesCheckpointDataUntouched() {
        let splits = [
            RunSplit(index: 1, distance: RunDistance(meters: 1000)!, duration: 300)!,
            RunSplit(index: 2, distance: RunDistance(meters: 1000)!, duration: 310)!
        ]
        let checkpoint = makeCheckpoint(state: .running, meters: 2000, elapsed: 610, splits: splits)
        let machine = RunSessionMachine(restoring: checkpoint)
        XCTAssertEqual(machine.restoredCheckpoint?.completedDistance, checkpoint.completedDistance)
        XCTAssertEqual(machine.restoredCheckpoint?.elapsed, checkpoint.elapsed)
        XCTAssertEqual(machine.restoredCheckpoint?.splits, checkpoint.splits)
    }

    func testRecoveryTerminalAndReady() {
        var finished = RunSessionMachine(restoring: makeCheckpoint(state: .finished, meters: 5000, elapsed: 1500))
        XCTAssertEqual(finished.state, .finished)
        XCTAssertThrowsError(try finished.resume())
        XCTAssertThrowsError(try finished.start())
        XCTAssertThrowsError(try finished.pause())
        XCTAssertEqual(finished.state, .finished)

        var ready = RunSessionMachine(restoring: makeCheckpoint(state: .ready))
        XCTAssertEqual(ready.state, .ready)
        XCTAssertNoThrow(try ready.start())
        XCTAssertEqual(ready.state, .running)
    }
}
