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
        let states: [(String, [CGRect])] = [
            ("未开始", balancedFrames(hintTop: 601.03)),
            ("运行中", balancedFrames(hintTop: 599.03)),
            ("暂停", balancedFrames(hintTop: 603.03)),
            ("已保存", balancedFrames(hintTop: 570.8, savedTop: 615.5))
        ]
        for (state, frames) in states {
            let evaluation = RunLayoutBalancePolicy.evaluate(
                contentFrames: frames,
                navigationBarBottom: 137.3,
                primaryActionTop: 701.0
            )
            XCTAssertTrue(evaluation.passes, "\(state): \(evaluation.problems)")
            XCTAssertLessThanOrEqual(evaluation.topGap, RunLayoutBalancePolicy.maximumTopGap)
            XCTAssertLessThanOrEqual(evaluation.bottomGap, RunLayoutBalancePolicy.maximumBottomGap)
            XCTAssertLessThanOrEqual(evaluation.largestGap, RunLayoutBalancePolicy.maximumGap)
            XCTAssertLessThanOrEqual(evaluation.imbalance, RunLayoutBalancePolicy.maximumImbalance)
        }
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
