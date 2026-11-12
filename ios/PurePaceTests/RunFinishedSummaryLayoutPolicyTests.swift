import XCTest
@testable import PurePace

/// 结束态总结（地图预览 + 分段明细）垂直预算（L1 纯逻辑）。
///
/// 只断言口径与取值来源：地图高度只有 180（未压缩标准档）/ 96（压缩档）两个值，
/// 压缩档多占的 64pt 由命名参数从非地图槽位回收；全部由既有 `DesignTokens.Spacing` 派生。
final class RunFinishedSummaryLayoutPolicyTests: XCTestCase {
    func testStandardSizesKeepExistingTrackPreviewHeight() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false),
            180
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            180
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: false),
            DesignTokens.Spacing.sectionGap
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.cardPadding(compresses: false),
            DesignTokens.Spacing.sm
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.rowSpacing(compresses: false),
            DesignTokens.Spacing.metricGroupSpacing
        )
    }

    func testAccessibilitySizesCompressEveryVerticalSlot() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: true),
            3 * DesignTokens.Spacing.xl
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: true),
            DesignTokens.Spacing.xxs
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.cardPadding(compresses: true),
            DesignTokens.Spacing.xs
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.rowSpacing(compresses: true),
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
            RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: true),
            RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: false)
        )
        XCTAssertLessThan(
            RunFinishedSummaryLayoutPolicy.cardPadding(compresses: true),
            RunFinishedSummaryLayoutPolicy.cardPadding(compresses: false)
        )
        XCTAssertLessThan(
            RunFinishedSummaryLayoutPolicy.rowSpacing(compresses: true),
            RunFinishedSummaryLayoutPolicy.rowSpacing(compresses: false)
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

    /// ac-finished-map-floor-96：标准档压缩分支的地图下限回到 96pt（3 × `Spacing.xl`）。
    /// 改前红：`2d40bc0`（经 `4d522e6` 合入 main）该分支返回 `Spacing.xl`(32)，本断言实测判红
    /// （日志 .munk/logs/map-floor-red-before-unit.log / map-floor-red-before-ui.log）。
    /// 断言用数值下限 96，不复述生产常量取别名。
    func testStandardBudgetCompressedMapMeetsFloor96() {
        let height = RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false)
        XCTAssertGreaterThanOrEqual(height, 96, "标准档压缩分支地图高度 \(height)pt < 96pt 下限")
        XCTAssertEqual(height, 96)
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsMapFloor(height))
    }

    /// ac-finished-map-not-strip：把历史值 32 作为输入喂给同一高度判据必须判红（反例）。
    /// 输入写死字面量 32（不取生产常量别名），判据若回落到 32 则 `meetsMapFloor(32)` 返回 true 必红。
    func testHistoricStripHeightIsRejectedByMapFloor() {
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsMapFloor(32),
            "32pt 是回归前的细条高度，必须被判红"
        )
        XCTAssertFalse(RunFinishedSummaryLayoutPolicy.meetsMapFloor(0))
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsMapFloor(96))
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsMapFloor(180))
    }

    /// ac-map-height-three-branches：地图高度只出现 180 / 96 两个值，三组合逐一断言；
    /// AX5 无论是否传预算都是 96，未压缩标准档 180。
    func testMapHeightOnlyHasUncompressedAndCompressedBranches() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            180
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false),
            96
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: true),
            96
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: true),
            96,
            "AX5 恒压缩，预算参数不改变地图高度"
        )
    }

    /// ac-nonmap-slack-parameterized：地图 +64pt（32 → 96）由非地图槽位回收 60pt，
    /// 每个槽位都是命名参数。余下 4pt 有意留在 `topBreathing`（`md`+`xxs`=20 而非 `md`=16）：
    /// 顶部是唯一钉住上沿的弹性位，取 20 才能让 0 行 / 1 行两种 canonical 内容同时满足
    /// 「上下留白差 ≤16」（UI 腿实测 9.33 / 12），否则 0 行恰好 16.0000000000001pt 超限。
    /// 反例：任一槽位回到未压缩值，回收合计 < 60 必红。
    func testCompressedNonMapSlotsRelieveTheMapDelta() {
        let relief =
            (RunFinishedSummaryLayoutPolicy.topBreathing(compresses: false)
                - RunFinishedSummaryLayoutPolicy.topBreathing(compresses: true))
            + (RunFinishedSummaryLayoutPolicy.heroTopPadding(compresses: false)
                - RunFinishedSummaryLayoutPolicy.heroTopPadding(compresses: true))
            + (RunFinishedSummaryLayoutPolicy.heroMetricsGap(compresses: false)
                - RunFinishedSummaryLayoutPolicy.heroMetricsGap(compresses: true))
            + 2 * (RunFinishedSummaryLayoutPolicy.metricCardPadding(compresses: false)
                - RunFinishedSummaryLayoutPolicy.metricCardPadding(compresses: true))
            + (RunFinishedSummaryLayoutPolicy.metricCardBottomPadding(compresses: false)
                - RunFinishedSummaryLayoutPolicy.metricCardBottomPadding(compresses: true))
            + 2 * (RunFinishedSummaryLayoutPolicy.metricGroupGap(compresses: false)
                - RunFinishedSummaryLayoutPolicy.metricGroupGap(compresses: true))
        XCTAssertEqual(relief, 60, "压缩档非地图回收总量 = 地图增量 64 − 顶部有意保留的 4pt")
        XCTAssertGreaterThanOrEqual(relief, 40, "至少回收 40pt 才够抵消实测溢出")
    }

    /// 压缩槽位只改压缩档：未压缩时逐项等于既有语义 token（视图层不再出现裸数字）。
    func testUncompressedSlotsStayOnExistingTokens() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.topBreathing(compresses: false),
            DesignTokens.Spacing.screenTop
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.heroTopPadding(compresses: false),
            DesignTokens.Spacing.sm
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.heroMetricsGap(compresses: false),
            DesignTokens.Spacing.cardGap
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.metricCardPadding(compresses: false),
            DesignTokens.Spacing.cardPadding
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.metricCardBottomPadding(compresses: false),
            DesignTokens.Spacing.xxs
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.metricGroupGap(compresses: false),
            DesignTokens.Spacing.metricGroupGap
        )
    }

    /// 反例方向：辅助字号档保持 96pt（不被未压缩标准档的 180 覆盖）。
    func testMapHeightKeepsAccessibilityBranch() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.accessibilityTrackPreviewHeight
        )
        XCTAssertNotEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            RunFinishedSummaryLayoutPolicy.budgetCompressedTrackPreviewHeight
        )
    }
}
