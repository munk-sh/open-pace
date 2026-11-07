import XCTest
import PurePaceRunCore

final class RunCoreErrorTests: XCTestCase {
    func testRunCoreErrorDescriptionsAreNonEmptyAndDistinct() {
        let errors: [RunCoreError] = [
            .invalidDistance(-1),
            .invalidPace(0),
            .invalidDuration(-2),
            .invalidSplitIndex(0),
            .invalidCoordinate(latitude: 91, longitude: 181),
            .invalidSample("latitude"),
            .invalidStateTransition(from: .ready, to: .running),
            .corruptedCheckpoint("truncated tail")
        ]

        var seen = Set<String>()
        for error in errors {
            let description = error.description
            XCTAssertFalse(description.isEmpty, "description 不应为空: \(error)")
            XCTAssertTrue(seen.insert(description).inserted, "description 重复: \(description)")
        }
        XCTAssertEqual(seen.count, errors.count)
    }

    func testRunCoreErrorEquality() {
        XCTAssertEqual(RunCoreError.invalidDistance(-1), .invalidDistance(-1))
        XCTAssertNotEqual(RunCoreError.invalidDistance(-1), .invalidDistance(-2))
        XCTAssertNotEqual(RunCoreError.invalidDistance(-1), .invalidPace(-1))
        XCTAssertEqual(
            RunCoreError.invalidStateTransition(from: .ready, to: .running),
            .invalidStateTransition(from: .ready, to: .running)
        )
        XCTAssertNotEqual(
            RunCoreError.invalidStateTransition(from: .ready, to: .running),
            .invalidStateTransition(from: .running, to: .ready)
        )
    }
}
