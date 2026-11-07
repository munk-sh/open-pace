import Foundation
import PurePaceRunCore

/// CoreLocation 授权状态的可序列化镜像（与 CLAuthorizationStatus 一一对应）。
enum HarnessLocationAuthorization: String, CaseIterable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways
}

/// Harness 纯逻辑内核：把采样/控制事件驱动成
/// `RunMetricsEngine` + `RunSessionMachine` + `AnnouncementScheduler` + `RunCheckpointStore`，
/// 并维护 status 文档所需的原始采样、计数、分段采样索引与恢复标志。
///
/// 不 import CoreLocation / SwiftUI，可在 XCTest 中直接单测。
struct HarnessCore {
    let mode: HarnessMode
    let resumed: Bool
    let restored: HarnessRestoredSnapshot?

    private let checkpointStore: RunCheckpointStore?
    private let appendsCheckpoints: Bool

    private var engine: RunMetricsEngine
    private var machine: RunSessionMachine
    private var scheduler: AnnouncementScheduler

    private(set) var rawSamples: [HarnessRawSampleRecord] = []
    private(set) var announcements: [HarnessAnnouncementRecord] = []
    private(set) var error: HarnessStatusError?
    private(set) var locationAuthorization: HarnessLocationAuthorization?
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    private var splitSampleIndexes: [Int] = []
    private var acceptedSampleCount = 0
    private var rejectedByAccuracy = 0
    private var rejectedByFirstPoint = 0
    private var hasLocationAnchor = false
    private var lastEventAt: Date?

    init(mode: HarnessMode, checkpointStore: RunCheckpointStore?, appendsCheckpoints: Bool) {
        self.mode = mode
        self.resumed = false
        self.restored = nil
        self.checkpointStore = checkpointStore
        self.appendsCheckpoints = appendsCheckpoints
        self.engine = RunMetricsEngine()
        self.machine = RunSessionMachine()
        self.scheduler = AnnouncementScheduler()
    }

    /// resume 模式：仅从真实 checkpoint 恢复，不接新采样、不追加新 checkpoint。
    init(resuming checkpoint: RunCheckpoint, checkpointPath: String) {
        self.mode = .resume
        self.resumed = true
        let announcedSplitIndex = checkpoint.announcedSplitIndex ?? checkpoint.splits.count
        self.restored = HarnessRestoredSnapshot(
            checkpointPath: checkpointPath,
            completedDistanceMeters: checkpoint.completedDistance.meters,
            elapsedSeconds: checkpoint.elapsed,
            splitCount: checkpoint.splits.count,
            announcedSplitIndex: announcedSplitIndex
        )
        self.checkpointStore = nil
        self.appendsCheckpoints = false
        self.engine = RunMetricsEngine(restoring: checkpoint)
        self.machine = RunSessionMachine(restoring: checkpoint)
        self.scheduler = AnnouncementScheduler(announcedSplitIndex: announcedSplitIndex)
        self.lastEventAt = checkpoint.recordedAt
    }

    var state: RunSessionState { machine.state }
    var isFinished: Bool { machine.state == .finished }
    var metrics: RunMetrics { engine.metrics }
    var activeDurationAnchor: Date? { startedAt }

    // MARK: - 控制事件

    mutating func start(at date: Date) {
        guard machine.state == .ready else { return }
        do {
            try machine.start()
        } catch {
            return
        }
        engine.start(at: date)
        startedAt = date
        lastEventAt = date
        applySchedulerTick(newlyCompletedSplits: [])
        appendCheckpointIfNeeded(force: true, at: date)
    }

    mutating func pause(at date: Date) {
        guard machine.state == .running else { return }
        do {
            try machine.pause()
        } catch {
            return
        }
        engine.pause(at: date)
        lastEventAt = date
        applySchedulerTick(newlyCompletedSplits: [])
        appendCheckpointIfNeeded(force: true, at: date)
    }

    mutating func resume(at date: Date) {
        guard machine.state == .paused else { return }
        do {
            try machine.resume()
        } catch {
            return
        }
        engine.resume(at: date)
        lastEventAt = date
        applySchedulerTick(newlyCompletedSplits: [])
        appendCheckpointIfNeeded(force: true, at: date)
    }

    mutating func finish(at date: Date) {
        guard machine.state != .finished else { return }
        if machine.state == .ready {
            start(at: date)
        }
        guard machine.state == .running || machine.state == .paused else { return }
        do {
            try machine.finish()
        } catch {
            return
        }
        engine.finish(at: date)
        finishedAt = date
        lastEventAt = date
        applySchedulerTick(newlyCompletedSplits: [])
        appendCheckpointIfNeeded(force: true, at: date)
    }

    // MARK: - 采样事件

    /// 直接流采样：所有合法采样都被接受（精度过滤只在 CoreLocation 适配层生效）。
    mutating func ingest(_ sample: RunSample, accuracyMeters: Double? = nil) {
        guard machine.state != .finished else { return }
        if machine.state == .ready {
            start(at: sample.timestamp)
        }
        recordAcceptedSample(sample, accuracyMeters: accuracyMeters)
        let update = engine.ingest(sample)
        lastEventAt = sample.timestamp
        applySchedulerTick(newlyCompletedSplits: update.newlyCompletedSplits)
        appendCheckpointIfNeeded(force: shouldAppendCadenceCheckpoint(hadNewSplit: !update.newlyCompletedSplits.isEmpty), at: sample.timestamp)
    }

    /// CoreLocation 采样：精度过滤 + 首点只作锚点（不计入距离、计入 rejectedByFirstPoint）。
    mutating func ingestLocation(_ sample: RunSample, horizontalAccuracy: Double) {
        guard machine.state != .finished else { return }
        let accuracyAccepted = horizontalAccuracy.isFinite
            && horizontalAccuracy >= 0
            && horizontalAccuracy <= HarnessThresholdValues.accuracyFilterMeters
        if !accuracyAccepted {
            rejectedByAccuracy += 1
            rawSamples.append(
                HarnessRawSampleRecord(
                    latitude: sample.latitude,
                    longitude: sample.longitude,
                    timestamp: sample.timestamp.timeIntervalSince1970,
                    accepted: false,
                    accuracyMeters: horizontalAccuracy,
                    rejectedReason: "accuracy"
                )
            )
            return
        }
        if !hasLocationAnchor {
            hasLocationAnchor = true
            rejectedByFirstPoint += 1
            rawSamples.append(
                HarnessRawSampleRecord(
                    latitude: sample.latitude,
                    longitude: sample.longitude,
                    timestamp: sample.timestamp.timeIntervalSince1970,
                    accepted: false,
                    accuracyMeters: horizontalAccuracy,
                    rejectedReason: "firstPoint"
                )
            )
            if machine.state == .ready {
                start(at: sample.timestamp)
            }
            // 锚点样本只建立引擎原点（距离与活跃时长仍为 0），后续样本从其继续累计。
            _ = engine.ingest(sample)
            lastEventAt = sample.timestamp
            return
        }
        if machine.state == .ready {
            start(at: sample.timestamp)
        }
        recordAcceptedSample(sample, accuracyMeters: horizontalAccuracy)
        let update = engine.ingest(sample)
        lastEventAt = sample.timestamp
        applySchedulerTick(newlyCompletedSplits: update.newlyCompletedSplits)
        appendCheckpointIfNeeded(force: shouldAppendCadenceCheckpoint(hadNewSplit: !update.newlyCompletedSplits.isEmpty), at: sample.timestamp)
    }

    mutating func recordError(code: String, message: String) {
        guard error == nil else { return }
        error = HarnessStatusError(code: code, message: message)
    }

    mutating func setLocationAuthorization(_ value: HarnessLocationAuthorization) {
        locationAuthorization = value
    }

    // MARK: - status 文档

    func status(now: Date = Date()) -> HarnessStatus {
        let metrics = engine.metrics
        let actual = HarnessActualRecord(
            distanceMeters: metrics.distance.meters,
            elapsedSeconds: metrics.elapsed,
            averagePaceSecondsPerKilometer: metrics.averagePace?.secondsPerKilometer,
            currentPaceSecondsPerKilometer: metrics.currentPace?.secondsPerKilometer,
            completedKilometers: metrics.completedKilometers,
            splitCount: metrics.splits.count,
            splitSampleIndexes: splitSampleIndexes
        )
        let splits = metrics.splits.map { split in
            HarnessSplitRecord(
                index: split.index,
                distanceMeters: split.distance.meters,
                durationSeconds: split.duration,
                paceSecondsPerKilometer: split.pace?.secondsPerKilometer
            )
        }
        return HarnessStatus(
            schemaVersion: 1,
            mode: mode.rawValue,
            state: machine.state.rawValue,
            startedAt: startedAt?.timeIntervalSince1970,
            updatedAt: now.timeIntervalSince1970,
            finishedAt: finishedAt?.timeIntervalSince1970,
            resumed: resumed,
            restored: restored,
            rawSamples: rawSamples,
            sampleCounts: HarnessSampleCounts(
                received: rawSamples.count,
                accepted: acceptedSampleCount,
                rejectedByAccuracy: rejectedByAccuracy,
                rejectedByFirstPoint: rejectedByFirstPoint
            ),
            actual: actual,
            thresholds: .fixed,
            splits: splits,
            announcements: announcements,
            error: error,
            locationAuthorization: locationAuthorization?.rawValue,
            includesLocationAuthorization: mode == .corelocation
        )
    }

    // MARK: - 内部

    /// 落盘时机：新增已完成分段，或每 10 个被接受采样。
    private func shouldAppendCadenceCheckpoint(hadNewSplit: Bool) -> Bool {
        hadNewSplit
            || acceptedSampleCount % HarnessThresholdValues.checkpointEveryAcceptedSamples == 0
    }

    private mutating func recordAcceptedSample(_ sample: RunSample, accuracyMeters: Double?) {
        acceptedSampleCount += 1
        rawSamples.append(
            HarnessRawSampleRecord(
                latitude: sample.latitude,
                longitude: sample.longitude,
                timestamp: sample.timestamp.timeIntervalSince1970,
                accepted: true,
                accuracyMeters: accuracyMeters,
                rejectedReason: nil
            )
        )
    }

    /// 顺序固定：ingest → AnnouncementScheduler.tick → checkpoint append。
    private mutating func applySchedulerTick(newlyCompletedSplits: [RunSplit]) {
        for _ in newlyCompletedSplits {
            splitSampleIndexes.append(acceptedSampleCount)
        }
        let update = RunMetricsUpdate(metrics: engine.metrics, newlyCompletedSplits: newlyCompletedSplits)
        for command in scheduler.tick(update, state: machine.state) {
            announcements.append(
                HarnessAnnouncementRecord(
                    trigger: command.trigger.rawValue,
                    splitIndex: command.splitIndex,
                    distanceMeters: command.distance.meters,
                    paceSecondsPerKilometer: command.pace.secondsPerKilometer,
                    elapsedSeconds: command.elapsed
                )
            )
        }
    }

    private mutating func appendCheckpointIfNeeded(force: Bool, at date: Date) {
        guard force, appendsCheckpoints, let checkpointStore else { return }
        let metrics = engine.metrics
        guard let checkpoint = RunCheckpoint(
            state: machine.state,
            completedDistance: metrics.distance,
            elapsed: metrics.elapsed,
            splits: metrics.splits,
            recordedAt: lastEventAt ?? date,
            lastSample: engine.lastAcceptedSample,
            announcedSplitIndex: scheduler.announcedSplitIndex
        ) else {
            recordError(code: "checkpointWriteFailed", message: "checkpoint 字段不满足契约")
            return
        }
        do {
            try checkpointStore.append(checkpoint)
        } catch {
            recordError(code: "checkpointWriteFailed", message: "写入 checkpoint 失败: \(error)")
        }
    }
}
