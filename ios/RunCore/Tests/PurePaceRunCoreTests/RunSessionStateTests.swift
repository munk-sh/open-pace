import XCTest
import PurePaceRunCore

final class RunSessionStateTests: XCTestCase {
    func testRunSessionStateCasesAndRawValues() {
        XCTAssertEqual(RunSessionState.allCases, [.ready, .running, .paused, .finished])
        XCTAssertEqual(
            RunSessionState.allCases.map(\.rawValue),
            ["ready", "running", "paused", "finished"]
        )
    }

    func testRunSessionStateDerivedFlags() {
        XCTAssertFalse(RunSessionState.ready.isActive)
        XCTAssertTrue(RunSessionState.running.isActive)
        XCTAssertTrue(RunSessionState.paused.isActive)
        XCTAssertFalse(RunSessionState.finished.isActive)

        XCTAssertFalse(RunSessionState.ready.isTerminal)
        XCTAssertFalse(RunSessionState.running.isTerminal)
        XCTAssertFalse(RunSessionState.paused.isTerminal)
        XCTAssertTrue(RunSessionState.finished.isTerminal)
    }
}
