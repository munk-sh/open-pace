import XCTest
import PurePaceRunCore

// 合成 1 Hz 坐标流：固定航向、恒定配速，时间戳从固定基准递增（不读当前时间）。
private let resumeEarthRadius = 6_371_000.0
private let resumeMetersPerDegreeLatitude = resumeEarthRadius * Double.pi / 180.0
private let resumeBaseLatitude = 31.2304
private let resumeBaseLongitude = 121.4737

private func makeResumeStream(
    paceSecondsPerKilometer: Double = 300,
    sampleCount: Int,
    startTimestamp: TimeInterval = 0
) -> [RunSample] {
    let bearing = 60.0 * Double.pi / 180.0
    let metersPerDegreeLongitude = resumeMetersPerDegreeLatitude
        * cos(resumeBaseLatitude * Double.pi / 180.0)
    let metersPerSecond = 1000.0 / paceSecondsPerKilometer

    var samples: [RunSample] = []
    for index in 0..<sampleCount {
        let traveled = metersPerSecond * Double(index)
        let latitude = resumeBaseLatitude + traveled * cos(bearing) / resumeMetersPerDegreeLatitude
        let longitude = resumeBaseLongitude + traveled * sin(bearing) / metersPerDegreeLongitude
        guard let sample = RunSample(
            latitude: latitude,
            longitude: longitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: startTimestamp + Double(index)),
            heartRate: nil,
            cadence: nil
        ) else {
            return []
        }
        samples.append(sample)
    }
    return samples
}

final class ResumeContractTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        super.tearDown()
    }

    private var fileURL: URL {
        directory.appendingPathComponent("checkpoints/session.jsonl")
    }

    // MARK: - Helpers

    private func makeDistance(_ meters: Double) -> RunDistance {
        guard let distance = RunDistance(meters: meters) else {
            preconditionFailure("测试距离必须合法: \(meters)")
        }
        return distance
    }

    private func makeSplit(_ index: Int, duration: TimeInterval = 300) -> RunSplit {
        guard let split = RunSplit(index: index, distance: makeDistance(1000), duration: duration) else {
            preconditionFailure("测试分段必须合法: \(index)")
        }
        return split
    }

    private func makeAnchor(
        latitude: Double = 31.2304,
        longitude: Double = 121.4737,
        timestamp: TimeInterval = 900
    ) -> RunSampleAnchor {
        guard let anchor = RunSampleAnchor(
            latitude: latitude,
            longitude: longitude,
            timestamp: Date(timeIntervalSince1970: timestamp)
        ) else {
            preconditionFailure("测试锚点必须合法")
        }
        return anchor
    }

    private func makeCheckpoint(
        state: RunSessionState = .paused,
        meters: Double = 2500,
        elapsed: TimeInterval = 900,
        splits: [RunSplit] = [],
        recordedAt: Date = Date(timeIntervalSince1970: 900),
        lastSample: RunSampleAnchor? = nil,
        announcedSplitIndex: Int? = nil
    ) -> RunCheckpoint {
        guard let checkpoint = RunCheckpoint(
            state: state,
            completedDistance: makeDistance(meters),
            elapsed: elapsed,
            splits: splits,
            recordedAt: recordedAt,
            lastSample: lastSample,
            announcedSplitIndex: announcedSplitIndex
        ) else {
            preconditionFailure("测试 checkpoint 必须合法")
        }
        return checkpoint
    }

    private func encodedLine(_ checkpoint: RunCheckpoint) throws -> String {
        String(decoding: try JSONEncoder().encode(checkpoint), as: UTF8.self)
    }

    private func writeRaw(_ contents: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
    }

    private func makeUpdate(
        splits: [RunSplit],
        newly: [RunSplit],
        elapsed: TimeInterval
    ) -> RunMetricsUpdate {
        let metrics = RunMetrics(
            distance: makeDistance(Double(splits.count) * 1000),
            elapsed: elapsed,
            averagePace: RunPace(secondsPerKilometer: 300),
            currentPace: RunPace(secondsPerKilometer: 300),
            splits: splits,
            completedKilometers: splits.count
        )
        return RunMetricsUpdate(metrics: metrics, newlyCompletedSplits: newly)
    }

    // MARK: - ac-checkpoint-last-sample-roundtrip

    func testCheckpointLastSampleJSONRoundTrip() throws {
        let anchor = makeAnchor(latitude: 31.2304, longitude: 121.4737, timestamp: 900)
        let checkpoint = makeCheckpoint(splits: [makeSplit(1), makeSplit(2)], lastSample: anchor, announcedSplitIndex: 2)

        let decoded = try JSONDecoder().decode(RunCheckpoint.self, from: JSONEncoder().encode(checkpoint))

        guard let restored = decoded.lastSample else {
            return XCTFail("最后采样点应被解码")
        }
        XCTAssertEqual(restored.latitude, anchor.latitude, accuracy: 1e-9)
        XCTAssertEqual(restored.longitude, anchor.longitude, accuracy: 1e-9)
        XCTAssertEqual(restored.timestamp, anchor.timestamp)
    }

    func testCheckpointLastSampleStoreRoundTrip() throws {
        let anchor = makeAnchor(latitude: 31.2304, longitude: 121.4737, timestamp: 900)
        let checkpoint = makeCheckpoint(splits: [makeSplit(1), makeSplit(2)], lastSample: anchor, announcedSplitIndex: 2)
        let store = RunCheckpointStore(fileURL: fileURL)

        try store.append(checkpoint)
        let latest = try store.loadLatest()

        guard let restored = latest?.lastSample else {
            return XCTFail("已落盘的最后采样点应可读回")
        }
        XCTAssertEqual(restored.latitude, anchor.latitude, accuracy: 1e-9)
        XCTAssertEqual(restored.longitude, anchor.longitude, accuracy: 1e-9)
        XCTAssertEqual(restored.timestamp, anchor.timestamp)
    }

    // MARK: - ac-checkpoint-announced-index-roundtrip

    func testCheckpointAnnouncedIndexRoundTrip() throws {
        let checkpoint = makeCheckpoint(splits: [makeSplit(1), makeSplit(2)], announcedSplitIndex: 2)

        let decoded = try JSONDecoder().decode(RunCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(decoded.announcedSplitIndex, 2)

        let store = RunCheckpointStore(fileURL: fileURL)
        try store.append(checkpoint)
        XCTAssertEqual(try store.loadLatest()?.announcedSplitIndex, 2)
    }

    // MARK: - ac-checkpoint-legacy-decode

    private let legacyLine = """
    {"formatVersion":1,"state":"paused","completedDistance":1500,"elapsed":540,\
    "splits":[{"index":1,"distance":1000,"duration":360}],"recordedAt":1700000000}
    """

    func testLegacyCheckpointDecodesRecoveryFieldsAsNil() throws {
        let decoded = try JSONDecoder().decode(RunCheckpoint.self, from: Data(legacyLine.utf8))

        XCTAssertNil(decoded.lastSample)
        XCTAssertNil(decoded.announcedSplitIndex)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.state, .paused)
        XCTAssertEqual(decoded.completedDistance.meters, 1500)
        XCTAssertEqual(decoded.elapsed, 540)
        XCTAssertEqual(decoded.splits.map(\.index), [1])
        XCTAssertEqual(decoded.splits.first?.duration, 360)
        XCTAssertEqual(decoded.recordedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testStoreLoadsMixedLegacyAndNewLines() throws {
        let anchor = makeAnchor(timestamp: 900)
        let modern = makeCheckpoint(
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1), makeSplit(2)],
            lastSample: anchor,
            announcedSplitIndex: 2
        )
        try writeRaw(legacyLine + "\n" + (try encodedLine(modern)) + "\n")

        let all = try RunCheckpointStore(fileURL: fileURL).loadAll()

        XCTAssertEqual(all.count, 2)
        XCTAssertNil(all[0].lastSample)
        XCTAssertNil(all[0].announcedSplitIndex)
        XCTAssertEqual(all[1].lastSample?.latitude ?? 0, anchor.latitude, accuracy: 1e-9)
        XCTAssertEqual(all[1].announcedSplitIndex, 2)
    }

    // MARK: - ac-checkpoint-new-field-validation

    func testAnchorRejectsInvalidCoordinatesAndTimestamps() {
        let valid = Date(timeIntervalSince1970: 900)
        XCTAssertNil(RunSampleAnchor(latitude: 90.1, longitude: 0, timestamp: valid))
        XCTAssertNil(RunSampleAnchor(latitude: 0, longitude: 180.1, timestamp: valid))
        XCTAssertNil(RunSampleAnchor(latitude: .nan, longitude: 0, timestamp: valid))
        XCTAssertNil(RunSampleAnchor(latitude: 0, longitude: .infinity, timestamp: valid))
        XCTAssertNil(RunSampleAnchor(latitude: 0, longitude: 0, timestamp: .distantPast))
        XCTAssertNil(RunSampleAnchor(latitude: 0, longitude: 0, timestamp: .distantFuture))
        XCTAssertNotNil(RunSampleAnchor(latitude: 0, longitude: 0, timestamp: valid))
    }

    func testCheckpointRejectsOutOfRangeAnnouncedIndexAndReadyAnchor() {
        let splits = [makeSplit(1), makeSplit(2)]

        XCTAssertNil(RunCheckpoint(
            state: .paused,
            completedDistance: makeDistance(2500),
            elapsed: 900,
            splits: splits,
            recordedAt: Date(timeIntervalSince1970: 900),
            announcedSplitIndex: -1
        ))
        XCTAssertNil(RunCheckpoint(
            state: .paused,
            completedDistance: makeDistance(2500),
            elapsed: 900,
            splits: splits,
            recordedAt: Date(timeIntervalSince1970: 900),
            announcedSplitIndex: 3
        ))
        XCTAssertNotNil(RunCheckpoint(
            state: .paused,
            completedDistance: makeDistance(2500),
            elapsed: 900,
            splits: splits,
            recordedAt: Date(timeIntervalSince1970: 900),
            announcedSplitIndex: 2
        ))
        XCTAssertNil(RunCheckpoint(
            state: .ready,
            completedDistance: makeDistance(0),
            elapsed: 0,
            splits: [],
            recordedAt: Date(timeIntervalSince1970: 900),
            lastSample: makeAnchor()
        ))
    }

    func testDecodingRejectsInvalidLastSamplePayload() {
        let invalidLine = """
        {"formatVersion":1,"state":"paused","completedDistance":2500,"elapsed":900,"splits":[],\
        "recordedAt":1700000000,"lastSample":{"latitude":91,"longitude":0,"timestamp":900}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(RunCheckpoint.self, from: Data(invalidLine.utf8)))
    }

    // MARK: - ac-engine-restore-ledger

    func testEngineRestoreRebuildsLedgerAndAveragePace() {
        let checkpoint = makeCheckpoint(
            state: .paused,
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            lastSample: makeAnchor(),
            announcedSplitIndex: 2
        )

        let engine = RunMetricsEngine(restoring: checkpoint)

        XCTAssertEqual(engine.metrics.distance.meters, 2500, accuracy: 1e-9)
        XCTAssertEqual(engine.metrics.elapsed, 900, accuracy: 1e-9)
        XCTAssertEqual(engine.metrics.splits.map(\.index), [1, 2])
        XCTAssertEqual(engine.metrics.completedKilometers, 2)
        let expectedPace = 900 / (2500 / 1000.0)
        XCTAssertEqual(engine.metrics.averagePace?.secondsPerKilometer ?? 0, expectedPace, accuracy: 1e-9)
    }

    // MARK: - ac-engine-restore-paused-state

    func testEngineRestoreFromRunningOrPausedStaysPausedUntilResume() {
        let stream = makeResumeStream(sampleCount: 4, startTimestamp: 900)
        XCTAssertEqual(stream.count, 4)

        for original in [RunSessionState.running, RunSessionState.paused] {
            let checkpoint = makeCheckpoint(
                state: original,
                meters: 2500,
                elapsed: 900,
                splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
                lastSample: RunSampleAnchor(sample: stream[0])
            )
            var engine = RunMetricsEngine(restoring: checkpoint)
            let before = engine.metrics

            _ = engine.ingest(stream[1])
            XCTAssertEqual(engine.metrics, before, "恢复为暂停态时 ingest 不得累计")

            engine.resume(at: Date(timeIntervalSince1970: 900))
            _ = engine.ingest(stream[1])
            _ = engine.ingest(stream[2])

            XCTAssertGreaterThan(engine.metrics.distance.meters, 2500)
            XCTAssertEqual(engine.metrics.elapsed, 902, accuracy: 1e-9)
        }
    }

    // MARK: - ac-engine-restore-continues-splits

    func testEngineRestoreContinuesSplitsFromThree() {
        let stream = makeResumeStream(paceSecondsPerKilometer: 300, sampleCount: 400, startTimestamp: 900)
        XCTAssertEqual(stream.count, 400)
        let restoredDuration: TimeInterval = 350 + 360
        let checkpoint = makeCheckpoint(
            state: .paused,
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            lastSample: RunSampleAnchor(sample: stream[0])
        )

        var engine = RunMetricsEngine(restoring: checkpoint)
        engine.resume(at: Date(timeIntervalSince1970: 900))

        var fed: [RunSample] = []
        var created: [RunSplit] = []
        for sample in stream.dropFirst() {
            fed.append(sample)
            let update = engine.ingest(sample)
            created.append(contentsOf: update.newlyCompletedSplits)
            if !created.isEmpty { break }
        }

        XCTAssertEqual(created.map(\.index), [3], "恢复后不得重复产出 1/2")
        XCTAssertEqual(engine.metrics.splits.map(\.index), [1, 2, 3])
        guard let split3 = engine.metrics.splits.last else {
            return XCTFail("应完成第 3 段")
        }
        XCTAssertEqual(split3.duration, engine.metrics.elapsed - restoredDuration, accuracy: 1e-6)

        // 首个恢复后样本只重建位置锚点，位移从第二个样本起累计。
        var incremental = 0.0
        if fed.count > 1 {
            for index in 1..<fed.count {
                incremental += GeoDistance.meters(
                    latitude1: fed[index - 1].latitude,
                    longitude1: fed[index - 1].longitude,
                    latitude2: fed[index].latitude,
                    longitude2: fed[index].longitude
                )
            }
        }
        XCTAssertEqual(engine.metrics.distance.meters, 2500 + incremental, accuracy: 1e-6)
        XCTAssertGreaterThan(engine.metrics.distance.meters, 3000)
        XCTAssertLessThan(engine.metrics.distance.meters, 3100)
    }

    // MARK: - ac-engine-restore-anchor

    func testEngineRestoreAnchorDiscardsEqualTimestampAndAddsElapsedOnly() {
        guard let anchorSample = RunSample(
            latitude: resumeBaseLatitude,
            longitude: resumeBaseLongitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: 900),
            heartRate: nil,
            cadence: nil
        ) else {
            return XCTFail("锚点样本必须合法")
        }
        guard let laterSamePlace = RunSample(
            latitude: resumeBaseLatitude,
            longitude: resumeBaseLongitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: 905),
            heartRate: nil,
            cadence: nil
        ) else {
            return XCTFail("后续样本必须合法")
        }

        let checkpoint = makeCheckpoint(
            state: .paused,
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            lastSample: RunSampleAnchor(sample: anchorSample)
        )
        var engine = RunMetricsEngine(restoring: checkpoint)
        engine.resume(at: anchorSample.timestamp)

        let afterResume = engine.metrics
        _ = engine.ingest(anchorSample)
        XCTAssertEqual(engine.metrics, afterResume, "等时样本必须整条丢弃")

        _ = engine.ingest(laterSamePlace)
        XCTAssertEqual(engine.metrics.distance.meters, afterResume.distance.meters, accuracy: 1e-9)
        XCTAssertEqual(engine.metrics.elapsed, afterResume.elapsed + 5, accuracy: 1e-9)
        XCTAssertEqual(engine.metrics.splits.map(\.index), afterResume.splits.map(\.index))
    }

    // MARK: - ac-engine-restore-no-sample-anchor

    func testEngineRestoreWithoutAnchorUsesFirstSampleAsAnchor() {
        let stream = makeResumeStream(sampleCount: 4, startTimestamp: 0)
        XCTAssertEqual(stream.count, 4)
        let checkpoint = makeCheckpoint(
            state: .paused,
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            lastSample: nil
        )

        var engine = RunMetricsEngine(restoring: checkpoint)
        engine.resume(at: Date(timeIntervalSince1970: 0))

        let first = engine.ingest(stream[0])
        XCTAssertEqual(first.metrics.distance.meters, 2500, accuracy: 1e-9)
        XCTAssertEqual(first.metrics.elapsed, 900, accuracy: 1e-9)
        XCTAssertTrue(first.newlyCompletedSplits.isEmpty)

        let second = engine.ingest(stream[1])
        XCTAssertGreaterThan(second.metrics.distance.meters, 2500)
        XCTAssertEqual(second.metrics.elapsed, 901, accuracy: 1e-9)
    }

    // MARK: - ac-engine-restore-finished

    func testEngineRestoreFinishedIsTerminal() {
        let checkpoint = makeCheckpoint(
            state: .finished,
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            lastSample: makeAnchor()
        )
        var engine = RunMetricsEngine(restoring: checkpoint)
        let before = engine.metrics

        _ = engine.ingest(makeResumeStream(sampleCount: 1, startTimestamp: 900)[0])
        engine.finish(at: Date(timeIntervalSince1970: 1_000))
        engine.start(at: Date(timeIntervalSince1970: 1_100))
        engine.pause(at: Date(timeIntervalSince1970: 1_200))
        engine.resume(at: Date(timeIntervalSince1970: 1_300))

        XCTAssertEqual(engine.metrics, before)
    }

    // MARK: - ac-engine-exposes-last-sample

    func testEngineExposesLastAcceptedSample() {
        let stream = makeResumeStream(sampleCount: 4, startTimestamp: 0)
        var engine = RunMetricsEngine()
        XCTAssertNil(engine.lastAcceptedSample)

        _ = engine.ingest(stream[0])
        XCTAssertEqual(engine.lastAcceptedSample, RunSampleAnchor(sample: stream[0]))

        _ = engine.ingest(stream[1])
        XCTAssertEqual(engine.lastAcceptedSample, RunSampleAnchor(sample: stream[1]))

        // 时间倒退的样本不被接受，锚点保持不变。
        _ = engine.ingest(stream[0])
        XCTAssertEqual(engine.lastAcceptedSample, RunSampleAnchor(sample: stream[1]))
    }

    func testEngineLastAcceptedSampleAcrossRestore() {
        let anchor = makeAnchor()
        let withAnchor = RunMetricsEngine(restoring: makeCheckpoint(lastSample: anchor))
        XCTAssertEqual(withAnchor.lastAcceptedSample, anchor)

        let legacy = RunMetricsEngine(restoring: makeCheckpoint(lastSample: nil))
        XCTAssertNil(legacy.lastAcceptedSample)
    }

    // MARK: - ac-scheduler-restore-no-repeat / default

    func testSchedulerRestoreDoesNotRepeatAnnouncedSplits() {
        var scheduler = AnnouncementScheduler(announcedSplitIndex: 2)
        let splits = [makeSplit(1), makeSplit(2)]

        XCTAssertTrue(scheduler.tick(makeUpdate(splits: splits, newly: splits, elapsed: 600), state: .running).isEmpty)

        let split3 = makeSplit(3)
        let update3 = makeUpdate(splits: splits + [split3], newly: [split3], elapsed: 900)
        let commands = scheduler.tick(update3, state: .running)

        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.trigger, .kilometerCompleted)
        XCTAssertEqual(commands.first?.splitIndex, 3)
        XCTAssertTrue(scheduler.tick(update3, state: .running).isEmpty)
    }

    func testSchedulerRestoreDefaultBehavesLikeFresh() {
        for index in [Int?.none, 0, -5] {
            var scheduler = AnnouncementScheduler(announcedSplitIndex: index ?? 0)
            let split = makeSplit(1)
            let commands = scheduler.tick(makeUpdate(splits: [split], newly: [split], elapsed: 300), state: .running)
            XCTAssertEqual(commands.count, 1)
            XCTAssertEqual(commands.first?.splitIndex, 1)
        }
    }
}
