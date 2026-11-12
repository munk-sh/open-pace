# 清红 main 的 iOS 权威腿（ios.yml 同 commit run 确定性全绿）

## 范围

以 `main=51997ff` 的权威 run `43142574712` 为基线，把 iOS UI 腿的红灯清到**确定性**全绿，并把同族失败的成因固化成仓库约定，避免第三次复发。

事实基线（本 run 原文）：

- 失败点：`ios/PurePaceUITests/RunFlowUITests.swift:590`，`testAnnouncementTogglePersistsAcrossRelaunch`——`app.terminate()` + `app.launch()` 后直接 `relaunchedTabBar.buttons["设置"].tap()`，随后 `settings.announcementToggle` 在 10s 内未出现。
- 同 run 其余 UI 用例（pause/resume、公里边界、0 分段、导出 GPX）通过 → 产品侧地图修复（`96pt` 下限、保存态 canonical）未回退，本条是**测试状态机缺陷**而非产品回退。
- UI 腿墙钟 603s 顶到 600s 单腿上界（boot=206s prep=53s build=195s unit=55s ui=603s）。
- 历史：自 11-11T04:59Z 起 ios 腿连续红，失败点分散（细节行 311/510/689/713/789、EvidenceCapture 116/255/310），多为「导航后 getElement 未出现」；`4d522e6` 同一测试曾 passed（23.8s），本 commit 该用例代码未改。

本项要做的四件事：

1. **真实证据定位**：本地用同一 `xcodebuild` 命令复跑该用例（可加人为负载/慢速条件），失败时抓可及树/截图；无法复现则明确写「未复现 + 依据」，再按状态机判据加固（断言强度与 timeout 数值不变）。
2. **系统性加固同类风险**：同一套件内凡「tap 被吞 / 页面未就绪」依赖墙钟的断言，改为状态判据 + canonical 输入（参照本仓已有 `-uiTestLocationTargetMeters` 做法）。
3. **UI 腿墙钟度量与（必要时）分段**：度量 13 条 UI 用例在同 job 内的真实墙钟与用例级 setup 开销；若证据表明单次 `xcodebuild` 600s 上界结构性装不下，允许把 UI 腿拆成多次 `xcodebuild` 调用（每次仍 ≤600s，workflow 内分段执行），但**禁改阈值、禁加长 timeout、禁 continue-on-error、禁删腿**，并在 PRD/注释写明「拆分≠放宽」依据。
4. **约定落盘**：同族失败已 ≥2 次，本项内把结论写回 `AGENTS.md`（或 ios 子目录约定）：禁止墙钟依赖断言；导航/重启后必须状态判据而非固定 sleep；单次 `xcodebuild` ≤600s 下的套件分段执行约定。不留到下次。

## 验收

- ac-authoritative-run-green: 合入后新 commit 触发的 `ios.yml` 权威 run 中 `ios` job 全绿：unit 腿 0 失败、UI 腿 13 条用例 0 失败（13/13 passed），`android` job 结论与合入前一致（不受影响）；回执附 run id + 绿日志片段。
- ac-no-local-only-closure: 闭合判据只认权威 run；仅本地绿不算闭合，未拿到绿 run 时按「未闭合回执」交付并写明阻塞点。
- ac-repro-or-evidence: 本地复跑该用例（同一 `xcodebuild` 命令，必要时加人为负载/慢速条件）产出结论：复现则附失败时可及树/截图与命令原文；未复现则记录「未复现 + 依据」（命令、条件、重复次数、结果），二者择一，不得省略。
- ac-relaunch-state-gate: 重启后切到设置页的路径以状态判据就绪——先等 Tab 栏存在、再等 `设置` 按钮 `exists && isHittable`，tap 后以设置页根/`settings.announcementToggle` 出现作为页面就绪判据；若 tap 后判据在既有 timeout（10s）内未满足，允许**重试 tap ≤2 次**（不提高 timeout、不降低断言强度）。
- ac-relaunch-toggle-value: 重启后 `settings.announcementToggle` 值仍必须为 `"0"`（保存态跨重启断言强度不变）。
- ac-no-fixed-sleep: 改动后 UI 测试源码不新增 `sleep(` / `Thread.sleep` / `usleep`；所有等待走 `waitForExistence` / `waitUntil` 谓词轮询。
- ac-canonical-input-not-wallclock: 凡断言内容会随运行时长漂移的用例，改用 canonical 启动输入（`-uiTestLocation` / `-uiTestLocationTargetMeters` 等）锁定输入；13 条 UI 用例中不存在「跑得久就改变断言期望」的输入条件。
- ac-red-proof-for-changed-assertions: 每条新增/改动的断言在同 commit 附「构造错误输入必红」反例（错误输入 → 断言判红），并在本地实跑证明红/绿两侧都成立。
- ac-ui-leg-wallclock-measured: 产出 13 条 UI 用例在同一 job 内的逐用例墙钟 + 用例级 setup 开销实测数据（来自 xcresult/log 时间戳），写入 PRD 或证据文件。
- ac-split-not-relaxed: 若采用分段：UI 腿拆为多次 `xcodebuild` 调用且每次单次上界 ≤600s，`IOS_XCODEBUILD_TIMEOUT` 仍为 600，无 `continue-on-error`，无腿被删；PRD/脚本注释明确写「拆分≠放宽」及触发该决定的数据依据；若实测不需要拆分，则明确写「不拆分 + 数据依据」。
- ac-thresholds-frozen: `IOS_XCODEBUILD_TIMEOUT=600`、`-default-test-execution-time-allowance` / `-maximum-test-execution-time-allowance` 等执行预算参数数值不变；80/16、96pt 等既有阈值不变。
- ac-identifiers-frozen: 不新增 accessibility identifier；`check-ios-shell.sh` 冻结标识清单与用例计数保持一致（确有必要新增时只增不改，并同步清单与计数）。
- ac-shell-selftest-green: 若改动受管视图或 identifier，`bash scripts/check-ios-shell.sh --self-test` 全绿并同步用例计数。
- ac-agents-convention-landed: 仓库约定落盘（`AGENTS.md` 或 ios 子目录约定）且包含三条：(a) 禁止墙钟依赖断言；(b) 导航/重启后必须状态判据而非固定 sleep；(c) 单次 `xcodebuild` ≤600s 下的套件分段执行约定。同时有脚本断言（`check-ios-shell.sh` 或 `check-ios-workflow.sh`）保证该约定文本存在，防回归。
- ac-verification-matrix-updated: `docs/verification-matrix.md` 对应行更新，含接缝、断言名、反例、证据路径、归属项。
- ac-no-product-behavior-change: 不改 UI 视觉/布局/产品行为，不改产品地图修复与保存态 canonical 逻辑。
- ac-gates-green: 本地 `.munk/code-gates.json` 中 `lint-ios-*` / `test-ios`（`--unit-only`）/ `build-ios` / `check-gpx-export` / `test`（baseline）全绿。

## 非目标

- 不做 C 项 12 张复评截图；不碰分发（签名/上架/归档）。
- 不新增 UI 用例、不重构 UI 测试文件结构（除必要的最小加固）。
- 不调整 80/16、96pt、字号/间距等既定设计与断言阈值。
- 不做真机手测项（真机项仍 `pending: 待人现场`）。
- 不扩大范围到 Android / Core 逻辑；`android` job 只需保持不受影响。
- 不为了让 CI 变绿而降低任何既有断言强度、缩短被测流程或跳过用例。

## 实现约束

已由 owner 明确的技术锚点与硬约束（非正式技术方案，架构取舍留给 Coding 按证据决定）：

- 失败锚点：`ios/PurePaceUITests/RunFlowUITests.swift:582-591`（重启段：`terminate()` → `launch()` → 直接 `tap()` → `waitForExistence(10)`）；同类首段 `:555-580`；另见 `:702`、`:1053`、`EvidenceCaptureUITests.swift:70,180`。
- 套件规模：13 条 UI 用例 = `RunFlowUITests`(6) + `EvidenceCaptureUITests`(2) + `Ax5ScrollAudit`(3) + `MusicSourceSelfCheckUITests`(2)。
- 预算与看门狗：`scripts/test-ios.sh:140-212`（`IOS_XCODEBUILD_TIMEOUT` 默认 600、`PUREPACE_IOS_UI_MIN_BUDGET_SECONDS` 默认 300、`scripts/lib/ios-budget.sh` 记账）；`.github/workflows/ios.yml` 的 `test` step（step 预算 2700s、仅承载层不稳定才重试、`infra_pattern` 硬编码、`blocked:` 判失败）。
- canonical 输入先例：`-uiTestLocation`、`-uiTestLocationTargetMeters`（`RunFlowUITests.swift:597-604` 注释已记录 1200m = 1 条分段的归因做法）。
- identifier 冻结面：`scripts/check-ios-shell.sh:893`（frozen_ids）、`:984`、`:2024`；`--self-test` 入口 `:29,:44,:1086-1151`。
- workflow 结构断言：`scripts/check-ios-workflow.sh`（444 行）——分段改动需同步该检查器的期望。
- 约定落盘位置：仓库根 `AGENTS.md`（禁止删除其 skill 路由表；新增「测试稳定性约定」小节）或 `ios/` 子目录约定文件 + `AGENTS.md` 路由一行。
- 证据基线：run `43142574712`；时间分解 boot=206s / prep=53s / build=195s / unit=55s / ui=603s。
- 预算：≤8M token / ≤90 分钟；到点未闭合则交未闭合回执（含已取得证据与下一步）。
