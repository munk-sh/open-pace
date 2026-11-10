import Foundation
import XCTest
@testable import PurePaceRunCore

final class GPXCodecTests: XCTestCase {
    private let baseTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private let gpxHeader = """
    <gpx version="1.1" creator="unit" xmlns="http://www.topografix.com/GPX/1/1" \
    xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
    """

    // MARK: - Helpers

    private func makeSample(
        index: Int,
        altitude: Double? = 12.5,
        heartRate: Int? = 120,
        cadence: Int? = 80
    ) -> RunSample {
        RunSample(
            latitude: 30.0 + Double(index) * 0.001,
            longitude: 120.0 + Double(index) * 0.001,
            altitude: altitude,
            timestamp: baseTimestamp.addingTimeInterval(Double(index) * 60),
            heartRate: heartRate,
            cadence: cadence
        )!
    }

    private func makeTrack(points: [RunSample]) -> GPXTrack {
        GPXTrack(
            name: "unit run",
            description: "synthetic unit track",
            createdAt: baseTimestamp,
            activityType: "running",
            points: points
        )!
    }

    private func decodeError(_ document: String) -> GPXCodecError? {
        do {
            _ = try GPXCodec.decode(Data(document.utf8))
            return nil
        } catch let error as GPXCodecError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - Round trip through a real file

    func testRoundTripThroughRealFilePreservesEveryPoint() throws {
        let points = [
            makeSample(index: 0, altitude: 12.0, heartRate: 112, cadence: 82),
            makeSample(index: 1, altitude: 12.5, heartRate: 128, cadence: 84),
            makeSample(index: 2, altitude: nil, heartRate: nil, cadence: nil)
        ]
        let track = makeTrack(points: points)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpx-codec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("run.gpx")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try GPXCodec.write(track, to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let decoded = try GPXCodec.read(from: fileURL)
        XCTAssertEqual(decoded.points.count, points.count)
        for (expected, actual) in zip(points, decoded.points) {
            XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 1e-9)
            XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 1e-9)
            XCTAssertEqual(actual.altitude, expected.altitude)
            XCTAssertEqual(actual.timestamp, expected.timestamp)
            XCTAssertEqual(actual.heartRate, expected.heartRate)
            XCTAssertEqual(actual.cadence, expected.cadence)
        }

        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Namespaces and extensions

    func testEncodeUsesGPX11NamespacesAndTrackPointExtension() throws {
        let track = makeTrack(points: [makeSample(index: 0)])
        let document = try GPXCodec.encode(track)

        XCTAssertTrue(document.contains("version=\"1.1\""))
        XCTAssertTrue(document.contains("xmlns=\"http://www.topografix.com/GPX/1/1\""))
        XCTAssertTrue(
            document.contains(
                "xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\""
            )
        )

        let extensionStart = try XCTUnwrap(document.range(of: "<gpxtpx:TrackPointExtension>"))
        let heartRateStart = try XCTUnwrap(document.range(of: "<gpxtpx:hr>"))
        let cadenceStart = try XCTUnwrap(document.range(of: "<gpxtpx:cad>"))
        XCTAssertLessThan(extensionStart.lowerBound, heartRateStart.lowerBound)
        XCTAssertLessThan(heartRateStart.lowerBound, cadenceStart.lowerBound)

        XCTAssertTrue(document.contains("lat=\"30.000000\""))
        XCTAssertTrue(document.contains("lon=\"120.000000\""))
        XCTAssertEqual(try GPXCodec.encode(track), document)

        let decoded = try GPXCodec.decode(Data(document.utf8))
        XCTAssertEqual(decoded.points, track.points)
    }

    // MARK: - Optional fields

    func testOptionalFieldsAreOmittedButStillDecodable() throws {
        let point = makeSample(index: 0, altitude: nil, heartRate: nil, cadence: nil)
        let track = makeTrack(points: [point])
        let document = try GPXCodec.encode(track)

        XCTAssertFalse(document.contains("<ele>"))
        XCTAssertFalse(document.contains("<gpxtpx:hr>"))
        XCTAssertFalse(document.contains("<gpxtpx:cad>"))
        XCTAssertFalse(document.contains("<extensions>"))

        let decoded = try GPXCodec.decode(Data(document.utf8))
        XCTAssertEqual(decoded.points, track.points)
        XCTAssertNil(decoded.points[0].altitude)
        XCTAssertNil(decoded.points[0].heartRate)
        XCTAssertNil(decoded.points[0].cadence)
    }

    // MARK: - Inline fixture mirroring the shared 4-point sample

    /// 与共享 GPX 夹具（仓库 `shared` 目录下 4 点样例）**同值**的内联夹具（4 个 trkpt）。
    /// RunCore 测试不得跨目录引用夹具路径：本层自带自包含夹具，
    /// 跨目录逐字段比对由 `scripts/check-gpx-export.sh` 负责。
    private struct InlinePoint {
        let lat: String
        let lon: String
        let ele: String
        let time: String
        let heartRate: Int
        let cadence: Int
    }

    private static let inlineFixturePoints: [InlinePoint] = [
        InlinePoint(
            lat: "31.230400", lon: "121.473700", ele: "12.0",
            time: "2026-01-01T08:00:00Z", heartRate: 112, cadence: 82
        ),
        InlinePoint(
            lat: "31.232200", lon: "121.474900", ele: "12.5",
            time: "2026-01-01T08:01:00Z", heartRate: 128, cadence: 84
        ),
        InlinePoint(
            lat: "31.234000", lon: "121.476100", ele: "13.2",
            time: "2026-01-01T08:02:00Z", heartRate: 141, cadence: 86
        ),
        InlinePoint(
            lat: "31.235800", lon: "121.477300", ele: "13.8",
            time: "2026-01-01T08:03:00Z", heartRate: 147, cadence: 85
        )
    ]

    private func inlineTimestamp(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    /// 同一条内联夹具的两个反例入口：换命名空间、或删掉某个 trkpt 的 `<ele>`。
    private func inlineFixture(
        namespace: String = "http://www.topografix.com/GPX/1/1",
        omittingElevationAt omittedIndex: Int? = nil
    ) -> String {
        let points = Self.inlineFixturePoints.enumerated().map { index, point -> String in
            let elevation = index == omittedIndex ? "" : "<ele>\(point.ele)</ele>"
            return """
                  <trkpt lat="\(point.lat)" lon="\(point.lon)">\(elevation)<time>\(point.time)</time>\
                <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(point.heartRate)</gpxtpx:hr>\
                <gpxtpx:cad>\(point.cadence)</gpxtpx:cad></gpxtpx:TrackPointExtension></extensions></trkpt>
                """
        }.joined(separator: "\n")
        return """
        <gpx version="1.1" creator="inline" xmlns="\(namespace)" \
        xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <trk><name>synthetic run</name><type>running</type><trkseg>
        \(points)
          </trkseg></trk>
        </gpx>
        """
    }

    func testInlineFixtureDecodesEveryFieldOfEveryPoint() throws {
        let track = try GPXCodec.decode(Data(inlineFixture().utf8))
        XCTAssertEqual(track.points.count, 4)

        for (point, expected) in zip(track.points, Self.inlineFixturePoints) {
            XCTAssertEqual(point.latitude, Double(expected.lat)!, accuracy: 1e-9)
            XCTAssertEqual(point.longitude, Double(expected.lon)!, accuracy: 1e-9)
            XCTAssertEqual(point.altitude, Double(expected.ele)!)
            XCTAssertEqual(point.heartRate, expected.heartRate)
            XCTAssertEqual(point.cadence, expected.cadence)
            XCTAssertEqual(point.timestamp, inlineTimestamp(expected.time))
        }
    }

    /// 反例 (a)：删掉 `trkpt[1]` 的 `<ele>` → 该点 `altitude` 变 `nil`，逐字段断言失败；
    /// 其余三点的 ele 仍精确，证明判红只由被删字段触发。
    func testInlineFixtureMissingElevationFailsAltitudeFieldAssertion() throws {
        let track = try GPXCodec.decode(Data(inlineFixture(omittingElevationAt: 1).utf8))
        XCTAssertEqual(track.points.count, 4)
        XCTAssertEqual(track.points[0].altitude, 12.0)
        XCTAssertEqual(track.points[2].altitude, 13.2)
        XCTAssertEqual(track.points[3].altitude, 13.8)
        XCTAssertNil(track.points[1].altitude, "删掉 <ele> 后该点 altitude 必须为 nil")
        XCTAssertNotEqual(track.points[1].altitude, Double(Self.inlineFixturePoints[1].ele))
    }

    /// 反例 (b)：默认命名空间改成 GPX 1.0 → `decode` 必须抛 `unsupportedNamespace`，不得静默通过。
    func testInlineFixtureLegacyNamespaceThrowsUnsupportedNamespace() {
        guard let error = decodeError(inlineFixture(namespace: "http://www.topografix.com/GPX/1/0"))
        else {
            return XCTFail("expected unsupportedNamespace")
        }
        guard case .unsupportedNamespace = error else {
            return XCTFail("expected unsupportedNamespace, got \(error)")
        }
    }

    // MARK: - Rejection paths

    func testDecodeRejectsDocumentWithoutTrackSegment() {
        let document = gpxHeader + "<metadata><name>empty</name></metadata></gpx>"
        guard let error = decodeError(document) else {
            return XCTFail("expected missingTrack")
        }
        guard case .missingTrack = error else {
            return XCTFail("expected missingTrack, got \(error)")
        }
    }

    func testDecodeRejectsNonGPX11DefaultNamespace() {
        let document = """
        <gpx version="1.1" creator="unit" xmlns="http://www.topografix.com/GPX/1/0">
          <trk><trkseg><trkpt lat="30.0" lon="120.0"><time>2023-11-14T22:13:20Z</time></trkpt></trkseg></trk>
        </gpx>
        """
        guard let error = decodeError(document) else {
            return XCTFail("expected unsupportedNamespace")
        }
        guard case .unsupportedNamespace = error else {
            return XCTFail("expected unsupportedNamespace, got \(error)")
        }
    }

    func testDecodeRejectsOutOfRangeLatitude() {
        let document = gpxHeader
            + "<trk><name>run</name><type>running</type><trkseg>"
            + "<trkpt lat=\"91\" lon=\"120.0\"><time>2023-11-14T22:13:20Z</time></trkpt>"
            + "</trkseg></trk></gpx>"
        guard let error = decodeError(document) else {
            return XCTFail("expected invalidPoint")
        }
        guard case .invalidPoint = error else {
            return XCTFail("expected invalidPoint, got \(error)")
        }
    }

    func testDecodeRejectsNonISO8601Time() {
        let document = gpxHeader
            + "<trk><name>run</name><type>running</type><trkseg>"
            + "<trkpt lat=\"30.0\" lon=\"120.0\"><time>not-a-time</time></trkpt>"
            + "</trkseg></trk></gpx>"
        guard let error = decodeError(document) else {
            return XCTFail("expected invalidPoint")
        }
        guard case .invalidPoint = error else {
            return XCTFail("expected invalidPoint, got \(error)")
        }
    }

    func testReadFromMissingPathThrowsIOFailure() {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).gpx")
        XCTAssertThrowsError(try GPXCodec.read(from: fileURL)) { error in
            guard let codecError = error as? GPXCodecError, case .ioFailure = codecError else {
                return XCTFail("expected ioFailure, got \(error)")
            }
        }
    }

    // MARK: - Track validation

    func testTrackRejectsInvalidConstruction() {
        XCTAssertNil(
            GPXTrack(
                name: "",
                createdAt: baseTimestamp,
                activityType: "running",
                points: [makeSample(index: 0)]
            )
        )
        XCTAssertNil(
            GPXTrack(
                name: "empty",
                createdAt: baseTimestamp,
                activityType: "running",
                points: []
            )
        )
        let earlier = makeSample(index: 0)
        let later = makeSample(index: 1)
        XCTAssertNil(
            GPXTrack(
                name: "decreasing",
                createdAt: baseTimestamp,
                activityType: "running",
                points: [later, earlier]
            )
        )
    }

    func testErrorDescriptionsAreDistinctAndNonEmpty() {
        let errors: [GPXCodecError] = [
            .invalidDocument("a"),
            .missingTrack("b"),
            .unsupportedNamespace("c"),
            .invalidPoint(index: 0, reason: "d"),
            .ioFailure("e")
        ]
        let descriptions = errors.map(\.description)
        XCTAssertEqual(Set(descriptions).count, errors.count)
        XCTAssertTrue(descriptions.allSatisfy { !$0.isEmpty })
    }
}
