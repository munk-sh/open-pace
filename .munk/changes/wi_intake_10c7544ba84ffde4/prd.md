# 修红 ios.yml 权威腿：运行 / 暂停态指标区垂直居中（只修布局）

## Scope

只修 `ios/PurePace/Run/RunView.swift` 非结束态（未开始 / 运行中 / 暂停）首屏内容在「导航栏下沿 → 主操作顶边」之间的垂直分布，使 `RunLayoutBalancePolicy` 的 `top / bottom / largest / imbalance` 四判据在运行中与暂停态重新判绿；同一容器复用的未开始态不得回归。结束态（B1 待保存 / 已保存）版面与预算保持不变。

改前红事实（CI run `43234566773`，head `a677e17`，iOS 18.6 / iPhone 16，step `test`）：

- `ios/PurePaceUITests/RunFlowUITests.swift:890`：
  `运行中 指标区未垂直居中（顶部留白 73.41666666666669pt，底部留白 81.33333333333337pt，最大空洞 81.5pt）：["底部留白 81.33333333333337pt > 80.0pt", "最大单一垂直空洞 81.5pt > 80.0pt"]`
- 同套件 `testRunPauseResumeFinishAndHistory` 的「暂停」态同断言同样失败；同 run「未开始」（top 66.5 / bottom 74.33 / largest 74.67）与「保存态（无分段）」通过。

本次承接上一项因 Host 换代/静默中断留下的已归档改动（`artifacts/wi_intake_caf0abdb2486d501/centering-fix-unclosed/centering-fix.patch`，sha256 `911fa8e1d384aa08b161e586871c498114ad9f6b8492f6b068d26dd461c5e186`，在 `78313bb` 上 `git apply --check` 已通过），核 sha256 → apply → 单一实现 commit → 实测验证。

## Acceptance Criteria

- ac-red-before-recorded: 回执原样记录改前红：run `43234566773` + head `a677e17` + `RunFlowUITests.swift:890` 断言原文 + `top=73.41666666666669 / bottom=81.33333333333337 / largest=81.5` 与两条 problems；不得用「改后重跑绿」替代，也不得为制造红而回退生产代码。
- ac-patch-applied: 明确记录 apply 的 patch sha256（须等于 `911fa8e1d384aa08b161e586871c498114ad9f6b8492f6b068d26dd461c5e186`）与落地的唯一实现 commit sha；若实读 patch 与描述有差异，以实读为准并在回执写清差异（已知：补白 token 为 `Spacing.xs = 8`，不是描述里的 4pt，推导见「实现约束」）。
- ac-running-centered: 本地真实 UI 腿运行态 `assertRunMetricsBalanced` 通过；日志 `ac-run-metrics-balanced 运行中` 的 `top / bottom / largest` 均 ≤80（不得出现 80.x 贴边值）且 `imbalance ≤ 16`；`contentFrames` 仍含 `run.backgroundDegraded` inline 胶囊帧（胶囊未被排除或去重掉）。四元组实测小数写入回执。
- ac-paused-centered: 暂停态同一断言通过，`top / bottom / largest / imbalance` 满足 ≤80 / ≤80 / ≤80 / ≤16，实测值写入回执。
- ac-idle-no-regression: 未开始态（复用同一 `balancedMetrics` 容器）改后仍通过同一断言：`top / bottom / largest ≤ 80`、`imbalance ≤ 16`；改后实测值与改前（66.5 / 74.33 / 74.67）一并写回执；不得用 skip / allowlist / 删断言换取绿。
- ac-finished-budget-unchanged: 结束待保存态与保存态的既有断言全部保持绿：`assertRunMetricsBalanced`（保存态）、`assertFinishedContentBudget`（内容 ≤691、地图 hero 360、操作条 68）、inline 胶囊高度 ≤32（实测 248×23.67）、确认层推导 top≈682.33 / height≈169.67 / confirm 44pt；`RunFinishedSummaryLayoutPolicy` 的 691/360/68/32 数值与行为不变。
- ac-thresholds-and-sampling-frozen: `RunLayoutBalancePolicy` 的 `maximumTopGap/maximumBottomGap/maximumGap = 80`、`maximumImbalance = 16` 与 `evaluate` 实现逐字不变；`assertRunMetricsBalanced` 采样口径不变（staticTexts + `run.mapPreview` + inline 胶囊，排除 `run.telemetry`）；不新增 allowlist、不删改任何断言、不加 `continue-on-error`。
- ac-counterexample-shift-red: `LocalizationPolicyTests.testFourStatesShiftedUpBy24Fails` 通过：四态判绿代表帧整体上移 24pt 后 `evaluate().passes == false` 且 problems 至少覆盖「底部留白 / 最大单一垂直空洞 / 上下留白差」之一；反例只喂合成帧，不依赖改生产代码才红。既有反例（legacy 顶对齐、截图旧布局、缺地图卡、非对称留白）全部保留并继续判红。
- ac-existing-unit-cases-preserved: `bash scripts/test-ios.sh --unit-only` 全绿（PurePaceTests ≥265、RunCore 173，失败 0）；既有用例一条不删，新增反例导致的计数变化在回执写明实际条数与新增条数。
- ac-tokens-only: 布局改动只使用 `DesignTokens.Spacing` / 既有字号档位；不新增字面量 magic number、不改字号档位 / 圆角 / 色值；不引入 80 阈值替代物。
- ac-local-two-cases: 本地跑通 `RunFlowUITests/testRunPauseResumeFinishAndHistory` 与 `RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 两条用例（0 失败），日志含未开始 / 运行中 / 暂停 / 保存态 `ac-run-metrics-balanced` 四元组实测值。
- ac-shell-100-33: `bash scripts/check-ios-shell.sh --self-test` 汇总 100 项 0 失败；`bash scripts/check-ios-shell.sh` 汇总 33 项 0 失败；identifier 冻结 33 项、去重计数 42 不变（不新增 / 改名 / 删除任何 accessibilityIdentifier）。
- ac-gates-22: `.munk/code-gates.json` 的 22 门全部绿；不新增、不删除、不放宽门禁；本地不跑 `ios.yml` 代替权威腿。
- ac-single-commit: 一个缺陷一个 commit；commit 只含布局修复 + 对应单测，不夹带其他改动；回执含「改前红 → 改后同断言绿」对照表。
- ac-authoritative-ios-yml: 交付后针对本项实现 commit 取到 `.github/workflows/ios.yml` 的 run，`status=completed` 且 `conclusion=success`，并覆盖 `ios/PurePaceUITests/*UITests.swift` 全部套件（含 `ScreenshotEvidenceUITests`）；一次取不到就挂一次性 alarm 或常驻等待任务再取，禁止会话内 watch/sleep 轮询。回执含 run id + head sha + conclusion。
- ac-scope-frozen: 不改 token 色值 / 字号档 / 圆角，不改 identifier 集合（33 冻结 / 42 去重），不改 `VERSION` / 候选 `0.1.0(1)`，不改 `shared/` 与 Android，不重做视觉，不新增门禁机制，不做真机与分发，不碰 `docs/screenshots` 与 `docs/evidence`。
- ac-no-ui-verified-claim: 回执禁止写「已验证 UI」；人肉眼复评仍列为待办。

## Non-Goals

- 不改 80/80/80/16 阈值，不改 `evaluate` 采样口径，不加白名单、不 skip、不删断言、不加 `continue-on-error`。
- 重做视觉、重排 B1 结束态、动地图 hero 360 / 内容 ≤691 / 操作条 68 / 胶囊 32 预算。
- 新增页面、组件、颜色键、字号档或新 identifier。
- 改 `VERSION` / 构建号、改 CI 预算或分段策略、删除 / 放宽任何测试腿。
- 改共享夹具、Android、状态机、持久化、播报、GPX 逻辑。
- 重出 `docs/screenshots` / `docs/evidence` 截图（后续项负责）。

## Implementation Constraints

- 归档材料（相对产品目录）：`artifacts/wi_intake_caf0abdb2486d501/centering-fix-unclosed/`（`centering-fix.patch`、`diffstat.txt`、`change-pack/prd.md`、`SHA256SUMS`）。先 `shasum -a 256` 校验 `911fa8e1…c5e186`，再 `git apply`；`git apply --check` 已在 `78313bb` 通过（Owner 实测）。
- patch 实读内容：
  - `ios/PurePace/Run/RunView.swift` `balancedMetrics` 容器补 `.padding(.top, DesignTokens.Spacing.xs)`（一处 +6 行含注释）。
  - `ios/PurePaceTests/LocalizationPolicyTests.swift` 新增 `testFourStatesShiftedUpBy24Fails`（合成帧整体上移 24pt 必红）。
- 与描述的已知差异：`DesignTokens.Spacing.xs = 8`（`xxs 4 / xs 8 / sm 12 / md 16 / lg 24 / xl 32`），不是描述里的 4pt。patch 自身推导为：非结束态固定内边距本不等（顶部 hero 上呼吸 12；指标卡下 `cardPadding 16 + metricCardBottomPadding 4 = 20`；底部提示层尾隙 + 操作条内边距实测合计 20），顶部补一档 `xs` 补齐到 20 等权后，四层 Spacer 才能把 top / bottom / largest 同时压进 80。以实读 patch 为准，回执写清该差异。
- 落地顺序：校验 sha → `git apply` → 单一 commit（仅上述两个文件）。若 apply 后实测有任一态 >80，只允许在既有 `DesignTokens.Spacing` token 内微调该补白（xxs / xs / sm），并保持 patch 注释与推导同步更新；不得改阈值、采样口径、断言或新增字面量，最终 delta 与四元组写回执。
- 现场锚点：`ios/PurePace/Run/RunView.swift` `balancedMetrics`（`Spacer(screenTop)` → hero → `Spacer(cardGap)` → 指标卡 → `Spacer(sectionGap)` → hintLayer → `Spacer(sectionGap)`）；`metricsPanel` 的 `.padding(.bottom, RunFinishedSummaryLayoutPolicy.metricCardBottomPadding(compresses:))`。
- 只读冻结：`ios/PurePace/Design/RunLayoutBalancePolicy.swift`（80/80/80/16 + `evaluate`）、`ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift`（691/360/68/32）。
- UI 腿采样与失败断言：`ios/PurePaceUITests/RunFlowUITests.swift:845-895`（`:890` 为失败断言），调用点 `:129`（暂停）、`:642`（未开始）、`:662`（运行中）、保存态；`testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 的运行中态同样覆盖。
- 验证口径：先 `bash scripts/test-ios.sh --unit-only`（build-for-testing + `simctl install`），再 `test-without-building` 单跑两条 UI 用例取 `ac-run-metrics-balanced` 日志；`ios.yml` 权威腿只在交付后取一次结果（alarm / 常驻任务，不轮询）。
- 预算：≤8M token / ≤90 分钟；到点交未闭合回执。
