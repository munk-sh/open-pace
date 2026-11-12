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
    /// 动态字号档：结束态总结（地图预览 + 分段明细）据此压缩垂直预算，保证 AX5 不溢屏。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 丢弃确认层开合：结束待保存屏的破坏性动作必须先经过这里。
    @State private var showsDiscardConfirmation = false
    /// C2 sheet 的内容实测高度：由内容驱动 detent，不落 `.medium` 固定档。
    @State private var discardSheetContentHeight = RunFinishedSummaryLayoutPolicy.discardSheetFallbackHeight

    var body: some View {
        NavigationStack {
            // 四层（hero → 次级指标 → 提示 → 主操作）在「导航栏下沿 → 主操作顶边」之间等量分布：
            // 固定间距只取语义 token，剩余空间由四个等权 Spacer(minLength:) 吸收，
            // 不出现顶对齐后把余量堆成单块死白的旧布局；
            // 小屏/大字号溢出时由滚动容器自然承载，不截断、不压到底部主操作上。
            // 滚动体用 `minHeight` 撑满视口（不是 `maxHeight: .infinity`）：内容不溢出时余量
            // 仍由 Spacer 等权吸收，溢出时以内容本身高度滚动，`ViewThatFits` 不再有「永远选中
            // 第一分支、退不回滚动」的入口。
            GeometryReader { proxy in
                ScrollView {
                    if viewModel.state == .finished {
                        // B1 只定义「结束待保存态」的顶对齐 hero 版式；已保存态用上下等权
                        // Spacer 保持既有「保存总结垂直居中」观感（`assertRunMetricsBalanced` 判据不变）。
                        if viewModel.didSave {
                            VStack(spacing: .zero) {
                                // 保存态与底部主操作条共用同一内容区：条内已有 12pt 上内边距，
                                // 顶部多补一档 `md` 让内容块在「导航栏下沿 → 主操作顶边」之间光学居中
                                // （`assertRunMetricsBalanced` 的上下留白差 ≤ 16pt 判据不变）。
                                Spacer(minLength: DesignTokens.Spacing.md)
                                finishedContent(
                                    compresses: RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                                        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                        availableContentHeight: proxy.size.height
                                    )
                                )
                                Spacer(minLength: DesignTokens.Spacing.sm)
                            }
                            .frame(minHeight: proxy.size.height)
                        } else {
                            finishedContent(
                                compresses: RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                    availableContentHeight: proxy.size.height
                                )
                            )
                            .frame(minHeight: proxy.size.height, alignment: .top)
                        }
                    } else {
                        balancedMetrics(
                            compressesFinishedSummary: RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                availableContentHeight: proxy.size.height
                            )
                        )
                        .frame(minHeight: proxy.size.height)
                    }
                }
            }
            // DEBUG 诊断摘要不是指标内容块，贴内容区底部渲染，不参与居中。
            .overlay(alignment: .bottom) { telemetryOverlay }
            .background(DesignTokens.Colors.background)
            // 状态过渡只走 Motion token：Reduce Motion 打开时时长归零、无动画。
            .animation(.easeInOut(duration: DesignTokens.Motion.duration(DesignTokens.Motion.durationState, reduceMotion: reduceMotion)), value: viewModel.state)
            .animation(.easeInOut(duration: DesignTokens.Motion.duration(DesignTokens.Motion.durationState, reduceMotion: reduceMotion)), value: viewModel.didSave)
            .navigationTitle(L10n.runNavigationTitle)
            // B1 结束态用 inline 标题（不占大标题高度），把垂直预算全部让给地图 hero。
            .navigationBarTitleDisplayMode(viewModel.state == .finished ? .inline : .large)
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
                    .frame(minHeight: RunFinishedSummaryLayoutPolicy.actionBarHeight)
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
        .tint(DesignTokens.Colors.primary)
        .accessibilityIdentifier("tab.run")
        .sheet(isPresented: $showsDiscardConfirmation) {
            discardConfirmationSheet
        }
    }

    // MARK: - 指标内容块

    /// 首屏等量分布：四个 Spacer 夹出四层，等权吸收余量（最小间距取语义 token）。
    /// 只声明宽度弹性：若这里再给 `maxHeight: .infinity`，`ViewThatFits` 量到的理想高度
    /// 被撑成整个可用高度而永远选中本分支，内容溢出时退不回下面的滚动分支
    /// （结束态 `run.backgroundDegraded` 压到 `run.save` 上即由此产生）。
    private func balancedMetrics(compressesFinishedSummary: Bool) -> some View {
        // 压缩槽位只作用于结束态：未开始 / 运行中 / 暂停仍用既有语义 token，实测留白不回归。
        let compresses = compressesFinishedSummary && viewModel.state == .finished
        return VStack(spacing: .zero) {
            if compresses {
                Spacer(minLength: RunFinishedSummaryLayoutPolicy.topBreathing(compresses: true))
            } else {
                Spacer(minLength: DesignTokens.Spacing.screenTop)
            }
            distanceHero(compresses: compresses)
            if compresses {
                Spacer(minLength: RunFinishedSummaryLayoutPolicy.heroMetricsGap(compresses: true))
            } else {
                Spacer(minLength: DesignTokens.Spacing.cardGap)
            }
            metricsPanel(compresses: compresses)
            Spacer(minLength: DesignTokens.Spacing.sectionGap)
            hintLayer
            Spacer(minLength: DesignTokens.Spacing.sectionGap)
        }
        .padding(.horizontal, DesignTokens.Spacing.cardGap)
        .frame(maxWidth: .infinity)
    }

    /// 第一层：hero 距离。全屏唯一 `display` 主值，面板底只用中性 surface，
    /// 三态区分只落在数值色上，不铺满整块状态弱底。
    /// 单位单独一行（`metricBlock` 既有三行口径）：若把 display 与单位并入同一 `Text`，
    /// hero 末行变成 64pt 行盒，行盒下沿与静态文本 frame 相差约 21pt，
    /// 会被首屏居中判据计成 hero→指标卡空洞（实测 89.9pt > 80pt）。
    private func distanceHero(compresses: Bool) -> some View {
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
        .padding(.top, RunFinishedSummaryLayoutPolicy.heroTopPadding(compresses: compresses))
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
    private func metricsPanel(compresses: Bool) -> some View {
        VStack(spacing: RunFinishedSummaryLayoutPolicy.metricGroupGap(compresses: compresses)) {
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
        .padding(RunFinishedSummaryLayoutPolicy.metricCardPadding(compresses: compresses))
        // 指标卡底部补 4pt 既有空白，把等权 Spacer 的余量从底部分走一档（压缩档归零回收余量）。
        .padding(.bottom, RunFinishedSummaryLayoutPolicy.metricCardBottomPadding(compresses: compresses))
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
    }

    // MARK: - 结束态 B1（地图 hero + 指标行 + 分段 + inline 提示）

    /// B1 结束待保存态：地图 hero 360pt → 指标行 → 分段明细 → inline 提示，
    /// 内容合计按 `finishedContentHeightBudget`（≤ 691）排布；不再保留独立距离 hero 卡，
    /// 距离作为地图上的常显值（仍是 `run.distance`），指标行承载时长 + 平均配速。
    private func finishedContent(compresses: Bool) -> some View {
        VStack(spacing: RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: compresses)) {
            finishedMapHero(compresses: compresses)
            finishedMetricsRow(compresses: compresses)
            splitsDetail(compresses: compresses)
            if plan.notice != nil || plan.recovery != nil || viewModel.didSave {
                hintLayer
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.cardGap)
        .padding(.top, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity)
    }

    /// B1 地图 hero：`TrackMapView` 真实轨迹 + 左下距离常显值。
    /// 空轨迹 / 单点由地图壳自己给明确中文空态，不构造裸 `Map`、不留白。
    private func finishedMapHero(compresses: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            TrackMapView(
                samples: viewModel.acceptedSamples,
                emptyIdentifier: "run.mapEmpty",
                singlePointIdentifier: "run.mapEmpty.single"
            )
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Text(RunFormatting.distanceValueText(viewModel.metrics.distance))
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.primary)
                    .monospacedDigit()
                    .accessibilityIdentifier("run.distance")
                    .accessibilityLabel(Text(viewModel.distanceText))
                Text(RunFormatting.distanceUnitText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                DesignTokens.Colors.surface,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
            )
            .padding(RunFinishedSummaryLayoutPolicy.cardPadding(compresses: compresses))
        }
        .frame(
            height: RunFinishedSummaryLayoutPolicy.trackPreviewHeight(
                compresses: compresses,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
        )
    }

    /// B1 指标行：时长 + 平均配速两项常显（距离已在地图 hero 上）。
    private func finishedMetricsRow(compresses: Bool) -> some View {
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
                label: L10n.runMetricAverage,
                value: RunFormatting.paceValueText(viewModel.metrics.averagePace),
                unit: RunFormatting.paceUnitText(viewModel.metrics.averagePace),
                valueFont: DesignTokens.Typography.primaryValue,
                valueTint: DesignTokens.Colors.primary,
                identifier: "run.averagePace",
                accessibilityText: viewModel.averagePaceText
            )
            .monospacedDigit()
        }
        .padding(RunFinishedSummaryLayoutPolicy.metricCardPadding(compresses: compresses))
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
    }

    /// 分段明细：有分段逐段渲染「序号 + 配速」，无分段给明确中文替代文案。
    private func splitsDetail(compresses: Bool) -> some View {
        VStack(alignment: .leading, spacing: RunFinishedSummaryLayoutPolicy.rowSpacing(compresses: compresses)) {
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
        .padding(RunFinishedSummaryLayoutPolicy.cardPadding(compresses: compresses))
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
                    // 单位行是用户可见内容且占据垂直空间：保留在可及树里，
                    // 否则首屏居中判据会把「数值→下一块」的真实间距虚增一整个单位行。
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
                    .foregroundStyle(DesignTokens.Colors.primary)
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
                // 后台定位降级是单行紧凑胶囊（图标 + 短文案，实测约 23.7pt 高、宽度由内容决定），
                // 仍是 warning 语义的非阻断内联提示，不进入 hero / 主操作着色；动作入口由就绪态
                // 「打开设置」Link 承担，胶囊本身不承诺可点（24pt 胶囊给不了 44pt 点按区）。
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "location.slash")
                        .font(DesignTokens.Typography.caption)
                    Text(L10n.backgroundDegradedHintShort)
                        .font(DesignTokens.Typography.caption)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(color(for: notice.tint))
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.warningSoft, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(message))
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
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.primary)
                        .frame(minHeight: DesignTokens.minTapTarget)
                }
            }
        case .retryLocation:
            Button {
                viewModel.retryLocation()
            } label: {
                Text(L10n.runActionRetryLocation)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.primary)
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
        case .neutralOutline:
            outlineControl(title, label: label, tint: color(for: item.tint), action: action)
        case .textSecondary:
            textControl(title, label: label, action: action)
        case .dangerFilled:
            filledControl(
                title,
                label: label,
                tint: color(for: item.tint),
                onTint: DesignTokens.Colors.onDanger,
                action: action
            )
        }
    }

    /// 每态唯一填充主操作：同高（`minTapTarget`）、同行高、同一底部安全区锚点。
    private func primaryControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        filledControl(
            title,
            label: label,
            tint: actionTint,
            onTint: actionOnTint,
            action: action
        )
    }

    /// 唯一填充控件（主操作 / 确认层破坏性主操作）：实心底 + 高对比文字，`minTapTarget` 高。
    private func filledControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        tint: Color,
        onTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.control)
                .foregroundStyle(onTint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .background(
            tint,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
        )
        .accessibilityLabel(Text(label))
    }

    /// 无填充 / 无边框文字次操作（C2 取消、结束屏丢弃入口）：不与填充主操作同形状。
    private func textControl(
        _ title: LocalizedStringKey,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
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
                // 浅色下 accent 只作填充/描边：文字层级恒用 primary，靠描边与字重区分主次。
                .foregroundStyle(DesignTokens.Colors.primary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .strokeBorder(tint, lineWidth: lineWidth)
        }
        .accessibilityLabel(Text(label))
    }

    // MARK: - 丢弃确认层（C2 图标式紧凑版）

    /// 唯一破坏性确认层：图标块 + 标题/说明行内排布 + 「唯一填充 danger 主操作 + 无填充取消」同行。
    /// 标题 / 说明 / 取消 / 丢弃全部走 `L10n`；sheet 高度由内容自适应（无 `.medium` 固定档），
    /// 破坏性 danger 只出现在本层，不与 accent 填充主操作同屏同形状并列。
    @ViewBuilder
    private var discardConfirmationSheet: some View {
        if let confirmation = plan.discardConfirmation {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.danger)
                        .frame(
                            width: DesignTokens.Spacing.xl + DesignTokens.Spacing.xs,
                            height: DesignTokens.Spacing.xl + DesignTokens.Spacing.xs
                        )
                        .background(
                            DesignTokens.Colors.dangerSoft,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(L10n.runDiscardConfirmTitle)
                            .font(DesignTokens.Typography.title)
                            .foregroundStyle(DesignTokens.Colors.primary)
                        Text(L10n.runDiscardConfirmMessage)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: DesignTokens.Spacing.sm) {
                    control(for: confirmation.confirm)
                    control(for: confirmation.cancel)
                }
            }
            .padding(.top, DesignTokens.Spacing.xs)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface)
            // C2 自适应高度：iPhone 底部 sheet 不认 `.presentationSizing(.fitted)`，
            // 改为实测内容高度驱动 detent（内容驱动，不是 `.medium` 固定档）。
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                if height > 0 {
                    discardSheetContentHeight = height
                }
            }
            .presentationDetents([.height(discardSheetContentHeight)])
            .presentationDragIndicator(.visible)
        }
    }
}

