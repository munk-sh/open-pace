# Domain: ios-history-flow

History 侧的**状态与导航闭环**子域：下钻 / 返回、空态 CTA 回到可用 Run 首屏、归档读取失败态与重试、`refreshToken` 刷新一致性。只做状态机与导航接线，不做视觉重排（层级与令牌归 `ios-history-visual` / `ios-ui-design`），不改导出流程、identifier、文案键与归档语义。

## 范围

- `ios/PurePace/History/HistoryViewState.swift`：不依赖 SwiftUI 的纯值状态类型——`HistoryLoadOutcome`（`loaded([RunRecord])` / `failed`，Equatable）、`path: [UUID]` 单一导航路径、`loadedToken` 读取守卫、`shouldLoad(token:force:)` / `load(token:force:using:)` / `open(recordID:)` / `popToRoot()` / `openFirstDetailIfNeeded(autoOpen:)` / `reconcilePath()`。
- `ios/PurePace/History/HistoryView.swift`：`NavigationStack(path:)` + 行 `NavigationLink(value: record.id)` + `navigationDestination(for: UUID.self)` 单一详情真源（详情按 id 在 `state.records` 就地查找）；`archiveStore.list()` 仍在文件内但用 `try` 交给 `state.load`；失败态视图只渲染 `L10n.runActionRetryLocation` 重试按钮；空态 CTA 先 `popToRoot()` 再 `onRunAgain()`。
- `ios/PurePaceTests/HistoryViewStateTests.swift`：以可抛错假 loader 钉住读取成功 / 失败、重试恢复、同 token 只读一次、刷新后陈旧详情清栈、`autoOpenFirstDetail` 只执行一次。
- 新增源文件已由 `xcodegen generate --spec ios/project.yml --project ios` 重生成工程（`.xcodeproj` 不入库）。

## 验收

- ac-read-failure-distinct-from-empty: 读取归档抛错与「读取成功但 0 条」是可判等区分的两个状态——空归档映射为有记录集合（空数组），抛错映射为失败状态，二者不相等；`HistoryView` 内不得再用 `try?` 吞掉 `list()` 的错误。
- ac-failure-retry-recovers: 从失败状态触发重试会再次调用归档 loader：成功且有记录 → 有记录集合（`history.row` 可渲染）；成功且 0 条 → 空集合（渲染空态）；再次抛错 → 回到失败状态且重试入口仍在。重试可重复执行，全部转移无需重启 App。
- ac-failure-surface-not-empty: 失败状态下不渲染 `history.empty` / `history.runAgain` 元素，只呈现一个可重试操作：文案取自既有 L10n 键 `run.action.retryLocation`，带 `accessibilityLabel`、高度 ≥ `minTapTarget`；失败说明句若无语义相符的既有键可用则不渲染并记 `pending: 待人现场`，视图内零字符串字面量、零新增文案键。
- ac-empty-cta-to-run-and-clear-path: 空态 CTA `history.runAgain` 触发后导航路径为空且向外请求切到 Run Tab；不调用任何 `RunSessionViewModel` 命令（运行中 / 暂停中的会话状态与计时不被复位）。
- ac-single-path-source: History 详情只由一份路径状态驱动（列表行以记录 id 入栈，详情由该路径的 destination 构造），不存在与 `NavigationLink` 并行的第二套 `isPresented` 详情态；`RunDetailView(record:` 仍在 `HistoryView.swift` 内、`runDetail.root` 与 `history.row` 仍可按 identifier 定位。
- ac-back-returns-to-list-root: 路径从 1 个元素 pop 后回到 0（列表根），列表数据集合与顺序与入栈前逐项相等（同一 `refreshToken` 不触发重新读取）。
- ac-no-reload-on-back: 同一 `refreshToken` 下，「首次出现 → 下钻 → 返回」全过程归档 loader 只被调用 1 次；`refreshToken` 变化时再调用 1 次。
- ac-stale-detail-reconciled: `refreshToken` 变化后若路径指向的记录已不在新读取结果中，路径被清空回列表根；记录仍存在时路径保留。
- ac-drilldown-and-export-unchanged: 下钻目标仍是 `RunDetailView(record:)`，导出流程、`RunExportState`、`runDetail.export` / `runDetail.exported` / `runDetail.share` / `runDetail.exportFailed` 行为与标识零改动；既有 `RunFlowUITests` 的下钻与导出步骤一行未改。
- ac-identifier-and-copy-frozen: 33 项 accessibility identifier 集合等值不变（不新增、不改名、不删除，新控件只用 L10n 可读 label 承载）；`Localizable.xcstrings` 与 `Design/L10n.swift` 零 diff。
- ac-screenshot-gate-preserved: DEBUG 截图门控 `-screenshotOpenRunDetail`（`autoOpenFirstDetail`）行为保留——首次读取后直接进入首条记录详情且只执行一次（改为初始化路径实现）。
- ac-token-and-gate-compatible: 改动文件零字面色值、零 `.font(.` / 裸 `Font.system(`、零动效时长字面量、零 `spacing: N` / `.padding(N)` / `minHeight: N` 数字字面量，间距与尺寸只取 `DesignTokens.*` / `minTapTarget`；`check-ios-shell` 依赖的既有字面（`archiveStore.list()`、`RunDetailView(record:`、`"history.empty"`、`"history.row"`）仍在 `HistoryView.swift` 内，不触发该脚本任何既有断言。
- ac-gates-green: 全部门禁退出 0（含 `lint-ios-shell`（`--self-test` ≥84 项）、`test-ios`（`--unit-only`）、`build-ios`、`test-ios-run-core`、`test`）；不放宽既有断言，不新增 gate id，不改 `.munk/code-gates.json` 与 `scripts/**`。
- ac-scope-bounded: 代码 diff 仅 `ios/PurePace/History/**` + `ios/PurePaceTests/**` 新增断言 + 新增源文件带来的 `ios/PurePace.xcodeproj` 重生成；`ContentView.swift` 若需接线则 diff ≤5 行且不改 Tab 集合与初始 Tab；`Design/**`、`Run/**`、`Settings/**`、`Resources/**`、`project.yml`、`scripts/**`、`docs/**`、`android/**`、`shared/**` 零 diff。
- ac-budget-receipt: `digest.md` 首节写开工时刻、预算时长与期望收口绝对时刻；超时落盘现状并写「超时停手」与未完成项，不静默延长。
- ac-evidence-receipt: `digest.md` 记改动文件清单与 `git diff --name-only`、identifier 集合与冻结面零 diff 证据、新增 L1 用例名与 `test-ios --unit-only` 摘要、门禁命令 + exit code 片段；截图 / 模拟器 UI / 真机项不作为本项验收（真机项 `pending: 待人现场`）。

## 非目标

- 不改导出流程、导出状态标识与 `RunExportState` / `RunGPXExporter` 行为；不改任何既有 identifier；不改文案键（缺失说明文案记 `pending: 待人现场`）。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`、不改 `scripts/**` 与 `.munk/code-gates.json`、不改归档存储格式与 `RunArchiveStore` 语义、不改 `Run/**` 状态机与定位 / 音频 / GPX。
- 不重做 History 列表 / 详情 / 空态排版层级（归 `ios-history-visual`），不加新 Tab、二级入口、页面或路由，不新增 DesignSystem 分片。
- 不接动画，不做手势与横滑返回等交互路径重写。
- 不加 UI/XCUITest 用例、不跑浏览器 / 模拟器观感 / 真机验收；不写 `tech.md`，不排 Design / Architect / PM 阶段。

## 实现约束

- **门禁硬约束**：`scripts/check-ios-shell.sh` 对 `HistoryView.swift` 有字面 grep 依赖（`archiveStore.list()`、`RunDetailView(record:`、`"history.empty"`、`"history.row"`），并冻结 identifier 集合恰为 33 项。`archiveStore.list()` 必须留在 `HistoryView.swift`（`do/catch` 或 `try` 包裹后交给纯状态映射），新增控件只用 L10n 可读 label 承载、不得新增 identifier。`History/**` 整目录在零字面量受管面内。
- **纯状态接缝**：读取结果 → 视图状态、路径收敛抽成不依赖 SwiftUI 的纯值类型，落在 `History/` 内、零 UI 依赖零字面量；单测用可抛错假 loader 覆盖，不为凑断言引入无消费者的抽象。
- **导航单一真源**：`NavigationStack(path:)` + 行 `NavigationLink(value:)` + `navigationDestination(for:)`，不保留 `detailPresented` / `detailRecord` 双轨；`RunRecord` 不入 path，按 id 就地查找以避免复制值语义歧义。
- **读取触发点**：仅「首次出现 + `refreshToken` 变化」，用已读 token 守卫；不挂在会被 push / pop 再次触发的回调上。`force` 仅由失败态重试入口使用。
- **视图形态**：保留 `List` + `.plain` + `scrollContentBackground(.hidden)` + 既有行卡片 token（`surface` / `Radius.card` / `separator` / `minTapTarget` / `monospacedDigit()`），不改成 `ScrollView` 自绘。
- **XcodeGen**：新增源文件必须 `xcodegen generate --spec ios/project.yml --project ios` 重生成工程并一并提交，禁止手改 `project.pbxproj`。

## 最近交付证明

- workItemId: wi_ws_5068ceb7bfaa2e84（2026-11-11，pass）
- 交付：History 路径闭环。新增 `HistoryViewState`（86 行纯值状态：`loaded` / `failed` 可判等、`path: [UUID]` 单一真源、`loadedToken` 守卫、`reconcilePath` 清陈旧详情）；`HistoryView` 改 `NavigationStack(path:)` + `navigationDestination(for: UUID.self)`，删除 `detailPresented` / `detailRecord` 双轨；`try?` 吞错改为独立失败态（唯一 `run.action.retryLocation` 重试按钮 + `minTapTarget`），空态 CTA 先 `popToRoot()` 再 `onRunAgain()`，截图门控改初始化路径且只执行一次。
- 判定与断言：22 门全绿（`lint-ios-shell` 30 项 + `--self-test` 84 项、`test-ios --unit-only` 208 例、`build-ios`、`test-ios-core`、`test` 均 exit=0）；新增 `HistoryViewStateTests` 9 条用例（空/失败可区分、重试恢复三向、重复失败可重试、同 token 只读一次、刷新清栈与保留、失败清栈、CTA 清路径保留数据、autoOpen 只一次）。
- 证据与边界：`git diff --name-only` 仅 `History/HistoryView.swift`；新增 `History/HistoryViewState.swift` / `PurePaceTests/HistoryViewStateTests.swift`；identifier 33 项等值不变，`Design/**` / `Resources/**` / `Run/**` / `Settings/**` / `project.yml` / `scripts/**` 零 diff。失败说明句无语义相符既有键，按约束不渲染，记 `pending: 待人现场`；截图 / 模拟器观感 / 手势返回 / 真机项同样 `pending: 待人现场`。回执见 `.munk/changes/wi_ws_5068ceb7bfaa2e84/digest.md`。
