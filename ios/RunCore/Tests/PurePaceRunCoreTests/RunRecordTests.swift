import Foundation
import XCTest
@testable import PurePaceRunCore

final class RunRecordTests: XCTestCase {
    private let baseTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private var startDate: Date {
        baseTimestamp
    }

    private func makeSample(
        index: Int,
        altitude: Double? = 10.5,
        heartRate: Int? = 120,
        cadence: Int? = 80
    ) -> RunSample {
        RunSample(
            latitude: 30.0 + Double(index) * 0.001,
            longitude: 120.0 + Double(index) * 0.001,
            altitude: altitude,
            timestamp: baseTimestamp.addingTimeInterval(Double(index) * 10),
            heartRate: heartRate,
            cadence: cadence
        )!
    }

    private func makeSplit(index: Int) -> RunSplit {
        RunSplit(index: index, distance: RunDistance(meters: 1000)!, duration: 300)!
    }

    private func makeRecord(
        formatVersion: Int = RunRecord.currentFormatVersion,
        id: UUID = UUID(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        meters: Double = 2000,
        activeDuration: TimeInterval = 600,
        splits: [RunSplit]? = nil,
        samples: [RunSample]? = nil
    ) -> RunRecord? {
        let start = startedAt ?? baseTimestamp
        return RunRecord(
            formatVersion: formatVersion,
            id: id,
            startedAt: start,
            endedAt: endedAt ?? start.addingTimeInterval(600),
            distance: RunDistance(meters: meters)!,
            activeDuration: activeDuration,
            splits: splits ?? [makeSplit(index: 1), makeSplit(index: 2)],
            samples: samples ?? [makeSample(index: 0), makeSample(index: 1), makeSample(index: 2)]
        )
    }

    private func decodeError(from object: [String: Any]) -> Error? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        do {
            _ = try JSONDecoder().decode(RunRecord.self, from: data)
            return nil
        } catch {
            return error
        }
    }

    private func jsonObject(of record: RunRecord) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunArchiveError.invalidRecord("无法生成测试 JSON 对象")
        }
        return object
    }

    // MARK: - 构造校验

    func testRecordInitAcceptsValidFields() throws {
        let id = UUID()
        let record = try XCTUnwrap(makeRecord(id: id))
        XCTAssertEqual(record.formatVersion, 1)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.startedAt, baseTimestamp)
        XCTAssertEqual(record.endedAt, baseTimestamp.addingTimeInterval(600))
        XCTAssertEqual(record.distance.meters, 2000)
        XCTAssertEqual(record.activeDuration, 600)
        XCTAssertEqual(record.splits.map(\.index), [1, 2])
        XCTAssertEqual(record.samples.count, 3)
    }

    func testRecordInitRejectsUnknownFormatVersion() {
        XCTAssertNil(makeRecord(formatVersion: 2))
        XCTAssertNil(makeRecord(formatVersion: 0))
    }

    func testRecordInitRejectsEndBeforeStart() {
        XCTAssertNil(makeRecord(endedAt: baseTimestamp.addingTimeInterval(-1)))
        XCTAssertNotNil(makeRecord(endedAt: baseTimestamp))
    }

    func testRecordInitRejectsInvalidActiveDuration() {
        XCTAssertNil(makeRecord(activeDuration: -1))
        XCTAssertNil(makeRecord(activeDuration: .nan))
        XCTAssertNil(makeRecord(activeDuration: .infinity))
        XCTAssertNotNil(makeRecord(activeDuration: 0))
    }

    func testRecordInitRejectsNonContiguousSplitIndices() {
        XCTAssertNil(makeRecord(splits: [makeSplit(index: 2)]))
        XCTAssertNil(makeRecord(splits: [makeSplit(index: 1), makeSplit(index: 3)]))
        XCTAssertNil(makeRecord(splits: [makeSplit(index: 1), makeSplit(index: 1)]))
        XCTAssertNotNil(makeRecord(splits: []))
    }

    func testRecordInitRejectsDecreasingSampleTimestamps() {
        let first = makeSample(index: 1)
        let second = makeSample(index: 0)
        XCTAssertNil(makeRecord(samples: [first, second]))
        XCTAssertNotNil(makeRecord(samples: []))
    }

    // MARK: - Codable

    func testCodableRoundTripPreservesEveryField() throws {
        let samples = [
            makeSample(index: 0, altitude: 12.25, heartRate: 112, cadence: 82),
            makeSample(index: 1, altitude: nil, heartRate: nil, cadence: nil),
            makeSample(index: 2, altitude: 13.5, heartRate: 130, cadence: 88)
        ]
        let record = try XCTUnwrap(makeRecord(samples: samples))
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(RunRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.samples, samples)
        XCTAssertNil(decoded.samples[1].altitude)
        XCTAssertNil(decoded.samples[1].heartRate)
        XCTAssertNil(decoded.samples[1].cadence)
    }

    func testCodableEncodesOnlyRawScalars() throws {
        let record = try XCTUnwrap(makeRecord(samples: [makeSample(index: 0)]))
        let object = try jsonObject(of: record)
        XCTAssertNotNil(object["formatVersion"] as? Int)
        XCTAssertNotNil(object["id"] as? String)
        XCTAssertNotNil(object["startedAt"] as? Double)
        XCTAssertNotNil(object["endedAt"] as? Double)
        XCTAssertNotNil(object["distance"] as? Double)
        XCTAssertNotNil(object["activeDuration"] as? Double)
        let splits = try XCTUnwrap(object["splits"] as? [[String: Any]])
        XCTAssertEqual(splits.count, 2)
        XCTAssertNotNil(splits[0]["index"] as? Int)
        XCTAssertNotNil(splits[0]["distance"] as? Double)
        XCTAssertNotNil(splits[0]["duration"] as? Double)
        let samples = try XCTUnwrap(object["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 1)
        XCTAssertNotNil(samples[0]["latitude"] as? Double)
        XCTAssertNotNil(samples[0]["longitude"] as? Double)
        XCTAssertNotNil(samples[0]["timestamp"] as? Double)
    }

    func testDecodeRejectsUnknownVersionAndInvalidFields() throws {
        let valid = try XCTUnwrap(makeRecord(samples: [makeSample(index: 0), makeSample(index: 1)]))
        var object = try jsonObject(of: valid)

        object["formatVersion"] = 2
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object["endedAt"] = baseTimestamp.addingTimeInterval(-1).timeIntervalSince1970
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object["distance"] = -5.0
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object["activeDuration"] = -1.0
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object["splits"] = [["index": 2, "distance": 1000.0, "duration": 300.0]]
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object["samples"] = [
            ["latitude": 30.0, "longitude": 120.0, "timestamp": baseTimestamp.timeIntervalSince1970],
            ["latitude": 30.001, "longitude": 120.001, "timestamp": baseTimestamp.timeIntervalSince1970 - 1]
        ]
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object["samples"] = [["latitude": 91.0, "longitude": 120.0, "timestamp": baseTimestamp.timeIntervalSince1970]]
        XCTAssertNotNil(decodeError(from: object))

        object = try jsonObject(of: valid)
        object.removeValue(forKey: "samples")
        XCTAssertNotNil(decodeError(from: object))

        XCTAssertNil(decodeError(from: try jsonObject(of: valid)))
    }

    // MARK: - Sendable 契约

    private func assertSendable<T: Sendable>(_: T.Type) {}

    func testPublicTypesAreSendable() {
        assertSendable(RunRecord.self)
        assertSendable(RunArchiveStore.self)
        assertSendable(RunGPXExporter.self)
        assertSendable(RunArchiveError.self)
    }
}
