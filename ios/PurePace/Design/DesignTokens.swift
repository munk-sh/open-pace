import SwiftUI

/// 全仓唯一设计 token 真源：颜色 / 字号 / 字重 / 间距 / 圆角 / 图标尺寸 / 最小触控尺寸。
/// 视图只引用本文件，不写样式字面量；颜色一律取系统语义色，深色模式无需另开分支。
enum DesignTokens {
    // MARK: - 颜色

    enum Colors {
        /// 主信息前景色。
        static let primary = Color.primary
        /// 次信息前景色（平均配速、列表第二行、说明文案）。
        static let secondary = Color.secondary
        /// 主操作强调色。
        static let accent = Color.accentColor
        /// 结束类操作的警示色。
        static let warning = Color.orange
        /// 失败态前景色。
        static let danger = Color.red
        /// 成功态前景色（已保存）。
        static let success = Color.green
        /// 分组容器的表面色。
        static let surface = Color(.secondarySystemGroupedBackground)
    }

    // MARK: - 字号

    enum Typography {
        static let captionSize: CGFloat = 12
        static let bodySize: CGFloat = 15
        static let titleSize: CGFloat = 20
        static let primaryValueSize: CGFloat = 34
        static let displaySize: CGFloat = 56

        /// 由小到大的字号阶梯，供不变量断言使用。
        static let sizes: [CGFloat] = [captionSize, bodySize, titleSize, primaryValueSize, displaySize]

        static let caption = Font.system(size: captionSize, weight: .regular)
        static let body = Font.system(size: bodySize, weight: .regular)
        static let title = Font.system(size: titleSize, weight: .semibold)
        static let primaryValue = Font.system(size: primaryValueSize, weight: .semibold, design: .rounded)
        static let display = Font.system(size: displaySize, weight: .bold, design: .rounded)

        /// 控件内文字（按钮/开关）。
        static let control = Font.system(size: titleSize, weight: .semibold)
        /// 分组标题。
        static let sectionHeader = Font.system(size: bodySize, weight: .semibold)

        static let weights: [Font.Weight] = [.regular, .semibold, .bold]
    }

    // MARK: - 间距

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32

        /// 由小到大的间距档，供单调递增断言使用。
        static let scale: [CGFloat] = [xxs, xs, sm, md, lg, xl]
    }

    // MARK: - 圆角

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 16
        static let panel: CGFloat = 20

        static let scale: [CGFloat] = [control, card, panel]
    }

    // MARK: - 图标尺寸

    enum Icon {
        static let inline: CGFloat = 16
        static let row: CGFloat = 20
        static let control: CGFloat = 24

        static let scale: [CGFloat] = [inline, row, control]
    }

    // MARK: - 外观（深色模式留位）

    /// 本期只做浅色层级收敛，颜色全部取系统语义色；后续接深色模式时在此扩展，
    /// 视图仍只引用 `DesignTokens.Colors`，无需改动。
    enum Appearance {
        static let supportsDarkMode = false
    }

    // MARK: - 触控

    /// Apple HIG 最小可点击高度；所有交互控件不得低于此值。
    static let minTapTarget: CGFloat = 44
}
