import XCTest
@testable import PurePace

final class PlaceholderCopyTests: XCTestCase {
    func testAppNameAndTaglineArePresent() {
        XCTAssertEqual(PlaceholderCopy.appName, "PurePace")
        XCTAssertTrue(PlaceholderCopy.tagline.hasSuffix("."))
        XCTAssertFalse(PlaceholderCopy.tagline.isEmpty)
    }

    func testTabsExposeFourPlaceholdersInOrder() {
        XCTAssertEqual(
            PlaceholderTab.allCases.map(\.title),
            ["Run", "History", "Log", "Settings"]
        )
    }

    func testTabRawValuesAreStable() {
        XCTAssertEqual(
            PlaceholderTab.allCases.map(\.rawValue),
            ["run", "history", "log", "settings"]
        )
    }

    func testEachTabUsesDistinctSystemImage() {
        let images = PlaceholderTab.allCases.map(\.systemImage)
        XCTAssertEqual(Set(images).count, PlaceholderTab.allCases.count)
        XCTAssertFalse(images.contains(where: \.isEmpty))
    }
}
