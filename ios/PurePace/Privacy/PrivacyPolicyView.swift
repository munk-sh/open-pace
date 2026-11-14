import SwiftUI

/// 应用内政策全文：按二级标题渲染真源章节块（surface 行容器 + hairline），
/// 正文来自 bundle 内真源副本，Swift 侧不重复写正文。
struct PrivacyPolicyView: View {
    let document: PrivacyPolicyDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                if let document, !document.sections.isEmpty {
                    ForEach(document.sections) { section in
                        sectionBlock(section)
                    }
                } else {
                    Text(L10n.privacyPolicyUnavailable)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(DesignTokens.Colors.background)
        .navigationTitle(L10n.privacyPolicyNavigationTitle)
        .accessibilityIdentifier("settings.privacyPolicyBody")
        .accessibilityLabel(Text(L10n.privacyPolicyNavigationTitle))
    }

    private func sectionBlock(_ section: PrivacyPolicyDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(section.title)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(section.body)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView(document: PrivacyPolicyDocument(markdown: "# 标题\n\n## 采集项\n\n正文"))
    }
}
