import XCTest
@testable import PurePace

/// ac-brand-contrast：`ContrastPolicy` 纯函数对成对 light/dark token 的 WCAG 2.x 判定。
/// 正例必须通过、低对比反例必须判红、非法分量必须 fail-closed。
final class ContrastPolicyTests: XCTestCase {
    private var palette: [String: DesignTokens.ColorPair] {
        DesignTokens.Colors.palette
    }

    /// 正文 / 小字语义对照（前景 / 背景）。
    private let bodyPairs: [(String, String)] = [
        ("primary", "background"),
        ("primary", "surface"),
        ("secondary", "background"),
        ("secondary", "surface"),
        ("accent", "background"),
        ("onAccent", "accent"),
        ("accent", "accentSoft"),
        ("warning", "warningSoft"),
        ("success", "successSoft"),
        ("danger", "dangerSoft")
    ]

    private enum Scheme: String {
        case light
        case dark
    }

    private func component(_ name: String, _ scheme: Scheme) -> DesignTokens.SRGB? {
        guard let pair = palette[name] else { return nil }
        return scheme == .light ? pair.light : pair.dark
    }

    private func checks(for scheme: Scheme, minimum: Double) -> [ContrastPolicy.Check] {
        bodyPairs.map { foreground, background in
            ContrastPolicy.Check(
                name: "\(scheme.rawValue) \(foreground)/\(background)",
                foreground: component(foreground, scheme),
                background: component(background, scheme),
                minimum: minimum
            )
        }
    }

    // MARK: - 正例

    func testEveryBodyPairMeetsThresholdInBothAppearances() {
        for scheme in [Scheme.light, Scheme.dark] {
            let checks = checks(for: scheme, minimum: ContrastPolicy.bodyThreshold)
            for entry in ContrastPolicy.ratios(for: checks) {
                print("ac-contrast \(entry.name) \(entry.ratio.map(ContrastPolicy.formatted) ?? "nil")")
            }
            XCTAssertEqual(checks.count, bodyPairs.count)
            XCTAssertEqual(ContrastPolicy.problems(for: checks), [], "\(scheme.rawValue) 存在不达标语义色对")
        }
    }

    func testHeroLargeNumberMeetsLargeThreshold() {
        for scheme in [Scheme.light, Scheme.dark] {
            let foreground = component("primary", scheme)
            let background = component("background", scheme)
            XCTAssertNotNil(foreground)
            XCTAssertNotNil(background)
            guard let foreground, let background else { return }
            let value = ContrastPolicy.ratio(foreground: foreground, background: background)
            XCTAssertNotNil(value)
            print("ac-contrast \(scheme.rawValue) hero primary/background \(value.map(ContrastPolicy.formatted) ?? "nil")")
            XCTAssertGreaterThanOrEqual(value ?? 0, ContrastPolicy.largeThreshold)
        }
        XCTAssertEqual(ContrastPolicy.bodyThreshold, 4.5)
        XCTAssertEqual(ContrastPolicy.largeThreshold, 3)
    }

    func testKnownRatiosMatchReferenceValues() {
        guard
            let lightAccent = component("accent", .light),
            let lightOnAccent = component("onAccent", .light),
            let darkAccent = component("accent", .dark),
            let darkOnAccent = component("onAccent", .dark)
        else {
            return XCTFail("调色板缺少 accent / onAccent")
        }

        let lightRatio = ContrastPolicy.ratio(foreground: lightOnAccent, background: lightAccent)
        let darkRatio = ContrastPolicy.ratio(foreground: darkOnAccent, background: darkAccent)
        XCTAssertEqual(lightRatio ?? 0, 6.07, accuracy: 0.01, "light onAccent/accent 实测值应为 6.07")
        XCTAssertEqual(darkRatio ?? 0, 9.57, accuracy: 0.01, "dark onAccent/accent 实测值应为 9.57")
    }

    // MARK: - 反例（必须判红）

    func testLowContrastPairIsRejected() {
        let check = ContrastPolicy.Check(
            name: "low #AAAAAA on #FFFFFF",
            foreground: DesignTokens.SRGB(hex: 0xAAAAAA),
            background: DesignTokens.SRGB(hex: 0xFFFFFF),
            minimum: ContrastPolicy.bodyThreshold
        )
        let value = ContrastPolicy.ratio(
            foreground: DesignTokens.SRGB(hex: 0xAAAAAA),
            background: DesignTokens.SRGB(hex: 0xFFFFFF)
        )
        print("ac-contrast 反例 low #AAAAAA/#FFFFFF \(value.map(ContrastPolicy.formatted) ?? "nil")")
        XCTAssertEqual(value ?? 0, 2.32, accuracy: 0.01)
        let problems = ContrastPolicy.problems(for: [check])
        XCTAssertFalse(problems.isEmpty, "低对比反例必须判红")
        XCTAssertTrue(problems.first?.contains("对比度不足") == true, "反例问题必须写明对比度不足，实际 \(problems)")
    }

    func testOutOfRangeComponentsFailClosed() {
        let invalid = DesignTokens.SRGB(red: 1.4, green: -0.2, blue: 0.5)
        XCTAssertFalse(invalid.isInRange)
        XCTAssertNil(
            ContrastPolicy.ratio(foreground: invalid, background: DesignTokens.SRGB(hex: 0xFFFFFF)),
            "越界分量不得算出对比度"
        )
        let check = ContrastPolicy.Check(
            name: "越界反例",
            foreground: invalid,
            background: DesignTokens.SRGB(hex: 0xFFFFFF),
            minimum: ContrastPolicy.bodyThreshold
        )
        let problems = ContrastPolicy.problems(for: [check])
        XCTAssertFalse(problems.isEmpty, "越界分量必须判红")
        XCTAssertTrue(problems.first?.contains("分量越界") == true, "越界问题必须写明原因，实际 \(problems)")
    }

    func testMissingPairFailsClosed() {
        let missing = ContrastPolicy.Check(
            name: "缺色对",
            foreground: nil,
            background: DesignTokens.SRGB(hex: 0xFFFFFF),
            minimum: ContrastPolicy.bodyThreshold
        )
        let problems = ContrastPolicy.problems(for: [missing])
        XCTAssertFalse(problems.isEmpty, "缺色对必须判红")
        XCTAssertTrue(problems.first?.contains("缺色对") == true, "缺对问题必须写明原因，实际 \(problems)")
    }

    func testEmptyNameFailsClosed() {
        let unnamed = ContrastPolicy.Check(
            name: "",
            foreground: DesignTokens.SRGB(hex: 0x000000),
            background: DesignTokens.SRGB(hex: 0xFFFFFF),
            minimum: ContrastPolicy.bodyThreshold
        )
        let problems = ContrastPolicy.problems(for: [unnamed])
        XCTAssertFalse(problems.isEmpty, "空对照名必须判红")
        XCTAssertTrue(problems.first?.contains("缺对照名") == true, "空名问题必须写明原因，实际 \(problems)")
    }
}
