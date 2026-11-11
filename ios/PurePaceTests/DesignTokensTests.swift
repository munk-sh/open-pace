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
        for name in expected {
            guard let pair = DesignTokens.Colors.palette[name] else {
                XCTFail("调色板缺少语义色 \(name)")
                continue
            }
            XCTAssertTrue(pair.light.isInRange, "\(name).light 分量越界")
            XCTAssertTrue(pair.dark.isInRange, "\(name).dark 分量越界")
            XCTAssertNotEqual(pair.light, pair.dark, "\(name) 的 light/dark必须是两组真实取值")
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

        XCTAssertEqual(DesignTokens.Typography.sizes, [11, 12, 15, 20, 34, 56])
        // 既有字号一个不变。
        XCTAssertEqual(DesignTokens.Typography.captionSize, 12)
        XCTAssertEqual(DesignTokens.Typography.bodySize, 15)
        XCTAssertEqual(DesignTokens.Typography.titleSize, 20)
        XCTAssertEqual(DesignTokens.Typography.primaryValueSize, 34)
        XCTAssertEqual(DesignTokens.Typography.displaySize, 56)
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
        XCTAssertEqual(DesignTokens.Radius.scale, [12, 16, 20])
        XCTAssertEqual(DesignTokens.Icon.scale, [16, 20, 24])
        XCTAssertEqual(DesignTokens.Radius.scale.count, 3)
        XCTAssertEqual(DesignTokens.Icon.scale.count, 3)
        XCTAssertEqual(DesignTokens.Stroke.hairline, 1)
        XCTAssertEqual(DesignTokens.minTapTarget, 44)
        XCTAssertTrue(DesignTokens.Appearance.supportsDarkMode)
    }
}
