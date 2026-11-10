import XCTest
import PurePaceRunCore

final class AnnouncementSchedulerTests: XCTestCase {
    // MARK: - Helpers

    private func makeDistance(_ meters: Double) -> RunDistance {
        guard let distance = RunDistance(meters: meters) else {
            preconditionFailure("测试距离必须合法: \(meters)")
        }
        return distance
    }

    private func makeSplit(_ index: Int, duration: TimeInterval = 300) -> RunSplit {
        guard let split = RunSplit(
            index: index,
            distance: makeDistance(1000),
            duration: duration
        ) else {
            preconditionFailure("测试分段必须合法: \(index)")
        }
        return split
    }

    private func makeUpdate(
        splits: [RunSplit],
        newly: [RunSplit],
        elapsed: TimeInterval,
        distanceMeters: Double? = nil
    ) -> RunMetricsUpdate {
        let completed = splits.count
        let metrics = RunMetrics(
            distance: makeDistance(distanceMeters ?? Double(completed) * 1000),
            elapsed: elapsed,
            averagePace: RunPace(secondsPerKilometer: 300),
            currentPace: RunPace(secondsPerKilometer: 300),
            splits: splits,
            completedKilometers: completed
        )
        return RunMetricsUpdate(metrics: metrics, newlyCompletedSplits: newly)
    }

    // MARK: - ac-announcement-exactly-once-per-km

    func testEachKilometerAnnouncedExactlyOnceInOrder() {
        var scheduler = AnnouncementScheduler()
        var splits: [RunSplit] = []
        var commands: [AnnouncementCommand] = []

        for index in 1...5 {
            let split = makeSplit(index)
            splits.append(split)
            // 每次 tick 都把**累计**公里当作 `newlyCompletedSplits`（引擎重算会重复上报），
            // 因此「去掉 lastAnnouncedSplitIndex 过滤」会让旧公里重复播报、本用例必判红。
            let emitted = scheduler.tick(
                makeUpdate(splits: splits, newly: splits, elapsed: Double(index) * 300),
                state: .running
            )
            XCTAssertEqual(emitted.count, 1)
            XCTAssertEqual(emitted.first?.trigger, .kilometerCompleted)
            XCTAssertEqual(emitted.first?.splitIndex, index)
            commands.append(contentsOf: emitted)
        }

        XCTAssertEqual(commands.map(\.splitIndex), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(commands.map(\.splitIndex)).count, 5)
        for pair in zip(commands, commands.dropFirst()) {
            XCTAssertLessThan(pair.0.splitIndex, pair.1.splitIndex)
        }
    }

    // MARK: - ac-announcement-duplicate-tick-debounced

    func testDuplicateTickIsDebounced() {
        var scheduler = AnnouncementScheduler()
        let split = makeSplit(1)
        let update = makeUpdate(splits: [split], newly: [split], elapsed: 300)

        XCTAssertEqual(scheduler.tick(update, state: .running).count, 1)
        XCTAssertTrue(scheduler.tick(update, state: .running).isEmpty)

        for _ in 0..<10 {
            XCTAssertTrue(scheduler.tick(update, state: .running).isEmpty)
        }
        XCTAssertEqual(scheduler.announcedSplitIndex, 1)
    }

    // MARK: - ac-announcement-paused-suppressed

    func testReadyAndPausedSuppressAnnouncements() {
        var scheduler = AnnouncementScheduler()
        let split = makeSplit(1)
        let update = makeUpdate(splits: [split], newly: [split], elapsed: 300)

        XCTAssertTrue(scheduler.tick(update, state: .ready).isEmpty)
        XCTAssertTrue(scheduler.tick(update, state: .paused).isEmpty)
        XCTAssertTrue(scheduler.tick(update, state: .paused).isEmpty)
        XCTAssertEqual(scheduler.announcedSplitIndex, 0)
    }

    // MARK: - ac-announcement-finished-stops

    func testFinishedAnnouncesOnceThenStops() {
        var scheduler = AnnouncementScheduler()
        let first = makeSplit(1)
        let second = makeSplit(2)
        _ = scheduler.tick(
            makeUpdate(splits: [first], newly: [first], elapsed: 300),
            state: .running
        )
        _ = scheduler.tick(
            makeUpdate(splits: [first, second], newly: [second], elapsed: 600),
            state: .running
        )

        let finishedUpdate = makeUpdate(splits: [first, second], newly: [], elapsed: 600)
        let emitted = scheduler.tick(finishedUpdate, state: .finished)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.trigger, .finished)
        XCTAssertEqual(emitted.first?.splitIndex, 2)
        XCTAssertEqual(emitted.first?.elapsed, 600)
        XCTAssertEqual(emitted.first?.distance.meters ?? -1, 2000, accuracy: 1e-9)

        XCTAssertTrue(scheduler.tick(finishedUpdate, state: .finished).isEmpty)
        XCTAssertTrue(scheduler.tick(finishedUpdate, state: .paused).isEmpty)
        XCTAssertTrue(
            scheduler.tick(
                makeUpdate(splits: [first, second], newly: [makeSplit(3)], elapsed: 900),
                state: .running
            ).isEmpty
        )
    }

    func testFinishedWithoutCompletedKilometerEmitsNothing() {
        var scheduler = AnnouncementScheduler()
        let zeroUpdate = makeUpdate(splits: [], newly: [], elapsed: 0, distanceMeters: 900)

        XCTAssertTrue(scheduler.tick(zeroUpdate, state: .finished).isEmpty)
        XCTAssertTrue(scheduler.tick(zeroUpdate, state: .finished).isEmpty)
        XCTAssertTrue(scheduler.tick(zeroUpdate, state: .running).isEmpty)
    }

    // MARK: - ac-announcement-resume-catch-up-once

    func testResumeCatchUpEmitsAtMostOne() {
        var scheduler = AnnouncementScheduler()
        let first = makeSplit(1)
        _ = scheduler.tick(
            makeUpdate(splits: [first], newly: [first], elapsed: 300),
            state: .running
        )

        let second = makeSplit(2)
        XCTAssertTrue(
            scheduler.tick(
                makeUpdate(splits: [first, second], newly: [second], elapsed: 600),
                state: .paused
            ).isEmpty
        )

        let resumed = scheduler.tick(
            makeUpdate(splits: [first, second], newly: [], elapsed: 600),
            state: .running
        )
        XCTAssertEqual(resumed.count, 1)
        XCTAssertEqual(resumed.first?.trigger, .resumedAfterPause)
        XCTAssertEqual(resumed.first?.splitIndex, 2)
        XCTAssertEqual(resumed.first?.distance.meters ?? -1, 2000, accuracy: 1e-9)

        XCTAssertTrue(
            scheduler.tick(
                makeUpdate(splits: [first, second], newly: [], elapsed: 660),
                state: .running
            ).isEmpty
        )

        _ = scheduler.tick(
            makeUpdate(splits: [first, second], newly: [], elapsed: 690),
            state: .paused
        )
        XCTAssertTrue(
            scheduler.tick(
                makeUpdate(splits: [first, second], newly: [], elapsed: 690),
                state: .running
            ).isEmpty
        )
    }

    func testResumeCatchUpDoesNotReplayEachMissingKilometer() {
        var scheduler = AnnouncementScheduler()
        let first = makeSplit(1)
        _ = scheduler.tick(
            makeUpdate(splits: [first], newly: [first], elapsed: 300),
            state: .running
        )
        _ = scheduler.tick(
            makeUpdate(splits: [first], newly: [], elapsed: 300),
            state: .paused
        )

        let splits = [first, makeSplit(2), makeSplit(3), makeSplit(4)]
        let emitted = scheduler.tick(
            makeUpdate(splits: splits, newly: [], elapsed: 1200),
            state: .running
        )
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.trigger, .resumedAfterPause)
        XCTAssertEqual(emitted.first?.splitIndex, 4)
        XCTAssertEqual(scheduler.announcedSplitIndex, 4)
    }

    // MARK: - ac-announcement-command-fields

    func testCommandFieldsAndSubKilometerSilence() {
        var scheduler = AnnouncementScheduler()
        XCTAssertTrue(
            scheduler.tick(
                makeUpdate(splits: [], newly: [], elapsed: 299, distanceMeters: 999),
                state: .running
            ).isEmpty
        )

        var splits: [RunSplit] = []
        var commands: [AnnouncementCommand] = []
        for index in 1...3 {
            let split = makeSplit(index)
            splits.append(split)
            commands += scheduler.tick(
                makeUpdate(splits: splits, newly: [split], elapsed: Double(index) * 300),
                state: .running
            )
        }

        XCTAssertEqual(commands.count, 3)
        var previousElapsed: TimeInterval = 0
        for (offset, command) in commands.enumerated() {
            let index = offset + 1
            XCTAssertEqual(command.splitIndex, index)
            XCTAssertGreaterThanOrEqual(command.splitIndex, 1)
            XCTAssertTrue(command.elapsed.isFinite)
            XCTAssertGreaterThanOrEqual(command.elapsed, 0)
            XCTAssertEqual(
                command.distance.meters,
                Double(command.splitIndex) * 1000,
                accuracy: 1e-9
            )
            XCTAssertEqual(command.pace, splits[index - 1].pace)
            XCTAssertGreaterThanOrEqual(command.elapsed, previousElapsed)
            previousElapsed = command.elapsed
        }
    }
}
