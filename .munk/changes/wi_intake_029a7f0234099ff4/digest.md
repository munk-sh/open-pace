# Coding 回执：V1.2 定稿唯一品牌橙与对比度豁免（wi_intake_029a7f0234099ff4）

- 代码提交：`6cb9b435d6fcbddd18f0e91f94c5fbd63bea1c7d`（仅本项 scope 内 7 个文件）。
- 旁挂 manifest：`docs/evidence/palette-a-contrast.sha256`（evidence sha256 + 上述 commit sha）。
- 未在本地跑全量 code_gates 作交付真值；Host 在下一阶段执行。以下为本项自测与快速门的实跑命令与退出码。

## 1. 变更面

```
$ git diff --stat HEAD~1 HEAD
 docs/design/palette-a.md                    | 29 +++-
 docs/evidence/palette-a-contrast.txt        | 69 ++++----
 ios/PurePace/Design/ContrastPolicy.swift    | 38 ++++-
 ios/PurePace/Design/DesignTokens.swift      | 19 ++-
 ios/PurePaceTests/ContrastPolicyTests.swift | 149 ++++++++++++++++-
 ios/PurePaceTests/DesignTokensTests.swift   | 250 +++++++++++++++++++++++++++-
 scripts/check-ios-shell.sh                  | 21 ++-
 7 files changed, 513 insertions(+), 62 deletions(-)
```

## 2. ac-* 逐项

### ac-accent-single-orange / ac-onaccent-single-deep / ac-accentsoft-light-recomputed / ac-palette-shape-frozen

- 命令：`bash scripts/test-ios.sh --unit-only`，退出码 0。
- 关键输出：`PurePaceTests ... Executed 262 tests, with 0 failures`；`PurePaceRunCoreTests ... Executed 173 tests, with 0 failures`；日志 `.build/logs/xcodebuild-unit.log`。
- 断言落点：`DesignTokensTests.testAccentIsSingleBrandOrangeInBothSchemes`（H22.8/S100/L68.0、排除 `0xB4400B`/`0xE85D04`、第二套橙扫描）、`testOnAccentSingleDeepInBothSchemes`（8.44±0.01、light/dark 同值、白字反例判红）、`testAccentSoftLightRecomputedAndDarkFrozen`（`0xFFECE0`、旧 `0xFCEFE7` 判红）、`testPaletteShapeFrozenAfterSingleOrange`（18 键 / 36 槽位 / 仅 accent+onAccent 同值、surface 同值与缺键反例判红）。
- 同 commit 反例均以「构造 palette 副本」实现，不改生产代码即可判红。

### ac-danger-one-pass-separation / ac-danger-semantics / ac-dark-danger-red

- `DesignTokensTests.testDangerKeepsValuesAfterSinglePassSeparation`（light `0x660D09` 0 档调整、dark `0xF53A48`、ΔL 46.27pp、ΔH 27.31°、白字 vs dark danger 3.76<4.5 反例）、`testDangerSemanticsDescribeSolidDestructivePrimaryAction`（旧「仅出现在确认层文本或描边按钮」判红）、`testDarkDangerIsVividRedNotWarmOrange`。
- 语义文本：`purposes["danger"]` 与 `Colors.danger` 注释均为「确认层实心破坏性主操作（丢弃）+ 无填充次操作（C2 图标式紧凑版）」。

### ac-ondanger-matrix-pair

- `ContrastPolicyTests.testOnDangerPairIsSingleBodyTierAndMeasured`：矩阵中 `onDanger/danger` 恰 1 条、tier `.body`、minimum == bodyThreshold，light 12.9114 / dark 4.9479。
- `ContrastPolicyTests.testThresholdsAndMatrixSizeUnchanged`：`bodyThreshold 4.5` / `largeThreshold 3.0` / `decorativeThreshold 1.10` / `pairMatrix.count 37`。
- `ContrastPolicy.swift` L62-L64 注释写明「实心按钮文字按正文/小字 4.5」与 dark 保留深字 `onDanger`（白字仅 3.76）的推导。

### ac-brand-exemption-scoped / ac-exemption-not-formula

- `ContrastPolicyTests.testBrandExemptionRegistryIsExactlySixLightAccentPairs`：登记表恰 6 条、名称与实测值逐条对齐真实矩阵、无 dark 条目。
- `testClearingExemptionsTurnsAllSixPairsRed`：`problems(for:exemptions: [])` 后恰 6 条判红且名字集合相等。
- `testRemovingOneExemptionTurnsThatPairRed`：删 1 条 → 恰 1 条判红。
- `testUnregisteredLowContrastSyntheticPairStaysRed`：未登记 synthetic 低对比对仍判红。
- 豁免为 `ContrastPolicy.brandPriorityExemptions` 显式登记；`problems` 仍对每条真算比值，阈值与 37 对零改动（见上条断言）。

### ac-no-other-hex-drift

```
$ git diff HEAD~1 HEAD -- ios/PurePace/Design/DesignTokens.swift | grep -E '^[-+].*SRGB\(hex'
-  "accent": ... light: 0xB4400B ... dark: 0xFF9A5C
-  "onAccent": ... light: 0xFFFFFF ... dark: 0x2A1206
-  "accentSoft": ... light: 0xFCEFE7 ... dark: 0x3A1F12
+  "accent": ... light: 0xFF9A5C ... dark: 0xFF9A5C
+  "onAccent": ... light: 0x2A1206 ... dark: 0x2A1206
+  "accentSoft": ... light: 0xFFECE0 ... dark: 0x3A1F12
```

仅 3 个 light 槽位变化，其余 33 hex 未触碰（dark 行均为上下文不变）。

### ac-token-tests-red-both-ways / ac-contrast-tests-single-orange

- 旧口径断言改为同值口径：`testKnownRatiosMatchReferenceValues` 中 light `onAccent/accent` 5.71→8.44、light `accent/background` 5.47→2.0049（并入豁免），dark 8.44 保留。
- 反例覆盖旧 `0xB4400B` / `0xFFFFFF` / `0xFCEFE7` / 白字 vs dark danger / 未登记低对比对 / 删登记项 / 非白名单同值，均判红且不依赖改生产代码。

### ac-gate-execution-sync

```
$ bash -n scripts/check-ios-shell.sh                # 退出码 0
$ bash scripts/check-ios-shell.sh                   # 退出码 0，33 项断言，0 项失败
$ bash scripts/check-ios-shell.sh --self-test       # 退出码 0，95 项断言（原 92 + 新增 3），0 项失败
```

新增/更新夹具：accent/onAccent 同值白名单绿例、accent 回退设计稿候选/压暗橙红例（原因串含「方向 A 表不一致」）、非白名单 `surface` 同值红例（原因串含「色对」）。期望表 3 个新值已同步，对比度阈值与 pair 数不在该门内、未触碰。

### ac-evidence-overwritten / ac-evidence-bound

- `docs/evidence/palette-a-contrast.txt` 同名覆盖：74 行 `scheme pair fg bg ratio threshold`（4 位小数），附「品牌优先豁免」6 条段与「矩阵来源/公式/阈值来源」口径段。
- 现场重算比对（python3 解析 `DesignTokens.swift` + `ContrastPolicy.pairMatrix` 后按 WCAG 复算，逐行比对证据文件）：`rows 74 mismatches 0`。
- 旁挂 manifest 与校验：

```
$ cd docs/evidence && shasum -a 256 -c palette-a-contrast.sha256
palette-a-contrast.txt: OK            # 退出码 0
$ git show 6cb9b435d6fcbddd18f0e91f94c5fbd63bea1c7d:ios/PurePace/Design/DesignTokens.swift | grep accent
            "accent": ColorPair(light: SRGB(hex: 0xFF9A5C), dark: SRGB(hex: 0xFF9A5C)),
            "onAccent": ColorPair(light: SRGB(hex: 0x2A1206), dark: SRGB(hex: 0x2A1206)),
            "accentSoft": ColorPair(light: SRGB(hex: 0xFFECE0), dark: SRGB(hex: 0x3A1F12)),
```

### ac-doc-palette-sync

- `docs/design/palette-a.md` 18×2 表同步（accent 两侧 `#FF9A5C`、onAccent 两侧 `#2A1206`、accentSoft light `#FFECE0`），新增「品牌优先豁免（V1.2 唯一豁免族）」段与定稿来源。

### ac-no-fallback-enabled / ac-scope-frozen

- `DesignTokens.swift` 注释写明「同色相更深一档（H 22–26）仅作 fallback，必须人看过拍板后才可启用，本轮未启用」，palette 无第二套橙（单测橙区间扫描断言仅命中 `accent.light` / `accent.dark`）。
- 变更路径仅 scope 内 7 文件 + 本回执 + manifest；未动视图 / UI 测试 / 截图 / identifier / VERSION / Info.plist / `.munk/code-gates.json`。

## 3. 其他快速门（非交付真值）

```
$ bash scripts/check-ios-scripts.sh   # 退出码 0，34 项断言，0 项失败
$ bash scripts/check-baseline.sh      # 退出码 0，12 项断言，0 项失败
```

## 4. 未闭合 / 风险

- `ios/PurePace/Run/RunView.swift` 仍有 `Colors.accent` 作正文/链接前景（约 L345/L409/L419），浅色下约 2.00:1；本项只登记豁免与补偿约束，视图修正归下一子项。
- 全量 `code_gates` 由 Host 在上一阶段之后执行；本回执不宣称其结论。
