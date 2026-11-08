import XCTest
import PurePaceRunCore
@testable import PurePace

@MainActor
final class RunSessionViewModelTests: XCTestCase {
    private final class FakeLocationSource: RunLocationProviding {
        weak var delegate: RunLocationSourceDelegate?
        private(set) var authorization: RunLocationAuthorization = .authorizedWhenInUse
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start() {
            startCount += 1
            delegate?.locationSource(self, didChangeAuthorization: authorization)
        }

        func stop() {
            stopCount += 1
        }
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testInitialSnapshotIsEmpty() {
        let stores = makeStores()
        defer { removeStores(stores) }
        let viewModel = makeViewModel(stores: stores, clock: Clock(date: startDate))

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.metrics.distance.meters, 0)
        XCTAssertEqual(viewModel.metrics.elapsed, 0)
        XCTAssertNil(viewModel.metrics.currentPace)
        XCTAssertNil(viewModel.metrics.averagePace)
        XCTAssertEqual(viewModel.metrics.completedKilometers, 0)
        XCTAssertFalse(viewModel.didSave)
    }

    func testMetricsMatchOrchestratorForSameSamples() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock)

        let expectedStores = makeStores(suffix: "expected")
        defer { removeStores(expectedStores) }
        var expected = RunSessionOrchestrator(
            checkpointStore: expectedStores.checkpoint,
            archiveStore: expectedStores.archive
        )

        viewModel.start()
        try expected.start(at: startDate)

        for (offset, sample) in samples().enumerated() {
            viewModel.ingest(sample)
            _ = try expected.ingest(sample)
            XCTAssertEqual(viewModel.metrics, expected.metrics, "第 \(offset + 1) 条采样后的度量不一致")
        }

        XCTAssertEqual(viewModel.state, .running)
        XCTAssertEqual(viewModel.metrics.distance, expected.metrics.distance)
        XCTAssertEqual(viewModel.metrics.elapsed, expected.metrics.elapsed)
        XCTAssertEqual(viewModel.metrics.averagePace, expected.metrics.averagePace)
        XCTAssertEqual(viewModel.metrics.currentPace, expected.metrics.currentPace)
        XCTAssertEqual(viewModel.metrics.completedKilometers, expected.metrics.completedKilometers)
    }

    func testPauseFreezesDistanceElapsedAndPace() {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock)

        viewModel.start()
        viewModel.ingest(sample(latitude: baseLatitude, timestamp: t0 + 1))
        viewModel.ingest(sample(latitude: baseLatitude + step, timestamp: t0 + 2))
        viewModel.ingest(sample(latitude: baseLatitude + step * 2, timestamp: t0 + 3))

        clock.date = startDate.addingTimeInterval(4)
        viewModel.pause()
        let frozenDistance = viewModel.metrics.distance
        let frozenElapsed = viewModel.metrics.elapsed
        XCTAssertFalse(frozenDistance.meters == 0)
        XCTAssertNil(viewModel.metrics.currentPace)

        viewModel.ingest(sample(latitude: baseLatitude + step * 30, timestamp: t0 + 5))
        viewModel.ingest(sample(latitude: baseLatitude + step * 60, timestamp: t0 + 6))

        XCTAssertEqual(viewModel.metrics.distance, frozenDistance)
        XCTAssertEqual(viewModel.metrics.elapsed, frozenElapsed)
        XCTAssertNil(viewModel.metrics.currentPace)
        XCTAssertEqual(viewModel.state, .paused)
    }

    func testResumeRebuildsAnchorThenGrows() {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock)

        viewModel.start()
        viewModel.ingest(sample(latitude: baseLatitude, timestamp: t0 + 1))
        viewModel.ingest(sample(latitude: baseLatitude + step, timestamp: t0 + 2))

        clock.date = startDate.addingTimeInterval(3)
        viewModel.pause()
        let pausedDistance = viewModel.metrics.distance
        let pausedElapsed = viewModel.metrics.elapsed

        clock.date = startDate.addingTimeInterval(10)
        viewModel.resume()
        XCTAssertEqual(viewModel.state, .running)

        // 跨暂停空档的位移不累计，只重建位置锚点。
        viewModel.ingest(sample(latitude: baseLatitude + step * 100, timestamp: t0 + 11))
        XCTAssertEqual(viewModel.metrics.distance, pausedDistance)
        XCTAssertGreaterThan(viewModel.metrics.elapsed, pausedElapsed)

        let anchorTime = viewModel.metrics.elapsed
        viewModel.ingest(sample(latitude: baseLatitude + step * 101, timestamp: t0 + 12))
        XCTAssertGreaterThan(viewModel.metrics.distance.meters, pausedDistance.meters)
        XCTAssertGreaterThan(viewModel.metrics.elapsed, anchorTime)
    }

    func testFinishArchivesExactlyOnce() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock)

        viewModel.start()
        viewModel.ingest(sample(latitude: baseLatitude, timestamp: t0 + 1))
        viewModel.ingest(sample(latitude: baseLatitude + step, timestamp: t0 + 2))
        XCTAssertFalse(viewModel.didSave)

        clock.date = startDate.addingTimeInterval(3)
        viewModel.finish()
        XCTAssertTrue(viewModel.didSave)
        XCTAssertEqual(viewModel.state, .finished)

        let archived = try stores.archive.list()
        XCTAssertEqual(archived.count, 1)
        let record = try XCTUnwrap(archived.first)
        XCTAssertEqual(record.startedAt, startDate)
        XCTAssertEqual(record.endedAt, startDate.addingTimeInterval(3))
        XCTAssertEqual(record.distance, viewModel.metrics.distance)
        XCTAssertEqual(record.activeDuration, viewModel.metrics.elapsed)

        viewModel.finish()
        viewModel.finish()
        XCTAssertEqual(try stores.archive.list().count, 1)
        XCTAssertEqual(viewModel.savedCount, 1)
    }

    func testLocationSamplesDriveViewModel() {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let source = FakeLocationSource()
        let viewModel = RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: source,
            now: { clock.date }
        )

        viewModel.onAppear()
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(viewModel.authorization, .authorizedWhenInUse)

        viewModel.start()
        for sample in samples() {
            source.delegate?.locationSource(source, didProduce: sample)
        }

        XCTAssertEqual(viewModel.state, .running)
        XCTAssertGreaterThan(viewModel.metrics.distance.meters, 0)
        XCTAssertGreaterThan(viewModel.metrics.elapsed, 0)
    }

    // MARK: - 夹具

    private let t0: TimeInterval = 1_700_000_000
    private var startDate: Date { Date(timeIntervalSince1970: t0) }
    private let baseLatitude = 37.3349
    private let baseLongitude = -122.0090
    /// 约 30 米的纬度步长。
    private let step = 0.00027

    private struct Stores {
        let root: URL
        let checkpoint: RunCheckpointStore
        let archive: RunArchiveStore
    }

    private final class Clock {
        var date: Date
        init(date: Date) {
            self.date = date
        }
    }

    private func makeStores(suffix: String = "vm") -> Stores {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceVM-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        return Stores(
            root: root,
            checkpoint: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archive: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
    }

    private func removeStores(_ stores: Stores) {
        try? FileManager.default.removeItem(at: stores.root)
    }

    private func makeViewModel(stores: Stores, clock: Clock) -> RunSessionViewModel {
        RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: FakeLocationSource(),
            now: { clock.date }
        )
    }

    private func sample(latitude: Double, timestamp: TimeInterval) -> RunSample {
        RunSample(
            latitude: latitude,
            longitude: baseLongitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: timestamp),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func samples() -> [RunSample] {
        (1...6).map { index in
            sample(latitude: baseLatitude + step * Double(index), timestamp: t0 + Double(index))
        }
    }
}
