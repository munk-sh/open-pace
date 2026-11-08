import XCTest
import PurePaceRunCore
@testable import PurePace

final class RunExportStateTests: XCTestCase {
    private var exportDirectory: URL!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunExportStateTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let exportDirectory {
            try? FileManager.default.removeItem(at: exportDirectory)
        }
        try super.tearDownWithError()
    }

    private func sample(offset: TimeInterval) -> RunSample {
        RunSample(
            latitude: 31.2304 + offset * 0.0001,
            longitude: 121.4737 + offset * 0.0001,
            altitude: 10 + offset,
            timestamp: start.addingTimeInterval(offset),
            heartRate: nil,
            cadence: nil
        )!
    }

    private func makeRecord(samples: [RunSample]) -> RunRecord {
        RunRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(30),
            distance: RunDistance(meters: 300)!,
            activeDuration: 30,
            splits: [],
            samples: samples
        )!
    }

    private func gpxFiles() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "gpx" }
    }

    func testExportWritesRealFileAndRoundTripsSamples() throws {
        let samples = [sample(offset: 0), sample(offset: 1), sample(offset: 2)]
        var state = RunExportState()

        state.export(makeRecord(samples: samples), using: RunGPXExporter(directoryURL: exportDirectory))

        guard case .exported(let url) = state.phase else {
            return XCTFail("导出应成功，实际 \(state.phase)")
        }
        XCTAssertEqual(url.pathExtension, "gpx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "导出文件必须真实落盘")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        XCTAssertGreaterThan(size?.intValue ?? 0, 0, "导出文件必须非空")

        let track = try GPXCodec.read(from: url)
        XCTAssertEqual(track.points.count, samples.count)
        XCTAssertEqual(track.points.map(\.timestamp), samples.map(\.timestamp))
        XCTAssertEqual(track.points.map(\.latitude), samples.map(\.latitude))
        XCTAssertEqual(track.points.map(\.longitude), samples.map(\.longitude))
    }

    func testRepeatedExportDoesNotOverwriteEarlierFile() throws {
        let samples = [sample(offset: 0), sample(offset: 5)]
        let record = makeRecord(samples: samples)
        let exporter = RunGPXExporter(directoryURL: exportDirectory)
        var first = RunExportState()
        var second = RunExportState()

        first.export(record, using: exporter)
        second.export(record, using: exporter)

        guard case .exported(let firstURL) = first.phase,
              case .exported(let secondURL) = second.phase else {
            return XCTFail("两次导出都应成功")
        }
        XCTAssertNotEqual(firstURL, secondURL, "重复导出必须产生不同文件")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(gpxFiles().count, 2)

        let firstTrack = try GPXCodec.read(from: firstURL)
        XCTAssertEqual(firstTrack.points.map(\.timestamp), samples.map(\.timestamp))
    }

    func testEmptySamplesFailsWithoutNewFile() throws {
        let record = makeRecord(samples: [])
        let exporter = RunGPXExporter(directoryURL: exportDirectory)
        var state = RunExportState()

        XCTAssertThrowsError(try exporter.export(record))
        state.export(record, using: exporter)

        XCTAssertEqual(state.phase, .failed)
        XCTAssertTrue(gpxFiles().isEmpty, "失败导出不得新增 .gpx 文件")
    }

    func testExportDirectoryFollowsInjectedDocumentsDirectory() throws {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunExportDocuments-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: documents) }
        let fileManager = DocumentDirectoryFileManager(documentsURL: documents)

        let expected = documents.appendingPathComponent("Exports", isDirectory: true)
        XCTAssertEqual(RunStorage.exportDirectory(fileManager: fileManager), expected)
        XCTAssertEqual(
            RunStorage.makeExporter(fileManager: fileManager).directoryURL,
            expected
        )
        XCTAssertEqual(RunStorage.makeStores(fileManager: fileManager).exporter.directoryURL, expected)
    }
}

private final class DocumentDirectoryFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .documentDirectory {
            return [documentsURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
