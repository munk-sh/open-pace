import Foundation
import SwiftUI

/// 全仓唯一设计 token 真源：颜色 / 字号 / 字重 / 间距 / 圆角 / 图标尺寸 / 动效 / 最小触控尺寸。
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
            "background": ColorPair(light: SRGB(hex: 0xFAFAF9), dark: SRGB(hex: 0x0B0C0D)),
            "surface": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x16181A)),
            "surfaceMuted": ColorPair(light: SRGB(hex: 0xF2F2F1), dark: SRGB(hex: 0x1E2124)),
            "primary": ColorPair(light: SRGB(hex: 0x17181A), dark: SRGB(hex: 0xF2F3F4)),
            "secondary": ColorPair(light: SRGB(hex: 0x5C5F63), dark: SRGB(hex: 0xA2A7AC)),
            "accent": ColorPair(light: SRGB(hex: 0xB4400B), dark: SRGB(hex: 0xFF9A5C)),
            "onAccent": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x2A1206)),
            "accentSoft": ColorPair(light: SRGB(hex: 0xFCEFE7), dark: SRGB(hex: 0x3A1F12)),
            "separator": ColorPair(light: SRGB(hex: 0xD8D8D3), dark: SRGB(hex: 0x33383D)),
            "warning": ColorPair(light: SRGB(hex: 0x6E5C00), dark: SRGB(hex: 0xEECA2B)),
            "onWarning": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x2B1A00)),
            "warningSoft": ColorPair(light: SRGB(hex: 0xFBF1DC), dark: SRGB(hex: 0x3A2A0D)),
            "success": ColorPair(light: SRGB(hex: 0x1F6B45), dark: SRGB(hex: 0x58CF9B)),
            "onSuccess": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x042416)),
            "successSoft": ColorPair(light: SRGB(hex: 0xE7F2EB), dark: SRGB(hex: 0x11311F)),
            "danger": ColorPair(light: SRGB(hex: 0x660D09), dark: SRGB(hex: 0xF53A48)),
            "onDanger": ColorPair(light: SRGB(hex: 0xFFFFFF), dark: SRGB(hex: 0x2A0608)),
            "dangerSoft": ColorPair(light: SRGB(hex: 0xFBEAE8), dark: SRGB(hex: 0x2C0A10))
        ]

        // 色板唯一真源：公司调研 digest trun_cff114e082a2fb0e §3「方向 A / 石墨+竞速橙」。
        // 36 hex 逐键照抄，禁止截图取色或自行微调；warning/danger 系按公司裁决 owe_40221a8e983c7516 重取，
        // 使 accent↔warning、accent↔danger 在 HSL 口径下至少满足 ΔH≥25° / ΔL≥15 / ΔS≥30 其一。
        // 深色三中性键（#0B0C0D / #16181A / #1E2124）实测 HSL 色相 210°、chroma/255 = 0.78% / 1.57% / 2.35%，
        // 判据取「色相落在 60–200° 之外」且「chroma/255 ≤ 3.0%」（旧值 166–172°、3.14/4.31/5.10% 必然判红）。
        // HSV S 在深色 V≈5% 时分母极小（实测 8.3–9.1%），不构成本轮判据。

        /// 18 个语义键的机器可读用途；键集必须与 `palette` 完全相等，且用途不得为空或复读键名。
        static let purposes: [String: String] = [
            "background": "页面底色，承载全部内容的最底层",
            "surface": "卡片面与底部控制区",
            "surfaceMuted": "次级面板与提示弱底",
            "primary": "正文与 hero 数字",
            "secondary": "次文、字段标签与说明",
            "accent": "唯一品牌主色：记录态主操作（开始/暂停/继续/结束/保存）与选中态",
            "onAccent": "主色底上的文字",
            "accentSoft": "记录态弱底",
            "separator": "卡片描边与分隔线，仅装饰，不作为唯一信息载体",
            "warning": "非阻断内联提示（权限缺失 / GPS 弱 / 保存失败横幅），不作填充主按钮",
            "onWarning": "警示底上的文字",
            "warningSoft": "警示弱底（内联提示背景）",
            "success": "已保存成功态",
            "onSuccess": "成功底上的文字",
            "successSoft": "成功弱底",
            "danger": "丢弃等破坏性操作，仅出现在确认层文本或描边按钮",
            "onDanger": "危险底上的文字",
            "dangerSoft": "危险弱底（确认层背景）"
        ]

        /// 用途注册表的 fail-closed 校验：缺键 / 多键 / 空用途 / 复读键名都产出可读问题。
        static func purposeProblems(
            paletteEntries: [String: ColorPair] = palette,
            registry: [String: String] = purposes
        ) -> [String] {
            var problems: [String] = []
            let paletteKeys = Set(paletteEntries.keys)
            let registryKeys = Set(registry.keys)
            for key in paletteKeys.subtracting(registryKeys).sorted() {
                problems.append("缺用途 \(key)")
            }
            for key in registryKeys.subtracting(paletteKeys).sorted() {
                problems.append("多余用途 \(key)")
            }
            for key in paletteKeys.intersection(registryKeys).sorted() {
                let trimmed = (registry[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    problems.append("空用途 \(key)")
                } else if trimmed == key {
                    problems.append("复读键名 \(key)")
                }
            }
            return problems
        }

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
        /// 指标三行结构的小标签（上置，配合 `secondary` 色）。
        static let metricLabelSize: CGFloat = 11
        /// 指标三行结构的单位（下置，与标签同档）。
        static let metricUnitSize: CGFloat = 11
        static let captionSize: CGFloat = 13
        static let bodySize: CGFloat = 15
        static let titleSize: CGFloat = 20
        static let primaryValueSize: CGFloat = 36
        static let displaySize: CGFloat = 64

        /// 由小到大的字号阶梯，供不变量断言使用；label/unit 共享 11 这一档。
        static let sizes: [CGFloat] = [
            metricLabelSize, captionSize, bodySize, titleSize, primaryValueSize, displaySize
        ]

        /// 语义角色阶梯：按字号非递减排列，label/unit 允许同字号一次。
        struct Role: Equatable, Sendable {
            let name: String
            let size: CGFloat
            let needsMonospacedDigits: Bool
        }

        /// 需要等宽数字的角色；仅 `primaryValue` / `display` 两个数值角色。
        static let numericRoleNames: [String] = ["primaryValue", "display"]

        static let roleLadder: [Role] = [
            Role(name: "metricLabel", size: metricLabelSize, needsMonospacedDigits: false),
            Role(name: "metricUnit", size: metricUnitSize, needsMonospacedDigits: false),
            Role(name: "caption", size: captionSize, needsMonospacedDigits: false),
            Role(name: "body", size: bodySize, needsMonospacedDigits: false),
            Role(name: "title", size: titleSize, needsMonospacedDigits: false),
            Role(name: "primaryValue", size: primaryValueSize, needsMonospacedDigits: true),
            Role(name: "display", size: displaySize, needsMonospacedDigits: true)
        ]

        /// 角色阶梯的 fail-closed 校验：乱序、非法同字号、数值角色集合漂移都产出问题。
        static func roleProblems(_ ladder: [Role] = roleLadder) -> [String] {
            var problems: [String] = []
            for index in 1..<ladder.count where ladder[index].size < ladder[index - 1].size {
                problems.append("角色阶梯必须按字号非递减: \(ladder[index].name)")
            }

            let allowedDuplicates: Set<String> = ["metricLabel", "metricUnit"]
            let grouped = Dictionary(grouping: ladder, by: \.size)
            for size in grouped.keys.sorted() where (grouped[size]?.count ?? 0) > 1 {
                let names = Set(grouped[size]?.map(\.name) ?? [])
                if names != allowedDuplicates {
                    problems.append("仅 metricLabel/metricUnit 允许同字号: \(size)")
                }
            }

            let marked = Set(ladder.filter(\.needsMonospacedDigits).map(\.name))
            if marked != Set(numericRoleNames) {
                problems.append("数值角色标记必须与 numericRoleNames 一致")
            }
            if marked != Set(["primaryValue", "display"]) {
                problems.append("数值角色必须恰为 primaryValue / display")
            }
            return problems
        }

        static let metricLabel = Font.system(size: metricLabelSize, weight: .semibold)
        static let metricUnit = Font.system(size: metricUnitSize, weight: .regular)
        static let caption = Font.system(size: captionSize, weight: .regular)
        static let body = Font.system(size: bodySize, weight: .regular)
        static let title = Font.system(size: titleSize, weight: .semibold)
        static let primaryValue = Font.system(size: primaryValueSize, weight: .semibold, design: .monospaced)
        static let display = Font.system(size: displaySize, weight: .bold, design: .monospaced)

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

        // MARK: 语义间距（首屏四层垂直分布）

        /// 首屏内容区距导航栏下沿的最小呼吸位（= lg 24）。
        static let screenTop: CGFloat = lg
        /// hero 面板与次级指标卡片的层间距，同时用作内容区左右内边距（= md 16）。
        static let cardGap: CGFloat = md
        /// 指标卡片 / 提示片 / 底部主操作之间的层间距（= sm 12）。
        static let sectionGap: CGFloat = sm
        /// 指标三行（标签 / 数值 / 单位）组内间距（= xs 8）。
        static let metricGroupSpacing: CGFloat = xs
        /// 相邻指标组之间的间距（= md 16）。
        static let metricGroupGap: CGFloat = md
        /// 卡片内容内边距（= md 16）。
        static let cardPadding: CGFloat = md

        /// 由小到大的间距档，供单调递增断言使用。
        static let scale: [CGFloat] = [xxs, xs, sm, md, lg, xl]
    }

    // MARK: - 圆角

    enum Radius {
        static let control: CGFloat = 10
        static let card: CGFloat = 14
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

    // MARK: - 动效

    /// 动效时长的唯一常量来源（单位：秒）；视图接线留给后续波次。
    enum Motion {
        /// 数值 / 色块原地过渡（200ms）。
        static let durationShort: TimeInterval = 0.2
        /// 记录态切换（320ms）。
        static let durationState: TimeInterval = 0.32
        /// Reduce Motion 打开时的时长：无动画。
        static let reducedMotionDuration: TimeInterval = 0

        /// 纯函数降级解析：`reduceMotion == true` 一律返回 0，否则返回原时长。
        static func duration(_ duration: TimeInterval, reduceMotion: Bool) -> TimeInterval {
            reduceMotion ? reducedMotionDuration : duration
        }
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
