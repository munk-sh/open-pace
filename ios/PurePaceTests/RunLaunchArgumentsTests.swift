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
}
