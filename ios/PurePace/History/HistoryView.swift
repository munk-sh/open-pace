import PurePaceRunCore
import SwiftUI

/// 历史页：只读本机真实归档（`RunArchiveStore.list()` 已按 `startedAt` 降序）。
/// 列表项为「日期（标题）→ 距离 / 用时 / 配速三数值（同一行）→ 三个标签」三层；
/// 无记录时给出诚实空态与唯一「去跑一次」入口，不渲染任何示例跑次。
struct HistoryView: View {
    let archiveStore: RunArchiveStore
    let exporter: RunGPXExporter
    let refreshToken: Int
    let onRunAgain: () -> Void
    /// 仅截图取证用：默认 `nil`，Release 路径恒为 `nil`，不会进入正常用户路径。
    var injectedRecords: [RunRecord]?
    /// 仅截图取证用：加载后直接进入首条记录详情；Release 路径恒为 `false`。
    var autoOpenFirstDetail: Bool = false

    @State private var state = HistoryViewState()

    var body: some View {
        NavigationStack(path: $state.path) {
            Group {
                if state.didFail {
                    failureState
                } else if state.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(state.summaries, id: \.id) { summary in
                            NavigationLink(value: summary.id) {
                                row(for: summary)
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
            .navigationDestination(for: UUID.self) { recordID in
                // 详情按 id 懒解码完整 samples（列表只持摘要）；注入取证路径直接给已解码记录。
                if let record = injectedRecords?.first(where: { $0.id == recordID })
                    ?? (try? archiveStore.record(withID: recordID)) {
                    RunDetailView(record: record, exporter: exporter)
                }
            }
        }
        .tint(DesignTokens.Colors.accent)
        .accessibilityIdentifier("tab.history")
        .onAppear { load() }
        .onChange(of: refreshToken) { _, _ in load() }
    }

    /// 空态：一句标题 + 一句说明 + 唯一 CTA，卡面 `surface` / `Radius.card` / hairline。
    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(L10n.historyEmptyTitle)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("history.empty")
            Text(L10n.historyEmptyBody)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .multilineTextAlignment(.center)
            Button {
                state.popToRoot()
                onRunAgain()
            } label: {
                Text(L10n.historyRunAgain)
                    .font(DesignTokens.Typography.control)
                    .foregroundStyle(DesignTokens.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
            .padding(.top, DesignTokens.Spacing.metricGroupGap)
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

    /// 读取失败态：与「真的没有跑次」区分，只给唯一可重试操作（复用既有重试文案键）。
    private var failureState: some View {
        VStack(spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Button {
                load(force: true)
            } label: {
                Text(L10n.runActionRetryLocation)
                    .font(DesignTokens.Typography.control)
                    .foregroundStyle(DesignTokens.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
            .background(
                DesignTokens.Colors.accent,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
            )
            .accessibilityLabel(Text(L10n.runActionRetryLocation))
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

    /// 行三层：日期 `title` / 三数值 `body` 等宽同排 / 三标签 `metricLabel` 逐一对应。
    private func row(for summary: RunRecordSummary) -> some View {
        let content = HistoryRowContent(summary: summary)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(content.dateText)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.metricGroupGap) {
                metricColumn(content.distanceText, label: L10n.runMetricDistance)
                metricColumn(content.durationText, label: L10n.runMetricTime)
                metricColumn(content.paceText, label: L10n.runMetricAverage)
            }
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
        .accessibilityLabel(Text(content.accessibilityLabel))
    }

    /// 单列指标：数值在上（等宽）→ 标签在下（`metricLabel` + 次要色），与详情网格同构。
    private func metricColumn(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(value)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
            Text(label)
                .font(DesignTokens.Typography.metricLabel)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 读取触发点只有「首次出现」与「`refreshToken` 变化」；同一 token 不重复读取。
    /// `force` 仅由失败态的重试入口使用，可重复执行。
    private func load(force: Bool = false) {
        state.load(token: refreshToken, force: force) { () throws -> [RunRecordSummary] in
            if let injectedRecords {
                return injectedRecords.map(RunRecordSummary.init(record:))
            }
            return try archiveStore.listSummaries()
        }
        state.openFirstDetailIfNeeded(autoOpen: autoOpenFirstDetail)
    }
}

/// 列表行的纯展示映射：只读取 `RunRecord` 既有字段并复用 `RunFormatting`，
/// 与 `RunDetailContent` 同源，因此下钻 / 返回时同一指标只放大字号、不改变字样。
struct HistoryRowContent: Equatable {
    let dateText: String
    let distanceText: String
    let durationText: String
    let paceText: String

    init(record: RunRecord) {
        dateText = RunFormatting.zhHansDateTimeText(record.startedAt)
        distanceText = RunFormatting.distanceText(record.distance)
        durationText = RunFormatting.elapsedText(record.activeDuration)
        paceText = RunFormatting.paceText(
            RunPace(distance: record.distance, duration: record.activeDuration)
        )
    }

    /// 列表轻量索引版：字段全部来自 `RunRecordSummary`，不解码 `samples`。
    init(summary: RunRecordSummary) {
        dateText = RunFormatting.zhHansDateTimeText(summary.startedAt)
        distanceText = RunFormatting.distanceText(summary.distance)
        durationText = RunFormatting.elapsedText(summary.activeDuration)
        paceText = RunFormatting.paceText(
            RunPace(distance: summary.distance, duration: summary.activeDuration)
        )
    }

    /// 三数值固定顺序：距离 → 用时 → 平均配速。
    var metrics: [String] {
        [distanceText, durationText, paceText]
    }

    /// 合并可及 label：日期 + 三数值，供 `history.row` 单一元素朗读与 UI 用例断言。
    var accessibilityLabel: String {
        ([dateText] + metrics).joined(separator: "，")
    }
}
