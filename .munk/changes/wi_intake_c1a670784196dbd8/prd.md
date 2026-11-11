# 记录态收起 TabBar + 权限横幅降为卡片次级行

公司裁决 `owe_05122fb8604f2373`：本项是当前**唯一**在飞窄写项，只做下面两件事，不得扩范围。基线 = 本 worktree `HEAD 7c8cbef`。

## 范围

1. **记录态与结束待保存态收起底部三 Tab**：`running` / `paused`（记录态）以及 `finished && !didSave`（结束待保存态）隐藏 TabBar，跑动中不可误触离开主界面；`ready`（idle）、保存后总结态、历史页、设置页恢复正常三 Tab。全程不得出现必须杀进程/重启才能脱困的断头路。
2. **权限横幅移出主视区**：`WhenInUse` 降级时的后台定位提示（现为指标卡与主操作之间的整行 warning 胶囊）改为指标卡内的紧凑 `caption` 次级行（无胶囊底、无整宽弱底），不再压在距离/用时等主数据之上；同时不得在 hero 与提示片之间、提示片与主操作之间新增大片死白。

只改 iOS 跑步页与首屏 Tab 容器（`ios/PurePace/ContentView.swift`、`ios/PurePace/Run/RunView.swift`，必要时 `RunInteractionPlan.swift` 仅调整提示分区），以及配套纯判定、单测、UI 用例、截图与 digest。**零**颜色/字号 token 改动。

## 验收

- ac-tabbar-hidden-recording: 模拟器真实运行中（`running` 与 `paused` 均测），`XCUIApplication().tabBars.count == 0`，且「跑步 / 历史 / 设置」三个 tab 按钮均不存在（不可见、不可点）；`run.pause` / `run.resume` 可点，记录不中断（距离/用时继续增长）。
- ac-tabbar-hidden-finished-pending: 结束待保存态（`finished && !didSave`）下 `app.tabBars.count == 0` 且无 tab 按钮；`run.save` 与 `run.discard` 均可达。
- ac-tabbar-restore-no-deadend: 同一进程内，保存或丢弃结束后回到 idle/保存总结态，`app.tabBars.count == 1` 且三 tab 可点；再从 idle 切历史、设置并回跑步，TabBar 始终可见可点；全程不重新 launch App，不会出现只能杀进程的断头路。
- ac-tabbar-assert-red-proof: 同 commit 内，Tab 数量判定由可注入输入、不依赖 UI 的纯函数实现（期望值：记录态/待保存态隐藏=0，其余可见=1）；单测至少两个反例真实判红——记录态喂 `tabCount=1` 判失败、idle 喂 `tabCount=0` 判失败；对应正例通过。反例只喂不同输入，**不得靠修改 `ios/PurePace/**` 生产代码才变红**。
- ac-permission-banner-demoted: 在 `WhenInUse` 降级态下，后台定位提示不再是指标列上的整行 warning 胶囊；它以 `caption` 字号渲染在指标卡内的次级行（或紧贴卡片的次级区），无 `Capsule` 背景、无整宽弱底；`run.backgroundDegraded` identifier 保留、文案不变；其 frame `minY` 大于 `run.distance` frame `maxY`（机器证明不在距离 hero 上方），且不插在 hero 与指标卡之间。
- ac-layout-balance-thresholds-unchanged: `RunLayoutBalancePolicy` 四阈值（`maximumTopGap/maximumBottomGap/maximumGap = 80`、`maximumImbalance = 16`）源码不变；UI 用例在 ready（含降级提示）/ running / paused / saved 四态仍全部判绿并打印 `ac-run-metrics-balanced`；重排后 hero→提示、提示→主操作之间不出现 >80pt 的新空洞，|top − bottom| ≤16。
- ac-a11y-identifier-diff-zero: 既有 36 项 identifier 集合零增、零删、零改名（`scripts/check-ios-shell.sh` 的冻结 33 项与必需新增 3 项清单均不改；改动前后实跑去重集合完全相同）。
- ac-l10n-copy-preserved: 不新增裸英文或散落中文字面量；提示仍取既有 `L10n.backgroundDegradedHint` / `run.status.*` 与 `Localizable.xcstrings`，既有 `VisibleTextPolicy` 可见文案断言不变。
- ac-xcodegen-generated: `ios/project.yml` 是唯一工程真源，`xcodegen generate --spec project.yml`（cwd=`ios/`）可重复生成；不手改 `project.pbxproj`（`.xcodeproj/` 已 gitignore，diff 不含工程文件）。
- ac-code-gates-green: `.munk/code-gates.json` 全部门退出 0，含 `lint-ios-shell --self-test`、`build-ios`、`test-ios --unit-only`；不得删门、改门 id 或放宽既有断言。
- ac-evidence-screenshots: 记录态与结束待保存态各出浅/深截图：刷新 `docs/screenshots/run-running.png`、`run-running-dark.png`、`run-finished.png`、`run-finished-dark.png`，四张均为本轮真实 `xcrun simctl io <udid> screenshot` 产物（非空 PNG，1179×2556），不复用旧图、不手绘；逐文件 sha256 写入 `docs/screenshots/SHA256SUMS`，并把该文件最近改动 commit 全 sha 与 sha256 一并写入 `.munk/changes/{workItemId}/digest.md`（sha 用 `git log --format=%H -1 -- <file>` 实取，不猜不沿用旧值）。
- ac-evidence-a11y-trees: 同一轮 XCUITest 经既有 `scripts/capture-ios-screenshots.sh --stage trees` 机制重出 `docs/evidence/a11y/02-run-running.txt` 与 `03-run-finished.txt`，两份树中 TabBar 节点数为 0；测试日志打印 `ac-tabbar-hidden` 的实测计数证据（记录态与待保存态 `tabBarCount=0`）。
- ac-digest-budget-receipt: digest 开头记录预算回执（≤90 分钟、≤8M token、开工时刻、期望收口时刻）；超时立即停手回执，不得靠长会话自查补绿。
- ac-scope-bounded: diff 仅限 `ContentView.swift` / `RunView.swift`（及必要的提示分区纯逻辑）、新增 Tab 可见性纯判定与其单测、既有 UI 用例适配、截图/a11y 证据、digest 与 `SHA256SUMS`；零颜色/字号 token 改动，零地图/`TrackMapView`/结束总结感/分段明细，零定位/音频/持久化契约改动，零其他屏视觉改动，零分发动作。

## 非目标

- 不动任何颜色、字号、间距数值 token（三套色板待人拍板，提前改色一律打回）。
- 不做地图 / `TrackMapView` / 结束态总结感 / 分段明细——等色板与令牌项一起做。
- 不动定位、音频、持久化契约；不加新功能；不做任何分发动作。
- 不顺手改历史页、设置页、详情页或 Harness 的视觉；不做整屏重设计。
- 不排真机、不排人手步骤；真机项不出现在本项验收里。

## 实现约束

- **已加载/路由既有基线**：仓库已是 Munk 基线（`AGENTS.md` 路由 `.agents/skills/swiftui-pro`）。本项不新建工程、不跑 repo-bootstrap；改代码前按 `AGENTS.md` 读 `.agents/skills/swiftui-pro`。
- **路由（已定，不再开规格阶段）**：`needPm=false` / `needDesign=false` / `needArchitect=false` / `needChangePackReview=false`——人已给定两处缺口、验收与反范围，直接 Coding。
- **预算**：≤90 分钟、≤8M token。Intake 开工 2026-11-11 19:27 CST，期望收口 ≤ 20:57 CST；Coding 在 digest 先写预算回执，超时即停手回执。
- **TabBar 隐藏实现口径**：隐藏必须让 tab 栏从可及树消失（`tabBars.count == 0`），不得只是视觉遮挡。禁止用重建 `RunSessionViewModel`、重新 `launch` 或重走 `onAppear` 的方式切换根视图（`onAppear` 会 `locationSource.start()`，可能重启采样/重复计数）；判定只读 `runModel.state` + `didSave`。进入 idle/保存后总结/历史/设置必须显式恢复可见（如 `.toolbar(isImmersive ? .hidden : .visible, for: .tabBar)`），并在同一进程内用 UI 用例验证。
- **主操作锚定断言的适配边界**：TabBar 隐藏后，running/paused 的 `assertPrimaryActionAnchored` 不能再用 TabBar frame；只允许把该 UI 辅助改成「距窗口底边（扣除 Home Indicator 安全区）锚定」的等价检查，**不得删除该断言、不得放宽 `PrimaryActionLayoutPolicy` 的 44/24 阈值与单测**；idle/saved 仍用 TabBar frame 原断言。死白断言 `RunLayoutBalancePolicy` 属硬约束，源码与阈值零改动。
- **提示分区**：提示数据仍由 `RunInteractionPlan` 单一决策；只调整 `.backgroundDegraded`（以及权限类提示，如为保持同屏一致）的渲染位置/样式，不改 `RunSessionState`、`RunSessionViewModel` 行为与 `notice` 优先级语义。错误类提示（`recordingError` / `decisionFailed`）不在本项范围内，保持现状。
- **可及标识**：复用既有 `run.backgroundDegraded` / `run.distance` / `run.start|pause|resume|finish|save|discard|viewHistory` / `tab.*`；不新增 identifier。若确需新 id，也必须是「非空 + 全局唯一 + 带非空可读 label」，但本项验收要求 diff=0，优先不加。
- **工程与门禁**：`ios/project.yml` 手工新增文件时必须同步（新纯判定若被 UITests 复用，按既有 `VisibleTextPolicy` 等做法显式列入 `PurePaceUITests` sources），然后 `xcodegen generate --spec project.yml`；`.xcodeproj` 不入库。`scripts/check-ios-shell.sh` 中「Spacer ≥ 4」「语义间距 token」「RunView 三态色引用」「33+3 identifier」等既有静态断言必须保持绿，必要时只做不弱化既有断言的适配。
- **证据口径**：沿用 `scripts/capture-ios-screenshots.sh` 的 `trees` / `screenshots` 阶段与 `simctl io screenshot`；同一台 iPhone 16（UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`，iOS 18.6）。深色用 `xcrun simctl ui <udid> appearance dark` 真实切换，禁止后期调色。结束待保存态用既有 DEBUG 门控 `-screenshotRunFinished`，不得靠改生产逻辑造态。
- **禁止**：改 `.munk/baseline/**`、`shared/**`、`android/**`、CI 工作流与发布脚本；不得以「顺手优化」扩大 diff。
