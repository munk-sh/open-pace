import Foundation
import PurePaceRunCore

/// 跑步页交互展示决策的唯一真源：由 `RunSessionViewModel` 的公开面派生
/// 「本态显示哪些操作 / 谁是唯一主操作 / 倒计时读数 / 提示优先级 / 恢复动作 / 过渡时长」。
///
/// 纯值类型、无 View / 闭包，让五条路径（倒计时 / 暂停继续结束 / 保存丢弃 / 权限态）
/// 的展示决策能在 L1 直接断言；`RunView` 只按本 plan 渲染，不再各自 `switch`。
struct RunInteractionPlan: Equatable {
    /// 既有 8 个动作；文案映射留在 `RunView`（`L10n`），plan 不持有文案。
    enum Action: String, Equatable, Hashable, Sendable {
        case start
        case cancelCountdown
        case pause
        case resume
        case finish
        case save
        case discard
        case viewHistory
    }

    enum Emphasis: Equatable, Sendable {
        case primary
        case secondary
    }

    struct Item: Equatable, Sendable {
        let action: Action
        let emphasis: Emphasis
    }

    /// 同屏唯一提示；优先级：记录错误 > 决策失败 > 定位状态 > 后台降级。
    enum Notice: String, Equatable, Sendable {
        case recordingError
        case decisionFailed
        case locationDenied
        case locationUnavailable
        case waitingAuthorization
        case backgroundDegraded
    }

    /// 未开始态的可执行恢复出口；记录中 / 已结束恒为 `nil`。
    enum Recovery: String, Equatable, Sendable {
        case openSettings
        case retryLocation
    }

    /// 指标文本与读数分离：倒计时读数不替换 hero / 指标卡内容。
    struct Metrics: Equatable, Sendable {
        let distance: String
        let elapsed: String
        let currentPace: String
        let averagePace: String
        let splitCount: String
    }

    let items: [Item]
    let countdownText: String?
    let showsMetrics: Bool
    let notice: Notice?
    let recovery: Recovery?
    let transitionDuration: TimeInterval
    let metrics: Metrics

    init(
        state: RunSessionState,
        isCountingDown: Bool = false,
        countdownText: String? = nil,
        didSave: Bool = false,
        hasError: Bool = false,
        hasDecisionError: Bool = false,
        readiness: RunLocationReadiness = .ready,
        hasBackgroundDegradation: Bool = false,
        metrics: Metrics,
        reduceMotion: Bool = false
    ) {
        self.items = Self.items(
            state: state,
            isCountingDown: isCountingDown,
            didSave: didSave
        )
        self.countdownText = isCountingDown ? countdownText : nil
        self.showsMetrics = true
        self.notice = Self.notice(
            state: state,
            isCountingDown: isCountingDown,
            didSave: didSave,
            hasError: hasError,
            hasDecisionError: hasDecisionError,
            readiness: readiness,
            hasBackgroundDegradation: hasBackgroundDegradation
        )
        self.recovery = Self.recovery(
            state: state,
            isCountingDown: isCountingDown,
            didSave: didSave,
            readiness: readiness
        )
        self.transitionDuration = DesignTokens.Motion.duration(
            DesignTokens.Motion.durationState,
            reduceMotion: reduceMotion
        )
        self.metrics = metrics
    }

    /// 从 ViewModel 公开面取值；视图侧唯一便捷入口。
    @MainActor
    init(viewModel: RunSessionViewModel, reduceMotion: Bool) {
        self.init(
            state: viewModel.state,
            isCountingDown: viewModel.isCountingDown,
            countdownText: viewModel.countdownText,
            didSave: viewModel.didSave,
            hasError: viewModel.errorMessage != nil,
            hasDecisionError: viewModel.decisionErrorMessage != nil,
            readiness: viewModel.locationReadiness,
            hasBackgroundDegradation: viewModel.authorization.backgroundDegradationHint != nil,
            metrics: Metrics(
                distance: RunFormatting.distanceValueText(viewModel.metrics.distance),
                elapsed: viewModel.elapsedText,
                currentPace: RunFormatting.paceValueText(viewModel.metrics.currentPace),
                averagePace: RunFormatting.paceValueText(viewModel.metrics.averagePace),
                splitCount: viewModel.splitCountText
            ),
            reduceMotion: reduceMotion
        )
    }

    // MARK: - 派生

    /// 每个展示态恰有一个 `primary`；破坏性动作（finish / discard）恒为 `secondary`。
    private static func items(
        state: RunSessionState,
        isCountingDown: Bool,
        didSave: Bool
    ) -> [Item] {
        switch state {
        case .ready:
            return isCountingDown
                ? [Item(action: .cancelCountdown, emphasis: .primary)]
                : [Item(action: .start, emphasis: .primary)]
        case .running:
            return [
                Item(action: .pause, emphasis: .primary),
                Item(action: .finish, emphasis: .secondary)
            ]
        case .paused:
            return [
                Item(action: .resume, emphasis: .primary),
                Item(action: .finish, emphasis: .secondary)
            ]
        case .finished:
            return didSave
                ? [Item(action: .viewHistory, emphasis: .primary)]
                : [
                    Item(action: .save, emphasis: .primary),
                    Item(action: .discard, emphasis: .secondary)
                ]
        }
    }

    private static func notice(
        state: RunSessionState,
        isCountingDown: Bool,
        didSave: Bool,
        hasError: Bool,
        hasDecisionError: Bool,
        readiness: RunLocationReadiness,
        hasBackgroundDegradation: Bool
    ) -> Notice? {
        if hasError {
            return .recordingError
        }
        if hasDecisionError {
            return .decisionFailed
        }
        if state == .ready, !isCountingDown, !didSave {
            switch readiness {
            case .permissionDenied:
                return .locationDenied
            case .unavailable:
                return .locationUnavailable
            case .awaitingAuthorization:
                return .waitingAuthorization
            case .ready:
                break
            }
        }
        if hasBackgroundDegradation {
            return .backgroundDegraded
        }
        return nil
    }

    private static func recovery(
        state: RunSessionState,
        isCountingDown: Bool,
        didSave: Bool,
        readiness: RunLocationReadiness
    ) -> Recovery? {
        guard state == .ready, !isCountingDown, !didSave else {
            return nil
        }
        switch readiness.nextAction {
        case .openSettings:
            return .openSettings
        case .retry:
            return .retryLocation
        case nil:
            return nil
        }
    }
}
