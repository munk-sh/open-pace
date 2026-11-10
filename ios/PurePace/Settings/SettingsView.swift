import SwiftUI

/// 设置页：唯一真实偏好是每公里语音播报开关，按分组标题呈现并给每项一句说明；
/// 不放置任何额外假控件或数值。
struct SettingsView: View {
    @ObservedObject var store: AnnouncementSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $store.isEnabled) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text("每公里语音播报")
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.primary)
                            Text("每跑满一公里时朗读当前配速与累计时长。")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.secondary)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                    }
                    .frame(minHeight: DesignTokens.minTapTarget)
                    .accessibilityIdentifier("settings.announcementToggle")
                    .accessibilityLabel("每公里语音播报")
                } header: {
                    Text("播报")
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                } footer: {
                    Text("关闭后跑步过程中的语音播报会立即停止。")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .accessibilityIdentifier("tab.settings")
    }
}
