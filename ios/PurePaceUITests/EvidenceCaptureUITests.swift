import XCTest

/// 第 5 波证据收口：六屏可及树 + 真实归档跑次 + AX5 布局实测。
///
/// 只做取证，不改产品行为：
/// - 历史数据由真实「开始记录 → 跑步中 → 结束 → 保存」链路经 `run.save` 落盘产生，
///   全程不使用 `-screenshotHistoryDemo`（演示注入不落盘，不能冒充真实界面）。
/// - 定位源为 DEBUG 门控的 `-uiTestLocation`（确定性采样，可产生真实采样距离）；
///   本用例不使用 `-uiTestResetArchive`，避免清掉刚产出的真实归档。
/// - 截图由 `xcrun simctl io <udid> screenshot` 在宿主机实取，本用例只产出可及树与实测数值。
final class EvidenceCaptureUITests: XCTestCase {
    private static let locationAllowLabels = [
        "Allow While Using App", "Allow Once", "Allow", "Always Allow",
        "Change to Always Allow",
        "使用 App 期间允许", "允许一次", "始终允许", "允许改为始终允许"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 六屏可及树 + 真实归档

    /// 依次经过六屏并各落一棵可及树；中途真实保存一次跑次，供 History 列表/详情读取。
    func testEvidenceTreesAndRealArchive() {
        let app = launchApp(["-uiTestLocation"])

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "缺少 Tab 栏")

        // 1) Run 首屏（未开始）
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "缺少开始主操作")
        attachTree(app, name: "01-run-not-started")
        recordPrimaryAction(start, screen: "01-run-not-started")

        // 2) 跑步中：等待真实采样推高距离后取树
        start.tap()
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "缺少暂停主操作")
        // 让确定性采样源真实累积一段可读距离（约 30s），再取运行中与结束总结的可及树。
        XCTAssertTrue(
            waitUntil(timeout: 90) { app.staticTexts["run.elapsed"].label >= "00:30" },
            "运行中时长未随真实采样推进"
        )
        attachTree(app, name: "02-run-running")
        recordPrimaryAction(pause, screen: "02-run-running")

        // 3) 结束总结（待保存决策）
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        let save = app.buttons["run.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "结束总结缺少保存主操作")
        attachTree(app, name: "03-run-finished")
        recordPrimaryAction(save, screen: "03-run-finished")
        print(
            "evidence-finished distance=\(app.staticTexts["run.distance"].label) "
                + "elapsed=\(app.staticTexts["run.elapsed"].label)"
        )

        // 真实落盘：保存本次跑步（写入容器 Documents/Runs/）
        save.tap()
        XCTAssertTrue(app.staticTexts["run.saved"].waitForExistence(timeout: 20), "保存后缺少已保存反馈")

        // 4) History 列表（读取真实归档）
        tabBar.buttons["历史"].tap()
        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        XCTAssertTrue(waitUntil(timeout: 20) { rows.count >= 1 }, "历史列表未出现本次真实归档")
        attachTree(app, name: "04-history-list")
        recordPrimaryAction(rows.firstMatch, screen: "04-history-list")
        print("evidence-history-row label=\(rows.firstMatch.label)")

        // 5) History 详情
        rows.firstMatch.tap()
        let startedAt = app.staticTexts["runDetail.startedAt"]
        XCTAssertTrue(startedAt.waitForExistence(timeout: 20), "详情缺少开始时间")
        attachTree(app, name: "05-history-detail")
        recordPrimaryAction(app.buttons["runDetail.export"], screen: "05-history-detail")
        print(
            "evidence-history-detail startedAt=\(startedAt.label) "
                + "distance=\(app.staticTexts["runDetail.distance"].label) "
                + "elapsed=\(app.staticTexts["runDetail.activeDuration"].label)"
        )

        // 6) 设置
        tabBar.buttons["设置"].tap()
        let toggle = app.switches["settings.announcementToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "设置页缺少播报开关")
        attachTree(app, name: "06-settings")
        recordPrimaryAction(toggle, screen: "06-settings")
    }

    // MARK: - AX5（最大辅助字号档）布局实测

    /// 在系统字号已设为 `accessibility-extra-extra-extra-large` 时运行：
    /// 四张关键屏逐屏核对全部元素 frame 落在窗内、主操作 frame 与其它内容 frame 不相交。
    func testEvidenceAx5Layout() {
        // 1) Run 首屏
        var app = launchApp(["-uiTestLocation"])
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "AX5 首屏缺少开始主操作")
        attachTree(app, name: "ax5-01-run-not-started")
        assertFitsAndNoOverlap(app, screen: "01-run-not-started", primary: start)

        // 2) 结束总结：`-screenshotRunFinished` 自动结束到待保存决策态（不落盘）
        app = launchApp(["-uiTestLocation", "-autoStartRecording", "-screenshotRunFinished"])
        let save = app.buttons["run.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "AX5 结束总结缺少保存主操作")
        attachTree(app, name: "ax5-03-run-finished")
        assertFitsAndNoOverlap(app, screen: "03-run-finished", primary: save)

        // 3) History 详情：直接打开真实归档首条
        app = launchApp(["-uiTestLocation", "-screenshotInitialTab", "history", "-screenshotOpenRunDetail"])
        let export = app.buttons["runDetail.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 30), "AX5 详情缺少导出主操作")
        attachTree(app, name: "ax5-05-history-detail")
        assertFitsAndNoOverlap(app, screen: "05-history-detail", primary: export)

        // 4) 设置
        app = launchApp(["-uiTestLocation", "-screenshotInitialTab", "settings"])
        let toggle = app.switches["settings.announcementToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "AX5 设置页缺少播报开关")
        attachTree(app, name: "ax5-06-settings")
        assertFitsAndNoOverlap(app, screen: "06-settings", primary: toggle)
    }

    // MARK: - 启动与授权

    private func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
        return app
    }

    private func allowLocationIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if dismissLocationAlert(springboard: springboard, app: app) {
                return
            }
            if !springboard.alerts.firstMatch.exists && !app.alerts.firstMatch.exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func dismissLocationAlert(springboard: XCUIApplication, app: XCUIApplication) -> Bool {
        for label in Self.locationAllowLabels {
            let springboardButton = springboard.buttons[label]
            if springboardButton.exists {
                springboardButton.tap()
                return true
            }
            let alertButton = springboard.alerts.firstMatch.buttons[label]
            if alertButton.exists {
                alertButton.tap()
                return true
            }
            let appAlertButton = app.alerts.firstMatch.buttons[label]
            if appAlertButton.exists {
                appAlertButton.tap()
                return true
            }
        }
        return false
    }

    // MARK: - 证据落点

    private func attachTree(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func recordPrimaryAction(_ element: XCUIElement, screen: String) {
        print("evidence-primary screen=\(screen) identifier=\(element.identifier) label=\(element.label)")
        XCTAssertFalse(element.identifier.isEmpty, "\(screen) 主操作缺少 identifier")
        XCTAssertFalse(element.label.isEmpty, "\(screen) 主操作缺少可读 label")
    }

    // MARK: - AX5 判定

    /// 逐元素核对：所有内容元素 frame 落在窗口内；主操作 frame 与其它内容 frame 无相交。
    /// 内容元素口径为按钮 / 静态文本 / 开关 / 图片 / 链接 / 单元格，不含容器与滚动视图。
    private func assertFitsAndNoOverlap(
        _ app: XCUIApplication,
        screen: String,
        primary: XCUIElement
    ) {
        let window = app.windows.firstMatch.frame
        XCTAssertFalse(window.isEmpty, "\(screen) 缺少窗口 frame")

        let contentTypes: Set<XCUIElement.ElementType> = [
            .button, .staticText, .switch, .image, .link, .cell, .textField
        ]
        let elements = app.descendants(matching: .any).allElementsBoundByIndex.filter { element in
            contentTypes.contains(element.elementType) && !element.frame.isEmpty && element.frame.width > 0
        }

        var outOfBounds: [String] = []
        for element in elements {
            let frame = element.frame
            let inside = frame.minX >= window.minX - 1
                && frame.maxX <= window.maxX + 1
                && frame.minY >= window.minY - 1
                && frame.maxY <= window.maxY + 1
            if !inside {
                outOfBounds.append("\(element.elementType.rawValue):\(element.identifier):\(frame)")
            }
        }

        let primaryFrame = primary.frame
        var overlaps: [String] = []
        for element in elements {
            let frame = element.frame
            // 主操作自身与其子元素（frame 被主操作 frame 包含，如开关行内的标题/滑块）
            // 属于主操作的一部分，不计作「其它内容」。
            if frame == primaryFrame || primaryFrame.contains(frame) { continue }
            if frame.contains(primaryFrame) { continue }
            if frame.intersects(primaryFrame) {
                overlaps.append("\(element.elementType.rawValue):\(element.identifier):\(frame)")
            }
        }

        print(
            "AX5-FIT screen=\(screen) window=\(window) primary=\(primary.identifier) "
                + "primaryFrame=\(primaryFrame) elements=\(elements.count) "
                + "outOfBounds=\(outOfBounds.count) overlaps=\(overlaps.count)"
        )
        for entry in outOfBounds {
            print("AX5-FIT-OUT \(screen) \(entry)")
        }
        for entry in overlaps {
            print("AX5-FIT-OVERLAP \(screen) \(entry)")
        }
        XCTAssertTrue(outOfBounds.isEmpty, "\(screen) 存在超出屏幕的元素：\(outOfBounds)")
        XCTAssertTrue(overlaps.isEmpty, "\(screen) 主操作与其它内容相交：\(overlaps)")
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
}
