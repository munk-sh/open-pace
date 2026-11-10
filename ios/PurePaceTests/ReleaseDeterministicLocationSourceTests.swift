import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

/// Release 确定性定位源（`-releaseDeterministicLocation`，默认关）的进程内断言。
///
/// 全部用例同步驱动注入时钟/手动 tick，不出现 `sleep`，也不启动真实 `Timer`。
@MainActor
final class ReleaseDeterministicLocationSourceTests: XCTestCase {
    // MARK: - 可注入桩

    private final class StubLocationSource: RunLocationProviding {
        weak var delegate: RunLocationSourceDelegate?
        var authorization: RunLocationAuthorization = .authorizedAlways
        var sampleSource: RunSampleSource = .device
        var allowsBackgroundLocationUpdates = true
        var pausesLocationUpdatesAutomatically = true
        private(set) var startCount = 0

        func start() {
            startCount += 1
        }

        func stop() {}
    }

    private final class Recorder: RunLocationSourceDelegate {
        private(set) var samples: [RunSample] = []
        private(set) var authorizations: [RunLocationAuthorization] = []

        func locationSource(_ source: RunLocationProviding, didProduce sample: RunSample) {
            samples.append(sample)
        }

        func locationSource(
            _ source: RunLocationProviding,
            didChangeAuthorization authorization: RunLocationAuthorization
        ) {
            authorizations.append(authorization)
        }
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - ac-default-selects-real / ac-default-no-injection

    func testDefaultSelectionReturnsInjectedRealSourceWithoutBuildingDeterministicSource() {
        let real = StubLocationSource()
        let recorder = Recorder()
        real.delegate = recorder
        var deterministicFactoryCalls = 0

        let selection = RunLocationSourceSelection.select(
            arguments: ["PurePace", "-uiTestResetArchive"],
            makeReal: { real },
            makeDeterministic: { scenario in
                deterministicFactoryCalls += 1
                return ReleaseDeterministicLocationSource(
                    scenario: scenario,
                    now: { Self.start },
                    schedulesTicks: false
                )
            }
        )

        XCTAssertTrue(selection.source === real, "无 flag 时必须返回注入的真实源实例")
        XCTAssertFalse(selection.telemetryDebugEnabled, "默认路径不得打开调试遥测")
        XCTAssertEqual(deterministicFactoryCalls, 0, "无 flag 时确定性源工厂调用次数必须为 0")
        XCTAssertEqual(real.startCount, 0, "选择器不得主动 start 任何数据源")
        XCTAssertTrue(recorder.samples.isEmpty, "默认路径不得有任何样本注入")
    }

    // MARK: - ac-flag-selects-release-source

    func testFlagSelectsReleaseDeterministicSource() {
        var realFactoryCalls = 0

        let selection = RunLocationSourceSelection.select(
            arguments: ["PurePace", "-releaseDeterministicLocation", "km-crossing"],
            makeReal: {
                realFactoryCalls += 1
                return StubLocationSource()
            },
            makeDeterministic: { scenario in
                ReleaseDeterministicLocationSource(
                    scenario: scenario,
                    now: { Self.start },
                    schedulesTicks: false
                )
            }
        )

        XCTAssertEqual(realFactoryCalls, 0, "flag 命中时不得构造真实源")
        XCTAssertTrue(selection.source is ReleaseDeterministicLocationSource)
        XCTAssertEqual(selection.source.sampleSource, .simulated)
        XCTAssertTrue(selection.telemetryDebugEnabled)
    }

    // MARK: - ac-flag-fail-closed

    func testMalformedFlagFallsBackToRealSource() {
        let cases: [[String]] = [
            ["PurePace", "-releaseDeterministicLocation"],
            ["PurePace", "-releaseDeterministicLocation", "-uiTestLocation"],
            ["PurePace", "-releaseDeterministicLocation", "bogus"],
            ["PurePace", "-releaseDeterministicLocation", ""]
        ]

        for arguments in cases {
            let real = StubLocationSource()
            var deterministicFactoryCalls = 0
            let selection = RunLocationSourceSelection.select(
                arguments: arguments,
                makeReal: { real },
                makeDeterministic: { scenario in
                    deterministicFactoryCalls += 1
                    return ReleaseDeterministicLocationSource(
                        scenario: scenario,
                        now: { Self.start },
                        schedulesTicks: false
                    )
                }
            )
            XCTAssertTrue(selection.source === real, "非法形态必须回真实源: \(arguments)")
            XCTAssertFalse(selection.telemetryDebugEnabled, "fail-closed 不打开调试遥测: \(arguments)")
            XCTAssertEqual(deterministicFactoryCalls, 0, "非法形态不得构造确定性源: \(arguments)")
        }
    }

    // MARK: - ac-flag-sample-timing

    func testSamplesAdvanceExactlyOneSecondApartWithFixedLongitude() {
        let source = ReleaseDeterministicLocationSource(
            scenario: .kmCrossing,
            now: { Self.start },
            schedulesTicks: false
        )
        let recorder = Recorder()
        source.delegate = recorder
        source.start()
        for _ in 0..<4 {
            source.advanceTick()
        }
        source.stop()

        XCTAssertEqual(recorder.samples.count, 5)
        let timestamps = recorder.samples.map(\.timestamp)
        for index in 1..<timestamps.count {
            XCTAssertEqual(
                timestamps[index].timeIntervalSince(timestamps[index - 1]),
                1.0,
                accuracy: 0,
                "相邻样本时间戳必须严格相差 1.0 s"
            )
        }
        let latitudes = recorder.samples.map(\.latitude)
        for index in 1..<latitudes.count {
            XCTAssertGreaterThan(latitudes[index], latitudes[index - 1], "纬度必须单调推进")
        }
        XCTAssertEqual(Set(recorder.samples.map(\.longitude)).count, 1, "经度必须固定")
    }

    // MARK: - ac-flag-honest-capabilities

    func testCapabilitiesAreHonestlyReported() {
        let source = ReleaseDeterministicLocationSource(
            scenario: .kmCrossing,
            now: { Self.start },
            schedulesTicks: false
        )
        let recorder = Recorder()
        source.delegate = recorder
        source.start()
        source.stop()

        XCTAssertEqual(source.sampleSource, .simulated)
        XCTAssertEqual(source.authorization, .authorizedWhenInUse)
        XCTAssertFalse(source.allowsBackgroundLocationUpdates)
        XCTAssertFalse(source.pausesLocationUpdatesAutomatically)
        XCTAssertEqual(recorder.authorizations, [.authorizedWhenInUse])
    }

    // MARK: - ac-flag-km-boundary

    func testKmCrossingProducesExactlyOneKilometerAnnouncement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("purepace-release-deterministic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var orchestrator = RunSessionOrchestrator(
            checkpointStore: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archiveStore: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
        try orchestrator.start(at: Self.start)

        var announcements: [AnnouncementCommand] = []
        var previousDistance = 0.0
        receiverLoop: for tick in 0...60 {
            let sample = try XCTUnwrap(
                ReleaseDeterministicLocationSource.sample(
                    scenario: .kmCrossing,
                    tick: tick,
                    startedAt: Self.start
                )
            )
            let update = try orchestrator.ingest(sample)
            if update.metrics.distance.meters < RunMetricsEngine.splitDistanceMeters {
                XCTAssertTrue(update.announcements.isEmpty, "跨过 1 km 前不得有公里播报（tick \(tick)）")
                XCTAssertEqual(update.metrics.completedKilometers, 0)
            }
            announcements.append(contentsOf: update.announcements)
            previousDistance = update.metrics.distance.meters
            if previousDistance >= RunMetricsEngine.splitDistanceMeters, announcements.count == 1 {
                break receiverLoop
            }
        }

        XCTAssertEqual(announcements.count, 1, "跨过 1 km 必须恰好 1 条播报")
        XCTAssertEqual(announcements.first?.splitIndex, 1)
        XCTAssertEqual(announcements.first?.trigger, .kilometerCompleted)
        XCTAssertEqual(orchestrator.metrics.completedKilometers, 1)
    }
}
