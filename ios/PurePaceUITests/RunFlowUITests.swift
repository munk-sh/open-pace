import XCTest
import UIKit
import PurePaceRunCore

/// 真实链路 UI 测试：跑步会话由启动参数 `-uiTestLocation` 注入的确定性测试定位源驱动
/// （仅 DEBUG 生效），不依赖 simulator 的隐藏式定位投递；真实 CoreLocation 覆盖由
/// `scripts/verify-ios-sim-runtime.sh` 的门禁承担。不内置样例、不以固定 sleep 作为成功判据。
final class RunFlowUITests: XCTestCase {
    /// 授权弹窗按钮文案（系统英文/中文）。
    private static let locationAllowLabels = [
        "Allow While Using App", "Allow Once", "Allow", "Always Allow",
        "Change to Always Allow",
        "使用 App 期间允许", "允许一次", "始终允许", "允许改为始终允许"
    ]
    /// 首个真实定位样本的快速探针上限（秒）：注入若未投递样本，≤10s 即失败并落诊断，
    /// 不再用 60s 静默等待掩盖链路问题。真实样本通常在注入后 1-2s 内到达。
    private let firstSampleProbeTimeout: TimeInterval = 10
    /// iPhone 16 竖屏底部 Home Indicator 安全区：TabBar 自身 83pt = 49pt 栏 + 34pt 安全区，
    /// 记录态 Tab 栏收起后用它换算「距窗口底边（扣除安全区）」的等价锚点。
    private static let homeIndicatorInset: CGFloat = 34

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRunPauseResumeFinishAndHistory() {
        let app = XCUIApplication()
        // 确定性测试定位源（仅 DEBUG 生效）：不依赖 hosted runner 的 simulator 定位投递。
        app.launchArguments += ["-uiTestLocation", "-uiTestResetArchive"]
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
        XCTAssertTrue(tabBar.buttons["设置"].exists, "缺少 Settings Tab")
        XCTAssertFalse(tabBar.buttons["Log"].exists, "Log Tab 应已移除")

        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "缺少开始按钮")

        // 空态诚实：未开跑时 History 只有空态，不渲染任何示例跑次。
        let historyTab = app.tabBars.buttons["历史"]
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
        XCTAssertTrue(app.tabBars.buttons["跑步"].waitForExistence(timeout: 10), "缺少 Run Tab")
        app.tabBars.buttons["跑步"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "返回跑步页后缺少开始按钮")

        // 起点读数在 tap 之前取：此时跑步未开始，读数不受 1Hz 定位注入竞态影响。
        // tap 之后再读距离会被首个样本抢跑（曾出现 "0.01 km" vs "0.00 km" 伪红）。
        let startedDistance = distance.label
        let startedElapsed = elapsed.label
        XCTAssertEqual(startedDistance, "0.00 km", "开跑起点距离必须为零")

        start.tap()

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
        assertRenderedAccent(pause, evidence: "运行中暂停按钮")
        pause.tap()

        XCTAssertTrue(
            waitUntil(timeout: 10) { app.buttons["run.resume"].exists },
            "暂停后未进入可恢复状态"
        )
        XCTAssertEqual(app.staticTexts["run.currentPace"].label, "--", "暂停时当前配速必须为空")
        assertTabBarVisibility(
            app, state: .paused, didSave: false, screen: "暂停",
            evidence: "ac-tabbar-hidden-paused"
        )
        assertRunMetricsBalanced(app, primaryAction: app.buttons["run.resume"], state: "暂停")
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
        assertTabBarVisibility(
            app, state: .running, didSave: false, screen: "恢复运行",
            evidence: "ac-tabbar-hidden-recording"
        )

        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        assertRenderedAccent(finish, evidence: "结束按钮")
        finish.tap()
        assertTabBarVisibility(
            app, state: .finished, didSave: false, screen: "结束待保存",
            evidence: "ac-tabbar-hidden-finished-pending"
        )

        // 破坏性丢弃只经确认层：屏上先有入口、无 run.discard；sheet 内才出现，取消后状态不变。
        XCTAssertTrue(app.buttons["run.discardRequest"].exists, "结束待保存态缺少丢弃确认入口")
        XCTAssertFalse(app.buttons["run.discard"].exists, "确认层出现前不得直接暴露破坏性丢弃按钮")
        // 打开确认层前冻结读数：取消只关闭确认层，距离/时长必须逐字节不变。
        let pendingDistance = distance.label
        let pendingElapsed = elapsed.label
        app.buttons["run.discardRequest"].tap()
        XCTAssertTrue(
            app.buttons["run.discard"].waitForExistence(timeout: 10),
            "确认层未出现破坏性丢弃按钮"
        )
        app.buttons["run.discardCancel"].tap()
        XCTAssertTrue(
            waitUntil(timeout: 5) { !app.buttons["run.discard"].exists },
            "取消确认层后破坏性丢弃按钮应消失"
        )
        XCTAssertTrue(app.buttons["run.discardRequest"].exists, "取消后应回到结束待保存态")
        XCTAssertTrue(app.buttons["run.save"].exists, "取消后保存主操作应仍在")
        // 取消是纯关闭动作：屏幕与读数都必须零变更（未丢弃、未重置会话）。
        XCTAssertFalse(
            app.buttons["run.discard"].exists,
            "取消后破坏性丢弃按钮不得留在屏上：取消不得触发丢弃"
        )
        XCTAssertEqual(
            distance.label,
            pendingDistance,
            "取消确认层不得改变距离读数：期望仍为 \(pendingDistance)，实际 \(distance.label)"
        )
        XCTAssertEqual(
            elapsed.label,
            pendingElapsed,
            "取消确认层不得改变时长读数：期望仍为 \(pendingElapsed)，实际 \(elapsed.label)"
        )

        // 正向确认路径：确认后才真正丢弃，并回到 `ready` 未开始态。
        let discardEntry = app.buttons["run.discardRequest"]
        XCTAssertTrue(discardEntry.exists, "结束待保存态缺少丢弃确认入口，无法走确认路径")
        discardEntry.tap()
        let discardConfirm = app.buttons["run.discard"]
        XCTAssertTrue(
            discardConfirm.waitForExistence(timeout: 10),
            "再次打开确认层后缺少破坏性丢弃按钮"
        )
        discardConfirm.tap()
        let restartedStart = app.buttons["run.start"]
        XCTAssertTrue(
            restartedStart.waitForExistence(timeout: 10),
            "确认丢弃后应回到 ready 未开始态并出现开始按钮"
        )
        XCTAssertFalse(app.buttons["run.discard"].exists, "确认丢弃后破坏性按钮必须随确认层消失")
        XCTAssertFalse(app.buttons["run.discardRequest"].exists, "ready 态不得再有丢弃确认入口")
        XCTAssertFalse(app.buttons["run.save"].exists, "丢弃后不得再出现保存主操作")

        // 确认丢弃已把会话复位到 ready，保存链路需在新一轮会话上继续验证
        // （既有保存/历史/详情断言一条不删不改，只换承载会话）。
        restartedStart.tap()
        XCTAssertTrue(
            app.buttons["run.pause"].waitForExistence(timeout: 15),
            "丢弃后重新开跑未进入运行态（倒计时结束应出现暂停按钮）"
        )
        // 倒计时结束后的即时读数作基线：用复位后的 0.00 km 判「已增长」会把空记录当成功。
        let restartedBaselineDistance = distance.label
        XCTAssertTrue(
            waitUntil(timeout: 30) { distance.label != restartedBaselineDistance },
            "重新开跑后距离没有随定位样本增长，当前 \(distance.label)"
        )
        XCTAssertTrue(
            waitUntil(timeout: 10) { elapsed.label != "00:00" },
            "重新开跑后时长没有随真实采样增长，当前 \(elapsed.label)"
        )
        let restartedFinish = app.buttons["run.finish"]
        XCTAssertTrue(restartedFinish.waitForExistence(timeout: 10), "重新开跑后缺少结束按钮")
        restartedFinish.tap()
        XCTAssertTrue(
            app.buttons["run.save"].waitForExistence(timeout: 10),
            "重新结束后未回到结束待保存态"
        )

        let save = app.buttons["run.save"]
        XCTAssertTrue(save.exists, "结束待保存态缺少保存主操作")
        assertRenderedAccent(save, evidence: "保存主操作")
        saveFinishedRun(app)

        XCTAssertTrue(
            app.staticTexts["run.saved"].waitForExistence(timeout: 10),
            "结束后缺少「已保存」反馈"
        )
        assertTabBarVisibility(
            app, state: .finished, didSave: true, screen: "保存态",
            evidence: "ac-tabbar-restore-no-deadend"
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

    /// ac-audio-ui-e2e / ac-tel-always：跨 1 km 边界后由 DEBUG 门控的 `run.telemetry`
    /// 无障碍摘要断言授权/音频遥测。定位源为确定性快速源，仅用于触发公里边界。
    func testRunProducesTelemetryAcrossKilometerBoundary() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestLocation", "-uiTestLocationFast", "-uiTestResetArchive"]
        app.launch()

        let distance = app.staticTexts["run.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 30), "跑步页缺少距离读数")
        XCTAssertEqual(distance.label, "0.00 km", "未开始时距离必须为零")

        // 播报开关可能被前序用例关闭；本用例经真实 UI 归一为开启，保证公里播报会发生。
        enableAnnouncements(app)
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "缺少开始按钮")
        start.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) { self.distanceKilometers(distance.label) >= 1.0 },
            "快速确定源未在预算内跨过 1 km 边界，当前 \(distance.label)"
        )
        attachScreenshot(app, name: "telemetry-kilometer")
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        saveFinishedRun(app)
        XCTAssertTrue(
            app.staticTexts["run.saved"].waitForExistence(timeout: 10),
            "结束后缺少「已保存」反馈"
        )

        let telemetry = app.staticTexts["run.telemetry"]
        XCTAssertTrue(
            telemetry.waitForExistence(timeout: 10),
            "结束后缺少 DEBUG 门控的 run.telemetry 遥测摘要"
        )
        let summary = telemetry.label
        XCTAssertTrue(summary.contains("authorizationStatus"), "遥测缺少 authorizationStatus：\(summary)")
        XCTAssertTrue(summary.contains("authorizedAlways"), "系统授权应为 authorizedAlways：\(summary)")
        XCTAssertTrue(summary.contains("rawValue=3"), "授权 rawValue 应为 3：\(summary)")
        XCTAssertTrue(summary.contains("duckOthers=true"), "播报遥测缺少 duckOthers：\(summary)")
        XCTAssertTrue(summary.contains("第 1 公里"), "播报遥测缺少「第 1 公里」文本：\(summary)")
        XCTAssertTrue(summary.contains("otherAudioPlaying="), "遥测缺少 isOtherAudioPlaying：\(summary)")
        XCTAssertTrue(
            summary.contains("secondaryAudioSilenced="),
            "遥测缺少 secondaryAudioShouldBeSilencedHint：\(summary)"
        )
        attachScreenshot(app, name: "telemetry-finish")
    }

    /// 全链路导出自证：开始 → 结束 → 选中本次记录 → 详情 → 导出 GPX → 系统分享面板 → 回到详情。
    /// 与 `testRunPauseResumeFinishAndHistory` 相互独立：以「开始前记录行数 N → 结束后 N+1」取本次记录，
    /// 最新一行（按 startedAt 降序的首行）即本次记录，不依赖容器全局恰 1 条。
    func testStartFinishExportGPXArtifact() {
        let app = XCUIApplication()
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

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "缺少 Tab 栏")
        let historyTab = tabBar.buttons["历史"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "缺少 History Tab")

        // 记录开始前已有行数 N；本次结束后应变为 N+1，且降序首行即本次新记录。
        historyTab.tap()
        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        XCTAssertTrue(
            waitUntil(timeout: 10) { rows.count > 0 || app.staticTexts["history.empty"].exists },
            "History 列表未加载完成"
        )
        let baselineCount = rows.count
        XCTAssertTrue(app.tabBars.buttons["跑步"].waitForExistence(timeout: 10), "缺少 Run Tab")
        app.tabBars.buttons["跑步"].tap()
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "缺少开始按钮")
        start.tap()
        let startedDistance = distance.label
        let startedElapsed = elapsed.label
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
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        saveFinishedRun(app)
        XCTAssertTrue(app.staticTexts["run.saved"].waitForExistence(timeout: 15), "结束后缺少「已保存」反馈")
        attachScreenshot(app, name: "e2e-finish")

        historyTab.tap()
        XCTAssertTrue(
            waitUntil(timeout: 20) { rows.count == baselineCount + 1 },
            "结束后 History 应从 \(baselineCount) 条增至 \(baselineCount + 1) 条，实际 \(rows.count) 条"
        )
        XCTAssertFalse(app.staticTexts["history.empty"].exists, "有记录时不应显示空态")
        attachScreenshot(app, name: "e2e-history")

        // 列表按 startedAt 降序，首行即本次新记录。
        let row = rows.firstMatch
        XCTAssertTrue(row.exists, "History 缺少本次记录行")
        row.tap()

        let detailRoot = app.descendants(matching: .any).matching(identifier: "runDetail.root").firstMatch
        XCTAssertTrue(detailRoot.waitForExistence(timeout: 10), "点击历史行后未进入跑次详情")
        XCTAssertTrue(app.staticTexts["runDetail.startedAt"].waitForExistence(timeout: 5), "详情缺少开始时间")
        XCTAssertTrue(app.staticTexts["runDetail.distance"].exists, "详情缺少总距离")
        attachScreenshot(app, name: "e2e-detail")

        let exportButton = app.buttons["runDetail.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "详情缺少导出按钮")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "runDetail.exported").count,
            0,
            "落盘前不得出现导出完成态"
        )
        exportButton.tap()

        let exported = app.staticTexts["runDetail.exported"]
        XCTAssertTrue(exported.waitForExistence(timeout: 10), "导出后缺少完成态文本")
        XCTAssertTrue(exported.label.hasSuffix(".gpx"), "完成态必须包含 .gpx 文件名，实际 \(exported.label)")
        let share = app.descendants(matching: .any).matching(identifier: "runDetail.share").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "落盘后缺少系统分享入口")
        XCTAssertFalse(app.staticTexts["runDetail.exportFailed"].exists, "导出成功后不应显示失败态")

        // 真实点击分享入口后，系统活动视图必须出现；有界等待，不用固定 sleep。
        share.tap()
        XCTAssertTrue(
            waitUntil(timeout: 20) { shareSheetPresent(app) },
            "点击分享后系统分享面板/活动视图未出现"
        )
        attachScreenshot(app, name: "e2e-share")

        // 分享面板必须由用例自行关闭并回到详情（有界等待，无固定 sleep）：
        // 关闭按钮位于系统远程视图内，按面板右上角归一化坐标点击，失败再下滑兜底。
        XCTAssertTrue(dismissShareSheet(app), "系统分享面板未能在有界等待内自行关闭")
        XCTAssertFalse(shareSheetPresent(app), "分享面板应已消失")
        XCTAssertTrue(detailRoot.waitForExistence(timeout: 10), "关闭分享面板后应回到跑次详情")
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
        let settingsTab = tabBar.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "缺少 Settings Tab")
        XCTAssertTrue(
            tapSettingsUntilReady(app, screen: "settings-normalize"),
            "Settings 缺少每公里播报开关"
        )

        let toggle = app.switches["settings.announcementToggle"]

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
        // 重启后走状态判据：Tab 栏存在 → `设置` 按钮 exists && isHittable → tap →
        // 设置页根（`settings.announcementToggle`）出现。单次等待仍为 10s，未就绪允许再 tap ≤2 次；
        // 不用固定 sleep、不提高 timeout、不降低断言强度。
        let relaunchSettingsReady = tapSettingsUntilReady(app, screen: "relaunch-settings")
        if !relaunchSettingsReady {
            attachPersistedAnnouncementProbe(app, name: "relaunch-settings")
        }
        XCTAssertTrue(relaunchSettingsReady, "重启后缺少每公里播报开关")

        let relaunchedToggle = app.switches["settings.announcementToggle"]
        XCTAssertEqual(relaunchedToggle.value as? String, "0", "重启后应保持关闭状态")
    }

    /// ac-visible-copy-zh-hans / ac-run-detail-date-zh-hans / ac-primary-action-bottom-anchored：
    /// 三屏可及树逐条过 zh-Hans 白名单，详情/历史日期过 zh-Hans 判定，三态主操作过底部锚定判定；
    /// 同一判定同时产出 5 图 + 6 棵可及树证据（附件由 xcresulttool 导出）。
    ///
    /// 结束态内容 canonical（2026-11-12 归因）：`-uiTestLocationTargetMeters 1200` 把距离锁死在
    /// 1.2km（= 1 条分段），分段行数不再随 runner 墙钟漂移——CI 慢机器曾多跑 ≥100s 多出一行，
    /// 结束态实测 `top=36 bottom=12 imbalance=24` 判红，而本地 0 行时判绿。两种 canonical 内容
    /// （0 行 = 400m、1 行 = 1200m）分别由本用例与 `testSavedStateWithoutSplitsKeepsMapFloorAndBalance`
    /// 覆盖，两条都必须满足地图 ≥96 与保存态三判据（阈值 80/80/16 未改）。
    func testZhHansCopyDatesAndBottomAnchoredPrimaryAction() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestLocation",
            "-uiTestResetArchive",
            "-uiTestLocationTargetMeters",
            "1200"
        ]
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
        assertTabBarVisibility(app, state: .ready, didSave: false, screen: "未开始")
        assertBackgroundDegradedDemoted(app)

        // 1) 首屏未开始：文案 + 开始按钮底部锚定。
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "缺少开始按钮")
        assertVisibleCopyZhHans(app, screen: "跑步页（未开始）")
        assertPrimaryActionAnchored(app, button: start, state: "未开始")
        assertRunMetricsBalanced(app, primaryAction: start, state: "未开始")
        attachScreenshot(app, name: "run-not-started")
        attachAccessibilityTree(app, name: "01-run-not-started")

        // 2) 历史空态。
        tabBar.buttons["历史"].tap()
        XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: 10), "历史空态缺失")
        assertVisibleCopyZhHans(app, screen: "历史空态")
        attachScreenshot(app, name: "history-empty")
        attachAccessibilityTree(app, name: "03-history-empty")

        // 3) 运行中：文案 + 暂停按钮底部锚定。
        tabBar.buttons["跑步"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "返回跑步页后缺少开始按钮")
        start.tap()
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "运行时缺少暂停按钮")
        assertTabBarVisibility(app, state: .running, didSave: false, screen: "运行中")
        assertVisibleCopyZhHans(app, screen: "跑步页（运行中）")
        assertPrimaryActionAnchored(app, button: pause, state: "运行中")
        assertRunMetricsBalanced(app, primaryAction: pause, state: "运行中")
        attachScreenshot(app, name: "run-running")
        attachAccessibilityTree(app, name: "02-run-running")

        // 4) 保存态：主操作仍在底部锚定。
        // 距离已由 `-uiTestLocationTargetMeters` 在起跑帧锁到 1.2km（= 1 条分段），
        // 这里不再等「跑够时间」，分段行数对本地 / CI 同构。
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        assertTabBarVisibility(app, state: .finished, didSave: false, screen: "结束待保存")
        XCTAssertTrue(app.buttons["run.save"].exists, "结束待保存态缺少保存主操作")
        XCTAssertTrue(app.buttons["run.discardRequest"].exists, "结束待保存态缺少丢弃确认入口")
        XCTAssertFalse(app.buttons["run.discard"].exists, "确认层出现前不得直接暴露破坏性丢弃按钮")
        saveFinishedRun(app)
        XCTAssertTrue(app.staticTexts["run.saved"].waitForExistence(timeout: 15), "结束后缺少保存反馈")
        assertTabBarVisibility(app, state: .finished, didSave: true, screen: "保存态")
        let viewHistory = app.buttons["run.viewHistory"]
        XCTAssertTrue(viewHistory.waitForExistence(timeout: 10), "保存态缺少主操作按钮")
        assertVisibleCopyZhHans(app, screen: "跑步页（保存态）")
        assertPrimaryActionAnchored(app, button: viewHistory, state: "保存态")
        assertFinishedSplitRows(app, expected: 1, state: "保存态")
        assertFinishedMapFloor(app, state: "保存态")
        assertRunMetricsBalanced(app, primaryAction: viewHistory, state: "保存态")

        // 5) 历史列表与详情：日期必须 zh-Hans。
        tabBar.buttons["历史"].tap()
        assertTabBarVisibility(app, state: .finished, didSave: true, screen: "历史页")
        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        XCTAssertTrue(waitUntil(timeout: 15) { rows.count >= 1 }, "历史列表未出现本次记录")
        assertVisibleCopyZhHans(app, screen: "历史列表")
        rows.firstMatch.tap()

        let startedAt = app.staticTexts["runDetail.startedAt"]
        XCTAssertTrue(startedAt.waitForExistence(timeout: 10), "详情缺少开始时间")
        let startedText = startedAt.label
        let endedText = app.staticTexts["runDetail.endedAt"].label
        XCTAssertTrue(VisibleDatePolicy.isZhHansDateTime(startedText), "详情开始时间不是 zh-Hans：\(startedText)")
        XCTAssertTrue(VisibleDatePolicy.isZhHansDateTime(endedText), "详情结束时间不是 zh-Hans：\(endedText)")
        print("ac-run-detail-date-zh-hans started=\"\(startedText)\" ended=\"\(endedText)\"")
        assertVisibleCopyZhHans(app, screen: "跑次详情")
        attachScreenshot(app, name: "history-detail")
        attachAccessibilityTree(app, name: "04-history-detail")

        // 6) 设置页 + 完整 Tab 树。
        tabBar.buttons["设置"].tap()
        assertTabBarVisibility(app, state: .finished, didSave: true, screen: "设置页")
        XCTAssertTrue(
            app.switches["settings.announcementToggle"].waitForExistence(timeout: 10),
            "设置页缺少播报开关"
        )
        assertVisibleCopyZhHans(app, screen: "设置页")
        attachScreenshot(app, name: "settings")
        attachAccessibilityTree(app, name: "05-settings")

        // 7) 回到跑步页取完整 Tab 树（与设置页树区分）。
        tabBar.buttons["跑步"].tap()
        assertTabBarVisibility(app, state: .finished, didSave: true, screen: "回到跑步页")
        XCTAssertTrue(tabBar.buttons["设置"].waitForExistence(timeout: 10), "缺少设置 Tab")
        attachAccessibilityTree(app, name: "06-tabs")
    }

    /// ac-saved-balance-green（canonical 内容 B：0 条分段）：
    /// `-uiTestLocationTargetMeters 400` 把距离锁在 0.4km（= 0 行分段），保存态同样要满足
    /// 地图 ≥96pt 与 bottom ≤80 / largest ≤80 / imbalance ≤16。与 1 行内容（主用例 1200m）
    /// 成对固定，避免再用「墙钟跑多久」决定被断言的尺寸。
    func testSavedStateWithoutSplitsKeepsMapFloorAndBalance() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestLocation",
            "-uiTestResetArchive",
            "-uiTestLocationTargetMeters",
            "400"
        ]
        app.launch()
        allowLocationIfNeeded()

        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "缺少开始按钮")
        start.tap()
        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15), "缺少结束按钮")

        finish.tap()
        assertTabBarVisibility(app, state: .finished, didSave: false, screen: "结束待保存（无分段）")
        XCTAssertTrue(app.buttons["run.save"].exists, "结束待保存态缺少保存主操作")
        saveFinishedRun(app)
        XCTAssertTrue(app.staticTexts["run.saved"].waitForExistence(timeout: 15), "结束后缺少保存反馈")
        assertTabBarVisibility(app, state: .finished, didSave: true, screen: "保存态（无分段）")
        let viewHistory = app.buttons["run.viewHistory"]
        XCTAssertTrue(viewHistory.waitForExistence(timeout: 10), "保存态缺少主操作按钮")
        assertFinishedSplitRows(app, expected: 0, state: "保存态（无分段）")
        assertFinishedMapFloor(app, state: "保存态（无分段）")
        assertRunMetricsBalanced(app, primaryAction: viewHistory, state: "保存态（无分段）")
    }

    // MARK: - 授权与等待

    /// 把当前可及树中的全部非空 label 喂给与单测相同的 zh-Hans 白名单判定。
    /// SF Symbol 名称（系统图标标识）与 DEBUG 门控的 `run.telemetry` 诊断摘要不是用户可见文案，先滤除。
    /// MapKit 自己的注记（`VKPointFeature` / "Section N" 等系统地名、分区名）也不是 App 文案：
    /// 生产层已用 `children: .ignore` 把地图卡收敛成唯一 `run.mapPreview` 元素，但 MapKit 的
    /// 远端注记层会随相机缩放/地名密度抖动性地漏进可及树（实测 1.2km 轨迹缩放下出现
    /// "Ortega Park"），故按「地图卡区域内且非地图卡本身」过滤，保持门禁只判 App 文案。
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
            "ac-visible-copy-zh-hans \(screen): labels=\(texts.count) violations=\(violations.count) "
                + "offenders=\(offenders)"
        )
        XCTAssertTrue(
            violations.isEmpty,
            "\(screen) 存在裸英文文案：\(violations) offenders=\(offenders)"
        )
    }

    private func isSystemSymbolLabel(_ text: String) -> Bool {
        text.range(of: #"^[a-z0-9]+(\.[a-z0-9]+)+$"#, options: .regularExpression) != nil
    }

    /// 用真实按钮 frame 与 TabBar frame 喂给与单测相同的主操作底部锚定判定。
    /// 记录态 Tab 栏已收起时，以「窗口底边扣除 Home Indicator 安全区」作为等价锚点，
    /// 44pt 高度 / 24pt 底部间距阈值仍由 `PrimaryActionLayoutPolicy` 原样判定。
    private func assertPrimaryActionAnchored(
        _ app: XCUIApplication,
        button: XCUIElement,
        state: String
    ) {
        let tabBar = app.tabBars.firstMatch
        let anchor: CGRect
        // 记录态 Tab 栏已收起：hidden 状态下 firstMatch 仍可能命中零帧元素（minY = 0），
        // 只以落在底部的有效 frame 判定可见 Tab 栏，否则退回窗口底边扣除 Home Indicator 的等价锚点。
        if tabBar.exists && tabBar.frame.minY > 0 && tabBar.frame.height > 0 {
            anchor = tabBar.frame
        } else {
            let window = app.windows.firstMatch.frame
            anchor = CGRect(
                x: window.minX,
                y: window.maxY - Self.homeIndicatorInset,
                width: window.width,
                height: Self.homeIndicatorInset
            )
        }
        let evaluation = PrimaryActionLayoutPolicy.evaluate(
            actionFrame: button.frame,
            tabBarFrame: anchor
        )
        print(
            "ac-primary-action-bottom-anchored \(state): height=\(evaluation.height) "
                + "bottomGap=\(evaluation.bottomGap)"
        )
        XCTAssertTrue(
            evaluation.passes,
            "\(state) 主操作未底部锚定（高 \(evaluation.height)pt，底部间距 \(evaluation.bottomGap)pt）："
                + "\(evaluation.problems)"
        )
    }

    /// 采集四态可见内容块与主操作的真实 frame，喂给与单测相同的首屏四层分布判定。
    /// 采集口径：静态文本 frame + 结束态 `run.mapPreview` 地图卡 + 导航栏下沿 + 主操作顶边；
    /// 这里收全部 staticTexts（而非 identifier 白名单），把面板内 caption 也算作可见内容，
    /// 避免把「块内说明文案」误算成块间空洞。地图卡是可见内容块而非空白：96pt 地图
    /// 若不采样，会被误计成「最大单一垂直空洞」（保存态实测 112pt → 必红）。
    private func assertRunMetricsBalanced(
        _ app: XCUIApplication,
        primaryAction: XCUIElement,
        state: String
    ) {
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10), "缺少导航栏")
        let navigationBarBottom = navigationBar.frame.maxY
        let primaryActionTop = primaryAction.frame.minY
        var frames = app.staticTexts.allElementsBoundByIndex
            .filter { $0.identifier != "run.telemetry" }
            .map { $0.frame }
        if let mapFrame = mapPreviewFrame(
            app,
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop
        ) {
            frames.append(mapFrame)
        }
        frames = frames.filter { frame in
            !frame.isEmpty
                && frame.minY >= navigationBarBottom
                && frame.maxY <= primaryActionTop
        }
        let evaluation = RunLayoutBalancePolicy.evaluate(
            contentFrames: frames,
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop
        )
        print(
            "ac-run-metrics-balanced \(state): top=\(evaluation.topGap) bottom=\(evaluation.bottomGap) "
                + "largest=\(evaluation.largestGap) imbalance=\(evaluation.imbalance) "
                + "contentFrames=\(frames)"
        )
        XCTAssertTrue(
            evaluation.passes,
            "\(state) 指标区未垂直居中（顶部留白 \(evaluation.topGap)pt，底部留白 \(evaluation.bottomGap)pt，"
                + "最大空洞 \(evaluation.largestGap)pt）：\(evaluation.problems)"
        )
    }

    /// `run.mapPreview` 的真实 frame（仅结束态存在）；越界帧返回 nil，不塞脏样本。
    private func mapPreviewFrame(
        _ app: XCUIApplication,
        navigationBarBottom: CGFloat,
        primaryActionTop: CGFloat
    ) -> CGRect? {
        let map = app.descendants(matching: .any).matching(identifier: "run.mapPreview").firstMatch
        guard map.exists, !map.frame.isEmpty else { return nil }
        let frame = map.frame
        guard frame.minY >= navigationBarBottom, frame.maxY <= primaryActionTop else { return nil }
        return frame
    }

    /// ac-finished-content-canonical：结束态分段行数必须等于启动参数固定的 canonical 值
    /// （`-uiTestLocationTargetMeters m` → `floor(m / 1000)` 行），不允许随 runner 墙钟漂移。
    /// 行数漂移会把结束态内容顶出可用区，是「本地绿 / CI 红」的直接成因。
    private func assertFinishedSplitRows(_ app: XCUIApplication, expected: Int, state: String) {
        let rows = app.descendants(matching: .any).matching(identifier: "run.finished.splitRow")
        if expected == 0 {
            XCTAssertTrue(
                app.staticTexts["run.finished.splitsEmpty"].waitForExistence(timeout: 10),
                "\(state) 期望 0 条分段（splitsEmpty），实际行数 \(rows.count)"
            )
        } else {
            XCTAssertTrue(
                waitUntil(timeout: 10) { rows.count == expected },
                "\(state) 分段行数应为 canonical \(expected) 行，实际 \(rows.count) 行"
            )
        }
        print("ac-finished-content-canonical \(state): splitRows=\(rows.count) expected=\(expected)")
    }

    /// ac-finished-map-floor-96：结束态轨迹预览地图实测高度 ≥ 96pt（打印实测值）。
    /// 断言只用数值下限，不复述生产常量；历史 32pt 细条实测必红。
    private func assertFinishedMapFloor(_ app: XCUIApplication, state: String) {
        let map = app.descendants(matching: .any).matching(identifier: "run.mapPreview").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10), "\(state) 缺少轨迹预览地图 run.mapPreview")
        let height = map.frame.height
        print("ac-finished-map-floor-96 \(state): mapHeight=\(height)")
        XCTAssertGreaterThanOrEqual(height, 96, "\(state) 轨迹预览地图被压缩成细条：\(height)pt < 96pt")
    }

    /// Tab 栏可见性：把实测数量喂给与单测相同的纯判定，并打印可复核证据。
    private func assertTabBarVisibility(
        _ app: XCUIApplication,
        state: RunSessionState,
        didSave: Bool,
        screen: String,
        evidence: String = "ac-tabbar-hidden"
    ) {
        let observed = app.tabBars.count
        let evaluation = TabBarVisibilityPolicy.evaluate(
            state: state,
            didSave: didSave,
            observedTabBarCount: observed
        )
        print(
            "\(evidence) \(screen): state=\(state.rawValue) didSave=\(didSave) "
                + "tabBarCount=\(observed) expected=\(evaluation.expectedCount)"
        )
        XCTAssertTrue(evaluation.passes, "\(screen) Tab 栏可见性与状态不一致：\(evaluation.problems)")
        for title in ["跑步", "历史", "设置"] {
            let exists = app.tabBars.buttons[title].exists || app.buttons[title].exists
            XCTAssertEqual(
                exists,
                evaluation.expectedCount == 1,
                "\(screen) Tab「\(title)」存在性与期望不符"
            )
        }
    }

    /// 权限横幅降级：WhenInUse 降级态下提示降到指标卡内/之后的 `caption` 次级行，
    /// 不得压在距离 hero 之上，也不得插在 hero 与指标卡之间。
    private func assertBackgroundDegradedDemoted(_ app: XCUIApplication) {
        let hint = app.staticTexts["run.backgroundDegraded"]
        guard hint.waitForExistence(timeout: 5) else {
            print("ac-permission-banner-demoted skipped: 当前授权非 WhenInUse 降级态")
            return
        }
        let distance = app.staticTexts["run.distance"].frame
        let averagePace = app.staticTexts["run.averagePace"].frame
        print(
            "ac-permission-banner-demoted hint=\(hint.frame) distance=\(distance) "
                + "averagePace=\(averagePace)"
        )
        XCTAssertGreaterThan(hint.frame.minY, distance.maxY, "降级提示不得压在距离 hero 之上")
        XCTAssertGreaterThan(hint.frame.minY, averagePace.maxY, "降级提示必须在指标卡内/之后，不得插在 hero 与指标卡之间")
    }

    /// ac-finish-ui-rendered-accent：对按钮截图做真实像素采样，期望值从 `DesignTokens` 的
    /// `accent` light token 派生（不在测试里另写颜色字面量），容差 ≤ 2/255。
    /// 采样点取按钮左缘 1pt 的非文字竖线：填充主操作命中 accent 底，accent 描边命中边框，
    /// 旧 warning 描边 / 无 accent 填充实现采不到 accent 像素，必须判红。
    private func assertRenderedAccent(_ element: XCUIElement, evidence: String) {
        guard let expected = DesignTokens.Colors.palette["accent"]?.light else {
            XCTFail("\(evidence) 缺少 accent token")
            return
        }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else {
            XCTFail("\(evidence) 无有效 frame")
            return
        }
        let image = element.screenshot().image
        guard let cgImage = image.cgImage else {
            XCTFail("\(evidence) 无法取得截图")
            return
        }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            XCTFail("\(evidence) 无法建立采样位图")
            return
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let expectedR = Int((expected.red * 255).rounded())
        let expectedG = Int((expected.green * 255).rounded())
        let expectedB = Int((expected.blue * 255).rounded())
        let scaleX = CGFloat(width) / frame.width
        let scaleY = CGFloat(height) / frame.height
        let sampleX = min(width - 1, max(0, Int((1 * scaleX).rounded())))

        var matches = 0
        var nearest = (r: 0, g: 0, b: 0)
        var nearestDelta = Int.max
        var y = Int((frame.height * 0.2 * scaleY).rounded())
        let yEnd = Int((frame.height * 0.8 * scaleY).rounded())
        while y <= min(height - 1, yEnd) {
            let offset = (y * width + sampleX) * 4
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            let delta = max(abs(r - expectedR), max(abs(g - expectedG), abs(b - expectedB)))
            if delta < nearestDelta {
                nearestDelta = delta
                nearest = (r, g, b)
            }
            if delta <= 2 {
                matches += 1
            }
            y += max(1, Int(scaleY.rounded()))
        }

        print(
            "ac-finish-ui-rendered-accent \(evidence): expected=(\(expectedR),\(expectedG),\(expectedB)) "
                + "nearest=(\(nearest.r),\(nearest.g),\(nearest.b)) delta=\(nearestDelta) matches=\(matches)"
        )
        XCTAssertGreaterThan(
            matches, 0,
            "\(evidence) 未采到 accent 渲染像素（最近 \(nearest)，期望 \(expectedR),\(expectedG),\(expectedB)）"
        )
    }

    /// 以固定名称保存可及树文本（lifetime = .keepAlways），供证据导出。
    private func attachAccessibilityTree(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }


    /// 导航状态判据（AGENTS「测试稳定性约定」）：tap 前等 Tab 栏存在、`设置` 按钮 exists && isHittable，
    /// tap 后以设置页根 `settings.announcementToggle` 出现作为页面就绪判据。单次等待沿用既有 10s；
    /// 判据未满足时按状态重试 tap（首次 + 至多 2 次 = ≤2 次重试），不提高 timeout、不降低断言强度。
    /// 返回页面是否就绪；失败路径把当次可及树/截图写入 xcresult，供"点击被吞 vs 页面未就绪 vs 未持久化"归因。
    @discardableResult
    private func tapSettingsUntilReady(
        _ app: XCUIApplication,
        screen: String,
        waitAfterTap: TimeInterval = 10
    ) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            print("NAV-GATE screen=\(screen) stage=tabbar exists=false")
            attachAccessibilityTree(app, name: "\(screen)-tabbar-missing")
            attachScreenshot(app, name: "\(screen)-tabbar-missing")
            return false
        }
        let settingsTab = tabBar.buttons["设置"]
        guard waitUntil(timeout: 10, { settingsTab.exists && settingsTab.isHittable }) else {
            print(
                "NAV-GATE screen=\(screen) stage=settingsTab exists=\(settingsTab.exists) "
                    + "hittable=\(settingsTab.isHittable)"
            )
            attachAccessibilityTree(app, name: "\(screen)-settings-not-hittable")
            attachScreenshot(app, name: "\(screen)-settings-not-hittable")
            return false
        }
        let toggle = app.switches["settings.announcementToggle"]
        for attempt in 0...2 {
            if toggle.exists {
                return true
            }
            settingsTab.tap()
            if waitUntil(timeout: waitAfterTap, { toggle.exists }) {
                return true
            }
            print(
                "NAV-GATE screen=\(screen) stage=pageReady attempt=\(attempt) "
                    + "toggle=missing settingsSelected=\(settingsTab.isSelected) "
                    + "tabBar=\(tabBar.exists)"
            )
            attachAccessibilityTree(app, name: "\(screen)-attempt\(attempt)")
            attachScreenshot(app, name: "\(screen)-attempt\(attempt)")
        }
        return false
    }

    /// 判别探针：断言路径未就绪时，用既有 DEBUG 门控 `-screenshotInitialTab settings` 直接落到设置页，
    /// 绕过 tab tap 直读持久化值 —— `0` 说明等待/点击时序，`1` 说明偏好未跨重启持久化。
    /// 只读、只在失败路径调用，不参与断言判据。
    private func attachPersistedAnnouncementProbe(_ app: XCUIApplication, name: String) {
        app.terminate()
        app.launchArguments += ["-screenshotInitialTab", "settings"]
        app.launch()
        let toggle = app.switches["settings.announcementToggle"]
        let ready = toggle.waitForExistence(timeout: 30)
        let value = ready ? (toggle.value as? String ?? "nil") : "missing"
        print("RELAUNCH-PROBE name=\(name) probeToggleReady=\(ready) persisted=\(value)")
        attachAccessibilityTree(app, name: "\(name)-probe-tree")
        attachScreenshot(app, name: "\(name)-probe")
    }

    /// 通过真实 Settings UI 把每公里播报开关归一为开启（前序用例可能已关闭）。
    private func enableAnnouncements(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "缺少 Tab 栏")
        XCTAssertTrue(
            tapSettingsUntilReady(app, screen: "enable-announcements"),
            "Settings 缺少每公里播报开关"
        )
        let toggle = app.switches["settings.announcementToggle"]
        if (toggle.value as? String) == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertTrue(
                waitUntil(timeout: 5) { (toggle.value as? String) == "1" },
                "无法通过 Settings 开启每公里播报"
            )
        }
        tabBar.buttons["跑步"].tap()
        XCTAssertTrue(
            app.buttons["run.start"].waitForExistence(timeout: 10),
            "返回跑步页后缺少开始按钮"
        )
    }

    /// 从「1.23 km」距离读数解析公里数。
    private func distanceKilometers(_ label: String) -> Double {
        Double(label.split(separator: " ").first ?? "0") ?? 0
    }

    /// 以固定名称保存关键节点截图（lifetime = .keepAlways），供端到端脚本导出取证。
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 系统分享面板/活动视图是否可见（固定标识与本地化动作按钮的并集）。
    private func shareSheetPresent(_ app: XCUIApplication) -> Bool {
        app.otherElements["ActivityListView"].exists
            || app.sheets.firstMatch.exists
            || app.buttons["Copy"].exists
            || app.buttons["拷贝"].exists
            || app.buttons["Save to Files"].exists
            || app.buttons["存储到“文件”"].exists
    }

    /// 有界关闭系统分享面板：远程视图内的关闭按钮无法按 label 查询，先按面板右上角固定归一化
    /// 坐标点击关闭（X），失败再从面板内部下滑；整段关闭预算 ≤10s，返回面板是否已消失。
    private func dismissShareSheet(_ app: XCUIApplication) -> Bool {
        if !shareSheetPresent(app) {
            return true
        }
        let deadline = Date().addingTimeInterval(10)
        let sheet = app.otherElements["ActivityListView"]
        // 系统分享面板的关闭按钮位于远程容器内，只能相对面板坐标点击（右上角 X）。
        if sheet.exists {
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.08)).tap()
            if waitUntil(timeout: 3) { !shareSheetPresent(app) } {
                return true
            }
            // 兜底：从面板内部向下拖动关闭。
            let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            start.press(forDuration: 0.1, thenDragTo: end)
        } else {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        // 剩余预算内继续观察，总关闭判定不超过 10s。
        let remaining = max(1, deadline.timeIntervalSinceNow)
        return waitUntil(timeout: remaining) { !shareSheetPresent(app) }
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
    /// 返回是否点掉了弹窗；无弹窗返回 false。
    @discardableResult
    private func dismissLocationAlertsIfPresent() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication()
        for label in Self.locationAllowLabels {
            let springboardButton = springboard.buttons[label]
            if springboardButton.exists {
                springboardButton.tap()
                return true
            }
            let springboardAlertButton = springboard.alerts.firstMatch.buttons[label]
            if springboardAlertButton.exists {
                springboardAlertButton.tap()
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

    /// 授权兜底：`scripts/test-ios.sh` 预置 while-using 授权，`verify-ios-ui-e2e.sh` 在空容器上
    /// 走中断监听兜底；两条路径都可能有系统弹窗。此处只做有界兜底，扫描不到弹窗立即返回，
    /// 不空转到超时（弹窗存在时首轮即按文案放行并返回）。
    private func allowLocationIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if dismissLocationAlertsIfPresent() {
                return
            }
            // 没有任何授权弹窗：兜底立即结束，不消耗等待预算。
            if !springboard.alerts.firstMatch.exists && !app.alerts.firstMatch.exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// 结束只进入「待决策」：按可读 label 点保存主操作，落盘后才出现 `run.saved`。
    private func saveFinishedRun(_ app: XCUIApplication) {
        let save = app.buttons["保存本次跑步"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "结束待决策态缺少保存主操作")
        save.tap()
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
