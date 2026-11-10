import XCTest
@testable import PurePaceRunCore

/// 单调守卫去重计数的纯逻辑断言（L1，无 IO）。
///
/// 口径：只有「已开始、未暂停、未结束」时命中 `sample.timestamp <= lastTimestamp`
/// 的样本才计入 `duplicateSampleCount`；暂停/未开始的 drop 不计。
final class RunSampleDedupTests: XCTestCase {
    private let base: TimeInterval = 1_700_000_000
    private let baseLatitude = 31.0
    private let step = 0.00027

    private func makeSample(offset: Int, timestamp: TimeInterval? = nil) -> RunSample {
        RunSample(
            latitude: baseLatitude + step * Double(offset),
            longitude: 121.0,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: timestamp ?? base + Double(offset)),
            heartRate: nil,
            cadence: nil
        )!
    }

    // MARK: - 正例：等时/倒退样本 +1 且度量逐项不变

    func testDuplicateAndBackwardSamplesAreDroppedAndCounted() {
        var engine = RunMetricsEngine()
        engine.start(at: Date(timeIntervalSince1970: base))
        for offset in 1...5 {
            _ = engine.ingest(makeSample(offset: offset))
        }
        let before = engine.metrics
        XCTAssertEqual(engine.duplicateSampleCount, 0, "严格递增流不得产生去重计数")

        _ = engine.ingest(makeSample(offset: 5))
        XCTAssertEqual(engine.metrics, before, "等时样本必须整条丢弃")
        XCTAssertEqual(engine.duplicateSampleCount, 1)

        _ = engine.ingest(makeSample(offset: 3))
        XCTAssertEqual(engine.metrics, before, "倒退样本必须整条丢弃")
        XCTAssertEqual(engine.duplicateSampleCount, 2)
    }

    // MARK: - 反例护栏：严格递增流计数恒 0

    func testStrictlyIncreasingStreamStaysAtZeroCounterexample() {
        var engine = RunMetricsEngine()
        engine.start(at: Date(timeIntervalSince1970: base))
        var accepted = 0
        // 首条样本只建立锚点（距离/时长保持 0），从第二条起每条都应推进度量。
        _ = engine.ingest(makeSample(offset: 1))
        accepted += 1
        for offset in 2...20 {
            let metricsBefore = engine.metrics
            _ = engine.ingest(makeSample(offset: offset))
            XCTAssertNotEqual(engine.metrics, metricsBefore, "第 \(offset) 条严格递增样本必须被接受")
            accepted += 1
            XCTAssertEqual(engine.duplicateSampleCount, 0, "被接受的样本不得计入去重计数")
        }
        XCTAssertEqual(accepted, 20)
    }

    // MARK: - 暂停态 drop 不计数

    func testPausedDropDoesNotCount() {
        var engine = RunMetricsEngine()
        engine.start(at: Date(timeIntervalSince1970: base))
        _ = engine.ingest(makeSample(offset: 1))
        _ = engine.ingest(makeSample(offset: 2))
        engine.pause(at: Date(timeIntervalSince1970: base + 2))
        let before = engine.metrics

        _ = engine.ingest(makeSample(offset: 2))
        _ = engine.ingest(makeSample(offset: 3))

        XCTAssertEqual(engine.metrics, before, "暂停态摄入不得推进度量")
        XCTAssertEqual(engine.duplicateSampleCount, 0, "暂停态 drop 不计入去重计数")
    }

    // MARK: - 编排器只读转发

    func testOrchestratorForwardsDuplicateCount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceDedup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let orchestratorStores = (
            checkpoint: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archive: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
        var orchestrator = RunSessionOrchestrator(
            checkpointStore: orchestratorStores.checkpoint,
            archiveStore: orchestratorStores.archive
        )
        try orchestrator.start(at: Date(timeIntervalSince1970: base))
        _ = try orchestrator.ingest(makeSample(offset: 1))
        _ = try orchestrator.ingest(makeSample(offset: 2))
        _ = try orchestrator.ingest(makeSample(offset: 2))

        XCTAssertEqual(orchestrator.duplicateSampleCount, 1)
    }
}
