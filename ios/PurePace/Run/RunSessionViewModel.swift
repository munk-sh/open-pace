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
    /// 待决策态保存失败的 zh-Hans 可读提示；成功或丢弃后清空。
    @Published private(set) var decisionErrorMessage: String?
    /// 是否处于可取消的开始倒计时（`state` 仍为 `ready`）。
    @Published private(set) var isCountingDown = false
    /// 倒计时剩余秒数（按注入时钟刷新，恒不为负）。
    @Published private(set) var countdownRemaining: TimeInterval = 0
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
    /// 开始前倒计时总时长；测试注入 0 以跳过真实等待（生产恒用 RunCore 常量）。
    private let countdownDuration: TimeInterval
    private let now: () -> Date
    /// 锁屏区间观察者；非可选 `let`，生命周期跟随 ViewModel。
    private let lockObservation: RunProtectedDataObservation

    private var sampleSources: [TimeInterval: RunSampleSource] = [:]
    private var backgroundSnapshot: (allows: Bool, pauses: Bool)?
    /// 本跑次已计数并转发的定位采样条数（倒计时/暂停/已结束期间不增）。
    private(set) var runSampleCount = 0
    private var didAutoStart = false
    private var countdown: RunStartCountdown?

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
        countdownDuration: TimeInterval = RunStartCountdown.defaultDuration,
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
        self.countdownDuration = countdownDuration
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

    /// 点击开始：先进入可取消倒计时，到点才真正记录。
    ///
    /// `-autoStartRecording` 调试路径一次性把倒计时置为完成（不引入 sleep）；
    /// 注入零时长倒计时同样立即越过，供确定性单测使用。
    func start() {
        guard state == .ready, countdown == nil else { return }
        runSampleCount = 0
        duplicateSampleCount = 0
        didSave = false
        decisionErrorMessage = nil
        errorMessage = nil
        countdown = RunStartCountdown(
            duration: autoStartRecording ? 0 : countdownDuration,
            startedAt: now()
        )
        refreshCountdown()
        updateLifecycleSnapshot()
        if countdown?.isComplete(at: now()) == true {
            beginRecording(at: now())
        } else {
            // 倒计时期间即启动定位源：采样由 delegate 门丢弃，不计数、不摄入。
            locationSource.start()
        }
    }

    /// 取消倒计时：回到 `ready`、清空倒计时阶段，零度量零采样，可立即再次开始。
    func cancelCountdown() {
        guard countdown != nil else { return }
        countdown = nil
        isCountingDown = false
        countdownRemaining = 0
        runSampleCount = 0
        duplicateSampleCount = 0
        didSave = false
        decisionErrorMessage = nil
        apply(state: orchestrator.state, metrics: orchestrator.metrics)
    }

    /// 推进倒计时：注入时钟未到 deadline 时保持倒计时（零记录），到点才真正开始。
    func advanceCountdown() {
        guard let countdown else { return }
        let date = now()
        guard countdown.isComplete(at: date) else {
            countdownRemaining = countdown.remaining(at: date)
            return
        }
        beginRecording(at: date)
    }

    func pause() {
        guard state == .running else { return }
        perform { try orchestrator.pause(at: now()) }
    }

    func resume() {
        guard state == .paused else { return }
        perform { try orchestrator.resume(at: now()) }
    }

    /// 结束：生成结束快照并停止记录，但**不落盘**，等待显式保存或丢弃。
    func finish() {
        guard state.isActive else { return }
        do {
            _ = try orchestrator.prepareFinish(at: now())
            apply(state: orchestrator.state, metrics: orchestrator.metrics)
            locationSource.stop()
            decisionErrorMessage = nil
            didSave = false
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// 保存结束快照：归档恰一次；失败提示 zh-Hans 可读文案并可原地重试。
    func saveFinished() {
        guard state == .finished else { return }
        let wasSaved = orchestrator.savedRecord != nil
        do {
            let record = try orchestrator.saveFinished()
            if !wasSaved {
                didSave = true
                savedCount += 1
                decisionErrorMessage = nil
                injectTelemetry(for: record)
            }
            apply(state: orchestrator.state, metrics: orchestrator.metrics)
        } catch {
            decisionErrorMessage = L10n.saveFailed
        }
    }

    /// 丢弃结束快照：不写归档，重建为可立刻再跑的 `ready`。
    func discardFinished() {
        guard state == .finished else { return }
        do {
            try orchestrator.discard()
            didSave = false
            decisionErrorMessage = nil
            errorMessage = nil
            runSampleCount = 0
            duplicateSampleCount = 0
            apply(state: orchestrator.state, metrics: orchestrator.metrics)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// 真正开始记录：清倒计时阶段，度量从 0 起算。
    private func beginRecording(at date: Date) {
        guard state == .ready else { return }
        countdown = nil
        isCountingDown = false
        countdownRemaining = 0
        runSampleCount = 0
        duplicateSampleCount = 0
        perform { try orchestrator.start(at: date) }
        locationSource.start()
        // 抓「跑步进行态」的后台开关快照：真实源反映 manager，测试源如实为 false。
        backgroundSnapshot = (
            allows: locationSource.allowsBackgroundLocationUpdates,
            pauses: locationSource.pausesLocationUpdatesAutomatically
        )
    }

    private func refreshCountdown() {
        guard let countdown else {
            isCountingDown = false
            countdownRemaining = 0
            return
        }
        isCountingDown = true
        countdownRemaining = countdown.remaining(at: now())
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

    // MARK: - 定位可用性

    /// 由授权派生的可恢复定位状态（拒绝 → 去设置；不可用 → 重试）。
    var locationReadiness: RunLocationReadiness {
        RunLocationReadiness(authorization: authorization)
    }

    /// 系统设置页深链；「权限被拒」态的唯一恢复出口。
    var locationSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    /// 仅「不可用」态可重试：重新拉起定位源，授权转好即恢复就绪。
    func retryLocation() {
        guard locationReadiness.nextAction == .retry else { return }
        locationSource.start()
    }

    // MARK: - 展示

    /// 倒计时剩余整秒（向上取整，读数从总时长单调递减到 0）。
    var countdownText: String {
        String(Int(countdownRemaining.rounded(.up)))
    }

    /// 本跑次已进入归档序列的采样（倒计时/结束后恒为空）。
    var acceptedSamples: [RunSample] {
        orchestrator.acceptedSamples
    }

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
        // 采样门：只有记录态才计数与转发；倒计时/ready/paused/finished 一律整条丢弃。
        guard state == .running else { return }
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
