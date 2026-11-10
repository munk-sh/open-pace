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
