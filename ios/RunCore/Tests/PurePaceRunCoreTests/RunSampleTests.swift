import XCTest
import PurePaceRunCore

final class RunSampleTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testRunSampleRejectsInvalidCoordinates() {
        XCTAssertNil(RunSample(latitude: 91, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: -91, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 181, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: -181, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: .nan, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: .infinity, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))

        XCTAssertNotNil(RunSample(latitude: 90, longitude: 180, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNotNil(RunSample(latitude: -90, longitude: -180, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: nil))
    }

    func testRunSampleRejectsInvalidOptionalFields() {
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: .infinity, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: .nan, timestamp: timestamp, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: nil, timestamp: .distantPast, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: nil, timestamp: .distantFuture, heartRate: nil, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: 0, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: -5, cadence: nil))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: 0))
        XCTAssertNil(RunSample(latitude: 0, longitude: 0, altitude: nil, timestamp: timestamp, heartRate: nil, cadence: -1))
    }

    func testRunSampleAcceptsValidPointAndKeepsFields() {
        let sample = RunSample(
            latitude: 31.2304,
            longitude: 121.4737,
            altitude: 12.5,
            timestamp: timestamp,
            heartRate: 148,
            cadence: 176
        )
        XCTAssertNotNil(sample)
        guard let sample else { return }
        XCTAssertEqual(sample.latitude, 31.2304)
        XCTAssertEqual(sample.longitude, 121.4737)
        XCTAssertEqual(sample.altitude, 12.5)
        XCTAssertEqual(sample.timestamp, timestamp)
        XCTAssertEqual(sample.heartRate, 148)
        XCTAssertEqual(sample.cadence, 176)

        XCTAssertNotEqual(sample, RunSample(latitude: 31.2304, longitude: 121.4737, altitude: 12.5, timestamp: timestamp, heartRate: 149, cadence: 176))
        XCTAssertEqual(sample, RunSample(latitude: 31.2304, longitude: 121.4737, altitude: 12.5, timestamp: timestamp, heartRate: 148, cadence: 176))
    }
}
