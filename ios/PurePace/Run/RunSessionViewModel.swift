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

    private var orchestrator: RunSessionOrchestrator
    private let locationSource: RunLocationProviding
    private let now: () -> Date

    init(
        checkpointStore: RunCheckpointStore,
        archiveStore: RunArchiveStore,
        locationSource: RunLocationProviding,
        now: @escaping () -> Date = { Date() }
    ) {
        let orchestrator = RunSessionOrchestrator(
            checkpointStore: checkpointStore,
            archiveStore: archiveStore
        )
        self.orchestrator = orchestrator
        self.state = orchestrator.state
        self.metrics = orchestrator.metrics
        self.locationSource = locationSource
        self.now = now
        locationSource.delegate = self
    }

    // MARK: - 生命周期

    /// 页面出现即请求「使用期间」定位授权；授权后自动继续，不伪造进度。
    func onAppear() {
        locationSource.start()
    }

    // MARK: - 会话动作

    func start() {
        guard state == .ready else { return }
        perform { try orchestrator.start(at: now()) }
        locationSource.start()
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
            if try orchestrator.finish(at: now()) != nil {
                didSave = true
                savedCount += 1
            }
            apply(state: orchestrator.state, metrics: orchestrator.metrics)
            locationSource.stop()
        } catch {
            errorMessage = Self.describe(error)
        }
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
    }

    private func apply(state: RunSessionState, metrics: RunMetrics) {
        self.state = state
        self.metrics = metrics
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
        ingest(sample)
    }

    func locationSource(_ source: RunLocationProviding, didChangeAuthorization authorization: RunLocationAuthorization) {
        self.authorization = authorization
    }
}
