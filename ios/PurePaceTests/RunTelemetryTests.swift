import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

@MainActor
final class RunTelemetryTests: XCTestCase {
    private let t0: TimeInterval = 1_700_000_000

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - ac-tel-fields / ac-no-semantic-change

    func testWriterAddsTelemetryAndSourcesWithoutTouchingExistingValues() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let samples = makeSamples(count: 3)
        let record = makeRecord(samples: samples)
        let url = try store.save(record)
        let before = try readJSON(url)

        let sources: [TimeInterval: RunSampleSource] = [
            samples[1].timestamp.timeIntervalSince1970: .simulated
        ]
        try RunTelemetryWriter(directoryURL: store.directoryURL).inject(
            telemetry: makeTelemetry(),
            sources: sources,
            recordID: record.id,
            defaultSource: .device
        )
        let after = try readJSON(url)

        // telemetry 顶层键 + 四类字段
        let telemetry = try XCTUnwrap(after["telemetry"] as? [String: Any])
        let authorization = try XCTUnwrap(telemetry["authorizationStatus"] as? [String: Any])
        XCTAssertEqual(authorization["name"] as? String, "authorizedAlways")
        XCTAssertEqual(authorization["rawValue"] as? Int, 3)
        let accuracy = try XCTUnwrap(telemetry["accuracyAuthorization"] as? [String: Any])
        XCTAssertEqual(accuracy["name"] as? String, "full")
        XCTAssertEqual(accuracy["rawValue"] as? Int, 0)
        XCTAssertEqual(telemetry["allowsBackgroundLocationUpdates"] as? Bool, true)
        XCTAssertEqual(telemetry["pausesLocationUpdatesAutomatically"] as? Bool, false)

        // samples[].source：显式映射命中第二条，其余走默认 source
        let afterSamples = try XCTUnwrap(after["samples"] as? [[String: Any]])
        XCTAssertEqual(afterSamples.count, 3)
        let sourceValues = afterSamples.compactMap { $0["source"] as? String }
        XCTAssertEqual(sourceValues, ["device", "simulated", "device"])

        // 既有键值逐字段不变
        XCTAssertEqual(number(before["distance"]), number(after["distance"]))
        XCTAssertEqual(number(before["activeDuration"]), number(after["activeDuration"]))
        XCTAssertEqual(number(before["startedAt"]), number(after["startedAt"]))
        XCTAssertEqual(number(before["endedAt"]), number(after["endedAt"]))
        let beforeSamples = try XCTUnwrap(before["samples"] as? [[String: Any]])
        for (old, new) in zip(beforeSamples, afterSamples) {
            XCTAssertNotNil(number(old["latitude"]))
            XCTAssertEqual(number(old["latitude"]), number(new["latitude"]))
            XCTAssertEqual(number(old["longitude"]), number(new["longitude"]))
            XCTAssertEqual(number(old["timestamp"]), number(new["timestamp"]))
        }
    }

    // MARK: - ac-tel-source-device

    func testViewModelTagsDeviceSamplesFromInjectedSource() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = StubLocationSource(
            sampleSource: .device,
            allowsBackgroundLocationUpdates: true,
            pausesLocationUpdatesAutomatically: false
        )
        let (viewModel, clock) = makeViewModel(
            store: store,
            locationSource: source,
            probe: StubAuthorizationProbe(status: .authorizedAlways, accuracy: .full)
        )

        let samples = makeSamples(count: 4)
        runSession(viewModel: viewModel, clock: clock, source: source, samples: samples)

        let url = try onlyRunFile(in: store.directoryURL)
        let json = try readJSON(url)
        let jsonSamples = try XCTUnwrap(json["samples"] as? [[String: Any]])
        XCTAssertEqual(jsonSamples.compactMap { $0["source"] as? String }, Array(repeating: "device", count: 4))
        XCTAssertEqual(jsonSamples.count, 4)

        let telemetry = try XCTUnwrap(json["telemetry"] as? [String: Any])
        XCTAssertEqual(telemetry["allowsBackgroundLocationUpdates"] as? Bool, true)
        XCTAssertEqual(telemetry["pausesLocationUpdatesAutomatically"] as? Bool, false)
    }

    func testViewModelTagsSimulatedSamplesAndRecordsHonestBackgroundSwitches() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = StubLocationSource(
            sampleSource: .simulated,
            allowsBackgroundLocationUpdates: false,
            pausesLocationUpdatesAutomatically: false
        )
        let probe = StubAuthorizationProbe(status: .authorizedAlways, accuracy: .full)
        let (viewModel, clock) = makeViewModel(store: store, locationSource: source, probe: probe)

        let samples = makeSamples(count: 3)
        runSession(viewModel: viewModel, clock: clock, source: source, samples: samples)

        let url = try onlyRunFile(in: store.directoryURL)
        let json = try readJSON(url)
        let jsonSamples = try XCTUnwrap(json["samples"] as? [[String: Any]])
        XCTAssertEqual(
            jsonSamples.compactMap { $0["source"] as? String },
            Array(repeating: "simulated", count: 3)
        )
        let telemetry = try XCTUnwrap(json["telemetry"] as? [String: Any])
        XCTAssertEqual(telemetry["allowsBackgroundLocationUpdates"] as? Bool, false)
        XCTAssertEqual(telemetry["pausesLocationUpdatesAutomatically"] as? Bool, false)
    }

    // MARK: - ac-tel-always

    func testAuthorizationProbeMapsAuthorizedAlwaysToRawValueThree() throws {
        XCTAssertEqual(RunLocationAuthorization.notDetermined.clRawValue, 0)
        XCTAssertEqual(RunLocationAuthorization.restricted.clRawValue, 1)
        XCTAssertEqual(RunLocationAuthorization.denied.clRawValue, 2)
        XCTAssertEqual(RunLocationAuthorization.authorizedAlways.clRawValue, 3)
        XCTAssertEqual(RunLocationAuthorization.authorizedWhenInUse.clRawValue, 4)
        XCTAssertEqual(RunLocationAccuracy.full.clRawValue, 0)
        XCTAssertEqual(RunLocationAccuracy.reduced.clRawValue, 1)

        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = StubLocationSource(
            sampleSource: .simulated,
            allowsBackgroundLocationUpdates: false,
            pausesLocationUpdatesAutomatically: false
        )
        let (viewModel, clock) = makeViewModel(
            store: store,
            locationSource: source,
            probe: StubAuthorizationProbe(status: .authorizedAlways, accuracy: .full)
        )
        runSession(viewModel: viewModel, clock: clock, source: source, samples: makeSamples(count: 2))

        let json = try readJSON(onlyRunFile(in: store.directoryURL))
        let telemetry = try XCTUnwrap(json["telemetry"] as? [String: Any])
        let authorization = try XCTUnwrap(telemetry["authorizationStatus"] as? [String: Any])
        XCTAssertEqual(authorization["name"] as? String, "authorizedAlways")
        XCTAssertEqual(authorization["rawValue"] as? Int, 3)
    }

    // MARK: - ac-tel-backcompat

    func testLegacyRecordWithoutTelemetryDecodesViaList() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = makeRecord(samples: makeSamples(count: 3))
        try writeJSON(try encode(record), to: store.directoryURL.appendingPathComponent("legacy.json"))

        let listed = try store.list()
        XCTAssertEqual(listed, [record], "无 telemetry / source 的旧格式必须可解码")
    }

    func testRecordWithUnknownTelemetryAndSourceKeysDecodesUnchanged() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = makeRecord(samples: makeSamples(count: 3))
        var json = try readJSON(try writeJSON(try encode(record), to: store.directoryURL.appendingPathComponent("new.json")))
        json["telemetry"] = ["unknown": true]
        if var samples = json["samples"] as? [[String: Any]] {
            for index in samples.indices {
                samples[index]["source"] = "device"
            }
            json["samples"] = samples
        }
        try writeJSON(JSONSerialization.data(withJSONObject: json), to: store.directoryURL.appendingPathComponent("new.json"))

        let listed = try store.list()
        XCTAssertEqual(listed, [record], "含新增未知键的新格式字段数值必须逐字段不变")
    }

    // MARK: - ac-audio-telemetry

    func testAnnouncementTelemetryKeysRoundTripThroughJSON() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = makeRecord(samples: makeSamples(count: 2))
        try store.save(record)

        let recorder = AnnouncementTelemetryRecorder()
        let context = AnnouncementAudioContext(
            category: "playback",
            mode: "spokenAudio",
            categoryOptions: ["duckOthers", "mixWithOthers"],
            isOtherAudioPlaying: false,
            secondaryAudioShouldBeSilencedHint: false,
            sessionActivated: true
        )
        let start = Date(timeIntervalSince1970: t0 + 1)
        recorder.recordStarted(
            splitIndex: 1,
            text: "已完成第 1 公里，用时 05:30",
            startedAt: start,
            context: context
        )
        recorder.recordSpeechDidStart(splitIndex: 1, startedAt: start)
        recorder.recordFinished(
            splitIndex: 1,
            finishedAt: start.addingTimeInterval(3),
            cancelled: false,
            sessionDeactivated: true,
            duckRevoked: true
        )

        let telemetry = RunTelemetry(
            authorizationStatus: RunTelemetryAuthorization(name: "authorizedAlways", rawValue: 3),
            accuracyAuthorization: RunTelemetryAuthorization(name: "full", rawValue: 0),
            allowsBackgroundLocationUpdates: true,
            pausesLocationUpdatesAutomatically: false,
            announcements: recorder.snapshot()
        )
        try RunTelemetryWriter(directoryURL: store.directoryURL).inject(
            telemetry: telemetry,
            sources: [:],
            recordID: record.id,
            defaultSource: .device
        )

        let json = try readJSON(onlyRunFile(in: store.directoryURL))
        let telemetryJSON = try XCTUnwrap(json["telemetry"] as? [String: Any])
        let announcements = try XCTUnwrap(telemetryJSON["announcements"] as? [[String: Any]])
        XCTAssertEqual(announcements.count, 1)
        let entry = announcements[0]
        XCTAssertEqual(entry["splitIndex"] as? Int, 1)
        XCTAssertEqual(entry["text"] as? String, "已完成第 1 公里，用时 05:30")
        XCTAssertNotNil(entry["startedAt"] as? Double)
        XCTAssertNotNil(entry["finishedAt"] as? Double)
        XCTAssertEqual(entry["cancelled"] as? Bool, false)
        XCTAssertEqual(entry["category"] as? String, "playback")
        XCTAssertEqual(entry["mode"] as? String, "spokenAudio")
        let options = try XCTUnwrap(entry["categoryOptions"] as? [String])
        XCTAssertTrue(options.contains("duckOthers"))
        XCTAssertNotNil(entry["isOtherAudioPlaying"] as? Bool)
        XCTAssertNotNil(entry["secondaryAudioShouldBeSilencedHint"] as? Bool)
        XCTAssertEqual(entry["sessionActivated"] as? Bool, true)
        XCTAssertEqual(entry["sessionDeactivated"] as? Bool, true)
        XCTAssertEqual(entry["duckRevoked"] as? Bool, true)
    }

    // MARK: - 夹具

    private struct Stores {
        let root: URL
        let archive: RunArchiveStore
        let checkpoint: RunCheckpointStore
    }

    private final class StubLocationSource: RunLocationProviding {
        weak var delegate: RunLocationSourceDelegate?
        var authorization: RunLocationAuthorization = .authorizedAlways
        let sampleSource: RunSampleSource
        let allowsBackgroundLocationUpdates: Bool
        let pausesLocationUpdatesAutomatically: Bool

        init(
            sampleSource: RunSampleSource,
            allowsBackgroundLocationUpdates: Bool,
            pausesLocationUpdatesAutomatically: Bool
        ) {
            self.sampleSource = sampleSource
            self.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
            self.pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically
        }

        func start() {
            delegate?.locationSource(self, didChangeAuthorization: authorization)
        }

        func stop() {}
    }

    private final class StubAuthorizationProbe: SystemAuthorizationProbing {
        var authorizationStatus: RunLocationAuthorization
        var accuracyAuthorization: RunLocationAccuracy

        init(status: RunLocationAuthorization, accuracy: RunLocationAccuracy) {
            authorizationStatus = status
            accuracyAuthorization = accuracy
        }
    }

    private final class SilentSpeaker: AnnouncementSpeaking {
        private(set) var commands: [AnnouncementCommand] = []
        func speak(_ command: AnnouncementCommand) { commands.append(command) }
    }

    private final class Clock {
        var date: Date
        init(date: Date) { self.date = date }
    }

    private func makeStores() -> (URL, RunArchiveStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceTelemetry-\(UUID().uuidString)", isDirectory: true)
        let archive = RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        return (root, archive)
    }

    private func makeViewModel(
        store: RunArchiveStore,
        locationSource: RunLocationProviding,
        probe: SystemAuthorizationProbing
    ) -> (viewModel: RunSessionViewModel, clock: Clock) {
        let root = store.directoryURL.deletingLastPathComponent()
        let clock = Clock(date: Date(timeIntervalSince1970: t0))
        let viewModel = RunSessionViewModel(
            checkpointStore: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archiveStore: store,
            locationSource: locationSource,
            announcements: SilentSpeaker(),
            announcementRecorder: AnnouncementTelemetryRecorder(),
            authorizationProbe: probe,
            telemetryDebugEnabled: true,
            countdownDuration: 0,
            now: { clock.date }
        )
        return (viewModel, clock)
    }

    private func runSession(
        viewModel: RunSessionViewModel,
        clock: Clock,
        source: RunLocationProviding,
        samples: [RunSample]
    ) {
        clock.date = Date(timeIntervalSince1970: t0)
        viewModel.start()
        for sample in samples {
            viewModel.locationSource(source, didProduce: sample)
        }
        clock.date = Date(timeIntervalSince1970: t0 + 30)
        viewModel.finish()
        viewModel.saveFinished()
        XCTAssertTrue(viewModel.didSave, "结束必须归档一次")
    }

    private func makeTelemetry() -> RunTelemetry {
        RunTelemetry(
            authorizationStatus: RunTelemetryAuthorization(name: "authorizedAlways", rawValue: 3),
            accuracyAuthorization: RunTelemetryAuthorization(name: "full", rawValue: 0),
            allowsBackgroundLocationUpdates: true,
            pausesLocationUpdatesAutomatically: false,
            announcements: []
        )
    }

    private func makeRecord(samples: [RunSample]) -> RunRecord {
        RunRecord(
            startedAt: Date(timeIntervalSince1970: t0),
            endedAt: Date(timeIntervalSince1970: t0 + 10),
            distance: RunDistance(meters: 100)!,
            activeDuration: 10,
            splits: [],
            samples: samples
        )!
    }

    private func makeSamples(count: Int) -> [RunSample] {
        (1...count).map { index in
            RunSample(
                latitude: 37.3349 + Double(index) * 0.0003,
                longitude: -122.0090,
                altitude: 0,
                timestamp: Date(timeIntervalSince1970: t0 + Double(index)),
                heartRate: nil,
                cadence: nil
            )!
        }
    }

    private func encode(_ record: RunRecord) throws -> Data {
        try JSONEncoder().encode(record)
    }

    @discardableResult
    private func writeJSON(_ data: Data, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "RunTelemetryTests", code: 1)
        }
        return json
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func onlyRunFile(in directory: URL) throws -> URL {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
        XCTAssertEqual(files.count, 1, "应恰有 1 条跑次 JSON")
        return try XCTUnwrap(files.first)
    }
}
