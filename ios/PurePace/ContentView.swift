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
    @State private var selection: Tab = .run

    private let archiveStore: RunArchiveStore
    private let exporter: RunGPXExporter

    @MainActor
    init() {
        let stores = RunStorage.makeStores()
        let settings = AnnouncementSettingsStore()
        archiveStore = stores.archive
        exporter = stores.exporter
        _settings = StateObject(wrappedValue: settings)
        let locationSource: RunLocationProviding
#if DEBUG
        // 仅 DEBUG 且显式传 `-uiTestLocation` 时使用确定性测试定位源；
        // 生产与 Release 构建仍走真实定位数据源（RunLocationSource）。
        if CommandLine.arguments.contains("-uiTestLocation") {
            locationSource = RunTestLocationSource()
        } else {
            locationSource = RunLocationSource()
        }
#else
        locationSource = RunLocationSource()
#endif
        _runModel = StateObject(
            wrappedValue: RunSessionViewModel(
                checkpointStore: stores.checkpoint,
                archiveStore: stores.archive,
                locationSource: locationSource,
                announcementsEnabled: settings.isEnabled
            )
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            RunView(viewModel: runModel)
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(Tab.run)

            HistoryView(
                archiveStore: archiveStore,
                exporter: exporter,
                refreshToken: runModel.savedCount,
                onRunAgain: { selection = .run }
            )
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            SettingsView(store: settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: settings.isEnabled) { _, enabled in
            runModel.setAnnouncementsEnabled(enabled)
        }
    }
}

#Preview {
    ContentView()
}
