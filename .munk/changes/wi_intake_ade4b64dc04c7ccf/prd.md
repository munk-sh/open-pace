# 跑步页三态指标区垂直居中 + 空白可机器判红断言

## 范围

公司裁决 `owe_bd22c86ba9f83139` 第 3 条后半句（「上方指标区与权限提示随之收紧，消除约 200pt 空白」）在前项 `wi_intake_41e9dc65e08c5971`（main `6512fba` / commit `7195b54`）未达成：实测内容块底边 y=447.4pt、主操作顶边 y=699.0pt，单一空洞 251.6pt，空白只是从按钮下方挪到了内容与按钮之间。本条从 `6512fba` 拉 worktree，只修这一处。

**1）跑步页三态指标内容块垂直居中**
- `.ready`（未开始）、`.running`/`.paused`（运行中）、`didSave`（保存态）三态，指标内容块在「导航栏下沿 → 底部控制区上沿」区间内垂直居中，上下留白差 ≤40pt，内容区最大单一垂直空洞（含内容块底边到主操作顶边）≤160pt。
- 保留既有结构：`safeAreaInset(edge: .bottom)` 底部控制区、主操作高 ≥44pt（`DesignTokens.minTapTarget`）、与 TabBar 的既有间距不变。
- 仅使用既有 `DesignTokens.Spacing`；不改字号/颜色/层级/文案/identifier。

**2）新增第四条门断言 `ac-run-metrics-balanced`**
- UI 用例读取相邻可见内容块 frame（距离/用时/当前配速/平均配速/分段/提示/主操作），按纵向排序算内容区最大单一垂直空洞（含内容块底边到主操作顶边），断言 ≤160pt；三态都量；同时断言上下留白差 ≤40pt。
- 判定抽成纯函数 `RunLayoutBalancePolicy`，单测用本轮实测旧布局（内容 177.7–447.4pt、导航栏下沿 149.7pt、主操作顶边 699.0pt → 底部空洞 251.6pt）作反例证明能红，再给居中布局正例；单测与 UI 用例编译同一份实现，不得各写一套。

**3）证据重出**
- `docs/screenshots/` 5 图 + `docs/evidence/a11y/` 6 树，文件名不变、同名覆盖，来自真实模拟器构建 + 现有 UI 用例附件导出。
- 本条必须写 `.munk/changes/<workItemId>/digest.md`（前项缺失，本项补上），含：逐文件 `shasum -a 256`、生成命令、`ac-run-metrics-balanced` 与既有三条断言（`ac-visible-copy-zh-hans`、`ac-run-detail-date-zh-hans`、`ac-primary-action-bottom-anchored`）通过的日志关键行、三态实测空洞数值。

## 验收

- ac-run-metrics-balanced：三态（未开始/运行中/保存态）UI 用例采集可见内容块与主操作的真实 `frame`，喂给同一纯函数 `RunLayoutBalancePolicy`，判定（a）内容区最大单一垂直空洞（内容块之间及内容块底边 → 主操作顶边，区间上界为导航栏下沿、下界为主操作顶边）≤160pt；（b）上下留白差 |顶部空白 − 底部空白| ≤40pt。纯函数单测以旧布局（底部空洞 251.6pt、上下差 223.6pt）反例证明两条判据均能红，并给出居中正例通过；UI 用例复用同一实现，反例自测证明断言可反向失败。
- 回归：ac-visible-copy-zh-hans、ac-run-detail-date-zh-hans、ac-primary-action-bottom-anchored 三条既有断言保持绿，不得放宽阈值或删除反向用例。
- 证据：`docs/screenshots/` 5 图与 `docs/evidence/a11y/` 6 树同名覆盖更新，且 `.munk/changes/<workItemId>/digest.md` 存在并含 shasum、生成命令、四条断言通过日志关键行、三态实测空洞数值。

## 非目标（越界即停并回报）

- 不动本地化/日期/identifier/状态机/定位/音频/TTS/GPX/持久化/CI workflow。
- 不重设计视觉 token（不改 `DesignTokens` 数值、不新增 token），不改字号/颜色/层级/文案。
- 不改 5 图 6 树的文件名与目录；不加英文/双语；不碰 Android、`shared/`、`ios/Core`、`ios/RunCore`、`Harness/`。
- 不放松既有断言阈值，不删任何反向用例；不做真机验收（真机项仍 `pending: 待人现场`）。

## 实现约束

**预算与收口（开工先落）**：本条预算 ≤4M token、墙钟 ≤45 分钟。开工时刻 2026-11-11 02:41 CST，期望收口时刻 2026-11-11 03:26 CST；超时即停手并回执，不硬撑。

**布局锚点**
- `ios/PurePace/Run/RunView.swift` L11–L90：当前为 `ScrollView { VStack(spacing: .md) { … } .padding(.md) }` 顶部堆叠，即 251.6pt 空洞来源；需改为在导航栏下沿与 `.safeAreaInset` 控制区上沿之间垂直居中（例如内容容器 `maxHeight: .infinity` + 上下等量 `Spacer(minLength: DesignTokens.Spacing.md)`，或等价居中容器），保留 `safeAreaInset(edge: .bottom)` 与控制区内边距不动。
- 三态内容差异：`.ready` 有 `run.backgroundDegraded` 提示（实测底边 447.4pt），保存态多 `run.saved` 文本；居中容器必须让内容块整体（含提示/保存文案）一起居中，不能只居中前四块。小屏溢出风险由 `ScrollView` 保留兜底，不得截断内容。
- 取值只允许既有 `DesignTokens.Spacing`（`xxs/xs/sm/md` 等），`DesignTokens.swift` 零 diff。

**断言锚点**
- 新建 `ios/PurePace/Design/RunLayoutBalancePolicy.swift`（纯函数，无 SwiftUI 依赖），形态对齐既有 `PrimaryActionLayoutPolicy.swift`（`Evaluation` + `problems` + `passes`），阈值常量 `maximumGap = 160`、`maximumImbalance = 40` 与判定实现单点定义。
- `ios/project.yml` L96–L104 `PurePaceUITests.sources` 需追加该策略文件（与现有三个 Policy 并列，App target 走 `path: PurePace` 自动纳入）；`PurePace.xcodeproj` 仍由 XcodeGen 生成后入库，禁手改 `project.pbxproj`。
- 单测落 `ios/PurePaceTests/LocalizationPolicyTests.swift`（L60–L95 已有 `PrimaryActionLayoutPolicy` 用例，新用例同文件或同位）；反例数据必须取本轮实测：内容块 177.7–447.4、导航栏下沿 149.7、主操作顶边 699.0。
- UI 用例落 `ios/PurePaceUITests/RunFlowUITests.swift` 的 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction`（L485–L574，已覆盖三态与 5 图 6 树），新增 `assertRunMetricsBalanced(...)` 依次在未开始（L511 附近）、运行中（L529 附近）、保存态（L541 附近）调用；采集 identifier 清单固定为 `run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` / `run.backgroundDegraded`（存在时）/ `run.saved`（存在时）+ 当态主操作按钮；区间上界取 `app.navigationBars.firstMatch.frame.maxY`。

**证据与门禁**
- 现有 `scripts/verify-ios-ui-e2e.sh` 只覆盖 GPX 全链路并写 `docs/evidence/stage3-e2e/`，**不**产出 `docs/screenshots/` 与 `docs/evidence/a11y/`；本条证据须按等价流程显式导出：`xcodebuild test -only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction -resultBundlePath <dir>` → `xcrun xcresulttool export attachments --path <dir>.xcresult --output-path <attachments>`（附件名即 `run-not-started`/`run-running`/`history-detail`/`history-empty`/`settings` 与 `01-run-not-started`…`06-tabs`）→ 同名覆盖复制到 `docs/screenshots/`、`docs/evidence/a11y/`。生成命令与关键日志行必须原样进 digest。
- `digest.md` 写 `.munk/changes/wi_intake_ade4b64dc04c7ccf/digest.md`；三态实测空洞数值从新导出的可及树/用例日志取真实值，不得沿用本轮旧值冒充。
- `code_gates` 若 attempt ≥2，digest 逐条写清上一 attempt 的失败项或作废原因（树变化 or 环境），不得只写「重跑后绿」。
- 交付回执只要三样：① 5 图 + 6 树路径与 sha256；② `ac-run-metrics-balanced`（含反例判红证据）与既有三条断言的门名/用例名与通过日志；③ diff 范围（只含布局改动 + 该断言 + 证据）。
