import XCTest

/// 真机取证用例集：由 `scripts/verify-ios-device-flow.sh` 按阶段驱动，零人工操作。
///
/// - audit：Release 构建，只读观察首屏五个读数位 / 三 Tab / 详情导出入口，落盘截图与可及树。
/// - audio：Debug 构建 + `-uiTestLocation` 确定性测试源，跨一次公里边界；音源由 `--music-strategy`
///   决定（默认 `runner` = UITests runner 自播合成音，`app` = 起外部 App，`none` = 负对照无音源），
///   验证 duck 遥测与 `isOtherAudioPlaying` 可归因。
/// - background：两段式。阶段一开跑 → 起音源 → `press(.home)` 后立即结束；6 分钟等待放 Mac 侧；
///   阶段二 `activate()` 回前台完成结束保存、历史与导出。不在测试进程内 sleep 断言后台连续性。
///
/// 硬约束：不调用锁屏/解锁/密码相关 API；不在 run 内要求人按任何步骤；不驱动模拟器。
final class DeviceFlowUITests: XCTestCase {
    private static let locationAllowLabels = [
        "Allow While Using App", "Allow Once", "Allow", "Always Allow",
        "Change to Always Allow",
        "使用 App 期间允许", "允许一次", "始终允许", "允许改为始终允许"
    ]

    override func setUpWithError() throws {
        // 审计缺项要作为缺陷连同证据交回，不能让首个失败提前中断证据落盘；最终仍以断言收口。
        continueAfterFailure = true
    }

    // MARK: - 阶段 audit

    func testAuditFirstScreenAndTabs() {
        let app = XCUIApplication()
        app.launch()
        allowLocationIfNeeded()

        var result: [String: Any] = [
            "test": "testAuditFirstScreenAndTabs",
            "generatedAt": Date().timeIntervalSince1970,
        ]

        let distance = app.staticTexts["run.distance"]
        _ = distance.waitForExistence(timeout: 30)
        attachScreenshot(app, name: "audit-runview")
        attachAXDump(app, name: "audit-runview.ax.json")

        let metricIdentifiers = [
            "run.distance", "run.elapsed", "run.currentPace", "run.averagePace", "run.splits"
        ]
        var metrics: [String: [String: Any]] = [:]
        for identifier in metricIdentifiers {
            let element = app.staticTexts[identifier]
            let exists = element.waitForExistence(timeout: 5)
            metrics[identifier] = [
                "exists": exists,
                "label": exists ? element.label : NSNull(),
            ]
        }
        result["fiveMetrics"] = metrics
        let missingMetrics = metrics.filter { ($0.value["exists"] as? Bool) != true }.keys.sorted()

        let tabBar = app.tabBars.firstMatch
        let tabBarExists = tabBar.waitForExistence(timeout: 15)
        var tabs: [String: [String: Any]] = [
            "run": tabEvidence(
                app,
                tabName: "Run",
                tabBarExists: tabBarExists,
                content: { distance.exists },
                screenshot: "audit-run-tab",
                axDump: "audit-run-tab.ax.json"
            )
        ]

        tabs["history"] = tabEvidence(
            app,
            tabName: "History",
            tabBarExists: tabBarExists,
            content: {
                app.staticTexts["history.empty"].exists
                    || app.descendants(matching: .any).matching(identifier: "history.row").count > 0
            },
            screenshot: "audit-history",
            axDump: "audit-history.ax.json"
        )

        tabs["settings"] = tabEvidence(
            app,
            tabName: "Settings",
            tabBarExists: tabBarExists,
            content: { app.switches["settings.announcementToggle"].exists },
            screenshot: "audit-settings",
            axDump: "audit-settings.ax.json"
        )
        result["tabs"] = tabs

        // 详情导出入口：从 History 进入；归档为空时记 FAIL 并写明原因，不把入口写成「存在」。
        if tabBarExists { tabBar.buttons["History"].tap() }
        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        _ = waitUntil(timeout: 10) {
            rows.count > 0 || app.staticTexts["history.empty"].exists
        }
        var detailExport: [String: Any] = [
            "archiveAvailable": rows.count > 0,
            "rowCount": rows.count,
            "exists": false,
            "hittable": false,
        ]
        if rows.count > 0 {
            rows.firstMatch.tap()
            let detailRoot = app.descendants(matching: .any).matching(identifier: "runDetail.root").firstMatch
            if detailRoot.waitForExistence(timeout: 10) {
                let exportButton = app.buttons["runDetail.export"]
                _ = exportButton.waitForExistence(timeout: 5)
                var attempts = 0
                while !exportButton.isHittable && attempts < 4 {
                    app.swipeUp()
                    attempts += 1
                }
                detailExport = [
                    "archiveAvailable": true,
                    "rowCount": rows.count,
                    "exists": exportButton.exists,
                    "hittable": exportButton.exists && exportButton.isHittable,
                    "reason": exportButton.exists
                        ? (exportButton.isHittable ? "" : "runDetail.export 存在但不可点击")
                        : "详情页缺少 runDetail.export",
                ]
                attachScreenshot(app, name: "audit-detail")
                attachAXDump(app, name: "audit-detail.ax.json")
            } else {
                detailExport["reason"] = "点击历史行后未进入详情（runDetail.root 缺失）"
                attachAXDump(app, name: "audit-detail.ax.json")
            }
        } else {
            detailExport["reason"] = "归档为空：History 无 history.row，无法验证详情导出入口"
            attachAXDump(app, name: "audit-history-empty.ax.json")
        }
        result["detailExport"] = detailExport

        let tabsOk = tabs.values.allSatisfy { ($0["ok"] as? Bool) == true }
        let detailOk = (detailExport["exists"] as? Bool) == true
            && (detailExport["hittable"] as? Bool) == true
        result["allPassed"] = missingMetrics.isEmpty && tabBarExists && tabsOk && detailOk
        result["missingMetrics"] = missingMetrics
        attachJSON(result, name: "audit-result.json")

        XCTAssertTrue(tabBarExists, "缺少 Tab 栏")
        XCTAssertTrue(missingMetrics.isEmpty, "首屏缺失读数位: \(missingMetrics)")
        XCTAssertTrue(tabsOk, "三 Tab 审计未全部通过: \(tabs)")
        XCTAssertTrue(detailOk, "详情导出入口未通过: \(detailExport)")
    }

    // MARK: - 阶段 audio

    func testAudioKilometerBoundaryWithMusic() {
        let environment = ProcessInfo.processInfo.environment
        let resolution = MusicStrategy.from(environment: environment)

        let app = XCUIApplication()
        app.launchArguments += ["-uiTestLocation", "-uiTestResetArchive"]
        app.launch()
        allowLocationIfNeeded()

        let distance = app.staticTexts["run.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 30), "跑步页缺少距离读数")
        enableAnnouncements(app)

        var result: [String: Any] = [
            "test": "testAudioKilometerBoundaryWithMusic",
            "generatedAt": Date().timeIntervalSince1970,
        ]
        // 起音源（runner 自播 / app 外启 / none 不产生音源）；证据先于任何语义结论落盘。
        let (musicEvidence, runnerSource) = startMusicSource(environment: environment)
        result.merge(musicEvidence) { _, new in new }
        // 他路音频旁证：播报前 / 播报窗口 / 结束后各取一次快照（含取样时刻）。
        result["otherAudioSnapshotSource"] = OtherAudioSnapshot.source
        var otherAudioSnapshots: [[String: Any]] = [OtherAudioSnapshot.capture(label: "beforeRun")]

        app.activate()
        allowLocationIfNeeded()
        XCTAssertTrue(
            app.buttons["run.start"].waitForExistence(timeout: 15),
            "回到跑步页后缺少开始按钮"
        )

        let startedAt = Date()
        result["runStartedAt"] = startedAt.timeIntervalSince1970
        app.buttons["run.start"].tap()
        attachScreenshot(app, name: "audio-start")

        let crossed = waitUntil(timeout: 180) { self.distanceKilometers(distance.label) >= 1.0 }
        let crossSeconds = Date().timeIntervalSince(startedAt)
        otherAudioSnapshots.append(OtherAudioSnapshot.capture(label: "announcementWindow"))
        attachScreenshot(app, name: "audio-km")
        result["kilometerBoundaryReached"] = crossed
        result["kilometerBoundarySeconds"] = crossSeconds
        result["distanceAtBoundary"] = distance.label
        XCTAssertTrue(
            crossed,
            "确定性测试源未在有界等待内跨过 1 km 边界，当前 \(distance.label)"
        )

        let finish = app.buttons["run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "缺少结束按钮")
        finish.tap()
        let saved = app.staticTexts["run.saved"].waitForExistence(timeout: 15)
        XCTAssertTrue(saved, "结束后缺少「已保存」反馈")
        otherAudioSnapshots.append(OtherAudioSnapshot.capture(label: "afterFinish"))
        attachScreenshot(app, name: "audio-finish")

        let telemetry = app.staticTexts["run.telemetry"]
        let telemetryExists = telemetry.waitForExistence(timeout: 10)
        result["telemetrySummaryExists"] = telemetryExists
        result["telemetrySummary"] = telemetryExists ? telemetry.label : NSNull()
        result["runSeconds"] = Date().timeIntervalSince(startedAt)

        // 历史 → 详情 → 导出 GPX：让 audio 阶段也留下可校验的 .gpx 证据。
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 15) {
            tabBar.buttons["History"].tap()
            let rows = app.descendants(matching: .any).matching(identifier: "history.row")
            if waitUntil(timeout: 20, { rows.count > 0 }) {
                rows.firstMatch.tap()
                let detailRoot = app.descendants(matching: .any).matching(identifier: "runDetail.root").firstMatch
                if detailRoot.waitForExistence(timeout: 15) {
                    let exportButton = app.buttons["runDetail.export"]
                    if exportButton.waitForExistence(timeout: 10) {
                        var attempts = 0
                        while !exportButton.isHittable && attempts < 4 {
                            app.swipeUp()
                            attempts += 1
                        }
                        exportButton.tap()
                        let exported = app.staticTexts["runDetail.exported"]
                        let exportedReady = exported.waitForExistence(timeout: 20)
                        result["exported"] = exportedReady
                        result["exportedLabel"] = exportedReady ? exported.label : NSNull()
                        attachScreenshot(app, name: "audio-export")
                    }
                }
            }
        }

        // runner 播放器状态日志：结束前记录实测值，再停止播放；两遍（runner/none）都落这份字段。
        if let source = runnerSource {
            let finishEvidence = source.evidence()
            result["currentTimeAtFinish"] = finishEvidence["currentTimeAtFinish"]
            result["isPlayingAtFinish"] = finishEvidence["isPlayingAtFinish"]
            result["playbackStartedAt"] = finishEvidence["playbackStartedAt"]
            result["sessionSetActiveTrueCalled"] = finishEvidence["sessionSetActiveTrueCalled"]
            source.stop()
            result["playbackStoppedAt"] = source.playbackStoppedAt ?? NSNull()
        }
        result["otherAudioSnapshots"] = otherAudioSnapshots
        attachJSON(result, name: "audio-result.json")

        XCTAssertTrue(telemetryExists, "结束后缺少 DEBUG 门控的 run.telemetry 遥测摘要")
        if telemetryExists {
            XCTAssertTrue(
                telemetry.label.contains("第 1 公里"),
                "遥测缺少第 1 公里播报：\(telemetry.label)"
            )
            XCTAssertTrue(
                telemetry.label.contains("otherAudioPlaying="),
                "遥测缺少 isOtherAudioPlaying：\(telemetry.label)"
            )
        }

        // 音源可归因（裁决 A）：runner 正例必须起播且早于跑次开始；none 负例不得创建播放器。
        switch resolution.strategy {
        case .runner:
            XCTAssertEqual(result["playerStarted"] as? Bool, true, "runner 自播未起播（playerStarted）")
            XCTAssertEqual(result["isPlayingAtStart"] as? Bool, true, "runner 播放器起播后不在播")
            if let playbackStartedAt = result["playbackStartedAt"] as? Double {
                XCTAssertLessThan(
                    playbackStartedAt,
                    startedAt.timeIntervalSince1970,
                    "runner 起播时刻必须早于跑次开始时刻，否则不可归因"
                )
            } else {
                XCTFail("runner 起播时刻（playbackStartedAt）缺失，无法归因")
            }
            XCTAssertGreaterThan(
                (result["currentTimeAtFinish"] as? Double) ?? 0,
                0,
                "结束时 runner 播放器 currentTime 应为正"
            )
        case .none:
            XCTAssertEqual(result["playerStarted"] as? Bool, false, "none 策略不得创建播放器")
            XCTAssertEqual(result["isPlayingAtStart"] as? Bool, false, "none 策略不得在播")
            XCTAssertEqual(result["hasPlayer"] as? Bool, false, "none 策略下 hasPlayer 必须为 false")
        case .app:
            XCTAssertEqual(
                result["playerStarted"] as? Bool,
                result["musicPlayingConfirmed"] as? Bool,
                "app 策略须如实记录外部音源是否起播"
            )
        }
    }


    // MARK: - 阶段 background（阶段一：开跑 + 切后台）

    func testBackgroundStartAndPressHome() {
        let app = XCUIApplication()
        app.launch()
        allowLocationIfNeeded()

        let distance = app.staticTexts["run.distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 30), "跑步页缺少距离读数")

        // 播放器必须活到 home 键之后，否则 AVAudioPlayer 立刻释放、后台期间无他路音频。
        let (musicEvidence, backgroundSource) = startMusicSource(environment: ProcessInfo.processInfo.environment)
        app.activate()
        allowLocationIfNeeded()

        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "缺少开始按钮")
        let startedAt = Date().timeIntervalSince1970
        start.tap()
        attachScreenshot(app, name: "background-start")

        // 观测首个真实样本是否到来，仅作记录，不作后台成功判据。
        let elapsed = app.staticTexts["run.elapsed"]
        let firstSample = waitUntil(timeout: 20) { elapsed.exists && elapsed.label != "00:00" }

        let pressedHomeAt = Date().timeIntervalSince1970
        // 唯一前后台动作：home 键。不调用任何锁屏/解锁 API。
        XCUIDevice.shared.press(.home)

        var result: [String: Any] = [
            "test": "testBackgroundStartAndPressHome",
            "startedAt": startedAt,
            "pressedHomeAt": pressedHomeAt,
            "firstSampleObservedBeforeHome": firstSample,
        ]
        result.merge(musicEvidence) { _, new in new }
        result["isPlayingAtHome"] = backgroundSource?.isPlaying ?? false
        attachJSON(result, name: "background-stage1.json")
        backgroundSource?.stop()
    }

    // MARK: - 阶段 background（阶段二：回前台结束保存 + 导出）

    func testBackgroundFinishSaveAndExport() {
        let app = XCUIApplication()
        // 不 launch：只把仍在后台的运行会话带回前台，保住真实采样与 checkpoint。
        app.activate()
        allowLocationIfNeeded()

        var result: [String: Any] = [
            "test": "testBackgroundFinishSaveAndExport",
            "generatedAt": Date().timeIntervalSince1970,
        ]

        let finish = app.buttons["run.finish"]
        let finishExists = finish.waitForExistence(timeout: 60)
        result["sessionStillActive"] = finishExists
        guard finishExists else {
            result["reason"] = "回前台后未找到 run.finish：后台会话可能已被系统终止，不能伪造结束动作"
            attachScreenshot(app, name: "background-resume-failed")
            attachJSON(result, name: "background-result.json")
            XCTFail("回前台后运行会话不可用：\(result["reason"] ?? "")")
            return
        }

        finish.tap()
        let saved = app.staticTexts["run.saved"].waitForExistence(timeout: 20)
        result["saved"] = saved
        attachScreenshot(app, name: "background-finish")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "缺少 Tab 栏")
        tabBar.buttons["History"].tap()
        let rows = app.descendants(matching: .any).matching(identifier: "history.row")
        let historyReady = waitUntil(timeout: 20) { rows.count > 0 }
        result["historyRowCount"] = rows.count
        XCTAssertTrue(historyReady, "History 未出现本次跑次")
        attachScreenshot(app, name: "background-history")

        rows.firstMatch.tap()
        let detailRoot = app.descendants(matching: .any).matching(identifier: "runDetail.root").firstMatch
        let detailReady = detailRoot.waitForExistence(timeout: 15)
        result["detailRoot"] = detailReady
        XCTAssertTrue(detailReady, "未进入跑次详情")

        let exportButton = app.buttons["runDetail.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10), "详情缺少导出按钮")
        var attempts = 0
        while !exportButton.isHittable && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(exportButton.isHittable, "导出按钮不可点击")
        exportButton.tap()

        let exported = app.staticTexts["runDetail.exported"]
        let exportedReady = exported.waitForExistence(timeout: 20)
        result["exported"] = exportedReady
        result["exportedLabel"] = exportedReady ? exported.label : NSNull()
        attachScreenshot(app, name: "background-export")
        attachJSON(result, name: "background-result.json")

        XCTAssertTrue(exportedReady, "导出后缺少完成态文本")
        XCTAssertTrue(exported.label.hasSuffix(".gpx"), "完成态必须包含 .gpx 文件名")
    }

    // MARK: - 音源

    /// 按策略起音源并返回结构化证据 + runner 播放器（非 runner 策略为 nil）。
    ///
    /// - `runner`（默认）：UITests runner 自播合成循环音，对被测 App 就是他路音频，可归因；
    /// - `app`：启动 `--music-bundle-id` 指定 App（缺省 `com.apple.Music`），起播失败如实记 false；
    /// - `none`：不创建任何播放器（负对照）。
    private func startMusicSource(
        environment: [String: String]
    ) -> ([String: Any], RunnerMusicSource?) {
        let resolution = MusicStrategy.from(environment: environment)
        let bundleIdentifier = MusicStrategy.bundleIdentifier(environment: environment)
        var payload: [String: Any] = [
            "musicStrategy": resolution.strategy.rawValue,
            "musicStrategyRequested": resolution.rawValue ?? NSNull(),
            "musicStrategyInvalidRequested": resolution.invalidRequested ?? NSNull(),
            "musicBundleIdentifier": NSNull(),
        ]
        switch resolution.strategy {
        case .runner:
            let source = RunnerMusicSource()
            let started = source.start()
            payload.merge(source.evidence()) { _, new in new }
            payload["musicPlayingConfirmed"] = started
            payload["musicRunning"] = started
            return (payload, source)
        case .app:
            let music = XCUIApplication(bundleIdentifier: bundleIdentifier)
            music.launch()
            let running = music.wait(for: .runningForeground, timeout: 20)
                || music.wait(for: .runningBackground, timeout: 10)
            let playing = running ? ensureMusicPlaying(music) : false
            payload["musicBundleIdentifier"] = bundleIdentifier
            payload["musicRunning"] = running
            payload["musicPlayingConfirmed"] = playing
            payload["playerStarted"] = playing
            payload["isPlayingAtStart"] = playing
            attachScreenshot(music, name: "audio-music")
            return (payload, nil)
        case .none:
            payload["musicRunning"] = false
            payload["musicPlayingConfirmed"] = false
            payload["playerStarted"] = false
            payload["isPlaying"] = false
            payload["isPlayingAtStart"] = false
            payload["isPlayingAtFinish"] = false
            payload["hasPlayer"] = false
            return (payload, nil)
        }
    }

    /// `app` 策略下尽力让外部播放器进入播放态：先找 Pause（已在播），再点 Play；
    /// 找不到播放控件如实返回 false。
    private func ensureMusicPlaying(_ music: XCUIApplication) -> Bool {
        if music.buttons["Pause"].exists || music.buttons["暂停"].exists {
            return true
        }
        for label in ["Play", "播放", "Shuffle", "随机播放"] {
            let button = music.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                if music.buttons["Pause"].waitForExistence(timeout: 5)
                    || music.buttons["暂停"].waitForExistence(timeout: 5) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - 证据附件

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 可及树 dump：把 `debugDescription` 包进 JSON，脚本按 identifier 文本判定。
    private func attachAXDump(_ app: XCUIApplication, name: String) {
        let payload: [String: Any] = [
            "generatedAt": Date().timeIntervalSince1970,
            "dump": app.debugDescription,
        ]
        attachJSON(payload, name: name)
    }

    private func attachJSON(_ payload: [String: Any], name: String) {
        let data: Data
        if JSONSerialization.isValidJSONObject(payload),
           let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            data = encoded
        } else {
            data = Data("{\"error\":\"unserializable\"}".utf8)
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 授权与等待

    private func enableAnnouncements(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "缺少 Tab 栏")
        tabBar.buttons["Settings"].tap()
        let toggle = app.switches["settings.announcementToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings 缺少每公里播报开关")
        if (toggle.value as? String) == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            _ = waitUntil(timeout: 5) { (toggle.value as? String) == "1" }
        }
        tabBar.buttons["Run"].tap()
        _ = app.buttons["run.start"].waitForExistence(timeout: 10)
    }

    private func tabEvidence(
        _ app: XCUIApplication,
        tabName: String,
        tabBarExists: Bool,
        content: () -> Bool,
        screenshot: String,
        axDump: String
    ) -> [String: Any] {
        guard tabBarExists, app.tabBars.buttons[tabName].exists else {
            return ["ok": false, "reason": "缺少 \(tabName) Tab", "screenshot": screenshot]
        }
        app.tabBars.buttons[tabName].tap()
        let ok = waitUntil(timeout: 10, content)
        attachScreenshot(app, name: screenshot)
        attachAXDump(app, name: axDump)
        return [
            "ok": ok,
            "reason": ok ? "" : "\(tabName) 页面缺少可及内容元素",
            "screenshot": "\(screenshot).png",
            "axDump": axDump,
        ]
    }

    private func distanceKilometers(_ label: String) -> Double {
        Double(label.split(separator: " ").first ?? "0") ?? 0
    }

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

    private func allowLocationIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if dismissLocationAlertsIfPresent() {
                return
            }
            if !springboard.alerts.firstMatch.exists && !app.alerts.firstMatch.exists {
                return
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
}
