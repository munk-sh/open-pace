import Foundation
import XCTest
import PurePaceRunCore
@testable import PurePace

/// 第 4 波会话契约的 App 侧 L1 断言：倒计时、结束保存/丢弃、定位两态与文案入口。
@MainActor
final class RunSessionContractTests: XCTestCase {
    private let t0: TimeInterval = 1_700_000_000
    private let baseLatitude = 37.3349
    private let baseLongitude = -122.0090
    /// 约 30 米的纬度步长。
    private let step = 0.00027

    // MARK: - 夹具

    private final class FakeLocationSource: RunLocationProviding {
        weak var delegate: RunLocationSourceDelegate?
        var authorization: RunLocationAuthorization = .authorizedWhenInUse
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

        func report(_ authorization: RunLocationAuthorization) {
            self.authorization = authorization
            delegate?.locationSource(self, didChangeAuthorization: authorization)
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

    // MARK: - ac-countdown-before-running

    func testStartEntersCountdownWithZeroMetricsAndNoRecords() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock)

        viewModel.start()

        XCTAssertEqual(viewModel.state, .ready, "开始后先进入倒计时，而不是记录态")
        XCTAssertTrue(viewModel.isCountingDown)
        XCTAssertEqual(viewModel.countdownRemaining, RunStartCountdown.defaultDuration)
        XCTAssertEqual(viewModel.metrics, .initial)
        XCTAssertTrue(viewModel.acceptedSamples.isEmpty)
        XCTAssertEqual(viewModel.runSampleCount, 0)
        XCTAssertEqual(try checkpointCount(stores), 0)
        XCTAssertEqual(try stores.archive.list().count, 0)

        clock.date = startDate.addingTimeInterval(1)
        viewModel.advanceCountdown()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertTrue(viewModel.isCountingDown)
        let firstRemaining = viewModel.countdownRemaining
        XCTAssertLessThan(firstRemaining, RunStartCountdown.defaultDuration)

        clock.date = startDate.addingTimeInterval(2)
        viewModel.advanceCountdown()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertLessThan(viewModel.countdownRemaining, firstRemaining, "剩余时间必须随时钟单调递减")

        clock.date = startDate.addingTimeInterval(RunStartCountdown.defaultDuration)
        viewModel.advanceCountdown()
        XCTAssertEqual(viewModel.state, .running, "到点后才真正开始记录")
        XCTAssertFalse(viewModel.isCountingDown)
        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertEqual(viewModel.metrics.elapsed, 0, "计时从 0 起算")
        XCTAssertEqual(viewModel.metrics.distance.meters, 0, "距离从 0 起算")
    }

    // MARK: - ac-countdown-cancel-zero

    func testCancelCountdownLeavesNoTraceAndIsReentrant() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let source = FakeLocationSource()
        let viewModel = makeViewModel(stores: stores, clock: clock, source: source)

        viewModel.start()
        clock.date = startDate.addingTimeInterval(1)
        viewModel.advanceCountdown()
        viewModel.cancelCountdown()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertFalse(viewModel.isCountingDown)
        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertEqual(viewModel.metrics, .initial)
        XCTAssertTrue(viewModel.acceptedSamples.isEmpty)
        XCTAssertEqual(viewModel.runSampleCount, 0)
        XCTAssertEqual(try checkpointCount(stores), 0)
        XCTAssertEqual(try stores.archive.list().count, 0)
        XCTAssertFalse(viewModel.didSave)

        // 可重入：取消后立刻可以再次进入倒计时，无断头路。
        viewModel.start()
        XCTAssertTrue(viewModel.isCountingDown)
        XCTAssertEqual(viewModel.countdownRemaining, RunStartCountdown.defaultDuration)

        viewModel.cancelCountdown()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertFalse(viewModel.isCountingDown)
    }

    // MARK: - ac-countdown-no-samples

    func testCountdownDropsLocationSamples() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let source = FakeLocationSource()
        let viewModel = makeViewModel(stores: stores, clock: clock, source: source)

        viewModel.start()
        for sample in samples(count: 3) {
            source.delegate?.locationSource(source, didProduce: sample)
        }

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.metrics, .initial, "倒计时期间度量不得变化")
        XCTAssertEqual(viewModel.runSampleCount, 0, "倒计时期间不计数采样")
        XCTAssertTrue(viewModel.acceptedSamples.isEmpty, "倒计时期间不得进归档序列")
        XCTAssertEqual(viewModel.duplicateSampleCount, 0)
        XCTAssertEqual(try checkpointCount(stores), 0, "倒计时期间不得写 checkpoint")
        XCTAssertEqual(try stores.archive.list().count, 0)

        // 到点后的采样必须正常计数与摄入，证明是「门」而不是永久丢弃。
        clock.date = startDate.addingTimeInterval(RunStartCountdown.defaultDuration)
        viewModel.advanceCountdown()
        XCTAssertEqual(viewModel.state, .running)
        source.delegate?.locationSource(source, didProduce: sample(index: 10, secondsAfterStart: 1))
        XCTAssertEqual(viewModel.runSampleCount, 1)
        XCTAssertEqual(viewModel.acceptedSamples.count, 1)
    }

    // MARK: - ac-countdown-no-early-complete

    func testAdvanceBeforeDeadlineNeverStartsRecording() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock)

        viewModel.start()
        for offset in stride(from: 0.0, to: RunStartCountdown.defaultDuration, by: 0.25) {
            clock.date = startDate.addingTimeInterval(offset)
            viewModel.advanceCountdown()
            XCTAssertEqual(viewModel.state, .ready, "早于 deadline 不得进入记录态（offset=\(offset)）")
            XCTAssertTrue(viewModel.isCountingDown)
        }

        XCTAssertEqual(viewModel.metrics, .initial)
        XCTAssertTrue(viewModel.acceptedSamples.isEmpty)
        XCTAssertEqual(viewModel.runSampleCount, 0)
        XCTAssertEqual(try checkpointCount(stores), 0)
        XCTAssertEqual(try stores.archive.list().count, 0)
    }

    // MARK: - ac-finish-awaits-decision

    func testFinishFromRunningAwaitsDecisionWithoutArchiving() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock, countdownDuration: 0)

        viewModel.start()
        XCTAssertEqual(viewModel.state, .running)
        for sample in samples(count: 2) {
            viewModel.ingest(sample)
        }
        let metricsAtFinish = viewModel.metrics
        let acceptedAtFinish = viewModel.acceptedSamples
        XCTAssertGreaterThan(try checkpointCount(stores), 0)

        clock.date = startDate.addingTimeInterval(10)
        viewModel.finish()

        XCTAssertEqual(viewModel.state, .finished)
        XCTAssertFalse(viewModel.didSave, "结束不得直接落盘")
        XCTAssertNil(viewModel.decisionErrorMessage)
        XCTAssertEqual(viewModel.metrics, metricsAtFinish, "结束快照与结束时刻度量逐项一致")
        XCTAssertEqual(viewModel.acceptedSamples, acceptedAtFinish)
        XCTAssertEqual(try stores.archive.list().count, 0)
        XCTAssertEqual(try checkpointCount(stores), 0, "结束后清 checkpoint 且不再追加")

        // 结束后继续到达的采样不得推进度量或追加 checkpoint。
        viewModel.ingest(sample(index: 50, secondsAfterStart: 11))
        XCTAssertEqual(viewModel.metrics, metricsAtFinish)
        XCTAssertEqual(try checkpointCount(stores), 0)
    }

    func testFinishFromPausedAwaitsDecisionAndSavedRecordMatchesSnapshot() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock, countdownDuration: 0)

        viewModel.start()
        for sample in samples(count: 2) {
            viewModel.ingest(sample)
        }
        clock.date = startDate.addingTimeInterval(5)
        viewModel.pause()
        let metricsAtPause = viewModel.metrics

        clock.date = startDate.addingTimeInterval(10)
        viewModel.finish()
        XCTAssertEqual(viewModel.state, .finished)
        XCTAssertEqual(try stores.archive.list().count, 0)
        XCTAssertEqual(viewModel.metrics, metricsAtPause)

        viewModel.saveFinished()
        let record = try XCTUnwrap(try stores.archive.list().first)
        XCTAssertEqual(record.startedAt, startDate)
        XCTAssertEqual(record.endedAt, startDate.addingTimeInterval(10))
        XCTAssertEqual(record.distance, metricsAtPause.distance)
        XCTAssertEqual(record.activeDuration, metricsAtPause.elapsed)
        XCTAssertEqual(record.splits, metricsAtPause.splits)
        XCTAssertEqual(record.samples, viewModel.acceptedSamples)
    }

    // MARK: - ac-discard-no-archive

    func testDiscardKeepsArchiveEmptyAndRestartsClean() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock, countdownDuration: 0)

        viewModel.start()
        for sample in samples(count: 3) {
            viewModel.ingest(sample)
        }
        clock.date = startDate.addingTimeInterval(10)
        viewModel.finish()
        viewModel.discardFinished()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.metrics, .initial, "丢弃后度量全零")
        XCTAssertTrue(viewModel.acceptedSamples.isEmpty)
        XCTAssertEqual(viewModel.runSampleCount, 0)
        XCTAssertEqual(viewModel.duplicateSampleCount, 0)
        XCTAssertFalse(viewModel.didSave)
        XCTAssertEqual(try stores.archive.list().count, 0)
        XCTAssertEqual(try checkpointCount(stores), 0)

        // 新会话正常从 0 累计，不残留上一跑次。
        clock.date = startDate.addingTimeInterval(20)
        viewModel.start()
        XCTAssertEqual(viewModel.state, .running)
        viewModel.ingest(sample(index: 1, secondsAfterStart: 21))
        XCTAssertEqual(viewModel.metrics.distance.meters, 0)
        viewModel.ingest(sample(index: 2, secondsAfterStart: 22))
        XCTAssertGreaterThan(viewModel.metrics.distance.meters, 0)
        XCTAssertEqual(viewModel.metrics.completedKilometers, 0)
    }

    // MARK: - ac-save-once

    func testSaveArchivesExactlyOnce() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock, countdownDuration: 0)

        viewModel.start()
        viewModel.ingest(sample(index: 1, secondsAfterStart: 1))
        viewModel.ingest(sample(index: 2, secondsAfterStart: 2))
        clock.date = startDate.addingTimeInterval(10)
        viewModel.finish()

        viewModel.saveFinished()
        XCTAssertTrue(viewModel.didSave)
        XCTAssertEqual(viewModel.savedCount, 1)
        let first = try stores.archive.list()
        XCTAssertEqual(first.count, 1)

        viewModel.saveFinished()
        viewModel.saveFinished()
        XCTAssertEqual(try stores.archive.list(), first, "再次保存不新增、不重写文件")
        XCTAssertEqual(viewModel.savedCount, 1, "VM 侧保存成功计数恒为 1")
    }

    // MARK: - ac-save-failure-retry

    func testSaveFailureShowsRetryableCopyAndRetrySucceeds() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        // 归档目录路径被同名普通文件占用 → 首次保存必然失败。
        try FileManager.default.createDirectory(at: stores.root, withIntermediateDirectories: true)
        try Data("occupied".utf8).write(to: stores.archive.directoryURL)

        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock, countdownDuration: 0)

        viewModel.start()
        viewModel.ingest(sample(index: 1, secondsAfterStart: 1))
        clock.date = startDate.addingTimeInterval(10)
        viewModel.finish()

        viewModel.saveFinished()
        XCTAssertFalse(viewModel.didSave)
        XCTAssertEqual(viewModel.savedCount, 0)
        XCTAssertEqual(viewModel.state, .finished, "保存失败后决策仍在")
        let message = try XCTUnwrap(viewModel.decisionErrorMessage)
        XCTAssertEqual(message, L10n.saveFailed)
        XCTAssertTrue(message.contains("保存失败"), "失败提示必须是 zh-Hans 可读文案")
        XCTAssertTrue(message.contains("重试"), "失败提示必须带重试语义")
        XCTAssertFalse(message.contains("ioFailure"), "不得回显英文错误描述")
        XCTAssertEqual(try stores.archive.list().count, 0)

        try FileManager.default.removeItem(at: stores.archive.directoryURL)
        viewModel.saveFinished()
        XCTAssertTrue(viewModel.didSave)
        XCTAssertEqual(viewModel.savedCount, 1)
        XCTAssertNil(viewModel.decisionErrorMessage)
        XCTAssertEqual(try stores.archive.list().count, 1)
    }

    // MARK: - ac-decision-guards

    func testDecisionGuardsKeepStateMetricsAndArchiveUntouched() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let viewModel = makeViewModel(stores: stores, clock: clock, countdownDuration: 0)

        viewModel.saveFinished()
        viewModel.discardFinished()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.metrics, .initial)
        XCTAssertEqual(try stores.archive.list().count, 0)

        viewModel.start()
        viewModel.saveFinished()
        viewModel.discardFinished()
        XCTAssertEqual(viewModel.state, .running)
        XCTAssertEqual(try stores.archive.list().count, 0)

        viewModel.pause()
        viewModel.saveFinished()
        viewModel.discardFinished()
        XCTAssertEqual(viewModel.state, .paused)
        XCTAssertEqual(try stores.archive.list().count, 0)

        clock.date = startDate.addingTimeInterval(10)
        viewModel.finish()
        let pendingMetrics = viewModel.metrics
        viewModel.finish()
        XCTAssertEqual(viewModel.state, .finished)
        XCTAssertEqual(viewModel.metrics, pendingMetrics, "重复结束不得重复生成快照")
        XCTAssertEqual(try stores.archive.list().count, 0, "重复结束不得重复归档")

        viewModel.saveFinished()
        XCTAssertEqual(try stores.archive.list().count, 1)
    }

    // MARK: - ac-location-two-recoverable-states

    func testLocationReadinessSplitsDeniedAndUnavailable() throws {
        let denied = RunLocationReadiness(authorization: .denied)
        let unavailable = RunLocationReadiness(authorization: .restricted)

        XCTAssertEqual(denied, .permissionDenied)
        XCTAssertEqual(denied.nextAction, .openSettings)
        XCTAssertEqual(denied.messageKey, "run.status.locationDenied")
        XCTAssertEqual(denied.message, L10n.locationDenied)

        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(unavailable.nextAction, .retry)
        XCTAssertEqual(unavailable.messageKey, "run.status.locationUnavailable")
        XCTAssertEqual(unavailable.message, L10n.locationUnavailable)

        XCTAssertNotEqual(denied, unavailable)
        XCTAssertNotEqual(denied.nextAction, unavailable.nextAction)
        XCTAssertNotEqual(denied.messageKey, unavailable.messageKey)
        XCTAssertNotEqual(denied.message, unavailable.message)

        for authorization in [RunLocationAuthorization.authorizedWhenInUse, .authorizedAlways] {
            let readiness = RunLocationReadiness(authorization: authorization)
            XCTAssertEqual(readiness, .ready)
            XCTAssertNil(readiness.nextAction)
            XCTAssertNil(readiness.messageKey)
            XCTAssertNil(readiness.message)
        }

        let awaiting = RunLocationReadiness(authorization: .notDetermined)
        XCTAssertEqual(awaiting, .awaitingAuthorization)
        XCTAssertNil(awaiting.nextAction)
        XCTAssertEqual(awaiting.messageKey, "run.status.waitingAuthorization")
        XCTAssertEqual(awaiting.message, L10n.waitingAuthorization)
    }

    func testTheFollowingAuthorizationUpdatesViewModelReadiness() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let source = FakeLocationSource()
        source.authorization = .denied
        let viewModel = makeViewModel(stores: stores, clock: clock, source: source)

        viewModel.onAppear()
        XCTAssertEqual(viewModel.locationReadiness, .permissionDenied)
        XCTAssertEqual(viewModel.locationReadiness.nextAction, .openSettings)
        XCTAssertNotNil(viewModel.locationSettingsURL)
    }

    // MARK: - ac-location-retry-restarts

    func testRetryRestartsLocationSourceAndRecoversReadiness() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let source = FakeLocationSource()
        source.authorization = .restricted
        let viewModel = makeViewModel(stores: stores, clock: clock, source: source)

        viewModel.onAppear()
        XCTAssertEqual(viewModel.locationReadiness, .unavailable)
        let startCountBeforeRetry = source.startCount

        viewModel.retryLocation()
        XCTAssertEqual(source.startCount, startCountBeforeRetry + 1, "重试必须重新拉起定位源")

        source.report(.authorizedWhenInUse)
        XCTAssertEqual(viewModel.authorization, .authorizedWhenInUse)
        XCTAssertEqual(viewModel.locationReadiness, .ready)
        XCTAssertNil(viewModel.locationReadiness.message, "恢复后提示立即消失")
        XCTAssertNil(viewModel.locationReadiness.nextAction)
    }

    func testRetryIsIgnoredWhenNextActionIsNotRetry() throws {
        let stores = makeStores()
        defer { removeStores(stores) }
        let clock = Clock(date: startDate)
        let source = FakeLocationSource()
        source.authorization = .denied
        let viewModel = makeViewModel(stores: stores, clock: clock, source: source)

        viewModel.onAppear()
        let startCountBeforeRetry = source.startCount
        viewModel.retryLocation()
        XCTAssertEqual(source.startCount, startCountBeforeRetry, "「权限被拒」态只有去设置，不做重试")
    }

    // MARK: - ac-l10n-single-catalog

    func testNewCopyIsZhHansAndDistinct() throws {
        let strings = [
            L10n.locationDenied,
            L10n.locationUnavailable,
            L10n.waitingAuthorization,
            L10n.saveFailed
        ]
        XCTAssertEqual(Set(strings).count, strings.count, "四种定位/保存提示必须互不相同")
        XCTAssertFalse(strings.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        for value in [L10n.locationDenied, L10n.locationUnavailable, L10n.saveFailed] {
            XCTAssertTrue(
                value.unicodeScalars.contains { $0.value > 0x4E00 },
                "新增文案必须是 zh-Hans 可读字符串：\(value)"
            )
        }
    }

    // MARK: - 夹具实现

    private var startDate: Date {
        Date(timeIntervalSince1970: t0)
    }

    private func makeStores() -> Stores {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceContract-\(UUID().uuidString)", isDirectory: true)
        return Stores(
            root: root,
            checkpoint: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archive: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
    }

    private func removeStores(_ stores: Stores) {
        try? FileManager.default.removeItem(at: stores.root)
    }

    private func checkpointCount(_ stores: Stores) throws -> Int {
        let url = stores.root.appendingPathComponent("checkpoint.jsonl")
        return try RunCheckpointStore(fileURL: url).loadAll().count
    }

    private func makeViewModel(
        stores: Stores,
        clock: Clock,
        source: FakeLocationSource = FakeLocationSource(),
        countdownDuration: TimeInterval = RunStartCountdown.defaultDuration
    ) -> RunSessionViewModel {
        RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: source,
            announcements: SilentSpeaker(),
            countdownDuration: countdownDuration,
            now: { clock.date },
            notificationCenter: NotificationCenter()
        )
    }

    private func samples(count: Int) -> [RunSample] {
        (1...count).map { sample(index: $0, secondsAfterStart: Double($0)) }
    }

    private func sample(index: Int, secondsAfterStart: TimeInterval) -> RunSample {
        RunSample(
            latitude: baseLatitude + step * Double(index),
            longitude: baseLongitude,
            altitude: nil,
            timestamp: startDate.addingTimeInterval(secondsAfterStart),
            heartRate: nil,
            cadence: nil
        )!
    }

    private final class SilentSpeaker: AnnouncementSpeaking {
        func speak(_ command: AnnouncementCommand) {}
    }
}
