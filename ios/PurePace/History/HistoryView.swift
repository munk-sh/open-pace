import PurePaceRunCore
import SwiftUI

/// 历史页：只读本机真实归档（`RunArchiveStore.list()` 已按 `startedAt` 降序）。
/// 列表项为「日期（主）→ 距离 / 时长 / 配速（次）」两级层级；
/// 无记录时给出诚实空态与「去跑一次」入口，不渲染任何示例跑次。
struct HistoryView: View {
    let archiveStore: RunArchiveStore
    let exporter: RunGPXExporter
    let refreshToken: Int
    let onRunAgain: () -> Void
    /// 仅截图取证用：默认 `nil`，Release 路径恒为 `nil`，不会进入正常用户路径。
    var injectedRecords: [RunRecord]?
    /// 仅截图取证用：加载后直接进入首条记录详情；Release 路径恒为 `false`。
    var autoOpenFirstDetail: Bool = false

    @State private var records: [RunRecord] = []
    @State private var detailPresented = false
    @State private var detailRecord: RunRecord?
    @State private var didAutoOpenDetail = false

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(records, id: \.id) { record in
                            NavigationLink {
                                RunDetailView(record: record, exporter: exporter)
                            } label: {
                                row(for: record)
                            }
                            .accessibilityIdentifier("history.row")
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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DesignTokens.Colors.background)
                }
            }
            .navigationTitle(L10n.historyNavigationTitle)
            .navigationDestination(isPresented: $detailPresented) {
                if let record = detailRecord {
                    RunDetailView(record: record, exporter: exporter)
                }
            }
        }
        .tint(DesignTokens.Colors.accent)
        .accessibilityIdentifier("tab.history")
        .onAppear(perform: load)
        .onChange(of: refreshToken) { _, _ in load() }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text(L10n.historyEmptyTitle)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
                .accessibilityIdentifier("history.empty")
            Text(L10n.historyEmptyBody)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .multilineTextAlignment(.center)
            Button(action: onRunAgain) {
                Text(L10n.historyRunAgain)
                    .font(DesignTokens.Typography.control)
                    .foregroundStyle(DesignTokens.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
            .background(
                DesignTokens.Colors.accent,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
            )
            .accessibilityIdentifier("history.runAgain")
            .accessibilityLabel(Text(L10n.historyRunAgain))
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(DesignTokens.Colors.background)
    }

    private func row(for record: RunRecord) -> some View {
        let dateText = RunFormatting.zhHansDateTimeText(record.startedAt)
        let metricsText = rowMetricsText(for: record)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(dateText)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
            Text(metricsText)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .monospacedDigit()
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(
            maxWidth: .infinity,
            minHeight: DesignTokens.minTapTarget,
            alignment: .leading
        )
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dateText)，\(metricsText)")
    }

    private func rowMetricsText(for record: RunRecord) -> String {
        let pace = RunFormatting.paceText(
            RunPace(distance: record.distance, duration: record.activeDuration)
        )
        return "\(RunFormatting.distanceText(record.distance)) · "
            + "\(RunFormatting.elapsedText(record.activeDuration)) · \(pace)"
    }

    private func load() {
        if let injectedRecords {
            records = injectedRecords
        } else {
            records = (try? archiveStore.list()) ?? []
        }
        if autoOpenFirstDetail, !didAutoOpenDetail, let first = records.first {
            didAutoOpenDetail = true
            detailRecord = first
            detailPresented = true
        }
    }
}
