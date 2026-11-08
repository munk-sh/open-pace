import XCTest
import PurePaceRunCore

/// 编译期契约：编排器与更新值类型必须满足 `Sendable`（Swift 6 严格并发）。
private func requireOrchestratorSendable<T: Sendable>(_: T.Type) {}

final class RunSessionOrchestratorTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunSessionOrchestratorTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeOrchestrator(announcementsEnabled: Bool = true) -> RunSessionOrchestrator {
        RunSessionOrchestrator(
            checkpointStore: RunCheckpointStore(fileURL: checkpointURL),
            archiveStore: RunArchiveStore(directoryURL: archiveDirectoryURL),
            announcementsEnabled: announcementsEnabled
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sample(
        latitude: Double,
        at seconds: TimeInterval,
        altitude: Double? = nil,
        heartRate: Int? = nil,
        cadence: Int? = nil
    ) -> RunSample {
        RunSample(
            latitude: latitude,
            longitude: 0,
            altitude: altitude,
            timestamp: date(seconds),
            heartRate: heartRate,
            cadence: cadence
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

    // MARK: - ac-start-ready-to-running

    func testStartTransitionsReadyToRunningAndWritesCheckpoint() throws {
        var orchestrator = makeOrchestrator()
        let t0 = date(1_700_000_000)

        let update = try orchestrator.start(at: t0)

        XCTAssertEqual(update.state, .running)
        XCTAssertEqual(orchestrator.state, .running)
        XCTAssertEqual(orchestrator.metrics.distance.meters, 0, accuracy: 0)
        XCTAssertEqual(orchestrator.metrics.elapsed, 0, accuracy: 0)
        XCTAssertTrue(orchestrator.metrics.splits.isEmpty)
        XCTAssertNil(orchestrator.metrics.currentPace)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpointURL.path))

        let checkpoints = try RunCheckpointStore(fileURL: checkpointURL).loadAll()
        XCTAssertEqual(checkpoints.count, 1)
        XCTAssertEqual(checkpoints.first?.state, .running)
        XCTAssertEqual(checkpoints.first?.completedDistance.meters ?? -1, 0, accuracy: 0)
        XCTAssertEqual(checkpoints.first?.elapsed ?? -1, 0, accuracy: 0)
        XCTAssertEqual(checkpoints.first?.recordedAt, t0)
    }

    // MARK: - ac-ingest-accumulates

    func testIngestAccumulatesDistanceElapsedAndKeepsSamples() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        let first = sample(latitude: 0, at: 1010, altitude: 10, heartRate: 120, cadence: 80)
        let second = sample(latitude: 0.001, at: 1020, altitude: 11, heartRate: 121, cadence: 81)
        let third = sample(latitude: 0.002, at: 1030, altitude: 12, heartRate: 122, cadence: 82)

        _ = try orchestrator.ingest(first)
        _ = try orchestrator.ingest(second)
        _ = try orchestrator.ingest(third)

        let expected = GeoDistance.meters(latitude1: 0, longitude1: 0, latitude2: 0.001, longitude2: 0)
            + GeoDistance.meters(latitude1: 0.001, longitude1: 0, latitude2: 0.002, longitude2: 0)
        XCTAssertEqual(orchestrator.metrics.distance.meters, expected, accuracy: 1e-6)
        XCTAssertEqual(orchestrator.metrics.elapsed, 20, accuracy: 1e-9)
        XCTAssertEqual(orchestrator.acceptedSamples, [first, second, third])
    }

    // MARK: - ac-pause-zero-growth

    func testPauseFreezesMetricsAndExcludesPausedSamplesFromArchive() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        let first = sample(latitude: 0, at: 1010)
        let second = sample(latitude: 0.001, at: 1020)
        _ = try orchestrator.ingest(first)
        _ = try orchestrator.ingest(second)
        let snapshot = orchestrator.metrics

        let paused = try orchestrator.pause(at: date(1030))
        XCTAssertEqual(paused.state, .paused)
        XCTAssertEqual(paused.metrics.distance.meters, snapshot.distance.meters, accuracy: 0)
        XCTAssertEqual(paused.metrics.elapsed, snapshot.elapsed, accuracy: 0)
        XCTAssertEqual(paused.metrics.splits, snapshot.splits)
        XCTAssertNil(paused.metrics.currentPace)
        XCTAssertTrue(paused.announcements.isEmpty)

        let duringPause = try orchestrator.ingest(sample(latitude: 40, at: 1040))
        XCTAssertTrue(duringPause.announcements.isEmpty)
        XCTAssertEqual(duringPause.metrics.distance.meters, snapshot.distance.meters, accuracy: 0)
        XCTAssertEqual(duringPause.metrics.elapsed, snapshot.elapsed, accuracy: 0)
        XCTAssertEqual(duringPause.metrics.splits, snapshot.splits)
        XCTAssertNil(duringPause.metrics.currentPace)
        _ = try orchestrator.ingest(sample(latitude: 41, at: 1050))

        XCTAssertEqual(orchestrator.metrics.distance.meters, snapshot.distance.meters, accuracy: 0)
        XCTAssertEqual(orchestrator.metrics.elapsed, snapshot.elapsed, accuracy: 0)
        XCTAssertEqual(orchestrator.acceptedSamples, [first, second])

        let record = try XCTUnwrap(try orchestrator.finish(at: date(1060)))
        XCTAssertEqual(record.samples, [first, second])
    }

    // MARK: - ac-resume-continues

    func testResumeRebuildsAnchorThenContinuesAndAnnouncesSplit() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        _ = try orchestrator.ingest(sample(latitude: 0.0001, at: 1020))
        _ = try orchestrator.pause(at: date(1030))
        let beforeResume = orchestrator.metrics

        _ = try orchestrator.resume(at: date(1100))
        let anchorUpdate = try orchestrator.ingest(sample(latitude: 0.5, at: 1110))
        XCTAssertEqual(anchorUpdate.metrics.distance.meters, beforeResume.distance.meters, accuracy: 0)
        XCTAssertEqual(
            anchorUpdate.metrics.elapsed,
            beforeResume.elapsed + 10,
            accuracy: 1e-9
        )

        var announcements: [AnnouncementCommand] = []
        var latitude = 0.5
        var timestamp = 1120.0
        for _ in 0..<6 {
            latitude += 0.002
            let update = try orchestrator.ingest(sample(latitude: latitude, at: timestamp))
            announcements.append(contentsOf: update.announcements)
            timestamp += 10
        }

        XCTAssertEqual(announcements.map(\.splitIndex), [1])
        XCTAssertEqual(announcements.first?.trigger, .kilometerCompleted)
        XCTAssertEqual(orchestrator.metrics.completedKilometers, 1)
    }

    // MARK: - ac-finish-archives-once

    func testFinishArchivesExactlyOnce() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        _ = try orchestrator.ingest(sample(latitude: 0.001, at: 1020))

        let first = try XCTUnwrap(try orchestrator.finish(at: date(1030)))
        XCTAssertEqual(archiveJSONFileCount(), 1)
        let listed = try RunArchiveStore(directoryURL: archiveDirectoryURL).list()
        XCTAssertEqual(listed, [first])

        let second = try orchestrator.finish(at: date(1040))
        XCTAssertNil(second)
        XCTAssertEqual(orchestrator.state, .finished)
        XCTAssertEqual(archiveJSONFileCount(), 1)
        XCTAssertEqual(try RunArchiveStore(directoryURL: archiveDirectoryURL).list(), [first])
    }

    // MARK: - ac-finish-record-matches-session

    func testFinishRecordMatchesSessionMetricsAndSamples() throws {
        var orchestrator = makeOrchestrator()
        let startedAt = date(1000)
        let endedAt = date(1040)
        try orchestrator.start(at: startedAt)
        let first = sample(latitude: 0, at: 1010, altitude: 5, heartRate: 130, cadence: 85)
        let second = sample(latitude: 0.001, at: 1020, altitude: 6, heartRate: 131, cadence: 86)
        let third = sample(latitude: 0.002, at: 1030, altitude: 7, heartRate: 132, cadence: 87)
        _ = try orchestrator.ingest(first)
        _ = try orchestrator.ingest(second)
        _ = try orchestrator.ingest(third)
        let metrics = orchestrator.metrics

        let record = try XCTUnwrap(try orchestrator.finish(at: endedAt))

        XCTAssertEqual(record.startedAt, startedAt)
        XCTAssertEqual(record.endedAt, endedAt)
        XCTAssertEqual(record.distance, metrics.distance)
        XCTAssertEqual(record.activeDuration, metrics.elapsed)
        XCTAssertEqual(record.splits, metrics.splits)
        XCTAssertEqual(record.samples, [first, second, third])
        XCTAssertEqual(record.formatVersion, RunRecord.currentFormatVersion)
    }

    // MARK: - ac-finish-resets-checkpoint

    func testFinishClearsCheckpointButKeepsArchive() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1010))
        let beforeFinish = try RunCheckpointStore(fileURL: checkpointURL).loadAll()
        XCTAssertFalse(beforeFinish.isEmpty)

        _ = try orchestrator.finish(at: date(1020))

        XCTAssertEqual(try RunCheckpointStore(fileURL: checkpointURL).loadAll(), [])
        XCTAssertEqual(archiveJSONFileCount(), 1)
    }

    // MARK: - ac-sample-monotonic-gate

    func testMonotonicGateDropsEqualAndEarlierSamples() throws {
        var orchestrator = makeOrchestrator()
        try orchestrator.start(at: date(1000))
        let first = sample(latitude: 0, at: 1010)
        let second = sample(latitude: 0.001, at: 1020)
        _ = try orchestrator.ingest(first)
        _ = try orchestrator.ingest(second)
        let snapshot = orchestrator.metrics

        let equalTimed = try orchestrator.ingest(sample(latitude: 0.002, at: 1020))
        XCTAssertEqual(equalTimed.metrics.distance.meters, snapshot.distance.meters, accuracy: 0)
        XCTAssertEqual(equalTimed.metrics.elapsed, snapshot.elapsed, accuracy: 0)
        XCTAssertEqual(equalTimed.metrics.splits, snapshot.splits)
        XCTAssertTrue(equalTimed.announcements.isEmpty)

        let earlierTimed = try orchestrator.ingest(sample(latitude: 0.003, at: 1015))
        XCTAssertEqual(earlierTimed.metrics.distance.meters, snapshot.distance.meters, accuracy: 0)
        XCTAssertEqual(earlierTimed.metrics.elapsed, snapshot.elapsed, accuracy: 0)
        XCTAssertEqual(orchestrator.acceptedSamples, [first, second])

        let record = try XCTUnwrap(try orchestrator.finish(at: date(1030)))
        XCTAssertEqual(record.samples, [first, second])
    }

    func testIngestIsIgnoredBeforeStartAndAfterFinish() throws {
        var orchestrator = makeOrchestrator()
        let readyUpdate = try orchestrator.ingest(sample(latitude: 0, at: 1000))
        XCTAssertEqual(readyUpdate.state, .ready)
        XCTAssertEqual(readyUpdate.metrics, .initial)
        XCTAssertEqual(orchestrator.state, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
        XCTAssertEqual(archiveJSONFileCount(), 0)

        try orchestrator.start(at: date(1010))
        _ = try orchestrator.ingest(sample(latitude: 0, at: 1020))
        let record = try XCTUnwrap(try orchestrator.finish(at: date(1030)))
        let metricsAfterFinish = orchestrator.metrics

        let finishedUpdate = try orchestrator.ingest(sample(latitude: 5, at: 1040))
        XCTAssertEqual(finishedUpdate.state, .finished)
        XCTAssertEqual(finishedUpdate.metrics, metricsAfterFinish)
        XCTAssertTrue(finishedUpdate.announcements.isEmpty)
        XCTAssertEqual(try RunCheckpointStore(fileURL: checkpointURL).loadAll(), [])
        XCTAssertEqual(try RunArchiveStore(directoryURL: archiveDirectoryURL).list(), [record])
    }

    // MARK: - ac-announce-toggle-off

    func testAnnouncementToggleOffSuppressesWithoutCatchUp() throws {
        var orchestrator = makeOrchestrator()
        XCTAssertTrue(orchestrator.announcementsEnabled)
        try orchestrator.start(at: date(1000))

        var first: [AnnouncementCommand] = []
        var timestamp = 1010.0
        for step in 1...7 {
            let update = try orchestrator.ingest(sample(latitude: 0.002 * Double(step), at: timestamp))
            first.append(contentsOf: update.announcements)
            timestamp += 10
        }
        XCTAssertEqual(first.map(\.splitIndex), [1])

        orchestrator.setAnnouncementsEnabled(false)
        var suppressed: [AnnouncementCommand] = []
        for step in 8...11 {
            let update = try orchestrator.ingest(sample(latitude: 0.002 * Double(step), at: timestamp))
            suppressed.append(contentsOf: update.announcements)
            timestamp += 10
        }
        XCTAssertTrue(suppressed.isEmpty)
        XCTAssertEqual(orchestrator.metrics.completedKilometers, 2)

        orchestrator.setAnnouncementsEnabled(true)
        let stillSilent = try orchestrator.ingest(sample(latitude: 0.002 * 12, at: timestamp))
        timestamp += 10
        XCTAssertTrue(stillSilent.announcements.isEmpty)

        var third: [AnnouncementCommand] = []
        for step in 13...16 {
            let update = try orchestrator.ingest(sample(latitude: 0.002 * Double(step), at: timestamp))
            third.append(contentsOf: update.announcements)
            timestamp += 10
        }
        XCTAssertEqual(third.map(\.splitIndex), [3])
        XCTAssertEqual(third.first?.trigger, .kilometerCompleted)
    }

    func testAnnouncementsDisabledFromInitNeverEmitUntilEnabled() throws {
        var orchestrator = makeOrchestrator(announcementsEnabled: false)
        XCTAssertFalse(orchestrator.announcementsEnabled)
        try orchestrator.start(at: date(1000))

        var suppressed: [AnnouncementCommand] = []
        var timestamp = 1010.0
        for step in 1...6 {
            let update = try orchestrator.ingest(sample(latitude: 0.002 * Double(step), at: timestamp))
            suppressed.append(contentsOf: update.announcements)
            timestamp += 10
        }
        XCTAssertTrue(suppressed.isEmpty)
        XCTAssertEqual(orchestrator.metrics.completedKilometers, 1)

        orchestrator.setAnnouncementsEnabled(true)
        let catchUp = try orchestrator.ingest(sample(latitude: 0.002 * 7, at: 1100))
        XCTAssertTrue(catchUp.announcements.isEmpty)

        var announced: [AnnouncementCommand] = []
        for step in 8...10 {
            let update = try orchestrator.ingest(sample(latitude: 0.002 * Double(step), at: 1100 + 10 * Double(step)))
            announced.append(contentsOf: update.announcements)
        }
        XCTAssertEqual(announced.map(\.splitIndex), [2])
    }

    // MARK: - ac-invalid-transitions

    func testInvalidTransitionsPreserveStateAndStorage() throws {
        var orchestrator = makeOrchestrator()
        let stamp = date(1000)

        XCTAssertThrowsError(try orchestrator.pause(at: stamp)) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .ready, to: .paused))
        }
        XCTAssertThrowsError(try orchestrator.resume(at: stamp)) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .ready, to: .running))
        }
        XCTAssertThrowsError(try orchestrator.finish(at: stamp)) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .ready, to: .finished))
        }
        XCTAssertEqual(orchestrator.state, .ready)
        XCTAssertEqual(try checkpointCount(), 0)
        XCTAssertEqual(archiveJSONFileCount(), 0)

        try orchestrator.start(at: date(1010))
        XCTAssertEqual(try checkpointCount(), 1)
        XCTAssertThrowsError(try orchestrator.start(at: date(1020))) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .running, to: .running))
        }
        XCTAssertEqual(orchestrator.state, .running)
        XCTAssertEqual(try checkpointCount(), 1)

        _ = try orchestrator.finish(at: date(1030))
        XCTAssertThrowsError(try orchestrator.start(at: date(1040))) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .finished, to: .running))
        }
        XCTAssertThrowsError(try orchestrator.pause(at: date(1040))) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .finished, to: .paused))
        }
        XCTAssertThrowsError(try orchestrator.resume(at: date(1040))) { error in
            XCTAssertEqual(error as? RunCoreError, .invalidStateTransition(from: .finished, to: .running))
        }
        XCTAssertEqual(orchestrator.state, .finished)
        XCTAssertEqual(try checkpointCount(), 0)
        XCTAssertEqual(archiveJSONFileCount(), 1)
    }

    // MARK: - 并发契约

    func testOrchestratorTypesAreSendable() {
        requireOrchestratorSendable(RunSessionOrchestrator.self)
        requireOrchestratorSendable(RunSessionUpdate.self)
    }
}
