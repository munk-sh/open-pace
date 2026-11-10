import Foundation
import PurePaceRunCore

/// Release 候选包设备验证场使用的确定性定位源（显式 launch-arg 门控，默认关）。
///
/// 存在的唯一理由：Release 候选包上 Debug 专用的 `-uiTestLocation` 不可用，设备静止也走不出
/// 1 km，跨公里播报只能在 Debug 构建取到机器证据。本类型只实现既有 `RunLocationProviding`
/// 契约，不导入系统定位框架、不读写磁盘、不做播报、不请求任何授权；
/// 未传 `-releaseDeterministicLocation` 时根本不会被构造（见 `RunLocationSourceSelection`）。
@MainActor
final class ReleaseDeterministicLocationSource: RunLocationProviding {
    /// 显式门控参数名；正常用户路径不传即真实 CoreLocation。
    nonisolated static let flag = "-releaseDeterministicLocation"

    /// 每 tick 的时间间隔与位移：1.0 s 推进 20 m，约 50 步跨过 1 km。
    nonisolated static let tickInterval: TimeInterval = 1.0
    nonisolated static let stepMetersPerTick: Double = 20.0

    /// 与 `GeoDistance` 同一球面口径的「1 度纬度 = 多少米」，保证每 tick 恰约 20 m。
    private nonisolated static let metersPerDegreeLatitude = GeoDistance.earthRadiusMeters * Double.pi / 180.0
    nonisolated static let latitudeStepPerTick = stepMetersPerTick / metersPerDegreeLatitude

    /// `km-crossing` 场景的固定基准坐标（经度不变，只推进纬度）。
    nonisolated static let baseLatitude = 37.334900
    nonisolated static let baseLongitude = -122.009000

    /// 场景枚举：只接受显式合法值，未知值由调用方 fail-closed 回真实源。
    enum Scenario: String, CaseIterable, Sendable {
        case kmCrossing = "km-crossing"
    }

    weak var delegate: RunLocationSourceDelegate?
    private(set) var authorization: RunLocationAuthorization = .authorizedWhenInUse

    let scenario: Scenario
    private let now: () -> Date
    private let schedulesTicks: Bool
    private var startedAt: Date?
    private var tick = 0
    private var isRunning = false
    private var timer: Timer?

    /// - Parameters:
    ///   - scenario: 确定性轨迹场景。
    ///   - now: 时钟 seam；单测注入固定时间即可断言时序，无需 `sleep`。
    ///   - schedulesTicks: 生产走 `Timer`；单测关掉后由 `advanceTick()` 手动驱动。
    init(
        scenario: Scenario = .kmCrossing,
        now: @escaping () -> Date = Date.init,
        schedulesTicks: Bool = true
    ) {
        self.scenario = scenario
        self.now = now
        self.schedulesTicks = schedulesTicks
    }

    var sampleSource: RunSampleSource { .simulated }

    /// 确定性源不触碰系统定位管理器，如实记录 false/false 而不伪造后台能力。
    var allowsBackgroundLocationUpdates: Bool { false }
    var pausesLocationUpdatesAutomatically: Bool { false }

    func start() {
        delegate?.locationSource(self, didChangeAuthorization: authorization)
        guard !isRunning else { return }
        isRunning = true
        startedAt = now()
        emit()
        guard schedulesTicks else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceTick()
            }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// 推进一个 tick 并向 delegate 投递样本；生产由 `Timer` 调用，单测直接手动驱动。
    func advanceTick() {
        emit()
    }

    private func emit() {
        guard isRunning, let startedAt else { return }
        let sample = Self.sample(scenario: scenario, tick: tick, startedAt: startedAt)
        tick += 1
        guard let sample else { return }
        delegate?.locationSource(self, didProduce: sample)
    }

    /// 纯 tick → 样本生成（无 Timer、无 IO）：生产与单测共用同一时序/位移口径。
    ///
    /// 时间戳由 `startedAt + tick × tickInterval` 计算，因此相邻样本严格相差 1.0 s；
    /// tick 0 为跑步开始后的首个位置锚点，距离从下一条样本起累计。
    nonisolated static func sample(scenario: Scenario, tick: Int, startedAt start: Date) -> RunSample? {
        let latitude: Double
        switch scenario {
        case .kmCrossing:
            latitude = baseLatitude + Double(tick) * latitudeStepPerTick
        }
        return RunSample(
            latitude: latitude,
            longitude: baseLongitude,
            altitude: 0,
            timestamp: start.addingTimeInterval(Double(tick) * tickInterval),
            heartRate: nil,
            cadence: nil
        )
    }
}
