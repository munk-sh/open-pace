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
    }

    private func deliver(_ payloads: [LocationPayload]) {
        guard isUpdating else { return }
        for payload in payloads {
            guard payload.horizontalAccuracy >= 0,
                  payload.horizontalAccuracy <= RunLocationSource.accuracyThresholdMeters
            else {
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
