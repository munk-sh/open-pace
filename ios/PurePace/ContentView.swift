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
        _runModel = StateObject(
            wrappedValue: RunSessionViewModel(
                checkpointStore: stores.checkpoint,
                archiveStore: stores.archive,
                locationSource: RunLocationSource(),
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
