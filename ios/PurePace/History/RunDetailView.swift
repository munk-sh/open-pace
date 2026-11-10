import PurePaceRunCore
import SwiftUI

/// 跑次详情页：字段全部来自被点击的 `RunRecord` 与 `RunDetailContent` 纯映射，
/// 视图只做绑定与排版，不重算距离、不聚合分段、不读样例。
struct RunDetailView: View {
    let record: RunRecord
    let exporter: RunGPXExporter

    @State private var exportState = RunExportState()

    private var content: RunDetailContent {
        RunDetailContent(record: record)
    }

    var body: some View {
        List {
            Section {
                cardRow {
                    field(L10n.runDetailFieldStart, content.startedAtText, identifier: "runDetail.startedAt")
                    divider
                    field(L10n.runDetailFieldEnd, content.endedAtText, identifier: "runDetail.endedAt")
                }
            }
            Section {
                cardRow {
                    field(L10n.runDetailFieldDistance, content.distanceText, identifier: "runDetail.distance")
                    divider
                    field(
                        L10n.runDetailFieldActiveDuration,
                        content.activeDurationText,
                        identifier: "runDetail.activeDuration"
                    )
                    divider
                    field(
                        L10n.runDetailFieldAveragePace,
                        content.averagePaceText,
                        identifier: "runDetail.averagePace"
                    )
                }
            }
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
            exportSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.background)
        .navigationTitle(L10n.runDetailNavigationTitle)
        .accessibilityIdentifier("runDetail.root")
    }

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
    private func cardRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
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
                top: DesignTokens.Spacing.xs,
                leading: DesignTokens.Spacing.md,
                bottom: DesignTokens.Spacing.xs,
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

    private func field(_ title: LocalizedStringKey, _ value: String, identifier: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
            Spacer(minLength: DesignTokens.Spacing.xs)
            Text(value)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
        }
    }
}
