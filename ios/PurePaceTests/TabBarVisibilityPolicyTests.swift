import XCTest
import PurePaceRunCore
@testable import PurePace

/// 只断言 Tab 栏可见性判定：期望值由状态 + `didSave` 派生，实测数量作为可注入输入；
/// 反例只喂不同数量，不依赖 UI，也不靠改生产代码才判红。
final class TabBarVisibilityPolicyTests: XCTestCase {
    func testRecordingStatesHideTabBar() {
        for state in [RunSessionState.running, .paused] {
            XCTAssertTrue(TabBarVisibilityPolicy.hidesTabBar(state: state, didSave: false), "\(state) 应隐藏 Tab")
            XCTAssertEqual(TabBarVisibilityPolicy.expectedTabBarCount(state: state, didSave: false), 0)
            let evaluation = TabBarVisibilityPolicy.evaluate(state: state, didSave: false, observedTabBarCount: 0)
            print("ac-tabbar-hidden state=\(state.rawValue) expected=\(evaluation.expectedCount) observed=\(evaluation.observedCount)")
            XCTAssertTrue(evaluation.passes, "\(state): \(evaluation.problems)")
        }
    }

    func testFinishedUnsavedHidesTabBar() {
        XCTAssertTrue(TabBarVisibilityPolicy.hidesTabBar(state: .finished, didSave: false), "结束待保存态应隐藏 Tab")
        let evaluation = TabBarVisibilityPolicy.evaluate(state: .finished, didSave: false, observedTabBarCount: 0)
        XCTAssertTrue(evaluation.passes, "\(evaluation.problems)")
    }

    func testIdleAndSavedStatesShowTabBar() {
        for (state, didSave) in [(RunSessionState.ready, false), (.finished, true)] {
            XCTAssertFalse(
                TabBarVisibilityPolicy.hidesTabBar(state: state, didSave: didSave),
                "\(state) didSave=\(didSave) 应恢复 Tab"
            )
            let evaluation = TabBarVisibilityPolicy.evaluate(
                state: state,
                didSave: didSave,
                observedTabBarCount: 1
            )
            print("ac-tabbar-restored state=\(state.rawValue) didSave=\(didSave) expected=\(evaluation.expectedCount) observed=\(evaluation.observedCount)")
            XCTAssertTrue(evaluation.passes, "\(state) didSave=\(didSave): \(evaluation.problems)")
        }
    }

    /// 反例：记录态却仍可见表格 → 必须判红。
    func testRecordingStateWithVisibleTabBarFails() {
        let evaluation = TabBarVisibilityPolicy.evaluate(state: .running, didSave: false, observedTabBarCount: 1)
        XCTAssertFalse(evaluation.passes, "记录态 tabBarCount=1 必须判红")
        XCTAssertEqual(evaluation.expectedCount, 0)
        XCTAssertEqual(evaluation.problems, ["Tab 栏数量 1 ≠ 期望 0"])
    }

    /// 反例：idle 却没有 Tab 栏 → 必须判红。
    func testIdleStateWithHiddenTabBarFails() {
        let evaluation = TabBarVisibilityPolicy.evaluate(state: .ready, didSave: false, observedTabBarCount: 0)
        XCTAssertFalse(evaluation.passes, "idle tabBarCount=0 必须判红")
        XCTAssertEqual(evaluation.expectedCount, 1)
        XCTAssertEqual(evaluation.problems, ["Tab 栏数量 0 ≠ 期望 1"])
    }
}
