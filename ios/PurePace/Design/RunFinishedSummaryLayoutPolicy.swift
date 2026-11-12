import SwiftUI

/// 结束态（待保存屏）「轨迹预览 + 分段明细」的垂直预算：只在大字号档压缩，不改标准字号视觉。
///
/// 口径先定后测（2026-11-12）：AX5（`accessibility-extra-extra-extra-large`，393×852）实测
/// 03-run-finished 内容高 703.7pt，`run.mapPreview` 占 180pt，导致
/// `run.backgroundDegraded` 底沿 858.3 > 窗口 852、`run.finished.splits` 与 `run.save` 相交。
/// 压缩后逐项回收（全部为既有 `DesignTokens.Spacing` 派生，不新增字号档 / 色键）：
/// - 地图预览 180 → 96（= 3 × `Spacing.xl`，仍是可读的轨迹缩略），回收 84pt；
/// - 区块间距 `sectionGap` → `xxs`，回收 24pt；
/// - 分段卡内边距 `sm` → `xs`、卡内行距 `metricGroupSpacing` → `xxs`，回收 12pt。
/// 合计 120pt > 实测溢出 108pt。
enum RunFinishedSummaryLayoutPolicy {
    /// 标准字号档的地图预览高度（既有口径，保持 180pt 不变）。
    static let standardTrackPreviewHeight: CGFloat = 180
    /// 辅助字号档的地图预览高度：3 × `Spacing.xl`(32) = 96pt。
    static let accessibilityTrackPreviewHeight: CGFloat = 3 * DesignTokens.Spacing.xl

    /// 标准字号档在可用内容区不足时的地图预览高度（实测口径 → 参数 → 复用点）。
    ///
    /// 实测（2026-11-12，iPhone 16 竖屏，标准字号档保存态）：`run.averagePace` 单位行底 492.7
    /// → `run.finished.splits` 顶 620.7，最大单一垂直空洞 128pt；拆开为地图预览 96 + 区块间距 4
    /// + 分段卡内边距 8 + 文本行盒 20。地图占比 75%，是空洞主因（间距已是最小档）。
    /// 参数：要让空洞 ≤ 80pt，地图需 ≤ 48；取既有 `Spacing.xl`(32)，留 16pt 余量。
    /// 复用点：仅标准字号档且 `compressesFinishedSummary == true` 的结束总结地图；
    /// 辅助字号档仍用 96pt（AX5 可读性不变），标准未压缩档仍用 180pt。
    static let budgetCompressedTrackPreviewHeight: CGFloat = DesignTokens.Spacing.xl

    /// 地图预览高度：辅助字号档压缩到 96pt，其余档位保持既有 180pt。
    static func trackPreviewHeight(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? accessibilityTrackPreviewHeight : standardTrackPreviewHeight
    }

    /// 结束态地图高度：辅助字号档 96；标准字号档在预算不足时收到 32，预算充足时保 180。
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

    /// 结束态内容块之间的垂直间距：辅助字号档收到最小档 `xxs`。
    static func blockSpacing(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.sectionGap
    }

    /// 分段卡内边距：辅助字号档收到 `xs`。
    static func cardPadding(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? DesignTokens.Spacing.xs : DesignTokens.Spacing.sm
    }

    /// 分段卡内行距：辅助字号档收到 `xxs`，压缩「分段标题 / 分段行」的占高。
    static func rowSpacing(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? DesignTokens.Spacing.xxs : DesignTokens.Spacing.metricGroupSpacing
    }
}
