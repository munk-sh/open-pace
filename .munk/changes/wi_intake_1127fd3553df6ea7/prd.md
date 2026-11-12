# main 的 iOS UI 权威腿清红（5 条 UI 用例全绿）

## 范围

基线 commit `e9277b5`（origin/main），上一轮 `a0b0566` 的 `.github/workflows/ios.yml` run `43080817852` 有 5 条 UI 红。本项只做「把 main 的 UI 权威腿从红清到全绿」，是 C（12 屏复评截图）的前置硬闸，但本项不产出任何 C 截图。

要清的红（同一根因归并）：

1. `RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction` —— 保存态「指标区未垂直居中」（底部留白 232.3pt、最大单一垂直空洞 232.3pt、上下留白差 204.3pt，阈值 80 / 16）；未开始态也曾报最大空洞 84.6–88.6pt > 80。根因方向：`RunView.balancedMetrics` 的 `.frame(maxHeight: .infinity)` 吞掉居中余量。
2. `RunFlowUITests/testRunPauseResumeFinishAndHistory` —— 暂停态「Tab 栏数量 1 ≠ 期望 0」；同用例还会报「详情缺少导出按钮」。
3. `EvidenceCaptureUITests/testEvidenceAx5Layout` —— 「03-run-finished 主操作与其它内容相交：`run.backgroundDegraded` (22.3, 806.0, 348.3, 31.3)」，既有 `RunFinishedSummaryLayoutPolicy` 压缩未覆盖标准档 / `maxHeight:.infinity` 未拆。
4. `EvidenceCaptureUITests/testEvidenceTreesAndRealArchive` —— `runDetail.export` 在惰性 `List` 中未 realize。
5. `RunFlowUITests/testStartFinishExportGPXArtifact` —— 「详情缺少导出按钮」，与 4 同因。

处理口径（已定，不得改回）：

- **A. 详情页导出**：`runDetail.export` 是详情页主操作，按 AGENTS「主操作固定底部安全区上方、一屏一个主操作」做成底部固定主操作——内容区（`List`）可滚动，导出不进滚动区，复用 `RunView` 已有的 `.safeAreaInset(edge: .bottom)` 锚点写法。**不允许**把测试改成「先滚动再找导出」来绕开；RunFlow 用例语义就是导出必须直接可见。
- **B. 结束态 / 未开始态指标区**：去掉 `.frame(maxHeight: .infinity)` 这类吞居中的写法，让指标区在标准档与 AX5 档都满足既有居中阈值（80 / 16pt）；AX5 继续复用 `RunFinishedSummaryLayoutPolicy`。若需新增参数，按「实测溢出值 → 参数 → 复用点」三件套写进该策略，禁止逐屏补丁、禁止视图层裸 magic number、不新增字号档 / 色键。
- **C. 暂停态 Tab 栏**：按既有设计「记录态 / 结束待保存态收起 Tab 栏」修真问题；若实测是测试取树口径错（例如取到系统 chrome），改测试侧并把判据写进 `docs/verification-matrix.md`，不为绿放宽断言。
- **D. 断言只增不减**：不得删断言、不得放宽超时、不得加 `continue-on-error`、不得把用例改成条件跳过；新增/修改断言同 commit 附「构造错误输入 → 必须红」反例。accessibility identifier 只增不改。

## 验收

- ac-detail-export-bottom-fixed: `RunDetailView` 的 `runDetail.export` 渲染在 `List` 之外、底部安全区上方的固定主操作区（`.safeAreaInset(edge: .bottom)` 或等价固定锚点），详情页首次进入无需滚动即可命中；`List` 内容仍可滚动且导出按钮不在 `List` 的 section 内。
- ac-detail-export-visible-without-scroll: `RunFlowUITests/testStartFinishExportGPXArtifact` 与 `testRunPauseResumeFinishAndHistory` 在「未执行任何滚动操作」的前提下能找到并点击 `runDetail.export`；用例内既有断言零删除、超时零放宽。
- ac-trees-export-realized: `EvidenceCaptureUITests/testEvidenceTreesAndRealArchive` 的 `recordPrimaryAction(app.buttons["runDetail.export"], screen: "05-history-detail")` 在 30s 内取到元素（惰性 List 不再影响导出可见性）。
- ac-evidence-ax5-no-overlap: `EvidenceCaptureUITests/testEvidenceAx5Layout` 的 03-run-finished 屏 `run.backgroundDegraded` 与主操作互不相交（标准档与 AX5 档均成立），四屏 `AX5-FIT`（outOfBounds=0 / overlaps=0）保持。
- ac-finished-metrics-centered: 保存态指标区三条居中判据全部通过：底部留白 ≤ 80pt、最大单一垂直空洞 ≤ 80pt、上下留白差 ≤ 16pt。
- ac-ready-metrics-centered: 未开始态指标区最大单一垂直空洞 ≤ 80pt（既曾实测 84.6–88.6pt，必须压回阈值内）。
- ac-no-infinite-frame-centering: `RunView.balancedMetrics` 不再用 `.frame(maxHeight: .infinity)` 吞掉垂直余量；居中由语义间距 / `Spacer` 分布承担，视图层不新增裸 magic number。
- ac-paused-tabbar-hidden: 暂停态 `tabBars` 数量 = 0，与 `TabBarVisibilityPolicy.expectedTabBarCount` 一致；记录态 / 结束待保存态 0，`ready` / 已保存 / 历史 / 设置 1，四态判据同时成立。
- ac-assertions-not-weakened: 5 条用例的既有断言数量不减少、超时不放大、无 `continue-on-error`、无条件跳过；`xcodebuild` UI 腿全包 exit 0 且失败数为 0。
- ac-counterexamples-red: 每条新增/修改断言同 commit 附「构造错误输入 → 必须红」反例并在本地实跑红：居中三判据的错位反例、导出移回滚动区的反例（导出未直接可见必红）、暂停态 Tab 栏数量错配反例；反例结果落 `.munk/` 日志。
- ac-verification-matrix-updated: `docs/verification-matrix.md` 对应行写明「断言名 / 反例 / 证据路径 / 归属项」，证据路径指向本项落盘日志。
- ac-ui-leg-local-green: 本地 UI 腿（`scripts/test-ios.sh` 的 UI 部分或等价 `xcodebuild test` UI 全包）0 失败，日志落 `.munk/` 且在回执给出路径。
- ac-shell-self-test-green: 交付前显式跑 `scripts/check-ios-shell.sh --self-test` 全绿（该自检不在 `code_gates` 腿列表内，必须单独跑）。

## 非目标

- 不产出 C 的 12 张截图 / 确认层 / 复评材料。
- 不改色板与设计令牌数值（`DesignTokens` 现有 18 键 × light/dark 冻结值零改动）。
- 不动地图壳语义（MapKit 单 SDK、polyline 缓存、相机一次定位）。
- 不做分发 / 归档 / store 动作。
- 不处理 CI 期间可能新暴露的其它红项（另开项）。
- 不新增字号档、色键、第三方依赖；不引入设计 token 之外的常量。

## 实现约束

- **起点**：`e9277b5`（origin/main），工作树即为本项分支。
- **已核文件锚点（直接采信，未逐行考古）**：
  - `ios/PurePace/Run/RunView.swift:95` —— `balancedMetrics` 的 `.frame(maxWidth: .infinity, maxHeight: .infinity)`，B 的删除点。
  - `ios/PurePace/Run/RunView.swift:47` —— 已有 `.safeAreaInset(edge: .bottom)` 底部固定主操作锚点，A 直接复用同一写法与 `surface` + `separator` 视觉。
  - `ios/PurePace/History/RunDetailView.swift:18-27` —— `List { meta / hero / metricGrid / map / splits / export }`，导出当前在 `exportSection`（`runDetail.export` 在 :146），A 需把导出移出 `List`。
  - `ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift` —— AX5 压缩共享策略，B 的参数唯一落点（三件套：实测溢出值 → 参数 → 复用点）。
  - `ios/PurePace/Design/RunLayoutBalancePolicy.swift` —— 居中阈值 80 / 16 的既有真源，阈值不得改。
  - `ios/PurePace/Design/TabBarVisibilityPolicy.swift` —— 记录态 / 结束待保存态收起判定，C 的期望值来源（隐藏=0，可见=1）。
  - `ios/PurePaceUITests/RunFlowUITests.swift`（`testZhHansCopyDatesAndBottomAnchoredPrimaryAction`、`testRunPauseResumeFinishAndHistory`、`testStartFinishExportGPXArtifact`）、`ios/PurePaceUITests/EvidenceCaptureUITests.swift`（`testEvidenceAx5Layout`、`testEvidenceTreesAndRealArchive`）。
  - `scripts/test-ios.sh`（UI 腿入口）、`scripts/verify-ios-ui-e2e.sh`（持锁串行旁证）、`scripts/check-ios-shell.sh --self-test`。
  - `docs/verification-matrix.md`（22 行表格，对应行补写）。
- **仓库基线已就绪**：`AGENTS.md` 已路由 `.agents/skills/swiftui-pro` 与 `.agents/skills/android-cli`；iOS UI 与设计 token 基线已存在，本项不触发 repo-bootstrap / ui-baseline，不新建工程、不新增 skill。
- **A 的固定主操作要求**：导出按钮为详情页唯一主操作，播报/导出结果（`runDetail.exported` / `runDetail.exportFailed`）可留在内容区或主操作区，但主操作按钮本身必须在固定区；不得在 `List` 内保留第二份导出按钮。
- **B 的三件套**：新增 AX5 参数必须在 `RunFinishedSummaryLayoutPolicy` 内以「注释写明实测溢出值 + 命名参数 + 复用点列表」形式落地，视图层只读取策略属性。
- **C 的取树口径**：若最终确认是测试侧取到系统 chrome 导致计数错，改 `assertTabBarVisibility` 的取树方式并在 matrix 写明判据；不得把断言改为「≥0」或跳过。
- **本地执行**：模拟器重腿持锁串行（`scripts/verify-ios-ui-e2e.sh` 或等价 xcodebuild），日志与反例日志统一落 `.munk/`；不重跑已绿腿。
- **硬预算**：≤8M token / ≤90 分钟墙钟，到点即停手交四栏回执（已做 / 未做 / 已过门 / 未闭合点），不续命。
