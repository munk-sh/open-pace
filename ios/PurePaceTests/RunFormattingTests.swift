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
}
