import CoreLocation
import Foundation
import PurePaceRunCore

extension HarnessLocationAuthorization {
    init?(status: CLAuthorizationStatus) {
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
            return nil
        }
    }
}

/// 一次 `didUpdateLocations` 回调的可发送快照（CLLocation 本身不 Sendable）。
struct HarnessLocationPayload: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date
    let horizontalAccuracy: Double
}

/// CoreLocation 平台适配：授权 -> startUpdatingLocation -> 转成 RunSample 喂 HarnessCore。
/// 只做前台采集与配置声明，不承诺后台持续定位行为。
@MainActor
final class HarnessLocationController: NSObject {
    private let configuration: HarnessConfiguration
    private let manager = CLLocationManager()
    private var core: HarnessCore
    private var heartbeat: Timer?
    private var didStartUpdating = false
    private var didStop = false
    private let wallClockStart = Date()

    init(configuration: HarnessConfiguration) {
        self.configuration = configuration
        self.core = HarnessCore(
            mode: .corelocation,
            checkpointStore: RunCheckpointStore(fileURL: configuration.checkpointURL),
            appendsCheckpoints: true
        )
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        persist()
        let authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        handleAuthorization(authorizationStatus)
        // 授权被拒/受限时 handleAuthorization 已停采并置 didStop，不能再挂心跳定时器。
        guard !didStop else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        heartbeat = timer
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        heartbeat?.invalidate()
        heartbeat = nil
        manager.stopUpdatingLocation()
        persist()
    }

    private func tick() {
        guard !didStop else { return }
        if let limit = configuration.maxDurationSeconds,
           Date().timeIntervalSince(wallClockStart) >= limit {
            finishRun()
            return
        }
        persist()
    }

    private func finishRun() {
        guard !didStop else { return }
        core.finish(at: Date())
        didStop = true
        heartbeat?.invalidate()
        heartbeat = nil
        manager.stopUpdatingLocation()
        persist()
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        if let authorization = HarnessLocationAuthorization(status: status) {
            core.setLocationAuthorization(authorization)
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if !didStartUpdating, !didStop {
                didStartUpdating = true
                manager.startUpdatingLocation()
            }
        case .denied, .restricted:
            core.recordError(
                code: "locationUnauthorized",
                message: "定位授权不可用: \(HarnessLocationAuthorization(status: status)?.rawValue ?? "unknown")"
            )
            didStop = true
            heartbeat?.invalidate()
            heartbeat = nil
            manager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
        persist()
    }

    private func ingest(_ payloads: [HarnessLocationPayload]) {
        guard !didStop else { return }
        for payload in payloads {
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
            core.ingestLocation(sample, horizontalAccuracy: payload.horizontalAccuracy)
        }
        persist()
    }

    private func persist() {
        try? HarnessStatusWriter.write(core.status(), to: configuration.statusURL)
    }
}

extension HarnessLocationController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let payloads = locations.map { location in
            HarnessLocationPayload(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                timestamp: location.timestamp,
                horizontalAccuracy: location.horizontalAccuracy
            )
        }
        Task { @MainActor in
            self.ingest(payloads)
        }
    }
}
