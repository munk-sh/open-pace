#if DEBUG
import SwiftUI

/// B 组：结束态整屏两版（B1 地图 hero / B2 中等地图 + 可折叠摘要）。
///
/// 两版共用同一组同源真实数据（1.20 km / 00:22，fixture 见 `DesignDraftFixture`），
/// 主操作一律经 `safeAreaInset(edge: .bottom)` 锚在底部安全区上方；
/// 权限提示收成 inline 胶囊，不再整行占高。
struct DesignDraftFinishedScreen: View {
    enum Layout {
        case mapHero
        case collapsibleSummary

        /// 地图区块高度（pt）：B1 hero 360 ≥ 393×852 的 40%（340.8）；B2 中等 220（远高于现网 96 下限）。
        var mapHeight: CGFloat {
            switch self {
            case .mapHero: 360
            case .collapsibleSummary: 220
            }
        }
    }

    let layout: Layout
    let expanded: Bool
    let variant: DesignDraftV12.Variant

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xs) {
                mapBlock
                summaryBlock
                DesignDraftInlinePermissionHint()
                    .designDraftProbe("finished.hint", variant: variant.rawValue)
                Spacer(minLength: DesignTokens.Spacing.xs)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.background)
            .designDraftProbe("screen.content", variant: variant.rawValue)
            .navigationTitle(L10n.runNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DesignDraftActionBar {
                    DesignDraftPrimaryButton(
                        title: L10n.runActionSave,
                        fill: DesignTokens.Colors.accent,
                        foreground: DesignTokens.Colors.onAccent
                    )
                    DesignDraftOutlineButton(title: L10n.runActionDiscard, tint: DesignTokens.Colors.secondary)
                }
                .designDraftProbe("screen.actionBar", variant: variant.rawValue)
            }
        }
    }

    // MARK: 地图

    /// 地图 hero：轨迹为真实 fixture 折线（`TrackMapView` 生产地图壳），叠加距离/用时胶囊。
    private var mapBlock: some View {
        ZStack(alignment: .bottomLeading) {
            TrackMapView(
                samples: DesignDraftFixture.samples,
                emptyIdentifier: "draft.mapEmpty",
                singlePointIdentifier: "draft.mapSingle"
            )
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(verbatim: "\(DesignDraftFixture.distanceText) km")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.primary)
                Text(verbatim: DesignDraftFixture.durationText)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
            .padding(DesignTokens.Spacing.sm)
        }
        .frame(height: layout.mapHeight)
        .designDraftProbe("finished.map", variant: variant.rawValue)
    }

    // MARK: 摘要

    @ViewBuilder
    private var summaryBlock: some View {
        switch layout {
        case .mapHero:
            VStack(spacing: DesignTokens.Spacing.xs) {
                metricsRow
                splitsCard()
            }
        case .collapsibleSummary:
            VStack(spacing: DesignTokens.Spacing.xs) {
                collapsibleSummary
                metricsRow
            }
        }
    }

    /// B1：一行两项指标（用时 / 平均配速）；分段条数落在分段卡标题，避免三列 36pt 数字被裁切。
    private var metricsRow: some View {
        DesignDraftCard { metricsContent }
            .designDraftProbe("finished.metrics", variant: variant.rawValue)
    }

    private var metricsContent: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            DesignDraftMetric(
                label: L10n.runMetricTime,
                value: DesignDraftFixture.durationText,
                unit: nil,
                valueFont: DesignTokens.Typography.primaryValue,
                valueColor: DesignTokens.Colors.primary
            )
            DesignDraftMetric(
                label: L10n.runMetricAverage,
                value: DesignDraftFixture.averagePaceText,
                unit: "/km",
                valueFont: DesignTokens.Typography.primaryValue,
                valueColor: DesignTokens.Colors.primary
            )
        }
    }

    @ViewBuilder
    private func splitsCard(carded: Bool = true) -> some View {
        if carded {
            DesignDraftCard { splitsContent }
                .designDraftProbe("finished.splits", variant: variant.rawValue)
        } else {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Rectangle()
                    .fill(DesignTokens.Colors.separator)
                    .frame(height: DesignTokens.Stroke.hairline)
                splitsContent
            }
            .padding(.top, DesignTokens.Spacing.sm)
            .designDraftProbe("finished.splits", variant: variant.rawValue)
        }
    }

    private var splitsContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(L10n.runSplitsDetailTitle)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                Spacer(minLength: DesignTokens.Spacing.sm)
                Text(verbatim: "\(DesignDraftFixture.splitsSummaryText) 段")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
            }
            ForEach(DesignDraftFixture.splits) { split in
                DesignDraftSplitRow(index: split.id, distance: split.distance, pace: split.pace)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// B2：关键指标常显（折叠的只是分段明细）；摘要卡折叠态只留一行摘要，展开后补出分段；卡高由内容决定（无固定档高）。
    private var collapsibleSummary: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(verbatim: "本次跑步")
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.primary)
                    Text(verbatim: "1.20 km · 00:22 · 0:18 /km")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: DesignTokens.Spacing.sm)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.cardPadding)
            .frame(minHeight: DesignTokens.minTapTarget)
            if expanded {
                splitsCard(carded: false)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .designDraftProbe("finished.summary", variant: variant.rawValue)
    }
}
#endif
