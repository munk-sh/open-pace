import SwiftUI

/// 结束态（B1 地图 hero / C2 丢弃确认层）的版式预算：地图 360、内容 ≤ 691、操作条 68。
///
/// 口径先定后测（V1.2 定稿，`docs/design-draft-v12/`）：iPhone 16 竖屏 393×852、
/// 根内容区 759pt 去掉底部 68pt 主操作条后可用 691pt；B1 实测
/// 地图 360.0 + 指标 117.7 + 分段 114.0 + inline 提示 23.7 + 固定间距 48 ≈ 667.3 ≤ 691。
/// 标准字号档地图恒为 360（≥ 852×40% = 340.8），历史 96 / 180 只能作为反例输入；
/// 辅助字号档沿用既有 96pt 压缩分支（3 × `Spacing.xl`），不把 AX5 压缩当标准档兜底。
enum RunFinishedSummaryLayoutPolicy {
    /// B1 标准字号档地图 hero 高度（无条件，不随预算或压缩档变化）。
    static let standardMapHeroHeight: CGFloat = 360
    /// 版式基准屏高（iPhone 16 竖屏），只用于 40% 地图门槛判据。
    static let referenceScreenHeight: CGFloat = 852
    /// 地图 hero 占屏高门槛：40%（340.8 = 852 × 0.40）。
    static let mapHeroMinimumRatio: CGFloat = 0.40
    /// 主页面的内容预算：根内容区 759 − 底部主操作条 68 = 691。
    static let finishedContentHeightBudget: CGFloat = 691
    /// inline 提示胶囊的高度上限（目标实测 23.7pt）。
    static let inlineHintMaxHeight: CGFloat = 32
    /// 辅助字号档的地图预览高度：与既有视觉下限同值 96pt。
    static let accessibilityTrackPreviewHeight: CGFloat = 3 * DesignTokens.Spacing.xl
    /// C2 自适应高度在 iOS 17 上的兜底高度（内容实测 143.7，取整覆盖 44pt 主操作 + 内边距）。
    static let discardSheetFallbackHeight: CGFloat = 144

    /// 主操作条高度：44pt 主操作 + 上下各 12pt = 68pt（固定底部安全区上方）。
    static var actionBarHeight: CGFloat {
        DesignTokens.minTapTarget + 2 * DesignTokens.Spacing.sm
    }

    /// 地图 hero 门槛：≥ 852 × 40% = 340.8pt；96 / 180 一律判红。
    static func meetsMapHero(_ measuredHeight: CGFloat) -> Bool {
        measuredHeight >= referenceScreenHeight * mapHeroMinimumRatio
    }

    /// 内容预算判据：地图 + 指标 + 分段 + inline 提示合计 ≤ 691pt。
    static func meetsContentBudget(_ measuredHeight: CGFloat) -> Bool {
        measuredHeight <= finishedContentHeightBudget
    }

    /// inline 提示胶囊判据：高度 ≤ 32pt 且宽度小于内容宽（不占满整行）。
    static func meetsInlineHint(
        height: CGFloat,
        width: CGFloat,
        contentWidth: CGFloat
    ) -> Bool {
        height <= inlineHintMaxHeight && width < contentWidth
    }

    /// 地图高度：辅助字号档 96pt（既有压缩分支），标准字号档恒 360pt。
    /// `compresses` 参数保留给既有调用点迁移，但不改变标准档地图高度。
    static func trackPreviewHeight(compresses: Bool, isAccessibilitySize: Bool) -> CGFloat {
        _ = compresses
        return trackPreviewHeight(isAccessibilitySize: isAccessibilitySize)
    }

    /// 地图高度便捷入口：辅助字号档 96pt，其余 360pt。
    static func trackPreviewHeight(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? accessibilityTrackPreviewHeight : standardMapHeroHeight
    }

    /// 结束态是否走压缩档：只有辅助字号档压缩；标准字号档地图恒 360，
    /// 不再按内容区预算压图或压字号（B1 版式本身已落在 691 预算内）。
    static func compressesFinishedSummary(
        isAccessibilitySize: Bool,
        availableContentHeight: CGFloat
    ) -> Bool {
        _ = availableContentHeight
        return isAccessibilitySize
    }

    // MARK: - 结束态垂直槽位（压缩档 = 实测值 → 参数 → 复用点）

    /// 结束态顶部呼吸位：屏幕顶部 → hero。
    ///
    /// 实测（2026-11-12，保存态，iPhone 16 竖屏 / iOS 18.6）：该槽位是唯一「钉住上沿」的弹性位，
    /// 内容随分段行数增长时顶部恒等于它、底部余量被吃光。两种 canonical 内容实测——
    /// 0 行（400m）：顶 16 / 底 32，上下差 16.0000000000001pt 正好超限；1 行（1200m）：顶 16 / 底 12。
    /// 取两组的中间档 20（= `md` + `xxs`）后：0 行 顶 20 / 底 28（差 8）、1 行 顶 20 / 底 8（差 8→12），
    /// 两种内容都能在 16pt 阈值内且不贴边。这 4pt 有意留在顶部而不回收，是救济总量 60 而非 64 的原因。
    /// 复用点：`RunView` 非结束态的等权 Spacer（仅辅助字号压缩档；其余态/档位仍用 `screenTop`）。
    static func topBreathing(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.md + DesignTokens.Spacing.xxs : DesignTokens.Spacing.screenTop
    }

    /// hero 面板上呼吸位：实测 `sm`(12) 在压缩档归零（回收 12pt），余量交回等权 Spacer。
    /// 复用点：`RunView.distanceHero`（非结束态）的 `.padding(.top,)`。
    static func heroTopPadding(compresses: Bool) -> CGFloat {
        compresses ? 0 : DesignTokens.Spacing.sm
    }

    /// hero → 指标卡的层间距：实测 `cardGap`(16) 在压缩档收到 `xs`(8)，回收 8pt。
    /// 复用点：`RunView` 非结束态的等权 Spacer。
    static func heroMetricsGap(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xs : DesignTokens.Spacing.cardGap
    }

    /// 指标卡四边内边距：实测 `cardPadding`(16) 在压缩档收到 `sm`(12)，垂直回收 8pt。
    /// 复用点：`RunView.metricsPanel`（非结束态）的 `.padding(...)`。
    static func metricCardPadding(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.sm : DesignTokens.Spacing.cardPadding
    }

    /// 指标卡底部补白：实测 `xxs`(4) 在压缩档归零，回收 4pt（余量交回等权 Spacer）。
    /// 复用点：`RunView.metricsPanel`（非结束态）的 `.padding(.bottom,)`。
    static func metricCardBottomPadding(compresses: Bool) -> CGFloat {
        compresses ? 0 : DesignTokens.Spacing.xxs
    }

    /// 指标卡内三行组间距：实测 `metricGroupGap`(16) 在压缩档收到 `xxs`(4)，两处组间回收 24pt。
    /// 复用点：`RunView.metricsPanel` 纵向 `VStack(spacing:)`（横向列间距仍用 token）。
    static func metricGroupGap(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.metricGroupGap
    }

    /// 结束态内容块之间的垂直间距：压缩档收到最小档 `xxs`。
    /// 复用点：`RunView.finishedContent` 的地图 → 指标 → 分段 → 提示间距。
    static func blockSpacing(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.xs
    }

    /// 分段卡内边距：压缩档收到 `xs`。
    /// 复用点：`RunView.splitsDetail` 的 `.padding(...)`。
    static func cardPadding(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm
    }

    /// 分段卡内行距：压缩档收到 `xxs`，压缩「分段标题 / 分段行」的占高。
    /// 复用点：`RunView.splitsDetail` 的 `VStack(spacing:)`。
    static func rowSpacing(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.metricGroupSpacing
    }
}
