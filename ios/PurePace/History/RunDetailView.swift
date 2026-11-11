import PurePaceRunCore
import SwiftUI

/// 跑次详情页：字段全部来自被点击的 `RunRecord` 与 `RunDetailContent` 纯映射，
/// 视图只做绑定与排版，不重算距离、不聚合分段、不读样例。
/// 纵向序固定为 元信息 → hero 距离 → 指标网格 → 分段 → 导出。
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
            splitsSection
            exportSection
        }
        .listStyle(.plain)
        .listSectionSpacing(DesignTokens.Spacing.sectionGap)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.background)
        .navigationTitle(L10n.runDetailNavigationTitle)
        .accessibilityIdentifier("runDetail.root")
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

    /// 第五块：导出区，流程与状态标识保持不变。
    @ViewBuilder
    private var exportSection: some View {
        Section {
            cardRow {
                Button(L10n.runDetailExportButton) {
                    exportState.export(record, using: exporter)
                }
                .font(DesignTokens.Typography.control)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(minHeight: DesignTokens.minTapTarget)
                .accessibilityIdentifier("runDetail.export")
                .accessibilityLabel(Text(L10n.runDetailExportLabel))

                switch exportState.phase {
                case .idle:
                    EmptyView()
                case .exported(let url):
                    (Text(L10n.runDetailExported) + Text(verbatim: " \(url.lastPathComponent)"))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .accessibilityIdentifier("runDetail.exported")
                    ShareLink(item: url) {
                        Text(L10n.runDetailShare)
                    }
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .frame(minHeight: DesignTokens.minTapTarget)
                    .accessibilityIdentifier("runDetail.share")
                    .accessibilityLabel(Text(L10n.runDetailShareLabel))
                case .failed:
                    Text(L10n.runDetailExportFailed)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.danger)
                        .accessibilityIdentifier("runDetail.exportFailed")
                }
            }
        } header: {
            Text(L10n.runDetailExportSection)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .textCase(nil)
        } footer: {
            Text(L10n.runDetailExportFooter)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .listRowBackground(DesignTokens.Colors.background)
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
