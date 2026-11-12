# Domain: ios-history-visual

History 屏（列表 / 详情 / 空态）的视觉层级重建子域：只改 `ios/PurePace/History/**` 内两个视图的**排版与层级**——列表行三层（日期 → 三数值 → 三标签）、详情五段纵向序（元信息 → hero 距离 → 指标网格 → 分段 → 导出）、空态「一句标题 + 一句说明 + 唯一 CTA」，并把行文本抽成与 `RunDetailContent` 同源 `RunFormatting` 的纯值类型。一切颜色 / 字号 / 间距 / 圆角 / 描边只引用既有 `DesignTokens` 令牌（不新增令牌）；导出流程、identifier、文案键、归档与状态机零改动。令牌取值与三屏通用层级仍归 `ios-ui-design`，令牌静态门禁规则归 `design-token-gates`。

## 范围

- `ios/PurePace/History/HistoryView.swift`：行三层（日期 `title`+`primary`；距离/用时/平均配速三数值同一行、`body`+`primary`+`monospacedDigit()`，固定顺序 距离 → 用时 → 配速；三个标签 `metricLabel`+`secondary` 按列一一对应）；三数值组装抽为本文件内纯值类型 `HistoryRowContent`（只读 `RunRecord` 与 `RunFormatting`，含 `accessibilityLabel`）；空态标题 + 一句说明 + 唯一 CTA「去跑一次」，以 `metricGroupSpacing` / `metricGroupGap` 收紧层距。
- `ios/PurePace/History/RunDetailView.swift`：五段纵向序；hero 距离 `display`（数值与单位同属一个 `Text`）；指标网格每格值 `primaryValue`（等宽）在上、标签 `metricLabel`+`secondary` 在下；块间间距交给 `.listSectionSpacing(Spacing.sectionGap)`，卡内用 `metricGroupSpacing`，卡内分隔 `Stroke.hairline` + `separator`；清单仍为 `List` + `.plain` + `scrollContentBackground(.hidden)`。
- `ios/PurePaceTests/RunDetailContentTests.swift`：新增两条 L1 断言（行三数值与详情逐字符相等 + 行日期是详情开始时间前缀；行 a11y label 含 ` km` / `:` / `/km`）。
- 不新增源文件（`HistoryRowContent` 落在既有 `HistoryView.swift`），因此未重生成 `ios/PurePace.xcodeproj`；`ios/project.yml` 零 diff。

## 验收

- ac-history-row-three-tier: 有记录时每行自上而下恰为三层——日期（`title`+`primary`）、距离/用时/平均配速三数值（同一行、等宽、`primary`）、三个标签（`metricLabel`+`secondary`，顺序与数值一一对应）；数值不换到两行，标签不复用数值字重。
- ac-history-row-a11y-contract: `history.row` 仍是单一合并可及元素（`accessibilityElement(children: .combine)`，label 由日期与三数值拼接），label 同时含 ` km`、`:`、`/km`；数据源仍是 `archiveStore.list()`，`injectedRecords` 仅 DEBUG 启动参数注入，Release 默认路径不渲染任何示例跑次。
- ac-history-empty-single-action: 空态恰为「标题 `history.empty` + 一句说明 + 一个 CTA `history.runAgain`」；可点击元素恰 1 个，CTA 保留 `accessibilityLabel(Text(L10n.historyRunAgain))` 与 ≥`minTapTarget` 高度；不出现示例跑次、第二入口或二级导航。
- ac-detail-vertical-order: 详情内容区纵向顺序固定 元信息 → hero 距离 → 指标网格 → 地图 → 分段，不反序、不把 hero 夹在网格之后；导出不参与滚动序（固定底部主操作区，见 `ac-detail-export-reachable`）；块间垂直间距只取 `metricGroupGap` / `sectionGap`，分隔只用 `Stroke.hairline` + `Colors.separator`。
- ac-detail-hero-distance: hero 距离是详情屏最大文字（`display`），其可及元素 label 逐字符等于 `RunDetailContent.distanceText`（与列表行同一子串），不拆成「数值 + 单位」两个元素；`runDetail.distance` 仍可按 identifier 定位。
- ac-detail-metric-grammar-parity: 网格每格值（`primaryValue`，等宽）在上、标签（`metricLabel`+`secondary`）在下，与列表行同一角色映射；`runDetail.activeDuration` / `runDetail.averagePace` / `runDetail.startedAt` / `runDetail.endedAt` 各自仍是独立 staticText（不套合并容器），label 与列表行对应子串逐字一致。
- ac-drilldown-continuity: 行日期文本是详情开始时间（秒精度）的前缀，行内三数值与详情 `distanceText` / `activeDurationText` / `averagePaceText` 逐字符相等；下钻 / 返回同一指标只放大字号、不改变字样（L1 断言）。
- ac-detail-export-reachable: `runDetail.export` 是详情页唯一主操作，渲染在 `List` 之外、底部安全区上方的固定主操作区（`.safeAreaInset(edge: .bottom)`，与 `RunView` 同一锚点写法）；详情首次进入无需滚动即可命中，`List` 内容仍可滚动且导出按钮不在任何 section 内。`RunFlowUITests/testStartFinishExportGPXArtifact` / `testRunPauseResumeFinishAndHistory` 与 `EvidenceCaptureUITests/testEvidenceTreesAndRealArchive`（30s 内取到元素）在「未执行任何滚动」前提下找到并点击 `runDetail.export`；惰性 `List` realize 不再影响导出可见性。点击后 `runDetail.exported` / `runDetail.share` / `runDetail.exportFailed` 仍在首屏可及范围；导出流程、`RunExportState`、`RunGPXExporter` 调用与状态标识零改动，既有断言零删除、超时零放宽。
- ac-detail-export-single-copy: 详情页恰一份导出按钮且只挂在固定主操作区，`List` 内不保留第二份；把导出移回滚动区、或改成「先滚动再找导出」的绕行方案必须判红（首屏不可见即红），不得为转绿放宽用例语义。
- ac-splits-contract: `runDetail.splits` 仍是带条数摘要的 header staticText（`splitSummaryText(count:)`），`runDetail.splitRow` 数量与摘要条数相等，无分段时显示 `runDetail.splitsEmpty`；分段行字号角色可升为 body，数值仍等宽。
- ac-token-only-visuals: 两视图（及 `History/` 内共享视图）零字面色值、零 `.font(.` / 裸 `Font.system(`、零动效时长字面量、零 `.shadow(`、零系统语义色（`.primary` / `.secondary` / `.white` / `.black` / `Color(`）；颜色/字号/间距/圆角/描边全部引用 `DesignTokens.Colors.*` / `Typography.*` / `Spacing.*` / `Radius.card|control` / `Stroke.hairline` / `minTapTarget`。
- ac-single-accent: `Colors.accent` 只出现在可点击控件（`history.runAgain`、`runDetail.export`、`runDetail.share`）与 `.tint`；列表行、hero、指标网格、空态卡面无 accent / accentSoft 装饰性填充；状态色只保留既有 `danger` 失败态，不新增用途。
- ac-dark-and-light-isomorphic: 浅深色走同一布局代码路径（零 `colorScheme` 分支、零 `UIColor` / `UITraitCollection` 引用），全部颜色为成对 token，不使用未在 `ContrastPolicy.pairMatrix` 登记的配色。
- ac-no-truncation-ax5: 两文件零 `lineLimit(` / `minimumScaleFactor` / `truncationMode` / 固定 `.frame(height:`；日期与三数值窄宽下允许换行而不截断，AX5 下不重叠（`DynamicTypeLayoutTests` + 静态 grep 为证）。
- ac-identifier-and-keys-frozen: 33 项 accessibility identifier 集合零增删改名（`lint-ios-shell` 等值断言绿）；`Localizable.xcstrings` 与 `Design/L10n.swift` 零 diff——标签复用既有 `run.metric.*` / `runDetail.field.*` 键。
- ac-gates-green: 22 门全部退出 0（尤其 `lint-ios-shell`（`--self-test` ≥84 项）、`test-ios`、`build-ios`、`test-ios-core`、`test-ios-run-core`、`test`）；不放宽既有断言，不新增 gate id，不改 `.munk/code-gates.json` 与 `scripts/**`。
- ac-scope-bounded: 代码 diff 仅 `ios/PurePace/History/**`（两个视图 + 可选 ≤80 行共享视图）+ 可选 `ios/PurePaceTests/**` 新增断言，以及新增文件带来的 `PurePace.xcodeproj` 重生成；`Design/**`、`ContentView.swift`、`Run/**`、`Settings/**`、`project.yml`、`Resources/**`、`PurePaceUITests/**`、`scripts/**`、`docs/screenshots/**`、`android/**`、`shared/**` 零 diff。
- ac-budget-receipt: `digest.md` 首节写开工时刻、预算时长（建议 100 分钟：列表 ≤30 / 详情 ≤40 / 空态与回归 ≤20 / 证据 ≤10）与期望收口绝对时刻；超时须落盘现状并写「超时停手」+ 未完成项，不静默延长。
- ac-evidence-receipt: `digest.md` 记 ①改动文件清单与 diff 范围；②identifier 集合断言与 `git diff --name-only` 对 `Resources/` / `L10n.swift` / `docs/screenshots/` 为空的证据；③门禁输出片段（命令 + exit code）；④模拟器截图（浅/深只作旁证）路径与 sha256 只落 `.munk/changes/<workItemId>/`，不写 `docs/screenshots/**`。

## 非目标

- 不改导出流程、导出状态标识与 `RunExportState` / `RunGPXExporter` 行为；不改 identifier；不改文案键与 `Localizable.xcstrings`。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`（不新增 token、不改取值），不改 `scripts/**` 与 `.munk/code-gates.json`，不改状态机 / 归档存储 / 定位 / 音频 / GPX。
- 不做 Run 首屏 / 跑步中 / 结束总结 / Settings（同波兄弟子项），不新增 Tab、二级入口、页面或路由，不新建 DesignSystem / 组件库 / 令牌分片文件。
- 不接动画（`Motion.` 视图层引用仍为 0，`.animation(` / `withAnimation(` 新增为 0），不做手势与交互路径重写。
- 不覆盖 `docs/screenshots/**` 与 `SHA256SUMS`；不做真机 / 浏览器 / 桌面 GUI 验收，真机项一律 `pending: 待人现场`；不写 `tech.md`，不排 Design / Architect / PM 阶段。

## 实现约束

- 可消费的既有 token（不新增）：`Typography.metricLabel/metricUnit 11`、`body 15`、`title 20`、`primaryValue 34`、`display 56`、`sectionHeader`、`control`、`caption`；`Spacing.metricGroupSpacing 8` / `metricGroupGap 16` / `cardPadding 16` / `screenTop 24` / `sectionGap 12`；`Radius.card 16` / `control 12`；`Stroke.hairline 1`；`Colors.surface/background/primary/secondary/separator/accent/onAccent/danger`；`minTapTarget 44`。
- 门禁派生扫描：`History/**` 已在 `validate_design_tokens` 受管面内，新增视图文件自动进扫描，因此新文件同样必须零字面量；该函数还要求 History 视图引用 `Colors.secondary` / `minTapTarget` / `monospacedDigit()`，并有 `surface` + `Radius.card` + `separator` 齐备、禁 `.listStyle(.grouped|.insetGrouped)`、禁 `.system(size: N)` / `spacing: N` / `.padding(N)` / `minHeight: N` 字面量；既有断言不得删改。
- identifier 承载元素不可变：`runDetail.startedAt/endedAt/distance/activeDuration/averagePace` 必须继续挂在单个 `Text` 上；`runDetail.root` 在详情根容器、`runDetail.splits` 在分段 header Text、`runDetail.splitRow` 在合并后的分段行、`history.row` 在合并后的行；`history.empty` 在空态标题、`history.runAgain` 在 CTA 按钮。
- 导出固定底部：导出是详情页唯一主操作，按 AGENTS「主操作固定底部安全区上方、一屏一个主操作」走后 `.safeAreaInset(edge: .bottom)`（复用 `RunView` 同一锚点与 `surface` + `separator` 视觉），`List` 只留内容块；既有 `RunFlowUITests` 进详情后直接 `exportButton.tap()` 的语义不变，**禁止**把测试改成「先滚再找导出」或把导出留在 `List` 内靠实现顺序侥幸可见。
- 纯函数接缝：可选的 `HistoryRowContent` 一类纯值类型只依赖 `PurePaceRunCore` 的 `RunRecord` 与 `RunFormatting`，与 `RunDetailContent` 共用同一格式函数；单测断言逐字符相等与前缀关系，不改动既有 `RunDetailContentTests` 成功断言；不得为凑断言引入无消费者的抽象。
- 列表形态：保留 `List` + `.plain` + `scrollContentBackground(.hidden)` + `.listRowSeparator(.hidden)` 与 token 化行背景，不改成 `ScrollView` 自绘列表。
- XcodeGen：新增源文件必须 `xcodegen generate --spec ios/project.yml --project ios` 重生成工程一并提交，禁止手改 `project.pbxproj`。

## 最近交付证明

- workItemId: wi_intake_1127fd3553df6ea7（2026-11-12，pass）
- 交付：`RunDetailView` 把 `runDetail.export` 从 `List` 内 `exportSection` 移到根容器的 `.safeAreaInset(edge: .bottom)` 固定主操作区（复用 `RunView` 锚点与 `surface` + `separator` 视觉），`List` 只剩元信息 / hero / 指标网格 / 地图 / 分段五块；导出仍是唯一主操作且只有一份，惰性 `List` realize 与滚动位置不再影响可见性。
- 判定与证据：`testStartFinishExportGPXArtifact` / `testRunPauseResumeFinishAndHistory` / `testEvidenceTreesAndRealArchive` 在零滚动前提下命中导出；`code_gates` 22 门 attempt 001 全绿（`build-ios` / `test-ios` / `lint-ios-shell` 均 0）；日志 `.munk/logs/d-defect-zhhans.log`、`.munk/logs/b-defect-ui-subset.log`。
- 偏离与边界：导出流程 / `RunExportState` / `RunGPXExporter` 与 identifier 零改动；详情视觉截图未重出（`pending: 待人现场`）。
