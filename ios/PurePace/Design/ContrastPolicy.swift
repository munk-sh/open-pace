import Foundation

/// WCAG 2.x 对比度判定（Foundation-only 纯函数，不依赖 SwiftUI）。
/// 缺色对 / 空名 / 分量越界 / 低于阈值一律 fail-closed：产出一条问题，而不是默许通过。
enum ContrastPolicy {
    /// 正文与小字的最低对比度。
    static let bodyThreshold = 4.5
    /// hero 大数字（≥ 24pt 粗体或 ≥ 18.66pt 常规）的最低对比度。
    static let largeThreshold = 3.0
    /// 装饰性 hairline 的可区分下界：只保证可见，不承担信息语义。
    static let decorativeThreshold = 1.10

    /// 阈值分档标签。
    enum Tier: String, Equatable, Sendable {
        case body = "正文/小字"
        case large = "非文本 UI"
        case decorative = "装饰分隔"
    }

    /// 成对矩阵的单条声明：只引用 `DesignTokens.Colors.palette` 的键，不写十六进制。
    struct Pair: Equatable, Sendable {
        let name: String
        let foregroundKey: String
        let backgroundKey: String
        let minimum: Double
        let tier: Tier
    }

    /// 前景 / 背景成对矩阵（唯一声明点）：单测通过解析函数消费，不另行复制配对表。
    static let pairMatrix: [Pair] = [
        // 正文 / 小字 4.5 档
        Pair(name: "primary/background", foregroundKey: "primary", backgroundKey: "background", minimum: bodyThreshold, tier: .body),
        Pair(name: "primary/surface", foregroundKey: "primary", backgroundKey: "surface", minimum: bodyThreshold, tier: .body),
        Pair(name: "primary/surfaceMuted", foregroundKey: "primary", backgroundKey: "surfaceMuted", minimum: bodyThreshold, tier: .body),
        Pair(name: "primary/accentSoft", foregroundKey: "primary", backgroundKey: "accentSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "primary/warningSoft", foregroundKey: "primary", backgroundKey: "warningSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "primary/successSoft", foregroundKey: "primary", backgroundKey: "successSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "primary/dangerSoft", foregroundKey: "primary", backgroundKey: "dangerSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/background", foregroundKey: "secondary", backgroundKey: "background", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/surface", foregroundKey: "secondary", backgroundKey: "surface", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/surfaceMuted", foregroundKey: "secondary", backgroundKey: "surfaceMuted", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/accentSoft", foregroundKey: "secondary", backgroundKey: "accentSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/warningSoft", foregroundKey: "secondary", backgroundKey: "warningSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/successSoft", foregroundKey: "secondary", backgroundKey: "successSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "secondary/dangerSoft", foregroundKey: "secondary", backgroundKey: "dangerSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "accent/background", foregroundKey: "accent", backgroundKey: "background", minimum: bodyThreshold, tier: .body),
        Pair(name: "accent/surface", foregroundKey: "accent", backgroundKey: "surface", minimum: bodyThreshold, tier: .body),
        Pair(name: "accent/accentSoft", foregroundKey: "accent", backgroundKey: "accentSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "warning/background", foregroundKey: "warning", backgroundKey: "background", minimum: bodyThreshold, tier: .body),
        Pair(name: "warning/surface", foregroundKey: "warning", backgroundKey: "surface", minimum: bodyThreshold, tier: .body),
        Pair(name: "warning/warningSoft", foregroundKey: "warning", backgroundKey: "warningSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "success/background", foregroundKey: "success", backgroundKey: "background", minimum: bodyThreshold, tier: .body),
        Pair(name: "success/surface", foregroundKey: "success", backgroundKey: "surface", minimum: bodyThreshold, tier: .body),
        Pair(name: "success/successSoft", foregroundKey: "success", backgroundKey: "successSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "danger/background", foregroundKey: "danger", backgroundKey: "background", minimum: bodyThreshold, tier: .body),
        Pair(name: "danger/surface", foregroundKey: "danger", backgroundKey: "surface", minimum: bodyThreshold, tier: .body),
        Pair(name: "danger/dangerSoft", foregroundKey: "danger", backgroundKey: "dangerSoft", minimum: bodyThreshold, tier: .body),
        Pair(name: "onAccent/accent", foregroundKey: "onAccent", backgroundKey: "accent", minimum: bodyThreshold, tier: .body),
        Pair(name: "onWarning/warning", foregroundKey: "onWarning", backgroundKey: "warning", minimum: bodyThreshold, tier: .body),
        Pair(name: "onSuccess/success", foregroundKey: "onSuccess", backgroundKey: "success", minimum: bodyThreshold, tier: .body),
        Pair(name: "onDanger/danger", foregroundKey: "onDanger", backgroundKey: "danger", minimum: bodyThreshold, tier: .body),
        // 非文本 UI 边界 3.0 档
        Pair(name: "accent/background@large", foregroundKey: "accent", backgroundKey: "background", minimum: largeThreshold, tier: .large),
        Pair(name: "accent/surface@large", foregroundKey: "accent", backgroundKey: "surface", minimum: largeThreshold, tier: .large),
        Pair(name: "accent/surfaceMuted@large", foregroundKey: "accent", backgroundKey: "surfaceMuted", minimum: largeThreshold, tier: .large),
        // 装饰分隔 1.10 档
        Pair(name: "separator/background", foregroundKey: "separator", backgroundKey: "background", minimum: decorativeThreshold, tier: .decorative),
        Pair(name: "separator/surface", foregroundKey: "separator", backgroundKey: "surface", minimum: decorativeThreshold, tier: .decorative),
        Pair(name: "separator/surfaceMuted", foregroundKey: "separator", backgroundKey: "surfaceMuted", minimum: decorativeThreshold, tier: .decorative),
        // 轨迹光晕叠在卡片面上的可辨识下限（第 37 对：既有 36 对不删不改）。
        Pair(name: "accentSoft/surface", foregroundKey: "accentSoft", backgroundKey: "surface", minimum: decorativeThreshold, tier: .decorative)
    ]

    /// 判定所用的外观侧。
    enum Scheme: String, CaseIterable, Equatable, Sendable {
        case light
        case dark
    }

    /// 从 palette 键解析出指定外观侧的颜色；缺键返回 `nil`（fail-closed 的结构性来源）。
    static func component(_ key: String, scheme: Scheme) -> DesignTokens.SRGB? {
        guard let pair = DesignTokens.Colors.palette[key] else { return nil }
        return scheme == .light ? pair.light : pair.dark
    }

    /// 把整张矩阵解析成指定外观侧的 `Check`；空对照名保持为空，缺键产出 `nil` 侧。
    static func checks(for scheme: Scheme, matrix: [Pair] = pairMatrix) -> [Check] {
        matrix.map { pair in
            Check(
                name: pair.name.isEmpty ? "" : "\(scheme.rawValue) \(pair.name)",
                foreground: component(pair.foregroundKey, scheme: scheme),
                background: component(pair.backgroundKey, scheme: scheme),
                minimum: pair.minimum
            )
        }
    }

    /// 一组待判定的前景 / 背景对照。
    struct Check: Equatable {
        let name: String
        let foreground: DesignTokens.SRGB?
        let background: DesignTokens.SRGB?
        let minimum: Double

        init(
            name: String,
            foreground: DesignTokens.SRGB?,
            background: DesignTokens.SRGB?,
            minimum: Double
        ) {
            self.name = name
            self.foreground = foreground
            self.background = background
            self.minimum = minimum
        }
    }

    /// WCAG 2.x 对比度 `(L1 + 0.05) / (L2 + 0.05)`；任一侧分量非法时返回 `nil`。
    static func ratio(foreground: DesignTokens.SRGB, background: DesignTokens.SRGB) -> Double? {
        guard foreground.isInRange, background.isInRange else { return nil }
        let foregroundLuminance = foreground.relativeLuminance
        let backgroundLuminance = background.relativeLuminance
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 返回空数组表示全部达标；每一条问题都写明是缺对、越界还是低于阈值。
    static func problems(for checks: [Check]) -> [String] {
        checks.compactMap { check in
            let name = check.name.isEmpty ? "<unnamed>" : check.name
            guard !check.name.isEmpty else {
                return "缺对照名: \(name)"
            }
            guard let foreground = check.foreground, let background = check.background else {
                return "缺色对 \(name)"
            }
            guard foreground.isInRange, background.isInRange else {
                return "分量越界 \(name)"
            }
            guard let value = ratio(foreground: foreground, background: background) else {
                return "无法计算对比度 \(name)"
            }
            guard value >= check.minimum else {
                return "对比度不足 \(name): \(formatted(value)) < \(formatted(check.minimum))"
            }
            return nil
        }
    }

    /// `ac-contrast` 日志与 digest 用的逐对实测值；非法对照的比值记作 `nil`。
    static func ratios(for checks: [Check]) -> [(name: String, ratio: Double?)] {
        checks.map { check in
            let value = check.foreground.flatMap { foreground in
                check.background.flatMap { background in
                    ratio(foreground: foreground, background: background)
                }
            }
            return (check.name, value)
        }
    }

    static func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
