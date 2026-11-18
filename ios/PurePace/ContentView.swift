import PurePaceRunCore
import SwiftUI

/// App 首屏：Run / History / Settings 三个 Tab，启动即落在真实跑步页（0 秒可用）。
struct ContentView: View {
    enum Tab: Hashable {
        case run
        case history
        case settings
    }

    @StateObject private var runModel: RunSessionViewModel
    @StateObject private var settings: AnnouncementSettingsStore
    @StateObject private var consent: TrajectoryConsentStore
    @State private var selection: Tab
    /// 同意屏独立呈现：首次启动未同意时覆盖全屏；点「不同意」后本进程内关闭但记录仍禁用。
    @State private var showsConsentGate: Bool

    private let archiveStore: RunArchiveStore
    private let exporter: RunGPXExporter
    /// 仅截图取证：默认 `nil` / `false`，Release 路径不注入任何演示数据。
    private let demoRecords: [RunRecord]?
    private let autoOpenDetail: Bool

    @MainActor
    init() {
        let stores = RunStorage.makeStores()
        let settings = AnnouncementSettingsStore()
#if DEBUG
        // 仅 DEBUG UI 用例：预置已同意 / 清空同意记录，避免同意门打断既有 UI 腿。
        TrajectoryConsentStore.applyUITestArguments(CommandLine.arguments)
#endif
        let consent = TrajectoryConsentStore()
        archiveStore = stores.archive
        exporter = stores.exporter
        _settings = StateObject(wrappedValue: settings)
        _consent = StateObject(wrappedValue: consent)
        _showsConsentGate = State(initialValue: !consent.hasConsented)
        var initialTab = Tab.run
        var demoRecords: [RunRecord]?
        var autoOpenDetail = false
        let locationSource: RunLocationProviding
        let telemetryDebugEnabled: Bool
#if DEBUG
        // UI 用例容器隔离（仅 `-uiTestResetArchive` 时清空归档/导出）。
        RunStorage.resetArchiveIfRequested()
        // 截图取证门控（仅 DEBUG，Release 路径不可达）：首屏 Tab 与历史页演示态。
        if let tab = RunLaunchArguments.value(
            after: RunLaunchArguments.screenshotInitialTabFlag,
            arguments: CommandLine.arguments
        ) {
            switch tab {
            case "history": initialTab = .history
            case "settings": initialTab = .settings
            default: initialTab = .run
            }
        }
        demoRecords = HistoryDemoRecords.records()
        autoOpenDetail = RunLaunchArguments.flagEnabled(
            RunLaunchArguments.screenshotOpenRunDetailFlag,
            arguments: CommandLine.arguments
        )
        // 仅 DEBUG 且显式传 `-uiTestLocation` 时使用确定性测试定位源；
        // 其余分支（含 Release）统一经选择器，默认落真实 `RunLocationSource`。
        if CommandLine.arguments.contains("-uiTestLocation") {
            locationSource = RunTestLocationSource()
            telemetryDebugEnabled = true
        } else {
            let selected = Self.makeLocationSource()
            locationSource = selected.source
            telemetryDebugEnabled = selected.telemetryDebugEnabled
        }
#else
        let selected = Self.makeLocationSource()
        locationSource = selected.source
        telemetryDebugEnabled = selected.telemetryDebugEnabled
#endif
        self.demoRecords = demoRecords
        self.autoOpenDetail = autoOpenDetail
        _selection = State(initialValue: initialTab)
        let recorder = AnnouncementTelemetryRecorder()
        _runModel = StateObject(
            wrappedValue: RunSessionViewModel(
                checkpointStore: stores.checkpoint,
                archiveStore: stores.archive,
                locationSource: locationSource,
                announcements: SpeechAnnouncementSpeaker(telemetry: recorder),
                announcementsEnabled: settings.isEnabled,
                announcementRecorder: recorder,
                authorizationProbe: SystemAuthorizationProbe(),
                telemetryDebugEnabled: telemetryDebugEnabled,
                autoStartRecording: RunLaunchArguments.autoStartRecordingEnabled(
                    arguments: CommandLine.arguments
                )
            )
        )
    }

    /// 除 `-uiTestLocation`（仅 Debug UI 用例）外的唯一定位源入口：Debug/Release 共用，
    /// 无 `-releaseDeterministicLocation` 时返回真实 `RunLocationSource`。
    private static func makeLocationSource() -> RunLocationSourceSelection.Selection {
        RunLocationSourceSelection.select(
            arguments: CommandLine.arguments,
            makeReal: { RunLocationSource() },
            makeDeterministic: { ReleaseDeterministicLocationSource(scenario: $0) }
        )
    }

    /// 三处「回起跑」入口共用的唯一路由：先收口结束态，再切到跑步 Tab。
    private func showRunEntry() {
        resetFinishedSessionIfNeeded()
        selection = .run
    }

    /// 结束态（保存成功总结）收口回 `ready`：判定只读状态，运行 / 暂停中绝不打断。
    private func resetFinishedSessionIfNeeded() {
        guard TabBarVisibilityPolicy.resetsToReadyOnRunTabEntry(state: runModel.state) else { return }
        runModel.runAgain()
    }

    var body: some View {
        TabView(selection: $selection) {
            RunView(
                viewModel: runModel,
                onShowHistory: { selection = .history },
                hasRecordingConsent: consent.hasConsented
            )
                .tabItem {
                    Label(L10n.tabRun, systemImage: "figure.run")
                        .accessibilityIdentifier("tab.run")
                }
                .tag(Tab.run)

            HistoryView(
                archiveStore: archiveStore,
                exporter: exporter,
                refreshToken: runModel.savedCount,
                onRunAgain: showRunEntry,
                injectedRecords: demoRecords,
                autoOpenFirstDetail: autoOpenDetail
            )
            .tabItem {
                Label(L10n.tabHistory, systemImage: "clock.arrow.circlepath")
                    .accessibilityIdentifier("tab.history")
            }
            .tag(Tab.history)

            SettingsView(
                store: settings,
                consent: consent,
                runModel: runModel,
                onRunAgain: showRunEntry
            )
                .tabItem {
                    Label(L10n.tabSettings, systemImage: "gearshape")
                        .accessibilityIdentifier("tab.settings")
                }
                .tag(Tab.settings)
        }
        .tint(DesignTokens.Colors.primary)
        .onChange(of: settings.isEnabled) { _, enabled in
            runModel.setAnnouncementsEnabled(enabled)
        }
        // 任一入口回起跑：点「跑步」tab 时若停在结束态，先收口回 ready 再展示起跑入口。
        .onChange(of: selection) { _, tab in
            guard tab == .run else { return }
            resetFinishedSessionIfNeeded()
        }
        .fullScreenCover(isPresented: $showsConsentGate) {
            PrivacyConsentGateView(
                onAgree: {
                    consent.grant()
                    showsConsentGate = false
                },
                onDecline: {
                    showsConsentGate = false
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
