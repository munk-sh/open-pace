import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

final class HarnessArgumentTests: XCTestCase {
    // MARK: - ac-harness-args-parse

    func testNoHarnessArgumentIsInactiveEvenWithOtherFlags() {
        XCTAssertEqual(HarnessArgumentParser.parse(arguments: ["PurePace"]), .inactive)
        XCTAssertEqual(
            HarnessArgumentParser.parse(arguments: ["PurePace", "--status", "/tmp/s.json"]),
            .inactive
        )
    }

    func testParsesAllThreeModesWithRequiredArguments() throws {
        let direct = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "direct",
            "--status", "/tmp/status.json",
            "--stream", "/tmp/stream.jsonl",
            "--checkpoint", "/tmp/checkpoint.jsonl",
            "--max-duration", "30",
        ])
        guard case let .active(directConfiguration) = direct else {
            return XCTFail("direct 参数应解析成功")
        }
        XCTAssertEqual(directConfiguration.mode, .direct)
        XCTAssertEqual(directConfiguration.statusURL.path, "/tmp/status.json")
        XCTAssertEqual(directConfiguration.streamURL?.path, "/tmp/stream.jsonl")
        XCTAssertEqual(directConfiguration.checkpointURL.path, "/tmp/checkpoint.jsonl")
        XCTAssertEqual(directConfiguration.maxDurationSeconds, 30)

        let corelocation = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "corelocation",
            "--status", "/tmp/status.json",
            "--checkpoint", "/tmp/checkpoint.jsonl",
        ])
        guard case let .active(locationConfiguration) = corelocation else {
            return XCTFail("corelocation 参数应解析成功")
        }
        XCTAssertEqual(locationConfiguration.mode, .corelocation)
        XCTAssertNil(locationConfiguration.streamURL)
        XCTAssertNil(locationConfiguration.maxDurationSeconds)

        let resume = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "resume",
            "--status", "/tmp/status.json",
            "--checkpoint", "/tmp/checkpoint.jsonl",
        ])
        guard case let .active(resumeConfiguration) = resume else {
            return XCTFail("resume 参数应解析成功")
        }
        XCTAssertEqual(resumeConfiguration.mode, .resume)
        XCTAssertNil(resumeConfiguration.streamURL)
    }

    func testRejectsUnknownModeAndMissingRequiredArguments() {
        guard case let .invalid(mode, _, error) = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "bogus", "--status", "/tmp/status.json",
        ]) else {
            return XCTFail("未知模式应解析失败")
        }
        XCTAssertNil(mode)
        XCTAssertEqual(error.code, "unknownHarnessMode")

        guard case let .invalid(directMode, statusURL, missing) = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "direct",
            "--status", "/tmp/status.json",
            "--checkpoint", "/tmp/checkpoint.jsonl",
        ]) else {
            return XCTFail("direct 缺 --stream 应解析失败")
        }
        XCTAssertEqual(directMode, .direct)
        XCTAssertEqual(statusURL?.path, "/tmp/status.json")
        XCTAssertEqual(missing.code, "missingArgument")
        XCTAssertTrue(missing.message.contains("--stream"))

        guard case let .invalid(_, locationStatus, locationMissing) = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "corelocation", "--checkpoint", "/tmp/checkpoint.jsonl",
        ]) else {
            return XCTFail("corelocation 缺 --status 应解析失败")
        }
        XCTAssertNil(locationStatus)
        XCTAssertEqual(locationMissing.code, "missingArgument")

        guard case let .invalid(_, resumeStatus, resumeMissing) = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "resume", "--status", "/tmp/status.json",
        ]) else {
            return XCTFail("resume 缺 --checkpoint 应解析失败")
        }
        XCTAssertNotNil(resumeStatus)
        XCTAssertEqual(resumeMissing.code, "missingArgument")
        XCTAssertTrue(resumeMissing.message.contains("--checkpoint"))

        guard case let .invalid(_, _, durationError) = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "resume",
            "--status", "/tmp/status.json",
            "--checkpoint", "/tmp/checkpoint.jsonl",
            "--max-duration", "0",
        ]) else {
            return XCTFail("非法 --max-duration 应解析失败")
        }
        XCTAssertEqual(durationError.code, "invalidMaxDuration")
    }

    func testArgumentFailureWritesErrorStatusWhenStatusPathProvided() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let statusURL = directory.appendingPathComponent("nested/status.json")
        let activation = HarnessArgumentParser.parse(arguments: [
            "PurePace", "--harness", "bogus", "--status", statusURL.path,
        ])

        let status = try XCTUnwrap(HarnessBootstrap.writeArgumentFailure(activation))
        XCTAssertEqual(status.schemaVersion, 1)
        XCTAssertEqual(status.error?.code, "unknownHarnessMode")

        let object = try HarnessTestSupport.decodeJSONObject(at: statusURL)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? String, "unknownHarnessMode")
        XCTAssertTrue(object["restored"] is NSNull)
        for key in HarnessStatusContract.requiredTopLevelKeys {
            XCTAssertTrue(object.keys.contains(key), "status 缺少顶层键 \(key)")
        }

        // 没有 --status 时不落盘、不崩溃。
        let withoutStatus = HarnessArgumentParser.parse(arguments: ["PurePace", "--harness", "bogus"])
        XCTAssertNil(HarnessBootstrap.writeArgumentFailure(withoutStatus))
    }
}

enum HarnessStatusContract {
    static let requiredTopLevelKeys = [
        "schemaVersion", "mode", "state", "startedAt", "updatedAt", "finishedAt", "resumed",
        "restored", "rawSamples", "sampleCounts", "actual", "thresholds", "splits",
        "announcements", "error",
    ]

    static let requiredActualKeys = [
        "distanceMeters", "elapsedSeconds", "averagePaceSecondsPerKilometer",
        "currentPaceSecondsPerKilometer", "completedKilometers", "splitCount", "splitSampleIndexes",
    ]

    static let requiredThresholdKeys = [
        "distanceRelativeErrorMax", "paceErrorMaxSecondsPerKilometer",
        "splitBoundaryToleranceSamples", "accuracyFilterMeters", "checkpointEveryAcceptedSamples",
    ]
}

final class HarnessStatusWriterTests: XCTestCase {
    // MARK: - ac-status-atomic-write

    func testAtomicWriterAlwaysLeavesCompleteJSON() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let url = directory.appendingPathComponent("status.json")

        for index in 0..<25 {
            let status = HarnessStatus.failure(
                mode: "direct",
                error: HarnessStatusError(code: "e\(index)", message: "第 \(index) 次写入"),
                now: Date(timeIntervalSince1970: Double(index))
            )
            try HarnessStatusWriter.write(status, to: url)
            let object = try HarnessTestSupport.decodeJSONObject(at: url)
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
            XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? String, "e\(index)")
        }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "不应残留临时文件: \(leftovers)")
    }

    // MARK: - ac-status-schema-complete / ac-threshold-values

    func testStatusSchemaAndThresholdsAreComplete() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let statusURL = directory.appendingPathComponent("status.json")

        var core = HarnessCore(mode: .direct, checkpointStore: nil, appendsCheckpoints: false)
        core.start(at: Date(timeIntervalSince1970: 1_700_000_000))
        let sample = try XCTUnwrap(
            HarnessTestSupport.sample(latitude: 31.0, longitude: 121.0, timestamp: 1_700_000_001)
        )
        core.ingest(sample)
        try HarnessStatusWriter.write(core.status(now: Date(timeIntervalSince1970: 1_700_000_002)), to: statusURL)

        let object = try HarnessTestSupport.decodeJSONObject(at: statusURL)
        for key in HarnessStatusContract.requiredTopLevelKeys {
            XCTAssertTrue(object.keys.contains(key), "status 缺少顶层键 \(key)")
        }
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["mode"] as? String, "direct")
        XCTAssertEqual(object["state"] as? String, "running")
        XCTAssertTrue(object["restored"] is NSNull)
        XCTAssertTrue(object["error"] is NSNull)
        XCTAssertNil(object["locationAuthorization"])

        let actual = try XCTUnwrap(object["actual"] as? [String: Any])
        for key in HarnessStatusContract.requiredActualKeys {
            XCTAssertTrue(actual.keys.contains(key), "actual 缺少键 \(key)")
        }
        let thresholds = try XCTUnwrap(object["thresholds"] as? [String: Any])
        for key in HarnessStatusContract.requiredThresholdKeys {
            XCTAssertTrue(thresholds.keys.contains(key), "thresholds 缺少键 \(key)")
        }
        XCTAssertEqual(thresholds["distanceRelativeErrorMax"] as? Double, 0.01)
        XCTAssertEqual(thresholds["paceErrorMaxSecondsPerKilometer"] as? Double, 2.0)
        XCTAssertEqual(thresholds["splitBoundaryToleranceSamples"] as? Int, 1)
        XCTAssertEqual(thresholds["accuracyFilterMeters"] as? Double, 50.0)
        XCTAssertEqual(thresholds["checkpointEveryAcceptedSamples"] as? Int, 10)
        XCTAssertEqual(core.status().thresholds, HarnessThresholdsRecord.fixed)

        let counts = try XCTUnwrap(object["sampleCounts"] as? [String: Any])
        XCTAssertEqual(counts["received"] as? Int, 1)
        XCTAssertEqual(counts["accepted"] as? Int, 1)
        XCTAssertEqual(counts["rejectedByAccuracy"] as? Int, 0)
        XCTAssertEqual(counts["rejectedByFirstPoint"] as? Int, 0)
    }
}
