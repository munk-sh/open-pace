# Domain: ios-dynamic-type

首屏主操作区在**最大辅助字号档 AX5**（SwiftUI `.dynamicTypeSize = .accessibility5` / UIKit `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`）下的可及几何判定域。做法是「纯函数 + 注入几何」：字号与文案理想尺寸在测试侧用 `UIFontMetrics` / `NSString.size(withAttributes:)` 解析后注入 `ios/PurePace/Design/` 下的无状态策略，Design 层不引入 UIKit、不做运行态测量、不靠截图取色判读。同一域闭合 `docs/verification-matrix.md` 的最后一行缺口（Dynamic Type）。声明口径：生产侧 `Typography.control` 仍为固定 20pt 档（不随 Dynamic Type 缩放），本域断言属**注入式几何断言**，不代表运行态 AX5 渲染已实测，也不得写成真机结论。

## 范围

- `ios/PurePace/Design/PrimaryActionLayoutPolicy.swift`：additive 扩展 `AccessibilityGeometry`（`actionFrame` / `contentBottom` / `availableTop` / `availableBottom` / `textSize` / `textInsets`）、`AccessibilityEvaluation`（`height` / `contentGap` / `textArea` / `issues` / `passes`）、`AccessibilityIssue`（`heightBelowMinimum` / `overlapsUpperContent` / `exceedsAvailableHeight` / `textTruncated`）、`evaluateAccessibilityLayout(_:tolerance:)`、`textArea(for:insets:)` 与 `layoutTolerance`；既有 `evaluate(actionFrame:tabBarFrame:)`、`minimumActionHeight` 签名与语义零改动。
- `ios/PurePaceTests/DynamicTypeLayoutTests.swift`（新增）：6 条正例（`testAX5PrimaryActionMeetsMinimumTapTarget` / `testAX5PrimaryActionDoesNotOverlapUpperContent` / `testAX5PrimaryActionIsNotClipped` / `testAX5PrimaryActionTextIsNotTruncated` / `testAX5ThresholdsArePinnedBeforeMeasurement` / `testAX5TypographyBaselineComesFromTitleSizeToken`）+ 4 条反例（`testFixed32ptActionHeightCounterexample` / `testCompressedAvailableHeightCounterexample` / `testOverlapWithUpperContentCounterexample` / `testStaticMinimumHeightTruncatesAX5TextCounterexample`）。
- `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`：计数断言由 `pending 0 / 缺口 1 / 实测 9` 改为 `pending 0 / 缺口 0 / 实测 10`，并断言 Dynamic Type 行只含真实符号与真实证据路径。
- `docs/verification-matrix.md`：仅「Dynamic Type」行的「现状 / 断言名 / 反例 / 证据路径 / 归属项」改写为本项实测口径；其余 9 行逐字不动，表头与 6 列结构不变。
- 未改生产布局：`RunView` 主操作区本项未动（判定在注入几何上即已判绿，无需 token 级收敛）。

## 验收

- ac-ax5-min-height: AX5 判定入口在 `.accessibility5` 档、以 `UIFontMetrics`（`UIContentSizeCategory.accessibilityExtraExtraExtraLarge`）解析主操作文案行高推出的需求高度上判定通过，且该需求高度 ≥ `minimumActionHeight`；单测同时锁定 `PrimaryActionLayoutPolicy.minimumActionHeight == DesignTokens.minTapTarget == 44`，不新增第二个 44 字面量。
- ac-ax5-no-overlap: 同一 AX5 几何判定通过且 `actionFrame.minY >= contentBottom`（容差 0.5pt）；反例把 `contentBottom` 抬到主操作上沿之上时必须返回失败并带 `overlapsUpperContent` 问题项。
- ac-ax5-no-clip: 同一 AX5 几何判定通过且 `actionFrame.maxY <= availableBottom`、`actionFrame.minY >= availableTop`（容差 0.5pt）；反例把可用高度压缩到放不下主操作时必须判红并带 `exceedsAvailableHeight` 问题项；不允许「静默裁剪也算通过」。
- ac-ax5-text-not-truncated: 文案在 AX5 解析字体下的理想尺寸（`NSString.size(withAttributes:)` 或等价布局度量，纯单测内计算）必须 `width <= textArea.width` 且 `height <= textArea.height`（`textArea = actionFrame` 内缩注入的横 / 纵内边距）；反例把可用文字区压到小于 AX5 理想高度时必须判红并带 `textTruncated`。
- ac-ax5-single-source-thresholds: 全部阈值与口径（44pt = Apple HIG 最小点按区、不重叠 = `minY >= contentBottom`、不裁剪 = `maxY <= availableBottom` 且 `minY >= availableTop`、容差 0.5pt）在实现前以源码注释写死并注明设定日期（2026-11-11）与依据；单测断言策略常量与 `DesignTokens` 对齐；阈值不得在判红后回调。
- ac-ax5-counterexamples-red: 同 commit 至少 2 条反例各自独立判红（`passes == false` 且命中对应问题项），且只通过传入错误输入判红：`testFixed32ptActionHeightCounterexample`（按钮固定 32pt 高）、`testCompressedAvailableHeightCounterexample`（可用高度压缩）；每条反例与正例共用同一策略实现，禁止靠改生产代码才红。
- ac-ax5-identifiers-frozen: `bash scripts/check-ios-shell.sh` 的可及 identifier 冻结清单仍为 33 项且与现状 diff = 0；本项不新增、不改名、不删除任何 `accessibilityIdentifier`。
- ac-matrix-dynamotype-measured: `docs/verification-matrix.md` 的「Dynamic Type」行「现状」列改为本项实测口径（不再出现 `缺口` / `none（缺口）`），「断言名」「反例」「证据路径」「归属项」列填真实符号（`DynamicTypeLayoutTests.swift` + `PrimaryActionLayoutPolicy.swift`）；表格其余 9 行逐字不变；`DocsVerificationMatrixTests` 的表头逐字 / 恰 10 条接缝 / 6 列非空断言保持通过，计数断言为 `pending 0 / 缺口 0 / 实测 10`。
- ac-gates-green: `bash scripts/test-ios.sh --unit-only` 的 `-only-testing:PurePaceTests` 腿通过（`.build/logs/xcodebuild-unit.log` 含 Executed 摘要）；`swift test --package-path ios/RunCore`（含矩阵守护）、`check-ios-shell.sh`、`check-ios-core.sh`、`check-ios-scripts.sh`、`check-baseline.sh` 均退 0。
- ac-scope-frozen: `git diff --name-only` 只含 `ios/PurePace/Design/PrimaryActionLayoutPolicy.swift`、`ios/PurePaceTests/DynamicTypeLayoutTests.swift`、`ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`、`docs/verification-matrix.md` 四个文件；不改 `ios/project.yml`、不改 `.github/workflows/*`、不改 `.munk/code-gates.json`、不改 `RunSessionViewModel` / `RunCore` 业务逻辑、不新增第三方依赖。
- ac-no-new-style-literals: 新增几何数值只引用既有 `DesignTokens`（`Spacing` / `Radius` / `minTapTarget`）与常量注入；`check-ios-shell.sh` 的样式字面量扫描（`.system(size:数字`、`.padding(数字`、`minHeight: 数字`、字面色值、零散字体修饰符）保持零命中。

## 非目标

- 不做真机结论；任何「真机已验证」表述禁止，真机类验收项保持 `pending: 待人现场`。
- 不出 Release 候选包、不跑归档 / 导出 / 公证。
- 不做主题系统、不引入自定义字体资产管线、不改配色与字号阶梯。
- 不改 CI workflow、不新增 gate、不改 `.munk/code-gates.json`。
- 不引入第三方依赖或跨端框架。
- 不重做旋转 / size class 断言（竖屏 + iPhone-only 单设备为既定前提）。
- 不做现场测量 App 运行态的黑盒用例（不写 XCUITest 测量版、不做截图取色判读）。
- 不扩范围去修 History / Settings / RunDetail 的 AX5 布局；不把 `Typography.control` 改为 Dynamic Type 缩放字体。

## 实现约束

- **纯函数优先**：判定在 `ios/PurePace/Design/` 下、只依赖 `Foundation` / `CoreGraphics` 的无状态 `enum` 策略，参数化「可用高度 + 内容底沿 + 主操作 frame + 文案理想尺寸」；UIKit 度量只在测试侧解析后注入，避免 Design 层引入 UIKit 依赖，也避免现场测量。
- **AX5 需求高度来源**：字号基线取 `DesignTokens.Typography.titleSize`（`Typography.control` 字号 20），由 `UIFontMetrics(forTextStyle:)` 在 `accessibilityExtraExtraExtraLarge` 下 `scaledValue` 得出；单测锁定基线等于 token，不得手调缩放比。
- **可用宽度来源**：固定目标设备 iPhone 16 竖屏逻辑宽 393pt − 左右 `Spacing.md`（16 × 2）= 361pt；来源写进测试注释（与 `scripts/test-ios.sh` 的 `platform=iOS Simulator,name=iPhone 16` 一致），不得用运行态实测。
- **反例纪律**：反例与正例共用同一策略实现，差异只在输入；反例断言具体问题项，避免「任一条红即通过」。
- **既有行为不动**：`evaluate(actionFrame:tabBarFrame:)` 已被 UI 用例使用，签名与语义保持不变，新能力走 overload / 新类型 additive 加入。
- **最小布局修正**：仅当判定确实现红且原因落在 `RunView` 主操作区时，才允许用既有 `DesignTokens` 做 token 级收敛并写明理由；本项判定未红，故未改生产布局。
- **阈值先定后测**：44 / 不重叠 / 不裁剪 / 0.5pt 容差于 2026-11-11 实现前写入策略注释，判红后未回调。
- **证据路径**：`ios/PurePaceTests/DynamicTypeLayoutTests.swift`、`ios/PurePace/Design/PrimaryActionLayoutPolicy.swift`、`docs/verification-matrix.md`。

## 最近交付证明

- workItemId: wi_intake_1adb1c339093ec57（2026-11-11，pass，AX5 主操作几何断言 + 验证矩阵收口）
- 交付：`PrimaryActionLayoutPolicy` additive 出 AX5 注入式判定（44pt 高度 / 不重叠 / 不裁剪 / 文案不截断，容差 0.5pt），`DynamicTypeLayoutTests` 6 正例 + 4 反例（含固定 32pt 高与可用高度压缩两条必做反例）；`docs/verification-matrix.md` Dynamic Type 行由 `none（缺口）` 改为本项实测口径，矩阵终态 10 行实测 + 0 缺口；`DocsVerificationMatrixTests` 计数断言改为 `pending 0 / 缺口 0 / 实测 10` 并锁定 Dynamic Type 行真实符号。
- 验证：`code_gates` 22 门 attempt 001 全绿（含 `test-ios` 的 `-only-testing:PurePaceTests`、`test-ios-run-core` 的 `swift test`、`lint-ios-shell` identifier 冻结 33 项）。口径限制：生产 `Typography.control` 仍固定 20pt 档，本项是注入几何断言，非运行态 AX5 渲染实测，真机与现场测量仍待人工。
