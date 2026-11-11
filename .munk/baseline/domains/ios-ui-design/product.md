# Domain: ios-ui-design

PurePace iOS 三屏（Run / History / Settings）视觉层级、文案与布局锚定域：`ios/PurePace/Design/DesignTokens.swift` 是全仓唯一 token 真源（颜色 / 字号 / 字重 / 间距 / 圆角 / 图标尺寸 / 最小触控尺寸），三屏只引用 token；跑步页建立「主信息 ≫ 次信息」层级，历史页建立「日期 → 三数值 → 三标签」层级并给空态单 CTA，设置页用带分组标题的 Section + 每项说明。文案 zh-Hans 单语，唯一来源 `Localizable.xcstrings`（视图只引用 `L10n` 键）；主操作下沉到 TabBar 之上安全区。断言落在既有 `test-ios` / `lint-ios-shell` / `PurePaceUITests`，不新增 gate；证据为真实 `simctl` 截图 + 可及树文本。History 屏层级细则见域 `ios-history-visual`，令牌门禁规则见域 `design-token-gates`。

## 范围

- `ios/PurePace/Design/DesignTokens.swift`：无状态 `enum` 命名空间，含 `Colors` / `Typography` / `Spacing` / `Radius` / `Stroke` / `Icon` / `Appearance` / `minTapTarget`。颜色为 `SRGB` + `ColorPair { light, dark }`，18 个语义色全部成对（动态 `Color` 只经 `Color(uiColor: UIColor { trait in ... })`，只 `import SwiftUI`）；唯一品牌主色 `Colors.accent`（`#0B6F60` / 暗色 `#5ED6C4`）。字号阶梯 caption 12 < body 15 < title 20 < primaryValue 34 < display 56，另有指标角色 `metricLabel` / `metricUnit` = 11；间距档 4/8/12/16/24/32 与六个语义间距 token（`screenTop` / `cardGap` / `sectionGap` / `metricGroupSpacing` / `metricGroupGap` / `cardPadding`），圆角 12/16/20，图标 16/20/24，`minTapTarget == 44`，`Appearance.supportsDarkMode = true`；`Colors.purposes` 为 18 键用途注册表，`roleLadder` / `numericRoleNames = [primaryValue, display]` 锁字形单调；`Motion` 只提供 `durationShort` / `durationState` / `reducedMotionDuration` 与降级纯函数，不接动画。逐值冻结与反例清单见域 `design-token-gates` 与本文件验收项。
- `ios/PurePace/Design/ContrastPolicy.swift`：Foundation-only 纯函数，按 WCAG 2.x 相对亮度计算成对 sRGB token 对比度（`ratio(foreground:background:) -> Double?` / `problems(for:) -> [String]` / `ratios(for:)`），阈值常量 body 4.5 / large 3.0，缺对、空名、分量越界一律 fail-closed；另持唯一成对矩阵 `pairMatrix`（`Pair` + `Tier` body 4.5 / large 3.0 / decorative 1.10，只引用 palette 键）与 `component(_:scheme:)` / `checks(for:)` 解析函数。
- `ios/PurePace/Run/RunView.swift`：距离用 `Typography.display`，时长/当前配速用 `primaryValue`，平均配速/分段/说明用 `caption` + `Colors.secondary`；开始/暂停/继续/结束四按钮带非空互异 `accessibilityLabel` 与既有 identifier，主操作强调色、结束用警示色，四态互斥渲染不变。
- `ios/PurePace/History/HistoryView.swift`：列表行三层（日期 title → 三数值 body 等宽 → 三标签 metricLabel）与空态单 CTA（`history.runAgain`，带 `accessibilityLabel`）；层级细则见域 `ios-history-visual`；行可点击进详情。
- `ios/PurePace/Settings/SettingsView.swift`：带分组标题的 Section（含「播报」组），每项一句说明文案，字号不低于 caption；保留 `settings.announcementToggle` 与 `Toggle`。
- `ios/PurePace/History/RunDetailView.swift`：五段纵向序（元信息 → hero 距离 → 指标网格 → 分段 → 导出），细则见域 `ios-history-visual`；`runDetail.export` 保持首屏可及，导出流程与状态标识不变。
- `ios/PurePace/ContentView.swift`：三个 Tab 的 `Label` 文案保留，并给 tabItem 加 `tab.run` / `tab.history` / `tab.settings` 标识；新增 DEBUG-only 截图启动参数接线（`-screenshotInitialTab` / `-screenshotHistoryDemo` / `-screenshotOpenRunDetail`）。
- `ios/PurePace/Run/RunLaunchArguments.swift` + `ios/PurePace/History/HistoryDemoRecords.swift`：`value(after:)` / `flagEnabled(_:)` 纯函数解析，演示跑次整文件 `#if DEBUG` 包裹、不落盘、不读夹具。
- 断言：`DesignTokensTests.swift`（token 不变量 L1）+ `ContrastPolicyTests.swift`（逐对打印 `ac-contrast`）+ `scripts/check-ios-shell.sh` 的 `validate_design_tokens`（零字面色值/零散字体/动效字面量 + 三屏层级、identifier 冻结、demo 入口禁令；规则契约见域 `design-token-gates`）与其 `--self-test` 正负反例。
- `ios/PurePace/Design/DesignComponents.swift`（可选的视图内复用件）：只允许引用 token，不允许字面色值与零散字体修饰符；本轮以视图内联修饰实现，未新增独立文件。
- 证据入仓：`docs/screenshots/` 的 `run-not-started.png`、`run-running.png`、`history-detail.png`、`history-empty.png`、`settings.png` 与新增暗色运行态 `run-running-dark.png`，连同 `docs/evidence/a11y/0{1..6}-*.txt`。
- `ios/PurePace/Resources/Localizable.xcstrings`：String Catalog，`sourceLanguage = zh-Hans`，三屏全部用户可见文案（Tab / 导航标题 / 字段标签 / 空态 / 提示 / 按钮 / 状态 / a11y label）的唯一真源；`ios/project.yml` 声明 `developmentLanguage: zh-Hans`、`knownRegions`、`INFOPLIST_KEY_CFBundleDevelopmentRegion: zh-Hans` 并以 XcodeGen 重生成工程。
- `ios/PurePace/Design/L10n.swift`：本地化键唯一入口（`LocalizedStringKey` 静态属性 + 少量 `String(localized:)` 用于拼接），视图内不得保留裸英文文案字面量。
- `ios/PurePace/Design/{VisibleTextPolicy,VisibleDatePolicy,PrimaryActionLayoutPolicy,RunLayoutBalancePolicy}.swift`：四条判定的纯函数实现，与 `PurePaceTests` / `PurePaceUITests` 共用同一源文件（`project.yml` 显式列入 UITests target sources）。
- `ios/PurePace/Run/RunView.swift`：主内容区与底部控制区分离，`controls` 由 `.safeAreaInset(edge: .bottom)` 承载，`.ready` / `.running` / `.paused` / 保存态共用同一底部锚点；指标内容块（距离/用时/当前配速/平均配速/分段/提示/已保存）抽为单一组件，经 `ViewThatFits(in: .vertical)` 的首选分支在「导航栏下沿 → 控制区上沿」之间等量分布（固定间距只取 `Spacing.screenTop` / `cardGap` / `sectionGap` 语义 token，剩余余量由 4 个等权 `Spacer(minLength:)` 吸收，不允许顶对齐后把余量堆成底部单块死白），小屏/大字号溢出退回 `ScrollView` 不截断；DEBUG `run.telemetry` 诊断摘要改内容区底部 overlay，不进入居中块；保存态主操作 `run.viewHistory` 回历史 Tab（纯视图回调）。
- `ios/PurePace/Run/RunFormatting.swift`：`zhHansDateTimeText`（分钟精度，历史行）与 `dateTimeText`（带秒，详情）统一走 `zh_Hans_CN` locale + 固定 `dateFormat` + 固定 `TimeZone`（`Asia/Shanghai`），历史行不再直调 `date.formatted(...)`。

## 验收

- ac-token-single-source: 有且仅有一处 `enum DesignTokens` 定义（`ios/PurePace/Design/DesignTokens.swift`），覆盖颜色 / 字号 / 字重 / 间距 / 圆角 / 图标 / 最小触控尺寸；`RunView`、`HistoryView`、`SettingsView` 新增样式全部以 `DesignTokens.` 引用；脚本对 token 定义数断言为 1。
- ac-token-values-valid: 单测断言间距档严格递增且为正、字号阶梯严格递增（caption < body < title < primaryValue < display）、圆角/图标档为正且递增、`DesignTokens.minTapTarget == 44`、主信息字号 ≥ 次信息（body）两倍。
- ac-run-metrics-balanced: UI 用例在 `.ready` / `.running` / `.paused` / `didSave` 四态读取内容区可见 `staticTexts`（排除 `run.telemetry` 与导航标题）与当态主操作的 `frame`，区间上界导航栏 `maxY`、下界主操作顶边，逐态打印 `ac-run-metrics-balanced <state>: top=… bottom=… largest=… imbalance=…`，四条同时成立：顶部留白 ≤80pt、底部留白 ≤80pt、块间最大单一垂直空洞 ≤80pt、|顶部 − 底部| ≤16pt。判定抽成纯函数 `RunLayoutBalancePolicy`（`Evaluation` + `problems` + `passes`，阈值 `maximumTopGap/maximumBottomGap/maximumGap = 80` / `maximumImbalance = 16` 单点定义，`testPolicyThresholds` 逐值锁定）；旧布局两类历史帧反例必须判红（`passes == false`），四态同构样本全部判绿。
- ac-hero-gap-tokenized: `DesignTokens.Spacing` 新增语义间距 token（`screenTop` / `cardGap` / `sectionGap`），取值全部落在既有档位（4/8/12/16/24/32）；`RunView` 的固定 padding 与 VStack spacing 只引用这些 token，`grep -E '\.system\(size: *[0-9]|spacing: *[0-9]|\.padding\([0-9]|minHeight: *[0-9]'` 对 `RunView.swift` 为空；布局余量只由等权 `Spacer(minLength:)` 吸收。
- ac-layout-thresholds-static: `scripts/check-ios-shell.sh` 静态断言锁定三个语义 token 存在、`RunView` 余量走语义间距、`RunLayoutBalancePolicy` 四阈值取值；`--self-test` 增补反例（阈值改回 160/40、缺语义 token、首屏余量未用语义间距）全部判红，既有 46 项断言不减少。
- ac-no-magic-numbers: 三屏源码不出现 `.system(size: <数字>`、`spacing: <数字>`、`.padding(<数字>`、`minHeight: <数字>` 形式的样式字面量（系统默认 `.padding()` 不算）；`--self-test` 含样式字面量负例且判失败。
- ac-run-controls-states: 未开始显示「开始」，记录中「暂停」「结束」，已暂停「继续」「结束」；主操作强调样式、结束用警示样式；状态机与 `RunSessionViewModel` / 编排器零改动。
- ac-run-a11y-labels: 开始 / 暂停 / 继续 / 结束四按钮均有非空、互不相同的显式 `accessibilityLabel`；静态检查对 `label: ""` 与「少于 4 个互异非空值」判失败。
- ac-tap-target-44: 三屏可点击控件（主按钮、空态 CTA、导出按钮、列表行）最小触控高度 ≥ 44pt 且引用 `DesignTokens.minTapTarget`，不写 44 字面量。
- ac-history-row-hierarchy: 列表项第一行日期（title 级 token）、第二行距离 / 时长 / 配速（caption + 次要色）；无记录时不渲染任何示例跑次（演示态仅 DEBUG 启动参数注入）。
- ac-history-empty-state: 空态同时含非空标题、非空一句说明与 CTA「去跑一次」；空态不含样例/夹具数据。
- ac-history-export-discoverable: 跑次详情存在可点击「导出 GPX」入口（`runDetail.export`），位于导航可达位置，导出流程与既有断言标识不变。
- ac-settings-grouped: 设置页使用带分组标题的 Section（至少「播报」组），每项一句说明；`settings.announcementToggle` 与 `Toggle` 保留；不出现 `Stepper` / `Slider` / 示例数值 / 「暂无可配置项」。
- ac-visible-copy-zh-hans: 三屏（跑步/历史/设置）可及树中全部可见 label/text 逐条匹配 zh-Hans 白名单（仅允许 `km`、`/km`、`GPX`、`PurePace` 等专有名词/单位与数字），零裸英文；判定抽成纯函数 `VisibleTextPolicy.isAllowed/violations`，单测用固定中文列表通过 + 英文反例（`Run`/`History`/`Settings`）证明能红；UI 用例把真实可及树喂给同一判定，静态腿断言 `Localizable.xcstrings` 的 `sourceLanguage == zh-Hans`、三屏视图无 `Text/Label/Button/navigationTitle/accessibilityLabel("英文…")` 裸字面量。
- ac-run-detail-date-zh-hans: 单测以固定 `Date`（`1760000000`）+ 固定 `TimeZone`（`Asia/Shanghai`）断言详情时间形如「2025年10月9日 16:53」/带秒同形，不含英文月份集合与 `at`；历史行日期同走 `RunFormatting.zhHansDateTimeText`；`VisibleDatePolicy.isZhHansDateTime` 对 `Oct 9, 2025 at 16:53`、`10/9/25, 4:53 PM`、`2025/10/09 16:53` 等反例样本必须返回拒绝。
- ac-primary-action-bottom-anchored: UI 用例在首屏「开始」、运行中「暂停」、结束保存态（`run.viewHistory`）三态读取主操作按钮 `frame`，判定（a）高 ≥44pt；（b）按钮底边距 TabBar 顶边 ≤24pt；（c）位于 TabBar 之上；判定抽成纯函数 `PrimaryActionLayoutPolicy.evaluate`，单测用「距安全区 200pt / 高 30pt」与「低于 TabBar」反例证明能红。
- ac-a11y-identifiers: 主操作除 label 外必须有 `accessibilityIdentifier`；三个 Tab 与关键控件有可读 label + identifier（`run.start` / `run.pause` / `run.resume` / `run.finish` / `history.runAgain` / `history.row` / `runDetail.export` / `runDetail.root` / `settings.announcementToggle` / `tab.run` / `tab.history` / `tab.settings`）；验收 = 真实构建的可及树里可按 identifier 定位（见 `docs/evidence/a11y/`）。identifier 只用于定位与模拟器测试，不做真机驱动埋点。
- ac-zero-demo-entry: 首屏与工作流工具栏的 demo / 示例入口数为 0；静态段对 `Button`/`ToolbarItem`/`NavigationLink`/`Label` 内出现「示例 / 样例 / Demo / demo」判失败。
- ac-assertions-in-gates: 上述断言经既有三条 gate 运行——`test-ios`（`PurePaceTests`：`DesignTokensTests` + `LocalizationPolicyTests`；`PurePaceUITests`：含 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction`）、`lint-ios-shell`（`validate_design_tokens` + `validate_localization` + `--self-test` 正负反例）、`build-ios`；不改 `code-gates.json` 门列表、不新增 gate id。
- ac-local-gates-green: `bash -n scripts/check-ios-shell.sh`、`bash scripts/check-ios-shell.sh`、`bash scripts/test-ios.sh --unit-only`、`bash scripts/build-ios.sh` 本机全部退出 0。
- ac-screenshots-archived: `docs/screenshots/run-not-started.png`（首屏）、`run-running.png`（运行中）、`history-detail.png`（历史详情）存在且为 `simctl io screenshot` 产出的非空 PNG；连同可及树文本 `docs/evidence/a11y/01..06-*.txt` 入仓；不以 XCTest attachment 顶替、不手绘。
- ac-demo-data-gated: 运行中与历史详情所需数据只由 `#if DEBUG` + 启动参数（`-uiTestLocation` / `-screenshotHistoryDemo` / `-screenshotOpenRunDetail`）注入，Release 路径不可达、不落盘、不引用 `shared/fixtures` 或 `.gpx`/`.tcx` 夹具；截图注记「演示数据不入发布路径」。
- ac-no-ui-leg-change: `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿无 diff；既有 identifier 字符串原样保留，新增 identifier 仅用于可及树定位与模拟器测试。
- ac-no-sample-in-release: 首屏与发布业务流不出现任何示例/种子跑次。
- ac-brand-primary-token: 全仓只有一个品牌主色语义 token（`DesignTokens.Colors.accent`），记录态 / 主操作 / 强调共用它；`accent` / `onAccent` 与全部语义色均 light/dark 成对定义；RunView / HistoryView / SettingsView / RunDetailView / ContentView 与 `Design/**` 组件文件中 `Color(`、`Color.`、`UIColor`、`#colorLiteral`、`.foregroundStyle(.` 命中数为 0；静态门正例通过，追加字面色值的反例必须判红。
- ac-brand-contrast: `ContrastPolicy` 纯函数按 WCAG 2.x 计算 token 对比度；正文/小字（primary、secondary、warning、success、danger 及其弱底）light/dark 均 ≥4.5:1，hero 大数字 ≥3:1；逐对实测值打印为 `ac-contrast <pair> <ratio>` 日志并写入 digest；单测必须含达标正例通过、低对比反例（如 `#AAAAAA` on `#FFFFFF`）判红、分量越界 fail-closed。
- ac-monospaced-metrics: 距离、用时、当前配速、平均配速、分段以及历史行、详情数值全部使用 `.monospacedDigit()`；hero 指标固定为距离（`Typography.display`），用时/当前配速为次级主值（`Typography.primaryValue`），平均配速/分段为再次级（`Typography.caption`）；三屏与详情无 `spacing: <数字>`、`.padding(<数字`、`minHeight: <数字>`、`.system(size: <数字>` 样式字面量。
- ac-typography-token-only: 字号、字重、行距只从 `DesignTokens.Typography` 取；视图与 Design 组件中 `.font(.`、`.fontWeight(`、`.fontDesign(`、`.lineSpacing(<数字` 命中数为 0（`DesignTokens.Typography.*` 与 `.monospacedDigit()` 除外）；静态门正例通过，追加零散字体修饰符的反例必须判红。
- ac-token-single-source: 全仓唯一 `enum DesignTokens`，用途注册表 / 字形角色 / 语义间距 / `Motion` 等全部令牌只落在 `ios/PurePace/Design/DesignTokens.swift` 与 `ios/PurePace/Design/ContrastPolicy.swift`；不新建 DesignSystem / 组件库 / 令牌分片文件；`validate_design_tokens` 零字面色值与零散字体修饰符正例保持绿。
- ac-color-purpose-registry: 18 个语义色键名与数量不变，每键在 `Colors.purposes` 中有非空、去空白非空且不等于键名的用途；`Colors.purposeProblems` 对缺键 / 多键 / 空用途 / 复读键名 fail-closed；单测断言「注册表键集 == palette 键集」，空串、复读键名、删键三类反例判红；每对 light/dark 仍不相等且分量在 `0...1`。
- ac-contrast-matrix-exhaustive: 成对矩阵单点声明在 Design 层（`ContrastPolicy.pairMatrix`），只以 palette 键引用颜色、矩阵内零十六进制；分档 body 4.5 / large 3.0 / decorative 1.10，≥36 对且 18 个键每个至少出现一次；`checks(for:)` 在 light 与 dark 两侧求解整张矩阵，单测断言 `problems == []` 并逐对打印 `ac-contrast <scheme> <name> <ratio>`。
- ac-contrast-fail-closed-red: 缺键（矩阵引用不存在的 palette 键 → `component` 返回 `nil`）、空对照名、分量越界、低于阈值四类输入在单测真实执行，原因串分别含「缺色对」「缺对照名」「分量越界」「对比度不足」；低对比反例固定 `#AAAAAA` on `#FFFFFF`（2.32）；删除或改名任一 palette 键必须因「缺色对」结构性判红。
- ac-contrast-values-locked: 锁定 `onAccent/accent` light `6.07` / dark `9.57`、light 最低对 `success/successSoft` `4.81`、dark 最低对 `danger/dangerSoft` `6.86`（容差 0.01），并断言 `bodyThreshold == 4.5`、`largeThreshold == 3.0`；hex 或 WCAG 公式漂移即红。
- ac-typography-metric-roles: `metricLabelSize` 与 `metricUnitSize` 均为 `11` 且相等、`< captionSize`、`>= 10`；`Typography.sizes` 为严格递增 6 档 `[11, 12, 15, 20, 34, 56]`，`caption/body/title/primaryValue/display` 取值不变，`primaryValue` 与 `display` 均 ≥ 2 × `body`；改成 13、删 `metricUnit`、`sizes` 不再递增三类反例判红。
- ac-typography-role-ladder: `roleLadder` 按字号非递减覆盖 7 角色（label == unit == 11 < caption 12 < body 15 < title 20 < primaryValue 34 < display 56），非相邻重复只允许 label/unit；`numericRoleNames` 恰为 `[primaryValue, display]` 且仅这两角色标记等宽数字；`roleProblems` 对长度 / 顺序 / 乱标记 fail-closed，移出数值角色或给 `caption` 打等宽标记必须判红。
- ac-motion-tokens-and-degrade: `Motion.durationShort == 0.2`、`durationState == 0.32`（`TimeInterval` 秒，注释毫秒）、`0 < durationShort < durationState <= 0.4`、`reducedMotionDuration == 0`；纯函数 `Motion.duration(_:reduceMotion:)` 在 `true` 返回 0、`false` 返回原值；改 0.25、state < short、`true` 时返回非零三类反例判红。
- ac-no-animation-wiring: 本轮 `ios/PurePace/**` 除 `DesignTokens.swift` 外 `Motion.` 引用为 0，`.animation(` / `withAnimation(` / `UIAccessibility.isReduceMotionEnabled` 新增为 0（动画接线留给后续波次）。
- ac-semantic-spacing: `Spacing` 新增指标组内 / 指标组之间 / 卡片内边距三个 `CGFloat` 语义项，取值只落在 `{4, 8, 12, 16, 24, 32}`；`screenTop == 24` / `cardGap == 16` / `sectionGap == 12` 与严格递增 6 档 `Spacing.scale` 保持；新增项改成 20（档位外）必须判红。
- ac-existing-tiers-frozen: `Radius.scale == [12, 16, 20]`、`Icon.scale == [16, 20, 24]`、`Stroke.hairline == 1`、`minTapTarget == 44`、`Appearance.supportsDarkMode == true` 逐值锁定；不新增圆角 / 图标 / 描边档；33 项 identifier 固定集合零增删改名。
- ac-run-three-states-five-layers: 三态固定为 ready / running+paused（暂停是跑步中子态）/ finished && didSave（saved），每态自上而下五层：hero 距离（唯一 `Typography.display`，等宽数字）→ 次级主值（用时 / 当前配速 `primaryValue`）→ caption 层（平均配速 / 分段）→ 提示（caption + 小面积弱底，saved 态仍渲染 `run.saved` 胶囊）→ 主操作（`safeAreaInset(edge: .bottom)` 每态恰一个填充主操作）；指标块统一三行：`metricLabel` 标签 → 等宽数值 → `metricUnit` 单位，无单位项（用时 / 分段 / 空配速）不渲染空单位行；`RunView` 内 `monospacedDigit()` ≥ 3、零 `.shadow(` / 零渐变 / 零嵌套双描边，hero 面板底色只取中性 `surface` / `surfaceMuted`（弱底只出现在提示胶囊这类小面积元素）；保留 `ViewThatFits(in: .vertical)` → `ScrollView` 退路与等权 `Spacer(minLength:)`，不引入固定高度 / `lineLimit(1)` / `fixedSize(horizontal: true)`。
- ac-run-unit-split-a11y: 数值 / 单位拆分只在 `RunFormatting` **新增**纯函数（`distanceValueText` / `distanceUnitText` / `paceValueText` / `paceUnit` / `paceUnitText`），既有 `distanceText` / `paceText` / `elapsedText` / `splitCountText` 签名与输出不变；单位行 `accessibilityHidden`，可及 label 用显式合并串复原：`run.distance` 仍为 `0.00 km`（ready）、`run.elapsed` 仍为 `00:00`、`run.currentPace` / `run.averagePace` 空值仍为 `--`（不带 `/km`），既有 RunFlowUI 断言字符串不需改。
- ac-run-single-primary-action: 四态主操作走同一 helper、同一 `safeAreaInset(edge: .bottom)` 锚点与行高、`minHeight = DesignTokens.minTapTarget`；ready = `run.start`（accent）、running = `run.pause`（accent）、paused = `run.resume`（warning）、saved = `run.viewHistory`（success）。
- ac-run-destructive-weaker: running / paused 下 `run.finish` 不与主操作等宽等重——无填充主色底（只 `warning` 描边 / 文字）、水平内在宽度（禁 `frame(maxWidth: .infinity)`）、字号弱于主操作（`body` vs `control`），同时仍 ≥ 44pt 且保留 `accessibilityLabel(Text(label))`。
- ac-run-l10n-and-literals-frozen: `ios/PurePace/Design/L10n.swift` 与 `Resources/Localizable.xcstrings` 零 diff，`RunView` 仍存在 ≥ 4 个互不相同的 `label: L10n.*` 且引用 `L10n.runActionStart / Pause / Resume / Finish`；`RunView` 零字面色值、零散字体修饰符、零动效时长与零样式字面量（`spacing: 0` 必须写 `.zero`，`padding` / `minHeight` / `spacing` 只取 `DesignTokens.*`）。
- ac-surface-history-detail: 历史列表与跑次详情统一使用 `Colors.surface` 卡片面、`Radius.card` 圆角、`Spacing.*` 内边距、`Colors.separator` 分隔，不保留 `.listStyle(.grouped)` / `.listStyle(.insetGrouped)` 的系统默认 grouped 观感；静态断言要求两个视图都引用 surface/radius/separator，移除 surface 引用的反例必须判红。
- ac-run-state-visuals: 记录中 / 暂停 / 保存三态各有明确视觉状态：running 用 `accent`、paused 用 `warning`、saved 用 `success`，记录态与主操作强调共用 accent；三态主操作 identifier、按钮文案与行为不变；静态断言检查三态色引用，把 running 改错为 warning 的反例必须判红。
- ac-a11y-identifier-set-frozen: app 内可及 identifier 集合与基线完全一致（33 项，覆盖 `history.*` / `run.*` / `runDetail.*` / `settings.announcementToggle` / `tab.*`，逐项固定集合以 `scripts/check-ios-shell.sh` 的断言为正本），不新增、不改名、不删除；`validate_design_tokens` 以固定集合逐项比对且总数必须相等，重命名 `run.start` 或追加 `run.extra` 的反例必须判红；既有 6 棵可及树重新采集后集合不变。
- ac-dark-mode-real: `Appearance.supportsDarkMode == true`；全部语义色带 dark 值；暗色下正文/小字对比度 ≥4.5:1、大数字 ≥3:1；真实 dark appearance 模拟器运行（`xcrun simctl ui <udid> appearance dark`）产出 `docs/screenshots/run-running-dark.png`，不得手绘或旧图改色；若暗色确不可用，digest 必须如实写 `pending` 并给出 token 计划。
- ac-screenshots-refreshed: `run-not-started.png` / `run-running.png` / `history-detail.png` / `history-empty.png` / `settings.png` 五张同名覆盖，新增 `run-running-dark.png`；六个文件均为非空 PNG 且来自本轮真实 xcodebuild / simctl 产物；逐文件 sha256 写入 digest；不复用旧图、不手绘、不改色。
- ac-gates-green: `.munk/code-gates.json` 的 22 门全部退出 0；不新增 gate id、不改门列表；`lint-ios-shell --self-test` 全过（≥84 项断言，含本轮与令牌门禁项新增正负反例）；`test-ios --unit-only` 执行到新增对比度与布局阈值单测；`build-ios` 真实构建成功。
- ac-diff-scope-bounded: 代码 diff 仅含 DesignTokens、ContrastPolicy（及可选 DesignComponents）、四个视图 + ContentView 的样式、`scripts/check-ios-shell.sh`、PurePaceTests 断言、`docs/screenshots/*`、`docs/evidence/a11y/*`；状态机、定位、音频、GPX、CI、Android、`project.yml`、本地化键、页面/路由全部零改动。
- ac-digest-receipt: digest.md 三样回执齐全：①新截图路径 + sha256；②新增/扩展断言名 + 关键日志（含反例能红的那一行）；③diff 范围清单；另含设备/OS/Xcode、暗色生成命令、light/dark 对比度数值与 pending 项。

## 非目标

- 深色模式已在阶段 1 收口落地（`supportsDarkMode == true` + 真实暗色模拟器截图），不做深色以外的主题、不做动效/动画专项、不做 Android 视觉对齐、不做截图回归基线。
- 不引入第三方主题系统 / 第三方 UI 依赖 / 跨端框架；不替换系统语义色与系统控件的基本行为。
- 不改状态机与业务契约：`RunSessionViewModel` / `RunSessionOrchestrator` / `RunLocationSource` / AudioSession / TTS / 持久化 / GPX 导出与命名契约零改动。
- 不做英文 / 双语 / 其它 locale（本期 zh-Hans 单语）；不做日期以外的本地化（数字/单位/时区以外不改）。
- 不改 `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿；UI 断言只扩既有 `PurePaceUITests` 用例（新增 1 例 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction`），不新增 gate id。
- 不把示例/种子数据放进首屏或发布业务流；不在 `shared/` 增加夹具。
- 不改 `project.yml` 的 target 结构与依赖：只增本地化声明（`developmentLanguage` / `knownRegions` / `INFOPLIST_KEY_CFBundleDevelopmentRegion`）与把三条策略纯函数列入 UITests sources，无新 target、无新依赖。
- 不做真机验收与设备场；真机项一律 `pending: 待人现场`。

## 实现约束

- Token 为唯一真源：`DesignTokens.Colors` 是唯一颜色出入口（`SRGB` + `ColorPair`，18 对语义色，动态色只 `import SwiftUI` + `UIColor` trait 闭包，不新增 `UIKit` import），视图只引用 token、不改系统控件行为；任何 hex 微调必须用同一 `ContrastPolicy` 重算，把新数值写进 digest 与断言日志，且不得低于 body 4.5:1 / large 3:1 阈值。
- 既有 identifier 是稳定测试契约，原样保留（`run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` / `run.saved` / `history.empty` / `history.row` / `runDetail.*` / `settings.announcementToggle` 等）；新增 identifier 只做可及树定位。
- 静态断言写在既有 `scripts/check-ios-shell.sh` 的 `validate_design_tokens` / `validate_localization`，并在 `--self-test` 补正负反例（token 文件缺失、样式字面量、空 label、缺 Tab 标识、缺控件标识、demo 入口、视图裸英文、缺 String Catalog），**不新增 gate id、不改 `code-gates.json`**；门禁用真实 `grep -Fq`/`grep -Eq` 断言，不用通配允许表；`pipefail` 下禁用 `cmd | grep -q`，改 here-string / 内建匹配。
- 本地化单一来源：新增 `ios/PurePace/Resources/Localizable.xcstrings` 是唯一文案真源；视图只引用 `L10n.*`（`LocalizedStringKey`），需要拼进 `String` 的状态提示走 `String(localized:)`；`RunFormatting` 的 `km` / `/km` 单位拼接属白名单，不改硬编码文案；工程由 XcodeGen 从 `ios/project.yml` 重新生成，禁手改 `project.pbxproj`。
- 日期判定：`RunFormatting.zhHansDateTimeText` / `dateTimeText` 显式 `zh_Hans_CN` + 固定 `dateFormat` + 固定 `TimeZone`，与设备时区/语言无关；历史行与详情共用同一实现，`VisibleDatePolicy` 只判形与字符集。
- 底部锚定与等量分布：`RunView` 主内容与操作区分离，`controls` 只经 `.safeAreaInset(edge: .bottom)` 承载（不写 `Spacer()` 顶开），主按钮 `frame(minHeight: DesignTokens.minTapTarget)`；四态共用同一容器；四层（hero → 次级指标 → 提示 → 主操作）在「导航栏下沿 → 控制区上沿」间由 4 个等权 `Spacer(minLength:)` 等量分布，固定间距只取语义间距 token，取值只用 `DesignTokens.Spacing` / `Radius` / `Stroke`；新增 card / 状态条 / 弱底提示不得把内容撑进 `ViewThatFits` 的滚动分支，也不得改变底部锚点。
- 卡片面与列表：History / Detail 优先保留 `List` + `.plain`（`scrollContentBackground(.hidden)` + token 化行背景 / 圆角 / 内边距 / 分隔），确保 `runDetail.export` 在首屏可见且 UI 用例可直接点击；如改自绘卡片必须证明同一 UI 用例仍能点到导出按钮。
- 设置页静态约束：`validate_settings_view` 禁止 `Stepper` / `Slider` / 「示例」/「Sample」/「暂无可配置项」，新文案须避开这些词。
- 截图造态：只允许 DEBUG 编译期 + 启动参数门控；`HistoryDemoRecords` 整文件 `#if DEBUG` 包裹、不落盘、默认启动不可见；`xcrun simctl io <udid> screenshot` 产出，安装包来自 `bash scripts/build-ios.sh` 的 `.build/ios`。
- 证据口径：只写模拟器 / 单测 / 静态断言结论；深色只能写「真实 dark appearance 模拟器产物」，不得写「真机已验证」；真机项（锁屏后台定位、音频实听、定位授权弹窗观感）一律写 `pending: 待人现场`。

## 最近交付证明

- workItemId: wi_ws_42e16c64648066eb（2026-11-11，pass）
- 交付：跑步页三态五层重建。`RunView.swift` 重排为 hero 距离（`display`，中性面板）→ 用时 / 当前配速（`primaryValue`）→ 平均配速 / 分段（`caption`）→ 提示胶囊 → 底部唯一填充主操作；指标块统一三行（`metricLabel` → 等宽数值 → `metricUnit`），单位行 `accessibilityHidden` 并由显式合并串复原可及 label；`run.finish` 改内在宽度 + `warning` 描边 + `body` 字号（弱于主操作，仍 ≥ 44pt）；零投影 / 零渐变 / 零嵌套双描边。`RunFormatting.swift` 仅新增拆分纯函数，既有签名与输出不变；`RunFormattingTests.swift` 补 3 例。
- 判定与证据：22 门 attempt 001 全绿——`check-ios-shell` 30 项 / `--self-test` 84 项 / `check-baseline` 11 项断言 0 失败，`test-ios --unit-only` 182 例 0 失败（RunCore 141 例亦 0）；冻结 identifier 33 项与状态取色三行原文未变，`L10n` / `xcstrings` / `DesignTokens` / `scripts/**` / `project.yml` 零 diff；`RunFlowUITests` 本机 signal-kill 崩溃经 stash 回 HEAD 复现同一结果，判定环境级 flake 与本次改动无关。
- 偏离与边界：未做保存 / 丢弃二选一与 `finished && didSave == false` 空控制区（留第 4 波）、未接动效与 Reduce Motion、未归档截图、未做真机验收（`pending`）。
