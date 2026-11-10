import Foundation
import XCTest
import PurePaceRunCore
@testable import PurePace

/// 进程重启恢复的应用级端到端断言（L2，真实临时 checkpoint + 全新 store/orchestrator/ViewModel）。
///
/// 覆盖：恢复距离/时长/分段/最后采样点、resume 后计时与距离连续、坏尾回退上一有效记录、
/// 中间损坏抛 `corruptedCheckpoint`（不得静默零度量）。
@MainActor
final class RunSessionRestoreTests: XCTestCase {
    private let t0: TimeInterval = 1_700_000_000
    private let baseLatitude = 37.3349
    private let baseLongitude = -122.0090
    /// 约 30 米的纬度步长；70 个样本约 2070 米（2 个完整分段）。
    private let step = 0.00027

    // MARK: - 夹具

    private final class FakeLocationSource: RunLocationProviding {
        weak var delegate: RunLocationSourceDelegate?
        private(set) var authorization: RunLocationAuthorization = .authorizedWhenInUse
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var sampleSource: RunSampleSource = .device
        var allowsBackgroundLocationUpdates = false
        var pausesLocationUpdatesAutomatically = false

        func start() {
            startCount += 1
            delegate?.locationSource(self, didChangeAuthorization: authorization)
        }

        func stop() {
            stopCount += 1
        }
    }

    private final class Clock {
        var date: Date
        init(date: Date) {
            self.date = date
        }
    }

    private struct Stores {
        let root: URL
        let checkpoint: RunCheckpointStore
        let archive: RunArchiveStore
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func makeStores() -> Stores {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceRestore-\(UUID().uuidString)", isDirectory: true)
        return Stores(
            root: root,
            checkpoint: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archive: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
    }

    private func removeStores(_ stores: Stores) {
        try? FileManager.default.removeItem(at: stores.root)
    }

    private func makeSample(index: Int) -> RunSample {
        RunSample(
            latitude: baseLatitude + step * Double(index),
            longitude: baseLongitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: t0 + Double(index)),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func feed(_ sample: RunSample, from source: FakeLocationSource) {
        source.delegate?.locationSource(source, didProduce: sample)
    }

    /// 旧进程：跑到 ≥2 个完整分段并落盘 checkpoint；返回后丢弃全部内存实例。
    @discardableResult
    private func runOldProcess(stores: Stores) -> RunSessionViewModel {
        let source = FakeLocationSource()
        let clock = Clock(date: Date(timeIntervalSince1970: t0))
        let viewModel = RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: source,
            now: { clock.date },
            notificationCenter: NotificationCenter()
        )
        viewModel.start()
        for index in 1...70 {
            feed(makeSample(index: index), from: source)
        }
        return viewModel
    }

    /// 新进程：同一文件、全新 store / orchestrator / ViewModel。
    private func restore(
        stores: Stores,
        now: Date
    ) throws -> (viewModel: RunSessionViewModel, source: FakeLocationSource) {
        let freshStore = RunCheckpointStore(fileURL: stores.checkpoint.fileURL)
        let freshArchive = RunArchiveStore(directoryURL: stores.archive.directoryURL)
        let source = FakeLocationSource()
        let clock = Clock(date: now)
        let viewModel = try RunSessionViewModel.makeRestored(
            checkpointStore: freshStore,
            archiveStore: freshArchive,
            locationSource: source,
            notificationCenter: NotificationCenter(),
            now: { clock.date }
        )
        return (viewModel, source)
    }

    private func makeDistance(_ meters: Double) -> RunDistance {
        RunDistance(meters: meters) ?? RunDistance(meters: 0)!
    }

    private func makeSplit(_ index: Int, duration: TimeInterval) -> RunSplit {
        RunSplit(index: index, distance: makeDistance(1000), duration: duration)!
    }

    private func makeCheckpoint(
        meters: Double,
        elapsed: TimeInterval,
        splits: [RunSplit],
        anchorTimestamp: TimeInterval
    ) -> RunCheckpoint {
        RunCheckpoint(
            state: .running,
            completedDistance: makeDistance(meters),
            elapsed: elapsed,
            splits: splits,
            recordedAt: Date(timeIntervalSince1970: anchorTimestamp),
            lastSample: RunSampleAnchor(
                latitude: baseLatitude + step * Double(Int(anchorTimestamp - t0)),
                longitude: baseLongitude,
                timestamp: Date(timeIntervalSince1970: anchorTimestamp)
            )
        )!
    }

    // MARK: - ac-restart-viewmodel-e2e / ac-restart-restores-metrics / last-sample / timer

    func testMakeRestoredFromCheckpointContinuesSession() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        runOldProcess(stores: stores)

        let checkpoint = try XCTUnwrap(try stores.checkpoint.loadLatest())
        XCTAssertEqual(checkpoint.splits.count, 2, "旧进程应已完成 2 个整公里分段")
        XCTAssertNotEqual(checkpoint.completedDistance.meters, 0)

        let restoredProcess = try restore(stores: stores, now: checkpoint.lastSample!.timestamp)
        let restored = restoredProcess.viewModel
        XCTAssertTrue(restored.didRestoreFromCheckpoint)
        XCTAssertEqual(restored.state, .paused)
        XCTAssertEqual(restored.metrics.distance, checkpoint.completedDistance)
        XCTAssertEqual(restored.metrics.elapsed, checkpoint.elapsed, accuracy: 1e-9)
        XCTAssertEqual(restored.metrics.splits.map(\.index), checkpoint.splits.map(\.index))
        for (actual, expected) in zip(restored.metrics.splits, checkpoint.splits) {
            XCTAssertEqual(actual.distance, expected.distance)
            XCTAssertEqual(actual.duration, expected.duration, accuracy: 1e-9)
        }
        XCTAssertNotEqual(restored.metrics.distance.meters, 0)
        XCTAssertNotEqual(restored.metrics.elapsed, 0)

        let restoredMetrics = restored.metrics
        restored.resume()

        // 锚点同时间戳样本被拒：度量不变、去重计数 +1。
        feed(makeSample(index: 70), from: restoredProcess.source)
        XCTAssertEqual(restored.metrics, restoredMetrics)
        XCTAssertEqual(restored.duplicateSampleCount, 1)

        // 第一条晚于锚点的样本只重建位置锚点，不因坐标跳变累计距离。
        feed(makeSample(index: 71), from: restoredProcess.source)
        XCTAssertEqual(restored.metrics.distance, restoredMetrics.distance)
        XCTAssertEqual(restored.metrics.elapsed, restoredMetrics.elapsed + 1, accuracy: 1e-9)

        // 第二条晚于锚点的样本恢复距离累计，计时从恢复值继续。
        feed(makeSample(index: 72), from: restoredProcess.source)
        XCTAssertGreaterThan(restored.metrics.distance.meters, restoredMetrics.distance.meters)
        XCTAssertEqual(restored.metrics.elapsed, restoredMetrics.elapsed + 2, accuracy: 1e-9)
        XCTAssertEqual(restored.state, .running)
    }

    // MARK: - ac-restart-bad-tail（反例：不得以零度量假装恢复）

    func testMakeRestoredBadTailFallsBack() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        runOldProcess(stores: stores)
        let checkpoint = try XCTUnwrap(try stores.checkpoint.loadLatest())

        let handle = try FileHandle(forWritingTo: stores.checkpoint.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"formatVersion\":1,\"state\":\"run".utf8))
        try handle.close()

        let restored = try restore(stores: stores, now: checkpoint.lastSample!.timestamp).viewModel
        XCTAssertTrue(restored.didRestoreFromCheckpoint)
        XCTAssertEqual(restored.metrics.distance, checkpoint.completedDistance)
        XCTAssertEqual(restored.metrics.elapsed, checkpoint.elapsed, accuracy: 1e-9)
        XCTAssertEqual(restored.metrics.splits.count, 2)
    }

    func testRestoreBadTailCounterexample() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        runOldProcess(stores: stores)
        let checkpoint = try XCTUnwrap(try stores.checkpoint.loadLatest())

        let handle = try FileHandle(forWritingTo: stores.checkpoint.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"formatVersion\":1,".utf8))
        try handle.close()

        let restored = try restore(stores: stores, now: checkpoint.lastSample!.timestamp).viewModel
        XCTAssertNotEqual(restored.metrics.distance.meters, 0, "坏尾恢复不得退化为零度量会话")
        XCTAssertEqual(restored.metrics.distance, checkpoint.completedDistance)
    }

    // MARK: - ac-restart-middle-corruption（反例：不得静默零度量）

    func testMakeRestoredMiddleCorruptionThrows() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let first = makeCheckpoint(
            meters: 1000,
            elapsed: 400,
            splits: [makeSplit(1, duration: 400)],
            anchorTimestamp: t0 + 400
        )
        let last = makeCheckpoint(
            meters: 2500,
            elapsed: 900,
            splits: [makeSplit(1, duration: 350), makeSplit(2, duration: 360)],
            anchorTimestamp: t0 + 900
        )
        let firstLine = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
        let lastLine = String(decoding: try JSONEncoder().encode(last), as: UTF8.self)
        try FileManager.default.createDirectory(
            at: stores.checkpoint.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data((firstLine + "\nnot-json\n" + lastLine + "\n").utf8)
            .write(to: stores.checkpoint.fileURL)

        var restored: RunSessionViewModel?
        XCTAssertThrowsError(try { restored = try restore(stores: stores, now: Date(timeIntervalSince1970: t0 + 900)).viewModel }()) { error in
            guard case RunCoreError.corruptedCheckpoint = error else {
                return XCTFail("期望 corruptedCheckpoint，实际 \(error)")
            }
        }
        XCTAssertNil(restored, "中间行损坏时不得静默构造会话（零度量也不行）")
        XCTAssertNotEqual(RunMetrics.initial.distance, last.completedDistance)
    }

    // MARK: - 恢复后归档 startedAt 派生（不改归档契约）

    func testRestoredFinishUsesDerivedStartedAt() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        runOldProcess(stores: stores)
        let checkpoint = try XCTUnwrap(try stores.checkpoint.loadLatest())
        let anchor = try XCTUnwrap(checkpoint.lastSample)

        let restoredProcess = try restore(stores: stores, now: anchor.timestamp)
        let restored = restoredProcess.viewModel
        restored.resume()
        feed(makeSample(index: 71), from: restoredProcess.source)
        feed(makeSample(index: 72), from: restoredProcess.source)
        restored.finish()

        XCTAssertTrue(restored.didSave, "恢复后结束会话必须落盘归档")
        let records = try stores.archive.list()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(
            record.startedAt,
            anchor.timestamp.addingTimeInterval(-checkpoint.elapsed),
            "startedAt 按锚点时间 − 活跃时长派生（下界）"
        )
        XCTAssertEqual(record.activeDuration, checkpoint.elapsed + 2, accuracy: 1e-9)
        XCTAssertEqual(record.samples.count, 2, "恢复后归档只含重启后被接受的样本")
    }
}
