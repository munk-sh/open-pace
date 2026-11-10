import XCTest
@testable import PurePaceRunCore

/// 编排器级重启恢复断言（L1，真实临时文件 JSONL，无 UI）。
///
/// 覆盖：恢复后度量/状态/锚点、`resume` 后计时与距离连续、锚点及更早样本被拒、
/// 已播报序号不重复播报、坏尾回退上一有效行、中间损坏抛错、派生 `startedAt`。
final class OrchestratorRestoreTests: XCTestCase {
    private var directory: URL!

    private let base: TimeInterval = 1_700_000_000
    private let baseLatitude = 31.2304
    private let baseLongitude = 121.4737
    /// 约 30 米的纬度步长。
    private let step = 0.00027

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        super.tearDown()
    }

    // MARK: - 夹具

    private var fileURL: URL {
        directory.appendingPathComponent("checkpoints/session.jsonl")
    }

    private var archiveURL: URL {
        directory.appendingPathComponent("Runs", isDirectory: true)
    }

    private func makeDistance(_ meters: Double) -> RunDistance {
        guard let distance = RunDistance(meters: meters) else {
            preconditionFailure("测试距离必须合法: \(meters)")
        }
        return distance
    }

    private func makeSplit(_ index: Int, duration: TimeInterval) -> RunSplit {
        guard let split = RunSplit(index: index, distance: makeDistance(1000), duration: duration) else {
            preconditionFailure("测试分段必须合法: \(index)")
        }
        return split
    }

    /// 恢复锚点固定在 `base + 900`，与 `elapsed = 900` 一起派生 `startedAt = base`。
    private var anchorTimestamp: TimeInterval { base + 900 }

    private var anchorDate: Date { Date(timeIntervalSince1970: anchorTimestamp) }

    private func makeAnchor(
        latitude: Double? = nil,
        longitude: Double? = nil,
        timestamp: TimeInterval? = nil
    ) -> RunSampleAnchor {
        guard let anchor = RunSampleAnchor(
            latitude: latitude ?? baseLatitude,
            longitude: longitude ?? baseLongitude,
            timestamp: Date(timeIntervalSince1970: timestamp ?? anchorTimestamp)
        ) else {
            preconditionFailure("测试锚点必须合法")
        }
        return anchor
    }

    private func makeSample(offset: Int) -> RunSample {
        RunSample(
            latitude: baseLatitude + step * Double(offset),
            longitude: baseLongitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: anchorTimestamp + Double(offset)),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func makeCheckpoint(
        state: RunSessionState = .running,
        meters: Double = 2500,
        elapsed: TimeInterval = 900,
        splits: [RunSplit]? = nil,
        lastSample: RunSampleAnchor? = nil,
        announcedSplitIndex: Int? = nil
    ) -> RunCheckpoint {
        guard let checkpoint = RunCheckpoint(
            state: state,
            completedDistance: makeDistance(meters),
            elapsed: elapsed,
            splits: splits ?? [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            recordedAt: anchorDate,
            lastSample: lastSample ?? makeAnchor(),
            announcedSplitIndex: announcedSplitIndex
        ) else {
            preconditionFailure("测试 checkpoint 必须合法")
        }
        return checkpoint
    }

    private func makeOrchestrator(restoring checkpoint: RunCheckpoint) -> RunSessionOrchestrator {
        RunSessionOrchestrator(
            restoring: checkpoint,
            checkpointStore: RunCheckpointStore(fileURL: fileURL),
            archiveStore: RunArchiveStore(directoryURL: archiveURL)
        )
    }

    /// 模拟应用级恢复入口：读回最后一条有效记录；无记录时拒绝构造（不允许零度量假装成功）。
    private func makeOrchestratorFromStore() throws -> RunSessionOrchestrator {
        let store = RunCheckpointStore(fileURL: fileURL)
        guard let checkpoint = try store.loadLatest() else {
            throw RunCoreError.corruptedCheckpoint("恢复入口不得以空记录构造零度量会话")
        }
        return makeOrchestrator(restoring: checkpoint)
    }

    private func writeRaw(_ contents: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
    }

    private func encodedLine(_ checkpoint: RunCheckpoint) throws -> String {
        String(decoding: try JSONEncoder().encode(checkpoint), as: UTF8.self)
    }

    // MARK: - ac-restart-restores-metrics

    func testRestoreRebuildsStateMetricsAndSplits() {
        let checkpoint = makeCheckpoint()
        let orchestrator = makeOrchestrator(restoring: checkpoint)

        XCTAssertEqual(orchestrator.state, .paused, "running/paused checkpoint 恢复为 paused")
        XCTAssertEqual(orchestrator.metrics.distance, checkpoint.completedDistance)
        XCTAssertEqual(orchestrator.metrics.elapsed, checkpoint.elapsed, accuracy: 1e-9)
        XCTAssertEqual(orchestrator.metrics.splits, checkpoint.splits)
        XCTAssertEqual(orchestrator.metrics.completedKilometers, 2)
        XCTAssertNotEqual(orchestrator.metrics.distance.meters, 0)
        XCTAssertNotEqual(orchestrator.metrics.elapsed, 0)
    }

    // MARK: - ac-restart-timer-continues（反例：不得重置计时）

    func testRestoreMustNotResetTimerCounterexample() throws {
        var orchestrator = makeOrchestrator(restoring: makeCheckpoint())
        let restoredElapsed = orchestrator.metrics.elapsed
        let restoredDistance = orchestrator.metrics.distance

        try orchestrator.resume(at: anchorDate)
        _ = try orchestrator.ingest(makeSample(offset: 2))

        XCTAssertNotEqual(orchestrator.metrics.elapsed, 0, "恢复后计时不得归零")
        XCTAssertGreaterThan(orchestrator.metrics.elapsed, restoredElapsed)
        XCTAssertEqual(orchestrator.metrics.elapsed, restoredElapsed + 2, accuracy: 1e-6)
        XCTAssertEqual(orchestrator.metrics.distance, restoredDistance, "首个恢复样本只重建位置锚点")

        _ = try orchestrator.ingest(makeSample(offset: 3))
        XCTAssertGreaterThan(orchestrator.metrics.distance.meters, restoredDistance.meters)
    }

    // MARK: - ac-restart-last-sample（反例：锚点及更早样本被拒）

    func testRestoreRejectsSampleAtOrBeforeAnchorCounterexample() throws {
        var orchestrator = makeOrchestrator(restoring: makeCheckpoint())
        let restoredMetrics = orchestrator.metrics

        try orchestrator.resume(at: anchorDate)
        _ = try orchestrator.ingest(makeSample(offset: 0))
        _ = try orchestrator.ingest(makeSample(offset: -1))

        XCTAssertEqual(orchestrator.metrics, restoredMetrics, "锚点及更早样本不得改变度量")
        XCTAssertEqual(orchestrator.duplicateSampleCount, 2)
        XCTAssertTrue(orchestrator.acceptedSamples.isEmpty, "锚点及更早样本不得污染归档序列")
    }

    // MARK: - 已播报序号恢复，不重复播报

    func testRestorePreservesAnnouncedSplitIndexWithoutReannouncing() throws {
        var orchestrator = makeOrchestrator(
            restoring: makeCheckpoint(announcedSplitIndex: 2)
        )
        let resumeUpdate = try orchestrator.resume(at: anchorDate)
        XCTAssertTrue(resumeUpdate.announcements.isEmpty, "恢复后不得补播已播的第 1/2 公里")

        var announced: [Int] = []
        for offset in 1...25 {
            let update = try orchestrator.ingest(makeSample(offset: offset))
            announced.append(contentsOf: update.announcements.map(\.splitIndex))
        }
        XCTAssertEqual(announced, [3], "恢复后跨过的新公里只播报一次")
    }

    // MARK: - ac-restart-bad-tail

    func testBadTailFallsBackToPreviousValidRecord() throws {
        let first = makeCheckpoint(meters: 1000, elapsed: 400, splits: [makeSplit(1, duration: 400)])
        let second = makeCheckpoint()
        let firstLine = try encodedLine(first)
        let secondLine = try encodedLine(second)
        try writeRaw(firstLine + "\n" + secondLine + "\n"
            + "{\"formatVersion\":1,\"state\":\"run")

        let orchestrator = try makeOrchestratorFromStore()
        XCTAssertEqual(orchestrator.metrics.distance, second.completedDistance)
        XCTAssertEqual(orchestrator.metrics.elapsed, second.elapsed, accuracy: 1e-9)
        XCTAssertEqual(orchestrator.metrics.splits, second.splits)
    }

    // MARK: - ac-restart-middle-corruption（反例：不得零度量假装成功）

    func testMidCorruptionThrowsInsteadOfZeroMetricRestore() throws {
        let first = makeCheckpoint(meters: 1000, elapsed: 400, splits: [makeSplit(1, duration: 400)])
        let last = makeCheckpoint()
        let firstLine = try encodedLine(first)
        let lastLine = try encodedLine(last)
        try writeRaw(firstLine + "\nnot-json\n" + lastLine + "\n")

        var restored: RunSessionOrchestrator?
        XCTAssertThrowsError(try { restored = try makeOrchestratorFromStore() }()) { error in
            guard case let RunCoreError.corruptedCheckpoint(reason) = error else {
                return XCTFail("期望 corruptedCheckpoint，实际 \(error)")
            }
            XCTAssertFalse(reason.isEmpty)
        }
        XCTAssertNil(restored, "中间行损坏时不得静默构造会话（零度量也不行）")
        XCTAssertNotEqual(RunMetrics.initial.distance, last.completedDistance)
    }

    // MARK: - 派生 startedAt 与恢复后归档样本

    func testRestoredFinishUsesDerivedStartedAt() throws {
        var orchestrator = makeOrchestrator(restoring: makeCheckpoint())
        try orchestrator.resume(at: anchorDate)
        _ = try orchestrator.ingest(makeSample(offset: 2))
        _ = try orchestrator.ingest(makeSample(offset: 3))
        _ = try orchestrator.ingest(makeSample(offset: 4))

        let finishDate = Date(timeIntervalSince1970: anchorTimestamp + 4)
        let record = try XCTUnwrap(try orchestrator.finish(at: finishDate))

        XCTAssertEqual(record.startedAt, Date(timeIntervalSince1970: base))
        XCTAssertEqual(record.activeDuration, 904, accuracy: 1e-6)
        XCTAssertEqual(record.samples.map(\.timestamp.timeIntervalSince1970), [anchorTimestamp + 2, anchorTimestamp + 3, anchorTimestamp + 4])
        XCTAssertEqual(try RunCheckpointStore(fileURL: fileURL).loadAll(), [])
    }
}
