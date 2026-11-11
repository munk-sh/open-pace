import XCTest
import PurePaceRunCore
@testable import PurePace

final class RunDetailContentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(
        distanceMeters: Double,
        activeDuration: TimeInterval,
        splits: [RunSplit]
    ) -> RunRecord {
        RunRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(activeDuration + 5),
            distance: RunDistance(meters: distanceMeters)!,
            activeDuration: activeDuration,
            splits: splits,
            samples: []
        )!
    }

    private func split(index: Int, duration: TimeInterval) -> RunSplit {
        RunSplit(index: index, distance: RunDistance(meters: 1000)!, duration: duration)!
    }

    func testMapsRecordFieldsWithoutRecompute() {
        let record = makeRecord(distanceMeters: 1000, activeDuration: 300, splits: [])
        let content = RunDetailContent(record: record)

        XCTAssertEqual(content.distanceText, RunFormatting.distanceText(record.distance))
        XCTAssertEqual(content.distanceText, "1.00 km")
        XCTAssertEqual(content.activeDurationText, RunFormatting.elapsedText(record.activeDuration))
        XCTAssertEqual(content.activeDurationText, "05:00")
        XCTAssertEqual(
            content.averagePaceText,
            RunFormatting.paceText(RunPace(distance: record.distance, duration: record.activeDuration))
        )
        XCTAssertEqual(content.averagePaceText, "5:00 /km")
        XCTAssertEqual(content.startedAtText, RunFormatting.dateTimeText(record.startedAt))
        XCTAssertEqual(content.endedAtText, RunFormatting.dateTimeText(record.endedAt))
        XCTAssertFalse(content.startedAtText.isEmpty)
        XCTAssertNotEqual(content.startedAtText, content.endedAtText)
    }

    func testMapsAllSplitsInOrder() {
        let record = makeRecord(
            distanceMeters: 3000,
            activeDuration: 990,
            splits: [split(index: 1, duration: 300), split(index: 2, duration: 330), split(index: 3, duration: 360)]
        )
        let content = RunDetailContent(record: record)

        XCTAssertTrue(content.hasSplits)
        XCTAssertEqual(content.splits.map(\.indexText), ["1", "2", "3"])
        XCTAssertEqual(content.splits.map(\.paceText), ["5:00 /km", "5:30 /km", "6:00 /km"])
        XCTAssertEqual(content.splits.map(\.id), [1, 2, 3])
        XCTAssertEqual(content.splitsSummaryText, "分段 · 3")
    }

    func testEmptySplitsExposeHonestEmptyState() {
        let record = makeRecord(distanceMeters: 400, activeDuration: 120, splits: [])
        let content = RunDetailContent(record: record)

        XCTAssertFalse(content.hasSplits)
        XCTAssertTrue(content.splits.isEmpty)
        XCTAssertEqual(content.splitsSummaryText, "分段 · 0")
    }

    func testHistoryRowSharesDetailTextsAndDatePrefix() {
        let record = makeRecord(distanceMeters: 5120, activeDuration: 1860, splits: [])
        let row = HistoryRowContent(record: record)
        let detail = RunDetailContent(record: record)

        XCTAssertEqual(row.distanceText, detail.distanceText)
        XCTAssertEqual(row.durationText, detail.activeDurationText)
        XCTAssertEqual(row.paceText, detail.averagePaceText)
        XCTAssertEqual(row.metrics, [detail.distanceText, detail.activeDurationText, detail.averagePaceText])
        XCTAssertTrue(
            detail.startedAtText.hasPrefix(row.dateText),
            "行日期必须是详情开始时间（秒精度）的前缀：\(row.dateText) / \(detail.startedAtText)"
        )
    }

    func testHistoryRowLabelCarriesDateAndThreeMetrics() {
        let record = makeRecord(distanceMeters: 1000, activeDuration: 300, splits: [])
        let row = HistoryRowContent(record: record)

        XCTAssertEqual(
            row.accessibilityLabel,
            "\(row.dateText)，\(row.distanceText)，\(row.durationText)，\(row.paceText)"
        )
        XCTAssertTrue(row.accessibilityLabel.contains(" km"))
        XCTAssertTrue(row.accessibilityLabel.contains(":"))
        XCTAssertTrue(row.accessibilityLabel.contains("/km"))
    }

    func testPaceFallsBackToPlaceholderWhenDataMissing() {
        let zeroDistance = makeRecord(distanceMeters: 0, activeDuration: 300, splits: [])
        XCTAssertEqual(RunDetailContent(record: zeroDistance).averagePaceText, RunFormatting.emptyPace)
        XCTAssertEqual(RunDetailContent(record: zeroDistance).averagePaceText, "--")

        let zeroDuration = makeRecord(distanceMeters: 500, activeDuration: 0, splits: [])
        XCTAssertEqual(RunDetailContent(record: zeroDuration).averagePaceText, RunFormatting.emptyPace)
        XCTAssertEqual(RunDetailContent(record: zeroDuration).averagePaceText, "--")
    }
}
