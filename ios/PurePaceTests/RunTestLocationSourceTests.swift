import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

#if DEBUG
/// ac-finished-content-canonical：结束态分段行数只能由 `-uiTestLocationTargetMeters` 决定，
/// 不得随 runner 墙钟（tick 数）漂移。
///
/// 归因（2026-11-12）：跑动距离由本测试源的 tick 数驱动，tick 数 = 墙钟时间 × 1 Hz；同一份
/// 用例在 CI 慢机器上多跑 ≥100s 就多跨一个 1km 边界、多一行分段（约 20pt），结束态内容被顶出
/// 可用区（CI 实测 `top=36 bottom=12 imbalance=24`；本地 0 行时 `bottom≈32.7` 判绿）。目标模式
/// 让两条路径产出同构内容，测试里的断言才可比。
@MainActor
final class RunTestLocationSourceTests: XCTestCase {
    // MARK: - 参数解析

    func testTargetMetersIsOptInOnly() {
        XCTAssertNil(
            RunTestLocationSource(arguments: ["-uiTestLocation"]).targetMeters,
            "不传目标参数时必须保持既有墙钟节奏"
        )
        XCTAssertNil(
            RunTestLocationSource(arguments: ["-uiTestLocation", "-uiTestLocationFast"]).targetMeters,
            "快速模式不得被误解析成目标模式"
        )
        XCTAssertNil(
            RunTestLocationSource(
                arguments: ["-uiTestLocation", "-uiTestLocationTargetMeters", "-autoStartRecording"]
            ).targetMeters,
            "flag 后跟另一个 flag 时不得解析成目标"
        )
        XCTAssertNil(
            RunTestLocationSource(
                arguments: ["-uiTestLocation", "-uiTestLocationTargetMeters", "0"]
            ).targetMeters,
            "0 米不是有效目标（否则所有样本同点、距离衡为 0 却无法区分拼写错误）"
        )
        XCTAssertEqual(
            RunTestLocationSource(
                arguments: ["-uiTestLocation", "-uiTestLocationTargetMeters", "1200"]
            ).targetMeters,
            1200
        )
    }

    // MARK: - 距离冻结（反例：墙钟多跑一段就多一行）

    /// 反例输入：不冻结距离时，同一份用例只因为 runner 多跑 101s 就从 0 行变 2 行。
    func testUnpinnedWallClockTicksChangeSplitRowsCounterexample() {
        let stepMeters = 10.0075 // 默认源每 tick 的位移（1 Hz）
        XCTAssertEqual(splitRows(meters: 99 * stepMeters), 0)
        XCTAssertEqual(
            splitRows(meters: 200 * stepMeters),
            2,
            "不冻结距离时多数 101 个 tick 就多 2 行——这正是 4d522e6 CI 红的内容漂移"
        )
    }

    func testTravelledMetersIsCappedAtTarget() {
        XCTAssertEqual(
            RunTestLocationSource.targetTravelledMeters(tick: 0, targetMeters: 1200),
            0,
            "首个样本是基准点，不计距离"
        )
        XCTAssertEqual(RunTestLocationSource.targetTravelledMeters(tick: 1, targetMeters: 1200), 1200)
        XCTAssertEqual(
            RunTestLocationSource.targetTravelledMeters(tick: 500, targetMeters: 1200),
            1200,
            "墙钟再慢（500 tick）也不得让距离继续增长"
        )
    }

    func testCanonicalTargetsPinSplitRowCount() {
        XCTAssertEqual(splitRows(targetMeters: 400, tick: 1), 0)
        XCTAssertEqual(splitRows(targetMeters: 400, tick: 600), 0)
        XCTAssertEqual(splitRows(targetMeters: 1200, tick: 1), 1)
        XCTAssertEqual(splitRows(targetMeters: 1200, tick: 600), 1)
        XCTAssertEqual(splitRows(targetMeters: 2100, tick: 1), 2)
    }

    /// 纬度必须按米换算（不是沿用 0.00009°/tick 的角度步进），否则目标米数在真机上不成立。
    func testTargetLatitudeMapsToRequestedMeters() {
        let source = RunTestLocationSource(
            arguments: ["-uiTestLocation", "-uiTestLocationTargetMeters", "1200"]
        )
        let base = source.latitude(atTick: 0)
        let reached = source.latitude(atTick: 1)
        let meters = GeoDistance.meters(
            latitude1: base,
            longitude1: 0,
            latitude2: reached,
            longitude2: 0
        )
        XCTAssertEqual(meters, 1200, accuracy: 1.0, "目标模式必须按真实米数推进，实测 \(meters)m")
    }

    // MARK: - Helpers

    /// 分段行数 = floor(累计距离 / 1000)，与 `RunMetricsEngine.completeSplits` 同一口径。
    private func splitRows(meters: Double) -> Int {
        Int((meters / 1000).rounded(.down))
    }

    private func splitRows(targetMeters: Double, tick: Int) -> Int {
        splitRows(
            meters: RunTestLocationSource.targetTravelledMeters(
                tick: tick,
                targetMeters: targetMeters
            )
        )
    }
}
#endif
