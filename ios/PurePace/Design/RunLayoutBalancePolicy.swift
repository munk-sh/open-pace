import Foundation

/// 跑步页指标区垂直居中判定（纯函数）：
/// 区间上界为导航栏下沿、下界为主操作顶边，采集相邻可见内容块 frame 后
/// （a）内容区最大单一垂直空洞（导航栏下沿 → 首块、块间、末块 → 主操作顶边）≤ 160pt；
/// （b）上下留白差 |顶部空白 − 底部空白| ≤ 40pt。
/// 单测用本轮实测旧布局（内容 177.7–447.4、导航栏下沿 149.7、主操作顶边 699.0 →
/// 底部空洞 251.6pt / 上下差 223.6pt）反例证明两条判据均能红；UI 用例用真实 frame 喂同一实现。
enum RunLayoutBalancePolicy {
    /// 内容区允许的最大单一垂直空洞。
    static let maximumGap: CGFloat = 160
    /// 上下留白允许的最大差值。
    static let maximumImbalance: CGFloat = 40

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
