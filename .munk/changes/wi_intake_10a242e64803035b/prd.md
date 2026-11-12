# 结束态标准字号档轨迹预览地图下限回 96pt（不再压成 32pt 条状）

## 范围

修复上一个写项（`wi_intake_1127fd3553df6ea7`，已合 main `4d522e6`）引入的视觉退化：`RunFinishedSummaryLayoutPolicy.budgetCompressedTrackPreviewHeight = Spacing.xl`（32pt）让标准字号档的压缩分支把结束态轨迹预览压成一条细条，iPhone 16 竖屏标准字号实测命中，违背 goal.md「结束态须有轨迹预览卡 + 总结感」。

本项只做四件事：

1. **地图下限**：标准字号档压缩分支的地图高度从 32pt 提到 **96pt**（= 3 × `Spacing.xl`，与 AX5 压缩档对齐）；未压缩标准档保持 180pt，AX5 保持 96pt。主力机型（iPhone 16 竖屏、标准字号）不再命中「地图 < 96pt」路径。
2. **余量再分配**：地图从 32 → 96 多占 64pt，必须从非地图项（区块间距 / 卡片内边距 / 行距 / hero 与指标区间距 / 结束态区块间距）找回，全部按「实测值 → 命名参数 → 复用点」三件套进 `RunFinishedSummaryLayoutPolicy`，视图层零裸 magic number。
3. **判据保持绿**：保存态居中三判据（bottom ≤ 80、largest ≤ 80、imbalance ≤ 16）、暂停/记录态 Tab 栏与导出、AX5 四屏 outOfBounds=0 / overlaps=0 全部保持；**阈值一律不改**（`RunLayoutBalancePolicy` 80/16 原样）。
4. **证据**：改前红（引用 `2d40bc0` 把地图压到 32pt 的命中事实 + 本项本地实测「地图压缩后高度」断言）、改后同一断言绿；新增断言同 commit 附「构造错误输入 → 必须红」反例；`docs/verification-matrix.md` 对应行补断言 / 反例 / 证据路径。

## 验收

- ac-finished-map-floor-96: 标准字号档压缩分支的地图高度 ≥ 96pt（与 AX5 档同值 96 = 3 × `Spacing.xl`）；iPhone 16 竖屏标准字号保存态实测 `run.mapPreview` frame 高度 ≥ 96pt（打印实测值，断言用数值下限，不复述生产常量）。
- ac-finished-map-not-strip: 标准字号档压缩分支不再返回 32pt；把历史值 32 作为输入喂给同一高度判据必须判红（反例）。
- ac-map-height-three-branches: 地图高度只出现 180 / 96 两个值——未压缩标准档 = 180，标准档压缩 = 96，AX5（无论是否传预算）= 96；三组合逐一断言。
- ac-nonmap-slack-parameterized: 为地图让位的非地图垂直值（结束态区块间距、分段卡内边距、卡内行距、hero→指标区间距 / 结束态顶部呼吸位等，按实测取用）全部以命名参数落在 `RunFinishedSummaryLayoutPolicy`，注释写明「实测值 → 参数 → 复用点」；`RunView` 结束态路径不出现裸数字，只读策略属性或既有 `DesignTokens.Spacing`。
- ac-saved-balance-green: `RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 保存态实测 bottom ≤ 80pt、largest ≤ 80pt、imbalance ≤ 16pt，用例通过且打印三判据实测值。
- ac-balance-audit-counts-map-card: 保存态居中审计把 `run.mapPreview` 当作可见内容块（不是空白）纳入采样；96pt 地图不再被计成「最大单一垂直空洞」。单测同构补一条保存态帧（含地图卡），并附「去掉地图卡帧 → largestGap 必红」反例；阈值 80/16 不变。
- ac-pause-history-green: `RunFlowUITests/testRunPauseResumeFinishAndHistory` 暂停态 / 记录态 `tabBars=0`，`runDetail.export` 首次进入零滚动可直接命中并点击，用例通过。
- ac-ax5-green: `EvidenceCaptureUITests/testEvidenceAx5Layout` 四屏 `outOfBounds=0 / overlaps=0`，AX5 结束态地图仍为 96、主操作不重叠。
- ac-red-before-green-after: 改前证据可回溯到 `2d40bc0`（地图压缩到 32pt）与上一项实测的保存态 `largest=64.0`（= 地图 32 + 区块间距 4 + 卡内边距 8 + 文本行盒 20）；同一「压缩后地图高度 ≥ 96」断言在改前必红、改后必绿，两份日志落 `.munk/`。
- ac-counterexamples-red: 每条新增/修改断言同 commit 附「构造错误输入 → 必须红」反例并本地实跑红（地图 32 不满足下限、去掉地图卡帧后 largestGap > 80 等），反例日志落 `.munk/`；反例不得与断言同源别名自证。
- ac-shell-self-test-green: 交付前单独跑 `bash scripts/check-ios-shell.sh --self-test` 全绿（该自检不在 `code_gates` 腿列表内）。
- ac-matrix-updated: `docs/verification-matrix.md` 对应行（详情导出固定底部 / 指标区居中 / 暂停态 Tab 栏 一行）更新为 96pt 口径，写明断言名 / 反例 / 证据路径 / 归属项。

## 非目标

- 不改 palette、字号档、identifier 冻结集（33 项只增不改；本项复用既有 `run.mapPreview`，不新增标识）。
- 不改居中阈值 80 / 16，不删断言、不放宽超时、不加 `continue-on-error`、不改条件跳过。
- 不做 C 的 12 张复评截图，不做分发 / 归档 / store 动作。
- 不重做上一项的导出底部固定与 TabBar 逻辑。
- 不处理本项范围外的新红项；不 watch / sleep 轮询 CI（CI 权威腿以 4d522e6 的既有 run 为准，本项只以本地日志交付）。

## 实现约束

- **起点**：main `4d522e6`，工作树即本项分支。仓库已有 `AGENTS.md` 路由（`.agents/skills/swiftui-pro` / `android-cli`），本项不触发 repo-bootstrap，也不是 `ui-baseline`（视觉基线已存在）。
- **语义真源与锚点**：
  - `ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift` —— 唯一参数落点：`budgetCompressedTrackPreviewHeight`（32 → 96）、`uncompressedFinishedContentHeight`（688，保持不变）、`trackPreviewHeight(compresses:isAccessibilitySize:)`、`blockSpacing/cardPadding/rowSpacing`。
  - `ios/PurePace/Run/RunView.swift:29-39`（GeometryReader + ScrollView(minHeight:)）、`:94-109`（`balancedMetrics` 的 Spacer 最小间距）、`:214-274`（`finishedTrackSummary` / `splitsDetail`）。当前 `blockSpacing(isAccessibilitySize: compresses)` 把「压缩」冒充「辅助字号」，属参数命名错位，本项应收口成显式压缩参数。
  - `ios/PurePace/Design/RunLayoutBalancePolicy.swift` —— 80/16 阈值真源，**只读不改**。
  - `ios/PurePaceTests/RunFinishedSummaryLayoutPolicyTests.swift` —— `testStandardBudgetCompressedMapUsesTokenDerivedHeight` 必须从「== 32 / ≤ maximumGap−间距」改为 96pt 下限口径（改断言，不删）；`testMapHeightKeepsAccessibilityAndUncompressedBranches` 保留。
  - `ios/PurePaceTests/LocalizationPolicyTests.swift:126-209` —— 四态居中代表帧；保存态帧需补地图卡（与 UI 审计同构）。
  - `ios/PurePaceUITests/RunFlowUITests.swift:762-794`（`assertRunMetricsBalanced` 采样）、`:597`（zh-Hans + 居中用例）、`:26`（暂停 / 历史用例）、`ios/PurePaceUITests/EvidenceCaptureUITests.swift:125`（AX5 四屏）。
  - `ios/PurePace/Track/TrackMapView.swift:140` —— `run.mapPreview` 既有标识与 `runMapPreviewLabel` 可及 label。
  - `docs/verification-matrix.md` 第 23 行（上一项）与 `scripts/check-ios-shell.sh`（`--self-test`）。
- **关键几何事实（决定了判据不能只靠缩间距）**：上一项实测保存态 `largest=64.0` 正好等于「地图 32 + 区块间距 4 + 卡内边距 8 + 文本行盒 20」；地图顶到分段标题之间没有第二个静态文本，所以 96pt 地图在「只采 staticTexts」的口径下必然被计成 ≥96pt 空洞。要让 `map ≥ 96` 与 `largest ≤ 80` 同时成立，居中审计必须把地图卡作为可见内容块纳入采样（这是加严：多一个块要判上下空洞，不是放宽阈值 / 删断言），并在单测里用同构帧与反例固定该口径。
- **余量来源**：地图 +64pt 后内容高增加，需从非地图固定项回收（估计 ≥ 40pt），候选顺序：结束态顶部呼吸位 / hero 与指标区间距 / 指标卡内边距 / 结束态区块间距 / 分段卡内边距与行距。只动结束态（`state == .finished` 且压缩）路径，未开始 / 运行中 / 暂停的既有实测值（largest 72.58 / 79.5 / 79.5）不得回归。
- **证据与执行**：本地 UI 腿持锁串行（`scripts/test-ios.sh` UI 部分或等价 `xcodebuild test`）；日志与反例日志统一落 `.munk/`，矩阵行写明路径；`--self-test` 单独跑。硬预算 ≤8M token / ≤90 分钟墙钟，到点即停手交四栏回执（已做 / 未做 / 已过门 / 未闭合点）。
