import XCTest
@testable import PurePace

/// `ContrastPolicy` 纯函数对成对 light/dark token 的 WCAG 2.x 判定。
/// 正例必须通过、低对比反例必须判红、非法输入必须 fail-closed。
final class ContrastPolicyTests: XCTestCase {
    private var palette: [String: DesignTokens.ColorPair] {
        DesignTokens.Colors.palette
    }

    // MARK: - ac-contrast-matrix-exhaustive

    func testMatrixIsSingleSourceAndExhaustive() {
        let matrix = ContrastPolicy.pairMatrix
        XCTAssertEqual(matrix.count, 37, "成对矩阵恰为 37 对（既有 36 + 轨迹光晕 1）")
        XCTAssertEqual(matrix.count, Set(matrix.map(\.name)).count, "矩阵条目名必须唯一")
        XCTAssertEqual(
            matrix.filter { $0.tier == .decorative }.contains { $0.name == "accentSoft/surface" },
            true,
            "新增的第 37 对必须是装饰档 accentSoft/surface 光晕可辨识对"
        )

        for pair in matrix {
            XCTAssertFalse(pair.name.isEmpty, "矩阵条目必须有可读对照名")
            XCTAssertNotNil(palette[pair.foregroundKey], "矩阵引用了不存在的键 \(pair.foregroundKey)")
            XCTAssertNotNil(palette[pair.backgroundKey], "矩阵引用了不存在的键 \(pair.backgroundKey)")
            XCTAssertFalse(pair.name.contains("0x"), "矩阵不得重复写十六进制")
            XCTAssertFalse(pair.foregroundKey.contains("0x"))
            XCTAssertFalse(pair.backgroundKey.contains("0x"))
            switch pair.tier {
            case .body:
                XCTAssertEqual(pair.minimum, ContrastPolicy.bodyThreshold)
            case .large:
                XCTAssertEqual(pair.minimum, ContrastPolicy.largeThreshold)
            case .decorative:
                XCTAssertEqual(pair.minimum, ContrastPolicy.decorativeThreshold)
            }
        }

        let referenced = Set(matrix.flatMap { [$0.foregroundKey, $0.backgroundKey] })
        XCTAssertEqual(referenced, Set(palette.keys), "18 个语义键每个至少出现一次")
    }

    func testEveryPairMeetsThresholdInBothAppearances() {
        for scheme in ContrastPolicy.Scheme.allCases {
            let checks = ContrastPolicy.checks(for: scheme)
            XCTAssertEqual(checks.count, ContrastPolicy.pairMatrix.count)
            for entry in ContrastPolicy.ratios(for: checks) {
                print("ac-contrast \(entry.name) \(entry.ratio.map(ContrastPolicy.formatted) ?? "nil")")
            }
            XCTAssertEqual(
                ContrastPolicy.problems(for: checks),
                [],
                "\(scheme.rawValue) 存在不达标语义色对"
            )
        }
    }

    // MARK: - ac-contrast-values-locked

    func testKnownRatiosMatchReferenceValues() {
        guard
            let lightAccent = ContrastPolicy.component("accent", scheme: .light),
            let lightOnAccent = ContrastPolicy.component("onAccent", scheme: .light),
            let darkAccent = ContrastPolicy.component("accent", scheme: .dark),
            let darkOnAccent = ContrastPolicy.component("onAccent", scheme: .dark),
            let lightSuccess = ContrastPolicy.component("success", scheme: .light),
            let lightSuccessSoft = ContrastPolicy.component("successSoft", scheme: .light),
            let lightAccentSoft = ContrastPolicy.component("accentSoft", scheme: .light),
            let lightPrimary = ContrastPolicy.component("primary", scheme: .light),
            let lightSecondary = ContrastPolicy.component("secondary", scheme: .light),
            let lightBackground = ContrastPolicy.component("background", scheme: .light),
            let lightSurface = ContrastPolicy.component("surface", scheme: .light),
            let darkDanger = ContrastPolicy.component("danger", scheme: .dark),
            let darkDangerSoft = ContrastPolicy.component("dangerSoft", scheme: .dark)
        else {
            return XCTFail("调色板缺少锁定实测值所需的语义色")
        }

        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightOnAccent, background: lightAccent) ?? 0,
            8.44,
            accuracy: 0.01,
            "light onAccent/accent 与 dark 同值口径，实测 8.44"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightAccent, background: DesignTokens.SRGB(hex: 0xFAFAF9)) ?? 0,
            2.0049,
            accuracy: 0.0001,
            "light accent/background 实测 2.0049（品牌优先豁免，见登记表）"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: darkOnAccent, background: darkAccent) ?? 0,
            8.44,
            accuracy: 0.01,
            "dark onAccent/accent 实测值应为 8.44"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightSuccess, background: lightSuccessSoft) ?? 0,
            5.64,
            accuracy: 0.01,
            "light success/successSoft 实测值应为 5.64"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: darkDanger, background: darkDangerSoft) ?? 0,
            4.82,
            accuracy: 0.01,
            "dark danger/dangerSoft 实测值应为 4.82（最薄 body pair）"
        )

        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightAccentSoft, background: lightBackground) ?? 0,
            1.0971,
            accuracy: 0.0001,
            "light accentSoft/background 必须 ≥1.05"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightAccentSoft, background: lightSurface) ?? 0,
            1.1459,
            accuracy: 0.0001,
            "light accentSoft/surface 必须 ≥1.10"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightPrimary, background: lightAccentSoft) ?? 0,
            15.5047,
            accuracy: 0.0001,
            "primary/accentSoft 实测 15.5047"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightSecondary, background: lightAccentSoft) ?? 0,
            5.6008,
            accuracy: 0.0001,
            "secondary/accentSoft 实测 5.6008"
        )

        XCTAssertEqual(ContrastPolicy.bodyThreshold, 4.5)
        XCTAssertEqual(ContrastPolicy.largeThreshold, 3)
    }

    // MARK: - ac-ondanger-matrix-pair

    func testOnDangerPairIsSingleBodyTierAndMeasured() {
        let pairs = ContrastPolicy.pairMatrix.filter { $0.name == "onDanger/danger" }
        XCTAssertEqual(pairs.count, 1, "onDanger/danger 恰 1 条")
        XCTAssertEqual(pairs.first?.tier, .body)
        XCTAssertEqual(pairs.first?.minimum, ContrastPolicy.bodyThreshold)

        guard
            let lightOnDanger = ContrastPolicy.component("onDanger", scheme: .light),
            let lightDanger = ContrastPolicy.component("danger", scheme: .light),
            let darkOnDanger = ContrastPolicy.component("onDanger", scheme: .dark),
            let darkDanger = ContrastPolicy.component("danger", scheme: .dark)
        else {
            return XCTFail("调色板缺少 onDanger/danger 实测所需颜色")
        }
        let light = ContrastPolicy.ratio(foreground: lightOnDanger, background: lightDanger) ?? 0
        let dark = ContrastPolicy.ratio(foreground: darkOnDanger, background: darkDanger) ?? 0
        XCTAssertEqual(light, 12.91, accuracy: 0.01)
        XCTAssertEqual(dark, 4.95, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(dark, ContrastPolicy.bodyThreshold)

        // 反例：dark 改用白字只有 3.76，不达标，不能靠反向放宽阈值补绿。
        let whiteOnDarkDanger = ContrastPolicy.ratio(
            foreground: DesignTokens.SRGB(hex: 0xFFFFFF),
            background: darkDanger
        ) ?? 0
        XCTAssertEqual(whiteOnDarkDanger, 3.76, accuracy: 0.01)
        XCTAssertLessThan(whiteOnDarkDanger, ContrastPolicy.bodyThreshold)
    }

    // MARK: - ac-brand-exemption-scoped / ac-exemption-not-formula

    private let expectedExemptions: [(name: String, measured: Double)] = [
        ("light accent/background", 2.0049),
        ("light accent/surface", 2.0940),
        ("light accent/accentSoft", 1.8274),
        ("light accent/background@large", 2.0049),
        ("light accent/surface@large", 2.0940),
        ("light accent/surfaceMuted@large", 1.8693)
    ]

    func testBrandExemptionRegistryIsExactlySixLightAccentPairs() {
        let registry = ContrastPolicy.brandPriorityExemptions
        XCTAssertEqual(registry.count, 6)
        XCTAssertEqual(registry.map(\.name), expectedExemptions.map(\.name))
        XCTAssertTrue(registry.allSatisfy { $0.name.hasPrefix("light accent/") })
        XCTAssertFalse(registry.contains { $0.name.hasPrefix("dark ") })
        XCTAssertTrue(registry.allSatisfy { !$0.source.isEmpty && $0.source.contains("V1.2") })

        let lightRatios = Dictionary(
            uniqueKeysWithValues: ContrastPolicy.ratios(for: ContrastPolicy.checks(for: .light))
                .map { ($0.name, $0.ratio) }
        )
        let matrixNames = Set(ContrastPolicy.checks(for: .light).map(\.name))
        for (entry, expected) in zip(registry, expectedExemptions) {
            XCTAssertEqual(entry.measured, expected.measured, accuracy: 0.0001)
            XCTAssertTrue(matrixNames.contains(entry.name), "登记项必须命中真实矩阵：\(entry.name)")
            guard let value = lightRatios[entry.name] ?? nil else {
                XCTFail("登记项无法现场重算：\(entry.name)")
                continue
            }
            XCTAssertEqual(value, expected.measured, accuracy: 0.0001)
            XCTAssertLessThan(value, ContrastPolicy.bodyThreshold, "登记项必须是低对比豁免，不掩盖达标对")
        }
        let darkExemptions = ContrastPolicy.brandPriorityExemptions.filter { $0.name.hasPrefix("dark ") }
        XCTAssertEqual(darkExemptions, [], "dark 侧零豁免")
    }

    func testClearingExemptionsTurnsAllSixPairsRed() {
        let lightChecks = ContrastPolicy.checks(for: .light)
        let problems = ContrastPolicy.problems(for: lightChecks, exemptions: [])
        XCTAssertEqual(problems.count, 6, "清空登记表后应恰有 6 条品牌橙对判红")
        let exemptNames = Set(ContrastPolicy.brandPriorityExemptions.map(\.name))
        let redNames = Set(problems.compactMap { message -> String? in
            guard message.hasPrefix("对比度不足 ") else { return nil }
            return message.dropFirst("对比度不足 ".count).split(separator: ":").first.map(String.init)
        })
        XCTAssertEqual(redNames, exemptNames)
    }

    func testRemovingOneExemptionTurnsThatPairRed() {
        let lightChecks = ContrastPolicy.checks(for: .light)
        var trimmed = ContrastPolicy.brandPriorityExemptions
        trimmed.removeAll { $0.name == "light accent/accentSoft" }
        let problems = ContrastPolicy.problems(for: lightChecks, exemptions: trimmed)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems.first?.contains("light accent/accentSoft") == true)
    }

    func testUnregisteredLowContrastSyntheticPairStaysRed() {
        let synthetic = ContrastPolicy.Check(
            name: "light synthetic/accentOnWhite",
            foreground: DesignTokens.SRGB(hex: 0xFF9A5C),
            background: DesignTokens.SRGB(hex: 0xFFFFFF),
            minimum: ContrastPolicy.bodyThreshold
        )
        let problems = ContrastPolicy.problems(for: [synthetic])
        XCTAssertFalse(problems.isEmpty, "未登记的低对比 synthetic pair 必须判红")
        XCTAssertTrue(problems.first?.contains("对比度不足") == true)
    }

    func testThresholdsAndMatrixSizeUnchanged() {
        XCTAssertEqual(ContrastPolicy.bodyThreshold, 4.5)
        XCTAssertEqual(ContrastPolicy.largeThreshold, 3.0)
        XCTAssertEqual(ContrastPolicy.decorativeThreshold, 1.10)
        XCTAssertEqual(ContrastPolicy.pairMatrix.count, 37)
    }

    // MARK: - ac-contrast-fail-closed-red

    func testMissingPaletteKeyFailsClosedThroughResolution() {
        // 结构性保证：矩阵引用不存在的键时，解析结果必须是 nil 侧并判红；
        // 因此删除或改名任一 palette 键都会让整张真实矩阵因「缺色对」而红。
        let matrix = [
            ContrastPolicy.Pair(
                name: "missing/background",
                foregroundKey: "notARealKey",
                backgroundKey: "background",
                minimum: ContrastPolicy.bodyThreshold,
                tier: .body
            )
        ]
        let problems = ContrastPolicy.problems(for: ContrastPolicy.checks(for: .light, matrix: matrix))
        XCTAssertFalse(problems.isEmpty, "缺键必须判红")
        XCTAssertTrue(problems.first?.contains("缺色对") == true, "缺键问题必须写明缺色对，实际 \(problems)")
    }

    func testEmptyNameFailsClosedThroughResolution() {
        let matrix = [
            ContrastPolicy.Pair(
                name: "",
                foregroundKey: "primary",
                backgroundKey: "background",
                minimum: ContrastPolicy.bodyThreshold,
                tier: .body
            )
        ]
        let problems = ContrastPolicy.problems(for: ContrastPolicy.checks(for: .light, matrix: matrix))
        XCTAssertFalse(problems.isEmpty, "空对照名必须判红")
        XCTAssertTrue(problems.first?.contains("缺对照名") == true, "空名问题必须写明原因，实际 \(problems)")
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

    func testLowContrastPairIsRejected() {
        let foreground = DesignTokens.SRGB(hex: 0xAAAAAA)
        let background = DesignTokens.SRGB(hex: 0xFFFFFF)
        let value = ContrastPolicy.ratio(foreground: foreground, background: background)
        print("ac-contrast 反例 low #AAAAAA/#FFFFFF \(value.map(ContrastPolicy.formatted) ?? "nil")")
        XCTAssertEqual(value ?? 0, 2.32, accuracy: 0.01)

        let check = ContrastPolicy.Check(
            name: "low #AAAAAA on #FFFFFF",
            foreground: foreground,
            background: background,
            minimum: ContrastPolicy.bodyThreshold
        )
        let problems = ContrastPolicy.problems(for: [check])
        XCTAssertFalse(problems.isEmpty, "低对比反例必须判红")
        XCTAssertTrue(problems.first?.contains("对比度不足") == true, "反例问题必须写明对比度不足，实际 \(problems)")
    }
}
