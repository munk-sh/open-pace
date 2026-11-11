import Foundation
import UIKit
import XCTest
import PurePaceRunCore
@testable import PurePace

/// 锁屏区间（protected-data 锚点）的应用层断言（L2，注入通知中心 + 注入时钟 + fake 采样源）。
///
/// 阈值先定后测：fixture 固定 1.0 s 采样间隔 × 2 倍系统调度抖动容差 = 2.0 s；
/// 该阈值只用于模拟器进程内采样连续性断言，不构成真机采样频率承诺。
@MainActor
final class RunSessionLockTests: XCTestCase {
    static let fixtureSampleInterval: TimeInterval = 1.0
    static let maximumSampleGapSeconds: TimeInterval = 2.0

    private let t0: TimeInterval = 1_700_000_000
    private let baseLatitude = 37.3349
    private let baseLongitude = -122.0090
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

    private func makeStores() -> Stores {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceLock-\(UUID().uuidString)", isDirectory: true)
        return Stores(
            root: root,
            checkpoint: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archive: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
    }

    private func removeStores(_ stores: Stores) {
        try? FileManager.default.removeItem(at: stores.root)
    }

    private struct System {
        let stores: Stores
        let source: FakeLocationSource
        let clock: Clock
        let center: NotificationCenter
        let viewModel: RunSessionViewModel
    }

    private func makeSystem() -> System {
        let stores = makeStores()
        let source = FakeLocationSource()
        let clock = Clock(date: Date(timeIntervalSince1970: t0))
        let center = NotificationCenter()
        let viewModel = RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: source,
            countdownDuration: 0,
            now: { clock.date },
            notificationCenter: center
        )
        return System(stores: stores, source: source, clock: clock, center: center, viewModel: viewModel)
    }

    private func makeSample(index: Int, latitudeOffset: Double = 0) -> RunSample {
        RunSample(
            latitude: baseLatitude + step * Double(index) + latitudeOffset,
            longitude: baseLongitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: t0 + Double(index) * Self.fixtureSampleInterval),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func feed(_ sample: RunSample, from system: System) {
        system.source.delegate?.locationSource(system.source, didProduce: sample)
    }

    private func postLock(_ system: System, locked: Bool) {
        let name = locked
            ? UIApplication.protectedDataWillBecomeUnavailableNotification
            : UIApplication.protectedDataDidBecomeAvailableNotification
        system.center.post(name: name, object: nil)
    }

    private func lineCount(_ stores: Stores) throws -> Int {
        guard FileManager.default.fileExists(atPath: stores.checkpoint.fileURL.path) else { return 0 }
        let data = try Data(contentsOf: stores.checkpoint.fileURL)
        return data.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
    }

    // MARK: - ac-lock-running-continues

    func testLockRunningContinuesWithMonotonicSamples() {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        for index in 1...5 {
            feed(makeSample(index: index), from: system)
        }

        system.clock.date = Date(timeIntervalSince1970: t0 + 6)
        postLock(system, locked: true)

        var previous = system.viewModel.metrics
        for index in 6...20 {
            feed(makeSample(index: index), from: system)
            XCTAssertEqual(system.viewModel.state, .running, "锁定期间不得发生任何状态迁移")
            XCTAssertGreaterThan(system.viewModel.metrics.elapsed, previous.elapsed)
            XCTAssertGreaterThan(system.viewModel.metrics.distance.meters, previous.distance.meters)
            previous = system.viewModel.metrics
        }
        XCTAssertEqual(system.viewModel.metrics.splits.count, 0, "本夹具距离不足以完成分段")
    }

    // MARK: - ac-lock-sample-cadence

    func testLockSampleCadenceWithinThreshold() throws {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        system.clock.date = Date(timeIntervalSince1970: t0 + 1)
        postLock(system, locked: true)
        for index in 1...12 {
            feed(makeSample(index: index), from: system)
        }

        let timestamps = try system.stores.checkpoint.loadAll().compactMap { $0.lastSample?.timestamp }
        XCTAssertGreaterThanOrEqual(timestamps.count, 12)
        for (earlier, later) in zip(timestamps, timestamps.dropFirst()) {
            XCTAssertGreaterThan(later, earlier, "锁定区间内样本时间戳必须严格递增")
            XCTAssertLessThanOrEqual(
                later.timeIntervalSince(earlier),
                Self.maximumSampleGapSeconds,
                "相邻样本空洞不得超过预先写定的 \(Self.maximumSampleGapSeconds)s"
            )
        }
    }

    // MARK: - ac-lock-dedup-samples（正例 + 反例同 commit）

    func testDuplicateTimestampSampleIsDroppedAndCounted() {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        system.clock.date = Date(timeIntervalSince1970: t0 + 1)
        postLock(system, locked: true)
        for index in 1...5 {
            feed(makeSample(index: index), from: system)
        }

        let before = system.viewModel.metrics
        let countBefore = system.viewModel.duplicateSampleCount
        XCTAssertEqual(countBefore, 0)

        feed(makeSample(index: 5, latitudeOffset: 0.001), from: system)

        XCTAssertEqual(system.viewModel.metrics, before, "等时样本必须整条丢弃")
        XCTAssertEqual(system.viewModel.duplicateSampleCount, countBefore + 1)
    }

    func testFullDuplicateSequenceIsDroppedAndCountMatches() {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        system.clock.date = Date(timeIntervalSince1970: t0 + 1)
        postLock(system, locked: true)
        for index in 1...5 {
            feed(makeSample(index: index), from: system)
        }

        let before = system.viewModel.metrics
        let countBefore = system.viewModel.duplicateSampleCount
        for index in 1...5 {
            feed(makeSample(index: index), from: system)
        }

        XCTAssertEqual(system.viewModel.metrics, before, "整段重复序列必须全部丢弃")
        XCTAssertEqual(system.viewModel.duplicateSampleCount, countBefore + 5)
    }

    // MARK: - ac-lock-unlock-no-replay-no-reset

    func testUnlockDoesNotReplayOrResetElapsed() throws {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        for index in 1...3 {
            feed(makeSample(index: index), from: system)
        }
        system.clock.date = Date(timeIntervalSince1970: t0 + 4)
        postLock(system, locked: true)
        for index in 4...6 {
            feed(makeSample(index: index), from: system)
        }

        let lockedState = system.viewModel.state
        let lockedMetrics = system.viewModel.metrics
        let linesBeforeUnlock = try lineCount(system.stores)

        system.clock.date = Date(timeIntervalSince1970: t0 + 9)
        postLock(system, locked: false)

        XCTAssertEqual(system.viewModel.state, lockedState)
        XCTAssertEqual(system.viewModel.metrics, lockedMetrics)
        XCTAssertEqual(try lineCount(system.stores), linesBeforeUnlock, "解锁事件本身不得增加 checkpoint 行")

        feed(makeSample(index: 7), from: system)
        XCTAssertEqual(
            system.viewModel.metrics.elapsed,
            lockedMetrics.elapsed + Self.fixtureSampleInterval,
            accuracy: 1e-9,
            "解锁后按样本时间戳继续累加，不得按 tUnlock 重算"
        )
        XCTAssertGreaterThan(system.viewModel.metrics.distance.meters, lockedMetrics.distance.meters)
    }

    func testUnlockMustNotResetElapsedCounterexample() throws {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        for index in 1...3 {
            feed(makeSample(index: index), from: system)
        }
        system.clock.date = Date(timeIntervalSince1970: t0 + 4)
        postLock(system, locked: true)
        for index in 4...6 {
            feed(makeSample(index: index), from: system)
        }
        let lockedElapsed = system.viewModel.metrics.elapsed

        system.clock.date = Date(timeIntervalSince1970: t0 + 20)
        postLock(system, locked: false)
        feed(makeSample(index: 7), from: system)

        XCTAssertNotEqual(system.viewModel.metrics.elapsed, 0, "解锁后计时不得归零")
        XCTAssertGreaterThan(system.viewModel.metrics.elapsed, lockedElapsed, "解锁后计时不得重算变小")
        XCTAssertEqual(
            system.viewModel.metrics.elapsed,
            lockedElapsed + Self.fixtureSampleInterval,
            accuracy: 1e-9,
            "解锁后的时间增量只取样本间隔，与 tUnlock 无关"
        )
    }

    // MARK: - ac-lock-handler-observable

    func testProtectedDataLockStateIsObservable() {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        XCTAssertFalse(system.viewModel.isProtectedDataLocked)
        XCTAssertNil(system.viewModel.protectedDataUnavailableSince)

        let lockDate = Date(timeIntervalSince1970: t0 + 4)
        system.clock.date = lockDate
        postLock(system, locked: true)
        XCTAssertTrue(system.viewModel.isProtectedDataLocked)
        XCTAssertEqual(system.viewModel.protectedDataUnavailableSince, lockDate)

        system.clock.date = Date(timeIntervalSince1970: t0 + 9)
        postLock(system, locked: false)
        XCTAssertFalse(system.viewModel.isProtectedDataLocked)
        XCTAssertNil(system.viewModel.protectedDataUnavailableSince)
    }

    func testLockStateMissingCounterexample() {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        XCTAssertFalse(system.viewModel.isProtectedDataLocked, "锁前必须未锁定")

        postLock(system, locked: true)
        let violation = !system.viewModel.isProtectedDataLocked
        XCTAssertFalse(violation, "锁屏通知后锁状态缺失即判红")
    }

    func testLockMustNotPauseCounterexample() {
        let system = makeSystem()
        defer { removeStores(system.stores) }
        system.viewModel.start()
        postLock(system, locked: true)
        feed(makeSample(index: 1), from: system)
        feed(makeSample(index: 2), from: system)

        let violation = system.viewModel.state == .paused || system.viewModel.state == .finished
        XCTAssertFalse(violation, "锁屏不得自动 pause/finish")
        XCTAssertEqual(system.viewModel.state, .running)
        XCTAssertEqual(system.source.stopCount, 0, "锁屏不得停止定位")
    }
}
