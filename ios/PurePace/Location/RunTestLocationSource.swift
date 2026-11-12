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

    /// `-uiTestLocationTargetMeters <m>`：把累计距离锁死在给定米数，结束态分段行数
    /// = `floor(m / 1000)` 只由启动参数决定，与 runner 墙钟快慢无关。
    ///
    /// 存在理由（2026-11-12 归因）：跑动距离由本测试源的 tick 数驱动，tick 数 = 墙钟时间 × 1 Hz；
    /// 同一份用例在 CI 慢机器上多跑 ≥100s 就多跨一个 1km 边界、多出一行分段（约 20pt），
    /// 把结束态内容顶出可用区（CI 实测 `top=36 bottom=12 largest=64 imbalance=24`，本地 0 行
    /// 时 `bottom≈32.7` 判绿）——这是「本地绿 / CI 红」的唯一口径差。传该参数后距离到达目标
    /// 即冻结（首个样本仍是基准点，之后 1 个 tick 走满目标），内容对两条路径同构。
    let targetMeters: Double?

    /// 1° 纬度对应的米数（`earthRadiusMeters * π / 180`，与 `GeoDistance` 的 6 371 000 一致）。
    private static let metersPerDegreeLatitude = 111_194.93

    private var tick = 0
    private var isRunning = false
    private var timer: Timer?

    init(arguments: [String] = CommandLine.arguments) {
        let fast = arguments.contains("-uiTestLocationFast")
        stepPerTick = fast ? Self.fastStepPerTick : Self.defaultStepPerTick
        interval = fast ? Self.fastInterval : Self.defaultInterval
        targetMeters = RunLaunchArguments
            .value(after: "-uiTestLocationTargetMeters", arguments: arguments)
            .flatMap(Double.init)
            .flatMap { $0 > 0 ? $0 : nil }
    }

    /// 目标距离模式下第 `tick` 个样本的累计位移（米）：到达目标后恒为目标值，
    /// 计数器继续走但距离不再增长，因此墙钟再慢也不会多出分段。
    static func targetTravelledMeters(tick: Int, targetMeters: Double) -> Double {
        min(Double(tick) * targetMeters, targetMeters)
    }

    /// 第 `tick` 个样本的纬度：配置目标距离时按米换算，未配置时保持既有角度步进不变。
    func latitude(atTick tick: Int) -> Double {
        guard let targetMeters else {
            return Self.baseLatitude + Double(tick) * stepPerTick
        }
        let travelled = Self.targetTravelledMeters(tick: tick, targetMeters: targetMeters)
        return Self.baseLatitude + travelled / Self.metersPerDegreeLatitude
    }

    var sampleSource: RunSampleSource { .simulated }

    /// 确定性测试源不触碰 `CLLocationManager`，如实记录 false/false 而不伪造后台能力。
    var allowsBackgroundLocationUpdates: Bool { false }
    var pausesLocationUpdatesAutomatically: Bool { false }

    func start() {
        delegate?.locationSource(self, didChangeAuthorization: authorization)
        if isRunning {
            // 目标模式的重入：`onAppear` 先起一次源（此时还没进入记录态，样本会被引擎丢弃），
            // `beginRecording` 再起一次才是记录起点；这里重新锚定，让距离从记录起点算起。
            // 非目标模式保持既有「同进程坐标单调前进」语义，不重置。
            guard targetMeters != nil else { return }
            tick = 0
            emit()
            emit(timestampOffset: 0.001)
            return
        }
        isRunning = true
        // 首个样本立即产出（≤1s），之后按模式节奏推进。
        emit()
        if targetMeters != nil {
            // 目标模式：基准点后立刻补一个「到位」样本，距离在起跑同一帧就锁定 canonical 值，
            // 不依赖「等距离读数变化」这类时序判据；1ms 时间戳差同时满足「时间戳必须前进」
            // 与 `RunSplit.duration > 0` 两条既有契约。
            emit(timestampOffset: 0.001)
        }
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

    private func emit(timestampOffset: TimeInterval = 0) {
        guard isRunning else { return }
        let latitude = latitude(atTick: tick)
        tick += 1
        guard let sample = RunSample(
            latitude: latitude,
            longitude: Self.baseLongitude,
            altitude: 0,
            timestamp: Date().addingTimeInterval(timestampOffset),
            heartRate: nil,
            cadence: nil
        ) else {
            return
        }
        delegate?.locationSource(self, didProduce: sample)
    }
}
#endif
