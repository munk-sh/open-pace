#if DEBUG
import SwiftUI

/// C 组：丢弃确认弹窗两版（C1 说明式纵向主次 / C2 图标式行内主次），浅深各一张。
///
/// 两版都满足：主次分明（唯一实心 danger 破坏性动作 + 无填充次操作）、
/// 破坏性动作形态明确（实心 danger `#660D09` 底 + `onDanger` 白字）、
/// sheet 高度由内容决定（无固定 medium 档、无大段留白）、
/// 弹窗内不出现 accent 填充按钮与 danger 填充按钮同形状并列。
struct DesignDraftDiscardScreen: View {
    enum Style {
        case stacked
        case inlineIcon
    }

    let style: Style
    let variant: DesignDraftV12.Variant

    var body: some View {
        ZStack(alignment: .bottom) {
            DesignDraftFinishedScreen(layout: .collapsibleSummary, expanded: false, variant: variant)
            Color.black.opacity(0.32)
                .ignoresSafeArea()
            sheet
        }
    }

    // MARK: Sheet

    /// 自适应内容高度的底部 sheet：没有任何固定档高，高度 = 内容高度 + 内边距。
    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(DesignTokens.Colors.separator)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, DesignTokens.Spacing.xxs)
            sheetBody
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DesignTokens.Radius.panel,
                topTrailingRadius: DesignTokens.Radius.panel
            )
            .fill(DesignTokens.Colors.surface)
            .ignoresSafeArea(edges: .bottom)
        }
        .designDraftProbe("sheet.panel", variant: variant.rawValue)
    }

    @ViewBuilder
    private var sheetBody: some View {
        switch style {
        case .stacked:
            stackedBody
        case .inlineIcon:
            inlineIconBody
        }
    }

    /// C1：标题 + 说明 + 唯一实心 danger 主操作 + 无边框次操作（纵向，主在上、次在下）。
    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(L10n.runDiscardConfirmTitle)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.primary)
                    .designDraftProbe("sheet.title", variant: variant.rawValue)
                Text(L10n.runDiscardConfirmMessage)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            designDraftPrimaryDanger
            Text(L10n.runDiscardConfirmCancel)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
    }

    /// C2：图标 + 标题/说明行内排布 + 底部「实心 danger 主操作 + 无填充次操作」同行主次。
    private var inlineIconBody: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.danger)
                    .frame(width: 40, height: 40)
                    .background(
                        DesignTokens.Colors.dangerSoft,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    )
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.runDiscardConfirmTitle)
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.primary)
                        .designDraftProbe("sheet.title", variant: variant.rawValue)
                    Text(L10n.runDiscardConfirmMessage)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                DesignDraftPrimaryButton(
                    title: L10n.runDiscardConfirmConfirm,
                    fill: DesignTokens.Colors.danger,
                    foreground: DesignTokens.Colors.onDanger
                )
                Text(L10n.runActionCancel)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .frame(minHeight: DesignTokens.minTapTarget)
            }
        }
    }

    /// 唯一实心破坏性动作：danger 底 + onDanger 文字，全宽、`minTapTarget` 高。
    private var designDraftPrimaryDanger: some View {
        DesignDraftPrimaryButton(
            title: L10n.runDiscardConfirmConfirm,
            fill: DesignTokens.Colors.danger,
            foreground: DesignTokens.Colors.onDanger
        )
        .designDraftProbe("sheet.primary", variant: variant.rawValue)
    }
}
#endif
