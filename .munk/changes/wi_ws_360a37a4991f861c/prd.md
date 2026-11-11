# History 列表 / 详情 / 空态重建

WorkSet 第 3 波（核心屏重建）的 History 切片。前置已交付：`wi_ws_29e408731605ee3a`（竞品拆解，结论「单一品牌色只标可执行/选中、大圆角零投影 + hairline 分层、字号极端对比、数值等宽原地刷新」）、`wi_ws_d2340f794eac5a6c`（令牌真源：`Typography.metricLabel/metricUnit 11`、`Spacing.metricGroupSpacing/metricGroupGap/cardPadding`、`Motion`、36 对对比度矩阵）、`wi_ws_92e2e6cbdf3f17ec`（静态门按目录派生扫描 History/**，零字面色值/零散字体/动效字面量、33 项 identifier 等值冻结）。

现状：`HistoryView` 行是「日期 title + 单行 `a · b · c` 文本（body + secondary）」，没有标签层；`RunDetailView` 是四段等权字段列表（开始/结束 → 距离/时长/配速 → 分段 → 导出），所有字段同为 body 字号，没有 hero，也没有和列表共用的数值/标签语法。两者层级靠卡片堆叠而非字号/字重/色彩建立，正是「非常素」的直接来源。

本子项只重排这三块的视觉层级，不动功能面：列表行三数值 + 标签、详情的「元信息 → hero 距离 → 指标网格 → 分段」纵向序、空态的单标题 + 单说明 + 唯一 CTA。

## 范围

1. **列表行三层**（`ios/PurePace/History/HistoryView.swift`）：第一行日期（`Typography.title` + `Colors.primary`）；第二行距离 / 用时 / 平均配速三数值（等宽数字，`Typography.body` + `Colors.primary`，固定顺序 距离 → 用时 → 配速）；第三行三个标签（复用既有键 `L10n.runMetricDistance`「距离」/ `L10n.runMetricTime`「用时」/ `L10n.runMetricAverage`「平均配速」，`Typography.metricLabel` + `Colors.secondary`）。行仍是 `surface` + `Radius.card` + `separator` hairline 描边 + `minTapTarget` 最小高度，零投影。
2. **详情纵向序**（`ios/PurePace/History/RunDetailView.swift`）：顶部元信息（开始 / 结束，带秒）→ hero 距离（`Typography.display`，全屏最大文字）→ 指标网格（用时 / 平均配速，值 `Typography.primaryValue` 在上、标签 `Typography.metricLabel` 在下）→ 分段（摘要 header + 行，或诚实空态）→ 导出区（含既有 exported / share / failed 反馈）。块间只用 `Spacing.metricGroupGap` / `Spacing.sectionGap` 语义间距与 `Stroke.hairline` 分隔。
3. **同构语法**：列表行与详情网格共用同一「数值在上 + 标签在下」结构与同一角色映射（标签恒 `metricLabel` + `secondary`；数值等宽；列表行 body、网格 primaryValue、hero display），数值文本一律来自 `RunFormatting` 同一实现，因此下钻/返回时同一指标的字样不跳变。
4. **空态**（`HistoryView`）：一句标题 + 一句说明 + 唯一 CTA「去跑一次」，卡面 `surface` + `Radius.card` + hairline，标题/说明/按钮三级落差靠 `title` → `body` → `control` 与 `primary` / `secondary` / `onAccent` 建立。
5. **可断言化（按需最小）**：允许把行文本组装抽成 `History/` 内 ≤80 行纯值类型（与 `RunDetailContent` 同源 `RunFormatting`），并在 `ios/PurePaceTests` 加 L1 断言（行数值 == 详情数值逐字符相等、行日期是详情开始时间前缀）。不得为凑断言引入无消费者的抽象。

## 验收

- ac-history-row-three-tier: 有记录时每行自上而下恰为三层——日期（`Typography.title` + `Colors.primary`）、距离/用时/平均配速三数值（同一行、等宽数字、`Colors.primary`）、三个标签（`Typography.metricLabel` + `Colors.secondary`，顺序与数值一一对应）；行内数值不换到两行，标签不复用数值字重。
- ac-history-row-a11y-contract: `history.row` 仍是单一合并可及元素（`accessibilityElement(children: .combine)` + label 由日期与三数值拼接），label 同时含 ` km`、`:`、`/km`；行的数据源仍是 `archiveStore.list()`，`injectedRecords` 仅 DEBUG 启动参数注入，Release 默认路径不渲染任何示例跑次。
- ac-history-empty-single-action: 空态恰好由「标题（`history.empty`）+ 一句说明 + 一个 CTA（`history.runAgain`）」组成，空态内可点击元素恰为 1 个，CTA 保留 `accessibilityLabel(Text(L10n.historyRunAgain))` 与 ≥`minTapTarget` 高度；空态不出现示例/夹具跑次、不出现第二个入口或二级导航。
- ac-detail-vertical-order: 详情纵向顺序固定为 元信息 → hero 距离 → 指标网格 → 分段 → 导出，不得反序或把 hero 夹在网格之后；块间垂直间距只取 `Spacing.metricGroupGap` / `sectionGap`，分隔只用 `Stroke.hairline` + `Colors.separator`。
- ac-detail-hero-distance: hero 距离是详情屏上最大文字（`Typography.display`），其可及元素 label 逐字符等于 `RunDetailContent.distanceText`（与列表行内的同一子串），不得拆成「数值 + 单位」两个元素；`runDetail.distance` 仍能被 `app.staticTexts[...]` 按 identifier 定位。
- ac-detail-metric-grammar-parity: 网格每格结构为值（`Typography.primaryValue`，等宽）在上、标签（`Typography.metricLabel` + `Colors.secondary`）在下，与列表行同一角色映射；`runDetail.activeDuration` / `runDetail.averagePace` / `runDetail.startedAt` / `runDetail.endedAt` 各自仍是**独立** staticText（不得套 `.accessibilityElement(children: .combine)` 容器），label 与列表行内对应子串逐字一致（L1 断言）。
- ac-drilldown-continuity: 列表行日期文本是详情开始时间（秒精度）的前缀，且行内三数值与详情 `distanceText` / `activeDurationText` / `averagePaceText` 逐字符相等；因此从行下钻到详情、返回列表时同一指标只放大字号、不改变字样（L1 纯函数断言，可放 `RunDetailContentTests`）。
- ac-detail-export-reachable: 进入详情后**无需滚动**即可点击 `runDetail.export`，点击后 `runDetail.exported` / `runDetail.share` / `runDetail.exportFailed` 仍在首屏可及范围内；导出流程、`RunExportState`、`RunGPXExporter` 调用与状态标识零改动；既有 `RunFlowUITests` 的详情步骤与断言一行未改即可通过。
- ac-splits-contract: `runDetail.splits` 仍是带条数摘要的 header staticText（`splitSummaryText(count:)`），`runDetail.splitRow` 数量与摘要条数相等，无分段时显示 `runDetail.splitsEmpty`；分段行的字号角色可升为 body，但数值仍等宽。
- ac-token-only-visuals: 两个视图（及可选的 `History/` 内共享视图）零字面色值、零 `.font(.` / 裸 `Font.system(`、零动效时长字面量、零 `.shadow(`、零系统语义色（`.primary` / `.secondary` / `.white` / `.black` / `Color(`）；颜色/字号/间距/圆角/描边全部引用 `DesignTokens.Colors.*`（成对语义色）/ `Typography.*` / `Spacing.*` / `Radius.card|control` / `Stroke.hairline` / `minTapTarget`。
- ac-single-accent: `Colors.accent` 只出现在可点击控件（`history.runAgain`、`runDetail.export`、`runDetail.share`）与 `.tint`；列表行、hero、指标网格、卡片面、空态卡面上没有 accent / accentSoft 装饰性填充；状态色仅保留既有语义（导出失败态 `danger`），不新增状态色使用。
- ac-dark-and-light-isomorphic: 浅色与深色走同一布局代码路径（零 `colorScheme` 分支、零 `UIColor` / `UITraitCollection` 引用），所有颜色均为 light/dark 成对 token，因此浅深色结构同构；不使用任何未在 `ContrastPolicy.pairMatrix` 登记的配色。
- ac-no-truncation-ax5: 两文件零 `lineLimit(` / `minimumScaleFactor` / `truncationMode` / 固定 `.frame(height:`；日期与三数值在窄宽下允许换行而不截断，AX5 最大字号档下不重叠（以既有 `DynamicTypeLayoutTests` 与静态 grep 证据为准）。
- ac-identifier-and-keys-frozen: 33 项 accessibility identifier 集合零增删改名（`lint-ios-shell` 等值断言绿）；`ios/PurePace/Resources/Localizable.xcstrings` 与 `ios/PurePace/Design/L10n.swift` 零 diff——标签复用既有 `run.metric.*` / `runDetail.field.*` 键，不新增、不改名文案键。
- ac-gates-green: 22 门全部退出 0，尤其 `lint-ios-shell`（含 `--self-test` ≥84 项）、`test-ios`（`--unit-only`）、`build-ios`、`test-ios-core`、`test-ios-run-core`、`test`；不靠放宽既有断言补绿，不新增 gate id、不改 `.munk/code-gates.json`、不改 `scripts/**`。
- ac-scope-bounded: 代码 diff 仅 `ios/PurePace/History/**`（两个视图 + 可选 ≤80 行共享视图）+ 可选 `ios/PurePaceTests/**` 新增断言，以及新增文件带来的 `ios/PurePace.xcodeproj` 重生成；`ios/PurePace/Design/**`、`ios/PurePace/ContentView.swift`、`ios/PurePace/Run/**`、`ios/PurePace/Settings/**`、`ios/project.yml`、`ios/PurePace/Resources/**`、`ios/PurePaceUITests/**`、`scripts/**`、`docs/screenshots/**`、`android/**`、`shared/**` 零 diff。
- ac-budget-receipt: `digest.md` 首节写开工时刻、预算时长（建议 100 分钟：列表 ≤30 / 详情 ≤40 / 空态与回归 ≤20 / 证据 ≤10）与期望收口绝对时刻；预算耗尽仍未完成时落盘现状并写「超时停手」+ 未完成项，不得静默延长会话。
- ac-evidence-receipt: `digest.md` 记 ①改动文件清单与 diff 范围；②identifier 集合断言与 `git diff --name-only` 对 `Resources/` / `L10n.swift` / `docs/screenshots/` 为空的证据；③门禁输出片段（含命令与 exit code）；④若产出模拟器截图（浅/深只作旁证，不作为验收前置），路径与 sha256 只落 `.munk/changes/<workItemId>/`，不写 `docs/screenshots/**`。

## 非目标

- 不改导出流程、导出状态标识与 `RunExportState` / `RunGPXExporter` 行为；不改 accessibility identifier；不改文案键与 `Localizable.xcstrings`。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`（不新增 token、不改取值）、不改 `scripts/**` 与 `.munk/code-gates.json`、不改状态机 / 归档存储 / 定位 / 音频 / GPX。
- 不做 Run 首屏 / 跑步中 / 结束总结 / Settings（同波兄弟子项），不新增 Tab、二级入口、页面或路由，不新建 DesignSystem / 组件库 / 令牌分片文件。
- 不接动画（`Motion.` 视图层引用仍为 0，`.animation(` / `withAnimation(` 新增为 0）、不做手势与交互路径重写。
- 不覆盖 `docs/screenshots/**` 与 `docs/screenshots/SHA256SUMS`；不做真机、浏览器、桌面 GUI 验收；真机项一律 `pending: 待人现场`。
- 不写 `tech.md`；不为本子项排 Design / Architect / PM 阶段。

## 实现约束

- **可消费的既有 token（不新增）**：`Typography.metricLabel/metricUnit(11)`、`body(15)`、`title(20)`、`primaryValue(34)`、`display(56)`、`sectionHeader`、`control`；`Spacing.metricGroupSpacing(8)` / `metricGroupGap(16)` / `cardPadding(16)` / `screenTop(24)` / `sectionGap(12)`；`Radius.card(16)` / `control(12)`；`Stroke.hairline(1)`；`Colors.surface/background/primary/secondary/separator/accent/onAccent/danger`；`minTapTarget(44)`。
- **门禁派生扫描**：`History/**` 已在 `validate_design_tokens` 的受管面内，新增视图文件自动进扫描；因此新文件必须同样零字面量。`validate_design_tokens` 还要求 History 视图引用 `DesignTokens.Colors.secondary`、`minTapTarget`、`monospacedDigit()` ≥1、`surface`/`Radius.card`/`separator` 三者齐备、禁止 `.listStyle(.grouped|.insetGrouped)`、禁止 `.system(size: N)` / `spacing: N` / `.padding(N)` / `minHeight: N` 字面量；既有断言不得删改。
- **identifier 承载元素不可变**：`runDetail.startedAt/endedAt/distance/activeDuration/averagePace` 必须继续挂在单个 `Text` 上（`app.staticTexts[...]` 按 identifier 定位），`runDetail.root` 在详情根容器、`runDetail.splits` 在分段 header Text、`runDetail.splitRow` 在合并后的分段行、`history.row` 在合并后的行；`history.empty` 在空态标题、`history.runAgain` 在 CTA 按钮。
- **导出首屏可及**：现有 `RunFlowUITests` 进入详情后直接 `exportButton.tap()` 并立刻断言 `runDetail.exported` / `runDetail.share` 出现，全程无滚动；hero + 网格重排后仍须满足该时序（导出入口与导出的三种反馈都在首屏可命中）。若重排后无法满足，优先压缩上方块的垂直间距与分段区默认高度，不得改测试或降级导出交互。
- **纯函数接缝**（可选）：若抽 `HistoryRowContent` 一类纯值类型，只依赖 `PurePaceRunCore` 的 `RunRecord` 与 `RunFormatting`，与 `RunDetailContent` 共用同一格式函数；单测断言逐字符相等与前缀关系，不改动既有 `RunDetailContentTests` 的成功断言。
- **XcodeGen**：新增源文件必须 `xcodegen generate --spec ios/project.yml --project ios` 重新生成 `ios/PurePace.xcodeproj` 一并提交，禁止手改 `project.pbxproj`；若全部改动落在既有两个文件则不重生成。
- **列表形态**：保留 `List` + `.plain` + `scrollContentBackground(.hidden)` + `.listRowSeparator(.hidden)` 与 token 化行背景（保住 `runDetail.export` 的可点性与既有 UI 用例），不改成 `ScrollView` 自绘列表。
- **预算**：开工先在 `digest.md` 写预算与期望收口绝对时刻，超时按 `ac-budget-receipt` 停手回执。
- 本子项为 WorkSet 子项，`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 `false`；Design / Architect 结论不追加，视觉依据取自 `docs/design/competitor-teardown.md` 与 `docs/design` 基线。
