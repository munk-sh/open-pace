# Domain: ios-history-flow

History 侧的**状态与导航闭环**子域：下钻 / 返回、空态 CTA 回到可用 Run 首屏、归档读取失败态与重试、`refreshToken` 刷新一致性。只做状态机与导航接线，不做视觉重排（层级与令牌归 `ios-history-visual` / `ios-ui-design`），不改导出流程、identifier、文案键与归档语义。

## 范围

- `ios/PurePace/History/HistoryViewState.swift`：不依赖 SwiftUI 的纯值状态类型——`HistoryLoadOutcome`（`loaded([RunRecordSummary])` / `failed`，Equatable）、`summaries` 轻量摘要集合、`path: [UUID]` 单一导航路径、`loadedToken` 读取守卫、`shouldLoad(token:force:)` / `load(token:force:using:)` / `open(recordID:)` / `popToRoot()` / `openFirstDetailIfNeeded(autoOpen:)` / `reconcilePath()`。
- `ios/PurePace/History/HistoryView.swift`：`NavigationStack(path:)` + 行 `NavigationLink(value: summary.id)` + `navigationDestination(for: UUID.self)` 单一详情真源；生产路径只调 `archiveStore.listSummaries()`，行内容全部来自 `RunRecordSummary`（`HistoryRowContent(summary:)`，保留 `init(record:)` 供详情/注入）；详情在 destination 内按 id 调 `archiveStore.record(withID:)` 懒解码完整 `samples`；失败态视图只渲染 `L10n.runActionRetryLocation` 重试按钮；空态 CTA 先 `popToRoot()` 再 `onRunAgain()`。
- DEBUG 注入取证路径 `injectedRecords: [RunRecord]?` 保留：读列表时 `map(RunRecordSummary.init(record:))`，详情直接取注入记录，不落盘。
- `ios/PurePaceTests/HistoryViewStateTests.swift`：以可抛错假 loader 钉住读取成功 / 失败、重试恢复、同 token 只读一次、刷新后陈旧详情清栈、`autoOpenFirstDetail` 只执行一次（断言口径为 summary 集合）。
- 新增源文件已由 `xcodegen generate --spec ios/project.yml --project ios` 重生成工程（`.xcodeproj` 不入库）。

## 验收

- ac-read-failure-distinct-from-empty: 读取归档抛错与「读取成功但 0 条」是可判等区分的两个状态——空归档映射为有记录集合（空数组），抛错映射为失败状态，二者不相等；`HistoryView` 内不得再用 `try?` 吞掉 `list()` 的错误。
- ac-failure-retry-recovers: 从失败状态触发重试会再次调用归档 loader：成功且有记录 → 有记录集合（`history.row` 可渲染）；成功且 0 条 → 空集合（渲染空态）；再次抛错 → 回到失败状态且重试入口仍在。重试可重复执行，全部转移无需重启 App。
- ac-failure-surface-not-empty: 失败状态下不渲染 `history.empty` / `history.runAgain` 元素，只呈现一个可重试操作：文案取自既有 L10n 键 `run.action.retryLocation`，带 `accessibilityLabel`、高度 ≥ `minTapTarget`；失败说明句若无语义相符的既有键可用则不渲染并记 `pending: 待人现场`，视图内零字符串字面量、零新增文案键。
- ac-empty-cta-to-run-and-clear-path: 空态 CTA `history.runAgain` 触发后导航路径为空且向外请求切到 Run Tab；不调用任何 `RunSessionViewModel` 命令（运行中 / 暂停中的会话状态与计时不被复位）。
- ac-single-path-source: History 详情只由一份路径状态驱动（列表行以记录 id 入栈，详情由该路径的 destination 构造），不存在与 `NavigationLink` 并行的第二套 `isPresented` 详情态；`RunDetailView(record:` 仍在 `HistoryView.swift` 内、`runDetail.root` 与 `history.row` 仍可按 identifier 定位。
- ac-list-summary-only: 生产路径列表只调 `archiveStore.listSummaries()`，`HistoryView.swift` 内不得出现 `archiveStore.list()`（脚本反向判红）；行字段全部来自 `RunRecordSummary`；详情页按 id 用 `archiveStore.record(withID:)` 解码完整 `samples`，超大/畸形 samples 仍成行且列表不随 samples 线性变慢；排序（`startedAt` 降序 + id 升序）与坏文件跳过语义与 `list()` 一致。
- ac-back-returns-to-list-root: 路径从 1 个元素 pop 后回到 0（列表根），列表数据集合与顺序与入栈前逐项相等（同一 `refreshToken` 不触发重新读取）。
- ac-no-reload-on-back: 同一 `refreshToken` 下，「首次出现 → 下钻 → 返回」全过程归档 loader 只被调用 1 次；`refreshToken` 变化时再调用 1 次。
- ac-stale-detail-reconciled: `refreshToken` 变化后若路径指向的记录已不在新读取结果中，路径被清空回列表根；记录仍存在时路径保留。
- ac-drilldown-and-export-unchanged: 下钻目标仍是 `RunDetailView(record:)`，导出流程、`RunExportState`、`runDetail.export` / `runDetail.exported` / `runDetail.share` / `runDetail.exportFailed` 行为与标识零改动；既有 `RunFlowUITests` 的下钻与导出步骤一行未改。
- ac-identifier-and-copy-frozen: 既有 33 项 accessibility identifier 零删除、零改名（新增 identifier 走「只增不改」，当前总计 42：冻结 33 + 地图/分段 9）；新增控件一律带非空 `L10n` 可读 label；`Localizable.xcstrings` 只允许新增键（本轮新增空态 / 分段明细键），不得改动既有键文案。
- ac-screenshot-gate-preserved: DEBUG 截图门控 `-screenshotOpenRunDetail`（`autoOpenFirstDetail`）行为保留——首次读取后直接进入首条记录详情且只执行一次（改为初始化路径实现）。
- ac-token-and-gate-compatible: 改动文件零字面色值、零 `.font(.` / 裸 `Font.system(`、零动效时长字面量、零 `spacing: N` / `.padding(N)` / `minHeight: N` 数字字面量，间距与尺寸只取 `DesignTokens.*` / `minTapTarget`；`check-ios-shell` 依赖的既有字面（`listSummaries()`、`RunDetailView(record:`、`record(withID: recordID)`、`"history.empty"`、`"history.row"`、`RunFormatting.paceText`）必须留在 `HistoryView.swift` 内，且出现 `archiveStore.list()` 即判红。
- ac-gates-green: 全部门禁退出 0（含 `lint-ios-shell`（`--self-test` ≥84 项）、`test-ios`（`--unit-only`）、`build-ios`、`test-ios-run-core`、`test`）；不放宽既有断言，不新增 gate id，不改 `.munk/code-gates.json` 与 `scripts/**`。
- ac-scope-bounded: 本域代码面限定 `ios/PurePace/History/**` + `ios/PurePaceTests/**` 断言 + 因新增源文件带来的工程重生成；`Run/**`、`Design/**`、`Resources/**` 的改动只能由对应域（`ios-track-render` / `ios-ui-design`）主张，本域不借道修改视觉令牌、文案键或状态机。
- ac-budget-receipt: `digest.md` 首节写开工时刻、预算时长与期望收口绝对时刻；超时落盘现状并写「超时停手」与未完成项，不静默延长。
- ac-evidence-receipt: `digest.md` 记改动文件清单与 `git diff --name-only`、identifier 集合与冻结面零 diff 证据、新增 L1 用例名与 `test-ios --unit-only` 摘要、门禁命令 + exit code 片段；截图 / 模拟器 UI / 真机项不作为本项验收（真机项 `pending: 待人现场`）。

## 非目标

- 不改导出流程、导出状态标识与 `RunExportState` / `RunGPXExporter` 行为；不改任何既有 identifier；不改文案键（缺失说明文案记 `pending: 待人现场`）。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`、不改 `scripts/**` 与 `.munk/code-gates.json`、不改归档存储格式与 `RunArchiveStore` 语义、不改 `Run/**` 状态机与定位 / 音频 / GPX。
- 不重做 History 列表 / 详情 / 空态排版层级（归 `ios-history-visual`），不加新 Tab、二级入口、页面或路由，不新增 DesignSystem 分片。
- 不接动画，不做手势与横滑返回等交互路径重写。
- 不加 UI/XCUITest 用例、不跑浏览器 / 模拟器观感 / 真机验收；不写 `tech.md`，不排 Design / Architect / PM 阶段。

## 实现约束

- **门禁硬约束**：`scripts/check-ios-shell.sh` 对 `HistoryView.swift` 有字面 grep 依赖（`archiveStore.listSummaries()`、`RunDetailView(record:`、`record(withID: recordID)`、`RunFormatting.paceText`、`"history.empty"`、`"history.row"`），并对 `archiveStore.list()` 反向判红；既有 33 项 identifier 逐项必须存在、新增项只增不改。`History/**` 整目录在零字面量受管面内。
- **纯状态接缝**：读取结果 → 视图状态、路径收敛抽成不依赖 SwiftUI 的纯值类型，落在 `History/` 内、零 UI 依赖零字面量；单测用可抛错假 loader 覆盖，不为凑断言引入无消费者的抽象。
- **导航单一真源**：`NavigationStack(path:)` + 行 `NavigationLink(value:)` + `navigationDestination(for:)`，不保留 `detailPresented` / `detailRecord` 双轨；`RunRecord` 不入 path，按 id 就地查找以避免复制值语义歧义。
- **读取触发点**：仅「首次出现 + `refreshToken` 变化」，用已读 token 守卫；不挂在会被 push / pop 再次触发的回调上。`force` 仅由失败态重试入口使用。
- **视图形态**：保留 `List` + `.plain` + `scrollContentBackground(.hidden)` + 既有行卡片 token（`surface` / `Radius.card` / `separator` / `minTapTarget` / `monospacedDigit()`），不改成 `ScrollView` 自绘。
- **XcodeGen**：新增源文件必须 `xcodegen generate --spec ios/project.yml --project ios` 重生成工程并一并提交，禁止手改 `project.pbxproj`。

## 最近交付证明

- workItemId: wi_intake_7b9d19bc1e3be0ee（2026-11-12，pass，列表轻量索引）
- 交付：`HistoryLoadOutcome.loaded([RunRecordSummary])`、`state.summaries`，`HistoryView` 生产路径改 `archiveStore.listSummaries()`，行内容来自新增 `HistoryRowContent(summary:)`（三数值格式与旧 `init(record:)` 同源）；详情 destination 按 id 调 `archiveStore.record(withID: recordID)` 懒解码完整 `samples`，注入路径从 `injectedRecords` 派生 summary 并直接给详情；`HistoryViewStateTests` 10 用例改为 summary 口径。
- 判定与断言：`check-ios-shell.sh` 29 项断言 0 失败（`listSummaries()` 正断言 + `archiveStore.list()` 反向判红 + `record(withID: recordID)` 存在）；`test-ios --unit-only` 全绿（含 `HistoryViewStateTests` / `RunDetailContentTests`）；`code_gates` 22 门全绿（attempt 001）。
- 边界：列表量化耗时（数据量 / 耗时）未采集，只有结构性单测（超大/畸形 samples 仍成行）；详情页新增地图节归 `ios-track-render`。路径闭环、失败态重试与 `autoOpenFirstDetail` 语义未改。
