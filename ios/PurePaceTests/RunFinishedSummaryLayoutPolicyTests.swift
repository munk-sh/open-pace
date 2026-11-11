import XCTest
@testable import PurePace

/// 结束态总结（地图预览 + 分段明细）垂直预算（L1 纯逻辑）。
///
/// 只断言「辅助字号档压缩、标准字号档不变」的口径与取值来源：
/// 口径值全部由既有 `DesignTokens.Spacing` 派生，不引入新字号档 / 新色键。
final class RunFinishedSummaryLayoutPolicyTests: XCTestCase {
    func testStandardSizesKeepExistingTrackPreviewHeight() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false),
            180
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.blockSpacing(isAccessibilitySize: false),
            DesignTokens.Spacing.sectionGap
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.cardPadding(isAccessibilitySize: false),
            DesignTokens.Spacing.sm
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.rowSpacing(isAccessibilitySize: false),
            DesignTokens.Spacing.metricGroupSpacing
        )
    }

    func testAccessibilitySizesCompressEveryVerticalSlot() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: true),
            3 * DesignTokens.Spacing.xl
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.blockSpacing(isAccessibilitySize: true),
            DesignTokens.Spacing.xxs
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.cardPadding(isAccessibilitySize: true),
            DesignTokens.Spacing.xs
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.rowSpacing(isAccessibilitySize: true),
            DesignTokens.Spacing.xxs
        )
    }

    /// 压缩必须严格单调（大字号档逐项小于等于标准档，且地图至少省 80pt），
    /// 否则 AX5 实测 108pt 溢出无法靠压缩收回。
    func testAccessibilitySlotsAreStrictlyNotLarger() {
        XCTAssertLessThan(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false)
        )
        XCTAssertGreaterThanOrEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false)
                - RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: true),
            80
        )
        XCTAssertLessThan(
            RunFinishedSummaryLayoutPolicy.blockSpacing(isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.blockSpacing(isAccessibilitySize: false)
        )
        XCTAssertLessThan(
            RunFinishedSummaryLayoutPolicy.cardPadding(isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.cardPadding(isAccessibilitySize: false)
        )
        XCTAssertLessThan(
            RunFinishedSummaryLayoutPolicy.rowSpacing(isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.rowSpacing(isAccessibilitySize: false)
        )
    }
}
