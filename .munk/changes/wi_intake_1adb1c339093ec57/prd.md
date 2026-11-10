# Dynamic Type 最大档（AX5）主操作几何断言 + 验证矩阵回填

## 范围

闭合 `docs/verification-matrix.md` 唯一的缺口行「Dynamic Type」：为最大辅助字号档（SwiftUI `.dynamicTypeSize = .accessibility5`，即 AX5；UIKit 侧等价 `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`）补一组**可注入几何、纯函数、能判红**的断言，并同步矩阵该一行。

范围只含四件产出的文件：
1. `ios/PurePace/Design/PrimaryActionLayoutPolicy.swift`（additive 扩展：新增 AX5 几何判定入口 / 依赖类型；既有 `evaluate(actionFrame:tabBarFrame:)` 签名与语义零改动）。
2. `ios/PurePaceTests/DynamicTypeLayoutTests.swift`（新文件：AX5 正向断言 + ≥2 条独立反例）。
3. `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`（矩阵结构守护的计数断言：`9 实测 + 1 缺口` → `10 实测 + 0 缺口`）。
4. `docs/verification-matrix.md`（仅「Dynamic Type」一行改为本项实测；其余行逐字不动）。

判定口径（三条必做）在 AX5 下同时成立：
- ① 首屏主操作按钮实际高度 ≥ 44pt（`DesignTokens.minTapTarget`，Apple HIG 最小点按区）。
- ② 主操作与其上方指标 / 提示区不重叠，且整体完整落在可用高度内（上下沿都在可用区间内，不被裁剪）。
- ③ 主操作文案不被截断：以文案理想尺寸（AX5 字体下的布局尺寸）与按钮内可用文字区比较，不靠像素取色、不靠截图人工判读。

## 验收

- ac-ax5-min-height: `PrimaryActionLayoutPolicy` 新增的 AX5 判定入口在 `.accessibility5` 档、以 `UIFontMetrics`（`UIContentSizeCategory.accessibilityExtraExtraExtraLarge`）解析出的主操作文案行高推出的需求高度上判定通过，且该需求高度 ≥ `minimumActionHeight`；单测同时锁定 `PrimaryActionLayoutPolicy.minimumActionHeight == DesignTokens.minTapTarget == 44`（不新增第二个 44 字面量）。

- ac-ax5-no-overlap: 同一 AX5 几何下判定通过且满足 `actionFrame.minY >= contentBottom`（容差 0.5pt）；反例输入把 `contentBottom` 抬到主操作上沿之上时，判定必须返回失败并带「重叠」问题项。

- ac-ax5-no-clip: 同一 AX5 几何下判定通过且满足 `actionFrame.maxY <= availableBottom` 与 `actionFrame.minY >= availableTop`（容差 0.5pt）；反例输入把可用高度压缩到放不下主操作时，判定必须返回失败并带「超出可用高度 / 裁剪」问题项。不允许出现「静默裁剪也算通过」。

- ac-ax5-text-not-truncated: 主操作文案在 AX5 解析字体下的理想尺寸（`NSString.size(withAttributes:)` 或等价布局度量，纯单测内计算）必须 `requiredSize.width <= availableSize.width` 且 `requiredSize.height <= availableSize.height`（`availableSize = actionFrame` 内缩既有横/纵内边距）；反例把可用文字区压到小于 AX5 理想高度时必须判红。

- ac-ax5-single-source-thresholds: 所有阈值与口径（44pt = HIG 最小点按区、不重叠 = `minY >= contentBottom`、不裁剪 = `maxY <= availableBottom` 且 `minY >= availableTop`、容差 0.5pt）在**实现前**以源码注释写死在策略文件中，并注明设定日期与依据；单测断言策略的常量与 `DesignTokens` 对齐。阈值不得在判红后回调（digest 记录「阈值定于何时、依据什么」）。

- ac-ax5-counterexamples-red: 同一 commit 内至少 2 条反例测试，各自独立判红（`passes == false` 且命中对应问题项），且只通过传入错误输入判红：`testFixed32ptActionHeightCounterexample`（按钮固定 32pt 高）、`testCompressedAvailableHeightCounterexample`（可用高度压缩到放不下主操作）；每条反例与正例使用同一个策略实现，禁止靠改生产代码才红。

- ac-ax5-identifiers-frozen: `bash scripts/check-ios-shell.sh` 的可及 identifier 冻结清单仍为 33 项且与现状 diff = 0；本次不新增、不改名、不删除任何 `accessibilityIdentifier`。

- ac-matrix-dynamotype-measured: `docs/verification-matrix.md` 的「Dynamic Type」行「现状」列改为本项实测口径（不再出现 `缺口` / `none（缺口）`），「断言名」「反例」「证据路径」「归属项」列填本项真实符号（新测试文件与策略文件路径）；表格其余 9 行逐字不变；`DocsVerificationMatrixTests` 的结构断言（表头逐字 / 恰 10 条接缝 / 6 列非空）保持通过，计数断言改为 `pending 0 / 缺口 0 / 实测 10`。

- ac-gates-green: `bash scripts/test-ios.sh --unit-only` 的 `-only-testing:PurePaceTests` 腿通过（日志 `.build/logs/xcodebuild-unit.log` 含 Executed 摘要）；`swift test --package-path ios/RunCore`（含矩阵守护测试）、`bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-core.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-baseline.sh` 均退 0。

- ac-scope-frozen: `git diff --name-only` 只含上述 4 个文件；不改 `ios/project.yml`（尤其 `CODE_SIGNING_ALLOWED` / 签名相关项）、不改 `.github/workflows/*`、不改 `.munk/code-gates.json`、不改 `ios/PurePace/Run/RunView.swift` 以外的业务逻辑（`RunSessionViewModel` / `RunCore` / 定位 / 音频 / GPX / 历史 / 设置）、不新增第三方依赖。

- ac-no-new-style-literals: 新增几何数值只引用既有 `DesignTokens`（`Spacing` / `Radius` / `minTapTarget`）与常量注入；`scripts/check-ios-shell.sh` 的样式字面量扫描（`.system(size:数字`、`.padding(数字`、`minHeight: 数字`、字面色值、零散字体修饰符）保持零命中。

## 非目标

- 不做真机结论：本项不涉及真机，任何「真机已验证」表述禁止；真机类验收项仍保持 `pending: 待人现场`。
- 不出 Release 候选包、不跑归档/导出/公证。
- 不做主题系统、不引入自定义字体资产管线、不改配色与字号阶梯。
- 不改 CI workflow、不新增 gate、不改 `.munk/code-gates.json`。
- 不引入第三方依赖或跨端框架。
- 不重做旋转 / size class 断言（公司裁决已撤，竖屏 + iPhone-only 单设备为既定前提）。
- 不做现场测量 App 运行态的黑盒用例（不写 XCUITest 测量版、不做截图取色判读）。
- 不扩范围去修 History / Settings / RunDetail 的 AX5 布局。

## 实现约束

- **纯函数优先**：判定放在 `ios/PurePace/Design/` 下、只依赖 `Foundation` / `CoreGraphics` 的无状态 `enum` 策略（可扩展 `PrimaryActionLayoutPolicy` 或新增同类策略），参数化「动态字号档 + 可用高度 + 内容底沿 + 主操作 frame + 文案理想尺寸」。UIKit 度量（`UIFontMetrics` / `NSString.size(withAttributes:)`）只在测试侧解析后注入，避免给 Design 层引入 UIKit 依赖，也避免现场测量。
- **AX5 需求高度来源**：字号基线取既有 `DesignTokens.Typography.titleSize`（= `Typography.control` 的字号 20），由 `UIFontMetrics(forTextStyle:)` 在 `UIContentSizeCategory.accessibilityExtraExtraExtraLarge` 下的 `scaledValue` 得出，单测锁定该基线与 token 相等；不得手调缩放比。若实现中选择「固定字号阶梯不缩放」的声明口径，必须在策略注释与 digest 中写清，并保证矩阵「现状」列不虚标实测行为。
- **可用宽度来源**：固定目标设备 iPhone 16 竖屏逻辑宽 393pt − 左右 `Spacing.md`（16 × 2）= 361pt；来源写进测试注释（与 `scripts/test-ios.sh` 的 `platform=iOS Simulator,name=iPhone 16` 一致），不得用运行态实测。
- **反例纪律**：反例与正例共用同一策略实现，差异只在输入；反例必须断言具体问题项，避免「任一条红即通过」。
- **既有行为不动**：`PrimaryActionLayoutPolicy.evaluate(actionFrame:tabBarFrame:)` 已被 UI 用例使用，签名与语义保持不变，新增能力走 overload / 新类型 additive 加入。
- **最小布局修正**：仅当 AX5 几何判定确实现红，且原因落在 `RunView` 主操作区（例如按钮无固定高度约束而依赖内容撑高、或内边距吃掉可用高度）时，才允许用既有 `DesignTokens` 做 token 级收敛，并在 digest 写明理由；否则不改 `RunView` 生产布局。
- **证据路径**：`ios/PurePaceTests/DynamicTypeLayoutTests.swift`、`ios/PurePace/Design/PrimaryActionLayoutPolicy.swift`、`docs/verification-matrix.md`。
- **预算**：≤8M token / ≤90 分钟；超时即停手回执，不做半成品提交。
