import CoreGraphics
import XCTest
import PurePaceRunCore
@testable import PurePace

/// ac-visible-copy-zh-hans / ac-run-detail-date-zh-hans / ac-primary-action-bottom-anchored
/// 的纯函数判定。每条判定都必须有正向样本与能红的反例。
final class LocalizationPolicyTests: XCTestCase {
    // MARK: - A. 可见文案 zh-Hans

    func testVisibleTextPolicyAllowsZhHansWhitelist() {
        let samples = [
            "跑步", "历史", "设置", "开始", "暂停", "继续", "结束", "已保存",
            "距离", "用时", "当前配速", "平均配速", "分段",
            "0.00 km", "5:00 /km", "导出 GPX", "等待定位授权…",
            "2025年10月9日 16:53"
        ]
        XCTAssertEqual(VisibleTextPolicy.violations(in: samples), [])
    }

    func testVisibleTextPolicyRejectsBareEnglish() {
        XCTAssertEqual(VisibleTextPolicy.violations(in: ["Run"]), ["Run"])
        XCTAssertEqual(VisibleTextPolicy.violations(in: ["History"]), ["History"])
        XCTAssertEqual(VisibleTextPolicy.violations(in: ["Settings"]), ["Settings"])
        XCTAssertEqual(
            VisibleTextPolicy.violations(in: ["跑步", "Time", "0.00 km"]),
            ["Time"]
        )
    }

    // MARK: - B. 日期 zh-Hans

    func testZhHansDateTimeMatchesFixedFixture() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(
            RunFormatting.zhHansDateTimeText(date, timeZone: timeZone),
            "2025年10月9日 16:53"
        )
    }

    func testDetailDateTimeIsZhHansAndRejectsEnglishSamples() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let detailText = RunFormatting.dateTimeText(date, timeZone: timeZone)
        XCTAssertTrue(VisibleDatePolicy.isZhHansDateTime(detailText), detailText)

        let englishSamples = [
            "Oct 9, 2025 at 16:53",
            "October 9, 2025 at 4:53 PM",
            "10/9/25, 4:53 PM",
            "2025/10/09 16:53"
        ]
        for sample in englishSamples {
            XCTAssertFalse(VisibleDatePolicy.isZhHansDateTime(sample), "英文日期样本必须被拒绝: \(sample)")
        }
    }

    // MARK: - C. 主操作底部锚定

    func testPolicyThresholdMatchesDesignToken() {
        XCTAssertEqual(PrimaryActionLayoutPolicy.minimumActionHeight, DesignTokens.minTapTarget)
    }

    func testAnchoredPrimaryActionPasses() {
        let action = CGRect(x: 16, y: 713, width: 361, height: 44)
        let tabBar = CGRect(x: 0, y: 769, width: 393, height: 83)
        let evaluation = PrimaryActionLayoutPolicy.evaluate(actionFrame: action, tabBarFrame: tabBar)
        XCTAssertTrue(evaluation.passes, "\(evaluation.problems)")
        XCTAssertEqual(evaluation.bottomGap, 12)
        XCTAssertTrue(evaluation.isAboveTabBar)
    }

    func testRejectsTwoHundredPointGapAndThirtyPointHeight() {
        let tooFarAndTooShort = CGRect(x: 16, y: 500, width: 361, height: 30)
        let tabBar = CGRect(x: 0, y: 769, width: 393, height: 83)
        let evaluation = PrimaryActionLayoutPolicy.evaluate(
            actionFrame: tooFarAndTooShort,
            tabBarFrame: tabBar
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertGreaterThan(evaluation.bottomGap, PrimaryActionLayoutPolicy.maximumBottomGap)
        XCTAssertLessThan(evaluation.height, PrimaryActionLayoutPolicy.minimumActionHeight)
        XCTAssertEqual(evaluation.problems.count, 2)
    }

    func testRejectsActionBelowTabBar() {
        let belowTabBar = CGRect(x: 16, y: 760, width: 361, height: 44)
        let tabBar = CGRect(x: 0, y: 769, width: 393, height: 83)
        let evaluation = PrimaryActionLayoutPolicy.evaluate(
            actionFrame: belowTabBar,
            tabBarFrame: tabBar
        )
        XCTAssertFalse(evaluation.isAboveTabBar)
        XCTAssertFalse(evaluation.passes)
    }

    // MARK: - D. 首屏四层垂直分布（阈值先定后测：80 / 80 / 80 / 16）

    /// 旧布局实测帧：内容块 177.7–447.4pt、导航栏下沿 149.7pt、主操作顶边 699.0pt。
    private var legacyContentFrames: [CGRect] {
        [
            CGRect(x: 16, y: 177.7, width: 361, height: 57),
            CGRect(x: 16, y: 254.7, width: 174, height: 60),
            CGRect(x: 207, y: 254.7, width: 170, height: 60),
            CGRect(x: 16, y: 334.7, width: 174, height: 36),
            CGRect(x: 207, y: 334.7, width: 170, height: 36),
            CGRect(x: 16, y: 415.4, width: 361, height: 32)
        ]
    }

    /// 本轮截图实测旧布局帧（PNG 逐行扫描，`docs/screenshots/run-not-started.png`）：
    /// 导航内容下沿 137.3pt → hero 面板顶 265.3pt（死白 128.0pt）；
    /// 提示片底 584.7pt → 主操作顶边 701.0pt（死白 116.3pt）。
    private var screenshotLegacyFrames: [CGRect] {
        [
            CGRect(x: 88.5, y: 265.3, width: 216, height: 67),
            CGRect(x: 59.8, y: 391.5, width: 97, height: 40.7),
            CGRect(x: 269.4, y: 391.5, width: 30.7, height: 40.7),
            CGRect(x: 102.6, y: 475.5, width: 11.3, height: 14.3),
            CGRect(x: 280.9, y: 475.5, width: 7.7, height: 14.3),
            CGRect(x: 17.3, y: 548.0, width: 358.3, height: 36.7)
        ]
    }

    /// 四态同构代表帧（本轮实测顶/底 ≈ 57.5 附近）：四层等量分布，
    /// 顶部 67.3pt / 底部 63.3pt / 最大空洞 79.3pt / 上下差 4.0pt。
    private func balancedFrames(hintTop: CGFloat, savedTop: CGFloat? = nil) -> [CGRect] {
        var frames = [
            CGRect(x: 88.5, y: 204.58, width: 216, height: 67),
            CGRect(x: 184.5, y: 275.58, width: 24, height: 14.3),
            CGRect(x: 59.8, y: 369.15, width: 97, height: 40.7),
            CGRect(x: 96.2, y: 413.85, width: 24, height: 14.3),
            CGRect(x: 269.4, y: 369.15, width: 30.7, height: 40.7),
            CGRect(x: 260.8, y: 413.85, width: 48, height: 14.3),
            CGRect(x: 102.6, y: 493.15, width: 11.3, height: 14.3),
            CGRect(x: 84.2, y: 511.45, width: 48, height: 14.3),
            CGRect(x: 280.9, y: 493.15, width: 7.7, height: 14.3),
            CGRect(x: 272.8, y: 511.45, width: 24, height: 14.3),
            CGRect(x: 17.3, y: hintTop, width: 358.3, height: 36.7)
        ]
        if let savedTop {
            frames.append(CGRect(x: 154, y: savedTop, width: 86, height: 28))
        }
        return frames
    }

    /// 保存态同构帧（2026-11-12 本地 UI 腿实测，iPhone 16 / iOS 18.6 / 标准字号档，
    /// canonical 1 条分段 = `-uiTestLocationTargetMeters 1200`）：
    /// 与 `.munk/logs/ui-1split-green.log` 的 `ac-run-metrics-balanced 保存态` contentFrames 同构，
    /// 含 `run.mapPreview` 实测帧 (15.5, 473.5, 362, 97) —— 地图卡是可见内容块，不是空白。
    /// 实测 top=20.0 / bottom=8.0 / largest=20.0 / imbalance=12.0（阈值 80/16 未改）。
    private var savedStateFramesWithMapCard: [CGRect] {
        [
            Self.mapCardFrame,
            CGRect(x: 185.5, y: 169.66666666666666, width: 22, height: 13.333333333333343),
            CGRect(x: 117.33333333333333, y: 191.0, width: 158.33333333333331, height: 76.66666666666663),
            CGRect(x: 188.5, y: 275.66666666666663, width: 16, height: 13.333333333333371),
            CGRect(x: 97.25, y: 309.0, width: 22, height: 13.333333333333314),
            CGRect(x: 262.75, y: 309.0, width: 44, height: 13.333333333333314),
            CGRect(x: 52.583333333333336, y: 330.3333333333333, width: 111.33333333333331, height: 43.0),
            CGRect(x: 240.08333333333334, y: 330.3333333333333, width: 89.33333333333334, height: 43.0),
            CGRect(x: 275.08333333333337, y: 381.3333333333333, width: 19.333333333333314, height: 13.333333333333371),
            CGRect(x: 86.25, y: 403.6666666666667, width: 44, height: 13.333333333333314),
            CGRect(x: 273.75, y: 403.6666666666667, width: 22, height: 13.333333333333314),
            CGRect(x: 94.08333333333333, y: 425.0, width: 28.333333333333343, height: 15.666666666666686),
            CGRect(x: 280.5833333333333, y: 425.0, width: 8.333333333333314, height: 15.666666666666686),
            CGRect(x: 98.58333333333333, y: 448.6666666666667, width: 19.333333333333343, height: 13.333333333333314),
            CGRect(x: 24.0, y: 582.0, width: 59.66666666666666, height: 18.0),
            CGRect(x: 24.0, y: 604.0, width: 345.0, height: 18.0),
            CGRect(x: 22.166666666666686, y: 642.0, width: 348.66666666666663, height: 31.333333333333258),
            CGRect(x: 165.0, y: 681.3333333333333, width: 63.0, height: 23.66666666666663),
            CGRect(x: 24.0, y: 604.0, width: 9.333333333333329, height: 18.0),
            CGRect(x: 308.0, y: 604.0, width: 61.0, height: 18.0)
        ]
    }

    /// `run.mapPreview` 实测帧（96pt 地图 + 1pt 描边 = 97pt）。
    private static let mapCardFrame = CGRect(x: 15.5, y: 473.5, width: 362, height: 97)

    /// 反例输入：只删掉地图卡帧（旧 staticTexts 口径），其余帧原样不动。
    private var savedStateFramesWithoutMapCard: [CGRect] {
        savedStateFramesWithMapCard.filter { $0 != Self.mapCardFrame }
    }

    func testPolicyThresholds() {
        XCTAssertEqual(RunLayoutBalancePolicy.maximumTopGap, 80)
        XCTAssertEqual(RunLayoutBalancePolicy.maximumBottomGap, 80)
        XCTAssertEqual(RunLayoutBalancePolicy.maximumGap, 80)
        XCTAssertEqual(RunLayoutBalancePolicy.maximumImbalance, 16)
    }

    func testLegacyTopStackedLayoutFailsBothCriteria() {
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: legacyContentFrames,
            navigationBarBottom: 149.7,
            primaryActionTop: 699.0
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.topGap, 28, accuracy: 0.01)
        XCTAssertEqual(evaluation.bottomGap, 251.6, accuracy: 0.01)
        XCTAssertEqual(evaluation.largestGap, 251.6, accuracy: 0.01)
        XCTAssertEqual(evaluation.imbalance, 223.6, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(evaluation.problems.count, 2)
        XCTAssertTrue(evaluation.problems.contains { $0.contains("底部留白") })
        XCTAssertTrue(evaluation.problems.contains { $0.contains("最大单一垂直空洞") })
        XCTAssertTrue(evaluation.problems.contains { $0.contains("上下留白差") })
    }

    /// 本轮截图实测旧布局（顶 128.0 / 底 116.3）必须同时命中三条空洞判据。
    func testScreenshotLegacyLayoutFailsAllThreeGapCriteria() {
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: screenshotLegacyFrames,
            navigationBarBottom: 137.3,
            primaryActionTop: 701.0
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.topGap, 128.0, accuracy: 0.1)
        XCTAssertEqual(evaluation.bottomGap, 116.3, accuracy: 0.1)
        XCTAssertEqual(evaluation.largestGap, 128.0, accuracy: 0.1)
        XCTAssertEqual(evaluation.imbalance, 11.7, accuracy: 0.1)
        XCTAssertTrue(evaluation.problems.contains { $0.contains("顶部留白") })
        XCTAssertTrue(evaluation.problems.contains { $0.contains("底部留白") })
        XCTAssertTrue(evaluation.problems.contains { $0.contains("最大单一垂直空洞") })
    }

    /// 四态（未开始 / 运行中 / 暂停 / 已保存）代表帧全部判绿。
    func testFourStatesBalancedLayoutPasses() {
        let states: [(String, [CGRect], CGFloat, CGFloat)] = [
            ("未开始", balancedFrames(hintTop: 601.03), 137.3, 701.0),
            ("运行中", balancedFrames(hintTop: 599.03), 137.3, 701.0),
            ("暂停", balancedFrames(hintTop: 603.03), 137.3, 701.0),
            ("已保存", savedStateFramesWithMapCard, 149.67, 713.0)
        ]
        for (state, frames, navigationBarBottom, primaryActionTop) in states {
            let evaluation = RunLayoutBalancePolicy.evaluate(
                contentFrames: frames,
                navigationBarBottom: navigationBarBottom,
                primaryActionTop: primaryActionTop
            )
            XCTAssertTrue(evaluation.passes, "\(state): \(evaluation.problems)")
            XCTAssertLessThanOrEqual(evaluation.topGap, RunLayoutBalancePolicy.maximumTopGap)
            XCTAssertLessThanOrEqual(evaluation.bottomGap, RunLayoutBalancePolicy.maximumBottomGap)
            XCTAssertLessThanOrEqual(evaluation.largestGap, RunLayoutBalancePolicy.maximumGap)
            XCTAssertLessThanOrEqual(evaluation.imbalance, RunLayoutBalancePolicy.maximumImbalance)
        }
    }

    /// ac-balance-audit-counts-map-card：96pt 地图卡（实测帧 97pt 含描边）作为可见内容块纳入采样后
    /// 保存态判绿，地图不再被计成「最大单一垂直空洞」；三判据与 UI 腿实测同值。
    func testSavedStateWithMapCardPasses() {
        let frames = savedStateFramesWithMapCard
        XCTAssertTrue(frames.contains(Self.mapCardFrame), "保存态帧必须含实测地图卡")
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: frames,
            navigationBarBottom: 149.67,
            primaryActionTop: 713.0
        )
        XCTAssertTrue(evaluation.passes, "\(evaluation.problems)")
        XCTAssertEqual(evaluation.topGap, 20.0, accuracy: 0.01)
        XCTAssertEqual(evaluation.bottomGap, 8.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(evaluation.largestGap, RunLayoutBalancePolicy.maximumGap)
        XCTAssertEqual(evaluation.largestGap, 20.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(evaluation.imbalance, RunLayoutBalancePolicy.maximumImbalance)
        XCTAssertEqual(evaluation.imbalance, 12.0, accuracy: 0.01)
    }

    /// 反例（地图卡不计入采样 = 旧 staticTexts 口径）：同一组帧最大空洞 120pt
    /// （指标末行底 462.0 → 分段标题顶 582.0），仅「最大单一垂直空洞」一条判红，阈值 80 未改。
    func testSavedStateWithoutMapCardFailsLargestGap() {
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: savedStateFramesWithoutMapCard,
            navigationBarBottom: 149.67,
            primaryActionTop: 713.0
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.largestGap, 120.0, accuracy: 0.01)
        XCTAssertEqual(evaluation.problems.count, 1)
        XCTAssertTrue(evaluation.problems[0].contains("最大单一垂直空洞"))
    }

    /// 顶/底都合规但块间仍有一大块死白时必须判红（防止只判上下两条漏掉块间空洞）。
    func testRejectsLargeInterBlockHole() {
        let frames = [
            CGRect(x: 16, y: 180.6, width: 361, height: 67),
            CGRect(x: 16, y: 327.6, width: 361, height: 67),
            CGRect(x: 16, y: 621.0, width: 361, height: 36.7)
        ]
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: frames,
            navigationBarBottom: 137.3,
            primaryActionTop: 701.0
        )
        XCTAssertEqual(evaluation.topGap, 43.3, accuracy: 0.01)
        XCTAssertEqual(evaluation.bottomGap, 43.3, accuracy: 0.01)
        XCTAssertEqual(evaluation.largestGap, 226.4, accuracy: 0.01)
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.problems.count, 1)
        XCTAssertTrue(evaluation.problems[0].contains("最大单一垂直空洞"))
    }

    func testRejectsAsymmetricWhitespaceEvenWhenGapsFit() {
        // 上 20pt / 下 45pt：单洞未超 80pt，但上下差 25pt 必须判红。
        let frames = [CGRect(x: 16, y: 169.7, width: 361, height: 57)]
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: frames,
            navigationBarBottom: 149.7,
            primaryActionTop: 271.7
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.topGap, 20, accuracy: 0.01)
        XCTAssertEqual(evaluation.bottomGap, 45, accuracy: 0.01)
        XCTAssertEqual(evaluation.largestGap, 45, accuracy: 0.01)
        XCTAssertEqual(evaluation.imbalance, 25, accuracy: 0.01)
        XCTAssertEqual(evaluation.problems.count, 1)
        XCTAssertTrue(evaluation.problems[0].contains("上下留白差"))
    }

    func testRejectsMissingContent() {
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: [],
            navigationBarBottom: 149.7,
            primaryActionTop: 699.0
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.problems, ["未采集到任何可见内容块"])
    }
}
