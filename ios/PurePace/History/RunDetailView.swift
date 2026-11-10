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
                field(L10n.runDetailFieldStart, content.startedAtText, identifier: "runDetail.startedAt")
                field(L10n.runDetailFieldEnd, content.endedAtText, identifier: "runDetail.endedAt")
            }
            Section {
                field(L10n.runDetailFieldDistance, content.distanceText, identifier: "runDetail.distance")
                field(
                    L10n.runDetailFieldActiveDuration,
                    content.activeDurationText,
                    identifier: "runDetail.activeDuration"
                )
                field(L10n.runDetailFieldAveragePace, content.averagePaceText, identifier: "runDetail.averagePace")
            }
            Section {
                if content.hasSplits {
                    ForEach(content.splits) { split in
                        HStack {
                            Text(split.indexText)
                                .monospacedDigit()
                            Spacer()
                            Text(split.paceText)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("runDetail.splitRow")
                    }
                } else {
                    Text(L10n.runDetailSplitsEmpty)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("runDetail.splitsEmpty")
                }
            } header: {
                Text(content.splitsSummaryText)
                    .accessibilityIdentifier("runDetail.splits")
            }
            exportSection
        }
        .navigationTitle(L10n.runDetailNavigationTitle)
        .accessibilityIdentifier("runDetail.root")
    }

    @ViewBuilder
    private var exportSection: some View {
        Section {
            Button(L10n.runDetailExportButton) {
                exportState.export(record, using: exporter)
            }
            .font(DesignTokens.Typography.control)
            .frame(minHeight: DesignTokens.minTapTarget)
            .accessibilityIdentifier("runDetail.export")
            .accessibilityLabel(Text(L10n.runDetailExportLabel))

            switch exportState.phase {
            case .idle:
                EmptyView()
            case .exported(let url):
                (Text(L10n.runDetailExported) + Text(verbatim: " \(url.lastPathComponent)"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runDetail.exported")
                ShareLink(item: url) {
                    Text(L10n.runDetailShare)
                }
                .frame(minHeight: DesignTokens.minTapTarget)
                .accessibilityIdentifier("runDetail.share")
                .accessibilityLabel(Text(L10n.runDetailShareLabel))
            case .failed:
                Text(L10n.runDetailExportFailed)
                    .foregroundStyle(DesignTokens.Colors.danger)
                    .accessibilityIdentifier("runDetail.exportFailed")
            }
        } header: {
            Text(L10n.runDetailExportSection)
                .font(DesignTokens.Typography.sectionHeader)
        } footer: {
            Text(L10n.runDetailExportFooter)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
    }

    private func field(_ title: LocalizedStringKey, _ value: String, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier)
        }
    }
}
