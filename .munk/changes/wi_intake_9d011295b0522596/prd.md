# 首屏 hero 间距收敛（token 级）+ 布局策略断言收紧

## 范围

- 仅 iOS 跑步页首屏 `ios/PurePace/Run/RunView.swift` 的四层垂直布局，以及 `ios/PurePace/Design/DesignTokens.swift` 的间距语义 token。
- 收紧 `ios/PurePace/Design/RunLayoutBalancePolicy.swift` 的几何阈值，并补齐「旧布局判红 / 新布局判绿」的确定性反例（单测为主，`check-ios-shell.sh --self-test` 静态反例为补充）。
- 重采 `docs/screenshots/` 6 张（5 light + 1 真实暗色）与 `docs/evidence/a11y/01..06` 6 棵可及树，逐文件 sha256 入 digest。
- 不改配色、字号阶梯、组件形态与 identifier；不新增视图组件。

## 验收

- ac-hero-gap-tokenized: `DesignTokens.Spacing` 新增语义间距 token（`screenTop` / `cardGap` / `sectionGap` 或等价命名），取值全部落在既有 `Spacing.scale`（4/8/12/16/24/32）之内；`RunView` 的固定 padding 与 VStack spacing 只引用这些 token，`grep -E '\.system\(size: *[0-9]|spacing: *[0-9]|\.padding\([0-9]|minHeight: *[0-9]'` 对 `RunView.swift` 仍为空；布局余量只由等权 `Spacer(minLength:)` 吸收，不出现新的样式字面量。
- ac-layout-thresholds: `RunLayoutBalancePolicy` 暴露四个具体阈值常量并被单测逐值锁定——`maximumTopGap = 80`、`maximumBottomGap = 80`、`maximumGap = 80`、`maximumImbalance = 16`（单位 pt）；任一数值被动（例如回到 160/40 或改成 96/24）`testPolicyThresholds` 立即判红。
- ac-legacy-layout-red: 旧布局反例必须判红：①单测既有 legacy 帧（顶 28pt / 底 251.6pt）在 80/16 下 `passes == false` 且 problems 至少 2 条；②本轮截图实测帧（顶 128.0pt / 底 116.3pt，见「实现约束」）单独喂入也必须 `passes == false`，且 problems 同时命中「顶部留白 > 80」「底部留白 > 80」「最大空洞 > 80」。改回旧布局而断言仍绿即视为未达标。
- ac-fourstates-green: 四态（未开始 / 运行中 / 暂停 / 已保存）的代表帧全部 `passes == true`：顶部留白、底部留白、块间最大空洞均 ≤ 80pt，且 `|顶部 − 底部| ≤ 16pt`（等量分布下期望 57.5 / 57.5 附近）；单测覆盖四态同构样本，UI 用例在真实模拟器上补齐「暂停」态采集（未开始 / 运行中 / 暂停 / 保存四态各打印 `ac-run-metrics-balanced <state>: top=… bottom=… largest=… imbalance=…`）。
- ac-self-test-still-red: `bash scripts/check-ios-shell.sh --self-test` 全过且断言条数不减少；既有反例（字面色值 / 零散字体 / 暗色关闭 / 移除 surface / running 错配 warning / identifier 重命名 / identifier 追加等）仍全部判红；新增的布局阈值静态反例（阈值被改回 160/40 必须判红）同样生效。
- ac-identifier-frozen: 可及 identifier 集合仍为冻结的 33 项且 diff = 0；`docs/evidence/a11y/01..06` 重采后逐棵树的 identifier 集合不变（不分新增、改名、删除）。
- ac-screenshots-refreshed: `docs/screenshots/` 6 张同名覆盖（`run-not-started.png` / `run-running.png` / `run-running-dark.png` / `history-empty.png` / `history-detail.png` / `settings.png`），全部为非空 PNG 且来自本轮 `xcrun simctl io <udid> screenshot`；`run-running-dark.png` 必须在 `xcrun simctl ui <udid> appearance dark` 之后重跑产出、随后切回 `light`；逐文件 sha256 写入 digest，不复用旧图、不手绘、不改色。
- ac-visual-gap-closed: 截图目视复核记录进 digest：导航标题与 hero 之间、提示片与底部主操作之间不再出现块级死白，四层（hero → 次级指标 → 提示 → 主操作）层级仍成立；对照值为本轮实测旧布局顶 128.0pt / 底 116.3pt 与新布局实测值。
- ac-gates-green: `bash scripts/build-ios.sh`、`bash scripts/test-ios.sh --unit-only`、`bash scripts/check-ios-shell.sh --self-test` 全部退出 0；`lint-ios-shell` 现有设计断言（基线口径 15 条）全绿，字面色值命中数为 0、零散字体修饰符命中数为 0；`.munk/code-gates.json` 仍为 22 门，不新增/不删减 gate id。
- ac-diff-scope-bounded: 代码 diff 只允许落在 `DesignTokens.swift`、`RunLayoutBalancePolicy.swift`、`RunView.swift`、`ios/PurePaceTests/LocalizationPolicyTests.swift`、`ios/PurePaceUITests/RunFlowUITests.swift`、`scripts/check-ios-shell.sh`、`docs/screenshots/*`、`docs/evidence/a11y/*` 与 digest；状态机、定位、音频、GPX、CI workflow、Android、`project.yml`、本地化键、页面/路由零改动。
- ac-digest-receipt: digest 必须写清：改了哪几个 token 及每个阈值的取值理由、旧布局判红的原始输出（失败断言原文）、identifier diff = 0、6 张截图与 6 棵可及树的逐文件 sha256、四态实测 top/bottom/largest/imbalance；禁止出现「真机已验证 / 已发布」，真机项写 `pending: 待人现场`。

## 非目标

- 不改配色、字号层级、字重、圆角、描边、图标与组件形态；不新增 SwiftUI 视图组件或新页面。
- 不改状态机（`RunSessionViewModel` / `RunSessionOrchestrator`）、定位、音频与 TTS、持久化、GPX 导出、CI workflow、Android 侧。
- 不替换 Tab 图标、不扩充设置页（已列入阶段 2 后一次性打磨清单，本项不碰）。
- 不新增业务功能、不新增/改名/删除任何 `accessibilityIdentifier`、不新增 gate id、不改门禁列表。
- 不做真机验收、不做动效/主题系统、不做截图回归基线、不做图标资产管线。

## 实现约束

- 本轮实测基线（PNG 逐行扫描，`docs/screenshots/run-not-started.png` 等 1178×2556、iPhone 16 @3x）：导航内容下沿 137.3pt → hero 面板顶 265.3pt，**死白 128.0pt**；提示片底 584.7pt → 主操作顶 701.0pt，**死白 116.3pt**；内容块高约 319pt。「约 400pt」按实测修正为约 116–128pt，阈值以实测为准（旧布局在 80/16 下必然判红）。
- 布局方向（已约定）：四层在「导航栏下沿 → 主操作顶边」之间**等量分布**——固定间距取 token，剩余空间由 4 个等权 `Spacer(minLength: sectionGap)` 吸收；不允许顶对齐后把全部余量堆成底部单块死白。iPhone 16 竖屏下四个间隙期望 ≈ 57.5pt，文本帧因面板内 padding 会多约 12–16pt，故 80pt 阈值留出该余量。
- 阈值取值理由：`80 = 2.5 × Spacing.xl(32)`，约 iPhone 16 屏高（852pt）的 9.4%，且小于旧实测 116.3/128.0 的 2/3，肉眼不构成「块级死白」；`16 = Spacing.md`，等于卡片内一档固定间距，保证上下不偏而非机械居中。
- 判红证据落在 XCTest（`LocalizationPolicyTests`）：既有 `testLegacyTopStackedLayoutFailsBothCriteria`、`testRejectsAsymmetricWhitespaceEvenWhenGapsFit`、`testRejectsMissingContent` 必须保持判红；新增本轮截图帧反例与四态正例。`--self-test` 只做静态主源断言（阈值常量、RunView 无样式字面量、identifier 33 项），不在 shell 里伪造 Swift 执行结果。
- UI 用例采集口径保持现状（`staticTexts` 的 frame + `navigationBars.firstMatch.frame.maxY` + 主操作 `frame.minY`），不为了凑阈值改采集对象或加 identifier；`assertRunMetricsBalanced` 只扩到暂停态与新的判定文案。
- 截图造态与证据口径沿用既有约定：DEBUG 启动参数门控 + `xcrun simctl io <udid> screenshot`，安装包来自 `bash scripts/build-ios.sh` 的 `.build/ios`；深色只写「真实 dark appearance 模拟器产物」。
- 预算：≤8M token / ≤90 分钟（样式改动 ≤30 分钟）；超限交半成品并在 digest 如实列未完成项，不虚报。
