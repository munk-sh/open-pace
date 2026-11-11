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
        // 1) Run 首屏 / 2) 跑步中 / 3) 结束总结 + 真实落盘：由共享 seed helper 完成，
        //    取证点（attachTree / recordPrimaryAction / evidence-finished）仍按原顺序回调。
        let app = seedRealArchive(
            onNotStarted: { app, start in
                self.attachTree(app, name: "01-run-not-started")
                self.recordPrimaryAction(start, screen: "01-run-not-started")
            },
            onRunning: { app, pause in
                self.attachTree(app, name: "02-run-running")
                self.recordPrimaryAction(pause, screen: "02-run-running")
            },
            onFinished: { app, save in
                self.attachTree(app, name: "03-run-finished")
                self.recordPrimaryAction(save, screen: "03-run-finished")
                print(
                    "evidence-finished distance=\(app.staticTexts["run.distance"].label) "
                        + "elapsed=\(app.staticTexts["run.elapsed"].label)"
                )
            }
        )
        let tabBar = app.tabBars.firstMatch

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

    // MARK: - 真实归档 seed（唯一实现）

    /// 真实「开始记录 → 跑步中 → 结束 → 保存」链路：经 `run.save` 写入容器 `Documents/Runs/`。
    /// `testEvidenceTreesAndRealArchive` 与 `testEvidenceAx5Layout` 共用这一份实现；
    /// `on*` 闭包在各自原来的取证点回调，保证产出内容与顺序不变。
    @discardableResult
    private func seedRealArchive(
        onNotStarted: ((XCUIApplication, XCUIElement) -> Void)? = nil,
        onRunning: ((XCUIApplication, XCUIElement) -> Void)? = nil,
        onFinished: ((XCUIApplication, XCUIElement) -> Void)? = nil
    ) -> XCUIApplication {
        let app = launchApp(["-uiTestLocation"])

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "缺少 Tab 栏")

        // 1) Run 首屏（未开始）
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "缺少开始主操作")
        onNotStarted?(app, start)

        // 2) 跑步中：等待真实采样推高距离后回调
        start.tap()
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "缺少暂停主操作")
        // 让确定性采样源真实累积一段可读距离（约 30s）。
        XCTAssertTrue(
            waitUntil(timeout: 90) { app.staticTexts["run.elapsed"].label >= "00:30" },
            "运行中时长未随真实采样推进"
        )
        onRunning?(app, pause)

        // 3) 结束总结（待保存决策）
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        let save = app.buttons["run.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "结束总结缺少保存主操作")
        onFinished?(app, save)

        // 真实落盘：保存本次跑步（写入容器 Documents/Runs/）
        save.tap()
        XCTAssertTrue(app.staticTexts["run.saved"].waitForExistence(timeout: 20), "保存后缺少已保存反馈")
        return app
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
        app.terminate()
        app = launchApp(["-uiTestLocation", "-autoStartRecording", "-screenshotRunFinished"])
        let save = app.buttons["run.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "AX5 结束总结缺少保存主操作")
        attachTree(app, name: "ax5-03-run-finished")
        assertFitsAndNoOverlap(app, screen: "03-run-finished", primary: save)

        // 3) History 详情前置：先只读检测归档是否为空（本 launch 不写入归档），
        //    干净容器下单跑也自给自足——仅在空态时 seed 一条真实跑次。
        app.terminate()
        app = launchApp(["-uiTestLocation", "-screenshotInitialTab", "history"])
        let archiveRows = app.descendants(matching: .any).matching(identifier: "history.row")
        let archiveEmpty = app.staticTexts["history.empty"]
        XCTAssertTrue(
            waitUntil(timeout: 30) { archiveRows.count >= 1 || archiveEmpty.exists },
            "AX5 历史页既无归档行也无空态"
        )
        let needsSeed = archiveRows.count == 0
        app.terminate()
        if needsSeed {
            print("AX5-SEED action=seed reason=archive-empty")
            let seedApp = seedRealArchive()
            seedApp.terminate()
        } else {
            print("AX5-SEED action=skip reason=archive-present rows=\(archiveRows.count)")
        }

        // 3.1) History 详情：打开真实归档首条
        app = launchApp(["-uiTestLocation", "-screenshotInitialTab", "history", "-screenshotOpenRunDetail"])
        let export = app.buttons["runDetail.export"]
        // AX5 下详情是系统 List：导出位于地图/分段之后，惰性行需滚动才会 realize（不改断言、不放宽超时）。
        var detailScrolls = 0
        while !export.exists, detailScrolls < 4 {
            app.swipeUp()
            detailScrolls += 1
        }
        XCTAssertTrue(export.waitForExistence(timeout: 30), "AX5 详情缺少导出主操作")
        attachTree(app, name: "ax5-05-history-detail")
        assertScrollableScreenFits(app, screen: "05-history-detail", primary: export)

        // 4) 设置
        app.terminate()
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

    // MARK: - 可滚动屏口径（AX5：List / ScrollView）

    /// 可滚动屏判定：交互元素（button/link/switch/textField）必须「滚动可达 + frame 完整落在视口内 +
    /// 不被另一交互元素覆盖」；静态文本 / cell 只判水平不溢出，垂直滚出视口仅计数取证。
    /// 视口取 window 去掉底部 Tab 栏，避免「滚到底后被 Tab 栏覆盖」的伪红。
    private func assertScrollableScreenFits(
        _ app: XCUIApplication,
        screen: String,
        primary: XCUIElement,
        maxScrolls: Int = 5
    ) {
        let window = app.windows.firstMatch.frame
        let tabBar = app.tabBars.firstMatch
        let hasTabBar = tabBar.exists && !tabBar.frame.isEmpty
        let tabBarFrame = hasTabBar ? tabBar.frame : nil
        let viewport = hasTabBar
            ? CGRect(
                x: window.minX,
                y: window.minY,
                width: window.width,
                height: tabBar.frame.minY - window.minY
            )
            : window

        var realizedInteractives: Set<String> = []
        var reachableInteractives: Set<String> = []
        var scrolls = 0
        while true {
            for element in contentElements(app, excluding: tabBarFrame) where isAppInteractive(element) {
                let key = elementKey(element)
                realizedInteractives.insert(key)
                if element.isHittable {
                    reachableInteractives.insert(key)
                }
            }
            let primaryReady = primary.exists
                && primary.isHittable
                && viewport.insetBy(dx: -1, dy: -1).contains(primary.frame)
            if primaryReady || scrolls >= maxScrolls {
                break
            }
            app.swipeUp()
            scrolls += 1
        }

        var seen: Set<String> = []
        let snapshots = contentElements(app, excluding: tabBarFrame).compactMap { element -> Ax5ScrollAudit.Snapshot? in
            let snapshot = Ax5ScrollAudit.Snapshot(
                key: elementKey(element),
                isInteractive: isAppInteractive(element),
                frame: element.frame,
                isHittable: element.isHittable
            )
            let signature = "\(snapshot.key)|\(snapshot.frame)"
            return seen.insert(signature).inserted ? snapshot : nil
        }
        let result = Ax5ScrollAudit.audit(snapshots: snapshots, viewport: viewport, window: window)
        let unreachable = realizedInteractives.subtracting(reachableInteractives)

        // 保持既有四屏 `AX5-FIT screen=` 取证契约（05 仍是其中一条），滚动口径的证据另起 `AX5-SCROLL` 行。
        let overlapViolations = result.interactiveViolations.filter { $0.contains("相交") }
        let boundsViolations = result.interactiveViolations.filter { !$0.contains("相交") }
            + result.horizontalViolations
        print(
            "AX5-FIT screen=\(screen) window=\(window) primary=\(primary.identifier) "
                + "primaryFrame=\(primary.frame) elements=\(snapshots.count) "
                + "outOfBounds=\(boundsViolations.count) overlaps=\(overlapViolations.count)"
        )
        for entry in boundsViolations { print("AX5-FIT-OUT \(screen) \(entry)") }
        for entry in overlapViolations { print("AX5-FIT-OVERLAP \(screen) \(entry)") }

        print(
            "AX5-SCROLL screen=\(screen) scrolls=\(scrolls) "
                + "interactive=\(realizedInteractives.count) unreachable=\(unreachable.count) "
                + "scrollRequiredStatic=\(result.scrollRequiredStaticCount) "
                + "interactiveViolations=\(result.interactiveViolations.count) "
                + "horizontalViolations=\(result.horizontalViolations.count) viewport=\(viewport)"
        )
        for entry in result.interactiveViolations { print("AX5-SCROLL-INTERACTIVE \(screen) \(entry)") }
        for entry in result.horizontalViolations { print("AX5-SCROLL-HORIZONTAL \(screen) \(entry)") }
        for key in unreachable.sorted() { print("AX5-SCROLL-UNREACHABLE \(screen) \(key)") }

        XCTAssertTrue(unreachable.isEmpty, "\(screen) 交互元素滚动全程均不可点：\(unreachable)")
        XCTAssertTrue(
            result.interactiveViolations.isEmpty,
            "\(screen) 交互元素未完整在视口内或互相覆盖：\(result.interactiveViolations)"
        )
        XCTAssertTrue(
            result.horizontalViolations.isEmpty,
            "\(screen) 存在水平溢出的元素：\(result.horizontalViolations)"
        )
    }

    private func contentElements(_ app: XCUIApplication, excluding tabBarFrame: CGRect?) -> [XCUIElement] {
        let contentTypes: Set<XCUIElement.ElementType> = [
            .button, .staticText, .switch, .image, .link, .cell, .textField
        ]
        return app.descendants(matching: .any).allElementsBoundByIndex.filter { element in
            guard contentTypes.contains(element.elementType),
                  !element.frame.isEmpty,
                  element.frame.width > 0 else { return false }
            if let tabBarFrame, element.frame.minY >= tabBarFrame.minY - 1 { return false }
            return true
        }
    }

    /// 只审计 App 自己声明的可交互元素（有 accessibility identifier）：
    /// Apple 地图内部的「法律信息」等系统附属链接不属于 App 可及契约，不参与可达性判定。
    private func isAppInteractive(_ element: XCUIElement) -> Bool {
        switch element.elementType {
        case .button, .link, .switch, .textField:
            return !element.identifier.isEmpty
        default:
            return false
        }
    }

    private func elementKey(_ element: XCUIElement) -> String {
        let identifier = element.identifier.isEmpty ? element.label : element.identifier
        return "\(element.elementType.rawValue):\(identifier)"
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
