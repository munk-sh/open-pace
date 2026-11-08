import SwiftUI

/// 设置页：唯一真实偏好是每公里语音播报开关，不放置任何额外假控件或数值。
struct SettingsView: View {
    @ObservedObject var store: AnnouncementSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Toggle("每公里语音播报", isOn: $store.isEnabled)
                    .accessibilityIdentifier("settings.announcementToggle")
            }
            .navigationTitle("Settings")
        }
    }
}
