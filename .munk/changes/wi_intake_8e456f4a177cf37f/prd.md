# 修 UI 权威腿的测试脚手架稳健性（AX 索引绑定 → 批采快照）

## Scope

只改 `ios/PurePaceUITests/` 下的测试脚手架，消除对 `XCUIElementQuery.allElementsBoundByIndex` 返回元素的「按序号惰性回读」依赖，换取权威 UI 腿的确定性。

红证据（原样引用，勿改写）：CI run 43257709590（head 7411eaa，iOS 18.6 iPhone 16）唯一失败用例 `RunFlowUITests.testZhHansCopyDatesAndBottomAnchoredPrimaryAction`，错误原文 `<unknown>:0: error: ... Failed to get matching snapshot: No matches found for Element at index 39`，重试 2 次、用时 52.9s；6 个 UI 用例 1 红 5 绿。同类历史 run 43183052585 出现 `index 37`。

已核实（不重测）：居中修复实质成功（暂停 79.42/79.33/79.5、未开始 72.5/72.33/72.67、保存 48.17，全 ≤80，整场日志「指标区未垂直居中」零命中），权威腿红因是脚手架索引绑定，不是产品回归。

根因：`allElementsBoundByIndex` 返回的元素按索引惰性解析快照；逐个回读 identifier/frame/label 时，若 AX 元素数漂移（实测 37↔39，MapKit 注记随相机漂移漏入）即抛 `No matches found for Element at index N`。需修 6 处：

1. `ios/PurePaceUITests/RunFlowUITests.swift:774-775`（`assertVisibleCopyZhHans`，本次失败点；同函数内被调用 7 次）
2. `RunFlowUITests.swift:855`（`assertRunMetricsBalanced`）
3. `RunFlowUITests.swift:975`（`assertFinishedContentBudget`）
4. `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift:254-255`（同名副本 `assertVisibleCopyZhHans`）
5. `ios/PurePaceUITests/EvidenceCaptureUITests.swift:272`（`assertFitsAndNoOverlap`）
6. `EvidenceCaptureUITests.swift:413`（`contentElements`）

## Acceptance Criteria

- ac-diff-test-only: 交付 commit 的 `git diff` 只含 `ios/PurePaceUITests/` 下文件（可含 `docs/verification-matrix.md` 对应行），产品代码（`ios/PurePace/**`、`ios/Core/**`、`scripts/**`、`android/**`、`shared/**`）零改动。
- ac-no-lazy-index-read: 上述 6 处不再对 `allElementsBoundByIndex` 的返回元素做按序号的惰性属性回读（`identifier` / `label` / `frame` / `elementType`）；grep `allElementsBoundByIndex` 后逐处确认改走批采 helper 或 identifier/谓词 + `firstMatch` 定向查询。
- ac-batch-snapshot-helper: 存在共享批采 helper：一次调用即把当前 AX 树的 `count` 与每项的 `identifier` / `label` / `frame` / `elementType` 读入本地值类型（`struct`/元组），后续过滤与断言只消费本地值，不再触碰 `XCUIElement`。
- ac-bounded-recollect: 批采 helper 在读取过程抛出「快照失配」（`No matches found for Element at index N`）时，重采**整批**（非重取单个索引），单次等待 ≤3s、复用已有 `waitUntil` 语义、次数上限在代码中写死并注释说明；不引入无限重试、不新增/放大既有 timeout 上限、不引入固定 `sleep`。
- ac-failure-message-actionable: 重采达上限仍失败时，失败信息必须含当前采集到的元素数 + 目标 identifier/label（用于区分「元素数漂移」与「目标真缺失」），而不是仅透传 XCUITest 的 `Element at index N`。
- ac-visible-copy-semantics-preserved: 两处 `assertVisibleCopyZhHans` 改用同一批采口径后过滤语义不变——仍排除 `run.telemetry`、仍按 `run.mapPreview` 区域内且非地图卡本身过滤 MapKit 注记、仍排除 `isSystemSymbolLabel`，仍把结果喂 `VisibleTextPolicy.violations` 且 `violations.isEmpty` 的断言强度不变。
- ac-frame-sampling-semantics-preserved: `assertRunMetricsBalanced` / `assertFinishedContentBudget` / `assertFitsAndNoOverlap` / `contentElements` 改用批采后，内容类型集合、frame 过滤条件、窗口/主操作/地图/胶囊采样口径与既有断言阈值全部保持原值。
- ac-no-gate-weakening: 未删除/跳过任何用例，未加 `continue-on-error`，未改任何阈值或 identifier 集合，未改 `scripts/check-ios-scripts.sh` 的枚举与守卫，未重出 `docs/screenshots` 证据。
- ac-local-gates-green: 本地 `bash scripts/test-ios.sh` 相关 UI 分段（或等价单段命令）全绿；`bash scripts/check-ios-shell.sh --self-test`（100 项）与 `bash scripts/check-ios-scripts.sh`（34 项）全绿；identifier 计数 42（冻结 33）不变。
- ac-ci-same-commit-green: 交付后同 commit 的 `ios.yml` 全绿（覆盖全部 `*UITests` 套件，6 个 RunFlow 用例全 passed）；结论由 Owner 取 run 结果，禁止重跑到绿。
- ac-receipt-honesty: 回执写清改前红（run 43257709590 原文照引）与改后同用例绿；未取到 run 结论前只能写「未闭合」，不得写「居中未修好」或「产品回归」。

## Non-Goals

- 不动 `RunView` 布局、`DesignTokens`、`RunLayoutBalancePolicy` / `RunFinishedSummaryLayoutPolicy` 阈值。
- 不改任何 accessibility identifier 集合，不新增/删除门禁项。
- 不重出截图证据，不动 `docs/screenshots`。
- 不重构 UI 测试的组织结构、不合并/拆分套件、不调整 `ui_call` 分段。
- 不追求「跑得更快」或用重试掩盖产品缺元素：批采失败信息必须能暴露真缺失。

## Implementation Constraints

- 已约定做法（择一或组合，按最小改动）：a) 明确目标的查询改 identifier / `NSPredicate` 谓词 + `firstMatch`，不按序号取；b) 需要全树枚举的，改「一次采集到本地值（count + 每项的 identifier/label/frame 全量读入）」的批采 helper。
- 复用 `ios/PurePaceUITests/` 内已有 `waitUntil(timeout:_:)` 语义，不新增通用并发原语；`RunFlowUITests` 与 `EvidenceCaptureUITests` / `ScreenshotEvidenceUITests` 各自已有同名 helper 现状，先看是否可共享再决定落点（跨文件共享需避免 target 归属问题）。
- 单次等待 ≤3s、重采整批、次数上限写死并注释；禁止无限重试、禁止放大 `IOS_XCODEBUILD_TIMEOUT` 等上限。
- 已知文件锚点：`RunFlowUITests.swift:774-775 / 855 / 975`、`ScreenshotEvidenceUITests.swift:254-255`、`EvidenceCaptureUITests.swift:272 / 413`。
- 官方 skill 已就位（`AGENTS.md` 路由 `.agents/skills/swiftui-pro`），本项不涉及新建工程/视觉基线，`repo-bootstrap` 与 `ui-baseline` 均不触发。
