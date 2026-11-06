import SwiftUI

/// 空壳首屏：App 名称 + 一句 tagline，外加四个空 Tab。
/// 不含业务逻辑、网络请求或内置样例数据。
struct ContentView: View {
    var body: some View {
        TabView {
            PlaceholderScreen(
                title: PlaceholderCopy.appName,
                subtitle: PlaceholderCopy.tagline
            )
            .tabItem { tabLabel(.run) }

            PlaceholderScreen(title: PlaceholderTab.history.title)
                .tabItem { tabLabel(.history) }

            PlaceholderScreen(title: PlaceholderTab.log.title)
                .tabItem { tabLabel(.log) }

            PlaceholderScreen(title: PlaceholderTab.settings.title)
                .tabItem { tabLabel(.settings) }
        }
    }

    private func tabLabel(_ tab: PlaceholderTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}

#Preview {
    ContentView()
}
