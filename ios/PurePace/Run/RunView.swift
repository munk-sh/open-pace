import SwiftUI
import PurePaceRunCore

/// 首屏跑步页：距离是唯一 hero（`display`），用时 / 当前配速是次级主值（`primaryValue`），
/// 平均配速 / 分段退为 `caption`；三态（未开始 / 跑步中 / 已保存总结）共用同一四层结构，
/// 只靠 hero 数值色与提示胶囊区分。样式全部取自 `DesignTokens`：零字面色值、零投影、
/// 分组只用 hairline 与 surface 明度差。所有数值来自 `RunSessionViewModel`（即
/// `RunSessionOrchestrator.metrics`），View 只做绑定与格式化。
struct RunView: View {
    @ObservedObject var viewModel: RunSessionViewModel
    /// 保存态主操作：切到历史 Tab（纯视图回调，不触碰状态机）。
    var onShowHistory: () -> Void = {}
    /// Reduce Motion 打开时时长归零（无动画）；读取环境，不用 `UIAccessibility` 单例。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            // 四层（hero → 次级指标 → 提示 → 主操作）在「导航栏下沿 → 主操作顶边」之间等量分布：
            // 固定间距只取语义 token，剩余空间由四个等权 Spacer(minLength:) 吸收，
            // 不出现顶对齐后把余量堆成单块死白的旧布局；
            // 小屏/大字号溢出时退回滚动，不截断内容。
            ViewThatFits(in: .vertical) {
                balancedMetrics
                ScrollView { metricsContent }
            }
            // DEBUG 诊断摘要不是指标内容块，贴内容区底部渲染，不参与居中。
            .overlay(alignment: .bottom) { telemetryOverlay }
            .background(DesignTokens.Colors.background)
            // 状态过渡只走 Motion token：Reduce Motion 打开时时长归零、无动画。
            .animation(.easeInOut(duration: DesignTokens.Motion.duration(DesignTokens.Motion.durationState, reduceMotion: reduceMotion)), value: viewModel.state)
            .animation(.easeInOut(duration: DesignTokens.Motion.duration(DesignTokens.Motion.durationState, reduceMotion: reduceMotion)), value: viewModel.didSave)
            .navigationTitle(L10n.runNavigationTitle)
            // 主操作固定底部控制区：安全区上方、TabBar 之上，三态共用同一锚点。
            .safeAreaInset(edge: .bottom) {
                controls
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(DesignTokens.Colors.surface)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(DesignTokens.Colors.separator)
                            .frame(height: DesignTokens.Stroke.hairline)
                    }
            }
            .onAppear { viewModel.onAppear() }
            // 倒计时只按注入时钟判定到点：未到点仅刷新剩余读数，不产生任何记录。
            .task(id: viewModel.isCountingDown) {
                while !Task.isCancelled {
                    let counting = await MainActor.run { viewModel.isCountingDown }
                    guard counting, !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return }
                    await MainActor.run { viewModel.advanceCountdown() }
                }
            }
        }
        .tint(DesignTokens.Colors.accent)
        .accessibilityIdentifier("tab.run")
    }

    // MARK: - 指标内容块

    /// 首屏等量分布：四个 Spacer 夹出四层，等权吸收余量（最小间距取语义 token）。
    private var balancedMetrics: some View {
        VStack(spacing: .zero) {
            Spacer(minLength: DesignTokens.Spacing.screenTop)
            distanceHero
            Spacer(minLength: DesignTokens.Spacing.cardGap)
            metricsPanel
            Spacer(minLength: DesignTokens.Spacing.sectionGap)
            hintLayer
            Spacer(minLength: DesignTokens.Spacing.sectionGap)
        }
        .padding(.horizontal, DesignTokens.Spacing.cardGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 三态共用的四层内容块：hero 距离 → 次级指标 → 提示 → （底部）主操作。
    /// 仅作为 ViewThatFits 的滚动退路，垂直余量不是本分支的职责。
    private var metricsContent: some View {
        VStack(spacing: DesignTokens.Spacing.sectionGap) {
            distanceHero
            metricsPanel
            hintLayer
        }
        .padding(DesignTokens.Spacing.cardGap)
        .frame(maxWidth: .infinity)
    }

    /// 第一层：hero 距离。全屏唯一 `display` 主值，面板底只用中性 surface，
    /// 三态区分只落在数值色上，不铺满整块状态弱底。
    private var distanceHero: some View {
        metricBlock(
            label: L10n.runMetricDistance,
            value: RunFormatting.distanceValueText(viewModel.metrics.distance),
            unit: RunFormatting.distanceUnitText,
            valueFont: DesignTokens.Typography.display,
            valueTint: stateTint,
            identifier: "run.distance",
            accessibilityText: viewModel.distanceText
        )
        .monospacedDigit()
        .padding(.vertical, DesignTokens.Spacing.lg)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(
            DesignTokens.Colors.surfaceMuted,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
    }

    /// 第二层：surface 卡片。用时 / 当前配速 `primaryValue`，平均配速 / 分段 `caption`；
    /// 两组之间只用 hairline 分层，不叠双描边卡片。
    private var metricsPanel: some View {
        VStack(spacing: DesignTokens.Spacing.metricGroupGap) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.metricGroupGap) {
                metricBlock(
                    label: L10n.runMetricTime,
                    value: viewModel.elapsedText,
                    unit: nil,
                    valueFont: DesignTokens.Typography.primaryValue,
                    valueTint: DesignTokens.Colors.primary,
                    identifier: "run.elapsed",
                    accessibilityText: viewModel.elapsedText
                )
                .monospacedDigit()
                metricBlock(
                    label: L10n.runMetricCurrent,
                    value: RunFormatting.paceValueText(viewModel.metrics.currentPace),
                    unit: RunFormatting.paceUnitText(viewModel.metrics.currentPace),
                    valueFont: DesignTokens.Typography.primaryValue,
                    valueTint: DesignTokens.Colors.primary,
                    identifier: "run.currentPace",
                    accessibilityText: viewModel.currentPaceText
                )
                .monospacedDigit()
            }

            Rectangle()
                .fill(DesignTokens.Colors.separator)
                .frame(height: DesignTokens.Stroke.hairline)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.metricGroupGap) {
                metricBlock(
                    label: L10n.runMetricAverage,
                    value: RunFormatting.paceValueText(viewModel.metrics.averagePace),
                    unit: RunFormatting.paceUnitText(viewModel.metrics.averagePace),
                    valueFont: DesignTokens.Typography.caption,
                    valueTint: DesignTokens.Colors.secondary,
                    identifier: "run.averagePace",
                    accessibilityText: viewModel.averagePaceText
                )
                .monospacedDigit()
                metricBlock(
                    label: L10n.runMetricSplits,
                    value: viewModel.splitCountText,
                    unit: nil,
                    valueFont: DesignTokens.Typography.caption,
                    valueTint: DesignTokens.Colors.secondary,
                    identifier: "run.splits",
                    accessibilityText: viewModel.splitCountText
                )
                .monospacedDigit()
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
    }

    // MARK: - 指标块

    /// 指标块统一三行：上置标签（`metricLabel`）→ 数值（等宽）→ 下置单位（`metricUnit`）。
    /// 无单位项（用时 / 分段 / 空配速）不渲染空单位行；可及 label 复原合并串，
    /// 保证既有 UI 用例的 label 相等断言不变。
    private func metricBlock(
        label: LocalizedStringKey,
        value: String,
        unit: String?,
        valueFont: Font,
        valueTint: Color,
        identifier: String,
        accessibilityText: String
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(label)
                .font(DesignTokens.Typography.metricLabel)
                .foregroundStyle(DesignTokens.Colors.secondary)
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueTint)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(Text(accessibilityText))
            if let unit {
                Text(unit)
                    .font(DesignTokens.Typography.metricUnit)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// DEBUG 门控的遥测诊断摘要（非用户可见文案），不参与指标区居中。
    @ViewBuilder
    private var telemetryOverlay: some View {
#if DEBUG
        if let summary = viewModel.telemetrySummary {
            Text(summary)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("run.telemetry")
                .padding(.horizontal, DesignTokens.Spacing.md)
                .allowsHitTesting(false)
        }
#endif
    }

    // MARK: - 三态视觉

    /// 记录中 accent / 暂停 warning / 保存 success / 未开始 primary。
    private var stateTint: Color {
        if viewModel.didSave { return DesignTokens.Colors.success }
        switch viewModel.state {
        case .running: return DesignTokens.Colors.accent
        case .paused: return DesignTokens.Colors.warning
        default: return DesignTokens.Colors.primary
        }
    }

    // MARK: - 第三层：提示

    @ViewBuilder
    private var hintLayer: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            // 倒计时读数留在提示层，不覆盖 hero / 指标卡。
            if let countdownText = plan.countdownText {
                Text(countdownText)
                    .font(DesignTokens.Typography.primaryValue)
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .monospacedDigit()
            }

            if let notice = plan.notice {
                noticeRow(notice)
            }

            if let recovery = plan.recovery {
                readinessControl(recovery)
            }

            if viewModel.didSave {
                Text(L10n.runStatusSaved)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.success)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.successSoft, in: Capsule())
                    .accessibilityIdentifier("run.saved")
            }
        }
    }

    /// 同屏只出一条提示，优先级由 plan 固定。
    @ViewBuilder
    private func noticeRow(_ notice: RunInteractionPlan.Notice) -> some View {
        switch notice {
        case .recordingError:
            if let message = viewModel.errorMessage {
                hint(message, tint: DesignTokens.Colors.secondary, soft: DesignTokens.Colors.surfaceMuted)
            }
        case .decisionFailed:
            if let message = viewModel.decisionErrorMessage {
                hint(message, tint: DesignTokens.Colors.secondary, soft: DesignTokens.Colors.surfaceMuted)
            }
        case .locationDenied:
            hint(L10n.locationDenied, tint: DesignTokens.Colors.secondary, soft: DesignTokens.Colors.surfaceMuted)
        case .locationUnavailable:
            hint(L10n.locationUnavailable, tint: DesignTokens.Colors.secondary, soft: DesignTokens.Colors.surfaceMuted)
        case .waitingAuthorization:
            hint(L10n.waitingAuthorization, tint: DesignTokens.Colors.secondary, soft: DesignTokens.Colors.surfaceMuted)
        case .backgroundDegraded:
            if let message = viewModel.authorization.backgroundDegradationHint {
                hint(message, tint: DesignTokens.Colors.warning, soft: DesignTokens.Colors.warningSoft)
                    .accessibilityIdentifier("run.backgroundDegraded")
            }
        }
    }

    /// 恢复入口只给 `L10n` 可读 label（identifier 集合冻结，不新增标识）。
    @ViewBuilder
    private func readinessControl(_ recovery: RunInteractionPlan.Recovery) -> some View {
        switch recovery {
        case .openSettings:
            if let url = viewModel.locationSettingsURL {
                Link(destination: url) {
                    Text(L10n.runActionOpenSettings)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .frame(minHeight: DesignTokens.minTapTarget)
                }
            }
        case .retryLocation:
            Button {
                viewModel.retryLocation()
            } label: {
                Text(L10n.runActionRetryLocation)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
        }
    }

    private func hint(_ message: String, tint: Color, soft: Color) -> some View {
        Text(message)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(soft, in: Capsule())
    }

    // MARK: - 主操作

    /// 视图唯一决策入口：所有可见操作 / 提示 / 恢复动作 / 过渡时长都来自 plan。
    private var plan: RunInteractionPlan {
        RunInteractionPlan(viewModel: viewModel, reduceMotion: reduceMotion)
    }

    /// 主操作强调色：未开始与记录中共用唯一品牌 accent。
    private var actionTint: Color {
        viewModel.state == .ready ? DesignTokens.Colors.accent : stateTint
    }

    private var actionOnTint: Color {
        if viewModel.didSave { return DesignTokens.Colors.onSuccess }
        switch viewModel.state {
        case .running, .ready: return DesignTokens.Colors.onAccent
        case .paused: return DesignTokens.Colors.onWarning
        // 待决策主操作（保存）与未开始共用中性/品牌底色，文字取主色底上的同款反白。
        case .finished: return DesignTokens.Colors.onAccent
        }
    }

    @ViewBuilder
    private var controls: some View {
        if plan.items.count == 1, let item = plan.items.first {
            control(for: item)
        } else {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(plan.items, id: \.action) { item in
                    control(for: item)
                }
            }
        }
    }

    /// 动作 → 既有 `L10n` 文案；强调级别由 plan 的 `emphasis` 决定。
    @ViewBuilder
    private func control(for item: RunInteractionPlan.Item) -> some View {
        switch item.action {
        case .start:
            styledControl(item, title: L10n.runActionStart, label: L10n.runStartLabel) {
                viewModel.start()
            }
            .accessibilityIdentifier("run.start")
        case .cancelCountdown:
            styledControl(item, title: L10n.runActionCancel, label: L10n.runCancelCountdownLabel) {
                viewModel.cancelCountdown()
            }
            .accessibilityIdentifier("run.cancelCountdown")
        case .pause:
            styledControl(item, title: L10n.runActionPause, label: L10n.runPauseLabel) {
                viewModel.pause()
            }
            .accessibilityIdentifier("run.pause")
        case .resume:
            styledControl(item, title: L10n.runActionResume, label: L10n.runResumeLabel) {
                viewModel.resume()
            }
            .accessibilityIdentifier("run.resume")
        case .finish:
            styledControl(item, title: L10n.runActionFinish, label: L10n.runFinishLabel) {
                viewModel.finish()
            }
            .accessibilityIdentifier("run.finish")
        case .save:
            styledControl(item, title: L10n.runActionSave, label: L10n.runSaveLabel) {
                viewModel.saveFinished()
            }
            .accessibilityIdentifier("run.save")
        case .discard:
            styledControl(item, title: L10n.runActionDiscard, label: L10n.runDiscardLabel) {
                viewModel.discardFinished()
            }
            .accessibilityIdentifier("run.discard")
        case .viewHistory:
            styledControl(item, title: L10n.runActionViewHistory, label: L10n.runViewHistoryLabel) {
                onShowHistory()
            }
            .accessibilityIdentifier("run.viewHistory")
        }
    }

    @ViewBuilder
    private func styledControl(
        _ item: RunInteractionPlan.Item,
        title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        switch item.emphasis {
        case .primary:
            primaryControl(title, label: label, action: action)
        case .secondary:
            secondaryControl(title, label: label, action: action)
        }
    }

    /// 每态唯一填充主操作：同高（`minTapTarget`）、同行高、同一底部安全区锚点。
    private func primaryControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.control)
                .foregroundStyle(actionOnTint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .background(
            actionTint,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
        )
        .accessibilityLabel(Text(label))
    }

    /// 结束（破坏性）操作：内在宽度 + warning 描边、无填充底，明显弱于同排主操作，
    /// 但仍保留 ≥ `minTapTarget` 点按区与同一可及 label。
    private func secondaryControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.warning)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .stroke(DesignTokens.Colors.warning, lineWidth: DesignTokens.Stroke.hairline)
        }
        .accessibilityLabel(Text(label))
    }
}
