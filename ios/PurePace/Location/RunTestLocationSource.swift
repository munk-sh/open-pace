import Foundation
import PurePaceRunCore

#if DEBUG
/// 仅 DEBUG 且由启动参数 `-uiTestLocation` 门控的确定性测试定位源。
///
/// 存在的唯一理由：hosted runner 的隐藏式 simulator 定位投递不可靠（每个 session 只投递
/// 一个缓存点），UI 测试不能依赖它。本类型只实现既有 `RunLocationProviding` 契约，
/// 不读写磁盘、不做播报、不触碰 `CoreLocation`；Release 构建完全不编译此类型。
@MainActor
final class RunTestLocationSource: RunLocationProviding {
    weak var delegate: RunLocationSourceDelegate?
    private(set) var authorization: RunLocationAuthorization = .authorizedWhenInUse

    /// 基准坐标与推进量：纬度每秒 +0.000090 度（约 10 m/s）。
    private static let baseLatitude = 37.334900
    private static let baseLongitude = -122.009000
    private static let latitudeStepPerSecond = 0.000090
    private static let interval: TimeInterval = 1.0

    private var tick = 0
    private var isRunning = false
    private var timer: Timer?

    func start() {
        delegate?.locationSource(self, didChangeAuthorization: authorization)
        guard !isRunning else { return }
        isRunning = true
        // 首个样本立即产出（≤1s），之后约每秒一个。
        emit()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emit()
            }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func emit() {
        guard isRunning else { return }
        let latitude = Self.baseLatitude + Double(tick) * Self.latitudeStepPerSecond
        tick += 1
        guard let sample = RunSample(
            latitude: latitude,
            longitude: Self.baseLongitude,
            altitude: 0,
            timestamp: Date(),
            heartRate: nil,
            cadence: nil
        ) else {
            return
        }
        delegate?.locationSource(self, didProduce: sample)
    }
}
#endif
