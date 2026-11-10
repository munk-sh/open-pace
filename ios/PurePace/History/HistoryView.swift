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
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationDestination(isPresented: $detailPresented) {
                if let record = detailRecord {
                    RunDetailView(record: record, exporter: exporter)
                }
            }
        }
        .accessibilityIdentifier("tab.history")
        .onAppear(perform: load)
        .onChange(of: refreshToken) { _, _ in load() }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text("还没有跑次记录")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
                .accessibilityIdentifier("history.empty")
            Text("完成一次跑步后，这里会按时间列出你的每一次跑次。")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .multilineTextAlignment(.center)
            Button(action: onRunAgain) {
                Text("去跑一次")
                    .font(DesignTokens.Typography.control)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.accent)
            .accessibilityIdentifier("history.runAgain")
            .accessibilityLabel("去跑一次")
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for record: RunRecord) -> some View {
        let dateText = record.startedAt.formatted(date: .abbreviated, time: .shortened)
        let metricsText = rowMetricsText(for: record)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(dateText)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
            Text(metricsText)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(minHeight: DesignTokens.minTapTarget, alignment: .leading)
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
