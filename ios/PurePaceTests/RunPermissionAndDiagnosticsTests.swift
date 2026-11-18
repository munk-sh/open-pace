import CoreLocation
import Foundation
import XCTest
import PurePaceRunCore
@testable import PurePace

/// 权限链路 + 诊断快照的 App 侧 L1 断言（无模拟器、无真实弹窗）。
///
/// 每条断言都对应一个可构造的错误输入反例：请求次数不唯一 / 拒绝仍进入记录态 /
/// 后台声明缺失 / 空 samples 距离伪装成 0，都会让断言红。
@MainActor
final class RunPermissionAndDiagnosticsTests: XCTestCase {
    private let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 夹具

    private final class SpyLocationSource: RunLocationProviding {
        weak var delegate: RunLocationSourceDelegate?
        var authorization: RunLocationAuthorization
        private(set) var whenInUseRequestCount = 0
        private(set) var alwaysRequestCount = 0
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var sampleSource: RunSampleSource = .device
        var allowsBackgroundLocationUpdates = true
        var pausesLocationUpdatesAutomatically = false
        var rawCallbackCount = 0
        var filteredCallbackCount = 0
        var lastAcceptedAccuracyMeters: Double?

        init(authorization: RunLocationAuthorization) {
            self.authorization = authorization
        }

        func start() {
            startCount += 1
        }

        func stop() {
            stopCount += 1
        }

        func requestWhenInUseAuthorization() {
            whenInUseRequestCount += 1
        }

        func requestAlwaysAuthorization() {
            alwaysRequestCount += 1
        }

        func report(_ authorization: RunLocationAuthorization) {
            self.authorization = authorization
            delegate?.locationSource(self, didChangeAuthorization: authorization)
        }
    }

    private final class StubProbe: SystemAuthorizationProbing {
        var authorizationStatus: RunLocationAuthorization
        var accuracyAuthorization: RunLocationAccuracy = .full

        init(status: RunLocationAuthorization) {
            self.authorizationStatus = status
        }
    }

    private final class SilentSpeaker: AnnouncementSpeaking {
        func speak(_ command: AnnouncementCommand) {}
    }

    private struct Stores {
        let root: URL
        let checkpoint: RunCheckpointStore
        let archive: RunArchiveStore
    }

    private func makeStores() -> Stores {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePacePermission-\(UUID().uuidString)", isDirectory: true)
        return Stores(
            root: root,
            checkpoint: RunCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.jsonl")),
            archive: RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
    }

    private func makeViewModel(
        stores: Stores,
        source: SpyLocationSource,
        probe: StubProbe,
        countdownDuration: TimeInterval = 0
    ) -> RunSessionViewModel {
        RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: source,
            announcements: SilentSpeaker(),
            authorizationProbe: probe,
            countdownDuration: countdownDuration,
            now: { self.startDate },
            notificationCenter: NotificationCenter()
        )
    }

    // MARK: - ac-permission-request-when-in-use

    func testStartRequestsWhenInUseExactlyOnceWhenNotDetermined() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let source = SpyLocationSource(authorization: .notDetermined)
        let probe = StubProbe(status: .notDetermined)
        let viewModel = makeViewModel(stores: stores, source: source, probe: probe)

        viewModel.start()
        viewModel.start()

        XCTAssertEqual(source.whenInUseRequestCount, 1, "notDetermined 点「开始」必须恰请求一次系统 WhenInUse 权限")
        XCTAssertEqual(source.alwaysRequestCount, 0, "尚未拿到 WhenInUse 前不得请求 Always")
    }

    // MARK: - ac-permission-request-always

    func testRunningWithWhenInUseUpgradesToAlwaysExactlyOnce() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let source = SpyLocationSource(authorization: .authorizedWhenInUse)
        let probe = StubProbe(status: .authorizedWhenInUse)
        let viewModel = makeViewModel(stores: stores, source: source, probe: probe)

        viewModel.start()
        viewModel.advanceCountdown()
        XCTAssertEqual(viewModel.state, .running, "零时长倒计时到点后必须进入记录态")
        source.report(.authorizedWhenInUse)
        viewModel.tick()

        XCTAssertEqual(source.alwaysRequestCount, 1, "WhenInUse 且 running 必须恰请求一次 Always 升级")
    }

    // MARK: - ac-permission-denied-blocks-recording

    func testDeniedNeverEntersRecordingStateAndExposesSettingsRecovery() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let source = SpyLocationSource(authorization: .denied)
        let probe = StubProbe(status: .denied)
        let viewModel = makeViewModel(
            stores: stores,
            source: source,
            probe: probe,
            countdownDuration: RunStartCountdown.defaultDuration
        )

        viewModel.start()

        XCTAssertEqual(viewModel.state, .ready, "denied 不得进入记录态")
        XCTAssertFalse(viewModel.isCountingDown, "denied 连倒计时都不应开始")
        XCTAssertEqual(viewModel.locationReadiness, .permissionDenied)
        XCTAssertEqual(viewModel.locationReadiness.nextAction, .openSettings)
        XCTAssertEqual(source.whenInUseRequestCount, 0)
        XCTAssertNotNil(viewModel.locationSettingsURL, "denied 必须有系统设置深链出口")

        // 反例：若授权恢复为 WhenInUse，同一条 start 路径必须能正常开跑。
        source.report(.authorizedWhenInUse)
        probe.authorizationStatus = .authorizedWhenInUse
        viewModel.start()
        XCTAssertTrue(viewModel.isCountingDown)
    }

    // MARK: - ac-background-declaration

    func testBackgroundLocationModeAndRuntimeFlagCannotDisagree() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertTrue(
            modes.contains("location"),
            "Info.plist 缺 UIBackgroundModes=location 时后台定位声明不成立，实际：\(modes)"
        )

        let manager = StubManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let source = RunLocationSource(manager: manager)
        source.start()
        XCTAssertTrue(
            manager.allowsBackgroundLocationUpdates,
            "已授权时运行期必须打开 allowsBackgroundLocationUpdates，否则声明与行为缺一"
        )
    }

    // MARK: - ac-location-fallback

    private final class StubManager: RunLocationManaging {
        weak var handler: RunLocationManagerHandler?
        var authorizationStatus: CLAuthorizationStatus = .notDetermined
        var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
        var distanceFilter: CLLocationDistance = 0
        var activityType: CLActivityType = .other
        var pausesLocationUpdatesAutomatically = true
        var allowsBackgroundLocationUpdates = false

        func requestWhenInUseAuthorization() {}
        func requestAlwaysAuthorization() {}
        func startUpdatingLocation() {}
        func stopUpdatingLocation() {}
    }

    private final class SampleRecorder: RunLocationSourceDelegate {
        private(set) var samples: [RunSample] = []

        func locationSource(_ source: RunLocationProviding, didProduce sample: RunSample) {
            samples.append(sample)
        }

        func locationSource(
            _ source: RunLocationProviding,
            didChangeAuthorization authorization: RunLocationAuthorization
        ) {}
    }

    func testSingleImpreciseFixIsAcceptedOnlyAfterFallbackWindowAndMarked() {
        var now: TimeInterval = 1_000
        let manager = StubManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let source = RunLocationSource(manager: manager, uptime: { now })
        let recorder = SampleRecorder()
        source.delegate = recorder
        source.start()

        let payload = LocationPayload(
            latitude: 37.3349,
            longitude: -122.0090,
            altitude: nil,
            timestamp: startDate,
            horizontalAccuracy: 65
        )

        source.locationManagerDidUpdate(payloads: [payload])
        XCTAssertTrue(recorder.samples.isEmpty, "窗口内 65m fix 不得立即接受（护栏不得放宽到任意精度）")
        XCTAssertEqual(source.rawCallbackCount, 1)
        XCTAssertEqual(source.filteredCallbackCount, 1)

        now += RunLocationSource.accuracyFallbackWindowSeconds
        source.locationManagerDidUpdate(payloads: [payload])

        XCTAssertEqual(recorder.samples.count, 1, "窗口到点后必须按降级口径接受最佳 fix，而不是永久 0")
        XCTAssertEqual(source.lastAcceptedAccuracyMeters, 65, "降级接受的 fix 必须标记真实精度")
    }

    // MARK: - ac-diagnostics

    private struct StubBundleInfo: BundleInfoProviding {
        var infoDictionary: [String: Any]
    }

    func testDiagnosticsSnapshotReportsVersionSHAAndCallbackCounters() {
        let diagnostics = RunDiagnostics(
            bundleInfo: StubBundleInfo(infoDictionary: [
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "PurePaceBuildSHA": "ebcb3d8f-extra",
            ]),
            authorization: .authorizedWhenInUse,
            accuracy: .reduced,
            sampleCount: 0,
            lastSampleAt: nil,
            allowsBackgroundLocationUpdates: true,
            rawCallbackCount: 12,
            filteredCallbackCount: 12
        )

        XCTAssertTrue(diagnostics.text.contains("0.1.0 (1)"), "诊断必须给出可核对的版本号")
        XCTAssertTrue(diagnostics.text.contains("ebcb3d8f"), "构建 sha 只展示前 8 位")
        XCTAssertFalse(diagnostics.text.contains("ebcb3d8f-extra"), "不得泄漏完整 sha")
        XCTAssertTrue(diagnostics.text.contains("原始回调: 12"))
        XCTAssertTrue(diagnostics.text.contains("精度过滤丢弃: 12"))
        XCTAssertTrue(diagnostics.text.contains("仅前台"), "未拿到 Always 时必须明确「仅前台」")

        let missingSHA = RunDiagnostics(
            bundleInfo: StubBundleInfo(infoDictionary: [:]),
            authorization: .notDetermined,
            accuracy: .full,
            sampleCount: 0,
            lastSampleAt: nil,
            allowsBackgroundLocationUpdates: false,
            rawCallbackCount: 0,
            filteredCallbackCount: 0
        )
        XCTAssertTrue(missingSHA.text.contains("未注入"), "缺构建 sha 必须显式写未注入，不得伪装")
    }
}