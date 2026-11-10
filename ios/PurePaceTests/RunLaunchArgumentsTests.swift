import XCTest
@testable import PurePace

final class RunLaunchArgumentsTests: XCTestCase {
    // MARK: - ac-autostart-default-off

    func testAutoStartRecordingDefaultsOff() {
        XCTAssertFalse(RunLaunchArguments.autoStartRecordingEnabled(arguments: []))
        XCTAssertFalse(RunLaunchArguments.autoStartRecordingEnabled(arguments: ["PurePace"]))
        XCTAssertFalse(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-uiTestLocation", "-uiTestResetArchive"]
            )
        )
    }

    // MARK: - ac-autostart-on-and-value

    func testAutoStartRecordingEnabledValues() {
        XCTAssertTrue(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-autoStartRecording", "1"]
            )
        )
        XCTAssertTrue(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-autoStartRecording", "true"]
            )
        )
        XCTAssertTrue(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-autoStartRecording"]
            )
        )
    }

    func testAutoStartRecordingDisabledValues() {
        XCTAssertFalse(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-autoStartRecording", "0"]
            )
        )
        XCTAssertFalse(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-autoStartRecording", "yes"]
            )
        )
    }

    // MARK: - ac-autostart-isolation

    func testAutoStartRecordingDoesNotReadLocationGate() {
        XCTAssertFalse(
            RunLaunchArguments.autoStartRecordingEnabled(arguments: ["PurePace", "-uiTestLocation"])
        )
        XCTAssertTrue(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-uiTestLocation", "-autoStartRecording", "1"]
            )
        )
        XCTAssertTrue(
            RunLaunchArguments.autoStartRecordingEnabled(
                arguments: ["PurePace", "-autoStartRecording", "1", "-uiTestLocation"]
            )
        )
    }

    // MARK: - ac-screenshot-launch-gating

    func testScreenshotInitialTabValueParsing() {
        XCTAssertEqual(
            RunLaunchArguments.value(
                after: RunLaunchArguments.screenshotInitialTabFlag,
                arguments: ["PurePace", "-screenshotInitialTab", "History"]
            ),
            "history"
        )
        XCTAssertEqual(
            RunLaunchArguments.value(
                after: RunLaunchArguments.screenshotInitialTabFlag,
                arguments: ["PurePace", "-screenshotInitialTab", "settings"]
            ),
            "settings"
        )
    }

    func testScreenshotInitialTabMissingOrInvalidValue() {
        XCTAssertNil(
            RunLaunchArguments.value(
                after: RunLaunchArguments.screenshotInitialTabFlag,
                arguments: ["PurePace"]
            )
        )
        XCTAssertNil(
            RunLaunchArguments.value(
                after: RunLaunchArguments.screenshotInitialTabFlag,
                arguments: ["PurePace", "-screenshotInitialTab"]
            )
        )
        XCTAssertNil(
            RunLaunchArguments.value(
                after: RunLaunchArguments.screenshotInitialTabFlag,
                arguments: ["PurePace", "-screenshotInitialTab", "-uiTestLocation"]
            )
        )
    }

    func testScreenshotFlagsAreOffByDefault() {
        XCTAssertFalse(
            RunLaunchArguments.flagEnabled(
                RunLaunchArguments.screenshotHistoryDemoFlag,
                arguments: ["PurePace", "-uiTestLocation"]
            )
        )
        XCTAssertFalse(
            RunLaunchArguments.flagEnabled(
                RunLaunchArguments.screenshotOpenRunDetailFlag,
                arguments: ["PurePace"]
            )
        )
        XCTAssertTrue(
            RunLaunchArguments.flagEnabled(
                RunLaunchArguments.screenshotHistoryDemoFlag,
                arguments: ["PurePace", "-screenshotHistoryDemo"]
            )
        )
        XCTAssertTrue(
            RunLaunchArguments.flagEnabled(
                RunLaunchArguments.screenshotOpenRunDetailFlag,
                arguments: ["PurePace", "-screenshotOpenRunDetail"]
            )
        )
    }
}
