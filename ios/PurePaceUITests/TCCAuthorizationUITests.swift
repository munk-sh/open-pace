import XCTest

/// 真机 TCC（系统定位授权）授权步骤：只走 XCUITest 官方可及性路径。
///
/// 由 `scripts/verify-ios-device-flow.sh --phase=tcc` 驱动（Debug 构建 + 真实 CoreLocation，
/// 不传 `-uiTestLocation`）；默认模拟器 UI 腿通过
/// `-skip-testing:PurePaceUITests/TCCAuthorizationUITests` 排除，不进 CI 预算。
///
/// 硬约束：不使用像素采样 / 颜色判定 / 归一化坐标点击 / 「截图找按钮」；
/// 只使用 SpringBoard 与 App 的 accessibility 元素查询 + 精确 label 匹配，
/// `addUIInterruptionMonitor` 仅作兜底。失败只输出可及性 label 集合。
@MainActor
final class TCCAuthorizationUITests: XCTestCase {

    // MARK: - label 兜底表（精确匹配，不做包含匹配）

    enum Labels {
        /// 首次「使用 App 期间」弹窗：命中即点击（同意 WhenInUse）。
        static let firstAllow = [
            "Allow While Using App",
            "使用App时允许",
            "使用 App 期间允许",
            "Allow Once",
            "允许一次",
        ]
        /// 首次弹窗的诊断 label：只记录，不点击拒绝。
        static let firstDiagnostic = [
            "Don't Allow",
            "不允许",
            "Allow",
            "允许",
        ]
        /// Always 升级弹窗：命中即点击。
        static let upgradeAllow = [
            "Change to Always Allow",
            "更改为始终允许",
            "允许改为始终允许",
            "Always Allow",
            "始终允许",
        ]
        /// 升级弹窗的诊断 label：只记录，不点击降级项。
        static let upgradeDiagnostic = [
            "Keep Only While Using",
            "仅在使用App期间允许",
            "仅在使用 App 期间允许",
        ]

        static var firstExpected: [String] { firstAllow + firstDiagnostic }
        static var upgradeExpected: [String] { upgradeAllow + upgradeDiagnostic }
        /// 诊断兜底只认已知授权 label，避免把主屏图标等无关按钮混进证据。
        static var allExpected: [String] { firstExpected + upgradeExpected }
    }

    /// 失败阶段名：与 `docs/device-tcc-automation.md` 的判读表一一对应。
    enum Stage: String {
        case waitFirstLaunch = "等待首启"
        case handleFirstPrompt = "处理首次弹窗"
        case requestUpgrade = "发起升级"
        case handleUpgradePrompt = "处理升级弹窗"
        case finishRun = "结束跑次"
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let app = XCUIApplication()

    /// `grantedThisRun`：本次跑次内处理过首次系统弹窗；`preAuthorized`：设备已预先授权、无弹窗。
    private var authorizationMode = "unknown"
    private var firstPromptHandled = false
    private var upgradePromptHandled = false
    private var currentStage: Stage = .waitFirstLaunch
    private var hitLabels: [String: String] = [:]
    private var stageDiagnostics: [[String: Any]] = []
    private var runSaved = false
    private var degradedGone = false
    private var resultAttachmentWritten = false

    override func setUpWithError() throws {
        // 任一阶段缺证据都要落盘交回；断言在用例末尾统一收口。
        continueAfterFailure = true
    }

    // MARK: - 用例：新装首启 → 首次弹窗 → Always 升级 → App 自报 authorizedAlways

    func testTCCFreshInstallReachesAuthorizedAlways() {
        // 用例中途退出（断言失败 / launch 崩溃）也要留下证据：teardown 块兜底落盘一次。
        addTeardownBlock { [weak self] in
            MainActor.assumeIsolated {
                self?.writeResultAttachmentIfNeeded()
            }
        }
        addUIInterruptionMonitor(withDescription: "TCC 定位授权弹窗") { [weak self] alert in
            guard let self, Thread.isMainThread else { return false }
            return MainActor.assumeIsolated { self.handleInterruption(alert) }
        }

        // 真实定位源；`-uiTestResetArchive` 只清历史归档与导出，不重置 TCC。
        app.launchArguments += ["-uiTestResetArchive"]
        app.launch()

        currentStage = .waitFirstLaunch
        if !app.wait(for: .runningForeground, timeout: 30) {
            recordFailure(stage: .waitFirstLaunch, reason: "首启后 30s 内未进入前台")
        }

        // 1) 首次系统弹窗：有界等待；整窗无弹窗即视为设备已预先授权。
        currentStage = .handleFirstPrompt
        handleFirstPromptIfPresent()

        // 首启就绪（系统弹窗可能盖在 App 上方，故放在弹窗处理之后判定）。
        currentStage = .waitFirstLaunch
        let distance = app.staticTexts["run.distance"]
        if !distance.waitForExistence(timeout: 60) {
            recordFailure(stage: .waitFirstLaunch, reason: "首启后未出现 run.distance")
        }

        // 2) WhenInUse 降级提示（App 自报）出现或短窗口超时。
        let degraded = app.staticTexts["run.backgroundDegraded"]
        _ = degraded.waitForExistence(timeout: 15)

        // 3) 点击 run.start 触发 requestAlwaysAuthorization；升级弹窗若已在首启阶段处理
        //    （设备预先 WhenInUse 时首启即升级），这里不重复等待。
        let elapsedBeforeStart = app.staticTexts["run.elapsed"].label
        currentStage = .requestUpgrade
        let start = app.buttons["run.start"]
        if start.waitForExistence(timeout: 20) {
            start.tap()
            triggerInterruptionMonitor()
            if !upgradePromptHandled {
                handleUpgradePromptIfPresent()
            }
        } else {
            recordFailure(stage: .requestUpgrade, reason: "未找到 run.start，无法发起 Always 升级请求")
        }

        // 让真实采样先落一点内容，避免 0 样本结束保存不出跑次。
        _ = waitUntil(timeout: 12) { self.app.staticTexts["run.elapsed"].label != elapsedBeforeStart }

        // 4) 有界等待降级提示消失（App 自报已非 WhenInUse）。
        degradedGone = waitUntil(timeout: 20) { !degraded.exists }

        // 5) 结束跑次并等 App 自报「已保存」。
        currentStage = .finishRun
        let finish = app.buttons["run.finish"]
        if finish.waitForExistence(timeout: 20) {
            finish.tap()
            triggerInterruptionMonitor()
            runSaved = app.staticTexts["run.saved"].waitForExistence(timeout: 30)
        } else {
            runSaved = false
        }
        if !runSaved {
            recordFailure(stage: .finishRun, reason: "结束跑次后 30s 内未出现 run.saved")
        }

        writeResultAttachment()

        XCTAssertNotEqual(authorizationMode, "unknown", "未判定授权模式（详见 tcc-result.json）")
        XCTAssertTrue(
            stageDiagnostics.isEmpty,
            "TCC 授权链路失败阶段: \(failureStageSummary)；详见 tcc-result.json"
        )
        XCTAssertTrue(runSaved, "结束跑次后未出现「已保存」反馈（详见 tcc-result.json）")
    }

    // MARK: - 可复用步骤

    /// 首个系统弹窗：按 label 而不是按时序分类——新装设备是「使用 App 期间」弹窗；
    /// 已预先 WhenInUse 的设备首启就会触发 Always 升级弹窗（`RunLocationSource.start()`）。
    private func handleFirstPromptIfPresent() {
        let hit = handlePrompt(
            stage: .handleFirstPrompt,
            allowLabels: Labels.firstAllow + Labels.upgradeAllow,
            expected: Labels.firstExpected + Labels.upgradeExpected,
            timeout: 20
        )
        guard let hit else {
            // 整窗内没有系统弹窗：设备已预先授权（首次弹窗不会出现）。
            if !firstPromptHandled {
                authorizationMode = "preAuthorized"
            }
            return
        }
        if Labels.firstAllow.contains(hit) {
            firstPromptHandled = true
            authorizationMode = "grantedThisRun"
            hitLabels["firstPrompt"] = hit
        } else {
            // 预先 WhenInUse：首启的弹窗就是 Always 升级弹窗。
            upgradePromptHandled = true
            authorizationMode = "preAuthorized"
            hitLabels["upgradePrompt"] = hit
        }
    }

    /// Always 升级弹窗：命中即点击；弹窗已出现但 label 未命中则记录失败阶段。
    private func handleUpgradePromptIfPresent() {
        guard let hit = handlePrompt(
            stage: .handleUpgradePrompt,
            allowLabels: Labels.upgradeAllow,
            expected: Labels.upgradeExpected,
            timeout: 20
        ) else { return }
        upgradePromptHandled = true
        hitLabels["upgradePrompt"] = hit
    }

    /// 可复用弹窗处理：有界轮询，命中允许 label 即点击；窗口结束时弹窗仍在且未命中才记失败。
    @discardableResult
    private func handlePrompt(
        stage: Stage,
        allowLabels: [String],
        expected: [String],
        timeout: TimeInterval
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var sawPrompt = false
        repeat {
            if promptPresent() {
                sawPrompt = true
                if let hit = tapPromptButton(labels: allowLabels) {
                    return hit
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline

        if sawPrompt {
            recordFailure(
                stage: stage,
                reason: "系统弹窗已出现但未命中任何允许 label（等待 \(Int(timeout))s）",
                expected: expected
            )
        }
        return nil
    }

    private func handleInterruption(_ alert: XCUIElement) -> Bool {
        guard currentStage != .finishRun else { return false }
        for label in Labels.firstAllow + Labels.upgradeAllow {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                recordHit(label: label)
                return true
            }
        }
        return false
    }

    private func recordHit(label: String) {
        if Labels.firstAllow.contains(label) {
            firstPromptHandled = true
            authorizationMode = "grantedThisRun"
            hitLabels["firstPrompt"] = label
        } else {
            upgradePromptHandled = true
            if authorizationMode == "unknown" {
                authorizationMode = "preAuthorized"
            }
            hitLabels["upgradePrompt"] = label
        }
    }

    // MARK: - 可及性查询（精确 label）

    private func promptPresent() -> Bool {
        springboard.alerts.firstMatch.exists || app.alerts.firstMatch.exists
    }

    /// 按精确 label 在 SpringBoard → App 弹窗内点击；返回命中的 label。
    @discardableResult
    private func tapPromptButton(labels: [String]) -> String? {
        for root in [springboard, app] {
            let alert = root.alerts.firstMatch
            guard alert.exists else { continue }
            // 常规情况弹窗自带按钮；个别系统版本把按钮挂在根节点，才回落到根查询。
            let scopes: [XCUIElement] = alert.buttons.count > 0 ? [alert] : [alert, root]
            for scope in scopes {
                for label in labels {
                    let button = scope.buttons[label]
                    if button.exists {
                        button.tap()
                        return label
                    }
                }
            }
        }
        return nil
    }

    /// 唤醒 `addUIInterruptionMonitor` 兜底：仅在确实有弹窗时触发一次 App 交互。
    private func triggerInterruptionMonitor() {
        if promptPresent() {
            app.tap()
        }
    }

    /// 当时实际存在的弹窗按钮 label 集合（只输出可及性 label，不做图片判读）。
    /// 没有弹窗时返回空集合：不把通知横幅等无关按钮混进诊断。
    private func promptLabelSnapshot() -> [String: [String]] {
        let known = Set(Labels.allExpected)
        func labels(of root: XCUIElement) -> [String] {
            let alert = root.alerts.firstMatch
            let buttons: [XCUIElement]
            if alert.exists {
                buttons = alert.buttons.allElementsBoundByIndex
            } else {
                // 个别系统版本把 TCC 面板放在 alert 之外：只在根节点按已知授权 label 兜底，
                // 避免把主屏图标等无关按钮混进诊断。
                buttons = root.buttons.allElementsBoundByIndex.filter { known.contains($0.label) }
            }
            var seen: Set<String> = []
            var result: [String] = []
            for button in buttons {
                let label = button.label
                if !label.isEmpty && !seen.contains(label) {
                    seen.insert(label)
                    result.append(label)
                }
            }
            return result
        }
        return [
            "springboard": labels(of: springboard),
            "app": labels(of: app),
        ]
    }

    // MARK: - 诊断

    private var failureStageSummary: String {
        stageDiagnostics.map { ($0["stage"] as? String) ?? "?" }.joined(separator: "、")
    }

    private func recordFailure(stage: Stage, reason: String, expected: [String]? = nil) {
        var entry: [String: Any] = [
            "stage": stage.rawValue,
            "reason": reason,
            "expectedLabels": expected ?? expectedLabels(for: stage),
            "actualPromptButtons": promptLabelSnapshot(),
        ]
        entry["at"] = Date().timeIntervalSince1970
        stageDiagnostics.append(entry)
    }

    private func expectedLabels(for stage: Stage) -> [String] {
        switch stage {
        case .waitFirstLaunch, .handleFirstPrompt:
            return Labels.firstExpected
        case .requestUpgrade, .handleUpgradePrompt:
            return Labels.upgradeExpected
        case .finishRun:
            // 结束跑次不涉及授权 label，诊断里不冒充授权期望。
            return []
        }
    }

    /// teardown 兜底：正常路径已落盘时不重复添加附件。
    private func writeResultAttachmentIfNeeded() {
        guard !resultAttachmentWritten else { return }
        writeResultAttachment()
    }

    private func writeResultAttachment() {
        let payload: [String: Any] = [
            "test": "testTCCFreshInstallReachesAuthorizedAlways",
            "generatedAt": Date().timeIntervalSince1970,
            "stage": currentStage.rawValue,
            "authorizationMode": authorizationMode,
            "firstPromptHandled": firstPromptHandled,
            "upgradePromptHandled": upgradePromptHandled,
            "hitLabels": hitLabels,
            "backgroundDegradedGone": degradedGone,
            "saved": runSaved,
            "failureStage": stageDiagnostics.first.flatMap { $0["stage"] as? String } ?? NSNull(),
            "failures": stageDiagnostics,
            "expectedLabels": [
                "firstPrompt": Labels.firstExpected,
                "upgradePrompt": Labels.upgradeExpected,
            ],
            "finalPromptButtons": promptLabelSnapshot(),
        ]
        let data: Data
        if JSONSerialization.isValidJSONObject(payload),
           let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            data = encoded
        } else {
            data = Data("{\"error\":\"unserializable\"}".utf8)
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "tcc-result.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        resultAttachmentWritten = true
    }

    // MARK: - 等待

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
