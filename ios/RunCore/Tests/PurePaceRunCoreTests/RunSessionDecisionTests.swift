import XCTest
import PurePaceRunCore

/// 第 4 波会话契约的 RunCore 侧断言：开始倒计时值语义 + 结束「快照 + 显式保存/丢弃」。
final class RunSessionDecisionTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunSessionDecisionTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        super.tearDown()
    }

    // MARK: - 夹具

    private var checkpointURL: URL {
        root.appendingPathComponent("checkpoint/session.jsonl")
    }

    private var archiveDirectoryURL: URL {
        root.appendingPathComponent("archive", isDirectory: true)
    }

    private func makeOrchestrator() -> RunSessionOrchestrator {
        RunSessionOrchestrator(
            checkpointStore: RunCheckpointStore(fileURL: checkpointURL),
            archiveStore: RunArchiveStore(directoryURL: archiveDirectoryURL)
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sample(latitude: Double, at seconds: TimeInterval) -> RunSample {
        RunSample(
            latitude: latitude,
            longitude: 0,
            altitude: nil,
            timestamp: date(seconds),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func checkpointCount() throws -> Int {
        try RunCheckpointStore(fileURL: checkpointURL).loadAll().count
    }

    private func archiveJSONFileCount() -> Int {
        let entries = try? FileManager.default.contentsOfDirectory(
            at: archiveDirectoryURL,
            includingPropertiesForKeys: nil
        )
        return (entries ?? []).filter { $0.pathExtension.lowercased() == "json" }.count
    }

    // MARK: - ac-countdown-before-running

    func testCountdownRemainingDecreasesWithInjectedClockAndCompletesAtDeadline() {
        let startedAt = date(1000)
        let countdown = RunStartCountdown(startedAt: startedAt)

        XCTAssertEqual(countdown.duration, RunStartCountdown.defaultDuration)
        XCTAssertEqual(countdown.remaining(at: startedAt), countdown.duration)
        XCTAssertFalse(countdown.isComplete(at: startedAt))
        XCTAssertFalse(countdown.isComplete(at: startedAt.addingTimeInterval(countdown.duration - 0.001)))

        let mid = startedAt.addingTimeInterval(countdown.duration / 2)
        XCTAssertEqual(countdown.remaining(at: mid), countdown.duration / 2, accuracy: 1e-9)

        let later = startedAt.addingTimeInterval(countdown.duration * 0.9)
        XCTAssertLessThan(countdown.remaining(at: later), countdown.remaining(at: mid))

        let deadline = startedAt.addingTimeInterval(countdown.duration)
        XCTAssertTrue(countdown.isComplete(at: deadline))
        XCTAssertEqual(countdown.remaining(at: deadline), 0)
        XCTAssertEqual(countdown.remaining(at: deadline.addingTimeInterval(5)), 0, "到点后剩余时间不得为负")
    }

    func testCountdownClampsNonPositiveDurationToImmediateCompletion() {
        let startedAt = date(1000)
        let zero = RunStartCountdown(duration: 0, startedAt: startedAt)
        XCTAssertEqual(zero.duration, 0)
        XCTAssertTrue(zero.isComplete(at: startedAt))

        let negative = RunStartCountdown(duration: -5, startedAt: startedAt)
        XCTAssertEqual(negative.duration, 0)

        let infinite = RunStartCountdown(duration: .infinity, startedAt: startedAt)
        XCTAssertEqual(infinite.duration, 0)
    }

    // MARK: - ac-finish-awaits-decision

    func testPrepareFinishFromRunningSnapshotsWithoutArchiving() throws {
        var orchestrator = makeOrchestrator()
        let startedAt = date(1000)
        try orchestrator.start(at: startedAt)
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        _ = try orchestrator.ingest(sample(latitude: 0.001, at: 1020))
        let metrics = orchestrator.metrics
        let checkpointBeforeFinish = try checkpointCount()
        XCTAssertGreaterThan(checkpointBeforeFinish, 0)

        let record = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1030)))

        XCTAssertEqual(orchestrator.state, .finished)
        XCTAssertTrue(orchestrator.isAwaitingDecision)
        XCTAssertNil(orchestrator.savedRecord)
        XCTAssertEqual(orchestrator.finishedSnapshot, record)
        XCTAssertEqual(archiveJSONFileCount(), 0, "结束决策前不得落盘")
        XCTAssertEqual(try checkpointCount(), 0, "结束后不再保留 checkpoint")
        XCTAssertEqual(record.startedAt, startedAt)
        XCTAssertEqual(record.endedAt, date(1030))
        XCTAssertEqual(record.distance, metrics.distance)
        XCTAssertEqual(record.activeDuration, metrics.elapsed)
        XCTAssertEqual(record.splits, metrics.splits)
        XCTAssertEqual(record.samples, orchestrator.acceptedSamples)

        let afterFinish = try orchestrator.ingest(sample(latitude: 0.5, at: 1040))
        XCTAssertEqual(afterFinish.state, .finished)
        XCTAssertEqual(afterFinish.metrics, metrics, "结束后不得再推进度量")
        XCTAssertEqual(try checkpointCount(), 0, "结束后不得再写 checkpoint")
    }

    func testPrepareFinishFromPausedSnapshotsWithoutArchiving() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        try orchestrator.pause(at: date(1015))
        let metrics = orchestrator.metrics

        let record = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1020)))

        XCTAssertEqual(orchestrator.state, .finished)
        XCTAssertEqual(archiveJSONFileCount(), 0)
        XCTAssertEqual(record.endedAt, date(1020))
        XCTAssertEqual(record.distance, metrics.distance)
        XCTAssertEqual(record.activeDuration, metrics.elapsed)
        XCTAssertEqual(record.splits, metrics.splits)
    }

    func testRepeatedPrepareFinishDoesNotRegenerateSnapshot() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))

        let first = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1020)))
        let second = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1030)))

        XCTAssertEqual(first, second, "重复结束不得生成第二份快照")
        XCTAssertEqual(archiveJSONFileCount(), 0)
    }

    // MARK: - ac-save-once

    func testSaveArchivesExactlyOnceAndReturnsSameRecord() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        let snapshot = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1020)))

        let saved = try orchestrator.saveFinished()
        XCTAssertEqual(saved, snapshot)
        XCTAssertEqual(archiveJSONFileCount(), 1)
        XCTAssertEqual(try RunArchiveStore(directoryURL: archiveDirectoryURL).list(), [snapshot])
        XCTAssertEqual(orchestrator.savedRecord, snapshot)
        XCTAssertFalse(orchestrator.isAwaitingDecision)

        let again = try orchestrator.saveFinished()
        XCTAssertEqual(again, snapshot)
        XCTAssertEqual(archiveJSONFileCount(), 1, "重复保存不得新增文件")
        XCTAssertEqual(try RunArchiveStore(directoryURL: archiveDirectoryURL).list(), [snapshot])
    }

    // MARK: - ac-save-failure-retry

    func testSaveFailureLeavesNoFileAndRetrySucceeds() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        // 归档目录路径被同名普通文件占用 → save 必然 ioFailure。
        try Data("occupied".utf8).write(to: archiveDirectoryURL)

        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        let snapshot = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1020)))

        XCTAssertThrowsError(try orchestrator.saveFinished()) { error in
            guard case RunArchiveError.ioFailure? = error as? RunArchiveError else {
                return XCTFail("首次保存失败原因必须是 ioFailure，实际 \(error)")
            }
        }
        XCTAssertEqual(orchestrator.state, .finished)
        XCTAssertTrue(orchestrator.isAwaitingDecision, "保存失败后决策仍在")
        XCTAssertNil(orchestrator.savedRecord)
        XCTAssertEqual(archiveJSONFileCount(), 0)

        try fileManager.removeItem(at: archiveDirectoryURL)
        let saved = try orchestrator.saveFinished()
        XCTAssertEqual(saved, snapshot)
        XCTAssertEqual(archiveJSONFileCount(), 1)
        XCTAssertEqual(try RunArchiveStore(directoryURL: archiveDirectoryURL).list(), [snapshot])
    }

    // MARK: - ac-discard-no-archive

    func testDiscardKeepsArchiveEmptyAndRestartsFromZero() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        _ = try orchestrator.prepareFinish(at: date(1020))

        try orchestrator.discard()

        XCTAssertEqual(orchestrator.state, .ready)
        XCTAssertEqual(orchestrator.metrics, .initial)
        XCTAssertTrue(orchestrator.acceptedSamples.isEmpty)
        XCTAssertNil(orchestrator.finishedSnapshot)
        XCTAssertNil(orchestrator.savedRecord)
        XCTAssertEqual(archiveJSONFileCount(), 0)
        XCTAssertEqual(try checkpointCount(), 0)

        try orchestrator.start(at: date(2000))
        let firstUpdate = try orchestrator.ingest(sample(latitude: 0, at: 2010))
        XCTAssertEqual(firstUpdate.state, .running)
        XCTAssertEqual(firstUpdate.metrics.distance.meters, 0, "丢弃后新跑次从 0 起算")
        XCTAssertEqual(firstUpdate.metrics.elapsed, 0)

        let secondUpdate = try orchestrator.ingest(sample(latitude: 0.00027, at: 2020))
        XCTAssertGreaterThan(secondUpdate.metrics.distance.meters, 0, "丢弃后必须能重新累计")
        XCTAssertEqual(secondUpdate.metrics.completedKilometers, 0)
        XCTAssertEqual(orchestrator.acceptedSamples.count, 2, "丢弃不残留上一跑次的采样")
    }

    // MARK: - ac-decision-guards

    func testSaveAndDiscardRejectNonFinishedStates() throws {
        var fresh = makeOrchestrator()
        XCTAssertThrowsError(try fresh.saveFinished()) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .ready, to: .finished))
        }
        XCTAssertThrowsError(try fresh.discard()) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .ready, to: .ready))
        }

        try fresh.start(at: date(1000))
        XCTAssertThrowsError(try fresh.saveFinished()) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .running, to: .finished))
        }
        XCTAssertThrowsError(try fresh.discard()) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .running, to: .ready))
        }
        XCTAssertEqual(fresh.state, .running)
        XCTAssertEqual(archiveJSONFileCount(), 0)

        try fresh.pause(at: date(1010))
        XCTAssertThrowsError(try fresh.saveFinished()) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .paused, to: .finished))
        }
        XCTAssertThrowsError(try fresh.discard()) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .paused, to: .ready))
        }
        XCTAssertEqual(fresh.state, .paused)
        XCTAssertEqual(archiveJSONFileCount(), 0)
        XCTAssertGreaterThan(try checkpointCount(), 0, "非法决策不得清 checkpoint")
    }

    func testFinishAfterPrepareDoesNotArchiveOrRegenerate() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        let snapshot = try XCTUnwrap(try orchestrator.prepareFinish(at: date(1020)))

        XCTAssertNil(try orchestrator.finish(at: date(1030)), "已结束后重复结束必须返回 nil")
        XCTAssertEqual(orchestrator.finishedSnapshot, snapshot)
        XCTAssertEqual(archiveJSONFileCount(), 0, "重复结束不得绕过决策直接归档")
    }

    // MARK: - 既有 finish 语义不回退

    func testFinishStillArchivesOnceWithoutExplicitPrepare() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))

        let record = try XCTUnwrap(try orchestrator.finish(at: date(1020)))
        XCTAssertEqual(archiveJSONFileCount(), 1)
        XCTAssertEqual(orchestrator.savedRecord, record)
        XCTAssertNil(try orchestrator.finish(at: date(1030)))
        XCTAssertEqual(archiveJSONFileCount(), 1)
    }
}
