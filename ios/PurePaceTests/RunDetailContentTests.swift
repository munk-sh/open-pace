import XCTest
import PurePaceRunCore
@testable import PurePace

final class RunDetailContentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecord(
        distanceMeters: Double,
        activeDuration: TimeInterval,
        splits: [RunSplit],
        samples: [RunSample] = []
    ) -> RunRecord {
        RunRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(activeDuration + 5),
            distance: RunDistance(meters: distanceMeters)!,
            activeDuration: activeDuration,
            splits: splits,
            samples: samples
        )!
    }

    private func sample(offset: TimeInterval) -> RunSample {
        RunSample(
            latitude: 31.2304 + offset * 0.0001,
            longitude: 121.4737 + offset * 0.0001,
            altitude: nil,
            timestamp: start.addingTimeInterval(offset),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func split(index: Int, duration: TimeInterval) -> RunSplit {
        RunSplit(index: index, distance: RunDistance(meters: 1000)!, duration: duration)!
    }

    func testMapsRecordFieldsWithoutRecompute() {
        // 空 samples 记录：距离位给明确「未获取到定位」的空语义，不显示 0.00 假装有轨迹。
        let record = makeRecord(distanceMeters: 1000, activeDuration: 300, splits: [])
        let content = RunDetailContent(record: record)

        XCTAssertFalse(record.hasLocationData)
        XCTAssertEqual(content.distanceText, L10n.runDistanceUnavailable)
        XCTAssertEqual(content.distanceText, "未获取到定位，距离为空")
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
        // 有定位采样的记录：距离位仍是精确里程文案，历史行与详情页共用同一组数值。
        let record = makeRecord(
            distanceMeters: 5120,
            activeDuration: 1860,
            splits: [],
            samples: [sample(offset: 0), sample(offset: 1)]
        )
        let row = HistoryRowContent(record: record)
        let detail = RunDetailContent(record: record)

        XCTAssertTrue(record.hasLocationData)
        XCTAssertEqual(detail.distanceText, RunFormatting.distanceText(record.distance))
        XCTAssertEqual(detail.distanceText, "5.12 km")
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
