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
}
