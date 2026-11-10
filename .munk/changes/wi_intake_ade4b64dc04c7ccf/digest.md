# digest — 跑步页三态指标区垂直居中 + 空白可机器判红断言

- WorkItem: `wi_intake_ade4b64dc04c7ccf`
- 基线: `6512fba`（前项 `wi_intake_41e9dc65e08c5971` / `7195b54`）
- 日期: 2026-11-11
- 设备/运行时: iPhone 16（UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`，iOS 18.6），Xcode 26.3（17C529）

## 1) 布局改动

- `ios/PurePace/Run/RunView.swift`：指标内容块（距离/用时/当前配速/平均配速/分段/提示/已保存）抽为 `metricsContent`，
  放进 `ViewThatFits(in: .vertical)` 的首选分支 `VStack { Spacer(minLength: .md); metricsContent; Spacer(minLength: .md) }`，
  在「导航栏下沿 → 底部控制区上沿」之间整体垂直居中；小屏/大字号溢出时退回 `ScrollView`，不截断内容。
- `safeAreaInset(edge: .bottom)` 底部控制区、`padding(.vertical, .sm)`、主操作 `minHeight: DesignTokens.minTapTarget`（44pt）
  与 TabBar 间距保持不变；`DesignTokens.swift` 零 diff（取值只用 `Spacing.md/.sm/.xs/.xxs`）。
- DEBUG 门控的 `run.telemetry` 遥测摘要改为内容区底部 overlay（非用户可见文案，不参与指标区居中），
  否则保存态下这段诊断文本会把指标块顶离中心（首次 UI 实测上下差 59pt）。

## 2) 新增断言 `ac-run-metrics-balanced`

- 纯函数：`ios/PurePace/Design/RunLayoutBalancePolicy.swift`（无 SwiftUI 依赖，`Evaluation` + `problems` + `passes`），
  阈值单点定义 `maximumGap = 160`、`maximumImbalance = 40`。
- `ios/project.yml`：`PurePaceUITests.sources` 追加 `PurePace/Design/RunLayoutBalancePolicy.swift`（与既有三个 Policy 并列）；
  `ios/PurePace.xcodeproj` 由 `xcodegen generate` 重新生成（未手改 `project.pbxproj`）。
- 单测：`ios/PurePaceTests/LocalizationPolicyTests.swift` D 段
  - `testLegacyTopStackedLayoutFailsBothCriteria`：旧布局实测（内容 177.7–447.4、导航栏下沿 149.7、主操作顶边 699.0）
    → 顶部 28 / 底部 251.6 / 最大空洞 251.6 / 上下差 223.6，`problems.count == 2`（两条判据都判红）。
  - `testCenteredLayoutPassesBothCriteria`：同一内容块整体下移 111.8pt → 上下各 139.8、最大空洞 139.8、上下差 0，通过。
  - `testRejectsAsymmetricWhitespaceEvenWhenGapsFit`：上 10 / 下 100 → 单洞未超 160 但上下差 90 判红（判据 b 独立可红）。
  - `testRejectsMissingContent`：空采集判红。
  - `testPolicyThresholds`：160 / 40 单点常量。
- UI 用例：`ios/PurePaceUITests/RunFlowUITests.swift`
  `testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 内新增 `assertRunMetricsBalanced(...)`，
  依次在未开始、运行中、保存态采集 `run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` /
  `run.backgroundDegraded`（存在时）/ `run.saved`（存在时）+ 当态主操作的真实 frame，
  上界 `app.navigationBars.firstMatch.frame.maxY`，喂给同一 `RunLayoutBalancePolicy`。

## 3) 生成命令

```bash
# 工程生成（project.yml 为唯一真源）
cd ios && xcodegen generate

# L1 单测（含 ac-run-metrics-balanced 反例/正例）
xcodebuild test -only-testing:PurePaceTests/LocalizationPolicyTests -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'

# L2 UI 用例 + 证据附件（5 图 6 树）
cd ios && xcodebuild test \
  -only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction \
  -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -resultBundlePath /var/folders/hn/rqf4yrcj4yn53l0vghdcgjcr0000gn/T/opencode/run-metrics-4/RunMetrics.xcresult

# 附件导出 → 同名覆盖
xcrun xcresulttool export attachments \
  --path /var/folders/hn/rqf4yrcj4yn53l0vghdcgjcr0000gn/T/opencode/run-metrics-4/RunMetrics.xcresult \
  --output-path /var/folders/hn/rqf4yrcj4yn53l0vghdcgjcr0000gn/T/opencode/run-metrics-4/attachments
# manifest.json 的 suggestedHumanReadableName 去掉 `_0_<uuid>` 后缀即目标文件名：
#   run-not-started/run-running/history-detail/history-empty/settings → docs/screenshots/<name>.png
#   01-run-not-started … 06-tabs → docs/evidence/a11y/<name>.txt
```

## 4) 四条断言通过日志（同一 UI 用例，exit=0，`** TEST SUCCEEDED **`）

```
Test Case '-[PurePaceUITests.RunFlowUITests testZhHansCopyDatesAndBottomAnchoredPrimaryAction]' started.
ac-visible-copy-zh-hans 跑步页（未开始）: labels=18 violations=0
ac-primary-action-bottom-anchored 未开始: height=58.0 bottomGap=12.0
ac-run-metrics-balanced 未开始: top=139.83333333333334 bottom=139.83333333333326 largest=139.83333333333334 imbalance=8.526512829121202e-14
ac-visible-copy-zh-hans 历史空态: labels=8 violations=0
ac-visible-copy-zh-hans 跑步页（运行中）: labels=19 violations=0
ac-primary-action-bottom-anchored 运行中: height=58.0 bottomGap=12.0
ac-run-metrics-balanced 运行中: top=139.83333333333334 bottom=139.83333333333326 largest=139.83333333333334 imbalance=8.526512829121202e-14
ac-visible-copy-zh-hans 跑步页（保存态）: labels=19 violations=0
ac-primary-action-bottom-anchored 保存态: height=58.0 bottomGap=12.0
ac-run-metrics-balanced 保存态: top=119.83333333333334 bottom=119.83333333333337 largest=119.83333333333337 imbalance=2.842170943040401e-14
ac-visible-copy-zh-hans 历史列表: labels=10 violations=0
ac-run-detail-date-zh-hans started="2026年11月11日 02:54:09" ended="2026年11月11日 02:54:14"
ac-visible-copy-zh-hans 跑次详情: labels=22 violations=0
ac-visible-copy-zh-hans 设置页: labels=11 violations=0
Test Case '-[PurePaceUITests.RunFlowUITests testZhHansCopyDatesAndBottomAnchoredPrimaryAction]' passed (40.267 seconds).
** TEST SUCCEEDED **
```

L1 单测（反例判红证据）：

```
Test Case '-[PurePaceTests.LocalizationPolicyTests testLegacyTopStackedLayoutFailsBothCriteria]' passed
Test Case '-[PurePaceTests.LocalizationPolicyTests testCenteredLayoutPassesBothCriteria]' passed
Test Case '-[PurePaceTests.LocalizationPolicyTests testRejectsAsymmetricWhitespaceEvenWhenGapsFit]' passed
Test Case '-[PurePaceTests.LocalizationPolicyTests testRejectsMissingContent]' passed
Test Case '-[PurePaceTests.LocalizationPolicyTests testPolicyThresholds]' passed
Test Suite 'LocalizationPolicyTests' passed
	 Executed 13 tests, with 0 failures (0 unexpected) in 0.015 seconds
** TEST SUCCEEDED **
```

## 5) 三态实测空洞（本轮真实 UI frame，iPhone 16 / iOS 18.6）

| 状态 | 顶部留白 | 底部留白 | 最大单一垂直空洞 | 上下差 | 判据（≤160 / ≤40） |
|---|---|---|---|---|---|
| 未开始 `.ready` | 139.83pt | 139.83pt | 139.83pt | ≈0 | 通过 |
| 运行中 `.running` | 139.83pt | 139.83pt | 139.83pt | ≈0 | 通过 |
| 保存态 `didSave` | 119.83pt | 119.83pt | 119.83pt | ≈0 | 通过 |

- 未开始（可及树 `01-run-not-started.txt`）：`run.distance` y=289.5（导航栏下沿 149.7）、
  `run.backgroundDegraded` 底边 559.2、`run.start` 顶边 699.0（高 58.0）。
- 旧布局反例（本轮基线实测，写进 L1 单测）：内容 177.7–447.4、顶部 28、底部 251.6、上下差 223.6 → 两条判据均红。

## 6) 证据文件 sha256（同名覆盖）

```
a02184420ef382d7a5f6d7d82dbbd068f16bf9daef7c0527992a3c8b58b532da  docs/screenshots/history-detail.png
3719ab91422d959eec4ad2dfdd77fed86d03ac8adb5941c1f8f707af4ac279ef  docs/screenshots/history-empty.png
6aee97ba96932f810450f27856de5757e926b6ca5ed932585aa7951dd41c5c95  docs/screenshots/run-not-started.png
86dd0f2e056a55ec3d893563f3b87c139d18d8e672d84b46ef9b36adeaf3af0c  docs/screenshots/run-running.png
aa88668606352dad57cefd2157bed20c6d543d250685ab0469093101d7759373  docs/screenshots/settings.png
757672dca264ef600ccb0613cde7b1bfcfbc129160f8a5d777c7760e51cb2e9a  docs/evidence/a11y/01-run-not-started.txt
161508e91a5e0db74df260d9759fb632c14e3872a8b180f6a8819f0483304963  docs/evidence/a11y/02-run-running.txt
16a9513ba1e5b71764e794bf18afc5f0f45d078f26cc34fa216d6eae58b6bff0  docs/evidence/a11y/03-history-empty.txt
7cdd44084281846faa93d4cc16f7f939cee9bfa3caee30be17e92b28ea24fbdf  docs/evidence/a11y/04-history-detail.txt
78f5582e1ecbdb773cd917d777d315915335e255fc787a3ff3e728549cac549b  docs/evidence/a11y/05-settings.txt
5859a7ccedbac675cce3f9bc609cd8355981ccb17bc5eb982b69e5358e5f241d  docs/evidence/a11y/06-tabs.txt
```

## 7) diff 范围

- 布局：`ios/PurePace/Run/RunView.swift`
- 断言：`ios/PurePace/Design/RunLayoutBalancePolicy.swift`（新增）、`ios/PurePaceTests/LocalizationPolicyTests.swift`、
  `ios/PurePaceUITests/RunFlowUITests.swift`、`ios/project.yml`
- 证据：`docs/screenshots/*.png`（5）、`docs/evidence/a11y/*.txt`（6）、本 digest
- 未触碰：`DesignTokens.swift`、本地化/日期/identifier/状态机/定位/音频/TTS/GPX/持久化/CI、Android、`shared/`、`ios/Core`、`ios/RunCore`、`Harness/`

## 8) 本轮自检补充

- 首次 UI 跑（未加 overlay 前）保存态实测 top=90.3 / bottom=149.3（上下差 59pt）判红，根因是 DEBUG `run.telemetry`
  诊断文本在指标 VStack 内占位；改为内容区底部 overlay 后保存态回到 119.83 / 119.83。反例证明该断言可反向失败。
- 结构门禁旁证：`bash scripts/check-ios-shell.sh` 28 项断言 0 失败（首跑曾报 `CoreGraphics` import 与 `spacing: 0`
  样式字面量两处，已分别改为 `import Foundation`、`VStack {}` 默认间距）；`bash scripts/check-baseline.sh`、
  `check-ios-scripts.sh`、`check-shell-expansion.sh` 均通过。
