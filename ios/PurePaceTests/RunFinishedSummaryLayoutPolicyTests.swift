import XCTest
@testable import PurePace

/// 结束态 B1（地图 hero 360 / 内容 ≤ 691 / 操作条 68）与 C2 版式预算（L1 纯逻辑）。
///
/// 口径先定后测：标准字号档地图恒 360（≥ 852×40% = 340.8），历史 96 / 180 只作反例输入；
/// 辅助字号档仍压缩到 96（3 × `Spacing.xl`），不得把 AX5 压缩当标准档兜底。
final class RunFinishedSummaryLayoutPolicyTests: XCTestCase {
    func testStandardSizesKeepExistingTrackPreviewHeight() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false),
            360
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            360
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false),
            360,
            "标准字号档地图恒 360，不因预算档位压图"
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.blockSpacing(compresses: false),
            DesignTokens.Spacing.xs
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

    /// 压缩必须严格单调（辅助字号档逐项小于等于标准档，且地图至少省 80pt）。
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

    /// B1 重基：标准字号档不再按可用内容区压图（旧口径 688 预算压缩废）。
    /// 反例（旧实现）：内容区 612.3pt 判压缩即红——标准档地图恒 360 是无条件值。
    func testStandardSizeDoesNotCompressForShortContentBudget() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false),
            360,
            "标准档即使传入压缩档也必须保持 360"
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: 762.0 - 149.7
            )
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: 0
            )
        )
    }

    /// 标准字号档在预算充足时同样不压缩（保持 B1 的 360 地图）。
    func testStandardSizeKeepsUncompressedSummaryWhenBudgetIsEnough() {
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: RunFinishedSummaryLayoutPolicy.finishedContentHeightBudget
            )
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: false,
                availableContentHeight: RunFinishedSummaryLayoutPolicy.finishedContentHeightBudget + 120
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
        XCTAssertTrue(
            RunFinishedSummaryLayoutPolicy.compressesFinishedSummary(
                isAccessibilitySize: true,
                availableContentHeight: 0
            )
        )
    }

    /// ac-b1-map-hero-360：标准字号档地图恒 360pt 且 ≥ 屏高 40%（852 × 0.40 = 340.8）。
    func testStandardMapHeroMeets360And40Percent() {
        let height = RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false)
        XCTAssertEqual(height, 360)
        XCTAssertGreaterThanOrEqual(
            height,
            RunFinishedSummaryLayoutPolicy.referenceScreenHeight
                * RunFinishedSummaryLayoutPolicy.mapHeroMinimumRatio
        )
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsMapHero(height))
    }

    /// ac-b1-map-hero-360 反例：把历史 96 / 180 喂给 B1 地图高度判据必须判红；
    /// 340.7（差 0.1pt）也判红，340.8 与 360 通过。
    func testHistoricMapHeightsAreRejectedByMapHero() {
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsMapHero(96),
            "96pt 是 AX5 压缩档，不是标准档 B1 地图"
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsMapHero(180),
            "180pt 是改前未压缩档，必须被判红"
        )
        XCTAssertFalse(RunFinishedSummaryLayoutPolicy.meetsMapHero(340.7))
        XCTAssertFalse(RunFinishedSummaryLayoutPolicy.meetsMapHero(0))
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsMapHero(340.8))
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsMapHero(360))
    }

    /// ac-map-height-two-branches：地图高度只出现 360 / 96 两个值，`compresses` 不改变标准档。
    func testMapHeightOnlyHasUncompressedAndCompressedBranches() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            360
        )
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: false),
            360
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

    /// 辅助字号压缩档仍逐项回收：地图 360 → 96 单独就回收 264pt（≥ 80），
    /// 其余槽位压缩严格单调（反例：任一槽位回到未压缩值即判红）。
    func testCompressedNonMapSlotsRelieveTheMapDelta() {
        let mapRelief =
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: false)
            - RunFinishedSummaryLayoutPolicy.trackPreviewHeight(isAccessibilitySize: true)
        XCTAssertGreaterThanOrEqual(mapRelief, 80)
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

    /// 未压缩槽位逐项等于既有语义 token（视图层不再出现裸数字）。
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

    /// 反例方向：辅助字号档保持 96pt（不被标准档的 360 覆盖）。
    func testMapHeightKeepsAccessibilityBranch() {
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: true, isAccessibilitySize: true),
            RunFinishedSummaryLayoutPolicy.accessibilityTrackPreviewHeight
        )
        XCTAssertNotEqual(
            RunFinishedSummaryLayoutPolicy.trackPreviewHeight(compresses: false, isAccessibilitySize: false),
            RunFinishedSummaryLayoutPolicy.accessibilityTrackPreviewHeight
        )
    }

    /// ac-b1-content-fits-691：B1 实测合计 667.3 ≤ 691 通过；
    /// 改前口径（地图 96 + 整行权限提示 44 + 四指标卡 4×117.7 + 分段 114 + 块间距 48 = 772.8）
    /// 与 691.1 必须判红。
    func testFinishedContentBudgetAcceptsB1AndRejectsPreChangeOverflow() {
        XCTAssertEqual(RunFinishedSummaryLayoutPolicy.finishedContentHeightBudget, 691)
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsContentBudget(667.3))
        XCTAssertTrue(RunFinishedSummaryLayoutPolicy.meetsContentBudget(691))
        XCTAssertFalse(RunFinishedSummaryLayoutPolicy.meetsContentBudget(691.1))
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsContentBudget(96 + 44 + 4 * 117.7 + 114 + 48),
            "改前版式（地图 96 + 整行权限提示 + 四指标卡）必须超预算"
        )
    }

    /// ac-b1-action-bar-68：44pt 主操作 + 上下各 12pt = 68pt。
    func testActionBarHeightIs68() {
        XCTAssertEqual(RunFinishedSummaryLayoutPolicy.actionBarHeight, 68)
        XCTAssertEqual(
            RunFinishedSummaryLayoutPolicy.actionBarHeight,
            DesignTokens.minTapTarget + 2 * DesignTokens.Spacing.sm
        )
    }

    /// ac-b1-inline-hint：高度 ≤32pt 且宽度小于内容宽；
    /// 整行 / ≥44pt 的提示与改前整行权限条必须判红。
    func testInlineHintCapsuleJudge() {
        XCTAssertTrue(
            RunFinishedSummaryLayoutPolicy.meetsInlineHint(height: 23.7, width: 196.3, contentWidth: 361)
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsInlineHint(height: 44, width: 196.3, contentWidth: 361),
            "≥44pt 的提示不是 inline 胶囊"
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsInlineHint(height: 23.7, width: 361, contentWidth: 361),
            "整宽提示必须判红"
        )
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsInlineHint(height: 60, width: 361, contentWidth: 361)
        )
        // 改前实测反例（2026-11-12，iPhone 16 / iOS 18.6，zh-Hans 长句换 2 行）：
        // 整行 360×39.33pt 胶囊必须判红，证明「≤32 且不占整行」不是事后放阈值。
        XCTAssertFalse(
            RunFinishedSummaryLayoutPolicy.meetsInlineHint(height: 39.33, width: 360, contentWidth: 361),
            "改前整行两行胶囊（39.33pt / 360pt）必须判红"
        )
        // 现实现：图标 + 短文案单行胶囊（实测约 23.7pt、宽度由内容决定）判绿。
        XCTAssertTrue(
            RunFinishedSummaryLayoutPolicy.meetsInlineHint(height: 23.7, width: 236.3, contentWidth: 361)
        )
    }
}
