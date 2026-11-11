import XCTest
import PurePaceRunCore
@testable import PurePace

final class RunFormattingTests: XCTestCase {
    func testDistanceTextCarriesUnitAndTwoDecimals() {
        XCTAssertEqual(RunFormatting.distanceText(RunDistance(meters: 0)!), "0.00 km")
        XCTAssertEqual(RunFormatting.distanceText(RunDistance(meters: 1234)!), "1.23 km")
    }

    func testElapsedTextUsesMonospacedFraction() {
        XCTAssertEqual(RunFormatting.elapsedText(0), "00:00")
        XCTAssertEqual(RunFormatting.elapsedText(65.9), "01:05")
        XCTAssertEqual(RunFormatting.elapsedText(3725), "1:02:05")
    }

    func testPaceTextPlaceholderAndValue() {
        XCTAssertEqual(RunFormatting.paceText(nil), "--")
        XCTAssertEqual(
            RunFormatting.paceText(RunPace(secondsPerKilometer: 300)!),
            "5:00 /km"
        )
        XCTAssertEqual(
            RunFormatting.paceText(RunPace(secondsPerKilometer: 333.4)!),
            "5:33 /km"
        )
    }

    func testSplitCountTextNeverNegative() {
        XCTAssertEqual(RunFormatting.splitCountText(3), "3")
        XCTAssertEqual(RunFormatting.splitCountText(-1), "0")
    }

    // MARK: - 数值 / 单位拆分（RunView 三行指标块）

    func testDistanceValueAndUnitRecombineToDistanceText() {
        for meters in [0.0, 1234.0, 999.999] {
            let distance = RunDistance(meters: meters)!
            XCTAssertEqual(
                "\(RunFormatting.distanceValueText(distance)) \(RunFormatting.distanceUnitText)",
                RunFormatting.distanceText(distance)
            )
        }
        let zero = RunDistance(meters: 0)!
        XCTAssertEqual(RunFormatting.distanceValueText(zero), "0.00")
        XCTAssertEqual(RunFormatting.distanceUnitText, "km")
        XCTAssertEqual(
            RunFormatting.distanceValueText(RunDistance(meters: 1234)!),
            "1.23"
        )
    }

    func testPaceValueAndUnitRecombineToPaceText() {
        XCTAssertEqual(RunFormatting.paceValueText(nil), RunFormatting.emptyPace)
        XCTAssertNil(RunFormatting.paceUnitText(nil), "空配速不得渲染单位行")

        let pace = RunPace(secondsPerKilometer: 333.4)!
        XCTAssertEqual(RunFormatting.paceValueText(pace), "5:33")
        XCTAssertEqual(RunFormatting.paceUnitText(pace), "/km")
        XCTAssertEqual(
            "\(RunFormatting.paceValueText(pace)) \(RunFormatting.paceUnitText(pace)!)",
            RunFormatting.paceText(pace)
        )
    }

    func testPaceValueTextMarksPlaceholderOnlyWhenEmpty() {
        XCTAssertEqual(
            RunFormatting.paceValueText(RunPace(secondsPerKilometer: 300)!),
            "5:00"
        )
        XCTAssertEqual(
            RunFormatting.paceValueText(RunPace(secondsPerKilometer: 59.6)!),
            "1:00",
            "配速数值按秒四舍五入，不残留小数"
        )
        XCTAssertFalse(RunFormatting.paceValueText(RunPace(secondsPerKilometer: 300)!).contains("/km"))
    }

    func testDateTimeTextDiffersAcrossStartAndEnd() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_000_301)
        let startedText = RunFormatting.dateTimeText(start)
        let endedText = RunFormatting.dateTimeText(end)
        XCTAssertFalse(startedText.isEmpty)
        XCTAssertFalse(endedText.isEmpty)
        XCTAssertNotEqual(startedText, endedText)
    }

    func testSplitTextHelpers() {
        XCTAssertEqual(RunFormatting.splitIndexText(2), "2")
        XCTAssertEqual(RunFormatting.splitSummaryText(count: 3), "分段 · 3")
        XCTAssertEqual(RunFormatting.splitSummaryText(count: -1), "分段 · 0")
    }
}
