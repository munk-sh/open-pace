import XCTest

final class PlaceholderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlaceholderScreenShowsNameTaglineAndTabs() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["PurePace"].waitForExistence(timeout: 10),
            "首屏缺少 PurePace 文案"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "缺少 Tab 栏")
        for title in ["Run", "History", "Log", "Settings"] {
            XCTAssertTrue(tabBar.buttons[title].exists, "缺少 Tab: \(title)")
        }

        XCTAssertTrue(
            app.staticTexts["Your pace, purely yours."].exists,
            "首屏缺少 tagline"
        )
    }
}
