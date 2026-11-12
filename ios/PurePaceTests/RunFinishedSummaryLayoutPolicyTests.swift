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

    /// 标准字号档也受内容区预算约束：iPhone 16 竖屏实测可用内容区 612.3pt
    /// （导航栏下沿 149.7 → 主操作顶边 762.0）< 未压缩所需 688pt → 必须压缩。
    /// 反例（「永不压缩」实现）：本条与下一条同时存在，任一方向的错判都会判红。
    func testStandardSizeCompressesWhenContentBudgetIsShort() {
        XCTAssertTrue(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: 762.0 - 149.7
            )
        )
    }

    /// 反例（「一律压缩」实现）：内容区给足 688pt 及以上时标准字号档保既有的 180pt 视觉。
    func testStandardSizeKeepsUncompressedSummaryWhenBudgetIsEnough() {
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: RunFinishedSummaryLayoutPolicy.uncompressedFinishedContentHeight
            )
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: RunFinishedSummaryLayoutPolicy.uncompressedFinishedContentHeight + 120
            )
        )
    }

    /// 辅助字号档不依赖预算：任何内容区高度都压缩（与既有 AX5 实测一致）。
    func testAccessibilitySizeAlwaysCompressesRegardlessOfBudget() {
        XCTAssertTrue(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: true,
                availableContentHeight: 4000
            )
        )
    }

    /// 标准字号档预算不足时，地图预览进一步收到 32pt：
    /// 实测保存态 metrics 底 → 分段标题顶 128pt = 96（地图）+ 4 + 8 + 20，地图占 75%。
    /// 反例（把标准压缩档误用 180/96）：下面的等值断言会判红，不需要改生产代码。
    func testStandardBudgetCompressedMapUsesTokenDerivedHeight() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false),
            DesignTokens.Spacing.xl
        )
        XCTAssertLessThanOrEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false),
            RunLayoutBalancePolicy.maximumGap
                - RunFinishedSummaryLayoutPolicy.blockSpacing(isAccessibilitySize: true)
                - RunFinishedSummaryLayoutPolicy.cardPadding(isAccessibilitySize: true)
        )
    }

    /// 反例方向：辅助字号档保持 96pt（不被标准预算档的 32 覆盖），未压缩标准档保持 180pt。
    func testMapHeightKeepsAccessibilityAndUncompressedBranches() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.accessibilityTrackPreviewHeight
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            RunFinishedSummaryLayoutPolicy.standardTrackPreviewHeight
        )
        XCTAssertNotEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            RunFinishedSummaryLayoutPolicy.budgetCompressedTrackPreviewHeight
        )
    }
}
