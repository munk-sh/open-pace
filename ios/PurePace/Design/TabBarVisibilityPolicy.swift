import Foundation
import PurePaceRunCore

/// 底部 Tab 栏可见性判定（纯函数，输入只有会话状态与保存标记）：
/// 记录态（`running` / `paused`）与结束待保存态（`finished && !didSave`）隐藏三 Tab；
/// 其余态（`ready` / 已保存总结 / 历史 / 设置）显式恢复可见。
///
/// 判定只读状态与 `didSave`，不重建 ViewModel、不重走 `onAppear`；
/// 单测用「记录态喂 tab 数 = 1」「idle 喂 tab 数 = 0」两个反例证明能判红。
enum TabBarVisibilityPolicy {
    /// 记录态与结束待保存态隐藏 Tab 栏；期望值：隐藏 = 0，可见 = 1。
    static func hidesTabBar(state: RunSessionState, didSave: Bool) -> Bool {
        switch state {
        case .running, .paused:
            return true
        case .finished:
            return !didSave
        case .ready:
            return false
        }
    }

    static func expectedTabBarCount(state: RunSessionState, didSave: Bool) -> Int {
        hidesTabBar(state: state, didSave: didSave) ? 0 : 1
    }

    /// 点「跑步」tab / 各页「回起跑」入口时是否先把结束态收口回 `ready`。
    ///
    /// 只有 `finished` 需要收口（Tab 栏此时本就可见，属保存成功总结页）；
    /// `running` / `paused` 的 Tab 栏收起，绝不因路由动作打断正在进行的会话。
    static func resetsToReadyOnRunTabEntry(state: RunSessionState) -> Bool {
        state == .finished
    }

    struct Evaluation: Equatable {
        let expectedCount: Int
        let observedCount: Int
        let problems: [String]

        var passes: Bool {
            problems.isEmpty
        }
    }

    /// 用实测 Tab 栏数量比对期望值；反例只喂不同输入，不改生产代码即可判红。
    static func evaluate(
        state: RunSessionState,
        didSave: Bool,
        observedTabBarCount: Int
    ) -> Evaluation {
        let expected = expectedTabBarCount(state: state, didSave: didSave)
        var problems: [String] = []
        if observedTabBarCount != expected {
            problems.append("Tab 栏数量 \(observedTabBarCount) ≠ 期望 \(expected)")
        }
        return Evaluation(expectedCount: expected, observedCount: observedTabBarCount, problems: problems)
    }
}
