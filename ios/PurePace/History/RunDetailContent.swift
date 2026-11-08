import Foundation
import PurePaceRunCore

/// 跑次详情页的纯展示映射：`RunRecord` → 可直接绑定的字符串与分段行。
/// 只读取记录既有字段并复用 `RunFormatting`，不重算距离、不重切分段、不读样例。
struct RunDetailContent: Equatable {
    struct SplitRow: Equatable, Identifiable {
        let id: Int
        let indexText: String
        let paceText: String
    }

    let startedAtText: String
    let endedAtText: String
    let distanceText: String
    let activeDurationText: String
    let averagePaceText: String
    let splits: [SplitRow]

    init(record: RunRecord) {
        startedAtText = RunFormatting.dateTimeText(record.startedAt)
        endedAtText = RunFormatting.dateTimeText(record.endedAt)
        distanceText = RunFormatting.distanceText(record.distance)
        activeDurationText = RunFormatting.elapsedText(record.activeDuration)
        averagePaceText = RunFormatting.paceText(
            RunPace(distance: record.distance, duration: record.activeDuration)
        )
        splits = record.splits.map { split in
            SplitRow(
                id: split.index,
                indexText: RunFormatting.splitIndexText(split.index),
                paceText: RunFormatting.paceText(split.pace)
            )
        }
    }

    /// 分段区域摘要文本，内含条数。
    var splitsSummaryText: String {
        RunFormatting.splitSummaryText(count: splits.count)
    }

    var hasSplits: Bool {
        !splits.isEmpty
    }
}
