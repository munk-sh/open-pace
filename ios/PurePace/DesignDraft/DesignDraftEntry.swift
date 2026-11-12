#if DEBUG
import SwiftUI

/// V1.2 设计稿入口（仅 DEBUG + 显式启动参数 `-designDraftV12 <变体号>`）。
///
/// 存在的唯一理由：本轮只出静态稿，不改任何生产视图 / token；Release 编译期即不存在该分支，
/// 出厂 App 无任何可达路径。变体号与 `docs/design-draft-v12/manifest.md` 一一对应。
enum DesignDraftV12 {
    static let flag = "-designDraftV12"

    enum Variant: String, CaseIterable {
        case a1RunNotStarted = "a1-run-not-started"
        case a1RunRunning = "a1-run-running"
        case a1RunFinished = "a1-run-finished"
        case a1HistoryList = "a1-history-list"
        case a1HistoryDetail = "a1-history-detail"
        case a1Settings = "a1-settings"
        case a2RunNotStarted = "a2-run-not-started"
        case a2RunRunning = "a2-run-running"
        case a2RunFinished = "a2-run-finished"
        case a2HistoryList = "a2-history-list"
        case a2HistoryDetail = "a2-history-detail"
        case a2Settings = "a2-settings"
        case b1Finished = "b1-finished"
        case b2Finished = "b2-finished"
        case b2FinishedExpanded = "b2-finished-expanded"
        case c1Discard = "c1-discard"
        case c2Discard = "c2-discard"
    }

    static func requested(arguments: [String] = CommandLine.arguments) -> Variant? {
        guard let raw = RunLaunchArguments.value(after: flag, arguments: arguments) else {
            return nil
        }
        return Variant(rawValue: raw)
    }
}

struct DesignDraftRootView: View {
    let variant: DesignDraftV12.Variant

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Colors.background)
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        DesignDraftReporter.reportScreen(
                            variant.rawValue,
                            scale: displayScale,
                            size: proxy.size
                        )
                        DesignDraftReporter.markReady(variant.rawValue)
                    }
                }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .a1RunNotStarted: DesignDraftRunScreen(palette: .a1, state: .notStarted, variant: variant)
        case .a1RunRunning: DesignDraftRunScreen(palette: .a1, state: .running, variant: variant)
        case .a1RunFinished: DesignDraftRunScreen(palette: .a1, state: .finished, variant: variant)
        case .a1HistoryList: DesignDraftHistoryListScreen(palette: .a1, variant: variant)
        case .a1HistoryDetail: DesignDraftHistoryDetailScreen(palette: .a1, variant: variant)
        case .a1Settings: DesignDraftSettingsScreen(palette: .a1, variant: variant)
        case .a2RunNotStarted: DesignDraftRunScreen(palette: .a2, state: .notStarted, variant: variant)
        case .a2RunRunning: DesignDraftRunScreen(palette: .a2, state: .running, variant: variant)
        case .a2RunFinished: DesignDraftRunScreen(palette: .a2, state: .finished, variant: variant)
        case .a2HistoryList: DesignDraftHistoryListScreen(palette: .a2, variant: variant)
        case .a2HistoryDetail: DesignDraftHistoryDetailScreen(palette: .a2, variant: variant)
        case .a2Settings: DesignDraftSettingsScreen(palette: .a2, variant: variant)
        case .b1Finished: DesignDraftFinishedScreen(layout: .mapHero, expanded: false, variant: variant)
        case .b2Finished: DesignDraftFinishedScreen(layout: .collapsibleSummary, expanded: false, variant: variant)
        case .b2FinishedExpanded:
            DesignDraftFinishedScreen(layout: .collapsibleSummary, expanded: true, variant: variant)
        case .c1Discard: DesignDraftDiscardScreen(style: .stacked, variant: variant)
        case .c2Discard: DesignDraftDiscardScreen(style: .inlineIcon, variant: variant)
        }
    }
}

// MARK: - 设计稿共用原子件

/// 卡片面：`surface` 底 + `Radius.card` 圆角 + `separator` 描边，与生产三屏同一口径。
struct DesignDraftCard<Content: View>: View {
    var fill: Color = DesignTokens.Colors.surface
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DesignTokens.Spacing.cardPadding)
            .frame(maxWidth: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
            }
    }
}

/// 唯一填充主操作：`minTapTarget` 高、`Radius.control` 圆角、accent/onAccent 或 success 着色。
struct DesignDraftPrimaryButton: View {
    let title: LocalizedStringKey
    let fill: Color
    let foreground: Color
    var expanded = true

    var body: some View {
        Text(title)
            .font(DesignTokens.Typography.control)
            .foregroundStyle(foreground)
            .frame(maxWidth: expanded ? .infinity : nil)
            .padding(.horizontal, expanded ? 0 : DesignTokens.Spacing.lg)
            .frame(minHeight: DesignTokens.minTapTarget)
            .background(fill, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
    }
}

/// 次操作：无填充描边（不与唯一填充主操作等权并排）。
struct DesignDraftOutlineButton: View {
    let title: LocalizedStringKey
    let tint: Color
    var lineWidth: CGFloat = DesignTokens.Stroke.hairline

    var body: some View {
        Text(title)
            .font(DesignTokens.Typography.body)
            .foregroundStyle(tint)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.minTapTarget)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .strokeBorder(tint, lineWidth: lineWidth)
            }
    }
}

/// 底部主操作条：`surface` 底 + 顶部 hairline，锚定在安全区上方（生产同一锚点口径）。
struct DesignDraftActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) { content }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sectionGap)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.Colors.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Colors.separator)
                    .frame(height: DesignTokens.Stroke.hairline)
            }
    }
}

/// A 组统一外壳：真实 TabView（真实 tab bar 与 tint），只换 accent/onAccent。
struct DesignDraftTabShell<Content: View>: View {
    let palette: DesignDraftPalette
    let selected: Int
    @ViewBuilder let content: Content

    var body: some View {
        TabView(selection: .constant(selected)) {
            tabContent(0)
                .tabItem { Label(L10n.tabRun, systemImage: "figure.run") }
                .tag(0)
            tabContent(1)
                .tabItem { Label(L10n.tabHistory, systemImage: "clock.arrow.circlepath") }
                .tag(1)
            tabContent(2)
                .tabItem { Label(L10n.tabSettings, systemImage: "gearshape") }
                .tag(2)
        }
        .tint(palette.accent)
    }

    /// 只有当前选中的 tab 承载设计稿内容；其余 tab 用占位，避免内容落在未选中的页上。
    @ViewBuilder
    private func tabContent(_ index: Int) -> some View {
        if index == selected {
            content
        } else {
            Color.clear
        }
    }
}

/// 指标三行结构（标签 / 数值 / 单位），与生产 hero/指标卡同构。
struct DesignDraftMetric: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String?
    let valueFont: Font
    let valueColor: Color
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: DesignTokens.Spacing.metricGroupSpacing) {
            Text(label)
                .font(DesignTokens.Typography.metricLabel)
                .foregroundStyle(DesignTokens.Colors.secondary)
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(DesignTokens.Typography.metricUnit)
                    .foregroundStyle(DesignTokens.Colors.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 后台定位提示：B/C 组收成 inline 小胶囊（不再整行占高）；A 组保持现网整行文本。
struct DesignDraftInlinePermissionHint: View {
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: "location.slash")
                .font(DesignTokens.Typography.caption)
            Text(verbatim: "后台定位未开启 · 前往设置")
                .font(DesignTokens.Typography.caption)
        }
        .foregroundStyle(DesignTokens.Colors.warning)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.warningSoft, in: Capsule())
    }
}

/// 分段明细行：序号 / 距离 / 配速。
struct DesignDraftSplitRow: View {
    let index: Int
    let distance: String
    let pace: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(verbatim: "\(index)")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .frame(width: 24, alignment: .leading)
            Text(verbatim: distance)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
            Spacer(minLength: DesignTokens.Spacing.sm)
            Text(verbatim: pace)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .monospacedDigit()
        }
        .frame(minHeight: DesignTokens.Spacing.lg)
    }
}
#endif
