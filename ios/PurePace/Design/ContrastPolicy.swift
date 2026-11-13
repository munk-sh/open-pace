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
        // light danger 仅作确认层填充主操作与 C2 图标着色，不作正文文字：三条按非文本 UI 3.0 档判
        // （light 实测 3.6026 / 3.7626 / 3.2315；dark 同色实测 5.2034 / 4.7312 / 4.8198，均 ≥3.0）。
        Pair(name: "danger/background", foregroundKey: "danger", backgroundKey: "background", minimum: largeThreshold, tier: .large),
        Pair(name: "danger/surface", foregroundKey: "danger", backgroundKey: "surface", minimum: largeThreshold, tier: .large),
        Pair(name: "danger/dangerSoft", foregroundKey: "danger", backgroundKey: "dangerSoft", minimum: largeThreshold, tier: .large),
        // 唯一品牌橙：accent 浅/深同值 #FF6B00，onAccent 浅/深同值 #2A1206，两模式实测均 6.1932。
        Pair(name: "onAccent/accent", foregroundKey: "onAccent", backgroundKey: "accent", minimum: bodyThreshold, tier: .body),
        Pair(name: "onWarning/warning", foregroundKey: "onWarning", backgroundKey: "warning", minimum: bodyThreshold, tier: .body),
        Pair(name: "onSuccess/success", foregroundKey: "onSuccess", backgroundKey: "success", minimum: bodyThreshold, tier: .body),
        // 实心按钮文字按正文/小字 4.5 判定（与 body 档同源，不另设按钮阈值）：
        // danger 两模式同色 #F53A48，深字 onDanger #2A0608 vs danger 实测 4.9479（两侧同值）。
        // 白字 vs #F53A48 仅 3.76，不达标，不能反向放宽。
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

    /// 品牌优先豁免的登记条目；`name` 与 `checks` 产出的对照名（`"<scheme> <pair>"`）逐字一致。
    struct Exemption: Equatable, Sendable {
        let name: String
        let measured: Double
        let source: String
    }

    /// 人的拍板来源：V1.2 终版「品牌优先」——唯一品牌橙 #FF6B00 作前景压不住浅色中性底。
    static let brandPrioritySource =
        "V1.2 终版人拍板：唯一品牌橙作为前景 vs 浅色中性底，品牌优先；补偿仅限描边/字重/尺寸，禁改色相或压暗"

    /// 品牌优先豁免族（唯一豁免登记，恰 6 条）：
    /// 只登记 light 侧 `accent` 作前景的 3 个浅色中性底 × body/large 两档；dark 侧零豁免。
    /// 登记 ≠ 改公式：`problems` 仍对每条真算比值，只对登记名放行；清空本表后 6 条全部判红，
    /// 未登记的低对比对仍 fail-closed，`bodyThreshold` / `largeThreshold` / `decorativeThreshold` 与 37 对数量零改动。
    /// 实测值随 `accent #FF6B00` 与 `accentSoft #FFE3CF` 重跑更新（light accent↔accentSoft 仅 2.3304，
    /// 该值由派生口径决定，不为凑旧预期反推公式或改 hex）。
    static let brandPriorityExemptions: [Exemption] = [
        Exemption(name: "light accent/background", measured: 2.7338, source: brandPrioritySource),
        Exemption(name: "light accent/surface", measured: 2.8552, source: brandPrioritySource),
        Exemption(name: "light accent/accentSoft", measured: 2.3304, source: brandPrioritySource),
        Exemption(name: "light accent/background@large", measured: 2.7338, source: brandPrioritySource),
        Exemption(name: "light accent/surface@large", measured: 2.8552, source: brandPrioritySource),
        Exemption(name: "light accent/surfaceMuted@large", measured: 2.5488, source: brandPrioritySource)
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
    /// 低于阈值但命中 `brandPriorityExemptions` 登记名的条目单独放行（登记 ≠ 改公式，比值仍真算）。
    static func problems(
        for checks: [Check],
        exemptions: [Exemption] = brandPriorityExemptions
    ) -> [String] {
        let exempted = Set(exemptions.map(\.name))
        return checks.compactMap { check in
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
                guard !exempted.contains(check.name) else { return nil }
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
