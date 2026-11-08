import XCTest

/// 真实链路 UI 测试：依赖 `scripts/test-ios.sh` 在测试前用
/// `xcrun simctl location start --speed=3 --interval=1` 注入 CoreLocation 更新。
/// 不使用 launch-arg 假流、不内置样例、不以固定 sleep 作为成功判据。
final class RunFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRunPauseResumeFinishAndHistory() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Location Authorization") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow", "使用 App 期间允许", "允许一次"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
        allowLocationIfNeeded()

        let distance = app.staticTexts["run.distance"]
        let elapsed = app.staticTexts["run.elapsed"]
        XCTAssertTrue(distance.waitForExistence(timeout: 30), "跑步页缺少距离读数")
        XCTAssertTrue(elapsed.exists, "跑步页缺少时长读数")
        XCTAssertEqual(distance.label, "0.00 km", "未开始时距离必须为零")
        XCTAssertEqual(elapsed.label, "00:00", "未开始时时长必须为零")
        XCTAssertEqual(app.staticTexts["run.currentPace"].label, "--", "未开始时当前配速必须为空")
        XCTAssertEqual(app.staticTexts["run.averagePace"].label, "--", "未开始时平均配速必须为空")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "缺少 Tab 栏")
        XCTAssertTrue(tabBar.buttons["Settings"].exists, "缺少 Settings Tab")
        XCTAssertFalse(tabBar.buttons["Log"].exists, "Log Tab 应已移除")

        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "缺少开始按钮")

        // 空态诚实：未开跑时 History 只有空态，不渲染任何示例跑次。
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "缺少 History Tab")
        historyTab.tap()
        XCTAssertTrue(
            app.staticTexts["history.empty"].waitForExistence(timeout: 10),
            "无记录时 History 应显示空态"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "history.row").count,
            0,
            "空态下不应渲染任何跑次"
        )
        XCTAssertTrue(app.tabBars.buttons["Run"].waitForExistence(timeout: 10), "缺少 Run Tab")
        app.tabBars.buttons["Run"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "返回跑步页后缺少开始按钮")

        start.tap()

        let startedDistance = distance.label
        let startedElapsed = elapsed.label
        XCTAssertTrue(
            waitUntil(timeout: 30) { distance.label != startedDistance },
            "开始后距离没有随真实定位变化"
        )
        XCTAssertTrue(
            waitUntil(timeout: 10) { elapsed.label != startedElapsed },
            "开始后时长没有随真实采样增长"
        )

        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "运行时缺少暂停按钮")
        pause.tap()

        XCTAssertTrue(
            waitUntil(timeout: 10) { app.buttons["run.resume"].exists },
            "暂停后未进入可恢复状态"
        )
        XCTAssertEqual(app.staticTexts["run.currentPace"].label, "--", "暂停时当前配速必须为空")
        let pausedDistance = distance.label
        let pausedElapsed = elapsed.label
        XCTAssertTrue(waitWindow(seconds: 4), "暂停观察窗口未完成")
        XCTAssertEqual(distance.label, pausedDistance, "暂停期间距离不得增长")
        XCTAssertEqual(elapsed.label, pausedElapsed, "暂停期间时长不得增长")

        let resume = app.buttons["run.resume"]
        XCTAssertTrue(resume.exists, "缺少恢复按钮")
        resume.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) { distance.label != pausedDistance },
            "恢复后距离没有继续增长"
        )

        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()

        XCTAssertTrue(
            app.staticTexts["run.saved"].waitForExistence(timeout: 10),
            "结束后缺少「已保存」反馈"
        )
        XCTAssertFalse(app.buttons["run.finish"].exists, "结束后不应再有结束按钮")

        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "缺少 History Tab")
        historyTab.tap()

        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        XCTAssertTrue(
            waitUntil(timeout: 15) { rows.count == 1 },
            "History 应恰有 1 条真实记录，实际 \(rows.count) 条"
        )
        XCTAssertFalse(app.staticTexts["history.empty"].exists, "有记录时不应显示空态")
    }

    // MARK: - 授权与等待

    private func allowLocationIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Allow While Using App", "Allow Once", "Allow", "使用 App 期间允许", "允许一次"]
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists {
                    button.tap()
                    return
                }
            }
            if springboard.alerts.firstMatch.exists {
                for label in labels {
                    let button = springboard.alerts.firstMatch.buttons[label]
                    if button.exists {
                        button.tap()
                        return
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// 观察窗口：不把「经过固定时长」当作成功判据，只用于验证暂停期间数值不变。
    private func waitWindow(seconds: TimeInterval) -> Bool {
        let expected = expectation(description: "pause observation window")
        expected.isInverted = true
        wait(for: [expected], timeout: seconds)
        return true
    }
}
