import Foundation

/// WCAG 2.x 对比度判定（Foundation-only 纯函数，不依赖 SwiftUI）。
/// 缺色对 / 空名 / 分量越界 / 低于阈值一律 fail-closed：产出一条问题，而不是默许通过。
enum ContrastPolicy {
    /// 正文与小字的最低对比度。
    static let bodyThreshold = 4.5
    /// hero 大数字（≥ 24pt 粗体或 ≥ 18.66pt 常规）的最低对比度。
    static let largeThreshold = 3.0

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
