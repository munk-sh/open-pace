import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

final class HarnessDirectRunTests: XCTestCase {
    // MARK: - ac-direct-metrics-within-threshold / ac-announcement-exactly-once

    func testDirectMetricsWithinThresholdsAndAnnouncementsExactlyOnce() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }

        let points = HarnessTestSupport.referenceRoute(meters: 2_200)
        let streamURL = try makeStream(points: points, in: directory, name: "stream.jsonl")
        let statusURL = directory.appendingPathComponent("status.json")
        let checkpointURL = directory.appendingPathComponent("checkpoint.jsonl")
        let configuration = HarnessConfiguration(
            mode: .direct,
            statusURL: statusURL,
            checkpointURL: checkpointURL,
            streamURL: streamURL,
            maxDurationSeconds: nil
        )

        let status = HarnessRunner(configuration: configuration).run()

        XCTAssertEqual(status.state, "finished")
        XCTAssertEqual(status.mode, "direct")
        XCTAssertFalse(status.resumed)
        XCTAssertNil(status.error)

        let reference = HarnessTestSupport.cumulativeDistances(points)
        let totalReferenceMeters = reference.last ?? 0
        XCTAssertGreaterThan(totalReferenceMeters, 1_000)
        XCTAssertEqual(
            status.actual.distanceMeters,
            totalReferenceMeters,
            accuracy: totalReferenceMeters * HarnessThresholdValues.distanceRelativeErrorMax
        )

        let referenceElapsed = points[points.count - 1].timestamp.timeIntervalSince(points[0].timestamp)
        XCTAssertEqual(status.actual.elapsedSeconds, referenceElapsed, accuracy: 0.001)
        let referenceAveragePace = referenceElapsed / (totalReferenceMeters / 1000.0)
        XCTAssertEqual(
            try XCTUnwrap(status.actual.averagePaceSecondsPerKilometer),
            referenceAveragePace,
            accuracy: HarnessThresholdValues.paceErrorMaxSecondsPerKilometer
        )

        // 当前配速：与最近 10 s 滑动窗口的独立累加结果比对。
        let window = Array(points.suffix(min(11, points.count)))
        let windowElapsed = window[window.count - 1].timestamp.timeIntervalSince(window[0].timestamp)
        var windowMeters = 0.0
        for index in 1..<window.count {
            windowMeters += GeoDistance.meters(
                latitude1: window[index - 1].latitude,
                longitude1: window[index - 1].longitude,
                latitude2: window[index].latitude,
                longitude2: window[index].longitude
            )
        }
        let referenceCurrentPace = windowElapsed / (windowMeters / 1000.0)
        XCTAssertEqual(
            try XCTUnwrap(status.actual.currentPaceSecondsPerKilometer),
            referenceCurrentPace,
            accuracy: HarnessThresholdValues.paceErrorMaxSecondsPerKilometer
        )

        // 分段采样索引：±1 采样点。
        XCTAssertEqual(status.actual.splitCount, 2)
        XCTAssertEqual(status.actual.completedKilometers, 2)
        XCTAssertEqual(status.actual.splitSampleIndexes.count, 2)
        for kilometer in 1...2 {
            let boundary = Double(kilometer) * 1000.0
            let expectedIndex = try XCTUnwrap(reference.firstIndex { $0 >= boundary }) + 1
            let actualIndex = status.actual.splitSampleIndexes[kilometer - 1]
            XCTAssertLessThanOrEqual(
                abs(actualIndex - expectedIndex),
                HarnessThresholdValues.splitBoundaryToleranceSamples
            )
        }

        // 每个整公里恰好 1 条播报，字段完整；finish 只产生收尾播报。
        let kilometerAnnouncements = status.announcements.filter { $0.trigger == "kilometerCompleted" }
        XCTAssertEqual(kilometerAnnouncements.count, 2)
        for kilometer in 1...2 {
            XCTAssertEqual(kilometerAnnouncements.filter { $0.splitIndex == kilometer }.count, 1)
        }
        for announcement in status.announcements {
            XCTAssertFalse(announcement.trigger.isEmpty)
            XCTAssertGreaterThanOrEqual(announcement.splitIndex, 1)
            XCTAssertEqual(announcement.distanceMeters, Double(announcement.splitIndex) * 1000.0, accuracy: 0.001)
            XCTAssertGreaterThan(announcement.paceSecondsPerKilometer, 0)
            XCTAssertGreaterThanOrEqual(announcement.elapsedSeconds, 0)
        }
        XCTAssertEqual(status.announcements.filter { $0.trigger == "finished" }.count, 1)

        // 同一输入重复运行（除时间戳外）结果一致。
        let secondConfiguration = HarnessConfiguration(
            mode: .direct,
            statusURL: directory.appendingPathComponent("status-second.json"),
            checkpointURL: directory.appendingPathComponent("checkpoint-second.jsonl"),
            streamURL: streamURL,
            maxDurationSeconds: nil
        )
        let second = HarnessRunner(configuration: secondConfiguration).run()
        XCTAssertEqual(second.actual, status.actual)
        XCTAssertEqual(second.rawSamples, status.rawSamples)
        XCTAssertEqual(second.sampleCounts, status.sampleCounts)
        XCTAssertEqual(second.splits, status.splits)
        XCTAssertEqual(second.announcements, status.announcements)
        XCTAssertEqual(second.thresholds, status.thresholds)
        XCTAssertEqual(second.restored, status.restored)
    }

    // MARK: - ac-direct-stream-order

    func testPausedIntervalFreezesMetricsAndAnnouncementQueue() throws {
        var core = HarnessCore(mode: .direct, checkpointStore: nil, appendsCheckpoints: false)
        let base: TimeInterval = 1_700_000_000
        core.start(at: Date(timeIntervalSince1970: base))
        core.ingest(try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0, longitude: 121.0, timestamp: base + 1)))
        core.ingest(try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0001, longitude: 121.0, timestamp: base + 2)))

        core.pause(at: Date(timeIntervalSince1970: base + 3))
        let pausedSnapshot = core.metrics
        let announcementsAtPause = core.announcements.count

        core.ingest(try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.01, longitude: 121.0, timestamp: base + 4)))
        core.ingest(try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.02, longitude: 121.0, timestamp: base + 5)))

        XCTAssertEqual(core.metrics, pausedSnapshot, "暂停区间距离/耗时必须冻结")
        XCTAssertEqual(core.announcements.count, announcementsAtPause, "暂停区间播报队列不得增长")

        core.resume(at: Date(timeIntervalSince1970: base + 6))
        core.ingest(try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0201, longitude: 121.0, timestamp: base + 7)))
        core.ingest(try XCTUnwrap(HarnessTestSupport.sample(latitude: 31.0202, longitude: 121.0, timestamp: base + 8)))

        // 跨暂停的空档（约 1.2 km）不计入距离，只累计恢复后的锚点位移。
        let stepMeters = GeoDistance.meters(
            latitude1: 31.0, longitude1: 121.0,
            latitude2: 31.0001, longitude2: 121.0
        )
        XCTAssertEqual(core.metrics.distance.meters, stepMeters * 2, accuracy: 0.5)
        XCTAssertEqual(core.metrics.elapsed, 3, accuracy: 0.001)
        XCTAssertTrue(core.announcements.isEmpty)
    }

    func testFinishStopsProcessingAndIgnoresRemainingLines() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let base: TimeInterval = 1_700_000_000
        let lines = [
            "{\"type\":\"start\",\"timestamp\":\(base)}",
            HarnessTestSupport.sampleLine(latitude: 31.0, longitude: 121.0, timestamp: base + 1),
            HarnessTestSupport.sampleLine(latitude: 31.0001, longitude: 121.0, timestamp: base + 2),
            "{\"type\":\"finish\",\"timestamp\":\(base + 3)}",
            HarnessTestSupport.sampleLine(latitude: 31.2, longitude: 121.0, timestamp: base + 4),
        ]
        let streamURL = directory.appendingPathComponent("stream.jsonl")
        try HarnessTestSupport.writeStream(lines, to: streamURL)
        let statusURL = directory.appendingPathComponent("status.json")

        let status = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: statusURL,
                checkpointURL: directory.appendingPathComponent("checkpoint.jsonl"),
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()

        XCTAssertEqual(status.state, "finished")
        XCTAssertNotNil(status.finishedAt)
        XCTAssertEqual(status.rawSamples.count, 2, "finish 之后的采样行必须被忽略")
        let expectedMeters = GeoDistance.meters(latitude1: 31.0, longitude1: 121.0, latitude2: 31.0001, longitude2: 121.0)
        XCTAssertEqual(status.actual.distanceMeters, expectedMeters, accuracy: 0.001)
    }

    func testInvalidStreamLineWritesStableErrorWithLineNumber() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let base: TimeInterval = 1_700_000_000
        let lines = [
            "{\"type\":\"start\",\"timestamp\":\(base)}",
            HarnessTestSupport.sampleLine(latitude: 31.0, longitude: 121.0, timestamp: base + 1),
            "这不是 JSON",
            HarnessTestSupport.sampleLine(latitude: 31.1, longitude: 121.0, timestamp: base + 2),
        ]
        let streamURL = directory.appendingPathComponent("stream.jsonl")
        try HarnessTestSupport.writeStream(lines, to: streamURL)
        let statusURL = directory.appendingPathComponent("status.json")

        let status = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: statusURL,
                checkpointURL: directory.appendingPathComponent("checkpoint.jsonl"),
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()

        XCTAssertEqual(status.error?.code, HarnessStreamParser.invalidLineCode)
        XCTAssertTrue(try XCTUnwrap(status.error?.message).contains("第 3 行"))
        XCTAssertEqual(status.rawSamples.count, 1)
        let object = try HarnessTestSupport.decodeJSONObject(at: statusURL)
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? String, "invalidStreamLine")
    }

    func testUnknownStreamTypeAndEmptyLines() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let base: TimeInterval = 1_700_000_000

        XCTAssertNil(try HarnessStreamParser.parse(line: "", lineNumber: 1))
        XCTAssertNil(try HarnessStreamParser.parse(line: "   \r", lineNumber: 2))

        let unknownLines = [
            "{\"type\":\"start\",\"timestamp\":\(base)}",
            "{\"type\":\"bogus\",\"timestamp\":\(base + 1)}",
        ]
        let streamURL = directory.appendingPathComponent("stream.jsonl")
        try HarnessTestSupport.writeStream(unknownLines, to: streamURL)
        let status = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: directory.appendingPathComponent("status.json"),
                checkpointURL: directory.appendingPathComponent("checkpoint.jsonl"),
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()
        XCTAssertEqual(status.error?.code, "invalidStreamLine")
        XCTAssertTrue(try XCTUnwrap(status.error?.message).contains("第 2 行"))
        XCTAssertTrue(try XCTUnwrap(status.error?.message).contains("bogus"))

        // 空行不产生错误，可正常跑到 finish。
        let withBlankLines = [
            "",
            "{\"type\":\"start\",\"timestamp\":\(base)}",
            "   ",
            HarnessTestSupport.sampleLine(latitude: 31.0, longitude: 121.0, timestamp: base + 1),
            HarnessTestSupport.sampleLine(latitude: 31.0001, longitude: 121.0, timestamp: base + 2),
            "",
            "{\"type\":\"finish\",\"timestamp\":\(base + 3)}",
        ]
        try HarnessTestSupport.writeStream(withBlankLines, to: streamURL)
        let clean = HarnessRunner(
            configuration: HarnessConfiguration(
                mode: .direct,
                statusURL: directory.appendingPathComponent("status-clean.json"),
                checkpointURL: directory.appendingPathComponent("checkpoint-clean.jsonl"),
                streamURL: streamURL,
                maxDurationSeconds: nil
            )
        ).run()
        XCTAssertNil(clean.error)
        XCTAssertEqual(clean.state, "finished")
        XCTAssertEqual(clean.rawSamples.count, 2)
    }

    // MARK: - ac-checkpoint-cadence

    func testCheckpointCadenceAppendsRealJSONLAndKeepsAnnouncedIndex() throws {
        let directory = try HarnessTestSupport.makeTemporaryDirectory()
        defer { HarnessTestSupport.removeTemporaryDirectory(directory) }
        let checkpointURL = directory.appendingPathComponent("checkpoint.jsonl")
        let store = RunCheckpointStore(fileURL: checkpointURL)
        var core = HarnessCore(mode: .direct, checkpointStore: store, appendsCheckpoints: true)
        let base: TimeInterval = 1_700_000_000

        core.start(at: Date(timeIntervalSince1970: base))
        XCTAssertEqual(try store.loadAll().count, 1, "每次状态迁移都要落一行")

        func sample(step: Int) throws -> RunSample {
            try XCTUnwrap(
                HarnessTestSupport.sample(
                    latitude: 31.0 + Double(step) * 100.0 / HarnessTestSupport.metersPerDegreeLatitude,
                    longitude: 121.0,
                    timestamp: base + Double(step) * 10
                )
            )
        }

        for step in 0...8 {
            core.ingest(try sample(step: step))
        }
        XCTAssertEqual(try store.loadAll().count, 1, "未到 10 个被接受采样且未完成分段前不落盘")

        core.ingest(try sample(step: 9))
        XCTAssertEqual(try store.loadAll().count, 2, "第 10 个被接受采样触发一次 checkpoint")

        core.ingest(try sample(step: 10))
        XCTAssertEqual(try store.loadAll().count, 3, "新增已完成分段再落一行")

        core.pause(at: Date(timeIntervalSince1970: base + 200))
        XCTAssertEqual(try store.loadAll().count, 4)

        let latest = try XCTUnwrap(store.loadLatest())
        XCTAssertEqual(latest.state, .paused)
        XCTAssertEqual(latest.splits.count, 1)
        XCTAssertEqual(latest.announcedSplitIndex, 1)
        XCTAssertNotNil(latest.lastSample)
        XCTAssertEqual(latest.completedDistance.meters, 1_000, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(latest.announcedSplitIndex),
            core.announcements.map(\.splitIndex).max() ?? 0
        )
    }

    private func makeStream(
        points: [(timestamp: Date, latitude: Double, longitude: Double)],
        in directory: URL,
        name: String
    ) throws -> URL {
        var lines = ["{\"type\":\"start\",\"timestamp\":\(points[0].timestamp.timeIntervalSince1970 - 1)}"]
        lines.append(contentsOf: points.map { point in
            HarnessTestSupport.sampleLine(
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: point.timestamp.timeIntervalSince1970
            )
        })
        lines.append("{\"type\":\"finish\",\"timestamp\":\(points[points.count - 1].timestamp.timeIntervalSince1970 + 1)}")
        let url = directory.appendingPathComponent(name)
        try HarnessTestSupport.writeStream(lines, to: url)
        return url
    }
}
