# Domain: ios-ui-design

PurePace iOS 三屏（Run / History / Settings）视觉层级与设计 token 收敛域：用 `ios/PurePace/Design/DesignTokens.swift` 做全仓唯一 token 真源（颜色 / 字号 / 字重 / 间距 / 圆角 / 图标尺寸 / 最小触控尺寸），三屏只引用 token；跑步页建立「主信息 ≫ 次信息」层级，历史页建立「日期 → 距离/时长/配速」层级并给空态 CTA，设置页用带分组标题的 Section + 每项说明。全部断言落在既有单测腿（`test-ios`）与静态腿（`lint-ios-shell`），不新增 UI/模拟器腿；证据为真实 `simctl` 截图 + 可及树文本。

## 范围

- `ios/PurePace/Design/DesignTokens.swift`：无状态 `enum` 命名空间，含 `Colors` / `Typography` / `Spacing` / `Radius` / `Icon` / `Appearance` / `minTapTarget`；颜色一律系统语义色派生，字号阶梯 caption 12 < body 15 < title 20 < primaryValue 34 < display 56，间距 4/8/12/16/24/32，圆角 12/16/20，图标 16/20/24，`minTapTarget == 44`，`Appearance.supportsDarkMode = false` 为深色模式留位。
- `ios/PurePace/Run/RunView.swift`：距离用 `Typography.display`，时长/当前配速用 `primaryValue`，平均配速/分段/说明用 `caption` + `Colors.secondary`；开始/暂停/继续/结束四按钮带非空互异 `accessibilityLabel` 与既有 identifier，主操作强调色、结束用警示色，四态互斥渲染不变。
- `ios/PurePace/History/HistoryView.swift`：列表行第一行日期（title 级）、第二行距离/时长/配速（caption + 次要色）；空态 = 标题「还没有跑次记录」+ 一句说明 + CTA「去跑一次」（`history.runAgain`，带 `accessibilityLabel`）；行可点击进详情。
- `ios/PurePace/Settings/SettingsView.swift`：带分组标题的 Section（含「播报」组），每项一句说明文案，字号不低于 caption；保留 `settings.announcementToggle` 与 `Toggle`。
- `ios/PurePace/History/RunDetailView.swift`：导出入口「导出 GPX」（`runDetail.export`，带 `accessibilityLabel`）保持在导航可达位置，导出流程与状态标识不变。
- `ios/PurePace/ContentView.swift`：三个 Tab 的 `Label` 文案保留，并给 tabItem 加 `tab.run` / `tab.history` / `tab.settings` 标识；新增 DEBUG-only 截图启动参数接线（`-screenshotInitialTab` / `-screenshotHistoryDemo` / `-screenshotOpenRunDetail`）。
- `ios/PurePace/Run/RunLaunchArguments.swift` + `ios/PurePace/History/HistoryDemoRecords.swift`：`value(after:)` / `flagEnabled(_:)` 纯函数解析，演示跑次整文件 `#if DEBUG` 包裹、不落盘、不读夹具。
- 断言：`ios/PurePaceTests/DesignTokensTests.swift`（token 不变量 L1 单测）+ `scripts/check-ios-shell.sh` 的 `validate_design_tokens`（token 唯一性、三屏无样式字面量、主/次层级、关键文案、a11y 标签、identifier、demo 入口禁令）与其 `--self-test` 正负反例。
- 证据入仓：`docs/screenshots/run-not-started.png`、`run-running.png`、`history-detail.png`（另含 `history-empty.png` / `settings.png`）与 `docs/evidence/a11y/0{1..6}-*.txt`。

## 验收

- ac-token-single-source: 有且仅有一处 `enum DesignTokens` 定义（`ios/PurePace/Design/DesignTokens.swift`），覆盖颜色 / 字号 / 字重 / 间距 / 圆角 / 图标 / 最小触控尺寸；`RunView`、`HistoryView`、`SettingsView` 新增样式全部以 `DesignTokens.` 引用；脚本对 token 定义数断言为 1。
- ac-token-values-valid: 单测断言间距档严格递增且为正、字号阶梯严格递增（caption < body < title < primaryValue < display）、圆角/图标档为正且递增、`DesignTokens.minTapTarget == 44`、主信息字号 ≥ 次信息（body）两倍。
- ac-no-magic-numbers: 三屏源码不出现 `.system(size: <数字>`、`spacing: <数字>`、`.padding(<数字>`、`minHeight: <数字>` 形式的样式字面量（系统默认 `.padding()` 不算）；`--self-test` 含样式字面量负例且判失败。
- ac-run-primary-hierarchy: 跑步页距离绑定 display、时长与当前配速绑定 primaryValue、平均配速与分段绑定 caption + 次要色；静态段对三处字号引用逐项断言。
- ac-run-controls-states: 未开始显示「开始」，记录中「暂停」「结束」，已暂停「继续」「结束」；主操作强调样式、结束用警示样式；状态机与 `RunSessionViewModel` / 编排器零改动。
- ac-run-a11y-labels: 开始 / 暂停 / 继续 / 结束四按钮均有非空、互不相同的显式 `accessibilityLabel`；静态检查对 `label: ""` 与「少于 4 个互异非空值」判失败。
- ac-tap-target-44: 三屏可点击控件（主按钮、空态 CTA、导出按钮、列表行）最小触控高度 ≥ 44pt 且引用 `DesignTokens.minTapTarget`，不写 44 字面量。
- ac-history-row-hierarchy: 列表项第一行日期（title 级 token）、第二行距离 / 时长 / 配速（caption + 次要色）；无记录时不渲染任何示例跑次（演示态仅 DEBUG 启动参数注入）。
- ac-history-empty-state: 空态同时含非空标题、非空一句说明与 CTA「去跑一次」；空态不含样例/夹具数据。
- ac-history-export-discoverable: 跑次详情存在可点击「导出 GPX」入口（`runDetail.export`），位于导航可达位置，导出流程与既有断言标识不变。
- ac-settings-grouped: 设置页使用带分组标题的 Section（至少「播报」组），每项一句说明；`settings.announcementToggle` 与 `Toggle` 保留；不出现 `Stepper` / `Slider` / 示例数值 / 「暂无可配置项」。
- ac-copy-strings: `开始`、`暂停`、`继续`、`结束`、`还没有跑次记录`、`去跑一次`、`每公里语音播报`、`导出 GPX` 均在源码中存在且非空。
- ac-a11y-identifiers: 主操作除 label 外必须有 `accessibilityIdentifier`；三个 Tab 与关键控件有可读 label + identifier（`run.start` / `run.pause` / `run.resume` / `run.finish` / `history.runAgain` / `history.row` / `runDetail.export` / `runDetail.root` / `settings.announcementToggle` / `tab.run` / `tab.history` / `tab.settings`）；验收 = 真实构建的可及树里可按 identifier 定位（见 `docs/evidence/a11y/`）。identifier 只用于定位与模拟器测试，不做真机驱动埋点。
- ac-zero-demo-entry: 首屏与工作流工具栏的 demo / 示例入口数为 0；静态段对 `Button`/`ToolbarItem`/`NavigationLink`/`Label` 内出现「示例 / 样例 / Demo / demo」判失败。
- ac-assertions-in-gates: 上述断言经既有 `test-ios`（`PurePaceTests`，含 `DesignTokensTests`）与 `lint-ios-shell`（`validate_design_tokens` + `--self-test` 正负反例）两条 gate 运行；不新增 XCUITest 用例、不新增 UI 驱动腿、不改 `code-gates.json` 门列表。
- ac-local-gates-green: `bash -n scripts/check-ios-shell.sh`、`bash scripts/check-ios-shell.sh`、`bash scripts/test-ios.sh --unit-only`、`bash scripts/build-ios.sh` 本机全部退出 0。
- ac-screenshots-archived: `docs/screenshots/run-not-started.png`（首屏）、`run-running.png`（运行中）、`history-detail.png`（历史详情）存在且为 `simctl io screenshot` 产出的非空 PNG；连同可及树文本 `docs/evidence/a11y/01..06-*.txt` 入仓；不以 XCTest attachment 顶替、不手绘。
- ac-demo-data-gated: 运行中与历史详情所需数据只由 `#if DEBUG` + 启动参数（`-uiTestLocation` / `-screenshotHistoryDemo` / `-screenshotOpenRunDetail`）注入，Release 路径不可达、不落盘、不引用 `shared/fixtures` 或 `.gpx`/`.tcx` 夹具；截图注记「演示数据不入发布路径」。
- ac-no-ui-leg-change: `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿无 diff；既有 identifier 字符串原样保留，新增 identifier 仅用于可及树定位与模拟器测试。
- ac-no-sample-in-release: 首屏与发布业务流不出现任何示例/种子跑次。

## 非目标

- 不做深色模式专项适配（token 只留 `Appearance` 结构位）、不做动效/动画专项、不做 Android 视觉对齐、不做截图回归基线。
- 不引入第三方主题系统 / 第三方 UI 依赖 / 跨端框架；不替换系统语义色与系统控件的基本行为。
- 不改状态机与业务契约：`RunSessionViewModel` / `RunSessionOrchestrator` / `RunLocationSource` / AudioSession / TTS / 持久化 / GPX 导出与命名契约零改动。
- 不新增/改动 XCUITest 用例与模拟器 UI 驱动腿；不改 `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿；不新增 gate id。
- 不把示例/种子数据放进首屏或发布业务流；不在 `shared/` 增加夹具。
- 不改 `project.yml` 依赖与 target 结构（新文件落既有 `PurePace` 源目录）。
- 不做真机验收与设备场；真机项一律 `pending: 待人现场`。

## 实现约束

- Token 只增不改语义：视图改为引用 token，不改系统语义色/控件行为；`DesignTokens.Colors` 是唯一颜色出入口，深色模式后续只在此扩展。
- 既有 identifier 是稳定测试契约，原样保留（`run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` / `run.saved` / `history.empty` / `history.row` / `runDetail.*` / `settings.announcementToggle` 等）；新增 identifier 只做可及树定位。
- 静态断言写在既有 `scripts/check-ios-shell.sh` 的 `validate_design_tokens`，并在 `--self-test` 补正负反例（token 文件缺失、样式字面量、空 label、缺 Tab 标识、缺控件标识、demo 入口），**不新增 gate id、不改 `code-gates.json`**；门禁用真实 `grep -Fq`/`grep -Eq` 断言，不用通配允许表。
- 设置页静态约束：`validate_settings_view` 禁止 `Stepper` / `Slider` / 「示例」/「Sample」/「暂无可配置项」，新文案须避开这些词。
- 截图造态：只允许 DEBUG 编译期 + 启动参数门控；`HistoryDemoRecords` 整文件 `#if DEBUG` 包裹、不落盘、默认启动不可见；`xcrun simctl io <udid> screenshot` 产出，安装包来自 `bash scripts/build-ios.sh` 的 `.build/ios`。
- 证据口径：只写模拟器 / 单测 / 静态断言结论，真机项写 `pending: 待人现场`，不得写「真机已验证」或「深色模式已适配」。

## 最近交付证明

- workItemId: wi_intake_837f0c6ab9066cf5（2026-11-11，pass）
- 交付：新建 `DesignTokens.swift` token 单一真源；三屏样式全部改为 token 引用并建立主/次信息层级；历史空态与详情导出入口可发现；设置页分组 + 说明文案；Tab 与主操作补可及标识，`accessibilityLabel` 非空互异。
- 断言：`DesignTokensTests`（9 例）随 `test-ios` 运行；`check-ios-shell.sh` 新增 `validate_design_tokens` 与其 7 组正负自检（28 项断言 0 失败，`--self-test` 36 项 0 失败）；`code_gates` 22 门全绿，单测 125 例 0 失败，`build-ios.sh` SUCCEEDED。
- 证据：`docs/screenshots/{run-not-started,run-running,history-detail,history-empty,settings}.png` + `docs/evidence/a11y/01..06-*.txt`，均由真实 `simctl` 构建采集；演示数据 `#if DEBUG` + 启动参数门控。真机项 `pending: 待人现场`。
