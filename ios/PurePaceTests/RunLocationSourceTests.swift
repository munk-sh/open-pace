import CoreLocation
import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

@MainActor
final class RunLocationSourceTests: XCTestCase {
    // MARK: - 可注入桩

    private final class StubLocationManager: RunLocationManaging {
        weak var handler: RunLocationManagerHandler?
        var authorizationStatus: CLAuthorizationStatus = .notDetermined
        var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
        var distanceFilter: CLLocationDistance = 0
        var activityType: CLActivityType = .other
        var pausesLocationUpdatesAutomatically = true
        var allowsBackgroundLocationUpdates = false
        private(set) var whenInUseRequestCount = 0
        private(set) var alwaysRequestCount = 0
        private(set) var startUpdatingCount = 0
        private(set) var stopUpdatingCount = 0

        func requestWhenInUseAuthorization() {
            whenInUseRequestCount += 1
        }

        func requestAlwaysAuthorization() {
            alwaysRequestCount += 1
        }

        func startUpdatingLocation() {
            startUpdatingCount += 1
        }

        func stopUpdatingLocation() {
            stopUpdatingCount += 1
        }

        func drive(_ status: CLAuthorizationStatus) {
            authorizationStatus = status
            handler?.locationManagerAuthorizationChanged(to: status)
        }
    }

    private final class Recorder: RunLocationSourceDelegate {
        private(set) var authorizations: [RunLocationAuthorization] = []
        private(set) var samples: [RunSample] = []

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

    // MARK: - ac-plist-background-mode（bundle 读回）

    func testInfoPlistBackgroundModesContainsLocation() throws {
        let modes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
            "Info.plist 缺少 UIBackgroundModes"
        )
        XCTAssertTrue(
            modes.contains("location"),
            "Info.plist 的 UIBackgroundModes 未含 location，实际：\(modes)"
        )
        XCTAssertTrue(
            modes.contains("audio"),
            "Info.plist 的 UIBackgroundModes 未含 audio，实际：\(modes)"
        )
    }

    // MARK: - ac-bundle-id-readback（bundle 读回）

    func testInfoPlistBundleIdentifierIsFinalProductId() {
        let actual = Bundle.main.bundleIdentifier ?? "<nil>"
        XCTAssertEqual(
            actual,
            "sh.munk.purepace",
            "构建产物 Info.plist 的 CFBundleIdentifier 读回值为 \(actual)，期望 sh.munk.purepace"
        )
    }

    // MARK: - ac-bg-enabled-while-running / ac-bg-disabled-after-stop

    func testBackgroundUpdatesEnabledWhileRunningAndResetAfterStop() {
        let manager = StubLocationManager()
        manager.authorizationStatus = .authorizedAlways
        let source = RunLocationSource(manager: manager)

        source.start()

        XCTAssertTrue(manager.allowsBackgroundLocationUpdates, "跑步进行态必须开启后台定位更新")
        XCTAssertFalse(manager.pausesLocationUpdatesAutomatically, "必须关闭系统自动暂停更新")
        XCTAssertEqual(manager.startUpdatingCount, 1)
        XCTAssertEqual(source.authorization, .authorizedAlways)

        source.stop()

        XCTAssertFalse(manager.allowsBackgroundLocationUpdates, "结束/停止后必须复位后台定位更新")
        XCTAssertFalse(manager.pausesLocationUpdatesAutomatically, "结束/停止后必须复位系统自动暂停开关")
        XCTAssertEqual(manager.stopUpdatingCount, 1)
    }

    // MARK: - 强引用持有（manager + delegate 不被回收）

    func testSystemManagerRetainsLocationManagerAndDelegate() throws {
        let source = RunLocationSource()
        let manager = source.retainedManager
        let system = try XCTUnwrap(manager as? SystemLocationManager, "生产默认应注入 SystemLocationManager")

        XCTAssertNotNil(system.underlyingManager, "CLLocationManager 必须被强引用持有")
        XCTAssertTrue(system.isDelegateAttached, "CLLocationManager.delegate 必须绑定到持有的包装对象")

        source.stop()

        XCTAssertTrue(source.retainedManager === manager, "停止后数据源仍须强引用同一 manager")
        XCTAssertFalse(system.underlyingManager.allowsBackgroundLocationUpdates)
    }

    // MARK: - ac-always-request-path

    func testNotDeterminedRequestsWhenInUseFirst() {
        let manager = StubLocationManager()
        let source = RunLocationSource(manager: manager)

        source.start()

        XCTAssertEqual(manager.whenInUseRequestCount, 1)
        XCTAssertEqual(manager.alwaysRequestCount, 0)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
    }

    func testWhenInUseRequestsAlwaysUpgradeOnlyOnce() {
        let manager = StubLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let source = RunLocationSource(manager: manager)

        source.start()
        XCTAssertEqual(manager.whenInUseRequestCount, 0)
        XCTAssertEqual(manager.alwaysRequestCount, 1, "已 WhenInUse 时必须存在 Always 升级请求路径")
        XCTAssertEqual(source.authorization, .authorizedWhenInUse)

        source.start()
        XCTAssertEqual(manager.alwaysRequestCount, 1, "同一数据源实例不得重复发起 Always 升级请求")
    }

    // MARK: - ac-wheninuse-degraded-visible / ac-auth-transitions-injectable

    func testAuthorizationTransitionsForwardedAndDegradedHintVisible() {
        let manager = StubLocationManager()
        let source = RunLocationSource(manager: manager)
        let recorder = Recorder()
        source.delegate = recorder

        source.start()
        XCTAssertEqual(recorder.authorizations, [.notDetermined])

        manager.drive(.authorizedWhenInUse)
        XCTAssertEqual(source.authorization, .authorizedWhenInUse)
        XCTAssertFalse(source.authorization.backgroundCapable, "WhenInUse 必须标记为后台能力不足")
        XCTAssertNotNil(source.authorization.backgroundDegradationHint, "WhenInUse 降级态必须有明确提示文案")
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)

        manager.drive(.authorizedAlways)
        XCTAssertEqual(source.authorization, .authorizedAlways)
        XCTAssertTrue(source.authorization.backgroundCapable)
        XCTAssertNil(source.authorization.backgroundDegradationHint, "已获得 Always 后不得再提示降级")

        XCTAssertEqual(
            recorder.authorizations,
            [.notDetermined, .authorizedWhenInUse, .authorizedAlways],
            "每次授权变化都必须回调 delegate"
        )
    }

    func testDeniedAndRestrictedDisableUpdatesAndForwardAuthorization() {
        let manager = StubLocationManager()
        manager.authorizationStatus = .authorizedAlways
        let source = RunLocationSource(manager: manager)
        let recorder = Recorder()
        source.delegate = recorder

        source.start()
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)

        manager.drive(.denied)
        XCTAssertEqual(source.authorization, .denied)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)

        manager.drive(.restricted)
        XCTAssertEqual(source.authorization, .restricted)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)

        XCTAssertEqual(recorder.authorizations, [.authorizedAlways, .denied, .restricted])
        XCTAssertGreaterThanOrEqual(manager.stopUpdatingCount, 2)
    }

    // MARK: - ac-loc-bg-flags-counterexample（脏值预置即回归夹具）

    func testStopResetsDirtyBackgroundFlagsIncludingAutoPause() {
        let manager = StubLocationManager()
        manager.authorizationStatus = .authorizedAlways
        let source = RunLocationSource(manager: manager)

        // 回归夹具：把两个开关预置为「脏」值，生产漏掉任一复位即判红。
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true

        source.stop()

        XCTAssertFalse(manager.allowsBackgroundLocationUpdates, "stop 后必须复位后台更新开关")
        XCTAssertFalse(manager.pausesLocationUpdatesAutomatically, "stop 后必须复位自动暂停开关")
    }

    // MARK: - ac-loc-manager-delegate-retained

    private final class WeakBox<Value: AnyObject> {
        weak var value: Value?
    }

    private struct WeakReferences {
        let underlying: WeakBox<CLLocationManager>
        let delegateObject: WeakBox<AnyObject>
    }

    /// 在独立函数作用域内构造并释放数据源，返回仅含弱引用的观察盒。
    private func makeReleasedWeakReferences() throws -> WeakReferences {
        let underlying = WeakBox<CLLocationManager>()
        let delegateObject = WeakBox<AnyObject>()
        try autoreleasepool {
            let source = RunLocationSource()
            let manager = try XCTUnwrap(source.retainedManager as? SystemLocationManager, "生产默认应注入 SystemLocationManager")
            underlying.value = manager.underlyingManager
            delegateObject.value = manager.underlyingManager.delegate as AnyObject?

            XCTAssertNotNil(underlying.value, "数据源存活期间 CLLocationManager 必须被强引用")
            XCTAssertNotNil(delegateObject.value, "CLLocationManager.delegate 必须绑定持有包装对象")
            XCTAssertTrue(manager.isDelegateAttached)
            XCTAssertTrue(source.retainedManager === manager, "强引用身份不得被替换")
        }
        return WeakReferences(underlying: underlying, delegateObject: delegateObject)
    }

    func testManagerAndDelegateWeakReferencesDieWithSource() throws {
        let references = try makeReleasedWeakReferences()

        XCTAssertNil(references.delegateObject.value, "包装对象释放后 delegate 弱引用链必须断开")
        XCTAssertNil(references.underlying.value, "释放 source 后底层 CLLocationManager 不得被额外强引用")
    }

    // MARK: - ac-auth-always-upgrade / ac-auth-wheninuse-degraded

    func testAlwaysUpgradeClearsDegradedHint() {
        let degraded = RunLocationAuthorization.authorizedWhenInUse
        let upgraded = RunLocationAuthorization.authorizedAlways

        XCTAssertNotEqual(
            degraded.backgroundDegradationHint,
            upgraded.backgroundDegradationHint,
            "升级到 Always 后降级提示必须与 WhenInUse 态区分（应为 nil）"
        )
        XCTAssertNil(upgraded.backgroundDegradationHint)
        XCTAssertTrue(upgraded.backgroundCapable)
    }

    func testWhenInUseDegradedCounterexample() {
        let degraded = RunLocationAuthorization.authorizedWhenInUse
        let upgraded = RunLocationAuthorization.authorizedAlways

        XCTAssertNotEqual(
            degraded.backgroundCapable,
            upgraded.backgroundCapable,
            "降级态若 backgroundCapable == true 会与 Always 无法区分，必须判红"
        )
        XCTAssertNotEqual(
            degraded.backgroundDegradationHint == nil,
            upgraded.backgroundDegradationHint == nil,
            "降级态若缺提示会与 Always 无法区分，必须判红"
        )
    }

    // MARK: - ac-bg-ingest-continuous

    func testBackgroundResumeIngestRejectsOverlapWithoutLosingSegments() throws {
        let base: TimeInterval = 1_700_000_000
        let baseLatitude = 31.0
        let step = 0.00027
        let samples = (1...12).map { index in
            sample(latitude: baseLatitude + step * Double(index), timestamp: base + Double(index))
        }

        // 第一段：跑到第 8 个样本后落盘 checkpoint（复用既有持久化契约）。
        var first = RunMetricsEngine()
        first.start(at: Date(timeIntervalSince1970: base))
        for sample in samples.prefix(8) {
            _ = first.ingest(sample)
        }
        let checkpoint = try XCTUnwrap(
            RunCheckpoint(
                state: .running,
                completedDistance: first.metrics.distance,
                elapsed: first.metrics.elapsed,
                splits: first.metrics.splits,
                recordedAt: samples[7].timestamp,
                lastSample: first.lastAcceptedSample
            )
        )

        // 恢复基准：只投递唯一的新样本。
        var clean = RunMetricsEngine(restoring: checkpoint)
        clean.resume(at: samples[7].timestamp)
        for sample in samples.dropFirst(8) {
            _ = clean.ingest(sample)
        }

        // 锁屏/后台挂起恢复：先重复投递重叠时间窗，再继续剩余样本。
        var replayed = RunMetricsEngine(restoring: checkpoint)
        replayed.resume(at: samples[7].timestamp)
        for sample in samples[5...9] {
            _ = replayed.ingest(sample)
        }
        for sample in samples.dropFirst(10) {
            _ = replayed.ingest(sample)
        }

        XCTAssertEqual(
            replayed.metrics,
            clean.metrics,
            "后台恢复的重叠投递不得造成重复累计或丢失段落"
        )
        XCTAssertEqual(replayed.lastAcceptedSample?.timestamp, samples.last?.timestamp)
        XCTAssertEqual(replayed.metrics.splits.count, clean.metrics.splits.count)
        XCTAssertGreaterThanOrEqual(
            replayed.metrics.distance.meters,
            checkpoint.completedDistance.meters,
            "恢复后距离不得回退"
        )
    }

    // MARK: - Helpers

    private func sample(latitude: Double, timestamp: TimeInterval) -> RunSample {
        RunSample(
            latitude: latitude,
            longitude: 121.0,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: timestamp),
            heartRate: nil,
            cadence: nil
        )!
    }
}
