# Domain: ios-ui-leg-determinism

iOS UI 腿（`scripts/test-ios.sh` 的 UI 段）的**确定性执行契约**：导航/重启后的等待只认状态判据（Tab 栏存在 → 目标按钮 `exists && isHittable` → tap → 页面根/关键元素出现），断言期望只由 canonical 启动输入（`-uiTestLocation` / `-uiTestLocationTargetMeters`）锁定；单次 `xcodebuild` 调用硬上界仍 600s，13 条 UI 用例按目标拆成两次 `ui_call` 分段执行（RunFlow 6 / 取证+AX5+音频 7）。**拆分≠放宽**：阈值、用例数、断言强度、重试策略与 `-only-testing` 覆盖范围都不减少。产品行为、80/16 与 96pt 阈值、identifier 冻结清单与 `.github/workflows/ios.yml` 零改动。同族「导航后 getElement 未出现」失败已 ≥2 次，故约定同时落 `AGENTS.md` 并由脚本断言防回归。

## 范围

- `ios/PurePaceUITests/RunFlowUITests.swift`：重启段（`testAnnouncementTogglePersistsAcrossRelaunch`）与 `enableAnnouncements` 统一走 `private func tapSettingsUntilReady(_:screen:waitAfterTap:)`——Tab 栏 30s → `设置` `exists && isHittable` 10s → tap → `settings.announcementToggle` 出现 10s 视为页面就绪；未就绪再 tap ≤2 次（单次等待仍 10s）。失败路径打印 `NAV-GATE screen/stage/attempt`、写可及树/截图，并调用只读诊断 `private func attachPersistedAnnouncementProbe`（`-screenshotInitialTab settings` 直落设置页读持久化值，打印 `RELAUNCH-PROBE`），只用于归因、不参与断言判据。
- `scripts/test-ios.sh`：UI 腿由单次调用改为 `ui_call "<group>" "<log>" <targets...>` 两段——`runflow` = `PurePaceUITests/RunFlowUITests`，`evidence` = `EvidenceCaptureUITests` + `Ax5ScrollAuditCounterexampleTests` + `MusicSourceSelfCheckUITests`；每段独立 `ios_leg_budget(min(600, attempt 剩余))` 看门狗、独立日志 `xcodebuild-ui.log` / `xcodebuild-ui-2.log`，段前各自重装 Runner 并重申 `simctl privacy location / location-always`；任一段失败即停并保留原始退出码（不掩盖为成功）。
- `AGENTS.md`：新增「测试稳定性约定（iOS UI 腿）」三条——(a) 禁止墙钟依赖断言；(b) 导航/重启后必须状态判据（禁固定 `sleep`，重试 ≤2 次）；(c) 单次 `xcodebuild` ≤600s 下的套件分段执行约定与「拆分≠放宽」。
- `scripts/check-baseline.sh`：新增 `ac-agents-test-stability` 断言，`测试稳定性约定` 节必须同时含 `禁止墙钟依赖断言`、`状态判据`、`isHittable`、`sleep`、`≤600`、`拆分≠放宽`、`continue-on-error`。
- `scripts/check-ios-scripts.sh`：UI 顺序锚点改取首个 `ui_call "` 行；`ui_call` 调用数必须为 2；分文件日志扩为 `xcodebuild-unit.log` / `xcodebuild-ui.log` / `xcodebuild-ui-2.log`；断言「拆分≠放宽」说明与 `xcodebuild-ui-2.log` 存在；顺序反转沙箱样本改用 `ui_call` 行注入。
- `docs/verification-matrix.md` 与 `DocsVerificationMatrixTests`：新增接缝「iOS UI 腿确定性（重启导航状态判据 + 600s 单腿预算）」，接缝计数 21 → 22，该行必须含「本项实测」与归属 `wi_intake_0a4f30b4782ffdd1`。
- 与 `domains/ios-ci-budget` 的边界：预算/看门狗记账语义仍以该域为准；本域只承接「UI 腿为何分段、分段如何不削弱断言」与 UI 用例的等待判据。与 `domains/ios-ci-stability` 的边界：该域仍是测试链路总契约（预热/锁/确定性定位源），冲突时以两域各自的 AC 域内为准，分段事实以本域为准。

## 验收

- ac-authoritative-run-green: 合入后新 commit 触发的 `ios.yml` 权威 run 中 `ios` job 全绿：unit 腿 0 失败、UI 腿 13 条用例 0 失败，`android` job 结论与合入前一致；回执附 run id + 绿日志片段。
- ac-no-local-only-closure: 闭合判据只认权威 run；仅本地绿不算闭合，未取得绿 run 时按「未闭合回执」交付并写明阻塞点。
- ac-repro-or-evidence: 本地用同一 `xcodebuild` 命令复跑（必要时叠加人为负载/慢速条件）必须二择一产证：复现则附失败时可及树/截图与命令原文；未复现则记录命令、条件、重复次数与结果，不得省略。
- ac-relaunch-state-gate: 重启后切设置页以状态判据就绪——先等 Tab 栏，再等 `设置` `exists && isHittable`，tap 后以 `settings.announcementToggle` 出现作为页面就绪判据；判据未满足允许**重试 tap ≤2 次**，不提高 timeout、不降低断言强度。
- ac-relaunch-toggle-value: 重启后 `settings.announcementToggle` 值仍必须为 `"0"`（保存态跨重启断言强度不变）。
- ac-no-fixed-sleep: 改动后 UI 测试源码不新增 `sleep(` / `Thread.sleep` / `usleep`；所有等待走 `waitForExistence` / 谓词轮询。
- ac-canonical-input-not-wallclock: 断言内容会随运行时长漂移的用例必须由 canonical 启动输入锁定；13 条 UI 用例中不存在「跑得久就改变断言期望」的输入条件。
- ac-red-proof-for-changed-assertions: 每条新增/改动的断言在同 commit 附「构造错误输入必红」反例，并在本地实跑证明红/绿两侧成立（反例代码不留仓）。
- ac-ui-leg-wallclock-measured: 产出 13 条 UI 用例在同一 job 内的逐用例墙钟 + 用例级 setup 开销实测数据（xcresult/log 时间戳），写入验证矩阵或证据文件。
- ac-split-not-relaxed: 若分段：每次 `xcodebuild` 调用各自 ≤600s 上界，`IOS_XCODEBUILD_TIMEOUT` 仍 600，无 `continue-on-error`，无腿被删，`-only-testing` 覆盖集合不减少；脚本注释与本域写明「拆分≠放宽」及触发决定的数据依据；若实测不需拆分则明确写「不拆分 + 数据依据」。
- ac-thresholds-frozen: `IOS_XCODEBUILD_TIMEOUT=600`、`-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540`、80/16、96pt 等既有数值不变。
- ac-identifiers-frozen: 不新增 accessibility identifier；`scripts/check-ios-shell.sh` 冻结标识清单与用例计数保持一致（确需新增时只增不改并同步清单与计数）。
- ac-shell-selftest-green: 若改动受管视图或 identifier，`bash scripts/check-ios-shell.sh --self-test` 全绿并同步用例计数。
- ac-agents-convention-landed: 仓库约定落盘（`AGENTS.md` 或 ios 子目录约定）含 (a) 禁止墙钟依赖断言、(b) 导航/重启后状态判据、(c) 单次 `xcodebuild` ≤600s 分段执行；并有脚本断言（`check-baseline.sh` / `check-ios-workflow.sh`）保证该文本存在防回归。
- ac-verification-matrix-updated: `docs/verification-matrix.md` 对应行更新，含接缝、断言名、反例、证据路径、归属项，且结构守护测试（固定表头 / 接缝计数 / 6 列非空）同步通过。
- ac-no-product-behavior-change: 不改 UI 视觉/布局/产品行为，不改产品地图修复与保存态 canonical 逻辑。
- ac-gates-green: 本地 `.munk/code-gates.json` 中 `lint-ios-*` / `test-ios`（`--unit-only`）/ `build-ios` / `check-gpx-export` / `test`（baseline）全绿，门数仍 22。

## 非目标

- 不做 C 项 12 张复评截图；不碰分发（签名/上架/归档）。
- 不新增 UI 用例、不重构 UI 测试文件结构（除必要的最小加固）；不改 `.github/workflows/ios.yml` 的 `timeout-minutes` / 重试策略 / `infra_pattern`。
- 不调整 80/16、96pt、字号/间距等既定设计与断言阈值；不提高任何 timeout。
- 不做真机手测项（真机项仍 `pending: 待人现场`）。
- 不扩大范围到 Android / Core 逻辑；`android` job 只需保持不受影响。
- 不为让 CI 变绿而降低断言强度、缩短被测流程或跳过用例；不做「重跑到绿」。

## 实现约束

- 等待纪律：任何导航/重启后的就绪判定必须由「Tab 栏存在 → 按钮 `exists && isHittable` → tap → 页面根元素出现」组成，禁止固定 `sleep` / `Thread.sleep`；重试只按状态允许、上限 2 次，单次 timeout 与断言强度不变。
- 归因纪律：失败路径必须把当次可及树/截图与持久化探针写入 xcresult，并用 `NAV-GATE` / `RELAUNCH-PROBE` 区分「点击被吞 / 页面未就绪 / 未持久化」；探针只读、只在失败路径调用、不参与断言判据。
- 分段纪律：两段调用共用同一组预算参数模板与 `-only-testing` 集合派生逻辑，各自过 `run_with_watchdog` 且预算取 `min(600, attempt 剩余)`；段超时仍走 `ios_timeout_classification_message`（段日志有 failed 用例 → 产品用例失败；无 failed 才归口承载层）。
- 静态门可观测：顺序锚点 install < privacy < 单测 < UI（首个 `ui_call` 行）；`ui_call` 恰 2 次；`xcodebuild-ui-2.log` 必须出现在脚本中；macOS bash 3.2 变量展开一律带 `${}`。
- 证据口径：本地复跑与墙钟数据落 `.munk/logs/**`（`ci-run-43142574712.log`、`test-ios-split-local.log`、`relaunch/load-*.log`、`.build/logs/test-ios-timing.log`），矩阵行只引用真实文件，禁编造。

## 最近交付证明

- workItemId: wi_intake_0a4f30b4782ffdd1（2026-11-12）
- 交付：`RunFlowUITests` 新增 `tapSettingsUntilReady` 状态判据（重启段 + `enableAnnouncements` 共用）与只读 `attachPersistedAnnouncementProbe`；`scripts/test-ios.sh` UI 腿改两段 `ui_call`（`runflow` 6 条 / `evidence` 7 条），独立看门狗与日志 `xcodebuild-ui.log` / `xcodebuild-ui-2.log`；`AGENTS.md` 落「测试稳定性约定（iOS UI 腿）」并由 `check-baseline.sh` 的 `ac-agents-test-stability` 防回归；`check-ios-scripts.sh` 增加 `ui_call=2` / `xcodebuild-ui-2.log` / 「拆分≠放宽」断言；验证矩阵新增第 22 条接缝。
- 未复现 + 依据：本地同 `xcodebuild` 命令 4 次全 passed（13.869 / 14.283 / 14.137 / 14.486s，其中 2 次叠加 6 / 16 个忙循环人为负载），故按状态机判据加固而非改产品。
- 墙钟数据：CI run `43142574712` 单次 UI 调用 603s 顶到 600s 硬超时（用例合计 476.8s + 13 次 setup，第 13 条被杀）；分段后本地 6 条=205.111s、7 条=122.306s，两次调用 setup/Runner 重装/TCC 重申合计 ≈8.6s（腿 336s − 用例和 327.4s）——据此决定分段，`IOS_XCODEBUILD_TIMEOUT` 仍 600。
- 反例（实跑取红后已还原）：A 持久化失效（强制 `AnnouncementSettingsStore` 为 true）→ 红在「重启后应保持关闭状态」；B 页面就绪判据查不存在 id → 红在「重启后缺少每公里播报开关」，耗时 39.1s=3×10s，证明重试 ≤2 次且 timeout 未提高；C 仅破坏重启查询 → 探针 `RELAUNCH-PROBE persisted=0 probeToggleReady=true`（持久化正常，红属 tap/时序）。
- 未闭合项：`ac-authoritative-run-green` 尚待合入后新 commit 触发的权威 run 证据；本项按未闭合回执交付，阻塞点=需远端 run 结果，非本地可闭合。
- 零改动：`.github/workflows/ios.yml`、`.munk/code-gates.json`（22 门）、`ios/PurePace/**` 产品源码与 `shared/`；`code_gates` 22 门 attempt 002 全绿。
