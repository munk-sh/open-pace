# iOS 三屏视觉体系阶段 1 收口

基线 `main 01b5f28`。本项是公司裁决「阶段 1 视觉收口走 A」的唯一依据：把当前「干净但纯 iOS 默认」的 Run / History / Settings 三屏改成有识别度的统一视觉体系，并把规则固化成可反向失败的门断言；交回后公司按真实截图判定设计感。

## 范围

- `ios/PurePace/Design/DesignTokens.swift`：唯一 token 真源。建立单一品牌主色与成对 light/dark 语义色（背景、卡片面、弱面、正文、次文、主色、主色上的文字、警示、成功、危险及其弱底、分隔），字号/字重/行距/间距/圆角/图标/描边/最小触控尺寸全部集中在此。
- `ios/PurePace/Design/ContrastPolicy.swift`（新增）：不依赖 SwiftUI 的纯函数，按 WCAG 2.x 计算成对 sRGB token 的对比度；缺对、空值、分量越界一律 fail-closed。
- `ios/PurePace/Design/DesignComponents.swift`（新增，可选但推荐）：`SurfaceCard`、主操作/次操作按钮样式等最小复用件；只允许引用 token，不允许字面色值和零散字体修饰符。
- `ios/PurePace/Run/RunView.swift`：距离 hero / 次级指标 / 提示 / 底部主操作四层；记录中 / 暂停 / 保存三态各有明确视觉状态；所有数字等宽；指标块与底部控制区的既有布局契约不变。
- `ios/PurePace/History/HistoryView.swift`、`ios/PurePace/History/RunDetailView.swift`：用统一 `surface` 卡片面、`Radius.card` 圆角、`Spacing.*` 内边距、`Colors.separator` 分隔替代系统默认 grouped 观感；列表行与详情数值等宽；导航、导出与既有 identifier 不变。
- `ios/PurePace/Settings/SettingsView.swift`：分组标题、每项说明与开关继续保留，颜色/字体全部换成 token；开关 tint 使用品牌主色；不新增控件与文案。
- `scripts/check-ios-shell.sh`：扩展现有 `validate_design_tokens`（零字面色值、零散字体修饰符、暗色开关、surface 卡片引用、四层引用、a11y identifier 集合冻结），并在 `--self-test` 补正负反例；不新增 gate id，不改 `code-gates.json` 门列表。
- `ios/PurePaceTests/DesignTokensTests.swift`（扩展现有 token 不变量，暗色开关改 true）与新增对比度单测：达标正例通过、低对比反例判红、非法分量 fail-closed；实测比值打印到日志。
- `docs/screenshots/`：5 张同名图由本轮真实 xcodebuild 产物覆盖，新增 1 张暗色运行态 `run-running-dark.png`；`docs/evidence/a11y/01..06-*.txt` 重新采集，identifier 集合不变。
- `.munk/changes/wi_intake_a6d5c85453b8ceab/digest.md`：截图路径与 sha256、断言名与关键日志（含反例判红）、diff 范围、对比度数值、设备/OS/Xcode、暗色命令与 pending 项。
- `.munk/changes/wi_intake_a6d5c85453b8ceab/ux/design-baseline.md`：token 源、组件清单、主屏与关键取舍；不改 `.munk/baseline/**`。

## 验收

- ac-brand-primary-token: 全仓只有一个品牌主色语义 token（`DesignTokens.Colors.accent`），记录态、主操作、强调共用它；`accent`/`onAccent` 与全部语义色均以 light/dark 成对定义；RunView / HistoryView / SettingsView / RunDetailView / ContentView 与 Design 组件文件中 `Color(`、`Color.`、`UIColor`、`#colorLiteral`、`.foregroundStyle(.` 命中数为 0。静态门正例通过，追加字面色值的反例必须判红。
- ac-brand-contrast: `ContrastPolicy` 纯函数按 WCAG 2.x 计算 token 对比度；正文/小字（primary、secondary、warning、success、danger 及其弱底）light/dark 均 ≥4.5:1，hero 大数字 ≥3:1；逐对实测值打印为 `ac-contrast ...` 日志并写入 digest。单测必须含：一个达标正例通过、一个低对比反例（如 `#AAAAAA` on `#FFFFFF`）判红、分量越界 fail-closed。
- ac-monospaced-metrics: 距离、用时、当前配速、平均配速、分段以及历史行、详情数值全部使用 `.monospacedDigit()`；hero 指标固定为距离（`Typography.display`），用时/当前配速为次级主值（`Typography.primaryValue`），平均配速/分段为再次级（`Typography.caption`）；三屏与详情无 `spacing: <数字>`、`.padding(<数字>`、`minHeight: <数字>`、`.system(size: <数字>` 样式字面量。
- ac-typography-token-only: 字号、字重、行距只从 `DesignTokens.Typography` 取；视图与 Design 组件中 `.font(.`、`.fontWeight(`、`.fontDesign(`、`.lineSpacing(<数字>` 命中数为 0（`.font(DesignTokens.Typography.*)` 与 `.monospacedDigit()` 允许）。静态门正例通过，追加零散字体修饰符的反例必须判红。
- ac-run-four-layers: 首屏与运行态可一眼分出四层：hero 距离（display，最大）→ 次级指标（primaryValue：用时/当前配速；caption：平均配速/分段）→ 提示（caption + 次要色/警示色，带弱底）→ 主操作（底部 accent 按钮）。静态断言检查 display / primaryValue / caption / `safeAreaInset(edge: .bottom)` 与状态色引用；5 图证据可见该层级。
- ac-surface-history-detail: 历史列表与跑次详情统一使用 `Colors.surface` 卡片面、`Radius.card` 圆角、`Spacing.*` 内边距、`Colors.separator` 分隔，不保留 `.listStyle(.grouped)` / `.listStyle(.insetGrouped)` 的系统默认 grouped 观感；静态断言要求两个视图都引用 surface/radius/separator，移除 surface 引用的反例必须判红。
- ac-run-state-visuals: 记录中 / 暂停 / 保存三态各有明确视觉状态：running 用 `accent`、paused 用 `warning`、saved 用 `success`，记录态与主操作强调共用 accent；三态主操作 identifier、按钮文案与行为不变。静态断言检查 running/paused/saved 对应的 accent/warning/success 引用，把 running 改错为 warning 的反例必须判红。
- ac-a11y-identifier-set-frozen: app 内可及 identifier 集合与基线完全一致（33 个，见实现约束），不新增、不改名、不删除；`validate_design_tokens` 以固定集合逐项比对且总数必须相等，重命名 `run.start` 或追加 `run.extra` 的反例必须判红；既有 6 棵可及树重新采集后 identifier 集合不变。
- ac-dark-mode-real: `Appearance.supportsDarkMode == true`；全部语义色带 dark 值；暗色下正文/小字对比度 ≥4.5:1、大数字 ≥3:1；真实 dark appearance 模拟器运行产出 `docs/screenshots/run-running-dark.png`，不得手绘或旧图改色。若暗色确不可用，digest 必须如实写 `pending` 并给出 token 计划，不得静默交付。
- ac-screenshots-refreshed: `docs/screenshots/` 的 `run-not-started.png` / `run-running.png` / `history-detail.png` / `history-empty.png` / `settings.png` 五张同名覆盖，新增 `run-running-dark.png`；六个文件均为非空 PNG 且来自本轮真实 xcodebuild/simctl 产物；逐文件 sha256 写入 digest；不复用旧图、不手绘、不改色。
- ac-gates-green: `code-gates.json` 的 22 门全部退出 0；不新增 gate id、不改门列表；`lint-ios-shell --self-test` 全过；`test-ios --unit-only` 执行到新增对比度单测；`build-ios` 真实构建成功；既有布局/文案/日期三条断言的阈值与策略文件零 diff。
- ac-diff-scope-bounded: 代码 diff 仅含 DesignTokens、ContrastPolicy（及可选 DesignComponents）、四个视图样式、`scripts/check-ios-shell.sh`、PurePaceTests 断言、`docs/screenshots/*`、`docs/evidence/a11y/*`、XcodeGen 生成的 `project.pbxproj`；状态机、定位、音频、GPX、CI、Android、`project.yml`、本地化键、页面/路由全部零改动。
- ac-digest-receipt: digest.md 三样回执齐全：①新截图路径 + sha256；②新增/扩展断言名 + 关键日志（含反例能红的那一行）；③diff 范围清单；另含设备/OS/Xcode、暗色生成命令、light/dark 对比度数值与 pending 项。

## 非目标

- 不碰状态机、定位、音频、GPX、CI、Android；`RunSessionViewModel` / `RunSessionOrchestrator` / `RunLocationSource` / AudioSession / TTS / 持久化 / 导出契约零改动。
- 不新增页面、路由、Tab 或导航层级；不新增用户可见文案、不改本地化键与既有文案语义。
- 不做自定义图标资产管线；只用 SF Symbols 选型/字重或纯形状，不新增图标资源。
- 不做深色以外的主题、不做动效专项、不做截图回归基线、不做 Android 视觉对齐。
- 不引入第三方 UI/主题依赖、跨端框架、自定义字体或 Asset Catalog 色彩集。
- 不改 `project.yml` 的 target 结构与依赖；不新增 gate id、不改 `code-gates.json` 门列表。
- 不改既有三条布局/文案/日期断言的阈值：`RunLayoutBalancePolicy`（160 / 40）、`PrimaryActionLayoutPolicy`（44 / 24）、`VisibleTextPolicy` / `VisibleDatePolicy` 的策略文件零 diff。
- 不做真机验收；锁屏定位、音频实听等真机项一律 `pending: 待人现场`。

## 实现约束

### 品牌与调色板（已实测，直接落地）

主色取「松针青 / 跑道青」：深青绿既有运动感又不与 iOS 默认蓝、警示橙、成功绿、危险红混淆；light 用作按钮底时白字 6.07:1，dark 用薄荷青保持夜间能量感。记录态、主操作、强调三者共用 `Colors.accent` 同一 token。

| 语义 token | Light | Dark | 用途 |
|---|---|---|---|
| background | `#F7F8F6` | `#0A1211` | 页面底色 |
| surface | `#FFFFFF` | `#141F1D` | 卡片面 / 底栏 |
| surfaceMuted | `#F0F3F1` | `#1A2724` | 提示弱底 / 次级面板 |
| primary | `#12201E` | `#ECF4F1` | 正文 / hero |
| secondary | `#566663` | `#A6B8B3` | 次文 / 字段标签 |
| accent | `#0B6F60` | `#5ED6C4` | 品牌主色 / 主操作 / 记录态 / 强调 |
| onAccent | `#FFFFFF` | `#06211C` | 主色上的文字 |
| accentSoft | `#EDF6F3` | `#123B34` | 记录态弱底 |
| separator | `#DCE5E1` | `#25332F` | 卡片描边 / 分隔 |
| warning | `#9A5B00` | `#F5B84C` | 暂停 / 结束 / 降级提示 |
| onWarning | `#FFFFFF` | `#2B1A00` | 警示底上的文字 |
| warningSoft | `#FDF3E1` | `#3A2A0D` | 警示弱底 |
| success | `#147A4E` | `#5BD69B` | 已保存 |
| onSuccess | `#FFFFFF` | `#042416` | 成功底上的文字 |
| successSoft | `#E8F6EF` | `#11311F` | 成功弱底 |
| danger | `#B3261E` | `#FF8A80` | 失败态 |
| onDanger | `#FFFFFF` | `#3A0906` | 危险底上的文字 |
| dangerSoft | `#FCEBE9` | `#3A1A17` | 危险弱底 |

已实测 WCAG 比值（sRGB，按 WCAG 2.x 相对亮度）：

- Light：primary/background 15.76；primary/surface 16.79；secondary/background 5.67；secondary/surface 6.04；accent/background 5.70；onAccent/accent 6.07；accent/accentSoft 5.52；warning/warningSoft 4.93；success/successSoft 4.81；danger/dangerSoft 5.66。
- Dark：primary/background 16.95；primary/surface 15.10；secondary/background 9.15；secondary/surface 8.15；accent/background 10.74；onAccent/accent 9.57；accent/accentSoft 6.99；warning/warningSoft 7.81；success/successSoft 7.78；danger/dangerSoft 6.86。

若 Coding 微调任一 hex，必须用同一纯函数重算，并把新数值写进 digest 与断言日志；不得低于上述阈值。

### Token 与断言落点

- Token 用 `SRGB`（0...1 三分量）+ `ColorPair { light, dark }` 表达；动态 `Color` 用 `Color(uiColor: UIColor { trait in ... })`，只 `import SwiftUI`（已验证可编译），不新增 `UIKit` import，保持 `validate_app_imports` 允许表不变。
- `ContrastPolicy` 为 Foundation-only 纯函数：`ratio(foreground:background:) -> Double?` 与 `problems(for:) -> [String]`；阈值常量 body 4.5、large 3.0；缺对/空值/越界一律返回问题（fail-closed）。单测逐对打印 `ac-contrast <pair> <ratio>`，并断言 `problems.isEmpty`；低对比反例必须产出非空问题。
- `validate_design_tokens` 扩展（不新增 gate id）：
  - 字面色值：扫描四个视图 + `ContentView` + `ios/PurePace/Design/**` 中非 `DesignTokens.swift` 的组件文件，命中 `Color(|Color\.|UIColor|#colorLiteral|\.foregroundStyle(\.[A-Za-z]` 即失败；正例通过，追加 `.foregroundStyle(Color.red)` 反例判红。
  - 零散字体：同一扫描面，命中 `\.font\(\.|\.fontWeight\(|\.fontDesign\(|\.lineSpacing\([0-9]` 即失败；正例通过，追加 `.font(.system(size: 12))` 或 `.fontWeight(.bold)` 反例判红。
  - 暗色：token 文件必须含 `supportsDarkMode = true`，且 `light:` / `dark:` 成对计数一致；把 true 改成 false 的反例判红。
  - 卡片面：HistoryView 与 RunDetailView 必须同时引用 `DesignTokens.Colors.surface`、`DesignTokens.Radius.card`、`DesignTokens.Colors.separator`；移除 surface 引用的反例判红。
  - 四层：RunView 必须引用 `Typography.display` / `primaryValue` / `caption`、`Colors.accent`、`safeAreaInset(edge: .bottom)`；缺任一判红。
  - 数字：RunView 至少 3 处 `.monospacedDigit()`（覆盖距离、主值、次值三个 Text 函数），HistoryView 与 RunDetailView 各至少 1 处；缺失判红。
  - identifier 集合：提取 `accessibilityIdentifier("...")` 与 `identifier: "..."` 中属于 `run.* / runDetail.* / history.* / tab.* / settings.*` 的值，排序去重后必须与固定 33 项集合完全相等；重命名或追加的反例判红。
- identifier 固定集合（33 项）：`history.empty`、`history.row`、`history.runAgain`、`run.averagePace`、`run.backgroundDegraded`、`run.currentPace`、`run.distance`、`run.elapsed`、`run.finish`、`run.pause`、`run.resume`、`run.saved`、`run.splits`、`run.start`、`run.telemetry`、`run.viewHistory`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.distance`、`runDetail.endedAt`、`runDetail.export`、`runDetail.exportFailed`、`runDetail.exported`、`runDetail.root`、`runDetail.share`、`runDetail.splitRow`、`runDetail.splits`、`runDetail.splitsEmpty`、`runDetail.startedAt`、`settings.announcementToggle`、`tab.history`、`tab.run`、`tab.settings`。
- 视图层级与卡片：RunView 的指标内容块继续在「导航栏下沿 → 控制区上沿」间整体居中；新增 surface 卡片/状态条/弱底提示不得把内容撑到 `ViewThatFits` 的滚动分支，也不得改变 `safeAreaInset` 底部锚点；主按钮仍 `minHeight: DesignTokens.minTapTarget`。History/Detail 优先保留 `List` + plain 样式 + token 化行背景/圆角/内边距/分隔，确保 `runDetail.export` 在首屏可见且 UI 用例可直接点击；如改用自绘卡片，必须证明同一 UI 用例仍能直接点到导出按钮。
- 截图与证据：先 `cd ios && xcodegen generate`（不手改 pbxproj），`bash scripts/build-ios.sh` 构建，运行既有 `PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 取得 light 5 图 + 6 树；再用 `xcrun simctl ui <udid> appearance dark` 真实切暗色，重跑同一用例取得 `run-running` 附图，导出为 `docs/screenshots/run-running-dark.png`，最后切回 light。截图来自 xcresult 附件或 `simctl io screenshot`，禁止手绘/旧图改色。
- 环境口径：基线 `01b5f28`；优先复用本机 iPhone 16（iOS 18.6，Xcode 26.3）与既有截图命令；实际设备/OS/Xcode 写入 digest。
- 预算与停手：≤8M token、≤90 分钟；超限立即停手，交半成品 + 已完成证据 + 未完成清单；不许靠长会话自查补绿、不许扩点。
