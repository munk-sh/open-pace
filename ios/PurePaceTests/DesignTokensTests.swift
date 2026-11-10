import XCTest
@testable import PurePace

/// 设计 token 不变量：间距/字号/圆角/图标阶梯有序，最小触控尺寸固定 44。
final class DesignTokensTests: XCTestCase {
    // MARK: - ac-token-values-valid

    func testSpacingScaleIsStrictlyIncreasingAndPositive() {
        let scale = DesignTokens.Spacing.scale
        XCTAssertEqual(scale.count, 6)
        XCTAssertGreaterThan(scale[0], 0)
        for index in 1..<scale.count {
            XCTAssertGreaterThan(scale[index], scale[index - 1], "间距档必须严格递增")
        }
    }

    func testTypographyScaleIsStrictlyIncreasingAndPositive() {
        let sizes = DesignTokens.Typography.sizes
        XCTAssertEqual(sizes.count, 5)
        XCTAssertGreaterThan(sizes[0], 0)
        for index in 1..<sizes.count {
            XCTAssertGreaterThan(sizes[index], sizes[index - 1], "字号层级必须严格递增")
        }
    }

    func testTypographyHierarchyMatchesDeclaredOrder() {
        XCTAssertLessThan(DesignTokens.Typography.captionSize, DesignTokens.Typography.bodySize)
        XCTAssertLessThan(DesignTokens.Typography.bodySize, DesignTokens.Typography.titleSize)
        XCTAssertLessThan(DesignTokens.Typography.titleSize, DesignTokens.Typography.primaryValueSize)
        XCTAssertLessThan(DesignTokens.Typography.primaryValueSize, DesignTokens.Typography.displaySize)
    }

    func testPrimaryMetricsAreClearlyLargerThanSecondary() {
        // 跑步页主信息（距离/时长/配速）至少是次信息（平均配速/分段/说明）的两倍字号。
        XCTAssertGreaterThanOrEqual(
            DesignTokens.Typography.displaySize,
            DesignTokens.Typography.bodySize * 2
        )
        XCTAssertGreaterThanOrEqual(
            DesignTokens.Typography.primaryValueSize,
            DesignTokens.Typography.bodySize * 2
        )
    }

    func testTapTargetIsFortyFourPoints() {
        XCTAssertEqual(DesignTokens.minTapTarget, 44)
    }

    func testRadiusAndIconScalesArePositiveAndOrdered() {
        let radius = DesignTokens.Radius.scale
        XCTAssertEqual(radius.count, 3)
        for value in radius {
            XCTAssertGreaterThan(value, 0)
        }
        for index in 1..<radius.count {
            XCTAssertGreaterThan(radius[index], radius[index - 1], "圆角档必须严格递增")
        }

        let icons = DesignTokens.Icon.scale
        XCTAssertEqual(icons.count, 3)
        for value in icons {
            XCTAssertGreaterThan(value, 0)
        }
        for index in 1..<icons.count {
            XCTAssertGreaterThan(icons[index], icons[index - 1], "图标尺寸档必须严格递增")
        }
    }

    func testTypographyWeightsAreDeclaredInAscendingOrder() {
        XCTAssertEqual(
            DesignTokens.Typography.weights,
            [.regular, .semibold, .bold]
        )
    }

    // MARK: - ac-token-categories

    func testTokenCoversColorsSizesSpacingAndRadius() {
        // 颜色常量由静态门 `validate_design_tokens` 断言 `DesignTokens.Colors`；
        // 这里对字号 / 间距 / 圆角三类数值档做可执行的覆盖断言。
        XCTAssertEqual(DesignTokens.Typography.sizes.count, 5)
        XCTAssertEqual(DesignTokens.Spacing.scale.count, 6)
        XCTAssertEqual(DesignTokens.Radius.scale.count, 3)
    }

    func testDarkModeIsStructurallyReservedButOff() {
        // 本期不做深色模式专项适配；token 结构留位，后续可无痛接入。
        XCTAssertFalse(DesignTokens.Appearance.supportsDarkMode)
    }
}
