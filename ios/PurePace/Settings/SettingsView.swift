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
                            Text(L10n.settingsAnnouncementTitle)
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.primary)
                            Text(L10n.settingsAnnouncementBody)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.secondary)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                    }
                    .tint(DesignTokens.Colors.accent)
                    .frame(minHeight: DesignTokens.minTapTarget)
                    .listRowBackground(DesignTokens.Colors.surface)
                    .listRowSeparatorTint(DesignTokens.Colors.separator)
                    .accessibilityIdentifier("settings.announcementToggle")
                    .accessibilityLabel(Text(L10n.settingsAnnouncementTitle))
                } header: {
                    Text(L10n.settingsSectionAnnouncement)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .textCase(nil)
                } footer: {
                    Text(L10n.settingsFooterAnnouncement)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.Colors.background)
            .navigationTitle(L10n.settingsNavigationTitle)
        }
        .tint(DesignTokens.Colors.accent)
        .accessibilityIdentifier("tab.settings")
    }
}
