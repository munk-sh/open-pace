import XCTest

/// 真实链路 UI 测试：跑步会话由启动参数 `-uiTestLocation` 注入的确定性测试定位源驱动
/// （仅 DEBUG 生效），不依赖 simulator 的隐藏式定位投递；真实 CoreLocation 覆盖由
/// `scripts/verify-ios-sim-runtime.sh` 的门禁承担。不内置样例、不以固定 sleep 作为成功判据。
final class RunFlowUITests: XCTestCase {
    /// 授权弹窗按钮文案（系统英文/中文）。
    private static let locationAllowLabels = [
        "Allow While Using App", "Allow Once", "Allow", "Always Allow",
        "使用 App 期间允许", "允许一次", "始终允许"
    ]
    /// 首个真实定位样本的快速探针上限（秒）：注入若未投递样本，≤10s 即失败并落诊断，
    /// 不再用 60s 静默等待掩盖链路问题。真实样本通常在注入后 1-2s 内到达。
    private let firstSampleProbeTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRunPauseResumeFinishAndHistory() {
        let app = XCUIApplication()
        // 确定性测试定位源（仅 DEBUG 生效）：不依赖 hosted runner 的 simulator 定位投递。
        app.launchArguments += ["-uiTestLocation"]
        addUIInterruptionMonitor(withDescription: "Location Authorization") { alert in
            for label in Self.locationAllowLabels {
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
        XCTAssertEqual(startedDistance, "0.00 km", "开跑起点距离必须为零")
        // 首样本探针：注入后 ≤10s 无真实样本即快速失败并落诊断，不再静默等 60s。
        // 期间持续处理定位授权弹窗：脚本预置的 TCC 可能被 xcodebuild 重新安装 App 清掉，
        // 弹窗出现在点击「开始」之后，必须在这里兜住，否则用例会一直看到 0.00 km。
        let firstSampleArrived = waitForFirstLocationSample(
            distance: distance,
            baseline: startedDistance,
            timeout: firstSampleProbeTimeout
        )
        if !firstSampleArrived {
            attachLocationDiagnostics(
                app,
                distance: distance,
                elapsed: elapsed,
                baseline: startedDistance
            )
        }
        XCTAssertTrue(
            firstSampleArrived,
            "开始后 \(Int(firstSampleProbeTimeout))s 内距离没有随真实定位样本从 \(startedDistance) 变化"
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
        attachScreenshot(app, name: "e2e-finish")

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
        attachScreenshot(app, name: "e2e-history")

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
        attachScreenshot(app, name: "e2e-detail")

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

        // 真实点击分享入口后，系统活动视图必须出现；有界等待，不用固定 sleep。
        share.tap()
        let shareSheetAppeared = waitUntil(timeout: 20) {
            app.otherElements["ActivityListView"].exists
                || app.sheets.firstMatch.exists
                || app.buttons["Copy"].exists
                || app.buttons["拷贝"].exists
                || app.buttons["Save to Files"].exists
                || app.buttons["存储到“文件”"].exists
        }
        XCTAssertTrue(shareSheetAppeared, "点击分享后系统分享面板/活动视图未出现")
        attachScreenshot(app, name: "e2e-share")

        // 关闭分享面板并恢复详情页，避免影响后续流程。
        var dismissed = false
        for label in ["Close", "关闭", "取消", "Cancel", "Done", "完成"] {
            let button = app.buttons[label]
            if button.exists {
                button.tap()
                dismissed = true
                break
            }
        }
        if !dismissed {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        XCTAssertTrue(
            waitUntil(timeout: 10) { detailRoot.exists },
            "关闭分享面板后应回到跑次详情"
        )
    }

    func testAnnouncementTogglePersistsAcrossRelaunch() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Location Authorization") { alert in
            for label in Self.locationAllowLabels {
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
        // 冷启动时 SpringBoard 授权弹窗可能吞掉首次点击；有界重试一次，断言强度不变。
        if !waitUntil(timeout: 5, { (toggle.value as? String) == "0" }) {
            allowLocationIfNeeded()
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertTrue(
            waitUntil(timeout: 10) { (toggle.value as? String) == "0" },
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

    /// 以固定名称保存关键节点截图（lifetime = .keepAlways），供端到端脚本导出取证。
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 首样本探针失败时把可观测状态写入 xcresult；App 侧授权与样本计数由
    /// `scripts/test-ios.sh` 回读容器内 `location-diagnostics.log` 输出到脚本日志。
    private func attachLocationDiagnostics(
        _ app: XCUIApplication,
        distance: XCUIElement,
        elapsed: XCUIElement,
        baseline: String
    ) {
        let summary = """
        location-probe-failed at \(Date())
        baseline=\(baseline) currentDistance=\(distance.label) currentElapsed=\(elapsed.label)
        springboardAlert=\(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        """
        let text = XCTAttachment(string: summary)
        text.name = "location-diagnostics"
        text.lifetime = .keepAlways
        add(text)
        attachScreenshot(app, name: "location-probe-failed")
    }

    /// 从「分段 · N」摘要中解析分段条数。
    private func splitCount(from label: String) -> Int {
        let digits = label.reversed().prefix { $0.isNumber }.reversed()
        return Int(String(digits)) ?? 0
    }

    /// 有界等待首个真实定位样本：等待期间持续处理可能弹出的定位授权弹窗（含 App 自身 alert 与
    /// SpringBoard 弹窗），一旦 `distance` 离开基线立即返回；不使用固定 sleep 作为成功判据。
    private func waitForFirstLocationSample(
        distance: XCUIElement,
        baseline: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if distance.label != baseline {
                return true
            }
            dismissLocationAlertsIfPresent()
            let remaining = max(0.5, min(5, deadline.timeIntervalSinceNow))
            _ = waitUntil(timeout: remaining) { distance.label != baseline }
        }
        return distance.label != baseline
    }

    /// 非阻塞扫描一次定位授权弹窗并放行，供首个样本等待循环复用（不消耗整段等待预算）。
    private func dismissLocationAlertsIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication()
        for label in Self.locationAllowLabels {
            let springboardButton = springboard.buttons[label]
            if springboardButton.exists {
                springboardButton.tap()
                return
            }
            let springboardAlertButton = springboard.alerts.firstMatch.buttons[label]
            if springboardAlertButton.exists {
                springboardAlertButton.tap()
                return
            }
            let appAlertButton = app.alerts.firstMatch.buttons[label]
            if appAlertButton.exists {
                appAlertButton.tap()
                return
            }
        }
    }

    /// 授权兜底：TCC 已由脚本预置时无弹窗；干净设备上仍要在有界窗口内处理 SpringBoard 弹窗。
    private func allowLocationIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            for label in Self.locationAllowLabels {
                let button = springboard.buttons[label]
                if button.exists {
                    button.tap()
                    return
                }
            }
            if springboard.alerts.firstMatch.exists {
                for label in Self.locationAllowLabels {
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
