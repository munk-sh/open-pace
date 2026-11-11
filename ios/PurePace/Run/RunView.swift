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
    /// 丢弃确认层开合：结束待保存屏的破坏性动作必须先经过这里。
    @State private var showsDiscardConfirmation = false

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
            // 记录态（running / paused）与结束待保存态收起底部三 Tab；idle / 保存总结
            // 显式恢复可见。判定只读状态与 `didSave`，同一进程内不留只能杀进程的断头路。
            .toolbar(
                TabBarVisibilityPolicy.hidesTabBar(
                    state: viewModel.state,
                    didSave: viewModel.didSave
                ) ? .hidden : .visible,
                for: .tabBar
            )
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
        .sheet(isPresented: $showsDiscardConfirmation) {
            discardConfirmationSheet
        }
    }

    // MARK: - 指标内容块

    /// 首屏等量分布：四个 Spacer 夹出四层，等权吸收余量（最小间距取语义 token）。
    private var balancedMetrics: some View {
        VStack(spacing: .zero) {
            Spacer(minLength: DesignTokens.Spacing.screenTop)
            distanceHero
            Spacer(minLength: DesignTokens.Spacing.cardGap)
            metricsPanel
            if viewModel.state == .finished {
                finishedTrackSummary
            }
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
            if viewModel.state == .finished {
                finishedTrackSummary
            }
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
            valueTint: color(for: plan.heroTint),
            identifier: "run.distance",
            accessibilityText: viewModel.distanceText
        )
        .monospacedDigit()
        // hero 卡只留上呼吸位：把既有底部空白让给层间 Spacer，
        // 使 hero→指标卡的空洞落在 80pt 上界内（无新增占位、无阈值改动）。
        .padding(.top, DesignTokens.Spacing.sm)
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
        // 指标卡底部补 4pt 既有空白，把等权 Spacer 的余量从底部分走一档。
        .padding(.bottom, DesignTokens.Spacing.xxs)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
    }

    // MARK: - 结束态总结（仅 finished）

    /// 结束态专属：轨迹预览卡（与详情页同一 `TrackMapView`）+ 分段明细。
    /// 记录态 / 暂停 / 未开始一律不出现这些块。
    private var finishedTrackSummary: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            TrackMapView(
                samples: viewModel.acceptedSamples,
                emptyIdentifier: "run.mapEmpty",
                singlePointIdentifier: "run.mapEmpty.single"
            )
            .frame(height: 180)
            splitsDetail
        }
    }

    /// 分段明细：有分段逐段渲染「序号 + 配速」，无分段给明确中文替代文案。
    private var splitsDetail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(L10n.runSplitsDetailTitle)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .accessibilityIdentifier("run.finished.splits")
                .accessibilityLabel(Text(L10n.runSplitsDetailTitle))
            if viewModel.metrics.splits.isEmpty {
                Text(L10n.runFinishedSplitsEmpty)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .accessibilityIdentifier("run.finished.splitsEmpty")
                    .accessibilityLabel(Text(L10n.runFinishedSplitsEmpty))
            } else {
                ForEach(viewModel.metrics.splits, id: \.index) { split in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(RunFormatting.splitIndexText(split.index))
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.primary)
                            .monospacedDigit()
                        Spacer(minLength: DesignTokens.Spacing.xs)
                        Text(RunFormatting.paceText(split.pace))
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("run.finished.splitRow")
                    .accessibilityLabel(Text(L10n.runSplitsDetailTitle))
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                hint(message, tint: color(for: notice.tint), soft: DesignTokens.Colors.warningSoft)
            }
        case .decisionFailed:
            if let message = viewModel.decisionErrorMessage {
                hint(message, tint: color(for: notice.tint), soft: DesignTokens.Colors.warningSoft)
            }
        case .locationDenied:
            hint(L10n.locationDenied, tint: color(for: notice.tint), soft: DesignTokens.Colors.warningSoft)
        case .locationUnavailable:
            hint(L10n.locationUnavailable, tint: color(for: notice.tint), soft: DesignTokens.Colors.warningSoft)
        case .waitingAuthorization:
            hint(L10n.waitingAuthorization, tint: color(for: notice.tint), soft: DesignTokens.Colors.warningSoft)
        case .backgroundDegraded:
            if let message = viewModel.authorization.backgroundDegradationHint {
                // 后台定位降级降为指标卡下方的紧凑 `caption` 次级行：无胶囊底、无整宽弱底。
                // 仍是 warning 语义的非阻断内联提示，不进入 hero / 主操作着色。
                Text(message)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(color(for: notice.tint))
                    .multilineTextAlignment(.center)
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

    /// 主操作强调色：记录态主操作族（开始 / 暂停 / 继续 / 结束 / 保存）统一品牌 accent，
    /// 已保存总结仍取 success；warning 不参与任何主操作着色。
    private var actionTint: Color {
        viewModel.didSave ? DesignTokens.Colors.success : DesignTokens.Colors.accent
    }

    private var actionOnTint: Color {
        viewModel.didSave ? DesignTokens.Colors.onSuccess : DesignTokens.Colors.onAccent
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
        case .discardRequest:
            // 结束待保存屏只给确认层入口：破坏性动作不得直调 `discardFinished()`。
            styledControl(item, title: L10n.runActionDiscard, label: L10n.runDiscardLabel) {
                showsDiscardConfirmation = true
            }
            .accessibilityIdentifier("run.discardRequest")
        case .discard:
            // 仅确认层渲染；确认后才真正丢弃并回到 ready。
            styledControl(item, title: L10n.runDiscardConfirmConfirm, label: L10n.runDiscardLabel) {
                showsDiscardConfirmation = false
                viewModel.discardFinished()
            }
            .accessibilityIdentifier("run.discard")
        case .cancel:
            styledControl(item, title: L10n.runDiscardConfirmCancel, label: L10n.runActionCancel) {
                showsDiscardConfirmation = false
            }
            .accessibilityIdentifier("run.discardCancel")
        case .viewHistory:
            styledControl(item, title: L10n.runActionViewHistory, label: L10n.runViewHistoryLabel) {
                onShowHistory()
            }
            .accessibilityIdentifier("run.viewHistory")
        }
    }

    /// plan 的 tint → palette 唯一着色入口；View 不再按动作各自 `switch` 颜色。
    private func color(for tint: RunInteractionPlan.Tint) -> Color {
        switch tint {
        case .accent: return DesignTokens.Colors.accent
        case .success: return DesignTokens.Colors.success
        case .secondary: return DesignTokens.Colors.secondary
        case .primary: return DesignTokens.Colors.primary
        case .danger: return DesignTokens.Colors.danger
        case .warning: return DesignTokens.Colors.warning
        }
    }

    @ViewBuilder
    private func styledControl(
        _ item: RunInteractionPlan.Item,
        title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        switch item.style {
        case .primaryAccent:
            primaryControl(title, label: label, action: action)
        case .accentOutline:
            outlineControl(
                title,
                label: label,
                tint: color(for: item.tint),
                lineWidth: DesignTokens.Stroke.hairline * 2,
                action: action
            )
        case .neutralOutline, .dangerOutline:
            outlineControl(title, label: label, tint: color(for: item.tint), action: action)
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

    /// 非填充描边控件：结束取 accent、入口取中性、确认层丢弃取 danger；
    /// 无填充底（不与唯一填充主操作同形状并列），仍保留 ≥ `minTapTarget` 点按区与可及 label。
    private func outlineControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        tint: Color,
        lineWidth: CGFloat = DesignTokens.Stroke.hairline,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(tint)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .strokeBorder(tint, lineWidth: lineWidth)
        }
        .accessibilityLabel(Text(label))
    }

    // MARK: - 丢弃确认层

    /// 唯一破坏性确认层：标题 / 说明 / 取消 / 丢弃全部走 `L10n`，丢弃为 danger 描边无填充。
    @ViewBuilder
    private var discardConfirmationSheet: some View {
        if let confirmation = plan.discardConfirmation {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text(L10n.runDiscardConfirmTitle)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.primary)
                Text(L10n.runDiscardConfirmMessage)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    control(for: confirmation.cancel)
                    control(for: confirmation.confirm)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}
