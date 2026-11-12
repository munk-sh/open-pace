import XCTest

/// 截图证据刷新：14 张界面证据全部由本用例在同一台模拟器内实取，宿主机只做导出。
///
/// 只产证据，不改产品行为：
/// - 六屏（Run 未开始 / 跑步中 / 结束态总结 / History 列表 / History 详情 / Settings）
///   加结束态丢弃确认层，各一张；浅/深各一个测试方法（`testEvidenceScreensLight` /
///   `testEvidenceScreensDark`），共用同一驱动，外观由宿主机 `simctl ui appearance` 决定。
/// - 截前先断言：`run.mapPreview` 存在、frame 非空且完整落在窗口内（详情不够时先滚动再判），
///   再跑 `VisibleTextPolicy` 的 zh-Hans 判定，全部通过后才调 `XCUIScreen.main.screenshot()`。
/// - 等待全部用状态判据（元素出现 / 时长推进），不用固定 `sleep` 决定断言期望。
/// - 本用例不进 CI 腿，只由 `scripts/capture-ios-screenshots.sh --stage screenshots` 显式调起。
final class ScreenshotEvidenceUITests: XCTestCase {
    private static let locationAllowLabels = [
        "Allow While Using App", "Allow Once", "Allow", "Always Allow",
        "Change to Always Allow",
        "使用 App 期间允许", "允许一次", "始终允许", "允许改为始终允许"
    ]

    /// 浅色 / 深色由测试方法区分，附件名即最终文件名（导出时不做改名）。
    private var dark = false

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEvidenceScreensLight() {
        dark = false
        captureAllScreens()
    }

    func testEvidenceScreensDark() {
        dark = true
        captureAllScreens()
    }

    // MARK: - 唯一捕获驱动

    private func captureAllScreens() {
        // 干净容器起步：本次链路写入的跑次就是 History 唯一一条。
        var app = launchApp([
            "-uiTestLocation", "-uiTestLocationTargetMeters", "1200", "-uiTestResetArchive"
        ])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "缺少 Tab 栏")

        // 1) Run 未开始
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "缺少开始主操作")
        assertVisibleCopyZhHans(app, screen: "run-not-started")
        recordPrimaryAction(start, screen: "run-not-started")
        capture(base: "run-not-started")

        // 2) 跑步中：等真实采样把时长与距离推起来（状态判据，不用固定 sleep）
        start.tap()
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "缺少暂停主操作")
        XCTAssertTrue(
            waitUntil(timeout: 60) { app.staticTexts["run.elapsed"].label >= "00:20" },
            "运行中时长未随采样推进"
        )
        XCTAssertTrue(
            waitUntil(timeout: 30) { app.staticTexts["run.distance"].label != "0.00 km" },
            "运行中距离未随采样推进"
        )
        assertVisibleCopyZhHans(app, screen: "run-running")
        recordPrimaryAction(pause, screen: "run-running")
        capture(base: "run-running")

        // 3) 结束态总结：先断言地图卡完整在窗内，再取图
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        let save = app.buttons["run.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 20), "结束总结缺少保存主操作")
        assertMapPreviewInWindow(app, screen: "run-finished")
        assertVisibleCopyZhHans(app, screen: "run-finished")
        recordPrimaryAction(save, screen: "run-finished")
        capture(base: "run-finished")

        // 4) 结束态丢弃确认层：仓内唯一的 `.sheet(...)` 确认层
        let discardRequest = app.buttons["run.discardRequest"]
        XCTAssertTrue(discardRequest.waitForExistence(timeout: 10), "结束态缺少丢弃入口")
        discardRequest.tap()
        let discard = app.buttons["run.discard"]
        let discardCancel = app.buttons["run.discardCancel"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10), "确认层缺少丢弃按钮")
        XCTAssertTrue(discardCancel.waitForExistence(timeout: 10), "确认层缺少取消按钮")
        XCTAssertFalse(discard.label.isEmpty, "确认层丢弃按钮缺少可读 label")
        XCTAssertFalse(discardCancel.label.isEmpty, "确认层取消按钮缺少可读 label")
        print(
            "evidence-discard sheet=discardRequest buttons=2 "
                + "discard=\(discard.label) cancel=\(discardCancel.label)"
        )
        capture(base: "discard-confirmation")
        discardCancel.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { !discard.exists }, "取消后确认层未收起")

        // 真实落盘：这次跑次写进容器 Documents/Runs/，供下面两屏读取
        save.tap()
        XCTAssertTrue(app.staticTexts["run.saved"].waitForExistence(timeout: 20), "保存后缺少已保存反馈")

        // 5) History 列表（读取刚保存的真实归档）
        app.terminate()
        app = launchApp(["-uiTestLocation", "-screenshotInitialTab", "history"])
        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        XCTAssertTrue(waitUntil(timeout: 30) { rows.count >= 1 }, "历史列表未出现本次真实归档")
        assertVisibleCopyZhHans(app, screen: "history-list")
        recordPrimaryAction(rows.firstMatch, screen: "history-list")
        capture(base: "history-list")

        // 6) History 详情：地图卡在惰性列表下方，先滚动到完整可见再判
        rows.firstMatch.tap()
        let startedAt = app.staticTexts["runDetail.startedAt"]
        XCTAssertTrue(startedAt.waitForExistence(timeout: 20), "详情缺少开始时间")
        assertMapPreviewInWindow(app, screen: "history-detail")
        assertVisibleCopyZhHans(app, screen: "history-detail")
        recordPrimaryAction(app.buttons["runDetail.export"], screen: "history-detail")
        capture(base: "history-detail")

        // 7) 设置
        app.terminate()
        app = launchApp(["-uiTestLocation", "-screenshotInitialTab", "settings"])
        let toggle = app.switches["settings.announcementToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "设置页缺少播报开关")
        assertVisibleCopyZhHans(app, screen: "settings")
        recordPrimaryAction(toggle, screen: "settings")
        capture(base: "settings")

        app.terminate()
    }

    // MARK: - 截图与断言

    /// 附件名 = 最终文件名（浅色 `<base>.png` / 深色 `<base>-dark.png`）。
    private func capture(base: String) {
        let name = dark ? "\(base)-dark" : base
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("evidence-shot screen=\(name)")
    }

    private func recordPrimaryAction(_ element: XCUIElement, screen: String) {
        print("evidence-primary screen=\(screen) identifier=\(element.identifier) label=\(element.label)")
        XCTAssertFalse(element.identifier.isEmpty, "\(screen) 主操作缺少 identifier")
        XCTAssertFalse(element.label.isEmpty, "\(screen) 主操作缺少可读 label")
    }

    /// 地图卡证据：存在、frame 非空、完整落在「窗口扣除底部主操作区」的可见区内；
    /// 不足时先滚动（≤4 次）再判，避免截图里地图被固定底部主操作遮住。
    private func assertMapPreviewInWindow(_ app: XCUIApplication, screen: String) {
        let map = app.descendants(matching: .any).matching(identifier: "run.mapPreview").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 20), "\(screen) 缺少 run.mapPreview")
        let window = app.windows.firstMatch.frame
        XCTAssertFalse(window.isEmpty, "\(screen) 窗口 frame 为空")
        let visible = visibleContentRect(app, window: window)
        var attempts = 0
        while attempts < 4 && !isFullyVisible(map.frame, in: visible) {
            scrollUp(app, mapFrame: map.frame)
            attempts += 1
        }
        let frame = map.frame
        XCTAssertFalse(frame.isEmpty, "\(screen) run.mapPreview frame 为空")
        XCTAssertTrue(
            isFullyVisible(frame, in: visible),
            "\(screen) run.mapPreview 未完整落在可见区内 frame=\(frame) visible=\(visible)"
        )
        print("evidence-map screen=\(screen) identifier=run.mapPreview frame=\(frame) visible=\(visible)")
    }

    /// 可见内容区 = 窗口扣除固定底部主操作区（`run.save` / `runDetail.export` 这类
    /// `safeAreaInset` 按钮会盖在滚动内容之上，只判窗口会把被遮住的地图误判为可见）。
    private func visibleContentRect(_ app: XCUIApplication, window: CGRect) -> CGRect {
        let primary = app.buttons["runDetail.export"].exists
            ? app.buttons["runDetail.export"]
            : app.buttons["run.save"]
        guard primary.exists && primary.frame.minY > window.midY else { return window }
        return CGRect(
            x: window.minX,
            y: window.minY,
            width: window.width,
            height: primary.frame.minY - window.minY
        )
    }

    private func isFullyVisible(_ frame: CGRect, in window: CGRect) -> Bool {
        !frame.isEmpty && window.insetBy(dx: -0.5, dy: -0.5).contains(frame)
    }

    /// 在地图卡上方内容区做一次拖拽滚动（避免手势落在 MapKit 地图上被地图自身吞掉）。
    private func scrollUp(_ app: XCUIApplication, mapFrame: CGRect) {
        let window = app.windows.firstMatch.frame
        let startY = max(window.minY + 120, min(mapFrame.minY - 60, window.midY))
        let endY = max(window.minY + 80, startY - 200)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: window.midX, dy: startY))
        let end = origin.withOffset(CGVector(dx: window.midX, dy: endY))
        print("evidence-scroll from=\(startY) to=\(endY) mapMinY=\(mapFrame.minY)")
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// 与 `RunFlowUITests` 同一口径（不改那个用例）：把当前可及树的非空 label 喂给同一
    /// `VisibleTextPolicy`；SF Symbol 标识与 DEBUG `run.telemetry` 摘要不是用户可见文案；
    /// 地图卡内部 MapKit 注记按「地图卡区域内且非地图卡本身」过滤。
    private func assertVisibleCopyZhHans(_ app: XCUIApplication, screen: String) {
        let mapCard = app.descendants(matching: .any).matching(identifier: "run.mapPreview").firstMatch
        let mapFrame = mapCard.exists ? mapCard.frame : .zero
        let elements = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .filter { element in
                guard element.identifier != "run.telemetry" else { return false }
                guard element.identifier != "run.mapPreview", !mapFrame.isEmpty else { return true }
                let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                return !mapFrame.insetBy(dx: -1, dy: -1).contains(center)
            }
        let texts = elements
            .map { $0.label }
            .filter { !$0.isEmpty && !isSystemSymbolLabel($0) }
        let violations = VisibleTextPolicy.violations(in: texts)
        let offenders = elements
            .filter { violations.contains($0.label) }
            .map { "\($0.elementType.rawValue)|\($0.identifier)|\($0.frame)|\($0.label)" }
        print(
            "ac-visible-copy-zh-hans screen=\(screen) labels=\(texts.count) "
                + "violations=\(violations.count) offenders=\(offenders)"
        )
        XCTAssertTrue(
            violations.isEmpty,
            "\(screen) 存在裸英文文案：\(violations) offenders=\(offenders)"
        )
    }

    private func isSystemSymbolLabel(_ text: String) -> Bool {
        text.range(of: #"^[a-z0-9]+(\.[a-z0-9]+)+$"#, options: .regularExpression) != nil
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
