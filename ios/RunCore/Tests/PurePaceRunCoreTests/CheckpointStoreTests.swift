import XCTest
@testable import PurePaceRunCore

final class CheckpointStoreTests: XCTestCase {
    private var directory: URL!

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

    private var fileURL: URL {
        directory.appendingPathComponent("checkpoints/session.jsonl")
    }

    private func makeCheckpoint(
        state: RunSessionState = .running,
        meters: Double = 1000,
        elapsed: TimeInterval = 360,
        splits: [RunSplit] = [],
        recordedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RunCheckpoint {
        RunCheckpoint(
            state: state,
            completedDistance: RunDistance(meters: meters)!,
            elapsed: elapsed,
            splits: splits,
            recordedAt: recordedAt
        )!
    }

    private func encodedLine(_ checkpoint: RunCheckpoint) throws -> String {
        let data = try JSONEncoder().encode(checkpoint)
        guard let line = String(data: data, encoding: .utf8) else {
            throw RunCoreError.corruptedCheckpoint("无法生成测试 JSON")
        }
        return line
    }

    private func writeRaw(_ contents: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }

    private func lines(of data: Data) -> [String] {
        data.split(separator: 0x0A).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - checkpoint 值校验

    func testCheckpointInitRejectsInvalidFields() {
        let distance = RunDistance(meters: 100)!
        let split = RunSplit(index: 1, distance: distance, duration: 60)!
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(RunCheckpoint(formatVersion: 2, state: .running, completedDistance: distance, elapsed: 1, splits: [], recordedAt: recordedAt))
        XCTAssertNil(RunCheckpoint(state: .running, completedDistance: distance, elapsed: -1, splits: [], recordedAt: recordedAt))
        XCTAssertNil(RunCheckpoint(state: .running, completedDistance: distance, elapsed: .nan, splits: [], recordedAt: recordedAt))
        XCTAssertNil(RunCheckpoint(state: .running, completedDistance: distance, elapsed: 1, splits: [], recordedAt: .distantPast))
        XCTAssertNil(RunCheckpoint(state: .running, completedDistance: distance, elapsed: 1, splits: [], recordedAt: .distantFuture))
        XCTAssertNil(RunCheckpoint(state: .running, completedDistance: distance, elapsed: 1, splits: [split, split], recordedAt: recordedAt))
        XCTAssertNil(RunCheckpoint(state: .ready, completedDistance: distance, elapsed: 1, splits: [], recordedAt: recordedAt))
        XCTAssertNil(RunCheckpoint(state: .ready, completedDistance: RunDistance(meters: 0)!, elapsed: 1, splits: [split], recordedAt: recordedAt))
        XCTAssertNotNil(RunCheckpoint(state: .ready, completedDistance: RunDistance(meters: 0)!, elapsed: 0, splits: [], recordedAt: recordedAt))
    }

    // MARK: - 真实文件追加

    func testAppendWritesOneJSONLinePerCallAndNeverRewritesHistory() throws {
        let store = RunCheckpointStore(fileURL: fileURL)
        let first = makeCheckpoint(meters: 500, elapsed: 120)
        try store.append(first)
        let firstBytes = try Data(contentsOf: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(firstBytes.last, 0x0A)
        XCTAssertEqual(lines(of: firstBytes).count, 1)

        let second = makeCheckpoint(meters: 1000, elapsed: 300)
        try store.append(second)
        let combined = try Data(contentsOf: fileURL)
        XCTAssertTrue(combined.prefix(firstBytes.count).elementsEqual(firstBytes), "旧行字节前缀必须不变")
        let written = lines(of: combined)
        XCTAssertEqual(written.count, 2)
        for line in written {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    func testRoundtripWithNewStoreInstance() throws {
        let first = makeCheckpoint(meters: 800, elapsed: 240)
        let split1 = RunSplit(index: 1, distance: RunDistance(meters: 1000)!, duration: 300)!
        let split2 = RunSplit(index: 2, distance: RunDistance(meters: 1000)!, duration: 310)!
        let last = makeCheckpoint(state: .paused, meters: 2000, elapsed: 610, splits: [split1, split2])
        let writer = RunCheckpointStore(fileURL: fileURL)
        try writer.append(first)
        try writer.append(last)

        let reader = RunCheckpointStore(fileURL: fileURL)
        XCTAssertEqual(try reader.loadLatest(), last)
        XCTAssertEqual(try reader.loadAll(), [first, last])
    }

    func testMissingAndEmptyFileReturnEmptyResults() throws {
        let store = RunCheckpointStore(fileURL: fileURL)
        XCTAssertNil(try store.loadLatest())
        XCTAssertEqual(try store.loadAll(), [])

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        XCTAssertNil(try store.loadLatest())
        XCTAssertEqual(try store.loadAll(), [])
    }

    // MARK: - 尾行容错

    func testPartialTailIsSilentlyDiscarded() throws {
        let first = makeCheckpoint(meters: 1000)
        let second = makeCheckpoint(meters: 2000, elapsed: 700)
        let firstLine = try encodedLine(first)
        let secondLine = try encodedLine(second)
        try writeRaw(firstLine + "\n" + secondLine + "\n" + "{\"formatVersion\":1,\"state\":\"run")

        let store = RunCheckpointStore(fileURL: fileURL)
        XCTAssertEqual(try store.loadLatest(), second)
        XCTAssertEqual(try store.loadAll(), [first, second])
    }

    func testCompleteButInvalidTailIsSilentlyDiscarded() throws {
        let valid = makeCheckpoint(meters: 1000)
        let invalidTails = [
            "{\"formatVersion\":1,\"state\":\"running\",\"completedDistance\":-5,\"elapsed\":10,\"splits\":[],\"recordedAt\":1700000000}",
            "{\"formatVersion\":9,\"state\":\"running\",\"completedDistance\":5,\"elapsed\":10,\"splits\":[],\"recordedAt\":1700000000}",
            "{\"formatVersion\":1,\"state\":\"running\",\"completedDistance\":5,\"elapsed\":-10,\"splits\":[],\"recordedAt\":1700000000}",
            "{\"formatVersion\":1,\"state\":\"running\",\"completedDistance\":5,\"elapsed\":10,\"splits\":[{\"index\":2,\"distance\":5,\"duration\":10}],\"recordedAt\":1700000000}"
        ]
        let validLine = try encodedLine(valid)
        for invalidTail in invalidTails {
            try writeRaw(validLine + "\n" + invalidTail + "\n")
            let store = RunCheckpointStore(fileURL: fileURL)
            XCTAssertEqual(try store.loadLatest(), valid)
            XCTAssertEqual(try store.loadAll(), [valid])
        }
    }

    func testMiddleCorruptionThrows() throws {
        let first = makeCheckpoint(meters: 1000)
        let last = makeCheckpoint(meters: 3000, elapsed: 900)
        let firstLine = try encodedLine(first)
        let lastLine = try encodedLine(last)
        try writeRaw(firstLine + "\n" + "not-json" + "\n" + lastLine + "\n")

        let store = RunCheckpointStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.loadAll()) { error in
            guard case let RunCoreError.corruptedCheckpoint(reason) = error else {
                return XCTFail("期望 corruptedCheckpoint，实际 \(error)")
            }
            XCTAssertFalse(reason.isEmpty)
        }
        XCTAssertThrowsError(try store.loadLatest())
    }

    // MARK: - 目录与重置

    func testAppendCreatesDirectoryAndResetIsIdempotent() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
        let store = RunCheckpointStore(fileURL: fileURL)
        try store.append(makeCheckpoint())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNoThrow(try store.reset())
        XCTAssertNil(try store.loadLatest())
    }

    // MARK: - 重启继续

    func testRestartKeepsCompletedSplitsAndDistance() throws {
        let split1 = RunSplit(index: 1, distance: RunDistance(meters: 1000)!, duration: 305)!
        let split2 = RunSplit(index: 2, distance: RunDistance(meters: 1000)!, duration: 315)!
        let written = makeCheckpoint(state: .running, meters: 2000, elapsed: 620, splits: [split1, split2])
        try RunCheckpointStore(fileURL: fileURL).append(written)

        let restartedStore = RunCheckpointStore(fileURL: fileURL)
        let restored = try XCTUnwrap(try restartedStore.loadLatest())
        let machine = RunSessionMachine(restoring: restored)
        XCTAssertEqual(machine.state, .paused)
        XCTAssertEqual(restored.splits.count, written.splits.count)
        for (actual, expected) in zip(restored.splits, written.splits) {
            XCTAssertEqual(actual.index, expected.index)
            XCTAssertEqual(actual.distance, expected.distance)
            XCTAssertEqual(actual.duration, expected.duration)
        }
        XCTAssertEqual(restored.completedDistance, written.completedDistance)
        XCTAssertEqual(restored.splits, [split1, split2])
    }
}
