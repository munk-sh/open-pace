import PurePaceRunCore
import SwiftUI

/// 跑次详情页：字段全部来自被点击的 `RunRecord` 与 `RunDetailContent` 纯映射，
/// 视图只做绑定与排版，不重算距离、不聚合分段、不读样例。
/// 内容区纵向序固定为 元信息 → hero 距离 → 指标网格 → 分段；导出是本页唯一主操作，
/// 固定底部安全区上方（与 `RunView` 同一 `.safeAreaInset(edge: .bottom)` 锚点写法），
/// 不进可滚动 `List`，首次进入无需滚动即可命中。
struct RunDetailView: View {
    let record: RunRecord
    let exporter: RunGPXExporter

    @State private var exportState = RunExportState()

    private var content: RunDetailContent {
        RunDetailContent(record: record)
    }

    var body: some View {
        List {
            metaSection
            heroSection
            metricGridSection
            mapSection
            splitsSection
        }
        .listStyle(.plain)
        .listSectionSpacing(DesignTokens.Spacing.sectionGap)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.background)
        .navigationTitle(L10n.runDetailNavigationTitle)
        .accessibilityIdentifier("runDetail.root")
        // 主操作固定底部控制区：安全区上方、TabBar 之上，与跑步页同一锚点与视觉口径。
        // 导出不在 `List` 内，惰性列表 realize 与滚动位置都不再影响其可见性。
        .safeAreaInset(edge: .bottom) {
            exportAction
        }
    }

    /// 第一块：顶部元信息（开始 / 结束，带秒），最低层级。
    private var metaSection: some View {
        Section {
            cardRow {
                metaField(
                    L10n.runDetailFieldStart,
                    content.startedAtText,
                    identifier: "runDetail.startedAt"
                )
                divider
                metaField(
                    L10n.runDetailFieldEnd,
                    content.endedAtText,
                    identifier: "runDetail.endedAt"
                )
            }
        }
    }

    /// 第二块：hero 距离，全屏最大文字；数值与单位同属一个 `Text`。
    private var heroSection: some View {
        Section {
            cardRow {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.metricGroupSpacing) {
                    Text(content.distanceText)
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(DesignTokens.Colors.primary)
                        .monospacedDigit()
                        .accessibilityIdentifier("runDetail.distance")
                    Text(L10n.runDetailFieldDistance)
                        .font(DesignTokens.Typography.metricLabel)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 第三块：指标网格（用时 / 平均配速），值与列表行同一「数值在上 + 标签在下」语法。
    private var metricGridSection: some View {
        Section {
            cardRow {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.metricGroupGap) {
                    metricCell(
                        value: content.activeDurationText,
                        label: L10n.runMetricTime,
                        identifier: "runDetail.activeDuration"
                    )
                    metricCell(
                        value: content.averagePaceText,
                        label: L10n.runMetricAverage,
                        identifier: "runDetail.averagePace"
                    )
                }
            }
        }
    }

    /// 第三块（地图）：与结束态共用同一 `TrackMapView`；空/单点轨迹走详情空态。
    private var mapSection: some View {
        Section {
            cardRow {
                TrackMapView(
                    samples: record.samples,
                    emptyIdentifier: "runDetail.mapEmpty",
                    singlePointIdentifier: "runDetail.mapEmpty.single"
                )
                .frame(height: 200)
            }
        } header: {
            Text(L10n.runMapPreviewLabel)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .textCase(nil)
        }
    }

    /// 第四块：分段（带条数摘要的 header + 行，或诚实空态）。
    private var splitsSection: some View {
        Section {
            cardRow {
                if content.hasSplits {
                    ForEach(content.splits) { split in
                        splitRow(split)
                    }
                } else {
                    Text(L10n.runDetailSplitsEmpty)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .accessibilityIdentifier("runDetail.splitsEmpty")
                }
            }
        } header: {
            Text(content.splitsSummaryText)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .textCase(nil)
                .accessibilityIdentifier("runDetail.splits")
        }
    }

    /// 主操作区：唯一导出主操作（填充 accent、`minTapTarget` 高）+ 导出结果 / 分享入口。
    /// 区块视觉与跑步页底部主操作同一口径：`surface` 底 + 顶部 hairline 分隔，
    /// 内边距取语义 token；导出结果只在真实落盘后出现，失败态复用既有 `danger` 文案。
    private var exportAction: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                exportState.export(record, using: exporter)
            } label: {
                Text(L10n.runDetailExportButton)
                    .font(DesignTokens.Typography.control)
                    .foregroundStyle(DesignTokens.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
            .background(
                DesignTokens.Colors.accent,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
            )
            .accessibilityIdentifier("runDetail.export")
            .accessibilityLabel(Text(L10n.runDetailExportLabel))

            switch exportState.phase {
            case .idle:
                EmptyView()
            case .exported(let url):
                (Text(L10n.runDetailExported) + Text(verbatim: " \(url.lastPathComponent)"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("runDetail.exported")
                ShareLink(item: url) {
                    Text(L10n.runDetailShare)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DesignTokens.minTapTarget)
                }
                .accessibilityIdentifier("runDetail.share")
                .accessibilityLabel(Text(L10n.runDetailShareLabel))
            case .failed:
                Text(L10n.runDetailExportFailed)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.danger)
                    .accessibilityIdentifier("runDetail.exportFailed")
            }
        }
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

    /// 一张 `surface` 卡片：`Radius.card` 圆角、`Spacing.*` 内边距、`separator` 描边。
    /// 块间垂直间距交给 `.listSectionSpacing`，卡片自身不再叠加行内上下留白。
    private func cardRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.metricGroupSpacing) {
            content()
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: DesignTokens.Spacing.md,
                bottom: 0,
                trailing: DesignTokens.Spacing.md
            )
        )
        .listRowBackground(DesignTokens.Colors.background)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.separator)
            .frame(height: DesignTokens.Stroke.hairline)
    }

    private func metaField(
        _ title: LocalizedStringKey,
        _ value: String,
        identifier: String
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.metricLabel)
                .foregroundStyle(DesignTokens.Colors.secondary)
            Spacer(minLength: DesignTokens.Spacing.xs)
            Text(value)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
        }
    }

    /// 网格单格：值 `primaryValue`（等宽）在上 → 标签 `metricLabel` + 次要色在下。
    private func metricCell(
        value: String,
        label: LocalizedStringKey,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(value)
                .font(DesignTokens.Typography.primaryValue)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
            Text(label)
                .font(DesignTokens.Typography.metricLabel)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func splitRow(_ split: RunDetailContent.SplitRow) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(split.indexText)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
            Spacer(minLength: DesignTokens.Spacing.xs)
            Text(split.paceText)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("runDetail.splitRow")
    }
}
