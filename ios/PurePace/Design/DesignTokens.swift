import SwiftUI

/// 全仓唯一设计 token 真源：颜色 / 字号 / 字重 / 间距 / 圆角 / 图标尺寸 / 最小触控尺寸。
/// 视图只引用本文件，不写样式字面量；语义色一律 light/dark 成对定义，深色模式真实可用。
enum DesignTokens {
    // MARK: - 颜色

    /// sRGB 0...1 三分量：token 的唯一颜色数值表达，也是 WCAG 对比度判定的输入。
    struct SRGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// `0xRRGGBB` 十六进制（token 真源里仅此一处允许出现颜色字面量）。
        init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }

        /// 三分量都必须是有限的 0...1 数值；越界或 NaN 一律视为非法（对比度判定 fail-closed）。
        var isInRange: Bool {
            [red, green, blue].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
        }

        /// WCAG 2.x 相对亮度。
        var relativeLuminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// 语义色的 light/dark 成对定义；缺任一侧不构成合法 token。
    struct ColorPair: Equatable, Sendable {
        let light: SRGB
        let dark: SRGB
    }

    enum Colors {
        /// 全部语义色（唯一调色板真源）；键名与下方 `static let` 一一对应。
        static let palette: [String: ColorPair] = [
            "background": ColorPair(light: SRGB(hex: 0xF7F8F6), dark: SRGB(hex: 0x0A1211)),
            "surface": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x141F1D)),
            "surfaceMuted": ColorPair(light: SRGB(hex: 0xF0F3F1), dark: SRGB(hex: 0x1A2724)),
            "primary": ColorPair(light: SRGB(hex: 0x12201E), dark: SRGB(hex: 0xECF4F1)),
            "secondary": ColorPair(light: SRGB(hex: 0x566663), dark: SRGB(hex: 0xA6B8B3)),
            "accent": ColorPair(light: SRGB(hex: 0x0B6F60), dark: SRGB(hex: 0x5ED6C4)),
            "onAccent": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x06211C)),
            "accentSoft": ColorPair(light: SRGB(hex: 0xEDF6F3), dark: SRGB(hex: 0x123B34)),
            "separator": ColorPair(light: SRGB(hex: 0xDCE5E1), dark: SRGB(hex: 0x25332F)),
            "warning": ColorPair(light: SRGB(hex: 0x9A5B00), dark: SRGB(hex: 0xF5B84C)),
            "onWarning": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x2B1A00)),
            "warningSoft": ColorPair(light: SRGB(hex: 0xFDF3E1), dark: SRGB(hex: 0x3A2A0D)),
            "success": ColorPair(light: SRGB(hex: 0x147A4E), dark: SRGB(hex: 0x5BD69B)),
            "onSuccess": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x042416)),
            "successSoft": ColorPair(light: SRGB(hex: 0xE8F6EF), dark: SRGB(hex: 0x11311F)),
            "danger": ColorPair(light: SRGB(hex: 0xB3261E), dark: SRGB(hex: 0xFF8A80)),
            "onDanger": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x3A0906)),
            "dangerSoft": ColorPair(light: SRGB(hex: 0xFCEBE9), dark: SRGB(hex: 0x3A1A17))
        ]

        /// 页面底色。
        static let background = color("background")
        /// 卡片面 / 底部控制区。
        static let surface = color("surface")
        /// 次级面板与提示弱底。
        static let surfaceMuted = color("surfaceMuted")
        /// 正文 / hero 数字。
        static let primary = color("primary")
        /// 次文 / 字段标签 / 说明。
        static let secondary = color("secondary")
        /// 唯一品牌主色：记录态、主操作、强调共用。
        static let accent = color("accent")
        /// 主色底上的文字。
        static let onAccent = color("onAccent")
        /// 记录态弱底。
        static let accentSoft = color("accentSoft")
        /// 卡片描边 / 分隔线。
        static let separator = color("separator")
        /// 暂停 / 结束 / 降级提示。
        static let warning = color("warning")
        /// 警示底上的文字。
        static let onWarning = color("onWarning")
        /// 警示弱底。
        static let warningSoft = color("warningSoft")
        /// 已保存。
        static let success = color("success")
        /// 成功底上的文字。
        static let onSuccess = color("onSuccess")
        /// 成功弱底。
        static let successSoft = color("successSoft")
        /// 失败态。
        static let danger = color("danger")
        /// 危险底上的文字。
        static let onDanger = color("onDanger")
        /// 危险弱底。
        static let dangerSoft = color("dangerSoft")

        /// 按 light/dark 解析成随系统外观切换的动态颜色。
        private static func color(_ name: String) -> Color {
            let pair = palette[name] ?? ColorPair(
                light: SRGB(hex: 0x000000),
                dark: SRGB(hex: 0xFFFFFF)
            )
            return Color(uiColor: UIColor { traits in
                let value = traits.userInterfaceStyle == .dark ? pair.dark : pair.light
                return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
            })
        }
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

    // MARK: - 描边

    enum Stroke {
        /// 分隔线 / 描边宽度。
        static let hairline: CGFloat = 1
    }

    // MARK: - 图标尺寸

    enum Icon {
        static let inline: CGFloat = 16
        static let row: CGFloat = 20
        static let control: CGFloat = 24

        static let scale: [CGFloat] = [inline, row, control]
    }

    // MARK: - 外观

    /// 语义色已带 dark 值，深色模式真实可用；视图仍只引用 `DesignTokens.Colors`。
    enum Appearance {
        static let supportsDarkMode = true
    }

    // MARK: - 触控

    /// Apple HIG 最小可点击高度；所有交互控件不得低于此值。
    static let minTapTarget: CGFloat = 44
}
