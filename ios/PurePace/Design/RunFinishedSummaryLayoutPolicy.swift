import SwiftUI

/// 结束态（待保存屏）「轨迹预览 + 分段明细」的垂直预算：只在压缩档回收，不改未压缩视觉。
///
/// 口径先定后测（2026-11-12）：AX5（`accessibility-extra-extra-extra-large`，393×852）实测
/// 03-run-finished 内容高 703.7pt，`run.mapPreview` 占 180pt，导致
/// `run.backgroundDegraded` 底沿 858.3 > 窗口 852、`run.finished.splits` 与 `run.save` 相交。
/// 压缩后逐项回收（全部为既有 `DesignTokens.Spacing` 派生，不新增字号档 / 色键）：
/// - 地图预览 180 → 96（= 3 × `Spacing.xl`，仍是可读的轨迹缩略），回收 84pt；
/// - 区块间距 `sectionGap` → `xxs`，回收 24pt；
/// - 分段卡内边距 `sm` → `xs`、卡内行距 `metricGroupSpacing` → `xxs`，回收 12pt。
/// 合计 120pt > 实测溢出 108pt。
///
/// 2026-11-12 回归（`2d40bc0` 引入，经 `4d522e6` 合入 main）：标准字号档压缩分支曾把地图压到 `Spacing.xl`(32)，
/// iPhone 16 竖屏保存态实测地图只剩 32pt 细条，轨迹预览卡不再成立。本项把地图下限回 96，
/// 多占的 64pt 从非地图槽位（顶部呼吸位 / hero 上呼吸位 / hero→指标间距 / 指标卡内边距与行距）
/// 逐一回收，全部以命名参数落在这里；视图层只读参数或既有 token，不写裸数字。
enum RunFinishedSummaryLayoutPolicy {
    /// 标准字号档的地图预览高度（既有口径，保持 180pt 不变）。
    static let standardTrackPreviewHeight: CGFloat = 180
    /// 结束态地图预览的视觉下限：3 × `Spacing.xl`(32) = 96pt（标准压缩档与 AX5 档同值）。
    static let finishedMapFloor: CGFloat = 3 * DesignTokens.Spacing.xl
    /// 辅助字号档的地图预览高度：与视觉下限同值 96pt。
    static let accessibilityTrackPreviewHeight: CGFloat = finishedMapFloor

    /// 标准字号档在可用内容区不足时的地图预览高度（实测口径 → 参数 → 复用点）。
    ///
    /// 实测（2026-11-12，iPhone 16 竖屏 / iOS 18.6，标准字号档保存态）：`2d40bc0` 把该值
    /// 压到 `Spacing.xl`(32)，`run.mapPreview` 实测高度 32pt，视觉退化成细条（本项修回 96）。
    /// 参数：96 = `finishedMapFloor` = 3 × `Spacing.xl`，与 AX5 压缩档同值，仍可读轨迹缩略。
    /// 复用点：仅压缩档（标准字号预算不足 + 辅助字号档）的结束总结地图；未压缩标准档仍用 180。
    static let budgetCompressedTrackPreviewHeight: CGFloat = finishedMapFloor

    /// 地图预览高度判据：结束态实测高度必须 ≥ 96pt（改前 32 命中必红，反例见单测）。
    static func meetsMapFloor(_ measuredHeight: CGFloat) -> Bool {
        measuredHeight >= finishedMapFloor
    }

    /// 地图预览高度：辅助字号档压缩到 96pt，其余档位保持既有 180pt。
    static func trackPreviewHeight(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? accessibilityTrackPreviewHeight : standardTrackPreviewHeight
    }

    /// 结束态地图高度：辅助字号档恒 96；标准字号档压缩档 96、未压缩档 180。
    static func trackPreviewHeight(compresses: Bool, isAccessibilitySize: Bool) -> CGFloat {
        if isAccessibilitySize {
            return accessibilityTrackPreviewHeight
        }
        return compresses ? budgetCompressedTrackPreviewHeight : standardTrackPreviewHeight
    }

    /// 未压缩结束态所需的最小内容区高度（实测口径 → 参数 → 复用点）。
    ///
    /// 实测（2026-11-12，iPhone 16 竖屏 393×852，标准字号档）：可用内容区 =
    /// 导航栏下沿 149.7 → 主操作顶边 762.0，共 612.3pt；结束待保存屏未压缩内容实测底沿 837.3，
    /// `run.backgroundDegraded` 与 `run.save` 相交 75.3pt（保存态叠加「已保存」提示后溢出更多）。
    /// 参数：未压缩所需内容区 ≥ 612.3 + 75.3 = 687.6 → 取整 688。
    /// 复用点：`RunView` 的结束总结（地图高度 / 区块间距 / 分段卡内边距与行距）与滚动体最小高度，
    /// 三处共用同一判定，不逐屏补丁、不在视图层写裸数字。
    static let uncompressedFinishedContentHeight: CGFloat = 688

    /// 结束态是否走压缩档：辅助字号档恒压缩；标准字号档只在可用内容区够不到未压缩预算时压缩。
    /// 反例只喂不同输入即可判红，不需要改生产代码。
    static func compressesFinishedSummary(
        isAccessibilitySize: Bool,
        availableContentHeight: CGFloat
    ) -> Bool {
        if isAccessibilitySize {
            return true
        }
        return availableContentHeight < uncompressedFinishedContentHeight
    }

    // MARK: - 结束态垂直槽位（压缩档 = 实测值 → 参数 → 复用点）

    /// 结束态顶部呼吸位：屏幕顶部 → hero。
    ///
    /// 实测（2026-11-12，保存态，iPhone 16 竖屏 / iOS 18.6）：该槽位是唯一「钉住上沿」的弹性位，
    /// 内容随分段行数增长时顶部恒等于它、底部余量被吃光。两种 canonical 内容实测——
    /// 0 行（400m）：顶 16 / 底 32，上下差 16.0000000000001pt 正好超限；1 行（1200m）：顶 16 / 底 12。
    /// 取两组的中间档 20（= `md` + `xxs`）后：0 行 顶 20 / 底 28（差 8）、1 行 顶 20 / 底 8（差 8→12），
    /// 两种内容都能在 16pt 阈值内且不贴边。这 4pt 有意留在顶部而不回收，是救济总量 60 而非 64 的原因。
    /// 复用点：`RunView.balancedMetrics` 首个等权 Spacer（仅结束态压缩档；其余态/档位仍用 `screenTop`）。
    static func topBreathing(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.md + DesignTokens.Spacing.xxs : DesignTokens.Spacing.screenTop
    }

    /// hero 面板上呼吸位：实测 `sm`(12) 在压缩档归零（回收 12pt），余量交回等权 Spacer。
    /// 复用点：`RunView.distanceHero` 的 `.padding(.top,)`。
    static func heroTopPadding(compresses: Bool) -> CGFloat {
        compresses ? 0 : DesignTokens.Spacing.sm
    }

    /// hero → 指标卡的层间距：实测 `cardGap`(16) 在压缩档收到 `xs`(8)，回收 8pt。
    /// 复用点：`RunView.balancedMetrics` 第二个等权 Spacer。
    static func heroMetricsGap(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xs : DesignTokens.Spacing.cardGap
    }

    /// 指标卡四边内边距：实测 `cardPadding`(16) 在压缩档收到 `sm`(12)，垂直回收 8pt。
    /// 复用点：`RunView.metricsPanel` 的 `.padding(...)`。
    static func metricCardPadding(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.sm : DesignTokens.Spacing.cardPadding
    }

    /// 指标卡底部补白：实测 `xxs`(4) 在压缩档归零，回收 4pt（余量交回等权 Spacer）。
    /// 复用点：`RunView.metricsPanel` 的 `.padding(.bottom,)`。
    static func metricCardBottomPadding(compresses: Bool) -> CGFloat {
        compresses ? 0 : DesignTokens.Spacing.xxs
    }

    /// 指标卡内三行组间距：实测 `metricGroupGap`(16) 在压缩档收到 `xxs`(4)，两处组间回收 24pt。
    /// 复用点：`RunView.metricsPanel` 纵向 `VStack(spacing:)`（横向列间距仍用 token）。
    static func metricGroupGap(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.metricGroupGap
    }

    /// 结束态内容块之间的垂直间距：压缩档收到最小档 `xxs`。
    /// 复用点：`RunView.finishedTrackSummary` 的地图 → 分段卡间距。
    static func blockSpacing(compresses: Bool) -> CGFloat {
        compresses ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.sectionGap
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
