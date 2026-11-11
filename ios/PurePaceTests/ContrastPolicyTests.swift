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
        XCTAssertGreaterThanOrEqual(matrix.count, 36, "成对矩阵至少 36 对")
        XCTAssertEqual(matrix.count, Set(matrix.map(\.name)).count, "矩阵条目名必须唯一")

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
            let darkDanger = ContrastPolicy.component("danger", scheme: .dark),
            let darkDangerSoft = ContrastPolicy.component("dangerSoft", scheme: .dark)
        else {
            return XCTFail("调色板缺少锁定实测值所需的语义色")
        }

        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightOnAccent, background: lightAccent) ?? 0,
            6.07,
            accuracy: 0.01,
            "light onAccent/accent 实测值应为 6.07"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: darkOnAccent, background: darkAccent) ?? 0,
            9.57,
            accuracy: 0.01,
            "dark onAccent/accent 实测值应为 9.57"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: lightSuccess, background: lightSuccessSoft) ?? 0,
            4.81,
            accuracy: 0.01,
            "light success/successSoft 实测最低值应为 4.81"
        )
        XCTAssertEqual(
            ContrastPolicy.ratio(foreground: darkDanger, background: darkDangerSoft) ?? 0,
            6.86,
            accuracy: 0.01,
            "dark danger/dangerSoft 实测最低值应为 6.86"
        )

        XCTAssertEqual(ContrastPolicy.bodyThreshold, 4.5)
        XCTAssertEqual(ContrastPolicy.largeThreshold, 3)
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
