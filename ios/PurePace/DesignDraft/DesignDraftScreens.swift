#if DEBUG
import SwiftUI

/// A 组：浅色主色候选（A1 / A2）在 6 屏上的真实渲染。
/// 两套候选共用**同一份渲染代码**，只有 `palette.accent` / `palette.onAccent` 不同，
/// 其余 token（背景 / 卡片 / 字号 / 间距 / 圆角）全部取 `DesignTokens`，保证对照口径唯一。
struct DesignDraftRunScreen: View {
    enum State {
        case notStarted
        case running
        case finished
    }

    let palette: DesignDraftPalette
    let state: State
    let variant: DesignDraftV12.Variant

    var body: some View {
        DesignDraftTabShell(palette: palette, selected: 0) {
            NavigationStack {
                VStack(spacing: 0) {
                    Spacer(minLength: topBreathing)
                    hero
                    Spacer(minLength: heroMetricsGap)
                    metricsPanel
                    if state == .finished {
                        Spacer(minLength: DesignTokens.Spacing.sectionGap)
                        mapPreview
                        Spacer(minLength: blockGap)
                        splitsCard
                    }
                    Spacer(minLength: DesignTokens.Spacing.sectionGap)
                    permissionHint
                    Spacer(minLength: bottomBreathing)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.Colors.background)
                .designDraftProbe("run.content", variant: variant.rawValue)
                .navigationTitle(L10n.runNavigationTitle)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    DesignDraftActionBar { actionControls }
                }
            }
        }
    }

    // MARK: 垂直槽位（结束态照抄生产压缩档，其余态用语义间距）

    private var topBreathing: CGFloat {
        state == .finished
            ? RunFinishedSummaryLayoutPolicy.topBreathing(compresses: true)
            : DesignTokens.Spacing.screenTop
    }

    private var heroMetricsGap: CGFloat {
        state == .finished
            ? RunFinishedSummaryLayoutPolicy.heroMetricsGap(compresses: true)
            : DesignTokens.Spacing.cardGap
    }

    private var blockGap: CGFloat {
        RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: true)
    }

    private var bottomBreathing: CGFloat {
        state == .finished ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.sectionGap
    }

    private var metricPadding: CGFloat {
        state == .finished
            ? RunFinishedSummaryLayoutPolicy.metricCardPadding(compresses: true)
            : DesignTokens.Spacing.cardPadding
    }

    private var metricGroupGapValue: CGFloat {
        state == .finished
            ? RunFinishedSummaryLayoutPolicy.metricGroupGap(compresses: true)
            : DesignTokens.Spacing.metricGroupGap
    }

    private var splitsPadding: CGFloat {
        RunFinishedSummaryLayoutPolicy.cardPadding(compresses: true)
    }

    private var splitsRowSpacing: CGFloat {
        RunFinishedSummaryLayoutPolicy.rowSpacing(compresses: true)
    }

    // MARK: 内容值

    private var distanceText: String {
        state == .notStarted ? "0.00" : DesignDraftFixture.distanceText
    }

    private var durationText: String {
        state == .notStarted ? "00:00" : DesignDraftFixture.durationText
    }

    private var averagePaceText: String {
        state == .notStarted ? "--" : DesignDraftFixture.averagePaceText
    }

    private var splitsText: String {
        state == .notStarted ? "0" : DesignDraftFixture.splitsSummaryText
    }

    // MARK: 区块

    /// hero：距离数字为全屏最大字，记录态用候选主色（与现网同一着色语义）。
    private var hero: some View {
        VStack(spacing: 0) {
            Text(L10n.runMetricDistance)
                .font(DesignTokens.Typography.metricLabel)
                .foregroundStyle(DesignTokens.Colors.secondary)
            Text(distanceText)
                .font(DesignTokens.Typography.display)
                .foregroundStyle(
                    state == .running ? palette.accent : DesignTokens.Colors.primary
                )
                .monospacedDigit()
            Text(verbatim: "km")
                .font(DesignTokens.Typography.metricUnit)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity)
        .background(
            DesignTokens.Colors.surfaceMuted,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .designDraftProbe("run.hero", variant: variant.rawValue)
    }

    private var metricsPanel: some View {
        VStack(spacing: metricGroupGapValue) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                DesignDraftMetric(
                    label: L10n.runMetricTime,
                    value: durationText,
                    unit: nil,
                    valueFont: DesignTokens.Typography.primaryValue,
                    valueColor: DesignTokens.Colors.primary
                )
                DesignDraftMetric(
                    label: L10n.runMetricCurrent,
                    value: "--:--",
                    unit: nil,
                    valueFont: DesignTokens.Typography.primaryValue,
                    valueColor: DesignTokens.Colors.primary
                )
            }
            Rectangle()
                .fill(DesignTokens.Colors.separator)
                .frame(height: DesignTokens.Stroke.hairline)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                DesignDraftMetric(
                    label: L10n.runMetricAverage,
                    value: averagePaceText,
                    unit: state == .notStarted ? nil : "/km",
                    valueFont: DesignTokens.Typography.caption,
                    valueColor: DesignTokens.Colors.primary
                )
                DesignDraftMetric(
                    label: L10n.runMetricSplits,
                    value: splitsText,
                    unit: nil,
                    valueFont: DesignTokens.Typography.caption,
                    valueColor: DesignTokens.Colors.primary
                )
            }
        }
        .padding(metricPadding)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .designDraftProbe("run.metrics", variant: variant.rawValue)
    }

    private var mapPreview: some View {
        TrackMapView(
            samples: DesignDraftFixture.samples,
            emptyIdentifier: "draft.mapEmpty",
            singlePointIdentifier: "draft.mapSingle"
        )
        .frame(height: RunFinishedSummaryLayoutPolicy.finishedMapFloor)
        .designDraftProbe("run.map", variant: variant.rawValue)
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: splitsRowSpacing) {
            Text(L10n.runSplitsDetailTitle)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.secondary)
            ForEach(DesignDraftFixture.splits) { split in
                DesignDraftSplitRow(index: split.id, distance: split.distance, pace: split.pace)
            }
        }
        .padding(splitsPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .designDraftProbe("run.splits", variant: variant.rawValue)
    }

    /// A 组保持现网「整行提示」形态（本轮只比颜色，不改这一行的高度）。
    private var permissionHint: some View {
        Text(verbatim: L10n.backgroundDegradedHint)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.warning)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actionControls: some View {
        switch state {
        case .notStarted:
            DesignDraftPrimaryButton(
                title: L10n.runActionStart,
                fill: palette.accent,
                foreground: palette.onAccent
            )
        case .running:
            DesignDraftPrimaryButton(
                title: L10n.runActionPause,
                fill: palette.accent,
                foreground: palette.onAccent
            )
            DesignDraftOutlineButton(
                title: L10n.runActionFinish,
                tint: palette.accent,
                lineWidth: DesignTokens.Stroke.hairline * 2
            )
        case .finished:
            DesignDraftPrimaryButton(
                title: L10n.runActionSave,
                fill: palette.accent,
                foreground: palette.onAccent
            )
            DesignDraftOutlineButton(title: L10n.runActionDiscard, tint: DesignTokens.Colors.secondary)
        }
    }
}

/// 历史列表：唯一一条同源真实跑次（1.20 km / 00:22）。
struct DesignDraftHistoryListScreen: View {
    let palette: DesignDraftPalette
    let variant: DesignDraftV12.Variant

    var body: some View {
        DesignDraftTabShell(palette: palette, selected: 1) {
            NavigationStack {
                List {
                    recordRow
                        .listRowSeparator(.hidden)
                        .listRowBackground(DesignTokens.Colors.background)
                        .listRowInsets(
                            EdgeInsets(
                                top: DesignTokens.Spacing.xs,
                                leading: DesignTokens.Spacing.md,
                                bottom: DesignTokens.Spacing.xs,
                                trailing: DesignTokens.Spacing.md
                            )
                        )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Colors.background)
                .navigationTitle(L10n.historyNavigationTitle)
            }
        }
    }

    private var recordRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(verbatim: "2026年11月12日 12:58")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.primary)
                HStack(spacing: 0) {
                    summaryColumn("1.20 km", L10n.runMetricDistance)
                    summaryColumn("00:22", L10n.runMetricTime)
                    summaryColumn("0:18 /km", L10n.runMetricAverage)
                }
            }
            Image(systemName: "chevron.right")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .designDraftProbe("history.row", variant: variant.rawValue)
    }

    private func summaryColumn(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(verbatim: value)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 跑次详情：与现网同序（距离 → 时长/配速 → 轨迹 → 分段 → 底部导出主操作）。
struct DesignDraftHistoryDetailScreen: View {
    let palette: DesignDraftPalette
    let variant: DesignDraftV12.Variant

    var body: some View {
        DesignDraftTabShell(palette: palette, selected: 1) {
            NavigationStack {
                List {
                    Section { distanceCard }
                    Section { metricsCard }
                    Section {
                        mapCard
                    } header: {
                        sectionHeader(L10n.runMapPreviewLabel)
                    }
                    Section {
                        splitsCard
                    } header: {
                        sectionHeader(L10n.runSplitsDetailTitle)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Colors.background)
                .navigationTitle(L10n.runDetailNavigationTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Label(L10n.historyNavigationTitle, systemImage: "chevron.left")
                            .font(DesignTokens.Typography.body)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    DesignDraftActionBar {
                        DesignDraftPrimaryButton(
                            title: L10n.runDetailExportButton,
                            fill: palette.accent,
                            foreground: palette.onAccent
                        )
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(DesignTokens.Colors.secondary)
            .textCase(nil)
    }

    private var distanceCard: some View {
        DesignDraftCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                    Text(verbatim: DesignDraftFixture.distanceText)
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(DesignTokens.Colors.primary)
                        .monospacedDigit()
                    Text(verbatim: "km")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.primary)
                }
                Text(L10n.runDetailFieldDistance)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .designDraftProbe("detail.distance", variant: variant.rawValue)
    }

    private var metricsCard: some View {
        DesignDraftCard {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                DesignDraftMetric(
                    label: L10n.runMetricTime,
                    value: DesignDraftFixture.durationText,
                    unit: nil,
                    valueFont: DesignTokens.Typography.primaryValue,
                    valueColor: DesignTokens.Colors.primary,
                    alignment: .leading
                )
                DesignDraftMetric(
                    label: L10n.runMetricAverage,
                    value: DesignDraftFixture.averagePaceText,
                    unit: "/km",
                    valueFont: DesignTokens.Typography.primaryValue,
                    valueColor: DesignTokens.Colors.primary,
                    alignment: .leading
                )
            }
        }
        .designDraftProbe("detail.metrics", variant: variant.rawValue)
    }

    private var mapCard: some View {
        DesignDraftCard {
            TrackMapView(
                samples: DesignDraftFixture.samples,
                emptyIdentifier: "draft.mapEmpty",
                singlePointIdentifier: "draft.mapSingle"
            )
            .frame(height: 200)
        }
        .designDraftProbe("detail.map", variant: variant.rawValue)
    }

    private var splitsCard: some View {
        DesignDraftCard {
            VStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(DesignDraftFixture.splits) { split in
                    DesignDraftSplitRow(index: split.id, distance: split.distance, pace: split.pace)
                }
            }
        }
        .designDraftProbe("detail.splits", variant: variant.rawValue)
    }
}

/// 设置页：唯一真实偏好行（播报开关），行底 / 描边 / 间距全部走 token。
struct DesignDraftSettingsScreen: View {
    let palette: DesignDraftPalette
    let variant: DesignDraftV12.Variant

    var body: some View {
        DesignDraftTabShell(palette: palette, selected: 2) {
            NavigationStack {
                List {
                    Section {
                        announcementRow
                        footerRow
                    } header: {
                        Text(L10n.settingsSectionAnnouncement)
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(DesignTokens.Colors.secondary)
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Colors.background)
                .navigationTitle(L10n.settingsNavigationTitle)
            }
        }
    }

    private var announcementRow: some View {
        Toggle(isOn: .constant(true)) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(L10n.settingsAnnouncementTitle)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.primary)
                Text(L10n.settingsAnnouncementBody)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .tint(palette.accent)
        .frame(minHeight: DesignTokens.minTapTarget)
        .padding(DesignTokens.Spacing.cardPadding)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(DesignTokens.Colors.background)
        .listRowInsets(
            EdgeInsets(
                top: DesignTokens.Spacing.xs,
                leading: DesignTokens.Spacing.md,
                bottom: DesignTokens.Spacing.xs,
                trailing: DesignTokens.Spacing.md
            )
        )
        .designDraftProbe("settings.toggleRow", variant: variant.rawValue)
    }

    private var footerRow: some View {
        Text(L10n.settingsFooterAnnouncement)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondary)
            .listRowSeparator(.hidden)
            .listRowBackground(DesignTokens.Colors.background)
            .listRowInsets(
                EdgeInsets(
                    top: DesignTokens.Spacing.xs,
                    leading: DesignTokens.Spacing.md,
                    bottom: DesignTokens.Spacing.xs,
                    trailing: DesignTokens.Spacing.md
                )
            )
    }
}
#endif
