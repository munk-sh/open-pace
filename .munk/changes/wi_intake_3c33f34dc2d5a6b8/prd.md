# 回填 docs/verification-matrix.md 剩余 6 行（B/C 归属）+ 放宽结构守护测试

## 范围

- 只动两个文件：`docs/verification-matrix.md`（第 7–12 行，即 TTS / duck / GPX / 竖屏+iPhone-only / Dynamic Type / 设计 token+hero 间距）与 `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`。
- 断言名与反例名逐条从 main 上已交付的代码/门禁里取真实符号，禁止编造；6 行归属项保持「阶段 2 断言补齐 B / C」不变。
- 「现状」列写实测口径 + 阈值来源，让读者不翻 digest 也能看到依据。

## 验收

- ac-matrix-pending-zero: `docs/verification-matrix.md` 中 `pending: 待对应 item 回填` 出现次数为 0，且数据行数仍恰为 10。
- ac-matrix-six-rows-real-names: 后 6 行（TTS、duck、GPX、竖屏+iPhone-only、设计 token+hero 间距共 5 行）的「断言名」「反例」两列均为代码中真实存在的测试/门禁断言标识，且不含 `pending`。
- ac-dynamic-type-explicit-gap: Dynamic Type 行「现状」含 `缺口：本波未做（预算取舍）`，其「断言名」「反例」两列均为 `none（缺口）`，全表恰 1 行缺口、且缺口行不在 `pending` 之列。
- ac-tts-real-names: TTS 行「断言名」含 `testEachKilometerAnnouncedExactlyOnceInOrder`、`testResumeCatchUpEmitsAtMostOne`、`testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates`；「反例」含 `testResumeCatchUpDoesNotReplayEachMissingKilometer`。
- ac-duck-real-names: duck 行「断言名」含 `testEndAnnouncementRevokesDuckWhenActivationDucked`、`testEndAnnouncementSeparatesDeactivationFromDuckRevocation`、`testApplyingDefaultConfigurationReadsBackFromRealSession`；「反例」含 `testDuckRevokedDiffersFromSessionDeactivatedWhenActivationSkipsDuck`。
- ac-gpx-real-names-and-tolerance: GPX 行「断言名」含 `fixture-fields-match`、`red-proof-missing-ele`、`red-proof-namespace`、`testExportRoundTripPreservesEveryPoint`；「现状」同时出现 `1e-6`、`0.11 m/格`、`恰为 4`、`不设数量容差`。
- ac-portrait-real-names: 竖屏行「断言名」含 `ac-portrait-orientation-lock`；「现状」同时写出 `UISupportedInterfaceOrientations=UIInterfaceOrientationPortrait` 与 `TARGETED_DEVICE_FAMILY=1`，并注明源码 `project.yml` 与构建产物 `Info.plist` 双向实测。
- ac-design-token-threshold-source: 设计 token/hero 间距行「现状」同时出现 `80 = 2.5 × Spacing.xl`、`16 = Spacing.md`、`2026-11-11`（先定后测）；「断言名」含 `testPolicyThresholds` 与 `ac-design-tokens`。
- ac-guard-test-structure-kept: `DocsVerificationMatrixTests` 保留「表头逐字 / 恰 10 条接缝 / 6 列 / 非空单元格」结构断言，且仍能定位仓库根 `VERSION`。
- ac-guard-test-counts-updated: 守护测试断言 `pending == 0`、`缺口 == 1`、`实测 == 9`，并保留 10 条接缝逐条存在性检查（不再要求旧 6 项标 pending）。
- ac-swift-test-runCore-passes: `swift test`（工作目录 `ios/RunCore`）exit 0。
- ac-check-ios-shell-passes: `bash scripts/check-ios-shell.sh` exit 0。
- ac-scope-frozen: `git diff --name-only` 仅列出 `docs/verification-matrix.md` 与 `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`。

## 非目标

- 不改 `ios/PurePace/**` 生产代码（含 `RunLayoutBalancePolicy.swift`、`RunView.swift`、`DesignTokens.swift`）。
- 不改 `.github/workflows/ios.yml` 与 `.munk/code-gates.json`，不新增门禁。
- 不改前 4 行（`wi_intake_9738f1ec924207f9` 的 A 归属）内容。
- 不补 Dynamic Type 实现或新增动态字号断言（本波明确缺口）。
- 不新增/改写其他文档散文，不改 `docs/` 下其他文件。

## 实现约束

- 表结构冻结：表头逐字 `| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |`，分隔行保持，数据行恰 10 条、每行 6 列且单元格非空（守护测试按 `|` 切分后 cells.count == 8 校验）。
- 证据路径必须指向真实文件，建议落点：
  - TTS：`ios/RunCore/Tests/PurePaceRunCoreTests/AnnouncementSchedulerTests.swift`、`ios/PurePaceTests/AnnouncementSpeakerTests.swift`。
  - duck：`ios/PurePaceTests/AudioSessionAdapterTests.swift`、`ios/PurePaceTests/AnnouncementSpeakerTests.swift`。
  - GPX：`ios/RunCore/Tests/PurePaceRunCoreTests/RunGPXExporterTests.swift`、`ios/RunCore/Tests/PurePaceRunCoreTests/GPXCodecTests.swift`、`scripts/check-gpx-export.sh`（CI 由 `.github/workflows/ios.yml` lint 腿第 116 行执行）。
  - 竖屏+iPhone-only：`ios/project.yml`、`scripts/check-ios-shell.sh`。
  - Dynamic Type：`ios/PurePaceTests/DesignTokensTests.swift`（无动态字号断言）。
  - 设计 token/hero 间距：`ios/PurePace/Design/RunLayoutBalancePolicy.swift`、`ios/PurePaceTests/LocalizationPolicyTests.swift`、`ios/PurePaceTests/DesignTokensTests.swift`、`scripts/check-ios-shell.sh`。
- 已核实的真实符号（取自 main）：
  - TTS 调度：`testEachKilometerAnnouncedExactlyOnceInOrder`、`testDuplicateTickIsDebounced`、`testReadyAndPausedSuppressAnnouncements`、`testFinishedAnnouncesOnceThenStops`、`testFinishedWithoutCompletedKilometerEmitsNothing`、`testResumeCatchUpEmitsAtMostOne`、`testResumeCatchUpDoesNotReplayEachMissingKilometer`。
  - TTS 中断恢复：`testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates`。
  - duck/deactivate：`testApplyingDefaultConfigurationReadsBackFromRealSession`、`testEndAnnouncementDeactivatesWithNotifyOthersExactlyOnce`、`testEndAnnouncementSeparatesDeactivationFromDuckRevocation`、`testEndAnnouncementRevokesDuckWhenActivationDucked`、`testRepeatedBeginAnnouncementActivatesOnce`、`testInterruptionBeganThenResumeReappliesDefaultConfiguration`、`testInterruptionEndedWithoutResumeReturnsToInactiveWithoutActivation`、`testDuckRevokedDiffersFromSessionDeactivatedWhenActivationSkipsDuck`。
  - GPX 导出单测：`testExportRoundTripPreservesEveryPoint`、`testExportFilenameContainsUTCStartAndIDAndNeverOverwrites`、`testExportEmptySamplesThrowsAndWritesNoFile`；codec：`testEncodeUsesGPX11NamespacesAndTrackPointExtension`、`testRoundTripThroughRealFilePreservesEveryPoint`、`testDecodeRejectsNonGPX11DefaultNamespace`。
  - GPX 外部门禁断言 id：`fixture-fields-match`、`red-proof-missing-ele`、`red-proof-namespace`（脚本头部写明 1e-6 容差 ≈0.11 m/格、trkpt 恰 4 不设数量容差）。
  - 竖屏：`ac-portrait-orientation-lock`（self-test 反例名「横屏方向」「device family 2」「缺竖屏声明」）。
  - 布局：`testPolicyThresholds`、`testLegacyTopStackedLayoutFailsBothCriteria`、`testScreenshotLegacyLayoutFailsAllThreeGapCriteria`、`testFourStatesBalancedLayoutPasses`、`testRejectsLargeInterBlockHole`、`testRejectsAsymmetricWhitespaceEvenWhenGapsFit`、`testPolicyThresholdMatchesDesignToken`；门禁 `ac-design-tokens` 与 self-test「布局阈值改回 160/40」「缺首屏语义间距 token」「首屏余量未用语义间距」。
  - 阈值来源原文：digest §3「阈值在本轮代码实现开始前（2026-11-11 03:5x）写入」，`80 = 2.5 × Spacing.xl(32)`，`16 = Spacing.md`。
- 守护测试改造方向：把旧的 `measuredSeams`(4) / `pendingSeams`(6) 常量改为「10 条接缝逐条存在」+ 计数断言（pending 0 / 缺口 1 / 实测 9），缺口行以 `none（缺口）` 或 `缺口：` 识别；保留 `MatrixError`、`repoRoot()` 与结构断言。
- 预算 ≤2M token；若超预算则交半成品并在回执如实写明已完成/未完成行数与守护测试计数，不得虚报。

## 回执要求

交付说明中写明：改前 4 实测 + 6 pending → 改后 9 实测 + 1 显式缺口；守护测试计数（10 接缝 / pending 0 / 缺口 1 / 实测 9）；`swift test` 与 `bash scripts/check-ios-shell.sh` 的 exit code 与关键输出行。
