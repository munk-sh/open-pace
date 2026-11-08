import PurePaceRunCore
import SwiftUI

/// 历史页：只读本机真实归档（`RunArchiveStore.list()` 已按 `startedAt` 降序）。
/// 无记录时给出诚实空态与「去跑一次」入口，不渲染任何示例跑次。
struct HistoryView: View {
    let archiveStore: RunArchiveStore
    let refreshToken: Int
    let onRunAgain: () -> Void

    @State private var records: [RunRecord] = []

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    List(records, id: \.id) { record in
                        row(for: record)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
        }
        .onAppear(perform: load)
        .onChange(of: refreshToken) { _, _ in load() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("还没有跑次记录")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("history.empty")
            Button("去跑一次", action: onRunAgain)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("history.runAgain")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for record: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text("\(RunFormatting.distanceText(record.distance)) · \(RunFormatting.elapsedText(record.activeDuration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.row")
    }

    private func load() {
        records = (try? archiveStore.list()) ?? []
    }
}
