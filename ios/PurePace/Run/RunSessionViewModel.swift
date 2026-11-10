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
    /// 运行态下被单调守卫整条丢弃的等时/倒退采样条数（paused 下 drop 不计）。
    @Published private(set) var duplicateSampleCount = 0
    /// 当前是否处于 `protectedDataWillBecomeUnavailable` … `DidBecomeAvailable` 区间。
    @Published private(set) var isProtectedDataLocked = false
    /// 进入锁屏区间的时刻（注入时钟）；解锁后复位为 `nil`。
    @Published private(set) var protectedDataUnavailableSince: Date?
    /// 本次实例是否由 checkpoint 恢复构造。
    @Published private(set) var didRestoreFromCheckpoint = false

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
    /// 锁屏区间观察者；非可选 `let`，生命周期跟随 ViewModel。
    private let lockObservation: RunProtectedDataObservation

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
        now: @escaping () -> Date = { Date() },
        restoringCheckpoint: RunCheckpoint? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let orchestrator = restoringCheckpoint.map {
            RunSessionOrchestrator(
                restoring: $0,
                checkpointStore: checkpointStore,
                archiveStore: archiveStore,
                announcementsEnabled: announcementsEnabled
            )
        } ?? RunSessionOrchestrator(
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
        self.didRestoreFromCheckpoint = restoringCheckpoint != nil
        self.duplicateSampleCount = orchestrator.duplicateSampleCount
        let reference = WeakViewModelReference()
        self.lockObservation = RunProtectedDataObservation(center: notificationCenter) { isLocked in
            guard let viewModel = reference.value else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { viewModel.applyProtectedDataLock(isLocked) }
            } else {
                Task { @MainActor in viewModel.applyProtectedDataLock(isLocked) }
            }
        }
        reference.value = self
        locationSource.delegate = self
        if restoringCheckpoint != nil {
            updateLifecycleSnapshot()
        }
    }

    /// 应用级恢复入口：从 checkpoint 文件读回最后一次有效记录并构造全新实例（含 orchestrator）。
    ///
    /// 尾行不完整/非法由 `RunCheckpointStore.loadLatest()` 静默丢弃并回退上一条有效记录；
    /// 非尾行损坏原样上抛 `RunCoreError.corruptedCheckpoint`（禁止降级为零度量会话）。
    static func makeRestored(
        checkpointStore: RunCheckpointStore,
        archiveStore: RunArchiveStore,
        locationSource: RunLocationProviding,
        announcements: AnnouncementSpeaking? = nil,
        announcementsEnabled: Bool = true,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = { Date() }
    ) throws -> RunSessionViewModel {
        let checkpoint = try checkpointStore.loadLatest()
        return RunSessionViewModel(
            checkpointStore: checkpointStore,
            archiveStore: archiveStore,
            locationSource: locationSource,
            announcements: announcements,
            announcementsEnabled: announcementsEnabled,
            now: now,
            restoringCheckpoint: checkpoint,
            notificationCenter: notificationCenter
        )
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
        duplicateSampleCount = 0
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
            duplicateSampleCount = orchestrator.duplicateSampleCount
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

    /// 锁屏区间只写可观测状态，绝不触发 pause/resume/finish、不停定位、不补样本。
    private func applyProtectedDataLock(_ isLocked: Bool) {
        isProtectedDataLocked = isLocked
        protectedDataUnavailableSince = isLocked ? now() : nil
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

/// 弱引用盒：让锁屏观察闭包不直接捕获尚未完成初始化的 `self`。
final class WeakViewModelReference: @unchecked Sendable {
    weak var value: RunSessionViewModel?
}

/// 锁屏区间观察者：只把两条 protected-data 通知映射为「已锁定」布尔。
///
/// 不做任何会话动作（不 pause/resume/finish、不停定位、不补样本）；回调按 `queue: nil`
/// 在投递线程同步执行，`deinit` 移除 token。与 `RunLifecycleTelemetryRecorder` 同构。
final class RunProtectedDataObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter, onChange: @escaping @Sendable (Bool) -> Void) {
        self.center = center
        let willBecomeUnavailable = center.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: nil
        ) { _ in
            onChange(true)
        }
        let didBecomeAvailable = center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: nil
        ) { _ in
            onChange(false)
        }
        self.tokens = [willBecomeUnavailable, didBecomeAvailable]
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
