import Foundation
import PurePaceRunCore
import SwiftUI

/// 首屏跑步页的会话 ViewModel：真实定位采样 -> 既有 `RunSessionOrchestrator` -> 可观测度量。
///
/// 距离/时长/配速/分段全部读编排器的 `metrics`，App 侧不自建计时器或距离公式；
/// 所有会话动作的时间由调用方注入，生产默认取当前时间，测试可注入合成时钟。
@MainActor
final class RunSessionViewModel: ObservableObject {
    @Published private(set) var state: RunSessionState
    @Published private(set) var metrics: RunMetrics
    @Published private(set) var authorization: RunLocationAuthorization = .notDetermined
    @Published private(set) var didSave = false
    @Published private(set) var savedCount = 0
    @Published private(set) var errorMessage: String?
    /// DEBUG + `-uiTestLocation` 时暴露的遥测摘要，供 XCUITest 断言；Release 恒为 nil。
    @Published private(set) var telemetrySummary: String?

    private var orchestrator: RunSessionOrchestrator
    private let locationSource: RunLocationProviding
    private let announcements: AnnouncementSpeaking
    private let announcementRecorder: AnnouncementTelemetryRecording
    private let authorizationProbe: SystemAuthorizationProbing
    private let telemetryWriter: RunTelemetryWriting
    private let telemetryDebugEnabled: Bool
    private let lifecycleRecorder: RunLifecycleTelemetryRecording
    private let bundleInfo: BundleInfoProviding
    private let lifecycleSnapshotBox: RunLifecycleSnapshotBox
    private let autoStartRecording: Bool
    private let now: () -> Date

    private var sampleSources: [TimeInterval: RunSampleSource] = [:]
    private var backgroundSnapshot: (allows: Bool, pauses: Bool)?
    private var runSampleCount = 0
    private var didAutoStart = false

    init(
        checkpointStore: RunCheckpointStore,
        archiveStore: RunArchiveStore,
        locationSource: RunLocationProviding,
        announcements: AnnouncementSpeaking? = nil,
        announcementsEnabled: Bool = true,
        announcementRecorder: AnnouncementTelemetryRecording? = nil,
        authorizationProbe: SystemAuthorizationProbing? = nil,
        telemetryWriter: RunTelemetryWriting? = nil,
        telemetryDebugEnabled: Bool = false,
        autoStartRecording: Bool = false,
        lifecycleRecorder: RunLifecycleTelemetryRecording? = nil,
        bundleInfo: BundleInfoProviding? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        let orchestrator = RunSessionOrchestrator(
            checkpointStore: checkpointStore,
            archiveStore: archiveStore,
            announcementsEnabled: announcementsEnabled
        )
        let recorder = announcementRecorder ?? AnnouncementTelemetryRecorder()
        self.orchestrator = orchestrator
        self.state = orchestrator.state
        self.metrics = orchestrator.metrics
        self.locationSource = locationSource
        self.announcements = announcements ?? SpeechAnnouncementSpeaker(telemetry: recorder)
        self.announcementRecorder = recorder
        self.authorizationProbe = authorizationProbe ?? SystemAuthorizationProbe()
        self.telemetryWriter = telemetryWriter ?? RunTelemetryWriter(directoryURL: archiveStore.directoryURL)
        self.telemetryDebugEnabled = telemetryDebugEnabled
        let snapshotBox = RunLifecycleSnapshotBox()
        self.lifecycleSnapshotBox = snapshotBox
        self.lifecycleRecorder = lifecycleRecorder
            ?? RunLifecycleTelemetryRecorder(snapshotProvider: { snapshotBox.read() })
        self.bundleInfo = bundleInfo ?? SystemBundleInfoProvider()
        self.autoStartRecording = autoStartRecording
        self.now = now
        locationSource.delegate = self
    }

    // MARK: - 生命周期

    /// 页面出现即请求「使用期间」定位授权；授权后自动继续，不伪造进度。
    ///
    /// `-autoStartRecording` 开启时仅在 `.ready` 下自动开跑一次；重复 `onAppear` 不再触发。
    func onAppear() {
        if autoStartRecording, state == .ready, !didAutoStart {
            didAutoStart = true
            start()
            return
        }
        locationSource.start()
    }

    // MARK: - 会话动作

    func start() {
        guard state == .ready else { return }
        runSampleCount = 0
        updateLifecycleSnapshot()
        perform { try orchestrator.start(at: now()) }
        locationSource.start()
        // 抓「跑步进行态」的后台开关快照：真实源反映 manager，测试源如实为 false。
        backgroundSnapshot = (
            allows: locationSource.allowsBackgroundLocationUpdates,
            pauses: locationSource.pausesLocationUpdatesAutomatically
        )
    }

    func pause() {
        guard state == .running else { return }
        perform { try orchestrator.pause(at: now()) }
    }

    func resume() {
        guard state == .paused else { return }
        perform { try orchestrator.resume(at: now()) }
    }

    func finish() {
        guard state.isActive else { return }
        do {
            let record = try orchestrator.finish(at: now())
            if record != nil {
                didSave = true
                savedCount += 1
            }
            apply(state: orchestrator.state, metrics: orchestrator.metrics)
            locationSource.stop()
            if let record {
                injectTelemetry(for: record)
            }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: - 播报开关

    /// 只转调编排器；关闭即时生效，重新开启不补播由编排器保证。
    func setAnnouncementsEnabled(_ enabled: Bool) {
        orchestrator.setAnnouncementsEnabled(enabled)
    }

    // MARK: - 采样摄入

    func ingest(_ sample: RunSample) {
        do {
            apply(try orchestrator.ingest(sample))
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: - 展示

    var distanceText: String {
        RunFormatting.distanceText(metrics.distance)
    }

    var elapsedText: String {
        RunFormatting.elapsedText(metrics.elapsed)
    }

    var currentPaceText: String {
        RunFormatting.paceText(metrics.currentPace)
    }

    var averagePaceText: String {
        RunFormatting.paceText(metrics.averagePace)
    }

    var splitCountText: String {
        RunFormatting.splitCountText(metrics.completedKilometers)
    }

    // MARK: - 内部

    private func perform(_ action: () throws -> RunSessionUpdate) {
        do {
            apply(try action())
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func apply(_ update: RunSessionUpdate) {
        apply(state: update.state, metrics: update.metrics)
        for command in update.announcements {
            announcements.speak(command)
        }
    }

    private func apply(state: RunSessionState, metrics: RunMetrics) {
        self.state = state
        self.metrics = metrics
        updateLifecycleSnapshot()
    }

    /// 事件快照只看本跑次：样本计数在 `start()` 归零，距离/时长取编排器度量。
    private func updateLifecycleSnapshot() {
        lifecycleSnapshotBox.update(
            RunLifecycleSnapshot(
                sampleCount: runSampleCount,
                distanceMeters: metrics.distance.meters,
                elapsedSeconds: metrics.elapsed
            )
        )
    }

    /// 跑次落盘后 additive 注入遥测；失败不改变归档结果，只作为自证缺失。
    private func injectTelemetry(for record: RunRecord) {
        let status = authorizationProbe.authorizationStatus
        let accuracy = authorizationProbe.accuracyAuthorization
        let telemetry = RunTelemetry(
            authorizationStatus: RunTelemetryAuthorization(
                name: status.rawValue,
                rawValue: status.clRawValue
            ),
            accuracyAuthorization: RunTelemetryAuthorization(
                name: accuracy.rawValue,
                rawValue: accuracy.clRawValue
            ),
            allowsBackgroundLocationUpdates: backgroundSnapshot?.allows
                ?? locationSource.allowsBackgroundLocationUpdates,
            pausesLocationUpdatesAutomatically: backgroundSnapshot?.pauses
                ?? locationSource.pausesLocationUpdatesAutomatically,
            announcements: announcementRecorder.snapshot(),
            events: lifecycleRecorder.events,
            bundle: RunTelemetryBundle(infoDictionary: bundleInfo.infoDictionary)
        )
        do {
            try telemetryWriter.inject(
                telemetry: telemetry,
                sources: sampleSources,
                recordID: record.id,
                defaultSource: locationSource.sampleSource
            )
        } catch {
            // 遥测是 additive 自证，注入失败不改变跑次归档与 UI。
        }
        if telemetryDebugEnabled {
            telemetrySummary = Self.summary(for: telemetry)
        }
    }

    static func summary(for telemetry: RunTelemetry) -> String {
        let announcements = telemetry.announcements.map { entry in
            let duck = entry.categoryOptions.contains("duckOthers") ? "true" : "false"
            return "\(entry.text)|duckOthers=\(duck)"
                + "|otherAudioPlaying=\(entry.isOtherAudioPlaying)"
                + "|secondaryAudioSilenced=\(entry.secondaryAudioShouldBeSilencedHint)"
        }.joined(separator: ";")
        return "authorizationStatus={name=\(telemetry.authorizationStatus.name)"
            + ",rawValue=\(telemetry.authorizationStatus.rawValue)}"
            + " accuracy={name=\(telemetry.accuracyAuthorization.name)"
            + ",rawValue=\(telemetry.accuracyAuthorization.rawValue)}"
            + " allowsBackground=\(telemetry.allowsBackgroundLocationUpdates)"
            + " announcements=[\(announcements)]"
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? RunCoreError {
            return error.description
        }
        return error.localizedDescription
    }
}

extension RunSessionViewModel: RunLocationSourceDelegate {
    func locationSource(_ source: RunLocationProviding, didProduce sample: RunSample) {
        sampleSources[sample.timestamp.timeIntervalSince1970] = source.sampleSource
        runSampleCount += 1
        updateLifecycleSnapshot()
        ingest(sample)
    }

    func locationSource(_ source: RunLocationProviding, didChangeAuthorization authorization: RunLocationAuthorization) {
        self.authorization = authorization
    }
}
