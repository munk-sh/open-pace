import CoreLocation
import Foundation
import PurePaceRunCore

/// 定位授权状态的可观测快照（与 `CLAuthorizationStatus` 一一对应）。
enum RunLocationAuthorization: String, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways

    var isAuthorized: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }

    /// 与 `CLAuthorizationStatus` 原始值一致的整数映射（遥测自证用）。
    var clRawValue: Int {
        switch self {
        case .notDetermined: return 0
        case .restricted: return 1
        case .denied: return 2
        case .authorizedAlways: return 3
        case .authorizedWhenInUse: return 4
        }
    }

    /// 只有 `Always` 授权才具备后台锁屏连续定位能力；`WhenInUse` 视为降级。
    var backgroundCapable: Bool {
        self == .authorizedAlways
    }

    /// 授权降级时给用户的明确提示；仅在 `WhenInUse` 降级态返回文案。
    var backgroundDegradationHint: String? {
        guard self == .authorizedWhenInUse else { return nil }
        return L10n.backgroundDegradedHint
    }

    init(status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorizedWhenInUse:
            self = .authorizedWhenInUse
        case .authorizedAlways:
            self = .authorizedAlways
        @unknown default:
            self = .notDetermined
        }
    }
}

/// 定位数据源对外契约，便于 `PurePaceTests` 注入假采样源做进程内断言。
@MainActor
protocol RunLocationProviding: AnyObject {
    var delegate: RunLocationSourceDelegate? { get set }
    var authorization: RunLocationAuthorization { get }
    /// 本数据源产出的采样点来源（`device` / `simulated`），供遥测如实记录。
    var sampleSource: RunSampleSource { get }
    /// 跑步进行态的后台更新开关快照（真实源反映 manager，测试源如实为 false）。
    var allowsBackgroundLocationUpdates: Bool { get }
    /// 跑步进行态的系统自动暂停开关快照。
    var pausesLocationUpdatesAutomatically: Bool { get }
    func start()
    func stop()
    /// 系统 WhenInUse 权限请求（notDetermined 时由「开始」显式触发，不得被 App 内告知同意短路）。
    func requestWhenInUseAuthorization()
    /// 系统 Always 升级请求（必须先有 WhenInUse 且在跑步进行中）。
    func requestAlwaysAuthorization()
    /// 系统原始定位回调条数（含随后被精度过滤丢弃的）。
    var rawCallbackCount: Int { get }
    /// 因精度超过阈值被整条丢弃的回调条数。
    var filteredCallbackCount: Int { get }
    /// 最近一条被接受 fix 的水平精度（米）；nil 表示尚未拿到 fix。
    var lastAcceptedAccuracyMeters: Double? { get }
    /// 系统定位服务当前是否开启；关闭时数据源不得启动更新。
    var locationServicesEnabled: Bool { get }
    /// 最近一次系统定位错误码（`CLError.rawValue`）；nil 表示无错误。
    var lastLocationErrorCode: Int? { get }
}

extension RunLocationProviding {
    /// 测试桩/确定性源默认无系统弹窗，显式空实现避免每个 fake 重复样板。
    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    var rawCallbackCount: Int { 0 }
    var filteredCallbackCount: Int { 0 }
    var lastAcceptedAccuracyMeters: Double? { nil }
    var locationServicesEnabled: Bool { true }
    var lastLocationErrorCode: Int? { nil }
}

@MainActor
protocol RunLocationSourceDelegate: AnyObject {
    func locationSource(_ source: RunLocationProviding, didProduce sample: RunSample)
    func locationSource(_ source: RunLocationProviding, didChangeAuthorization authorization: RunLocationAuthorization)
}

/// `CLLocationManager` 的最小可替换 seam：授权状态/请求 + 更新开关 + 后台属性。
///
/// 生产默认实现为 `SystemLocationManager`；测试注入桩即可驱动授权迁移与后台属性断言。
@MainActor
protocol RunLocationManaging: AnyObject {
    var handler: RunLocationManagerHandler? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var activityType: CLActivityType { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    /// 系统定位服务开关；`false` 时不启动更新，交由 readiness 呈现「定位不可用」。
    var locationServicesEnabled: Bool { get }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension RunLocationManaging {
    /// 测试桩默认视为系统定位服务开启；生产实现读系统真值。
    var locationServicesEnabled: Bool { true }
}

/// `RunLocationManaging` 向数据源回传授权/样本的窄回调。
@MainActor
protocol RunLocationManagerHandler: AnyObject {
    func locationManagerAuthorizationChanged(to status: CLAuthorizationStatus)
    func locationManagerDidUpdate(payloads: [LocationPayload])
    /// 系统定位失败（`didFailWithError`）：只上报 `CLError` 原始码，不伪造样本。
    func locationManagerDidFail(code: Int)
}

/// 真实 CoreLocation 数据源：授权 -> 采集 -> 过滤精度 -> 产出 `RunSample`。
///
/// 跑步进行态开启后台更新（`allowsBackgroundLocationUpdates = true`），结束/停止时复位，
/// 不在代码层伪造坐标或承诺未经真机验收的后台行为。
@MainActor
final class RunLocationSource: RunLocationProviding, RunLocationManagerHandler {
    /// 正常接受阈值（米）：`kCLLocationAccuracyBest` 在开阔路面的典型误差上界。
    static let accuracyThresholdMeters: Double = 50.0
    /// 有界降级窗口（秒）：自 `startUpdatingLocation` 起一直无 ≤50m fix 时，
    /// 窗口末接受「当前可得的最佳 fix」并标记其 accuracy。
    ///
    /// 推导（先定后测，禁止红了再调）：室内/高楼遮挡常见 65–120m；15s 足以覆盖
    /// 「开始后走出电梯/门口」的短暂遮挡，又不会让用户长时间面对 0 距离。
    static let accuracyFallbackWindowSeconds: TimeInterval = 15.0
    /// 降级可接受的精度上限（米）：超过 200m 已到蜂窝/基站级粗定位，接受它会伪造轨迹，宁可继续等。
    static let accuracyFallbackCeilingMeters: Double = 200.0

    weak var delegate: RunLocationSourceDelegate?
    private(set) var authorization: RunLocationAuthorization = .notDetermined

    private let manager: RunLocationManaging
    /// 单调读数注入点（默认系统时钟），只用于降级窗口判定，不参与会话计时。
    private let uptime: () -> TimeInterval
    private var isUpdating = false
    private var updatingStartedAt: TimeInterval?
    private var pendingFallbackPayload: LocationPayload?
    private var didRequestAlwaysAuthorization = false
    private var didRequestWhenInUseAuthorization = false
#if targetEnvironment(simulator)
    /// 仅模拟器（CI/本机测试）启用的定位链路诊断，不改授权与采样策略。
    private let diagnostics = RunLocationDiagnostics()
#endif

    convenience init() {
        self.init(manager: SystemLocationManager())
    }

    /// 测试可注入 `RunLocationManaging` 桩与单调读数。
    init(
        manager: RunLocationManaging,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.manager = manager
        self.uptime = uptime
        manager.handler = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// 强引用持有证明：数据源生命周期内 manager 不得被回收（供 XCTest 断言）。
    var retainedManager: RunLocationManaging {
        manager
    }

    var sampleSource: RunSampleSource { .device }

    /// 原始回调 / 被精度过滤丢弃的条数：诊断区可归因「室内全滤掉」。
    private(set) var rawCallbackCount = 0
    private(set) var filteredCallbackCount = 0
    /// 最近一条被接受 fix 的水平精度（米）；nil 表示尚未拿到任何 fix。
    private(set) var lastAcceptedAccuracyMeters: Double?
    /// 最近一次探测到的系统定位服务开关（`start()` 时刷新）。
    private(set) var locationServicesEnabled = true
    /// 最近一次系统定位错误码（`CLError.rawValue`）；成功后在下一次 `start()` 清空。
    private(set) var lastLocationErrorCode: Int?

    var allowsBackgroundLocationUpdates: Bool {
        manager.allowsBackgroundLocationUpdates
    }

    var pausesLocationUpdatesAutomatically: Bool {
        manager.pausesLocationUpdatesAutomatically
    }

    func start() {
        // 前置检查：系统定位服务被关闭时不得启动更新，也不得把「无数据」当正常态。
        let servicesEnabled = manager.locationServicesEnabled
        locationServicesEnabled = servicesEnabled
        guard servicesEnabled else {
            endUpdating()
            return
        }
        lastLocationErrorCode = nil
        let status = manager.authorizationStatus
        apply(status)
        switch status {
        case .notDetermined:
            requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysAuthorization()
        case .restricted, .denied, .authorizedAlways:
            break
        @unknown default:
            break
        }
    }

    /// 每个数据源实例只发起一次系统 WhenInUse 请求（避免 onAppear 与「开始」双触发）。
    func requestWhenInUseAuthorization() {
        guard !didRequestWhenInUseAuthorization else { return }
        didRequestWhenInUseAuthorization = true
        manager.requestWhenInUseAuthorization()
    }

    /// 每个数据源实例只发起一次系统 Always 升级请求。
    func requestAlwaysAuthorization() {
        guard !didRequestAlwaysAuthorization else { return }
        didRequestAlwaysAuthorization = true
        manager.requestAlwaysAuthorization()
    }

    func stop() {
        endUpdating()
    }

    private func apply(_ status: CLAuthorizationStatus) {
        let resolved = RunLocationAuthorization(status: status)
        authorization = resolved
        delegate?.locationSource(self, didChangeAuthorization: resolved)
        if resolved.isAuthorized {
            beginUpdating()
        } else {
            endUpdating()
        }
#if targetEnvironment(simulator)
        diagnostics.authorization(resolved, updating: resolved.isAuthorized)
#endif
    }

    private func beginUpdating() {
        guard !isUpdating else { return }
        isUpdating = true
        updatingStartedAt = uptime()
        pendingFallbackPayload = nil
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func endUpdating() {
        isUpdating = false
        updatingStartedAt = nil
        pendingFallbackPayload = nil
        manager.allowsBackgroundLocationUpdates = false
        // 停止时把自动暂停开关一并复位，避免残留脏值影响下一次开始的策略快照。
        manager.pausesLocationUpdatesAutomatically = false
        manager.stopUpdatingLocation()
    }

    private func deliver(_ payloads: [LocationPayload]) {
        guard isUpdating else { return }
        rawCallbackCount += payloads.count
        for payload in payloads {
            guard payload.horizontalAccuracy >= 0 else {
                filteredCallbackCount += 1
                continue
            }
            if payload.horizontalAccuracy <= RunLocationSource.accuracyThresholdMeters {
                pendingFallbackPayload = nil
                accept(payload)
                continue
            }
            filteredCallbackCount += 1
#if targetEnvironment(simulator)
            diagnostics.filtered(accuracy: payload.horizontalAccuracy)
#endif
            // 记下窗口内「最佳可得」fix；窗口到点才接受，且不得宽于 200m 上限。
            if let pending = pendingFallbackPayload {
                if payload.horizontalAccuracy < pending.horizontalAccuracy {
                    pendingFallbackPayload = payload
                }
            } else {
                pendingFallbackPayload = payload
            }
            guard let pending = pendingFallbackPayload,
                  let startedAt = updatingStartedAt,
                  uptime() - startedAt >= RunLocationSource.accuracyFallbackWindowSeconds,
                  pending.horizontalAccuracy <= RunLocationSource.accuracyFallbackCeilingMeters
            else { continue }
            pendingFallbackPayload = nil
            accept(pending)
        }
    }

    /// 造样本并下发给 delegate；同时记录该 fix 的精度，供「明确精度状态」展示。
    private func accept(_ payload: LocationPayload) {
        guard let sample = RunSample(
            latitude: payload.latitude,
            longitude: payload.longitude,
            altitude: payload.altitude,
            timestamp: payload.timestamp,
            heartRate: nil,
            cadence: nil
        ) else {
            return
        }
        lastAcceptedAccuracyMeters = payload.horizontalAccuracy
#if targetEnvironment(simulator)
        diagnostics.sample(
            latitude: payload.latitude,
            longitude: payload.longitude,
            accuracy: payload.horizontalAccuracy
        )
#endif
        delegate?.locationSource(self, didProduce: sample)
    }

    // MARK: - RunLocationManagerHandler

    func locationManagerAuthorizationChanged(to status: CLAuthorizationStatus) {
        apply(status)
    }

    func locationManagerDidUpdate(payloads: [LocationPayload]) {
        deliver(payloads)
    }

    /// 系统定位失败：记录原始错误码供 readiness 呈现，不静默丢弃。
    func locationManagerDidFail(code: Int) {
        lastLocationErrorCode = code
    }
}

/// 生产环境 seam 实现：把 `CLLocationManager` 包装为可注入协议。
///
/// 强引用持有 `CLLocationManager` 并自任 delegate（CoreLocation 的 delegate 为弱引用，
/// 因此必须由本包装类型与数据源共同保活）。
@MainActor
final class SystemLocationManager: NSObject, RunLocationManaging {
    weak var handler: RunLocationManagerHandler?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    /// 被强引用持有的系统 manager；供 XCTest 断言对象存活与 delegate 绑定。
    var underlyingManager: CLLocationManager {
        manager
    }

    var isDelegateAttached: Bool {
        (manager.delegate as AnyObject?) === self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// 系统级定位服务开关（与单 App 授权解耦：关掉服务时任何授权都不产出样本）。
    var locationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    var desiredAccuracy: CLLocationAccuracy {
        get { manager.desiredAccuracy }
        set { manager.desiredAccuracy = newValue }
    }

    var distanceFilter: CLLocationDistance {
        get { manager.distanceFilter }
        set { manager.distanceFilter = newValue }
    }

    var activityType: CLActivityType {
        get { manager.activityType }
        set { manager.activityType = newValue }
    }

    var pausesLocationUpdatesAutomatically: Bool {
        get { manager.pausesLocationUpdatesAutomatically }
        set { manager.pausesLocationUpdatesAutomatically = newValue }
    }

    var allowsBackgroundLocationUpdates: Bool {
        get { manager.allowsBackgroundLocationUpdates }
        set { manager.allowsBackgroundLocationUpdates = newValue }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension SystemLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handler?.locationManagerAuthorizationChanged(to: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let payloads = locations.map { location in
            LocationPayload(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                timestamp: location.timestamp,
                horizontalAccuracy: location.horizontalAccuracy
            )
        }
        Task { @MainActor in
            self.handler?.locationManagerDidUpdate(payloads: payloads)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        let code = clError.code.rawValue
        Task { @MainActor in
            self.handler?.locationManagerDidFail(code: code)
        }
    }
}

/// `CLLocation` 不满足 `Sendable`，跨 actor 传回主线程前先转成可发送快照。
struct LocationPayload: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date
    let horizontalAccuracy: Double
}

#if targetEnvironment(simulator)
/// 仅模拟器（CI/本机测试）启用的定位链路诊断：把授权状态与样本投递计数追加写入
/// App 沙盒 `Documents/location-diagnostics.log`，供 `scripts/test-ios.sh` 在测试后回读，
/// 使「授权是否被拒 / 是否收到样本」可在脚本日志与 xcresult 中取证；不进入真机行为。
@MainActor
private final class RunLocationDiagnostics {
    private let fileURL: URL
    private var sampleCount = 0
    private var filteredCount = 0
    private var hasSessionHeader = false

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = documents.appendingPathComponent("location-diagnostics.log")
    }

    func authorization(_ status: RunLocationAuthorization, updating: Bool) {
        append("authorization=\(status.rawValue) updating=\(updating)")
    }

    func sample(latitude: Double, longitude: Double, accuracy: Double) {
        sampleCount += 1
        guard sampleCount == 1 || sampleCount % 5 == 0 else { return }
        append(
            "sample count=\(sampleCount)"
                + " lat=\(Self.format(latitude, digits: 6))"
                + " lon=\(Self.format(longitude, digits: 6))"
                + " accuracy=\(Self.format(accuracy, digits: 1))"
        )
    }

    func filtered(accuracy: Double) {
        filteredCount += 1
        guard filteredCount == 1 else { return }
        append("filtered accuracy=\(Self.format(accuracy, digits: 1)) total=\(filteredCount)")
    }

    private func append(_ message: String) {
        let entry: String
        if hasSessionHeader {
            entry = "[location] \(message)\n"
        } else {
            hasSessionHeader = true
            entry = "[location] === session start ===\n[location] \(message)\n"
        }
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }

    private static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
#endif
