import Foundation
import XCTest
@testable import PurePaceRunCore

final class RunArchiveStoreTests: XCTestCase {
    private var directory: URL!

    private let baseTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        super.tearDown()
    }

    private func makeSample(index: Int) -> RunSample {
        RunSample(
            latitude: 30.0 + Double(index) * 0.001,
            longitude: 120.0 + Double(index) * 0.001,
            altitude: 10.0 + Double(index),
            timestamp: baseTimestamp.addingTimeInterval(Double(index) * 10),
            heartRate: 120 + index,
            cadence: 80 + index
        )!
    }

    private func makeRecord(
        id: UUID = UUID(),
        startedAt: Date,
        meters: Double = 2000,
        samples: [RunSample]? = nil
    ) -> RunRecord {
        RunRecord(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distance: RunDistance(meters: meters)!,
            activeDuration: 600,
            splits: [RunSplit(index: 1, distance: RunDistance(meters: 1000)!, duration: 300)!],
            samples: samples ?? [makeSample(index: 0), makeSample(index: 1)]
        )!
    }

    private func jsonFileNames() throws -> [String] {
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return entries.filter { $0.hasSuffix(".json") }.sorted()
    }

    private func writeRaw(_ contents: String, named name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func writeJSON(_ object: [String: Any], named name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func jsonObject(of record: RunRecord) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunArchiveError.invalidRecord("无法生成测试 JSON 对象")
        }
        return object
    }

    // MARK: - 真实文件 round-trip

    func testSaveAndListRoundTripThroughNewStoreInstance() throws {
        let record = makeRecord(startedAt: baseTimestamp)
        let store = RunArchiveStore(directoryURL: directory)
        let url = try store.save(record)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertEqual(try jsonFileNames().count, 1)

        let reread = try RunArchiveStore(directoryURL: directory).list()
        XCTAssertEqual(reread, [record])
    }

    func testSameStartedAtDifferentIDsProduceTwoFiles() throws {
        let first = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: baseTimestamp
        )
        let second = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            startedAt: baseTimestamp
        )
        let store = RunArchiveStore(directoryURL: directory)
        let firstURL = try store.save(first)
        let secondURL = try store.save(second)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try jsonFileNames().count, 2)
        let listed = try store.list()
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(Set(listed.map(\.id)), Set([first.id, second.id]))
    }

    func testSaveNeverOverwritesSameRecord() throws {
        let record = makeRecord(startedAt: baseTimestamp)
        let store = RunArchiveStore(directoryURL: directory)
        let firstURL = try store.save(record)
        let secondURL = try store.save(record)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try jsonFileNames().count, 2)
        let listed = try store.list()
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed[0], record)
        XCTAssertEqual(listed[1], record)
    }

    // MARK: - 排序

    func testListSortsByStartedAtDescendingThenIDAscending() throws {
        let tieEarlyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let tieLateID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tieEarly = makeRecord(id: tieEarlyID, startedAt: baseTimestamp.addingTimeInterval(100))
        let tieLate = makeRecord(id: tieLateID, startedAt: baseTimestamp.addingTimeInterval(100))
        let latest = makeRecord(startedAt: baseTimestamp.addingTimeInterval(300))

        let store = RunArchiveStore(directoryURL: directory)
        _ = try store.save(tieEarly)
        _ = try store.save(latest)
        _ = try store.save(tieLate)

        let expectedIDs = [latest.id, tieLate.id, tieEarly.id]
        XCTAssertEqual(try store.list().map(\.id), expectedIDs)
        XCTAssertEqual(try store.list().map(\.id), expectedIDs)
    }

    // MARK: - 损坏条目跳过

    func testListSkipsCorruptAndInvalidEntries() throws {
        let first = makeRecord(startedAt: baseTimestamp.addingTimeInterval(100))
        let second = makeRecord(startedAt: baseTimestamp.addingTimeInterval(200))
        let store = RunArchiveStore(directoryURL: directory)
        _ = try store.save(first)
        _ = try store.save(second)

        try writeRaw("this is not json", named: "garbage.json")

        var unknownVersion = try jsonObject(of: first)
        unknownVersion["formatVersion"] = 2
        try writeJSON(unknownVersion, named: "unknown-version.json")

        var missingField = try jsonObject(of: first)
        missingField.removeValue(forKey: "samples")
        try writeJSON(missingField, named: "missing-field.json")

        var badRange = try jsonObject(of: first)
        badRange["endedAt"] = baseTimestamp.timeIntervalSince1970 - 1
        try writeJSON(badRange, named: "bad-range.json")

        var badSplits = try jsonObject(of: first)
        badSplits["splits"] = [["index": 2, "distance": 1000.0, "duration": 300.0]]
        try writeJSON(badSplits, named: "bad-splits.json")

        let listed = try store.list()
        XCTAssertEqual(listed.map(\.id), [second.id, first.id])
    }

    // MARK: - 缺失目录

    func testListReturnsEmptyForMissingDirectoryWithoutCreatingIt() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let store = RunArchiveStore(directoryURL: directory)
        XCTAssertEqual(try store.list(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    // MARK: - 原子写

    func testSaveLeavesOnlyFinalRecordFile() throws {
        let store = RunArchiveStore(directoryURL: directory)
        _ = try store.save(makeRecord(startedAt: baseTimestamp))

        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].hasSuffix(".json"), true)
        XCTAssertFalse(entries[0].contains(".tmp"))
    }

    func testSaveFailsCleanlyWhenDirectoryPathIsOccupiedByFile() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockedURL = directory.appendingPathComponent("occupied")
        try Data("occupied".utf8).write(to: blockedURL)

        let store = RunArchiveStore(directoryURL: blockedURL)
        XCTAssertThrowsError(try store.save(makeRecord(startedAt: baseTimestamp))) { error in
            guard let archiveError = error as? RunArchiveError else {
                XCTFail("expected RunArchiveError, got \(error)")
                return
            }
            if case .ioFailure = archiveError {
            } else {
                XCTFail("expected ioFailure, got \(archiveError)")
            }
        }

        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(entries, ["occupied"])
        XCTAssertEqual(try String(contentsOf: blockedURL, encoding: .utf8), "occupied")
    }

    // MARK: - 忽略非记录条目

    func testListIgnoresDirectoriesTemporaryAndForeignFiles() throws {
        let record = makeRecord(startedAt: baseTimestamp)
        let store = RunArchiveStore(directoryURL: directory)
        _ = try store.save(record)

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("fake.json"),
            withIntermediateDirectories: true
        )
        try Data("temp".utf8).write(to: directory.appendingPathComponent("record.tmp"))
        try Data("text".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let listed = try store.list()
        XCTAssertEqual(listed, [record])
    }

    // MARK: - 轻量索引（ac-store-index-no-sample-decode）

    func testListSummariesMatchesListOrderingAndFields() throws {
        let store = RunArchiveStore(directoryURL: directory)
        let early = makeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, startedAt: baseTimestamp)
        let late = makeRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, startedAt: baseTimestamp.addingTimeInterval(60))
        try store.save(early)
        try store.save(late)

        let full = try store.list()
        let summaries = try store.listSummaries()
        XCTAssertEqual(summaries.map(\.id), full.map(\.id), "索引排序必须与 list() 一致：startedAt 降序 + id 升序")
        XCTAssertEqual(summaries.map(\.startedAt), full.map(\.startedAt))
        XCTAssertEqual(summaries.map(\.distance), full.map(\.distance))
        XCTAssertEqual(summaries.map(\.activeDuration), full.map(\.activeDuration))
        XCTAssertTrue(summaries.allSatisfy(\.hasTrack))
    }

    func testListSummariesFormsRowEvenWhenSamplesAreHugeOrMalformed() throws {
        // 采样数组畸形 + 超大：list() 会跳过，但列表索引必须照常成行（不解码 samples）。
        let id = UUID()
        let encoded = try JSONEncoder().encode(makeRecord(id: id, startedAt: baseTimestamp))
        let json = String(decoding: encoded, as: UTF8.self)
        guard let marker = json.range(of: "\"samples\":") else {
            return XCTFail("归档 JSON 必须包含 samples 键")
        }
        var valueStart = marker.upperBound
        while valueStart < json.endIndex, json[valueStart] == " " { valueStart = json.index(after: valueStart) }
        guard json[valueStart] == "[" else {
            return XCTFail("samples 必须是数组")
        }
        var depth = 0
        var scan = valueStart
        repeat {
            if json[scan] == "[" { depth += 1 }
            if json[scan] == "]" { depth -= 1 }
            scan = json.index(after: scan)
        } while depth > 0 && scan < json.endIndex
        let garbage = String(repeating: "x", count: 400_000)
        // 只把 samples 的数组值换成超大畸形字符串，其余键保持原样。
        let malformed = String(json[..<valueStart]) + "\"" + garbage + "\"" + String(json[scan...])
        try writeRaw(malformed, named: "huge-\(id.uuidString).json")

        XCTAssertEqual(try RunArchiveStore(directoryURL: directory).list(), [], "list() 仍按旧语义跳过坏文件")
        let summaries = try RunArchiveStore(directoryURL: directory).listSummaries()
        XCTAssertEqual(summaries.map(\.id), [id], "samples 畸形/超大时列表仍须成行")
    }

    func testListSummariesReportsNoTrackForEmptySamples() throws {
        let record = makeRecord(startedAt: baseTimestamp, samples: [])
        try RunArchiveStore(directoryURL: directory).save(record)
        let summaries = try RunArchiveStore(directoryURL: directory).listSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.hasTrack, false)
    }

    func testListSummariesSkipsInvalidMetadata() throws {
        try writeRaw("{ not json", named: "broken.json")
        let valid = makeRecord(startedAt: baseTimestamp)
        try RunArchiveStore(directoryURL: directory).save(valid)
        let summaries = try RunArchiveStore(directoryURL: directory).listSummaries()
        XCTAssertEqual(summaries.map(\.id), [valid.id], "元数据坏文件必须跳过")
    }

    func testRecordWithIDReturnsFullRecordIncludingSamples() throws {
        let record = makeRecord(startedAt: baseTimestamp)
        try RunArchiveStore(directoryURL: directory).save(record)
        let loaded = try XCTUnwrap(RunArchiveStore(directoryURL: directory).record(withID: record.id))
        XCTAssertEqual(loaded, record)
        XCTAssertNil(try RunArchiveStore(directoryURL: directory).record(withID: UUID()))
    }

    // MARK: - 错误描述

    func testRunArchiveErrorDescriptionsAreNonEmptyAndDistinct() {
        let descriptions = [
            RunArchiveError.invalidRecord("x").description,
            RunArchiveError.emptySamples.description,
            RunArchiveError.ioFailure("y").description
        ]
        XCTAssertTrue(descriptions.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(descriptions).count, descriptions.count)
    }
}
