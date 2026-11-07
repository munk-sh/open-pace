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
