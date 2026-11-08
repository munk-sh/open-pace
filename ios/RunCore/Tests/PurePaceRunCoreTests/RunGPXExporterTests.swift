import Foundation
import XCTest
@testable import PurePaceRunCore

final class RunGPXExporterTests: XCTestCase {
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

    private func makeSample(
        index: Int,
        altitude: Double?,
        heartRate: Int?,
        cadence: Int?
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

    private func makeSamples() -> [RunSample] {
        [
            makeSample(index: 0, altitude: 12.25, heartRate: 112, cadence: 82),
            makeSample(index: 1, altitude: 12.5, heartRate: 128, cadence: 84),
            makeSample(index: 2, altitude: nil, heartRate: nil, cadence: nil),
            makeSample(index: 3, altitude: 13.75, heartRate: 140, cadence: 90)
        ]
    }

    private func makeRecord(samples: [RunSample], startedAt: Date? = nil) -> RunRecord {
        let start = startedAt ?? baseTimestamp
        return RunRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(1800),
            distance: RunDistance(meters: 4000)!,
            activeDuration: 1800,
            splits: [
                RunSplit(index: 1, distance: RunDistance(meters: 1000)!, duration: 450)!,
                RunSplit(index: 2, distance: RunDistance(meters: 1000)!, duration: 450)!,
                RunSplit(index: 3, distance: RunDistance(meters: 1000)!, duration: 450)!,
                RunSplit(index: 4, distance: RunDistance(meters: 1000)!, duration: 450)!
            ],
            samples: samples
        )!
    }

    private func gpxFileNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return entries.filter { $0.hasSuffix(".gpx") }.sorted()
    }

    // MARK: - 导出回读

    func testExportRoundTripPreservesEveryPoint() throws {
        let samples = makeSamples()
        let record = makeRecord(samples: samples)
        let exporter = RunGPXExporter(directoryURL: directory)
        let url = try exporter.export(record)

        XCTAssertEqual(url.pathExtension, "gpx")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        XCTAssertGreaterThan(size?.intValue ?? 0, 0)

        let track = try GPXCodec.read(from: url)
        XCTAssertEqual(track.points.count, samples.count)
        XCTAssertEqual(track.points, samples)
        XCTAssertFalse(track.name.isEmpty)
        XCTAssertEqual(track.activityType, "running")
        XCTAssertEqual(track.points.map(\.timestamp), samples.map(\.timestamp))
    }

    func testExportFilenameContainsUTCStartAndIDAndNeverOverwrites() throws {
        let record = makeRecord(samples: makeSamples())
        let exporter = RunGPXExporter(directoryURL: directory)
        let firstURL = try exporter.export(record)
        let secondURL = try exporter.export(record)

        XCTAssertNotEqual(firstURL, secondURL)
        for url in [firstURL, secondURL] {
            XCTAssertTrue(url.lastPathComponent.contains("20231114T221320Z"))
            XCTAssertTrue(url.lastPathComponent.contains(record.id.uuidString))
            let track = try GPXCodec.read(from: url)
            XCTAssertEqual(track.points, record.samples)
        }
        XCTAssertEqual(try gpxFileNames().count, 2)
    }

    // MARK: - 空采样

    func testExportEmptySamplesThrowsAndWritesNoFile() throws {
        let record = makeRecord(samples: [])
        let exporter = RunGPXExporter(directoryURL: directory)

        XCTAssertThrowsError(try exporter.export(record)) { error in
            XCTAssertEqual(error as? RunArchiveError, .emptySamples)
        }
        XCTAssertEqual(try gpxFileNames(), [])
    }
}
