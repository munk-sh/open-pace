# 历史路径闭环：下钻/返回、空态 CTA、读取失败态

## 范围

把 History 侧的「能不能走完、走完能不能回来」补成闭环，只做状态与导航接线，不做新的视觉重排：

1. **列表下钻 / 返回**：`history.row` → `runDetail.root` 的下钻路径收敛为**单一导航状态**（当前实现同时存在 `NavigationLink { RunDetailView }` 与 `navigationDestination(isPresented: detailPresented)` 两套详情态），返回一次即回到列表根，不出现需要返回两次的残栈。
2. **返回后列表状态保留**：读取归档不因「进详情 → 返回」而重跑（同一 `refreshToken` 下 loader 只调用一次），列表数据、顺序与滚动位置不被重建。
3. **空态 CTA 回到可用 Run 首屏**：`history.runAgain` 点击后清空 History 导航路径并切到 Run Tab（`tab.run`），不向 `RunSessionViewModel` 发送任何命令（记录中/暂停中的会话不被重置）。
4. **读取失败态**：`archiveStore.list()` 抛错时不再退化为「空态 + 空列表」（当前是 `try? ... ?? []`，失败与「真的没有跑次」不可区分），改为独立的失败态与可重复重试；重试成功后按有无记录分别进入列表或空态，并可继续下钻。
5. **刷新一致性**：`refreshToken` 变化后，若当前打开的记录已不在新列表中，路径自动收敛回列表根，不展示已被删除的记录。

## 验收

- ac-read-failure-distinct-from-empty: 读取归档抛错与「读取成功但 0 条」是可判等区分的两个状态——空归档映射为有记录集合（空数组），抛错映射为失败状态，二者不相等；`HistoryView` 内不得再用 `try?` 吞掉 `list()` 的错误。
- ac-failure-retry-recovers: 从失败状态触发重试会再次调用归档 loader：成功且有记录 → 有记录集合（`history.row` 可渲染）；成功且 0 条 → 空集合（渲染空态）；再次抛错 → 回到失败状态且重试入口仍在。重试可重复执行，全部转移无需重启 App。
- ac-failure-surface-not-empty: 失败状态下不渲染 `history.empty` / `history.runAgain` 元素，只呈现一个可重试操作：文案取自既有 L10n 键 `run.action.retryLocation`（值「重试」），带 `accessibilityLabel`、高度 ≥ `minTapTarget`；失败说明句若无语义相符的既有键可用，一律不渲染并以 `pending: 待人现场` 记入 digest，视图内零字符串字面量、零新增文案键。
- ac-empty-cta-to-run-and-clear-path: 空态 CTA `history.runAgain` 触发后导航路径为空且向外请求切到 Run Tab；不调用任何 `RunSessionViewModel` 命令（运行中/暂停中的会话状态与计时不被复位）。
- ac-single-path-source: History 详情只由一份路径状态驱动（列表行以记录 id 入栈，详情由该路径的 destination 构造），不存在与 `NavigationLink` 并行的第二套 `isPresented` 详情态；`RunDetailView(record:` 仍在 `HistoryView.swift` 内、`runDetail.root` 与 `history.row` 仍可按 identifier 定位。
- ac-back-returns-to-list-root: 路径从 1 个元素 pop 后回到 0（列表根），列表数据集合与顺序与入栈前逐项相等（同一 `refreshToken` 不触发重新读取）。
- ac-no-reload-on-back: 同一 `refreshToken` 下，「首次出现 → 下钻 → 返回」全过程归档 loader 只被调用 1 次；`refreshToken` 变化时再调用 1 次。
- ac-stale-detail-reconciled: `refreshToken` 变化后若路径指向的记录已不在新读取结果中，路径被清空回列表根；记录仍存在时路径保留。
- ac-drilldown-and-export-unchanged: 下钻目标仍是 `RunDetailView(record:)`，导出流程、`RunExportState`、`runDetail.export` / `runDetail.exported` / `runDetail.share` / `runDetail.exportFailed` 行为与标识零改动；既有 `RunFlowUITests` 的下钻与导出步骤一行未改。
- ac-identifier-and-copy-frozen: 33 项 accessibility identifier 集合等值不变（不新增、不改名、不删除，新控件只用 L10n 可读 label 承载）；`Localizable.xcstrings` 与 `Design/L10n.swift` 零 diff。
- ac-token-and-gate-compatible: 改动文件零字面色值、零 `.font(.` / 裸 `Font.system(`、零动效时长字面量、零 `spacing: N` / `.padding(N)` / `minHeight: N` 数字字面量，间距与尺寸只取 `DesignTokens.*` / `minTapTarget`；`check-ios-shell` 依赖的既有字面（`archiveStore.list()`、`RunDetailView(record:`、`"history.empty"`、`"history.row"`）仍在 `HistoryView.swift` 内，不触发该脚本任何既有断言。
- ac-gates-green: 22 门全部退出 0（含 `lint-ios-shell`（`--self-test` ≥84 项）、`test-ios`（`--unit-only`）、`build-ios`、`test-ios-run-core`、`test`）；不放宽既有断言，不新增 gate id，不改 `.munk/code-gates.json` 与 `scripts/**`。
- ac-scope-bounded: 代码 diff 仅 `ios/PurePace/History/**` + `ios/PurePaceTests/**` 新增断言 + 新增源文件带来的 `ios/PurePace.xcodeproj` 重生成；`ContentView.swift` 若需接线则 diff ≤5 行且不改 Tab 集合与初始 Tab；`Design/**`、`Run/**`、`Settings/**`、`Resources/**`、`project.yml`、`scripts/**`、`docs/**`、`android/**`、`shared/**` 零 diff。
- ac-budget-receipt: `digest.md` 首节写开工时刻、预算时长（建议 80 分钟：路径与状态机 ≤30 / 失败态与重试 ≤25 / 断言与回归 ≤15 / 证据 ≤10）与期望收口绝对时刻；超时落盘现状并写「超时停手」与未完成项，不静默延长、不靠长会话补绿。
- ac-evidence-receipt: `digest.md` 记 ①改动文件清单与 `git diff --name-only`；②identifier 集合断言、`Localizable.xcstrings` / `L10n.swift` / `scripts/**` 零 diff 的证据；③新增 L1 用例名与 `test-ios --unit-only` 执行摘要；④门禁命令 + exit code 片段。截图、模拟器 UI 与真机项不作为本项验收（真机项 `pending: 待人现场`）。

## 非目标

- 不改导出流程、导出状态标识与 `RunExportState` / `RunGPXExporter` 行为；不改任何既有 identifier。
- 不改文案键：不新增、不修改 `Localizable.xcstrings`；缺失的失败说明文案以 `pending: 待人现场` 登记，不裸写字面量、不复用语义不符的键。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`、不改 `scripts/**` 与 `.munk/code-gates.json`、不改归档存储格式与 `RunArchiveStore` 语义、不改 `Run/**` 状态机与定位/音频/GPX。
- 不重做 History 列表 / 详情 / 空态的排版层级（由 `ios-history-visual` 已交付），不加新 Tab、二级入口、页面或路由，不新增 DesignSystem 分片。
- 不接动画，不做手势与横滑返回等交互路径重写。
- 不加 UI/XCUITest 用例（本项以代码层断言钉住状态与路径），不跑浏览器、模拟器观感与真机验收；不写 `tech.md`，不排 Design / Architect / PM 阶段。

## 实现约束

- **门禁硬约束（先读 `scripts/check-ios-shell.sh`）**：该脚本对 `HistoryView.swift` 有字面 grep 依赖（`archiveStore.list()`、`RunDetailView(record:`、`"history.empty"`、`"history.row"`），并冻结 identifier 集合恰为 33 项（`sort -u` 后与清单逐项相等）。因此：`archiveStore.list()` 调用必须留在 `HistoryView.swift`（用 `do/catch` 包裹后把结果交给纯状态映射），新增控件只能用 L10n 可读 label 承载、不得新增 identifier。`History/**` 整目录在零字面量受管面内。
- **纯状态接缝（L1 可断言）**：把「读取结果 → 视图状态」与「路径收敛」抽成不依赖 SwiftUI 的纯值类型（建议落在 `History/` 新文件，零 UI 依赖零字面量），由 `ios/PurePaceTests` 用可抛错的假 loader 覆盖：读取成功/失败、重试成功/再次失败、同一 token 不重复读取、刷新后陈旧详情清栈。不要为凑断言引入无消费者的抽象。
- **导航单一真源**：`NavigationStack(path:)` + 行 `NavigationLink(value:)` + `navigationDestination(for:)`，移除 `detailPresented` / `detailRecord` 双轨；DEBUG 截图门控 `-screenshotOpenRunDetail`（`autoOpenFirstDetail`）行为必须保留（第 5 波证据链依赖），改成初始化路径即可。`RunRecord` 不入 path 时就地查找，避免复制值语义歧义。
- **返回不重建列表**：读取触发点收敛为「首次出现 + `refreshToken` 变化」，用已读 token 守卫；不要挂在会被 push/pop 再次触发的回调上。
- **视图形态**：保留 `List` + `.plain` + `scrollContentBackground(.hidden)` + 既有行卡片 token（`surface` / `Radius.card` / `separator` / `minTapTarget` / `monospacedDigit()`），不改成 `ScrollView` 自绘。
- **XcodeGen**：新增源文件必须 `xcodegen generate --spec ios/project.yml --project ios` 重生成工程并一并提交，禁止手改 `project.pbxproj`。
- **开工先写预算**：动手前把开工时刻、预算与期望收口绝对时刻写入 `.munk/changes/{workItemId}/digest.md` 首节；超时即停手回执。
