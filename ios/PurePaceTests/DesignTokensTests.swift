import XCTest
@testable import PurePace

/// 设计 token 不变量：间距/字号/圆角/图标阶梯有序，最小触控尺寸固定 44。
final class DesignTokensTests: XCTestCase {
    // MARK: - ac-token-values-valid

    func testSpacingScaleIsStrictlyIncreasingAndPositive() {
        let scale = DesignTokens.Spacing.scale
        XCTAssertEqual(scale.count, 6)
        XCTAssertGreaterThan(scale[0], 0)
        for index in 1..<scale.count {
            XCTAssertGreaterThan(scale[index], scale[index - 1], "间距档必须严格递增")
        }
    }

    func testTypographyScaleIsStrictlyIncreasingAndPositive() {
        let sizes = DesignTokens.Typography.sizes
        XCTAssertEqual(sizes.count, 6)
        XCTAssertGreaterThan(sizes[0], 0)
        for index in 1..<sizes.count {
            XCTAssertGreaterThan(sizes[index], sizes[index - 1], "字号层级必须严格递增")
        }
    }

    func testTypographyHierarchyMatchesDeclaredOrder() {
        XCTAssertLessThan(DesignTokens.Typography.metricLabelSize, DesignTokens.Typography.captionSize)
        XCTAssertLessThan(DesignTokens.Typography.captionSize, DesignTokens.Typography.bodySize)
        XCTAssertLessThan(DesignTokens.Typography.bodySize, DesignTokens.Typography.titleSize)
        XCTAssertLessThan(DesignTokens.Typography.titleSize, DesignTokens.Typography.primaryValueSize)
        XCTAssertLessThan(DesignTokens.Typography.primaryValueSize, DesignTokens.Typography.displaySize)
    }

    func testPrimaryMetricsAreClearlyLargerThanSecondary() {
        // 跑步页主信息（距离/时长/配速）至少是次信息（平均配速/分段/说明）的两倍字号。
        XCTAssertGreaterThanOrEqual(
            DesignTokens.Typography.displaySize,
            DesignTokens.Typography.bodySize * 2
        )
        XCTAssertGreaterThanOrEqual(
            DesignTokens.Typography.primaryValueSize,
            DesignTokens.Typography.bodySize * 2
        )
    }

    func testTapTargetIsFortyFourPoints() {
        XCTAssertEqual(DesignTokens.minTapTarget, 44)
    }

    func testRadiusAndIconScalesArePositiveAndOrdered() {
        let radius = DesignTokens.Radius.scale
        XCTAssertEqual(radius.count, 3)
        for value in radius {
            XCTAssertGreaterThan(value, 0)
        }
        for index in 1..<radius.count {
            XCTAssertGreaterThan(radius[index], radius[index - 1], "圆角档必须严格递增")
        }

        let icons = DesignTokens.Icon.scale
        XCTAssertEqual(icons.count, 3)
        for value in icons {
            XCTAssertGreaterThan(value, 0)
        }
        for index in 1..<icons.count {
            XCTAssertGreaterThan(icons[index], icons[index - 1], "图标尺寸档必须严格递增")
        }
    }

    func testTypographyWeightsAreDeclaredInAscendingOrder() {
        XCTAssertEqual(
            DesignTokens.Typography.weights,
            [.regular, .semibold, .bold]
        )
    }

    // MARK: - ac-token-categories

    func testTokenCoversColorsSizesSpacingAndRadius() {
        // 颜色常量由静态门 `validate_design_tokens` 断言 `DesignTokens.Colors`；
        // 这里对字号 / 间距 / 圆角三类数值档做可执行的覆盖断言。
        XCTAssertEqual(DesignTokens.Typography.sizes.count, 6)
        XCTAssertEqual(DesignTokens.Spacing.scale.count, 6)
        XCTAssertEqual(DesignTokens.Radius.scale.count, 3)
    }

    func testDarkModeIsEnabledAndPaletteIsComplete() {
        // ac-dark-mode-real：深色模式真实开启，且每个语义色都有 light/dark 成对值。
        XCTAssertTrue(DesignTokens.Appearance.supportsDarkMode)
        let expected = [
            "background", "surface", "surfaceMuted", "primary", "secondary", "accent",
            "onAccent", "accentSoft", "separator", "warning", "onWarning", "warningSoft",
            "success", "onSuccess", "successSoft", "danger", "onDanger", "dangerSoft"
        ]
        XCTAssertEqual(DesignTokens.Colors.palette.count, expected.count)
        let sameValueAllowed: Set<String> = ["accent", "onAccent"]
        for name in expected {
            guard let pair = DesignTokens.Colors.palette[name] else {
                XCTFail("调色板缺少语义色 \(name)")
                continue
            }
            XCTAssertTrue(pair.light.isInRange, "\(name).light 分量越界")
            XCTAssertTrue(pair.dark.isInRange, "\(name).dark 分量越界")
            if sameValueAllowed.contains(name) {
                XCTAssertEqual(pair.light, pair.dark, "\(name) 按 V1.2 定稿必须 light/dark 同值")
            } else {
                XCTAssertNotEqual(pair.light, pair.dark, "\(name) 的 light/dark必须是两组真实取值")
            }
        }
    }

    func testBrandPrimaryTokenIsSingleAndMutedSurfacesAreDeclared() {
        // ac-brand-primary-token：唯一品牌主色 + 记录态弱底 + 卡片弱面同时存在。
        XCTAssertNotNil(DesignTokens.Colors.palette["accent"])
        XCTAssertNotNil(DesignTokens.Colors.palette["accentSoft"])
        XCTAssertNotNil(DesignTokens.Colors.palette["surfaceMuted"])
        XCTAssertNotNil(DesignTokens.Colors.palette["separator"])
    }

    // MARK: - ac-color-purpose-registry

    func testColorPurposeRegistryMatchesPalette() {
        let palette = DesignTokens.Colors.palette
        let purposes = DesignTokens.Colors.purposes
        XCTAssertEqual(purposes.count, palette.count)
        XCTAssertEqual(Set(purposes.keys), Set(palette.keys), "用途注册表键集必须与 palette 完全相等")
        XCTAssertEqual(DesignTokens.Colors.purposeProblems(), [], "真实注册表不得有缺键/空用途/复读键名")
        for (key, value) in purposes {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(trimmed.isEmpty, "\(key) 的语义用途不得为空")
            XCTAssertNotEqual(trimmed, key, "\(key) 的语义用途不得复读键名")
        }
    }

    func testColorPurposeRegistryRejectsBadEntries() {
        var empty = DesignTokens.Colors.purposes
        empty["background"] = "   "
        XCTAssertTrue(
            DesignTokens.Colors.purposeProblems(registry: empty).contains { $0.contains("空用途") },
            "空用途必须判红"
        )

        var echo = DesignTokens.Colors.purposes
        echo["accent"] = "accent"
        XCTAssertTrue(
            DesignTokens.Colors.purposeProblems(registry: echo).contains { $0.contains("复读键名") },
            "复读键名必须判红"
        )

        var missing = DesignTokens.Colors.purposes
        missing.removeValue(forKey: "separator")
        XCTAssertTrue(
            DesignTokens.Colors.purposeProblems(registry: missing).contains { $0.contains("缺用途") },
            "删除注册表键必须判红"
        )
    }

    // MARK: - ac-typography-metric-roles

    func testMetricTypographyRoles() {
        XCTAssertEqual(DesignTokens.Typography.metricLabelSize, 11)
        XCTAssertEqual(DesignTokens.Typography.metricUnitSize, 11)
        XCTAssertEqual(
            DesignTokens.Typography.metricLabelSize,
            DesignTokens.Typography.metricUnitSize
        )
        XCTAssertLessThan(DesignTokens.Typography.metricLabelSize, DesignTokens.Typography.captionSize)
        XCTAssertGreaterThanOrEqual(DesignTokens.Typography.metricLabelSize, 10)

        XCTAssertEqual(DesignTokens.Typography.sizes, [11, 13, 15, 20, 36, 64])
        // 方向 A 的 6 档字号：label/unit 同为 11，display 64 与 label 11 构成 5.8× 数值/标签比。
        XCTAssertEqual(DesignTokens.Typography.captionSize, 13)
        XCTAssertEqual(DesignTokens.Typography.bodySize, 15)
        XCTAssertEqual(DesignTokens.Typography.titleSize, 20)
        XCTAssertEqual(DesignTokens.Typography.primaryValueSize, 36)
        XCTAssertEqual(DesignTokens.Typography.displaySize, 64)
    }

    // MARK: - ac-typography-role-ladder

    func testTypographyRoleLadder() {
        let ladder = DesignTokens.Typography.roleLadder
        XCTAssertEqual(ladder.count, 7)
        for index in 1..<ladder.count {
            XCTAssertGreaterThanOrEqual(ladder[index].size, ladder[index - 1].size, "角色阶梯必须按字号非递减")
        }

        let duplicates = Dictionary(grouping: ladder, by: \.size).filter { $0.value.count > 1 }
        XCTAssertFalse(duplicates.isEmpty, "label/unit 必须共享 11 这一档")
        for (size, roles) in duplicates {
            XCTAssertEqual(size, 11)
            XCTAssertEqual(Set(roles.map(\.name)), ["metricLabel", "metricUnit"])
        }

        XCTAssertEqual(DesignTokens.Typography.numericRoleNames, ["primaryValue", "display"])
        XCTAssertEqual(
            Set(ladder.filter(\.needsMonospacedDigits).map(\.name)),
            ["primaryValue", "display"]
        )
        XCTAssertEqual(DesignTokens.Typography.roleProblems(), [])
    }

    func testRoleLadderRejectsNumericDrift() {
        var withoutDisplay = DesignTokens.Typography.roleLadder
        withoutDisplay = withoutDisplay.map { role in
            guard role.name == "display" else { return role }
            return DesignTokens.Typography.Role(
                name: role.name,
                size: role.size,
                needsMonospacedDigits: false
            )
        }
        XCTAssertFalse(
            DesignTokens.Typography.roleProblems(withoutDisplay).isEmpty,
            "把 display 移出数值角色集合必须判红"
        )

        let captionMarked = DesignTokens.Typography.roleLadder.map { role in
            guard role.name == "caption" else { return role }
            return DesignTokens.Typography.Role(
                name: role.name,
                size: role.size,
                needsMonospacedDigits: true
            )
        }
        XCTAssertFalse(
            DesignTokens.Typography.roleProblems(captionMarked).isEmpty,
            "给 caption 打等宽数字标记必须判红"
        )
    }

    // MARK: - ac-motion-tokens-and-degrade

    func testMotionTokensAndDegrade() {
        XCTAssertEqual(DesignTokens.Motion.durationShort, 0.2)
        XCTAssertEqual(DesignTokens.Motion.durationState, 0.32)
        XCTAssertEqual(DesignTokens.Motion.reducedMotionDuration, 0)
        XCTAssertGreaterThan(DesignTokens.Motion.durationShort, 0)
        XCTAssertLessThan(DesignTokens.Motion.durationShort, DesignTokens.Motion.durationState)
        XCTAssertLessThanOrEqual(DesignTokens.Motion.durationState, 0.4)

        XCTAssertEqual(
            DesignTokens.Motion.duration(DesignTokens.Motion.durationShort, reduceMotion: true),
            0
        )
        XCTAssertEqual(
            DesignTokens.Motion.duration(DesignTokens.Motion.durationState, reduceMotion: true),
            0
        )
        XCTAssertEqual(
            DesignTokens.Motion.duration(DesignTokens.Motion.durationShort, reduceMotion: false),
            DesignTokens.Motion.durationShort
        )
        XCTAssertEqual(
            DesignTokens.Motion.duration(DesignTokens.Motion.durationState, reduceMotion: false),
            DesignTokens.Motion.durationState
        )
    }

    // MARK: - ac-semantic-spacing

    func testSemanticSpacingFallsOnExistingTiers() {
        let tiers: Set<CGFloat> = [4, 8, 12, 16, 24, 32]
        XCTAssertTrue(tiers.contains(DesignTokens.Spacing.metricGroupSpacing), "指标组内间距必须落在既有档位")
        XCTAssertTrue(tiers.contains(DesignTokens.Spacing.metricGroupGap), "指标组间距必须落在既有档位")
        XCTAssertTrue(tiers.contains(DesignTokens.Spacing.cardPadding), "卡片内边距必须落在既有档位")

        XCTAssertEqual(DesignTokens.Spacing.screenTop, 24)
        XCTAssertEqual(DesignTokens.Spacing.cardGap, 16)
        XCTAssertEqual(DesignTokens.Spacing.sectionGap, 12)
        XCTAssertEqual(DesignTokens.Spacing.scale, [4, 8, 12, 16, 24, 32])
    }

    // MARK: - ac-existing-tiers-frozen

    func testExistingTiersAreFrozen() {
        XCTAssertEqual(DesignTokens.Radius.scale, [10, 14, 20])
        XCTAssertEqual(DesignTokens.Icon.scale, [16, 20, 24])
        XCTAssertEqual(DesignTokens.Radius.scale.count, 3)
        XCTAssertEqual(DesignTokens.Icon.scale.count, 3)
        XCTAssertEqual(DesignTokens.Stroke.hairline, 1)
        XCTAssertEqual(DesignTokens.minTapTarget, 44)
        XCTAssertTrue(DesignTokens.Appearance.supportsDarkMode)
    }

    // MARK: - ac-palette-hex-exact（方向 A 逐键锁值）

    /// 期望表：字面 UInt32，改任一键回旧值或改任一分量即红。
    private let directionAHex: [String: (light: UInt32, dark: UInt32)] = [
        "background": (0xFAFAF9, 0x0B0C0D),
        "surface": (0xFFFFFF, 0x16181A),
        "surfaceMuted": (0xF2F2F1, 0x1E2124),
        "primary": (0x17181A, 0xF2F3F4),
        "secondary": (0x5C5F63, 0xA2A7AC),
        "accent": (0xFF9A5C, 0xFF9A5C),
        "onAccent": (0x2A1206, 0x2A1206),
        "accentSoft": (0xFFECE0, 0x3A1F12),
        "separator": (0xD8D8D3, 0x33383D),
        "warning": (0x6E5C00, 0xEECA2B),
        "onWarning": (0xFFFFFF, 0x2B1A00),
        "warningSoft": (0xFBF1DC, 0x3A2A0D),
        "success": (0x1F6B45, 0x58CF9B),
        "onSuccess": (0xFFFFFF, 0x042416),
        "successSoft": (0xE7F2EB, 0x11311F),
        "danger": (0x660D09, 0xF53A48),
        "onDanger": (0xFFFFFF, 0x2A0608),
        "dangerSoft": (0xFBEAE8, 0x2C0A10)
    ]

    func testPaletteHexMatchesDirectionATable() {
        XCTAssertEqual(Set(DesignTokens.Colors.palette.keys), Set(directionAHex.keys), "18 键冻结清单必须一致")
        XCTAssertEqual(directionAHex.count, 18)
        for (key, expected) in directionAHex {
            guard let pair = DesignTokens.Colors.palette[key] else {
                XCTFail("缺少色键 \(key)")
                continue
            }
            XCTAssertEqual(hex(pair.light), expected.light, "\(key) light 必须逐键等于方向 A 表")
            XCTAssertEqual(hex(pair.dark), expected.dark, "\(key) dark 必须逐键等于方向 A 表")
        }
    }

    // MARK: - ac-accent-single-orange / ac-onaccent-single-deep / ac-accentsoft-light-recomputed

    func testAccentIsSingleBrandOrangeInBothSchemes() {
        XCTAssertEqual(singleBrandOrangeProblems(DesignTokens.Colors.palette), [], "V1.2 唯一品牌橙口径不成立")
        for side in ["light", "dark"] {
            let value = color("accent", side)
            XCTAssertEqual(hex(value), 0xFF9A5C, "accent.\(side) 必须是唯一品牌橙 #FF9A5C")
            let c = hsl(value)
            XCTAssertEqual(c.h, 22.8, accuracy: 0.1, "accent.\(side) 色相")
            XCTAssertEqual(c.s, 100, accuracy: 0.1, "accent.\(side) 饱和度")
            XCTAssertEqual(c.l, 68.0, accuracy: 0.1, "accent.\(side) 明度")
        }
        XCTAssertNotEqual(hex(color("accent", "light")), 0xB4400B, "旧砖红作废")
        XCTAssertNotEqual(hex(color("accent", "dark")), 0xE85D04, "设计稿候选作废")

        // 反例（不改生产代码）：回退旧砖红、切设计稿候选/压暗橙，同一判据都必须判红。
        var reverted = DesignTokens.Colors.palette
        reverted["accent"] = DesignTokens.ColorPair(
            light: DesignTokens.SRGB(hex: 0xB4400B),
            dark: DesignTokens.SRGB(hex: 0xFF9A5C)
        )
        XCTAssertFalse(singleBrandOrangeProblems(reverted).isEmpty, "回退旧砖红必须判红")

        var candidate = DesignTokens.Colors.palette
        candidate["accent"] = DesignTokens.ColorPair(
            light: DesignTokens.SRGB(hex: 0xE85D04),
            dark: DesignTokens.SRGB(hex: 0xE85D04)
        )
        XCTAssertFalse(singleBrandOrangeProblems(candidate).isEmpty, "设计稿候选/压暗橙必须判红")
    }

    func testOnAccentSingleDeepInBothSchemes() {
        XCTAssertEqual(onAccentProblems(DesignTokens.Colors.palette), [])
        for scheme in [ContrastPolicy.Scheme.light, .dark] {
            let side = scheme == .light ? "light" : "dark"
            let ratio = ContrastPolicy.ratio(
                foreground: color("onAccent", side),
                background: color("accent", side)
            ) ?? 0
            XCTAssertEqual(ratio, 8.44, accuracy: 0.01, "\(side) onAccent/accent 实测值应为 8.44")
            XCTAssertGreaterThanOrEqual(ratio, ContrastPolicy.bodyThreshold)
        }

        var whiteOnLight = DesignTokens.Colors.palette
        whiteOnLight["onAccent"] = DesignTokens.ColorPair(
            light: DesignTokens.SRGB(hex: 0xFFFFFF),
            dark: DesignTokens.SRGB(hex: 0x2A1206)
        )
        XCTAssertFalse(onAccentProblems(whiteOnLight).isEmpty, "旧白字 onAccent 必须判红")
    }

    func testAccentSoftLightRecomputedAndDarkFrozen() {
        XCTAssertEqual(accentSoftProblems(DesignTokens.Colors.palette), [])
        let light = DesignTokens.Colors.palette["accentSoft"]!.light
        let c = hsl(light)
        XCTAssertEqual(hex(light), 0xFFECE0)
        XCTAssertEqual(c.h, 23.2, accuracy: 0.1)
        XCTAssertEqual(c.s, 100, accuracy: 0.1)
        XCTAssertEqual(c.l, 93.9, accuracy: 0.1)
        XCTAssertEqual(hex(DesignTokens.Colors.palette["accentSoft"]!.dark), 0x3A1F12, "dark accentSoft 不得改动")

        var old = DesignTokens.Colors.palette
        old["accentSoft"] = DesignTokens.ColorPair(
            light: DesignTokens.SRGB(hex: 0xFCEFE7),
            dark: DesignTokens.SRGB(hex: 0x3A1F12)
        )
        XCTAssertFalse(accentSoftProblems(old).isEmpty, "旧 accentSoft #FCEFE7 必须判红")
    }

    func testPaletteShapeFrozenAfterSingleOrange() {
        XCTAssertEqual(paletteShapeProblems(DesignTokens.Colors.palette), [])
        XCTAssertEqual(DesignTokens.Colors.palette.count, 18)
        XCTAssertEqual(DesignTokens.Colors.palette.reduce(0) { count, _ in count + 2 }, 36, "light/dark 共 36 个 hex 槽位")
        let sameValue = DesignTokens.Colors.palette
            .filter { $0.value.light == $0.value.dark }
            .keys.sorted()
        XCTAssertEqual(sameValue, ["accent", "onAccent"], "仅 accent / onAccent 允许 light==dark")

        // 反例（不改生产代码）：非白名单同值 / 少一个语义键都必须判红。
        var surfaceSame = DesignTokens.Colors.palette
        surfaceSame["surface"] = DesignTokens.ColorPair(
            light: DesignTokens.SRGB(hex: 0xFFFFFF),
            dark: DesignTokens.SRGB(hex: 0xFFFFFF)
        )
        XCTAssertFalse(paletteShapeProblems(surfaceSame).isEmpty, "非白名单同值必须判红")

        var missing = DesignTokens.Colors.palette
        missing.removeValue(forKey: "warning")
        XCTAssertFalse(paletteShapeProblems(missing).isEmpty, "少语义键必须判红")
    }

    func testDangerSemanticsDescribeSolidDestructivePrimaryAction() {
        XCTAssertEqual(dangerSemanticsProblems(DesignTokens.Colors.purposes), [])
        let purpose = DesignTokens.Colors.purposes["danger"] ?? ""
        XCTAssertTrue(purpose.contains("实心破坏性主操作"))
        XCTAssertTrue(purpose.contains("C2"))
        XCTAssertFalse(purpose.contains("仅出现在确认层文本或描边按钮"))
        XCTAssertTrue(
            dangerSemanticsProblems(["danger": "丢弃等破坏性操作，仅出现在确认层文本或描边按钮"])
                .contains("残留旧口径"),
            "旧语义必须被同一判据判红"
        )
    }

    func testDangerKeepsValuesAfterSinglePassSeparation() {
        XCTAssertEqual(hex(color("danger", "light")), 0x660D09, "light danger 本次校验 0 档调整")
        XCTAssertEqual(hex(color("danger", "dark")), 0xF53A48, "dark danger 维持")
        // 实测：light 靠 ΔL 46.27pp、dark 靠 ΔH 27.31° 达标。
        let accentLight = hsl(color("accent", "light"))
        let dangerLight = hsl(color("danger", "light"))
        XCTAssertEqual(abs(accentLight.l - dangerLight.l), 46.27, accuracy: 0.05)
        let accentDark = hsl(color("accent", "dark"))
        let dangerDark = hsl(color("danger", "dark"))
        let rawHue = abs(accentDark.h - dangerDark.h)
        XCTAssertEqual(min(rawHue, 360 - rawHue), 27.31, accuracy: 0.05)

        // 反例：dark 侧若改用白字 onDanger 只有 3.76，不达标。
        let white = DesignTokens.SRGB(hex: 0xFFFFFF)
        let whiteOnDarkDanger = ContrastPolicy.ratio(
            foreground: white,
            background: color("danger", "dark")
        ) ?? 0
        XCTAssertEqual(whiteOnDarkDanger, 3.76, accuracy: 0.01)
        XCTAssertLessThan(whiteOnDarkDanger, ContrastPolicy.bodyThreshold)
    }

    // MARK: - ac-palette-neutral-purity（裁决 owe_40221a8e983c7516）

    func testDarkNeutralHueNotGreenAndChromaBounded() {
        // 判据：深色三键 HSL 色相落在 60–200° 之外，且 chroma/255 ≤ 3.0%。
        // A 表实测：色相均 210°，chroma 0.78% / 1.57% / 2.35%（余量 0.65pt）。
        // 旧值 #0A1211 / #141F1D / #1A2724：色相 172.5 / 169.1 / 166.2°、chroma 3.14 / 4.31 / 5.10% → 三键全红。
        for key in ["background", "surface", "surfaceMuted"] {
            let dark = DesignTokens.Colors.palette[key]!.dark
            let hue = hsl(dark).h
            let chroma = chromaPercent(dark)
            XCTAssertFalse((60.0...200.0).contains(hue), "\(key) 深色色相 \(hue)° 落在泛绿区间")
            XCTAssertGreaterThanOrEqual(hue, 195, "\(key) 深色色相应为石墨冷中性 195–225°")
            XCTAssertLessThanOrEqual(hue, 225, "\(key) 深色色相应为石墨冷中性 195–225°")
            XCTAssertLessThanOrEqual(chroma, 3.0, "\(key) 深色 chroma/255 必须 ≤3.0%（实测 \(chroma)%）")
        }

        // 内联旧 trio 反例：不得依赖改生产代码才红。
        let old = [DesignTokens.SRGB(hex: 0x0A1211),
                   DesignTokens.SRGB(hex: 0x141F1D),
                   DesignTokens.SRGB(hex: 0x1A2724)]
        for value in old {
            let hue = hsl(value).h
            XCTAssertTrue((60.0...200.0).contains(hue), "旧值色相必须落在泛绿区间")
            XCTAssertGreaterThan(chromaPercent(value), 3.0, "旧值 chroma 必须超 3.0%")
        }
    }

    func testLightNeutralSaturationIsBounded() {
        // 浅色三键实测 HSV S：0.40% / 0.00% / 0.41%（判据 ≤4%）。
        for key in ["background", "surface", "surfaceMuted"] {
            let light = DesignTokens.Colors.palette[key]!.light
            XCTAssertLessThanOrEqual(hsv(light).s, 4.0, "\(key) 浅色 HSV 饱和度必须 ≤4%")
        }
    }

    // MARK: - ac-palette-no-green

    func testPaletteHasNoForbiddenGreen() {
        // 使用方锁定 A 表的 success 系（语义"已保存"必须为绿），因此禁区扫描排除 success/onSuccess/successSoft；
        // 其余 15 键（含品牌色与三中性键）不得命中任何绿色禁区。把 accent 改回 #0B6F60 仍必红。
        let successFamily: Set<String> = ["success", "onSuccess", "successSoft"]
        var offenders: [String] = []
        for (key, pair) in DesignTokens.Colors.palette where !successFamily.contains(key) {
            for (side, value) in [("light", pair.light), ("dark", pair.dark)] {
                let c = hsv(value)
                if (72.0...85.0).contains(c.h) && c.s >= 90 { offenders.append("\(key).\(side)") }
                if (120.0...150.0).contains(c.h) && c.s >= 45 { offenders.append("\(key).\(side)") }
                if (165.0...180.0).contains(c.h) && c.s >= 55 { offenders.append("\(key).\(side)") }
            }
        }
        XCTAssertEqual(offenders, [], "调色板命中 digest §3.4 绿色禁区：\(offenders)")

        // 反例：旧 accent #0B6F60 的 HSV 约 H171°/S82% → 必红。
        let oldAccent = hsv(DesignTokens.SRGB(hex: 0x0B6F60))
        XCTAssertTrue((165.0...180.0).contains(oldAccent.h) && oldAccent.s >= 55, "旧 accent 必须命中禁区")
    }

    // MARK: - ac-palette-separation（accent↔warning / accent↔danger，HSL 口径）

    func testAccentSeparatesFromWarningAndDanger() {
        // HSL 判据（不用 HSV）：ΔH ≥ 25° 或 ΔL ≥ 15pp 或 ΔS ≥ 30pp，浅/深各判。
        for scheme in ["light", "dark"] {
            let accent = color("accent", scheme)
            for other in ["warning", "danger"] {
                let target = color(other, scheme)
                XCTAssertTrue(
                    separationHolds(accent, target),
                    "\(scheme) accent↔\(other) 分离度不足：\(metrics(accent, target))"
                )
            }
        }

        // 反例：旧值必须全部判红（浅/深 × warning/danger 四对）。
        let oldAccentLight = DesignTokens.SRGB(hex: 0xB4400B)
        let oldAccentDark = DesignTokens.SRGB(hex: 0xFF9A5C)
        XCTAssertFalse(separationHolds(oldAccentLight, DesignTokens.SRGB(hex: 0xA5231C)), "旧浅色 danger 必须判红")
        XCTAssertFalse(separationHolds(oldAccentDark, DesignTokens.SRGB(hex: 0xFF8A80)), "旧深色 danger 必须判红")
        // 旧浅色 warning #7A5A00 的 ΔH≈25.4° 恰好压线通过，故不作为反例；
        // 真正撞色的是深色 warning #F0B44C（ΔH≈15.5°、ΔL≈6、ΔS=0）。
        XCTAssertFalse(separationHolds(oldAccentDark, DesignTokens.SRGB(hex: 0xF0B44C)), "旧深色 warning 必须判红")
    }

    func testDarkDangerIsVividRedNotWarmOrange() {
        // 深色 danger 硬约束：H ≤ 8 或 ≥ 352、S ≥ 55、L ≤ 60。
        let dark = DesignTokens.Colors.palette["danger"]!.dark
        let c = hsl(dark)
        XCTAssertTrue(c.h <= 8.0 || c.h >= 352.0, "深色 danger 色相必须贴近正红：\(c.h)")
        XCTAssertGreaterThanOrEqual(c.s, 55, "深色 danger 饱和度必须 ≥55%")
        XCTAssertLessThanOrEqual(c.l, 60, "深色 danger 明度必须 ≤60%")
    }

    // MARK: - helpers

    private func color(_ key: String, _ scheme: String) -> DesignTokens.SRGB {
        let pair = DesignTokens.Colors.palette[key]!
        return scheme == "light" ? pair.light : pair.dark
    }

    private func hex(_ value: DesignTokens.SRGB) -> UInt32 {
        let r = UInt32((value.red * 255).rounded())
        let g = UInt32((value.green * 255).rounded())
        let b = UInt32((value.blue * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    private struct HSV { let h: Double; let s: Double; let v: Double }
    private struct HSL { let h: Double; let s: Double; let l: Double }

    private func hsv(_ c: DesignTokens.SRGB) -> HSV {
        let maxV = max(c.red, c.green, c.blue)
        let minV = min(c.red, c.green, c.blue)
        let delta = maxV - minV
        var h = 0.0
        if delta > 0 {
            if maxV == c.red {
                h = 60 * ((c.green - c.blue) / delta)
            } else if maxV == c.green {
                h = 60 * ((c.blue - c.red) / delta + 2)
            } else {
                h = 60 * ((c.red - c.green) / delta + 4)
            }
        }
        if h < 0 { h += 360 }
        return HSV(h: h, s: maxV == 0 ? 0 : delta / maxV * 100, v: maxV * 100)
    }

    private func hsl(_ c: DesignTokens.SRGB) -> HSL {
        let maxV = max(c.red, c.green, c.blue)
        let minV = min(c.red, c.green, c.blue)
        let delta = maxV - minV
        let l = (maxV + minV) / 2
        var h = 0.0
        if delta > 0 {
            if maxV == c.red {
                h = 60 * ((c.green - c.blue) / delta)
            } else if maxV == c.green {
                h = 60 * ((c.blue - c.red) / delta + 2)
            } else {
                h = 60 * ((c.red - c.green) / delta + 4)
            }
        }
        if h < 0 { h += 360 }
        let denominator = 1 - abs(2 * l - 1)
        let s = denominator == 0 ? 0 : delta / denominator
        return HSL(h: h, s: s * 100, l: l * 100)
    }

    private func chromaPercent(_ c: DesignTokens.SRGB) -> Double {
        let maxV = max(c.red, c.green, c.blue)
        let minV = min(c.red, c.green, c.blue)
        return (maxV - minV) * 100
    }

    private func separationHolds(_ a: DesignTokens.SRGB, _ b: DesignTokens.SRGB) -> Bool {
        let x = hsl(a)
        let y = hsl(b)
        let raw = abs(x.h - y.h)
        let deltaH = min(raw, 360 - raw)
        let deltaL = abs(x.l - y.l)
        let deltaS = abs(x.s - y.s)
        return deltaH >= 25 || deltaL >= 15 || deltaS >= 30
    }

    private func metrics(_ a: DesignTokens.SRGB, _ b: DesignTokens.SRGB) -> String {
        let x = hsl(a)
        let y = hsl(b)
        let raw = abs(x.h - y.h)
        return "dH=\(min(raw, 360 - raw)) dL=\(abs(x.l - y.l)) dS=\(abs(x.s - y.s))"
    }

    private func singleBrandOrangeProblems(_ palette: [String: DesignTokens.ColorPair]) -> [String] {
        var problems: [String] = []
        for side in ["light", "dark"] {
            guard let pair = palette["accent"] else {
                problems.append("缺 accent")
                continue
            }
            let value = side == "light" ? pair.light : pair.dark
            if hex(value) != 0xFF9A5C {
                problems.append("accent.\(side) 不是 #FF9A5C")
                continue
            }
            let c = hsl(value)
            if abs(c.h - 22.8) > 0.1 || abs(c.s - 100) > 0.1 || abs(c.l - 68.0) > 0.1 {
                problems.append("accent.\(side) HSL 漂移")
            }
        }
        var primaryOranges: [String] = []
        for (key, pair) in palette {
            for (side, value) in [("light", pair.light), ("dark", pair.dark)] {
                let c = hsl(value)
                if (20.0...35.0).contains(c.h) && c.s >= 90 && (40.0...75.0).contains(c.l) {
                    primaryOranges.append("\(key).\(side)")
                }
            }
        }
        if primaryOranges.sorted() != ["accent.dark", "accent.light"] {
            problems.append("存在第二套橙/压暗 fallback: \(primaryOranges.sorted())")
        }
        return problems
    }

    private func onAccentProblems(_ palette: [String: DesignTokens.ColorPair]) -> [String] {
        var problems: [String] = []
        guard let pair = palette["onAccent"], let accent = palette["accent"] else {
            return ["缺 onAccent/accent"]
        }
        for side in ["light", "dark"] {
            let value = side == "light" ? pair.light : pair.dark
            if hex(value) != 0x2A1206 {
                problems.append("onAccent.\(side) 不是 #2A1206")
                continue
            }
            let background = side == "light" ? accent.light : accent.dark
            guard let ratio = ContrastPolicy.ratio(foreground: value, background: background) else {
                problems.append("onAccent.\(side) 无法计算")
                continue
            }
            if abs(ratio - 8.44) > 0.01 || ratio < ContrastPolicy.bodyThreshold {
                problems.append("onAccent.\(side) 对比度 \(ratio)")
            }
        }
        return problems
    }

    private func accentSoftProblems(_ palette: [String: DesignTokens.ColorPair]) -> [String] {
        var problems: [String] = []
        guard let pair = palette["accentSoft"] else { return ["缺 accentSoft"] }
        if hex(pair.light) != 0xFFECE0 {
            problems.append("light accentSoft 不是 #FFECE0")
        }
        let c = hsl(pair.light)
        if abs(c.h - 23.2) > 0.1 || abs(c.s - 100) > 0.1 || abs(c.l - 93.9) > 0.1 {
            problems.append("light accentSoft HSL 漂移")
        }
        if hex(pair.dark) != 0x3A1F12 {
            problems.append("dark accentSoft 漂移")
        }
        return problems
    }

    private func paletteShapeProblems(_ palette: [String: DesignTokens.ColorPair]) -> [String] {
        var problems: [String] = []
        if palette.count != 18 {
            problems.append("键数 \(palette.count)")
        }
        let sameValue = palette.filter { $0.value.light == $0.value.dark }.keys.sorted()
        if sameValue != ["accent", "onAccent"] {
            problems.append("同值键 \(sameValue)")
        }
        for key in [
            "warning", "onWarning", "warningSoft",
            "danger", "onDanger", "dangerSoft",
            "success", "onSuccess", "successSoft"
        ] {
            guard let pair = palette[key] else {
                problems.append("缺 \(key)")
                continue
            }
            if pair.light == pair.dark {
                problems.append("\(key) 必须保持双值")
            }
        }
        return problems
    }

    private func dangerSemanticsProblems(_ purposes: [String: String]) -> [String] {
        let text = purposes["danger"] ?? ""
        var problems: [String] = []
        if !text.contains("实心破坏性主操作") {
            problems.append("缺实心破坏性主操作")
        }
        if !text.contains("C2") {
            problems.append("缺 C2 紧凑版")
        }
        if text.contains("仅") || text.contains("描边") {
            problems.append("残留旧口径")
        }
        return problems
    }
}
