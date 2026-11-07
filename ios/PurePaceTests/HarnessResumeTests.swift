import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

final class HarnessResumeTests: XCTestCase {
    // MARK: - ac-resume-restore / ac-resume-no-new-checkpoint

    func testResumeRestoresFinishedCheckpointWithoutAppending() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let checkpointURL = directory.appendingPathComponent("checkpoint.jsonl")
        let streamURL = try makeFinishedStream(in: directory, name: "stream.jsonl")

        let direct = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: directory.appendingPathComponent("direct-status.json"),
                checkpointURL: checkpointURL,
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()
        XCTAssertEqual(direct.state, "finished")
        XCTAssertEqual(direct.actual.completedKilometers, 1)

        let checkpointDataBefore = try Data(contentsOf: checkpointURL)
        let checkpoint = try XCTUnwrap(RunCheckpointStore(fileURL: checkpointURL).loadLatest())
        XCTAssertEqual(checkpoint.state, .finished)

        let statusURL = directory.appendingPathComponent("resume-status.json")
        let resumed = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .resume,
                statusURL: statusURL,
                checkpointURL: checkpointURL,
                streamURL: nil,
                maxDurationSeconds: nil
            )
        ).run()

        XCTAssertEqual(resumed.mode, "resume")
        XCTAssertTrue(resumed.resumed)
        XCTAssertEqual(resumed.state, "finished")
        XCTAssertNil(resumed.error)
        XCTAssertTrue(resumed.announcements.isEmpty, "恢复后不得重复播报已完成公里")

        let restored = try XCTUnwrap(resumed.restored)
        XCTAssertEqual(restored.checkpointPath, checkpointURL.path)
        XCTAssertEqual(restored.completedDistanceMeters, checkpoint.completedDistance.meters)
        XCTAssertEqual(restored.elapsedSeconds, checkpoint.elapsed)
        XCTAssertEqual(restored.splitCount, checkpoint.splits.count)
        XCTAssertEqual(restored.announcedSplitIndex, checkpoint.announcedSplitIndex ?? checkpoint.splits.count)

        XCTAssertEqual(resumed.actual.distanceMeters, checkpoint.completedDistance.meters)
        XCTAssertEqual(resumed.actual.elapsedSeconds, checkpoint.elapsed)
        XCTAssertEqual(resumed.splits.count, checkpoint.splits.count)

        // 不追加、不改写既有 checkpoint 内容。
        XCTAssertEqual(try Data(contentsOf: checkpointURL), checkpointDataBefore)
        XCTAssertEqual(try RunCheckpointStore(fileURL: checkpointURL).loadAll().count, 4)

        let object = try HarnessTestSupport.decodeJSONObject(at: statusURL)
        XCTAssertEqual(object["resumed"] as? Bool, true)
        XCTAssertEqual(object["state"] as? String, "finished")
        let restoredObject = try XCTUnwrap(object["restored"] as? [String: Any])
        XCTAssertEqual(restoredObject["splitCount"] as? Int, checkpoint.splits.count)
        XCTAssertEqual(restoredObject["checkpointPath"] as? String, checkpointURL.path)
        XCTAssertEqual((object["announcements"] as? [Any])?.count, 0)
    }

    func testResumeFromActiveCheckpointReturnsPaused() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let checkpointURL = directory.appendingPathComponent("checkpoint.jsonl")
        let base: TimeInterval = 1_700_000_000
        let lines = [
            "{\"type\":\"start\",\"timestamp\":\(base)}",
            HarnessTestSupport.sampleLine(latitude: 31.0, longitude: 121.0, timestamp: base + 1),
            HarnessTestSupport.sampleLine(latitude: 31.001, longitude: 121.0, timestamp: base + 2),
        ]
        let streamURL = directory.appendingPathComponent("stream.jsonl")
        try HarnessTestSupport.writeStream(lines, to: streamURL)

        _ = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: directory.appendingPathComponent("direct-status.json"),
                checkpointURL: checkpointURL,
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()
        let checkpoint = try XCTUnwrap(RunCheckpointStore(fileURL: checkpointURL).loadLatest())
        XCTAssertEqual(checkpoint.state, .running)

        let resumed = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .resume,
                statusURL: directory.appendingPathComponent("resume-status.json"),
                checkpointURL: checkpointURL,
                streamURL: nil,
                maxDurationSeconds: nil
            )
        ).run()

        XCTAssertTrue(resumed.resumed)
        XCTAssertEqual(resumed.state, "paused")
        XCTAssertTrue(resumed.announcements.isEmpty)
        XCTAssertEqual(resumed.actual.distanceMeters, checkpoint.completedDistance.meters)
    }

    func testResumeWithoutCheckpointReportsCheckpointMissing() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let checkpointURL = directory.appendingPathComponent("missing.jsonl")
        let statusURL = directory.appendingPathComponent("resume-status.json")

        let resumed = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .resume,
                statusURL: statusURL,
                checkpointURL: checkpointURL,
                streamURL: nil,
                maxDurationSeconds: nil
            )
        ).run()

        XCTAssertFalse(resumed.resumed)
        XCTAssertNil(resumed.restored)
        XCTAssertEqual(resumed.error?.code, "checkpointMissing")
        XCTAssertEqual(resumed.actual.distanceMeters, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path), "缺 checkpoint 时不得伪造文件")

        let object = try HarnessTestSupport.decodeJSONObject(at: statusURL)
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? String, "checkpointMissing")
        XCTAssertTrue(object["restored"] is NSNull)
        XCTAssertEqual(object["resumed"] as? Bool, false)
    }

    private func makeFinishedStream(in directory: URL, name: String) throws -> URL {
        let base: TimeInterval = 1_700_000_000
        var lines = ["{\"type\":\"start\",\"timestamp\":\(base)}"]
        for step in 0...10 {
            lines.append(
                HarnessTestSupport.sampleLine(
                    latitude: 31.0 + Double(step) * 100.0 / HarnessTestSupport.metersPerDegreeLatitude,
                    longitude: 121.0,
                    timestamp: base + Double(step) * 10 + 1
                )
            )
        }
        lines.append("{\"type\":\"finish\",\"timestamp\":\(base + 120)}")
        let url = directory.appendingPathComponent(name)
        try HarnessTestSupport.writeStream(lines, to: url)
        return url
    }
}
