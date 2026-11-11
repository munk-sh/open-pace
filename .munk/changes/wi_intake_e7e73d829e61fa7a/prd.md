# 视图层用途重映射（accent / warning / danger）+ 未开始态间距收敛

## Scope

公司裁决 `owe_1af0fad2441dc226` 的视图层用途重映射在 A 层只落了 registry 文案与 docs，实际渲染仍是旧语义；本项把「语义重映射」与「未开始态间距收敛」合成一次改动（同批 `RunView` / `RunInteractionPlan` 文件，分两轮会互相返工）：

1. **记录态主操作族统一 `accent`**：开始 / 暂停 / 继续 / 结束 / 保存一律取品牌主色；`finish` 从 secondary+warning 提升为主操作 `accent` 族，不再用 warning 描边。
2. **丢弃 = `danger` 且只在确认层**：结束待保存屏不得直调 `discardFinished()`，改为先出确认 sheet；破坏性确认按钮只在 sheet 内（danger 文本或描边，不填充），不得与 accent 主操作同屏同形状并列。
3. **`warning` 只作非阻断内联提示**：权限缺失 / GPS 弱 / 保存失败横幅；不得作暂停 tint、不得作填充主按钮、不得作为结束按钮样式。
4. **既有断言按新语义改写**：`RunInteractionPlanTests` 中 finish=secondary 的旧断言改为主操作 accent 族表达，禁止靠删除断言规避。
5. **注释与 registry 口径对齐**：`DesignTokens.swift` 的 warning 注释与本文件 `purposes` 注册表一致。
6. **未开始态间距收敛**：只重排既有空白让既有几何断言实跑转绿（`RunLayoutBalancePolicy` 阈值 80/80/16 与反例零改动，禁止新增占位内容视图）。
7. **补齐证据**：两条 UI 样式断言、`tab=0` 三态 + restore 实跑、digest 起点/修后实测对照并绑 commit、`docs/verification-matrix.md` 补 5 行。

## Acceptance Criteria

### 语义重映射

- ac-primary-family-accent: 记录态主操作族 `start` / `pause` / `resume` / `finish` / `save` 解析出的 tint 均为 `accent` token（单一映射真源可被 L1 断言）；任一动作解析为 `warning` / `secondary` / `primary` 中性色即判红。
- ac-finish-accent: `running` 与 `paused` 两态的 `finish` 不再属于 `secondary`，其样式归入主操作 accent 族；L1 断言 `finish` 的 accent 解析结果，且旧口径（warning / secondary）反例必须判红。
- ac-finish-ui-rendered-accent: UI 实跑断言结束按钮的实际渲染底色为 `accent`（读取 `DesignTokens.Colors.palette["accent"]` light 值，采样按钮内非文字区域像素，容差 ≤ 2/255）；同一用例对「已保存」态保存主操作与记录态暂停按钮做同口径断言。该断言对旧实现（finish 为 warning 描边、无 accent 填充）必须判红。
- ac-discard-confirm-only: `finished && !didSave` 屏内不存在破坏性 `run.discard` 按钮，只存在打开确认层的入口（`run.discardRequest`）；破坏性确认按钮 `run.discard` 仅存在于确认 sheet 内；sheet 取消后回到结束待保存态、距离与会话状态不变且未触发丢弃；确认后才执行丢弃并回到 `ready`。UI 断言「sheet 出现前 `run.discard` 不存在、sheet 出现后才存在」必须对旧实现（直调丢弃、无 sheet）判红。
- ac-discard-danger-shape: 确认层内丢弃控件解析为 `danger` 且无 accent 填充底；确认层内不出现 accent 填充主按钮，丢弃不与 accent 同屏同形状并列。
- ac-warning-inline-only: `warning` 只解析给非阻断内联提示（权限缺失 / GPS 弱 / 保存失败横幅）与其弱底；`running` / `paused` 的 hero 数值色与主操作 tint 均不得为 `warning`，暂停不把 tint 切到 warning；不存在 warning 填充主按钮（L1 反例判红）。
- ac-plan-tests-rewritten: `RunInteractionPlanTests` 中原 `finish == .secondary` 断言改写为「finish 属于主操作 accent 族、同屏唯一填充主操作仍是 pause/resume」；断言数量不得因改写而减少，反例（finish 回退 secondary/warning）必须判红。
- ac-token-comment-aligned: `DesignTokens.swift` warning 的文档注释与 `purposes["warning"]` 口径一致（非阻断内联提示 / 不作暂停 tint / 不作填充主按钮），无相反描述残留。

### 未开始态间距收敛

- ac-layout-ready-green: `未开始` 态既有几何断言在 iPhone 16 竖屏实跑通过：`top ≤ 80`、`bottom ≤ 80`、`largest ≤ 80`、`imbalance ≤ 16`（`RunLayoutBalancePolicy` 阈值与反例源码零改动）；实现只重排既有空白（调整既有 Spacer 的分布/权重），不得新增占位内容视图或硬编码伪造帧。
- ac-layout-evidence-bound: digest 并排记录「本项起点 HEAD `f907faf` 实测（预期 ≈ 88.58，若不同以实跑为准）」与「修后实测」，两列均原样落 `top` / `bottom` / `largest` / `contentFrames` 明细，并绑定本项提交 commit（hash 与实测同轮产出）。

### 实跑证据与文档

- ac-tabbar-live-branches: UI 腿实跑到 `running`、`paused`、`finished && !didSave` 与保存/丢弃后的 restore 路径，四行 `ac-tabbar-hidden-recording` / `-paused` / `-finished-pending` / `-restore-no-deadend` 结果原样打印进 digest；L1 单测不得顶替 UI 实跑。
- ac-l10n-zh-hans: 新增确认层标题 / 说明 / 确认 / 取消文案全部走 `Localizable.xcstrings`（sourceLanguage=zh-Hans，单语）与 `L10n` 键入口，无裸英文字面量；本地化策略测试绿。
- ac-palette-frozen: 36 hex 与既有对比度阈值零改动（`DesignTokensTests` 全绿），不新增颜色键。
- ac-matrix-rows: `docs/verification-matrix.md` 新增 5 行——palette hex 锁定 / accent↔warning 与 accent↔danger 分离 / 深色中性 chroma / finish=accent / discard 仅在确认层；每行带断言名、证据路径与归属项（本项标识）。
- ac-no-scope-creep: 不改 `TrackGeometry`、`RunArchiveStore`、地图、结束态总结（B 项）、截图与可及树（C 项）、`.github/workflows/**`、`project.yml` 签名配置；不新增门禁或脚本，不删除/放宽既有断言与阈值。

## Non-Goals

- 不重出截图与可及树（C 项），不更新 `docs/screenshots/SHA256SUMS`。
- 不做地图、结束态总结与 B 项任何范围。
- 不改 36 hex、对比度阈值、`RunLayoutBalancePolicy` 的 80/80/16 与四条反例。
- 不动 `TrackGeometry` / `RunArchiveStore` / 存档契约 / `RunSessionOrchestrator` 状态机。
- 不新增门禁、脚本、workflow 步骤；不改 `project.yml` 签名配置（仅允许为共享纯判定/样式映射补 sources 条目）。
- 不做 Android 侧改动。

## Implementation Constraints

- 语义与样式映射的单一真源放在 `RunInteractionPlan` / 共享纯判定层（可供 L1 断言），`RunView` 只按映射渲染；不得在 View 里各自 `switch` 颜色。
- `RunInteractionPlan.swift`：`items` 的 emphasis 语义按新口径调整（finish 不再 secondary，discard 仅在确认层语义下出现）；保持「每展示态唯一填充主操作」不变量。
- `RunView.swift`：`control(for:)` 中 `discard` 改为打开确认 sheet 的入口；破坏性按钮与确认 sheet 只用 `danger`/`dangerSoft` token；`stateTint` 暂停不再取 warning；`secondaryControl` 的 warning 描边语义移除或改为仅用于内联提示；`balancedMetrics` 只调整既有 Spacer 分布。
- `RunSessionViewModel.swift`：`discardFinished()` 仍作为状态变更实现保留（可保持 guard），是否可调用由视图确认层保证；不要删除其状态复位逻辑。
- `RunInteractionPlanTests.swift`：改写 `testDestructiveActionsStaySecondary` 中 finish=secondary 的断言表达，保留对 discard/save 的覆盖并新增确认层语义断言。
- `DesignTokens.swift`：仅改注释（`warning` 相关注释与 `purposes` 对齐），色值数组一字不动。
- 新增 UI 断言优先复用既有 `RunFlowUITests` 入口（`testRunPauseResumeFinishAndHistory`、`testZhHansCopyDatesAndBottomAnchoredPrimaryAction`），不要重立新套件；像素采样需从 token 派生期望值，避免在测试里另写颜色字面量。
- 若新增共享纯判定/样式映射文件，可在 `ios/project.yml` 的 UITests/Tests sources 增补条目；签名配置与 deployment target 不动。
- `finished && !didSave` 的既有 UI 期望（`app.buttons["run.discard"].exists`）按新语义改写为「入口存在、破坏性按钮不在屏」，属于语义升级而非删断言规避。
- 预算：≤8M token / ≤90 分钟墙钟；到点立即交未闭合回执（已改文件 / 已过门 / 未跑门 / 未闭合点），禁止为凑绿调阈值或删断言。
- 证据落盘：`.munk/changes/wi_intake_e7e73d829e61fa7a/digest.md` 记录逐门原文、实测行、起点/修后对照与 commit hash。
