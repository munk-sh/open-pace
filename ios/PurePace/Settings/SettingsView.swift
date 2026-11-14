import SwiftUI

/// 设置页：每公里语音播报开关 + 「关于」分组（应用内政策全文与撤回轨迹数据同意）。
/// 分组结构 = 显式 Section 标题 + token 化行容器（surface 行底 / separator hairline / Radius.card），
/// 不使用系统 grouped 观感，全部颜色、字号、间距、圆角与描边引用 `DesignTokens`。
struct SettingsView: View {
    @ObservedObject var store: AnnouncementSettingsStore
    @ObservedObject var consent: TrajectoryConsentStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    announcementRow
                    announcementFooterRow
                } header: {
                    Text(L10n.settingsSectionAnnouncement)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .textCase(nil)
                }

                Section {
                    privacyPolicyRow
                    if consent.hasConsented {
                        consentStatusRow
                        consentRevokeRow
                    }
                } header: {
                    Text(L10n.settingsSectionAbout)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.Colors.background)
            .navigationTitle(L10n.settingsNavigationTitle)
        }
        .tint(DesignTokens.Colors.primary)
        .accessibilityIdentifier("tab.settings")
    }

    /// 组内唯一行：标题（body / primary）+ 一句说明（caption / secondary），尾部为既有播报开关。
    private var announcementRow: some View {
        Toggle(isOn: $store.isEnabled) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(L10n.settingsAnnouncementTitle)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.settingsAnnouncementBody)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .tint(DesignTokens.Colors.accent)
        .frame(minHeight: DesignTokens.minTapTarget)
        .padding(DesignTokens.Spacing.md)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(DesignTokens.Colors.background)
        .listRowInsets(
            EdgeInsets(
                top: DesignTokens.Spacing.xs,
                leading: DesignTokens.Spacing.md,
                bottom: DesignTokens.Spacing.xs,
                trailing: DesignTokens.Spacing.md
            )
        )
        .accessibilityIdentifier("settings.announcementToggle")
        .accessibilityLabel(Text(L10n.settingsAnnouncementTitle))
    }

    /// 组尾说明：只读文字，落在页面底色上（不借用系统组底），字号不低于 caption。
    private var announcementFooterRow: some View {
        Text(L10n.settingsFooterAnnouncement)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .listRowSeparator(.hidden)
            .listRowBackground(DesignTokens.Colors.background)
            .listRowInsets(
                EdgeInsets(
                    top: DesignTokens.Spacing.xs,
                    leading: DesignTokens.Spacing.md,
                    bottom: DesignTokens.Spacing.xs,
                    trailing: DesignTokens.Spacing.md
                )
            )
    }

    /// 「关于」组：应用内渲染同一政策真源全文（外链不是唯一路径）。
    private var privacyPolicyRow: some View {
        NavigationLink {
            PrivacyPolicyView(document: PrivacyPolicyDocument.load())
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(L10n.settingsPrivacyPolicyTitle)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.settingsPrivacyPolicyBody)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(DesignTokens.Colors.background)
        .listRowInsets(
            EdgeInsets(
                top: DesignTokens.Spacing.xs,
                leading: DesignTokens.Spacing.md,
                bottom: DesignTokens.Spacing.xs,
                trailing: DesignTokens.Spacing.md
            )
        )
        .accessibilityIdentifier("settings.privacyPolicy")
        .accessibilityLabel(Text(L10n.settingsPrivacyPolicyTitle))
    }

    private var consentStatusRow: some View {
        Text(L10n.settingsConsentStatus)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .listRowSeparator(.hidden)
            .listRowBackground(DesignTokens.Colors.background)
            .listRowInsets(
                EdgeInsets(
                    top: DesignTokens.Spacing.xxs,
                    leading: DesignTokens.Spacing.md,
                    bottom: DesignTokens.Spacing.xxs,
                    trailing: DesignTokens.Spacing.md
                )
            )
    }

    /// 撤回同意：回到未同意态（单键置为未同意），记录入口再次禁用。
    private var consentRevokeRow: some View {
        Button {
            consent.revoke()
        } label: {
            Text(L10n.settingsConsentRevoke)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DesignTokens.minTapTarget)
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(DesignTokens.Colors.background)
        .listRowInsets(
            EdgeInsets(
                top: DesignTokens.Spacing.xs,
                leading: DesignTokens.Spacing.md,
                bottom: DesignTokens.Spacing.xs,
                trailing: DesignTokens.Spacing.md
            )
        )
        .accessibilityIdentifier("settings.consentRevoke")
        .accessibilityLabel(Text(L10n.settingsConsentRevoke))
    }
}
