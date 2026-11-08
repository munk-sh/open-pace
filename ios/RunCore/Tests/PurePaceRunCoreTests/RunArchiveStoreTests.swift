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
