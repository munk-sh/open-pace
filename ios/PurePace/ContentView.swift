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
    @State private var selection: Tab = .run

    private let archiveStore: RunArchiveStore

    @MainActor
    init() {
        let stores = RunStorage.makeStores()
        archiveStore = stores.archive
        _runModel = StateObject(
            wrappedValue: RunSessionViewModel(
                checkpointStore: stores.checkpoint,
                archiveStore: stores.archive,
                locationSource: RunLocationSource()
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
                refreshToken: runModel.savedCount,
                onRunAgain: { selection = .run }
            )
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
}
