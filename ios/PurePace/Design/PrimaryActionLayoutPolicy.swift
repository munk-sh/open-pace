import Foundation

/// 主操作底部锚定判定（纯函数）：
/// （a）按钮高 ≥ 44pt；（b）按钮底边距内容底部安全区（TabBar 顶边）≤ 24pt；（c）位于 TabBar 之上。
/// 单测用「距安全区 200pt / 高 30pt」反例证明能红；UI 用例用真实按钮与 TabBar frame 喂同一判定。
enum PrimaryActionLayoutPolicy {
    /// 与 `DesignTokens.minTapTarget` 对齐（单测保证二者相等）。
    static let minimumActionHeight: CGFloat = 44
    /// 底部安全区上方允许的最大间距。
    static let maximumBottomGap: CGFloat = 24

    struct Evaluation: Equatable {
        let height: CGFloat
        let bottomGap: CGFloat
        let isAboveTabBar: Bool
        let problems: [String]

        var passes: Bool {
            problems.isEmpty
        }
    }

    static func evaluate(actionFrame: CGRect, tabBarFrame: CGRect) -> Evaluation {
        let height = actionFrame.height
        let bottomGap = tabBarFrame.minY - actionFrame.maxY
        var problems: [String] = []
        if height < minimumActionHeight {
            problems.append("按钮高度 \(height)pt < \(minimumActionHeight)pt")
        }
        if bottomGap > maximumBottomGap {
            problems.append("底部间距 \(bottomGap)pt > \(maximumBottomGap)pt")
        }
        if bottomGap < 0 {
            problems.append("按钮底边 \(actionFrame.maxY) 低于 TabBar 顶边 \(tabBarFrame.minY)")
        }
        return Evaluation(
            height: height,
            bottomGap: bottomGap,
            isAboveTabBar: bottomGap >= 0,
            problems: problems
        )
    }
}

// MARK: - AX5（最大辅助字号档）主操作几何判定

/// 声明口径：生产侧 `Typography.control` 目前是固定 20pt 档（`Font.system(size:)`，不随
/// Dynamic Type 缩放）。本判定按验收口径以 `UIFontMetrics` 解析 AX5 需求高度后由测试注入几何，
/// 属**注入式几何断言**，不代表运行态已实测 AX5 渲染；生产布局本项未改。
extension PrimaryActionLayoutPolicy {
    /// 判定容差（pt）。
    ///
    /// 阈值先定后测：设定日期 2026-11-11，依据为 AX5 下 SwiftUI 布局取整最多产生亚点级误差；
    /// 0.5pt 远小于 44pt 最小点按区与最小 8pt 视觉留白，掩盖不了任何真实重叠或裁剪，
    /// 因此判红后不得回调本值。
    static let layoutTolerance: CGFloat = 0.5

    /// AX5 几何判定问题项（结构化，反例按具体项断言，避免「任一条红即通过」）。
    enum AccessibilityIssue: String, CaseIterable, Equatable {
        /// ① 主操作高度低于 Apple HIG 最小点按区。
        case heightBelowMinimum = "主操作高度低于最小点按区"
        /// ② 主操作与上方指标 / 提示区重叠。
        case overlapsUpperContent = "主操作与上方内容重叠"
        /// ② 主操作超出可用高度（被裁剪）。
        case exceedsAvailableHeight = "主操作超出可用高度（被裁剪）"
        /// ③ 主操作文案理想尺寸超出按钮文字区（被截断）。
        case textTruncated = "主操作文案被截断"
    }

    /// AX5 判定输入。字号 / 文案理想尺寸由测试侧用 `UIFontMetrics` 与
    /// `NSString.size(withAttributes:)` 解析后注入，Design 层不引入 UIKit，也不做运行态测量。
    struct AccessibilityGeometry: Equatable {
        /// 主操作按钮 frame（内容撑高后的实际高度）。
        let actionFrame: CGRect
        /// 上方指标 / 提示区内容底沿。
        let contentBottom: CGFloat
        /// 主操作可用区间的上沿。
        let availableTop: CGFloat
        /// 主操作可用区间的下沿。
        let availableBottom: CGFloat
        /// 主操作文案在 AX5 解析字体下的理想尺寸。
        let textSize: CGSize
        /// 文案区相对 `actionFrame` 的横 / 纵内边距（测试侧注入 `DesignTokens.Spacing` 档位）。
        let textInsets: CGSize
    }

    struct AccessibilityEvaluation: Equatable {
        let height: CGFloat
        let contentGap: CGFloat
        let textArea: CGRect
        let issues: [AccessibilityIssue]

        var passes: Bool {
            issues.isEmpty
        }
    }

    /// AX5 主操作几何判定（纯函数，只依赖 Foundation / CoreGraphics）。
    ///
    /// 阈值口径于 2026-11-11 在实现前写死（先定后测，判红后未回调）：
    /// ① 高度 ≥ `minimumActionHeight`（44pt = Apple HIG 最小点按区，与 `DesignTokens.minTapTarget` 同源）；
    /// ② 不重叠：`actionFrame.minY >= contentBottom`；不裁剪：`actionFrame.maxY <= availableBottom`
    ///    且 `actionFrame.minY >= availableTop`（不允许「静默裁剪也算通过」）；
    /// ③ 文案不截断：文案理想尺寸 ≤ 文字区（`actionFrame` 内缩注入的横 / 纵内边距）。
    /// ②③ 的比较允许 `layoutTolerance`（0.5pt）；① 为硬阈值，不参与容差。
    static func evaluateAccessibilityLayout(
        _ geometry: AccessibilityGeometry,
        tolerance: CGFloat = layoutTolerance
    ) -> AccessibilityEvaluation {
        let actionFrame = geometry.actionFrame
        let height = actionFrame.height
        let contentGap = actionFrame.minY - geometry.contentBottom
        let textArea = textArea(for: actionFrame, insets: geometry.textInsets)

        var issues: [AccessibilityIssue] = []
        if height < minimumActionHeight {
            issues.append(.heightBelowMinimum)
        }
        if contentGap < -tolerance {
            issues.append(.overlapsUpperContent)
        }
        if actionFrame.maxY > geometry.availableBottom + tolerance
            || actionFrame.minY < geometry.availableTop - tolerance {
            issues.append(.exceedsAvailableHeight)
        }
        if geometry.textSize.width > textArea.width + tolerance
            || geometry.textSize.height > textArea.height + tolerance {
            issues.append(.textTruncated)
        }
        return AccessibilityEvaluation(
            height: height,
            contentGap: contentGap,
            textArea: textArea,
            issues: issues
        )
    }

    /// 文案区：`actionFrame` 内缩横 / 纵内边距；负尺寸归零，避免异常输入被静默放大成「通过」。
    static func textArea(for actionFrame: CGRect, insets: CGSize) -> CGRect {
        CGRect(
            x: actionFrame.minX + insets.width,
            y: actionFrame.minY + insets.height,
            width: max(0, actionFrame.width - insets.width * 2),
            height: max(0, actionFrame.height - insets.height * 2)
        )
    }
}
