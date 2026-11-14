import SwiftUI

/// 首次启动的独立同意屏：标题 + 一段说明 + accent 填充主操作「同意并继续」+ 文字次操作「不同意」。
/// 不与记录页同屏堆叠（由根视图以全屏覆盖呈现），全部样式取 `DesignTokens`。
struct PrivacyConsentGateView: View {
    var onAgree: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Spacer(minLength: DesignTokens.Spacing.xl)

            Text(L10n.consentGateTitle)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.consentGate")
                .accessibilityLabel(Text(L10n.consentGateTitle))

            Text(L10n.consentGateBody)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DesignTokens.Spacing.lg)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Button(action: onAgree) {
                    Text(L10n.consentGateAgree)
                        .font(DesignTokens.Typography.control)
                        .foregroundStyle(DesignTokens.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DesignTokens.minTapTarget)
                }
                .background(
                    DesignTokens.Colors.accent,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                )
                .accessibilityIdentifier("settings.consentAgree")
                .accessibilityLabel(Text(L10n.consentGateAgree))

                Button(action: onDecline) {
                    Text(L10n.consentGateDecline)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DesignTokens.minTapTarget)
                }
                .accessibilityIdentifier("settings.consentDecline")
                .accessibilityLabel(Text(L10n.consentGateDecline))
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.background)
    }
}

#Preview {
    PrivacyConsentGateView(onAgree: {}, onDecline: {})
}
