import XCTest
import PurePaceRunCore

/// 计时与采样解耦的验收断言（L1，真实临时文件 JSONL，无 UI）。
///
/// 覆盖：时钟空跑走表（零定位采样）、暂停冻结与恢复续走、零采样结束归档，
/// 以及「时钟冻结时被接受的样本不得推进活跃时长」的反例护栏。
final class RunClockDecouplingTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunClockDecouplingTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeOrchestrator(clock: TestRunClock) -> RunSessionOrchestrator {
        RunSessionOrchestrator(
            checkpointStore: RunCheckpointStore(fileURL: checkpointURL),
            archiveStore: RunArchiveStore(directoryURL: archiveDirectoryURL),
            timeSource: clock
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

    // MARK: - ac-clock-tick

    func testElapsedTicksWithClockAndZeroLocationSamples() {
        let clock = TestRunClock(100)
        var engine = RunMetricsEngine(clock: clock)
        engine.start(at: date(1_700_000_000))

        clock.advance(by: 5.0)

        XCTAssertGreaterThanOrEqual(engine.metrics.elapsed, 4.5)
        XCTAssertEqual(engine.metrics.elapsed, 5.0, accuracy: 1e-9)
        XCTAssertEqual(engine.metrics.distance.meters, 0, "零条定位采样时距离必须为 0")
    }

    // MARK: - ac-clock-pause

    func testPauseFreezesElapsedAndResumeContinues() {
        let clock = TestRunClock()
        var engine = RunMetricsEngine(clock: clock)
        engine.start(at: date(0))

        clock.advance(by: 3.0)
        XCTAssertEqual(engine.metrics.elapsed, 3.0, accuracy: 1e-9)

        engine.pause(at: date(3))
        clock.advance(by: 10.0)
        XCTAssertEqual(engine.metrics.elapsed, 3.0, accuracy: 1e-9)

        engine.resume(at: date(13))
        clock.advance(by: 2.0)
        XCTAssertEqual(engine.metrics.elapsed, 5.0, accuracy: 1e-9)
    }

    // MARK: - ac-finish-empty

    func testFinishWithoutAnySampleArchivesClockDrivenDuration() throws {
        let clock = TestRunClock()
        var orchestrator = makeOrchestrator(clock: clock)
        let t0 = date(1_700_000_000)
        try orchestrator.start(at: t0)
        clock.advance(by: 5.0)

        let record = try XCTUnwrap(
            try orchestrator.finish(at: t0.addingTimeInterval(5)),
            "零采样会话结束必须产出记录"
        )

        XCTAssertEqual(orchestrator.state, .finished)
        XCTAssertEqual(try RunArchiveStore(directoryURL: archiveDirectoryURL).list(), [record])
        XCTAssertGreaterThanOrEqual(record.activeDuration, 4.5)
        XCTAssertEqual(record.activeDuration, 5.0, accuracy: 1e-9)
        XCTAssertTrue(record.samples.isEmpty)
        XCTAssertEqual(record.sampleCount, 0)
        XCTAssertEqual(record.distance.meters, 0)
        XCTAssertFalse(record.hasLocationData, "零采样时不得声称拿到定位")
    }

    // MARK: - 反例护栏：时长绝不来自采样回调

    func testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance() {
        let clock = TestRunClock()
        var engine = RunMetricsEngine(clock: clock)
        engine.start(at: date(0))

        for (index, latitude) in [0.0, 0.001, 0.002].enumerated() {
            _ = engine.ingest(sample(latitude: latitude, at: Double(index)))
        }

        XCTAssertEqual(engine.duplicateSampleCount, 0, "三条严格递增样本必须全部被接受")
        XCTAssertGreaterThan(engine.metrics.distance.meters, 0, "距离确实由采样推进")
        XCTAssertEqual(engine.metrics.elapsed, 0, "时钟冻结时活跃时长恒为 0，绝不来自采样时间戳")
        XCTAssertNil(engine.metrics.averagePace, "活跃时长为 0 时不得伪造平均配速")
    }
}
