import Foundation
import PurePaceRunCore

/// 跑步页交互展示决策的唯一真源：由 `RunSessionViewModel` 的公开面派生
/// 「本态显示哪些操作 / 谁是唯一主操作 / 倒计时读数 / 提示优先级 / 恢复动作 / 过渡时长」。
///
/// 纯值类型、无 View / 闭包，让五条路径（倒计时 / 暂停继续结束 / 保存丢弃 / 权限态）
/// 的展示决策能在 L1 直接断言；`RunView` 只按本 plan 渲染，不再各自 `switch`。
struct RunInteractionPlan: Equatable {
    /// 动作集合；文案映射留在 `RunView`（`L10n`），plan 不持有文案。
    /// `discardRequest` 只是打开确认层的入口，真正的破坏性 `discard` 仅属于确认层。
    enum Action: String, Equatable, Hashable, Sendable {
        case start
        case cancelCountdown
        case pause
        case resume
        case finish
        case save
        case discardRequest
        case discard
        case cancel
        case viewHistory
    }

    /// 强调语义：`primary` 是每屏唯一填充主操作；`accent` 是记录态主操作族的
    /// 非填充 accent 型（结束）；`secondary` 是中性入口；`danger` 只允许出现在确认层。
    enum Emphasis: Equatable, Sendable {
        case primary
        case accent
        case secondary
        case danger
    }

    /// 控件视觉语义（由 `Emphasis` 机械派生，视图只按本枚举取 token，不再按动作分支）。
    enum Style: Equatable, Sendable {
        case primaryAccent
        case accentOutline
        case neutralOutline
        case dangerOutline
    }

    /// 动作 / hero 主值解析出的 palette 键；`warning` 只服务非阻断内联提示，永不给任何动作或 hero。
    /// `primary` 只用于未开始态 hero 的中性主值，永不作为动作着色。
    enum Tint: String, Equatable, Sendable {
        case accent
        case success
        case secondary
        case primary
        case danger
        case warning
    }

    struct Item: Equatable, Sendable {
        let action: Action
        let emphasis: Emphasis

        var style: Style {
            switch emphasis {
            case .primary: .primaryAccent
            case .accent: .accentOutline
            case .secondary: .neutralOutline
            case .danger: .dangerOutline
            }
        }

        /// 记录态主操作族（开始 / 暂停 / 继续 / 结束 / 保存）统一 `accent`；
        /// 已保存总结的「查看历史」沿用成功色；确认层丢弃只取 `danger`。
        var tint: Tint {
            if action == .viewHistory { return .success }
            switch style {
            case .primaryAccent, .accentOutline: return .accent
            case .neutralOutline: return .secondary
            case .dangerOutline: return .danger
            }
        }

        /// 是否渲染填充底：每屏最多一个（`primary`），破坏性动作恒不填充。
        var fillsWithTint: Bool {
            style == .primaryAccent
        }
    }

    /// 结束待保存屏的确认层：破坏性按钮只在这里出现，且不填充、不与 accent 主操作并列。
    struct DiscardConfirmation: Equatable, Sendable {
        let cancel: Item
        let confirm: Item
    }

    /// 同屏唯一提示；优先级：记录错误 > 决策失败 > 定位状态 > 后台降级。
    enum Notice: String, Equatable, Sendable {
        case recordingError
        case decisionFailed
        case locationDenied
        case locationUnavailable
        case waitingAuthorization
        case backgroundDegraded

        /// 非阻断内联提示的唯一着色：`warning` 只服务这里，不进主操作 / hero。
        var tint: Tint { .warning }
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
    /// 仅 `finished && !didSave` 时非空；破坏性确认控件只存在于这里。
    let discardConfirmation: DiscardConfirmation?
    /// hero 主值唯一着色真源：记录中 / 暂停取 accent（不切 warning），已保存取 success，
    /// 未开始取中性 primary；`warning` 永不进 hero。
    let heroTint: Tint
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
        self.discardConfirmation = Self.discardConfirmation(
            state: state,
            didSave: didSave
        )
        self.heroTint = Self.heroTint(state: state, didSave: didSave)
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

    /// 每个展示态恰有一个填充主操作（`primary`）：暂停 / 继续 / 保存；
    /// `finish` 属于 accent 主操作族但保持非填充，破坏性 `discard` 不进本屏。
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
                Item(action: .finish, emphasis: .accent)
            ]
        case .paused:
            return [
                Item(action: .resume, emphasis: .primary),
                Item(action: .finish, emphasis: .accent)
            ]
        case .finished:
            return didSave
                ? [Item(action: .viewHistory, emphasis: .primary)]
                : [
                    Item(action: .save, emphasis: .primary),
                    Item(action: .discardRequest, emphasis: .secondary)
                ]
        }
    }

    /// hero 主值着色：记录中 / 暂停取品牌 accent（暂停不切 warning），未开始取中性 primary。
    private static func heroTint(state: RunSessionState, didSave: Bool) -> Tint {
        if didSave { return .success }
        switch state {
        case .running, .paused: return .accent
        default: return .primary
        }
    }

    private static func discardConfirmation(
        state: RunSessionState,
        didSave: Bool
    ) -> DiscardConfirmation? {
        guard state == .finished, !didSave else { return nil }
        return DiscardConfirmation(
            cancel: Item(action: .cancel, emphasis: .secondary),
            confirm: Item(action: .discard, emphasis: .danger)
        )
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
