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
        var locationServicesEnabled = true
        var lastLocationError: RunLocationErrorInfo?

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
        source: RunLocationProviding,
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
        var locationServicesEnabled = true
        private(set) var startUpdatingCount = 0

        func requestWhenInUseAuthorization() {}
        func requestAlwaysAuthorization() {}
        func startUpdatingLocation() { startUpdatingCount += 1 }
        func stopUpdatingLocation() {}

        /// 等价于系统 `didFailWithError`：只经 handler 上报 `CLError` 原始码。
        func fail(_ code: CLError.Code) {
            handler?.locationManagerDidFail(code: code.rawValue)
        }
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

    // MARK: - ac-location-error / ac-services-disabled

    private func makeLocationChain(
        stores: Stores
    ) -> (manager: StubManager, source: RunLocationSource, viewModel: RunSessionViewModel) {
        let manager = StubManager()
        manager.authorizationStatus = .authorizedAlways
        let source = RunLocationSource(manager: manager)
        let viewModel = makeViewModel(
            stores: stores,
            source: source,
            probe: StubProbe(status: .authorizedAlways)
        )
        viewModel.start()
        return (manager, source, viewModel)
    }

    /// ac-location-error / ac-services-disabled：系统定位失败或服务关闭都必须落到既有
    /// `.unavailable` 态并给出可见文案，不得静默当成「等待首条样本」。
    func testLocationFailureAndServicesOffSetUnavailableAndExposeCopy() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let chain = makeLocationChain(stores: stores)
        XCTAssertEqual(chain.viewModel.locationReadiness, .ready, "前置：已授权且服务开启时必须就绪")

        // 失败注入（等价系统 didFailWithError，.denied 与 .locationUnknown 都要覆盖）。
        chain.manager.fail(.denied)
        chain.manager.fail(.locationUnknown)
        XCTAssertEqual(
            chain.source.lastLocationErrorCode,
            CLError.Code.locationUnknown.rawValue,
            "最近一次系统定位失败必须被记录，不得静默丢弃"
        )
        XCTAssertEqual(chain.viewModel.locationReadiness, .unavailable, "定位失败必须置不可用态")

        let readiness = chain.viewModel.locationReadiness
        XCTAssertEqual(readiness.messageKey, "run.status.locationUnavailable", "必须复用既有定位不可用文案键")
        XCTAssertEqual(readiness.message, L10n.locationUnavailable)
        XCTAssertFalse(readiness.message?.isEmpty ?? true, "不可用态必须有可见文案，不能只有内部状态")
        XCTAssertEqual(readiness.nextAction, .retry, "不可用态的唯一出口是既有 retry")
        let plan = RunInteractionPlan(
            state: .ready,
            readiness: readiness,
            metrics: .init(distance: "0", elapsed: "0", currentPace: "-", averagePace: "-", splitCount: "0")
        )
        XCTAssertEqual(plan.notice, .locationUnavailable, "不可用态必须在跑步页渲染定位提示行")

        // 反例（不改生产代码）：把同一次失败当作「无错误」——等价断开 didFailWithError 转发——
        // 同一判据退回 ready，上面的 unavailable 断言必然判红。
        let withoutErrorForwarding = RunLocationReadiness.resolve(
            authorization: .authorizedAlways,
            servicesEnabled: true,
            lastErrorCode: nil
        )
        XCTAssertEqual(withoutErrorForwarding, .ready, "反例：断开错误转发后是 ready，即原断言必红")
        XCTAssertNotEqual(withoutErrorForwarding, readiness)

        // 服务关闭前置检查：点「开始」不得启动更新，且同样落到既有 unavailable 态。
        chain.manager.locationServicesEnabled = false
        let startsBefore = chain.manager.startUpdatingCount
        chain.source.start()
        XCTAssertEqual(startsBefore, 1, "前置：授权后开始过恰一次更新（供服务关闭对照）")
        XCTAssertEqual(
            chain.manager.startUpdatingCount,
            startsBefore,
            "定位服务关闭时不得调用 startUpdatingLocation（去掉前置检查即必红）"
        )
        XCTAssertFalse(chain.source.locationServicesEnabled)
        XCTAssertEqual(chain.viewModel.locationReadiness, .unavailable, "服务关闭必须置不可用态")
    }

    /// ac-location-error 恢复面：服务恢复且重新 start 后旧错误被清掉，readiness 回到 ready。
    func testRecoveryAfterLocationFailureReturnsReady() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let chain = makeLocationChain(stores: stores)

        chain.manager.fail(.locationUnknown)
        XCTAssertEqual(chain.viewModel.locationReadiness, .unavailable)

        // 反例（不改生产代码）：若 start() 不清旧错误，同一输入会一直停在 unavailable。
        XCTAssertEqual(
            RunLocationReadiness.resolve(
                authorization: .authorizedAlways,
                servicesEnabled: true,
                lastErrorCode: CLError.Code.locationUnknown.rawValue
            ),
            .unavailable,
            "反例：残留错误时仍是 unavailable，恢复断言在此必红"
        )

        chain.viewModel.retryLocation()

        XCTAssertNil(chain.source.lastLocationErrorCode, "恢复成功后必须清掉旧错误，避免残留不可用态")
        XCTAssertEqual(chain.viewModel.locationReadiness, .ready)
        XCTAssertNil(chain.viewModel.locationReadiness.message, "恢复就绪后不得再显示不可用文案")
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

    // MARK: - ac-loc-searching / ac-loc-timeout / ac-loc-degrade

    /// ac-loc-degrade：唯一一条 >50m fix 在 15s 窗口到点后必须被接受，
    /// 不再依赖「必须再来一个回调」才结算（旧静默丢弃路径必红）。
    func testSingleImpreciseFixAcceptedAtWindowWithoutAnotherCallback() {
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
        XCTAssertTrue(recorder.samples.isEmpty, "窗口内不得接受 65m fix")
        XCTAssertEqual(source.filteredCallbackCount, 1)

        // 反例：只走到窗口前一刻仍是空，证明「到点主动结算」才是判绿点。
        now += RunLocationSource.accuracyFallbackWindowSeconds - 0.1
        source.flushPendingFallbackIfDue()
        XCTAssertTrue(recorder.samples.isEmpty, "反例：窗口未到点前接受即破坏现有护栏")

        now += 0.1
        source.flushPendingFallbackIfDue()
        XCTAssertEqual(recorder.samples.count, 1, "窗口到点必须主动接受最佳 fix，不等第二个回调")
        XCTAssertEqual(source.lastAcceptedAccuracyMeters, 65, "降级数必须如实标记真实精度")
    }

    /// ac-loc-searching / ac-loc-timeout：四类原因优先级与 30s 边界（纯函数断言）。
    func testLocationSearchStateTimesOutWithAttributableReason() {
        func resolve(
            elapsed: TimeInterval,
            authorization: RunLocationAuthorization = .authorizedAlways,
            services: Bool = true,
            raw: Int = 0,
            filtered: Int = 0
        ) -> RunLocationSearchState {
            RunLocationSearchState.resolve(
                isRunning: true,
                hasLocationData: false,
                elapsedSinceRecording: elapsed,
                authorization: authorization,
                servicesEnabled: services,
                rawCallbackCount: raw,
                filteredCallbackCount: filtered
            )
        }

        XCTAssertEqual(resolve(elapsed: 29.9), .searching, "30s 前必须显示搜索中，不提前报错")
        XCTAssertEqual(resolve(elapsed: 30), .timedOut(.noCallbacks))
        XCTAssertEqual(
            resolve(elapsed: 30, authorization: .denied),
            .timedOut(.unauthorized),
            "未授权优先于其它原因"
        )
        XCTAssertEqual(
            resolve(elapsed: 30, services: false),
            .timedOut(.servicesDisabled),
            "系统定位服务关闭必须单独归因"
        )
        XCTAssertEqual(
            resolve(elapsed: 30, raw: 5, filtered: 5),
            .timedOut(.accuracyFiltered),
            "回调全被精度过滤必须可归因"
        )
        XCTAssertEqual(
            RunLocationSearchState.resolve(
                isRunning: false,
                hasLocationData: false,
                elapsedSinceRecording: 60,
                authorization: .authorizedAlways,
                servicesEnabled: true,
                rawCallbackCount: 0,
                filteredCallbackCount: 0
            ),
            .idle,
            "非记录态不得显示搜索/超时"
        )
    }

    /// ac-loc-timeout：点重试只重启定位会话，计时与已累计数据不变。
    func testTimeoutRetryRestartsLocationWithoutResettingSession() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let source = SpyLocationSource(authorization: .authorizedWhenInUse)
        let probe = StubProbe(status: .authorizedWhenInUse)
        var date = startDate
        let clock = TestRunClockSource()
        clock.advance(to: startDate)
        let viewModel = RunSessionViewModel(
            checkpointStore: stores.checkpoint,
            archiveStore: stores.archive,
            locationSource: source,
            announcements: SilentSpeaker(),
            authorizationProbe: probe,
            countdownDuration: 0,
            now: { date },
            timeSource: clock,
            notificationCenter: NotificationCenter()
        )

        viewModel.start()
        XCTAssertEqual(viewModel.state, .running)
        date = startDate.addingTimeInterval(31)
        clock.advance(by: 31)
        viewModel.tick()
        XCTAssertEqual(viewModel.locationSearchState, .timedOut(.noCallbacks))
        XCTAssertEqual(
            viewModel.locationSearchMessage,
            L10n.runLocationSearchNoCallbacks,
            "超时必须有可读原因，不能空白"
        )

        let metricsBefore = viewModel.metrics
        let startsBefore = source.startCount
        viewModel.retryLocation()

        XCTAssertEqual(source.startCount, startsBefore + 1, "重试必须重启定位源")
        XCTAssertEqual(viewModel.metrics, metricsBefore, "重试不得重置计时/距离")
        XCTAssertEqual(viewModel.state, .running, "重试不得结束会话")
    }

    /// ac-loc-diagnostics / ac-loc-nostale：诊断字段同源、自洽，最近错误只在本会话出现。
    func testDiagnosticsSnapshotIsSelfConsistentAndSingleSourced() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let chain = makeLocationChain(stores: stores)

        XCTAssertNil(chain.viewModel.diagnosticsSnapshot().lastError, "无错误时最近错误必须为空")

        chain.source.locationManagerDidUpdate(payloads: [
            LocationPayload(
                latitude: 37.3349,
                longitude: -122.0090,
                altitude: nil,
                timestamp: startDate,
                horizontalAccuracy: 65
            ),
        ])
        chain.manager.fail(.network)
        let diagnostics = chain.viewModel.diagnosticsSnapshot()

        XCTAssertEqual(diagnostics.rawCallbackCount, chain.source.rawCallbackCount)
        XCTAssertEqual(diagnostics.filteredCallbackCount, chain.source.filteredCallbackCount)
        XCTAssertEqual(diagnostics.lastError?.domain, "kCLErrorDomain")
        XCTAssertEqual(diagnostics.lastError?.code, CLError.Code.network.rawValue)
        XCTAssertTrue(diagnostics.text.contains("网络不可用"), "最近错误必须带可读描述")
        XCTAssertTrue(diagnostics.text.contains("原始回调: 1"))
        XCTAssertTrue(diagnostics.text.contains("精度过滤丢弃: 1"))
        XCTAssertGreaterThanOrEqual(
            diagnostics.rawCallbackCount,
            diagnostics.filteredCallbackCount,
            "自洽：raw 回调数不得小于精度丢弃数"
        )
        XCTAssertLessThanOrEqual(
            diagnostics.filteredCallbackCount + diagnostics.sampleCount,
            diagnostics.rawCallbackCount,
            "自洽：丢弃 + 入库不得超过 raw 回调"
        )
        XCTAssertTrue(diagnostics.text.contains("定位服务: 开启"))

        chain.viewModel.retryLocation()
        XCTAssertNil(chain.viewModel.diagnosticsSnapshot().lastError, "重启会话成功后旧错误必须清空")
    }

    /// ac-loc-nostale：最近样本时间随入库样本推进，乱序样本不回退。
    func testLastSampleTimeNeverRegresses() {
        let stores = makeStores()
        defer { try? FileManager.default.removeItem(at: stores.root) }
        let source = SpyLocationSource(authorization: .authorizedWhenInUse)
        let probe = StubProbe(status: .authorizedWhenInUse)
        let viewModel = makeViewModel(stores: stores, source: source, probe: probe)
        viewModel.start()
        viewModel.advanceCountdown()

        viewModel.ingest(runSample(offset: 5))
        XCTAssertEqual(
            viewModel.diagnosticsSnapshot().lastSampleAt,
            startDate.addingTimeInterval(5)
        )

        // 反例输入：较旧时间戳必须被单调守卫丢弃，最近样本时间不得倒退。
        viewModel.ingest(runSample(offset: 3))
        XCTAssertEqual(
            viewModel.diagnosticsSnapshot().lastSampleAt,
            startDate.addingTimeInterval(5),
            "时间戳不前进的样本不得回退最近样本时间"
        )
    }

    private func runSample(offset: TimeInterval) -> RunSample {
        RunSample(
            latitude: 37.3349 + offset * 0.00009,
            longitude: -122.0090,
            altitude: nil,
            timestamp: startDate.addingTimeInterval(offset),
            heartRate: nil,
            cadence: nil
        )!
    }
}