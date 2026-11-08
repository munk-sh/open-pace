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
    func start()
    func stop()
}

@MainActor
protocol RunLocationSourceDelegate: AnyObject {
    func locationSource(_ source: RunLocationProviding, didProduce sample: RunSample)
    func locationSource(_ source: RunLocationProviding, didChangeAuthorization authorization: RunLocationAuthorization)
}

/// 真实 CoreLocation 数据源：授权 -> 前台采集 -> 过滤精度 -> 产出 `RunSample`。
/// 只做前台采集与配置声明，不承诺后台持续定位行为，也不伪造任何坐标。
@MainActor
final class RunLocationSource: NSObject, RunLocationProviding {
    /// 与阶段 2 Harness 一致的精度过滤阈值（米）。
    static let accuracyThresholdMeters: Double = 50.0

    weak var delegate: RunLocationSourceDelegate?
    private(set) var authorization: RunLocationAuthorization = .notDetermined

    private let manager = CLLocationManager()
    private var isUpdating = false
#if targetEnvironment(simulator)
    /// 仅模拟器（CI/本机测试）启用的定位链路诊断，不改授权与采样策略。
    private let diagnostics = RunLocationDiagnostics()
#endif

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        apply(manager.authorizationStatus)
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func apply(_ status: CLAuthorizationStatus) {
        let resolved = RunLocationAuthorization(status: status)
        authorization = resolved
        delegate?.locationSource(self, didChangeAuthorization: resolved)
        if resolved.isAuthorized {
            if !isUpdating {
                isUpdating = true
                manager.startUpdatingLocation()
            }
        } else {
            isUpdating = false
            manager.stopUpdatingLocation()
        }
#if targetEnvironment(simulator)
        diagnostics.authorization(resolved, updating: resolved.isAuthorized)
#endif
    }

    private func deliver(_ payloads: [LocationPayload]) {
        guard isUpdating else { return }
        for payload in payloads {
            guard payload.horizontalAccuracy >= 0,
                  payload.horizontalAccuracy <= RunLocationSource.accuracyThresholdMeters
            else {
#if targetEnvironment(simulator)
                diagnostics.filtered(accuracy: payload.horizontalAccuracy)
#endif
                continue
            }
            guard let sample = RunSample(
                latitude: payload.latitude,
                longitude: payload.longitude,
                altitude: payload.altitude,
                timestamp: payload.timestamp,
                heartRate: nil,
                cadence: nil
            ) else {
                continue
            }
#if targetEnvironment(simulator)
            diagnostics.sample(
                latitude: payload.latitude,
                longitude: payload.longitude,
                accuracy: payload.horizontalAccuracy
            )
#endif
            delegate?.locationSource(self, didProduce: sample)
        }
    }
}

/// `CLLocation` 不满足 `Sendable`，跨 actor 传回主线程前先转成可发送快照。
private struct LocationPayload: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date
    let horizontalAccuracy: Double
}

extension RunLocationSource: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.apply(status)
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
            self.deliver(payloads)
        }
    }
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
