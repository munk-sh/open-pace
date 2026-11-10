# PurePace 三屏视觉层级与设计 Token 收敛（阶段 1 设计先行）

## Scope

在 `main @ f7d1c9f` 现状上做一次「只改样式与信息层级」的收敛，覆盖三屏与一组本地可断言的样式契约：

1. **Token 单一真源**：仓库当前没有 token/样式文件，新建 `ios/PurePace/Design/DesignTokens.swift` 作为唯一来源，集中定义
   颜色、字号、字重、间距档、圆角、图标尺寸、最小触控尺寸；三屏视图只引用 token，不留散落魔法数字。
   不引入第三方主题系统、第三方 UI 依赖或跨端框架。
2. **跑步页**：时长 / 距离 / 当前配速为强主信息（大号、高对比），平均配速 / 分段为次信息（明显更小、次要色）；
   开始 / 暂停 / 继续 / 结束是唯一主操作区，未开始 / 记录中 / 已暂停三态在文案与视觉权重上可辨。
   只改样式与信息层级，不动 CoreLocation / AudioSession / TTS / 持久化 / GPX 契约与状态机。
3. **历史页**：列表项建立「日期（主）→ 距离 / 时长 / 配速（次）」层级；空态给标题 + 一句说明 + 主 CTA「去跑一次」；
   导出入口在跑次详情中可被发现（保留既有「导出 GPX」按钮与流程）。
4. **设置页**：每公里播报开关放进带分组标题的 Section，并给每项一句说明文案；分组标题与说明文案可读
   （不使用低于 caption 的字号）。
5. **可读性与可发现性**：主按钮补显式 `accessibilityLabel`（服务 VoiceOver，不是自动化埋点）；交互控件最小触控区域 ≥ 44pt。
6. **代码层断言**（默认单测腿，进既有 code_gates，不新增模拟器/UI 腿）：
   - token 值本身可单测（间距档单调、字号层级有序、`minTapTarget == 44` 等）；
   - 静态检查三屏只引用 token、无字面量魔法数字；
   - 三屏关键文案与空态字符串存在；
   - 主按钮 a11y label 非空。
7. **截图取证**：构建并安装到已启动的模拟器 iPhone 16（`B3F00298-E08A-41E0-876E-6E8A75C730FD`，iOS 18.6），
   用 `xcrun simctl io <udid> screenshot` 逐屏取证，归档到 `docs/screenshots/`：
   跑步页未开始态、历史页空态、设置页。历史有数据态为可选项（见实现约束的门控条件）。

## Acceptance Criteria

- ac-token-single-source: 存在且仅存在一处设计 token 定义 `ios/PurePace/Design/DesignTokens.swift`，覆盖颜色 / 字号 / 字重 / 间距档 / 圆角 / 图标尺寸 / 最小触控尺寸；`RunView`、`HistoryView`、`SettingsView` 的新增样式全部以 `DesignTokens.` 引用。
- ac-token-values-valid: 单测断言 token 不变量成立——间距档严格递增、字号层级（display > primary > title > body > caption）严格递减/递增方向一致、`DesignTokens.minTapTarget == 44`、圆角与图标尺寸为正且有序。
- ac-no-magic-numbers: 三屏源码中不出现 `.system(size: <数字>`、`spacing: <数字>`、`.padding(<数字>`、`minHeight: <数字>` 形式的样式字面量（系统默认 `.padding()` 不算）；对应负例自检可判失败。
- ac-run-primary-hierarchy: 跑步页距离 / 时长 / 当前配速绑定主信息字号 token，平均配速 / 分段绑定明显更小的次信息 token；单测断言主/次字号比与 token 引用一致。
- ac-run-controls-states: 未开始显示「开始」、记录中显示「暂停」「结束」、已暂停显示「继续」「结束」；三态视觉权重可区分（主操作使用主色调/强调样式，结束使用次要或警示样式），状态机行为零改动。
- ac-run-a11y-labels: 开始 / 暂停 / 继续 / 结束四个按钮均有非空、互不相同的显式 `accessibilityLabel`；静态检查判空即失败。
- ac-tap-target-44: 三屏所有可点击控件（主按钮、空态 CTA、导出按钮、列表行）最小触控高度 ≥ 44pt，且引用 `DesignTokens.minTapTarget`，不写 44 字面量。
- ac-history-row-hierarchy: 历史列表项第一行是日期（headline 级别 token），第二行是距离 / 时长 / 配速（次信息 token 与次要色）；无记录时不渲染任何示例跑次。
- ac-history-empty-state: 空态同时包含非空标题、非空一句说明与 CTA「去跑一次」；字符串在源码中存在且空态不含样例/夹具数据。
- ac-history-export-discoverable: 跑次详情存在可点击的「导出 GPX」入口，位于导航可达的独立分组中，导出流程与既有断言标识不变。
- ac-settings-grouped: 设置页使用带分组标题的 Section（至少「播报」分组），每项有一句说明文案；每公里播报 Toggle 与 `settings.announcementToggle` 标识保留；不出现 Stepper / Slider / 示例数值，不出现「暂无可配置项」。
- ac-copy-strings: 关键文案在源码中存在且非空：`开始`、`暂停`、`继续`、`结束`、`还没有跑次记录`、`去跑一次`、`每公里语音播报`、`导出 GPX`。
- ac-assertions-in-gates: 上述断言通过既有 `test-ios`（`PurePaceTests` 单测）与 `lint-ios-shell`（静态正负自检）两条 gate 运行，二者均绿；`bash scripts/check-ios-shell.sh --self-test` 含新增正例与负例并全绿；不新增 XCUITest 用例、不新增 UI 驱动腿。
- ac-local-gates-green: `bash -n scripts/check-ios-shell.sh`、`bash scripts/check-ios-shell.sh`、`bash scripts/test-ios.sh --unit-only`、`bash scripts/build-ios.sh` 在本机全部退出 0。
- ac-screenshots-archived: `docs/screenshots/run-not-started.png`、`docs/screenshots/history-empty.png`、`docs/screenshots/settings.png` 存在且为 `simctl io screenshot` 产出的非空 PNG；三屏内容分别对应未开始态、空态、设置页，不以 XCTest attachment 顶替。
- ac-no-ui-leg-change: `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿无 diff；既有 identifier 字符串原样保留，新增 identifier 仅用于可及树定位与模拟器测试（见补正 1）；未改动定位 / 音频 / TTS / 持久化 / GPX 契约文件。
- ac-no-sample-in-release: 首屏与发布业务流不出现任何示例/种子跑次；如产出历史有数据态截图，其数据仅由 `#if DEBUG` + 启动参数门控注入，Release 路径不可达，归档截图注记「演示数据不入发布路径」。

## 验收口径补正（公司裁决 `owe_8bea26dc07c9c10e`）

上一 run 因 Host 重启被 cancelled 属承载层中断，本 run 从 coding 续跑并复用既有改动。以下为唯一生效口径，覆盖下文冲突处：

1. **可及标识**：主操作除 `accessibilityLabel` 外必须有 `accessibilityIdentifier`；三个 Tab 与关键控件同样要有可读 label + identifier。
   验收断言 = 从真实构建采集的可及树里能按 identifier 定位到它们。identifier 只用于可及树定位与模拟器测试，不作真机驱动埋点。
2. **证据截图**：交付三张模拟器截图必须是 **首屏 / 运行中（记录态）/ 历史详情**，来自真实 `simctl` 构建、非手绘；
   连同可及树导出文件（文本即可）入仓。运行中 / 历史详情所需数据只用既有 DEBUG 启动参数注入或测试夹具造态，种子数据不得进正常用户路径。
3. **零 demo 入口**：首屏与工作流工具栏的 demo / 示例入口数必须为 0。
4. **Token 范围**：设计 token 覆盖颜色 / 字号 / 间距 / 圆角四类代码常量，禁止散落 magic number；本期不做深色模式，但 token 结构留位（`DesignTokens.Appearance`）。

证据路径（入仓）：

- 截图：`docs/screenshots/run-not-started.png`（首屏）、`docs/screenshots/run-running.png`（运行中/记录态）、`docs/screenshots/history-detail.png`（历史详情）。
- 可及树：`docs/evidence/a11y/01-run-not-started.txt`、`02-run-running.txt`、`04-history-detail.txt`（另含 `03-history-empty.txt` / `05-settings.txt` / `06-tabs.txt`）。
- 造态口径：运行中与历史详情截图使用既有 DEBUG 启动参数（`-uiTestLocation` / `-screenshotHistoryDemo` / `-screenshotOpenRunDetail`）注入，种子数据不入发布路径，截图注记「演示数据不入发布路径」。

反范围不变：不夹带功能项、不碰定位/音频/TTS/持久化/GPX 契约、不开真机与设备场。

## Non-Goals

- 不做真机验收、不写设备脚本、不排设备场、不追 TestFlight；真机相关一律 `pending: 待人现场`。
- 不新增/改动 XCUITest 用例与模拟器 UI 驱动腿；不改 `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿。
- 不新增 accessibility identifier 真机驱动/埋点；新增 identifier 仅用于可及树定位与模拟器测试（见补正 1）。
- 不换状态机、不改 CoreLocation / AudioSession / TTS / 持久化 / GPX 导出与命名契约；不动 `ios/RunCore`、`ios/Core` 的业务契约。
- 不引入主题系统、第三方 UI/主题依赖、跨端框架；不做深色模式专项适配、不做动效/动画专项、不做 Android 视觉对齐。
- 不把示例/种子数据放进首屏或发布业务流；不在 `shared/` 增加夹具。
- 不修改 `project.yml` 依赖与 target 结构（新文件落在既有 `PurePace` 源目录内）。

## Implementation Constraints

- **Token 位置与结构**：`ios/PurePace/Design/DesignTokens.swift`，用无状态的 `enum` 命名空间（如 `DesignTokens`，内含 `Colors` / `Typography` / `Spacing` / `Radius` / `Icon` 与 `minTapTarget`）；颜色优先用系统语义色派生，字号/字重用 `Font`/`Font.Weight`，间距用固定标尺（如 4/8/12/16/24/32）。视图只引用 token，不改系统语义色/控件的基本行为。
- **既有契约优先**：`run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` / `run.start` / `run.pause` / `run.resume` / `run.finish` / `run.saved` / `history.empty` / `history.runAgain` / `history.row` / `runDetail.*` / `settings.announcementToggle` 等 identifier 原样保留；主操作新增 `accessibilityLabel`，并按补正 1 为三个 Tab 与关键控件补齐可及树可定位的 identifier（仅定位/模拟器测试用途，不改既有 identifier 字符串）。
- **跑步页状态机零改动**：只改 `RunView` 的排版与样式；`RunSessionViewModel` / `RunSessionOrchestrator` / 位置源 / 播报链路不动。`RunFormatting` 已有输出字符串（如 `--` 空配速）继续使用。
- **设置页静态约束**：`check-ios-shell.sh` 的 `validate_settings_view` 目前禁止 Settings 源码出现 `Stepper` / `Slider` / 「示例」/「Sample」/「暂无可配置项」；新文案需避开这些词，并保留 `Toggle` 与 `settings.announcementToggle`。
- **断言落点**：
  - 单测：新增 `ios/PurePaceTests/DesignTokensTests.swift`，对 token 不变量（间距单调、字号层级、`minTapTarget == 44`、圆角/图标尺寸为正）做 L1 断言；随既有 `test-ios` gate 运行。
  - 静态检查：在既有 `scripts/check-ios-shell.sh` 增加 `validate_design_tokens` 段（正向：token 文件存在、三屏引用 token、主按钮 a11y label 非空、关键文案存在、无样式字面量；负向：任一条缺失即失败），并在 `--self-test` 增加对应正例/反例；随既有 `lint-ios-shell` gate 运行。**不新增 gate id、不改 `code-gates.json` 的 gate 列表。**
  - 不新增 UI 测试，不靠模拟器 UI 驱动做断言。
- **截图执行口径**：`bash scripts/build-ios.sh` 后从 `.build/ios` 取 `.app` 安装到 `B3F00298-E08A-41E0-876E-6E8A75C730FD`；为免新增 UI 驱动腿，允许新增**仅 DEBUG**、启动参数门控的首屏 Tab 选择（如 `-screenshotInitialTab history|settings`），Release 路径不可达；历史空态用既有 `-uiTestResetArchive`（DEBUG）保证无记录；每屏 `simctl launch` 后 `xcrun simctl io <udid> screenshot docs/screenshots/<name>.png`。不得用 XCTest attachment 顶替；不改 UI 测试脚本与 CI。
- **历史有数据态截图（可选）**：仅当评审确需列表层级时产出 `docs/screenshots/history-with-data.png`；数据必须 `#if DEBUG` + 启动参数门控、使用临时/隔离归档、默认启动不可见、不进 Release、不引用 `shared/fixtures` 或 `.gpx`/`.tcx` 夹具；回执注明「演示数据不入发布路径」。若不做，在回执说明。
- **证据口径**：只写模拟器/单测/静态断言结论；真机项写 `pending: 待人现场`；不得写「真机已验证」。
