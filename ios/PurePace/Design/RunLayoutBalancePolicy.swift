import Foundation

/// 跑步页首屏四层垂直分布判定（纯函数）：
/// 区间上界为导航栏下沿、下界为主操作顶边，采集相邻可见内容块 frame 后判定
/// （a）顶部留白 ≤ 80pt；（b）底部留白 ≤ 80pt；（c）任一块间垂直空洞 ≤ 80pt；
/// （d）上下留白差 |顶部 − 底部| ≤ 16pt。
///
/// 阈值在**测量前**即按设计口径写死（2026-11-11，先定后测，未因判红回调）：
/// - `80 = 2.5 × Spacing.xl(32)`，约 iPhone 16 竖屏（852pt）的 9.4%，且小于旧布局
///   实测死白 116.3pt / 128.0pt 的 2/3，肉眼不再构成「块级死白」；
/// - `16 = Spacing.md`，等于卡片内一档固定间距，保证上下不偏而非机械居中。
///
/// 单测用旧布局实测帧（顶 28 / 底 251.6）与本轮截图实测帧（顶 128.0 / 底 116.3）
/// 反例证明判红；四态代表帧（顶/底 ≈ 57.5）证明判绿；UI 用例用真实 frame 喂同一实现。
enum RunLayoutBalancePolicy {
    /// 顶部留白允许上限。
    static let maximumTopGap: CGFloat = 80
    /// 底部留白允许上限。
    static let maximumBottomGap: CGFloat = 80
    /// 内容区允许的最大单一垂直空洞（含块间空洞）。
    static let maximumGap: CGFloat = 80
    /// 上下留白允许的最大差值。
    static let maximumImbalance: CGFloat = 16

    struct Evaluation: Equatable {
        let topGap: CGFloat
        let bottomGap: CGFloat
        let largestGap: CGFloat
        let imbalance: CGFloat
        let problems: [String]

        var passes: Bool {
            problems.isEmpty
        }
    }

    static func evaluate(
        contentFrames: [CGRect],
        navigationBarBottom: CGFloat,
        primaryActionTop: CGFloat
    ) -> Evaluation {
        let sorted = contentFrames
            .filter { !$0.isEmpty }
            .sorted { $0.minY < $1.minY }
        guard let first = sorted.first, let last = sorted.last else {
            return Evaluation(
                topGap: 0,
                bottomGap: 0,
                largestGap: .infinity,
                imbalance: 0,
                problems: ["未采集到任何可见内容块"]
            )
        }

        let topGap = first.minY - navigationBarBottom
        let bottomGap = primaryActionTop - last.maxY
        var gaps = [topGap, bottomGap]
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            gaps.append(next.minY - current.maxY)
        }
        let largestGap = gaps.max() ?? 0
        let imbalance = abs(topGap - bottomGap)

        var problems: [String] = []
        if topGap < 0 {
            problems.append("内容顶边 \(first.minY) 高于导航栏下沿 \(navigationBarBottom)")
        }
        if bottomGap < 0 {
            problems.append("内容底边 \(last.maxY) 低于主操作顶边 \(primaryActionTop)")
        }
        if topGap > maximumTopGap {
            problems.append("顶部留白 \(topGap)pt > \(maximumTopGap)pt")
        }
        if bottomGap > maximumBottomGap {
            problems.append("底部留白 \(bottomGap)pt > \(maximumBottomGap)pt")
        }
        if largestGap > maximumGap {
            problems.append("最大单一垂直空洞 \(largestGap)pt > \(maximumGap)pt")
        }
        if imbalance > maximumImbalance {
            problems.append("上下留白差 \(imbalance)pt > \(maximumImbalance)pt")
        }
        return Evaluation(
            topGap: topGap,
            bottomGap: bottomGap,
            largestGap: largestGap,
            imbalance: imbalance,
            problems: problems
        )
    }
}
