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
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "runDetail.root").count,
            0,
            "归档为空时详情不可达"
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

        let row = rows.firstMatch
        let rowLabel = row.label
        XCTAssertTrue(rowLabel.contains(" km"), "历史行缺少距离文本")
        XCTAssertTrue(rowLabel.contains(":"), "历史行缺少时长文本")
        XCTAssertTrue(rowLabel.contains("/km"), "历史行缺少平均配速文本")

        row.tap()

        let detailRoot = app.descendants(matching: .any).matching(identifier: "runDetail.root").firstMatch
        XCTAssertTrue(
            detailRoot.waitForExistence(timeout: 10),
            "点击历史行后未进入跑次详情"
        )

        let detailStarted = app.staticTexts["runDetail.startedAt"]
        let detailEnded = app.staticTexts["runDetail.endedAt"]
        XCTAssertTrue(detailStarted.waitForExistence(timeout: 5), "详情缺少开始时间")
        XCTAssertTrue(detailEnded.exists, "详情缺少结束时间")
        XCTAssertFalse(detailStarted.label.isEmpty)
        XCTAssertNotEqual(detailStarted.label, detailEnded.label, "起止时间必须可区分")

        let detailDistance = app.staticTexts["runDetail.distance"]
        let detailActiveDuration = app.staticTexts["runDetail.activeDuration"]
        let detailAveragePace = app.staticTexts["runDetail.averagePace"]
        XCTAssertTrue(detailDistance.exists, "详情缺少总距离")
        XCTAssertTrue(detailActiveDuration.exists, "详情缺少活跃时长")
        XCTAssertTrue(detailAveragePace.exists, "详情缺少平均配速")
        XCTAssertTrue(rowLabel.contains(detailDistance.label), "详情距离必须与列表同源")
        XCTAssertTrue(rowLabel.contains(detailActiveDuration.label), "详情时长必须与列表同源")
        XCTAssertTrue(rowLabel.contains(detailAveragePace.label), "详情配速必须与列表同源")

        let splits = app.staticTexts["runDetail.splits"]
        XCTAssertTrue(splits.waitForExistence(timeout: 5), "详情缺少分段区域")
        let splitRows = app.descendants(matching: .any).matching(identifier: "runDetail.splitRow")
        let expectedSplits = splitCount(from: splits.label)
        XCTAssertEqual(
            splitRows.count,
            expectedSplits,
            "详情分段行数必须等于摘要条数，实际 \(splitRows.count) / \(expectedSplits)"
        )
        if expectedSplits == 0 {
            XCTAssertTrue(
                app.staticTexts["runDetail.splitsEmpty"].exists,
                "无分段时详情应显示诚实空态"
            )
        }

        let exportButton = app.buttons["runDetail.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "详情缺少导出按钮")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "runDetail.exported").count,
            0,
            "落盘前不得出现导出完成态"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "runDetail.share").count,
            0,
            "落盘前不得出现分享入口"
        )
        exportButton.tap()

        let exported = app.staticTexts["runDetail.exported"]
        XCTAssertTrue(exported.waitForExistence(timeout: 10), "导出后缺少完成态文本")
        XCTAssertTrue(exported.label.hasSuffix(".gpx"), "完成态必须包含 .gpx 文件名，实际 \(exported.label)")
        let share = app.descendants(matching: .any).matching(identifier: "runDetail.share").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "落盘后缺少系统分享入口")
        XCTAssertEqual(
            app.staticTexts["runDetail.exportFailed"].exists,
            false,
            "导出成功后不应显示失败态"
        )
    }

    func testAnnouncementTogglePersistsAcrossRelaunch() {
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

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "缺少 Tab 栏")
        let settingsTab = tabBar.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "缺少 Settings Tab")
        settingsTab.tap()

        let toggle = app.switches["settings.announcementToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings 缺少每公里播报开关")

        // 先把开关归一为开启，避免上一次运行留下的状态影响断言。
        if (toggle.value as? String) == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertTrue(waitUntil(timeout: 5) { (toggle.value as? String) == "1" })
        }
        XCTAssertEqual(toggle.value as? String, "1", "默认/归一后开关应为开启")

        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(
            waitUntil(timeout: 5) { (toggle.value as? String) == "0" },
            "翻转后开关应关闭"
        )

        app.terminate()
        app.launch()

        let relaunchedTabBar = app.tabBars.firstMatch
        XCTAssertTrue(relaunchedTabBar.waitForExistence(timeout: 30), "重启后缺少 Tab 栏")
        relaunchedTabBar.buttons["Settings"].tap()

        let relaunchedToggle = app.switches["settings.announcementToggle"]
        XCTAssertTrue(relaunchedToggle.waitForExistence(timeout: 10), "重启后缺少每公里播报开关")
        XCTAssertEqual(relaunchedToggle.value as? String, "0", "重启后应保持关闭状态")
    }

    // MARK: - 授权与等待

    /// 从「分段 · N」摘要中解析分段条数。
    private func splitCount(from label: String) -> Int {
        let digits = label.reversed().prefix { $0.isNumber }.reversed()
        return Int(String(digits)) ?? 0
    }

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
