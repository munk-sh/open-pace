import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

final class HarnessLocationCoreTests: XCTestCase {
    // MARK: - ac-corelocation-filter-pure

    func testAccuracyFilterAndFirstPointAnchorArePureLogic() throws {
        var core = HarnessCore(mode: .corelocation, checkpointStore: nil, appendsCheckpoints: false)
        let base: TimeInterval = 1_700_000_000

        // 无效精度（负值）与超阈值（> 50 m）都被拒绝。
        core.ingestLocation(
            try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0, longitude: 121.0, timestamp: base)),
            horizontalAccuracy: -1
        )
        core.ingestLocation(
            try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.00001, longitude: 121.0, timestamp: base + 1)),
            horizontalAccuracy: 60
        )
        // 首个通过精度过滤的样本只作锚点。
        core.ingestLocation(
            try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0, longitude: 121.0, timestamp: base + 2)),
            horizontalAccuracy: 10
        )
        // 后续样本正常累计。
        core.ingestLocation(
            try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0001, longitude: 121.0, timestamp: base + 3)),
            horizontalAccuracy: 10
        )
        core.ingestLocation(
            try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0002, longitude: 121.0, timestamp: base + 4)),
            horizontalAccuracy: 10
        )

        let status = core.status(now: Date(timeIntervalSince1970: base + 5))
        XCTAssertEqual(status.sampleCounts.received, 5)
        XCTAssertEqual(status.sampleCounts.accepted, 2)
        XCTAssertEqual(status.sampleCounts.rejectedByAccuracy, 2)
        XCTAssertEqual(status.sampleCounts.rejectedByFirstPoint, 1)
        XCTAssertEqual(status.rawSamples.map(\.accepted), [false, false, false, true, true])
        XCTAssertEqual(status.rawSamples[0].rejectedReason, "accuracy")
        XCTAssertEqual(status.rawSamples[1].rejectedReason, "accuracy")
        XCTAssertEqual(status.rawSamples[2].rejectedReason, "firstPoint")
        XCTAssertNil(status.rawSamples[3].rejectedReason)
        XCTAssertEqual(status.rawSamples[0].accuracyMeters, -1)
        XCTAssertEqual(status.rawSamples[3].accuracyMeters, 10)

        // 原始时间戳不被改写、顺序保持。
        XCTAssertEqual(
            status.rawSamples.map(\.timestamp),
            [base, base + 1, base + 2, base + 3, base + 4]
        )

        // 距离从锚点起累计后续样本之间的位移（首点本身不计距离），活跃时长同样从锚点起算。
        let expectedMeters = GeoDistance.meters(
            latitude1: 31.0, longitude1: 121.0,
            latitude2: 31.0001, longitude2: 121.0
        ) + GeoDistance.meters(
            latitude1: 31.0001, longitude1: 121.0,
            latitude2: 31.0002, longitude2: 121.0
        )
        XCTAssertEqual(status.actual.distanceMeters, expectedMeters, accuracy: 0.001)
        XCTAssertEqual(status.actual.elapsedSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(status.actual.completedKilometers, 0)
        XCTAssertEqual(status.mode, "corelocation")
    }

    // MARK: - ac-corelocation-authorization

    func testCoreLocationStatusCarriesAuthorizationField() throws {
        var core = HarnessCore(mode: .corelocation, checkpointStore: nil, appendsCheckpoints: false)
        XCTAssertTrue(core.status().includesLocationAuthorization)
        XCTAssertNil(core.status().locationAuthorization)

        core.setLocationAuthorization(.authorizedWhenInUse)
        let status = core.status(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(status.locationAuthorization, "authorizedWhenInUse")
        let object = try JSONSerialization.jsonObject(
            with: try HarnessStatusWriter.encode(status)
        ) as? [String: Any]
        XCTAssertEqual(object?["locationAuthorization"] as? String, "authorizedWhenInUse")

        for authorization in HarnessLocationAuthorization.allCases {
            XCTAssertFalse(authorization.rawValue.isEmpty)
        }
        XCTAssertEqual(
            Set(HarnessLocationAuthorization.allCases.map(\.rawValue)),
            ["notDetermined", "restricted", "denied", "authorizedWhenInUse", "authorizedAlways"]
        )
    }

    // MARK: - ac-status-raw-samples

    func testRawSamplesMatchSampleCountsInDirectMode() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let base: TimeInterval = 1_700_000_000
        let lines = [
            "{\"type\":\"start\",\"timestamp\":\(base)}",
            HarnessTestSupport.sampleLine(latitude: 31.0, longitude: 121.0, timestamp: base + 1),
            HarnessTestSupport.sampleLine(latitude: 31.0001, longitude: 121.0, timestamp: base + 2, accuracy: 5),
        ]
        let streamURL = directory.appendingPathComponent("stream.jsonl")
        try HarnessTestSupport.writeStream(lines, to: streamURL)

        let status = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: directory.appendingPathComponent("status.json"),
                checkpointURL: directory.appendingPathComponent("checkpoint.jsonl"),
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()

        XCTAssertEqual(status.rawSamples.count, 2)
        XCTAssertEqual(status.sampleCounts.received, status.rawSamples.count)
        XCTAssertEqual(status.sampleCounts.accepted, status.rawSamples.filter(\.accepted).count)
        XCTAssertEqual(status.rawSamples[0].timestamp, base + 1)
        XCTAssertEqual(status.rawSamples[1].accuracyMeters, 5)
        XCTAssertTrue(status.rawSamples.allSatisfy(\.accepted))
    }
}
