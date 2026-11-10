import SwiftUI

/// 首屏跑步页：距离 / 时长 / 当前配速为强主信息，平均配速与分段为次信息；
/// 开始 / 暂停 / 继续 / 结束是唯一主操作区，三态可辨。样式全部取自 `DesignTokens`。
/// 所有数值来自 `RunSessionViewModel`（即 `RunSessionOrchestrator.metrics`），View 只做绑定与格式化。
struct RunView: View {
    @ObservedObject var viewModel: RunSessionViewModel
    /// 保存态主操作：切到历史 Tab（纯视图回调，不触碰状态机）。
    var onShowHistory: () -> Void = {}

    var body: some View {
        NavigationStack {
            // 指标内容块整体在「导航栏下沿 → 底部控制区上沿」之间垂直居中；
            // 小屏/大字号溢出时退回滚动，不截断内容。
            ViewThatFits(in: .vertical) {
                VStack {
                    Spacer(minLength: DesignTokens.Spacing.md)
                    metricsContent
                    Spacer(minLength: DesignTokens.Spacing.md)
                }
                ScrollView { metricsContent }
            }
            // DEBUG 诊断摘要不是指标内容块，贴内容区底部渲染，不参与居中。
            .overlay(alignment: .bottom) { telemetryOverlay }
            .background(DesignTokens.Colors.background)
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
        }
        .tint(DesignTokens.Colors.accent)
        .accessibilityIdentifier("tab.run")
    }

    // MARK: - 指标内容块

    /// 三态共用的四层内容块：hero 距离 → 次级指标 → 提示 → （底部）主操作。
    private var metricsContent: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            distanceHero
            metricsPanel
            hintLayer
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity)
    }

    /// 第一层：hero 距离，全屏最大字号；底色随三态变化。
    private var distanceHero: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(viewModel.distanceText)
                .font(DesignTokens.Typography.display)
                .foregroundStyle(stateTint)
                .monospacedDigit()
                .accessibilityIdentifier("run.distance")
            Text(L10n.runMetricDistance)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            stateSoft,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                .stroke(DesignTokens.Colors.separator)
        }
    }

    /// 第二层：surface 卡片面里的时长 / 当前配速（primaryValue）与平均配速 / 分段（caption）。
    private var metricsPanel: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                primaryMetric(
                    title: L10n.runMetricTime,
                    value: viewModel.elapsedText,
                    identifier: "run.elapsed"
                )
                primaryMetric(
                    title: L10n.runMetricCurrent,
                    value: viewModel.currentPaceText,
                    identifier: "run.currentPace"
                )
            }

            Rectangle()
                .fill(DesignTokens.Colors.separator)
                .frame(height: DesignTokens.Stroke.hairline)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                secondaryMetric(
                    title: L10n.runMetricAverage,
                    value: viewModel.averagePaceText,
                    identifier: "run.averagePace"
                )
                secondaryMetric(
                    title: L10n.runMetricSplits,
                    value: viewModel.splitCountText,
                    identifier: "run.splits"
                )
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator)
        }
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

    /// 与 `stateTint` 配套的弱底：记录态 / 暂停 / 保存各有一块可辨认的底。
    private var stateSoft: Color {
        if viewModel.didSave { return DesignTokens.Colors.successSoft }
        switch viewModel.state {
        case .running: return DesignTokens.Colors.accentSoft
        case .paused: return DesignTokens.Colors.warningSoft
        default: return DesignTokens.Colors.surfaceMuted
        }
    }

    // MARK: - 主信息

    private func primaryMetric(
        title: LocalizedStringKey,
        value: String,
        identifier: String
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(value)
                .font(DesignTokens.Typography.primaryValue)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 次信息

    private func secondaryMetric(
        title: LocalizedStringKey,
        value: String,
        identifier: String
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(value)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 第三层：提示

    @ViewBuilder
    private var hintLayer: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            if let message = statusMessage {
                hint(message, tint: DesignTokens.Colors.secondary, soft: DesignTokens.Colors.surfaceMuted)
            }

            if let hintMessage = viewModel.authorization.backgroundDegradationHint {
                hint(hintMessage, tint: DesignTokens.Colors.warning, soft: DesignTokens.Colors.warningSoft)
                    .accessibilityIdentifier("run.backgroundDegraded")
            }

            if viewModel.didSave {
                Text(L10n.runStatusSaved)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.success)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.successSoft, in: Capsule())
                    .accessibilityIdentifier("run.saved")
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

    private var statusMessage: String? {
        if let error = viewModel.errorMessage {
            return error
        }
        if viewModel.state == .ready {
            switch viewModel.authorization {
            case .denied, .restricted:
                return L10n.locationDenied
            case .notDetermined:
                return L10n.waitingAuthorization
            case .authorizedWhenInUse, .authorizedAlways:
                return nil
            }
        }
        return nil
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
        case .finished: return DesignTokens.Colors.onSuccess
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.state {
        case .ready:
            primaryControl(L10n.runActionStart, label: L10n.runStartLabel) {
                viewModel.start()
            }
            .accessibilityIdentifier("run.start")
        case .running:
            HStack(spacing: DesignTokens.Spacing.sm) {
                primaryControl(L10n.runActionPause, label: L10n.runPauseLabel) { viewModel.pause() }
                    .accessibilityIdentifier("run.pause")
                secondaryControl(L10n.runActionFinish, label: L10n.runFinishLabel) { viewModel.finish() }
                    .accessibilityIdentifier("run.finish")
            }
        case .paused:
            HStack(spacing: DesignTokens.Spacing.sm) {
                primaryControl(L10n.runActionResume, label: L10n.runResumeLabel) { viewModel.resume() }
                    .accessibilityIdentifier("run.resume")
                secondaryControl(L10n.runActionFinish, label: L10n.runFinishLabel) { viewModel.finish() }
                    .accessibilityIdentifier("run.finish")
            }
        case .finished:
            if viewModel.didSave {
                primaryControl(L10n.runActionViewHistory, label: L10n.runViewHistoryLabel) {
                    onShowHistory()
                }
                .accessibilityIdentifier("run.viewHistory")
            }
        }
    }

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

    private func secondaryControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.control)
                .foregroundStyle(DesignTokens.Colors.warning)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .background(
            DesignTokens.Colors.warningSoft,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .stroke(DesignTokens.Colors.warning)
        }
        .accessibilityLabel(Text(label))
    }
}
