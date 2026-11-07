import XCTest
import PurePaceRunCore

final class RunMetricsTests: XCTestCase {
    func testRunDistanceRejectsInvalidAndAcceptsValidValues() {
        XCTAssertNil(RunDistance(meters: -1))
        XCTAssertNil(RunDistance(meters: -0.5))
        XCTAssertNil(RunDistance(meters: .infinity))
        XCTAssertNil(RunDistance(meters: -.infinity))
        XCTAssertNil(RunDistance(meters: .nan))

        let zero = RunDistance(meters: 0)
        XCTAssertNotNil(zero)
        XCTAssertEqual(zero?.meters, 0)

        let thousand = RunDistance(meters: 1000)
        XCTAssertEqual(thousand?.meters, 1000)
    }

    func testRunDistanceIsComparableAndHashable() {
        let small = RunDistance(meters: 500)
        let large = RunDistance(meters: 1000)
        XCTAssertNotNil(small)
        XCTAssertNotNil(large)
        guard let small, let large else { return }
        XCTAssertLessThan(small, large)
        XCTAssertEqual(Set([small, large, small]).count, 2)
        XCTAssertEqual(small, RunDistance(meters: 500))
        XCTAssertNotEqual(small, large)
    }

    func testRunPaceRejectsInvalidSecondsPerKilometer() {
        XCTAssertNil(RunPace(secondsPerKilometer: 0))
        XCTAssertNil(RunPace(secondsPerKilometer: -3))
        XCTAssertNil(RunPace(secondsPerKilometer: .nan))
        XCTAssertNil(RunPace(secondsPerKilometer: .infinity))

        let pace = RunPace(secondsPerKilometer: 300)
        XCTAssertEqual(pace?.secondsPerKilometer, 300)
    }

    func testRunPaceDerivedFromDistanceAndDuration() {
        guard let distance = RunDistance(meters: 1000) else {
            return XCTFail("合法距离不应为 nil")
        }
        XCTAssertEqual(RunPace(distance: distance, duration: 300)?.secondsPerKilometer, 300)
        XCTAssertEqual(RunPace(distance: distance, duration: 450)?.secondsPerKilometer, 450)

        guard let zeroDistance = RunDistance(meters: 0) else {
            return XCTFail("零距离本身合法")
        }
        XCTAssertNil(RunPace(distance: zeroDistance, duration: 300))
        XCTAssertNil(RunPace(distance: distance, duration: 0))
        XCTAssertNil(RunPace(distance: distance, duration: -10))
        XCTAssertNil(RunPace(distance: distance, duration: .nan))
        XCTAssertNil(RunPace(distance: distance, duration: .infinity))
    }

    func testRunSplitValidationAndDerivedPace() {
        guard let distance = RunDistance(meters: 1000) else {
            return XCTFail("合法距离不应为 nil")
        }
        let split = RunSplit(index: 1, distance: distance, duration: 360)
        XCTAssertNotNil(split)
        XCTAssertEqual(split?.index, 1)
        XCTAssertEqual(split?.distance, distance)
        XCTAssertEqual(split?.duration, 360)
        XCTAssertNotNil(split?.pace)
        XCTAssertEqual(split?.pace?.secondsPerKilometer, 360)

        XCTAssertNil(RunSplit(index: 0, distance: distance, duration: 360))
        XCTAssertNil(RunSplit(index: -2, distance: distance, duration: 360))
        XCTAssertNil(RunSplit(index: 1, distance: distance, duration: 0))
        XCTAssertNil(RunSplit(index: 1, distance: distance, duration: -5))
        XCTAssertNil(RunSplit(index: 1, distance: distance, duration: .infinity))
    }
}
