import PurePaceRunCore
import SwiftUI

/// 跑次详情页：字段全部来自被点击的 `RunRecord` 与 `RunDetailContent` 纯映射，
/// 视图只做绑定与排版，不重算距离、不聚合分段、不读样例。
struct RunDetailView: View {
    let record: RunRecord

    private var content: RunDetailContent {
        RunDetailContent(record: record)
    }

    var body: some View {
        List {
            Section {
                field("开始", content.startedAtText, identifier: "runDetail.startedAt")
                field("结束", content.endedAtText, identifier: "runDetail.endedAt")
            }
            Section {
                field("总距离", content.distanceText, identifier: "runDetail.distance")
                field("活跃时长", content.activeDurationText, identifier: "runDetail.activeDuration")
                field("平均配速", content.averagePaceText, identifier: "runDetail.averagePace")
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
                    Text("暂无分段")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("runDetail.splitsEmpty")
                }
            } header: {
                Text(content.splitsSummaryText)
                    .accessibilityIdentifier("runDetail.splits")
            }
        }
        .navigationTitle("跑次详情")
        .accessibilityIdentifier("runDetail.root")
    }

    private func field(_ title: String, _ value: String, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier)
        }
    }
}
