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

    // MARK: - D. 指标区垂直居中

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

    /// 居中布局正例：同一内容块整体下移 111.8pt，上下留白各 139.8pt。
    private var centeredContentFrames: [CGRect] {
        legacyContentFrames.map { $0.offsetBy(dx: 0, dy: 111.8) }
    }

    func testPolicyThresholds() {
        XCTAssertEqual(RunLayoutBalancePolicy.maximumGap, 160)
        XCTAssertEqual(RunLayoutBalancePolicy.maximumImbalance, 40)
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
        XCTAssertEqual(evaluation.problems.count, 2)
    }

    func testCenteredLayoutPassesBothCriteria() {
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: centeredContentFrames,
            navigationBarBottom: 149.7,
            primaryActionTop: 699.0
        )
        XCTAssertTrue(evaluation.passes, "\(evaluation.problems)")
        XCTAssertEqual(evaluation.topGap, 139.8, accuracy: 0.01)
        XCTAssertEqual(evaluation.bottomGap, 139.8, accuracy: 0.01)
        XCTAssertEqual(evaluation.largestGap, 139.8, accuracy: 0.01)
        XCTAssertEqual(evaluation.imbalance, 0, accuracy: 0.01)
    }

    func testRejectsAsymmetricWhitespaceEvenWhenGapsFit() {
        // 上 10pt / 下 100pt：单洞未超 160pt，但上下差 90pt 必须判红。
        let frames = [CGRect(x: 16, y: 159.7, width: 361, height: 57)]
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: frames,
            navigationBarBottom: 149.7,
            primaryActionTop: 316.7
        )
        XCTAssertFalse(evaluation.passes)
        XCTAssertEqual(evaluation.largestGap, 100, accuracy: 0.01)
        XCTAssertEqual(evaluation.imbalance, 90, accuracy: 0.01)
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
