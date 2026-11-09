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

    /// 基准坐标：纬度每秒推进，步进由模式决定（约 10 m/s 为默认，快速模式用于跨公里边界）。
    private static let baseLatitude = 37.334900
    private static let baseLongitude = -122.009000
    private static let defaultStepPerTick = 0.000090
    private static let fastStepPerTick = 0.001500
    private static let defaultInterval: TimeInterval = 1.0
    private static let fastInterval: TimeInterval = 0.5

    /// `-uiTestLocationFast` 只在该测试源内生效，不改变既有 `-uiTestLocation` 默认节奏。
    private let stepPerTick: Double
    private let interval: TimeInterval

    private var tick = 0
    private var isRunning = false
    private var timer: Timer?

    init(arguments: [String] = CommandLine.arguments) {
        let fast = arguments.contains("-uiTestLocationFast")
        stepPerTick = fast ? Self.fastStepPerTick : Self.defaultStepPerTick
        interval = fast ? Self.fastInterval : Self.defaultInterval
    }

    var sampleSource: RunSampleSource { .simulated }

    /// 确定性测试源不触碰 `CLLocationManager`，如实记录 false/false 而不伪造后台能力。
    var allowsBackgroundLocationUpdates: Bool { false }
    var pausesLocationUpdatesAutomatically: Bool { false }

    func start() {
        delegate?.locationSource(self, didChangeAuthorization: authorization)
        guard !isRunning else { return }
        isRunning = true
        // 首个样本立即产出（≤1s），之后按模式节奏推进。
        emit()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
        let latitude = Self.baseLatitude + Double(tick) * stepPerTick
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
