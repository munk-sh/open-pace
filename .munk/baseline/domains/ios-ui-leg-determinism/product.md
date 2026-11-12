# Domain: ios-ui-leg-determinism

iOS UI 腿（`scripts/test-ios.sh` 的 UI 段）的**确定性与覆盖率契约**：导航/重启后的等待只认状态判据（Tab 栏存在 → 目标按钮 `exists && isHittable` → tap → 页面根/关键元素出现），断言期望只由 canonical 启动输入（`-uiTestLocation` / `-uiTestLocationTargetMeters`）锁定；单次 `xcodebuild` 调用硬上界仍 600s，15 条 UI 用例按目标拆成四次 `ui_call` 分段执行（runflow 6 / 取证+AX5+音频 7 / 截图浅色 1 / 截图深色 1），且 `ios/PurePaceUITests` 下每个 XCTestCase 套件都必须进入 `ui_call` 枚举（确需本机-only 者进 allowlist 且带非空理由）。**拆分≠放宽**：阈值、用例数、断言强度、重试策略与 `-only-testing` 覆盖范围都不减少。产品行为、80/16 与 96pt 阈值、identifier 冻结清单与 `.github/workflows/ios.yml` 零改动。同族「导航后 getElement 未出现」失败已 ≥2 次，故约定同时落 `AGENTS.md` 并由脚本断言防回归；`ScreenshotEvidenceUITests` 曾在 600s 分段改造后静默掉出权威腿（弱断言 `ui_call==2` 只数不点名），故改为「类名全覆盖枚举 + 反例自检」守卫。

## 范围

- `ios/PurePaceUITests/RunFlowUITests.swift`：重启段（`testAnnouncementTogglePersistsAcrossRelaunch`）与 `enableAnnouncements` 统一走 `private func tapSettingsUntilReady(_:screen:waitAfterTap:)`——Tab 栏 30s → `设置` `exists && isHittable` 10s → tap → `settings.announcementToggle` 出现 10s 视为页面就绪；未就绪再 tap ≤2 次（单次等待仍 10s）。失败路径打印 `NAV-GATE screen/stage/attempt`、写可及树/截图，并调用只读诊断 `private func attachPersistedAnnouncementProbe`（`-screenshotInitialTab settings` 直落设置页读持久化值，打印 `RELAUNCH-PROBE`），只用于归因、不参与断言判据。
- `scripts/test-ios.sh`：UI 腿由单次调用改为 `ui_call "<group>" "<log>" <targets...>` 四段——`runflow` = `PurePaceUITests/RunFlowUITests`，`evidence` = `EvidenceCaptureUITests` + `Ax5ScrollAuditCounterexampleTests` + `MusicSourceSelfCheckUITests`，`screenshot-light` / `screenshot-dark` = `ScreenshotEvidenceUITests/testEvidenceScreensLight` / `testEvidenceScreensDark`；每段独立 `ios_leg_budget(min(600, attempt 剩余))` 看门狗、独立日志 `xcodebuild-ui.log` / `-2` / `-3` / `-4`，段前各自重装 Runner 并重申 `simctl privacy location / location-always`；深色段前 `xcrun simctl ui "$sim_udid" appearance dark`、段后无条件恢复 `light`（失败路径不被失败即停短路跳过）；任一段失败即停并保留原始退出码（不掩盖为成功）。
- `scripts/ios-ui-local-only-suites.txt`：本机-only 套件 allowlist。文件不存在 / 仅注释 / 仅空行 = 空 allowlist（正常通过）；每条有效套件名必须同行或紧随带非空理由（`SuiteName | 理由` 或 `SuiteName # 理由`），缺套件名或缺理由即判红。
- `AGENTS.md`：新增「测试稳定性约定（iOS UI 腿）」三条——(a) 禁止墙钟依赖断言；(b) 导航/重启后必须状态判据（禁固定 `sleep`，重试 ≤2 次）；(c) 单次 `xcodebuild` ≤600s 下的四段套件执行约定、「拆分≠放宽」与「新增 *UITests 套件必须进入 `ui_call` 枚举，否则进 allowlist 且带理由」。
- `scripts/check-baseline.sh`：新增 `ac-agents-test-stability` 断言，`测试稳定性约定` 节必须同时含 `禁止墙钟依赖断言`、`状态判据`、`isHittable`、`sleep`、`≤600`、`拆分≠放宽`、`continue-on-error`。
- `scripts/check-ios-scripts.sh`：UI 顺序锚点取 `ui_call "runflow"` → `"evidence"` → `"screenshot-light"` → `"screenshot-dark"` 的行号；`ui_call` 调用数必须为 4；分文件日志断言含 `xcodebuild-unit.log` / `xcodebuild-ui.log` / `-2` / `-3` / `-4`；断言「拆分≠放宽」说明存在、深色段前有 `appearance dark` 且段后有 `appearance light` 恢复行、每段前有 `ui_status==0` 失败即停门控、每段一次 `xcodebuild` 且预算 ≤600s；覆盖守卫（`ac-ui-suite-coverage-guard` / `ac-ui-coverage-guard-counterexample` / `ac-ui-allowlist-requires-reason`）枚举 `ios/PurePaceUITests/*.swift` 的 `class …: XCTestCase` 套件并逐个确认出现在 `ui_call` 引号目标里（不认用法说明里的同名字样），缺任意一个即判红并点名；顺序反转/漏枚举/无理由 allowlist 均用 `mktemp` 沙箱样本注入。
- `docs/verification-matrix.md` 与 `DocsVerificationMatrixTests`：接缝现为 **23** 条——在「iOS UI 腿确定性（重启导航状态判据 + 600s 单腿预算）」行之后追加「UI 权威腿覆盖率守卫（新增 *UITests 必须入枚举 + ScreenshotEvidenceUITests 进 CI）」行（含接缝 × 现状 × 断言名 × 反例 × 证据路径 × 归属），结构守护测试期望 22 → 23，该行必须含「本项实测」与归属 `wi_intake_6bb510b0c105d362`。
- 与 `domains/ios-ci-budget` 的边界：预算/看门狗记账语义仍以该域为准；本域只承接「UI 腿为何分段、分段如何不削弱断言」与 UI 用例的等待判据。与 `domains/ios-ci-stability` 的边界：该域仍是测试链路总契约（预热/锁/确定性定位源），冲突时以两域各自的 AC 域内为准，分段事实以本域为准。

## 验收

- ac-authoritative-run-green: 合入后新 commit 触发的 `ios.yml` 权威 run 中 `ios` job 全绿：unit 腿 0 失败、UI 腿 15 条用例（runflow 6 + evidence 7 + 截图浅/深 2）0 失败，`android` job 结论与合入前一致；回执附 run id + 绿日志片段。
- ac-no-local-only-closure: 闭合判据只认权威 run；仅本地绿不算闭合，未取得绿 run 时按「未闭合回执」交付并写明阻塞点。
- ac-repro-or-evidence: 本地用同一 `xcodebuild` 命令复跑（必要时叠加人为负载/慢速条件）必须二择一产证：复现则附失败时可及树/截图与命令原文；未复现则记录命令、条件、重复次数与结果，不得省略。
- ac-relaunch-state-gate: 重启后切设置页以状态判据就绪——先等 Tab 栏，再等 `设置` `exists && isHittable`，tap 后以 `settings.announcementToggle` 出现作为页面就绪判据；判据未满足允许**重试 tap ≤2 次**，不提高 timeout、不降低断言强度。
- ac-relaunch-toggle-value: 重启后 `settings.announcementToggle` 值仍必须为 `"0"`（保存态跨重启断言强度不变）。
- ac-no-fixed-sleep: 改动后 UI 测试源码不新增 `sleep(` / `Thread.sleep` / `usleep`；所有等待走 `waitForExistence` / 谓词轮询。
- ac-canonical-input-not-wallclock: 断言内容会随运行时长漂移的用例必须由 canonical 启动输入锁定；13 条 UI 用例中不存在「跑得久就改变断言期望」的输入条件。
- ac-red-proof-for-changed-assertions: 每条新增/改动的断言在同 commit 附「构造错误输入必红」反例，并在本地实跑证明红/绿两侧成立（反例代码不留仓）。
- ac-ui-leg-wallclock-measured: 产出既有 13 条 UI 用例 + 新增截图 2 条在同一 job 内的逐用例/逐段墙钟 + 段级 setup 开销实测数据（xcresult/log 时间戳），写入验证矩阵或证据文件。
- ac-split-not-relaxed: 若分段：每次 `xcodebuild` 调用各自 ≤600s 上界，`IOS_XCODEBUILD_TIMEOUT` 仍 600，无 `continue-on-error`，无腿被删，`-only-testing` 覆盖集合不减少；脚本注释与本域写明「拆分≠放宽」及触发决定的数据依据；若实测不需拆分则明确写「不拆分 + 数据依据」。
- ac-thresholds-frozen: `IOS_XCODEBUILD_TIMEOUT=600`、`-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540`、80/16、96pt 等既有数值不变。
- ac-identifiers-frozen: 不新增 accessibility identifier；`scripts/check-ios-shell.sh` 冻结标识清单与用例计数保持一致（确需新增时只增不改并同步清单与计数）。
- ac-shell-selftest-green: 若改动受管视图或 identifier，`bash scripts/check-ios-shell.sh --self-test` 全绿并同步用例计数。
- ac-agents-convention-landed: 仓库约定落盘（`AGENTS.md` 或 ios 子目录约定）含 (a) 禁止墙钟依赖断言、(b) 导航/重启后状态判据、(c) 单次 `xcodebuild` ≤600s 分段执行；并有脚本断言（`check-baseline.sh` / `check-ios-workflow.sh`）保证该文本存在防回归。
- ac-verification-matrix-updated: `docs/verification-matrix.md` 对应行更新，含接缝、断言名、反例、证据路径、归属项，且结构守护测试（固定表头 / 接缝计数 / 6 列非空）同步通过。
- ac-no-product-behavior-change: 不改 UI 视觉/布局/产品行为，不改产品地图修复与保存态 canonical 逻辑。
- ac-gates-green: 本地 `.munk/code-gates.json` 中 `lint-ios-*` / `test-ios`（`--unit-only`）/ `build-ios` / `check-gpx-export` / `test`（baseline）全绿，门数仍 22。
- ac-ui-suite-coverage-guard: `scripts/check-ios-scripts.sh` 枚举 `ios/PurePaceUITests/*UITests.swift` 中声明的全部 `XCTestCase` 套件类名，并逐个确认其出现在 `scripts/test-ios.sh` 的 `ui_call` 目标（`PurePaceUITests/<Suite>` 形式）里；缺任意一个即非零退出并打印缺失套件名。判定只依赖仓库内文件内容，不需构建或跑模拟器。
- ac-ui-coverage-guard-counterexample: 该门自带反例自检——沙箱副本删掉某个已入枚举套件的 `ui_call` 目标后必须判红（含该套件名），未删时判绿（证明守卫不是恒真断言）。
- ac-ui-allowlist-requires-reason: `scripts/ios-ui-local-only-suites.txt` 为唯一 allowlist；文件不存在或只有注释/空行视为空 allowlist 且正常通过；每个非注释行必须有有效套件名且同行或紧随带非空理由，缺任一即判红；反例自检写入一条无理由条目必须判红。
- ac-screenshot-evidence-in-ci-leg: `scripts/test-ios.sh` 的 `ui_call` 段数为 4，一段目标含 `PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensLight`、另一段含 `testEvidenceScreensDark`；两段各自独立日志、各自一次 `xcodebuild`、各自受 `IOS_XCODEBUILD_TIMEOUT`(≤600) 看门狗约束；无 `continue-on-error`，既有段与预算参数值不变。
- ac-dark-appearance-gated: 深色段 `xcodebuild` 调用前存在 `xcrun simctl ui <udid> appearance dark`，段后（成功与失败路径均）恢复 `light`；恢复动作不得被失败即停短路跳过。证据：脚本结构断言 + 本地实跑日志中该段确在 dark 下执行且段后 `appearance` 查询为 `light`。
- ac-ui-legs-fail-fast-order: 4 段按固定顺序执行（runflow → evidence → screenshot-light → screenshot-dark），任一段失败即停止后续段并保留原始非零退出码；既有结构断言（每段一次 xcodebuild、每段 ≤600s、顺序门控、失败即停）仍由 `scripts/check-ios-scripts.sh` 校验，注入违规样本必须判红。
- ac-screenshot-evidence-counters: `scripts/check-ios-shell.sh` 新增 `ScreenshotEvidenceUITests` 计数断言——用例数恰为 2、`grep -c 'XCTAssert'` ≥24；各配一个反例自检（沙箱删 `func testEvidenceScreensDark` 或删全部 `XCTAssert` 行后必须判红，反例只改沙箱副本）。
- ac-local-verification-green: 本地 `bash scripts/check-ios-shell.sh --self-test`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-shell-expansion.sh` 全部退出 0；`.munk/code-gates.json` 仍 22 门且全绿；一次性 `bash scripts/test-ios.sh` 跑齐 4 段 UI 并留存各段日志与 `Executed N tests` 摘要。
- ac-no-production-change: `ios/PurePace/**` 无任何生产视图、identifier 或行为改动（`git diff --name-only` 不含 `ios/PurePace/`）。

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
- 分段纪律：四段调用共用同一组预算参数模板与 `-only-testing` 集合派生逻辑，各自过 `run_with_watchdog` 且预算取 `min(600, attempt 剩余)`；段超时仍走 `ios_timeout_classification_message`（段日志有 failed 用例 → 产品用例失败；无 failed 才归口承载层）。外观切换只由 `screenshot-light` / `screenshot-dark` 两段持有，dark 退出走无条件恢复。
- 静态门可观测：顺序锚点 install < privacy < 单测 < UI（`ui_call "runflow"` 行）；`ui_call` 恰 4 次且行号递增；`xcodebuild-ui-2.log` / `-3` / `-4` 必须出现在脚本中；`ui_call` 引号目标必须覆盖 allowlist 之外的全部 `PurePaceUITests` 套件；macOS bash 3.2 变量展开一律带 `${}`。
- 证据口径：本地复跑与墙钟数据落 `.munk/logs/**`（`ci-run-43142574712.log`、`test-ios-split-local.log`、`test-ios-4legs.log`、`relaunch/load-*.log`、`.build/logs/test-ios-timing.log`），矩阵行只引用真实文件，禁编造。

## 最近交付证明

- workItemId: wi_intake_6bb510b0c105d362（2026-11-12）
- 交付：`scripts/check-ios-scripts.sh` 把 `ui_call==2` 弱断言换成「`ios/PurePaceUITests` 全部 `XCTestCase` 套件必须出现在 `ui_call` 引号目标」的全覆盖守卫（`ac-ui-suite-coverage-guard` + `ac-ui-coverage-guard-counterexample` + `ac-ui-allowlist-requires-reason`），并扩到 4 段顺序/失败即停/深色外观切换/分文件日志断言；`scripts/test-ios.sh` UI 腿扩为 4 段（runflow → evidence → screenshot-light → screenshot-dark，日志 `xcodebuild-ui{,2,3,4}.log`），深色段前后 `appearance dark` / 无条件 `light`；新增 `scripts/ios-ui-local-only-suites.txt`（当前空 allowlist）；`scripts/check-ios-shell.sh` 加 `ScreenshotEvidenceUITests` 计数断言（用例恰 2、`XCTAssert` ≥24）+ 2 个沙箱反例；`AGENTS.md` 改四段口径并加「新增 *UITests 必须入枚举/allowlist」约定；验证矩阵新增第 23 条接缝「UI 权威腿覆盖率守卫」。
- 实跑（`.munk/logs/test-ios-4legs.log` + `.build/logs/xcodebuild-ui*.log`）：四段 `Executed 6 / 7 / 1 / 1 tests, 0 failures`，耗时 204.679 / 123.594 / 79.236 / 78.873s；分段 4 前打印「外观：dark（前）」、段后「外观恢复：light」，确证 dark 门控与无条件恢复生效。
- 反例（沙箱副本，未改生产文件）：删 `RunFlowUITests` 的 `ui_call` 目标 → 守卫点名判红（未删时判绿）；allowlist 写无理由条目 → 判红（缺失/仅注释 → 判绿）；删 `appearance light` 恢复行 → 判红；删最后一段 `ui_status==0` 门控 → 判红；删 `func testEvidenceScreensDark` 或删全部 `XCTAssert` → `check-ios-shell` 计数判红。
- 零改动：`ios/PurePace/**` 生产源码、`.github/workflows/ios.yml` trigger/步骤结构、预算参数（`IOS_XCODEBUILD_TIMEOUT` 仍 600）、Android/Shared；`.munk/code-gates.json` 仍 22 门且 attempt 001 全绿。
- 顺带：`.DS_Store` / `.munk/.DS_Store` 移出索引、`.gitignore` 加 `.DS_Store`，为单独 chore commit。未闭合项：`ac-authoritative-run-green` 待合入后新 commit 触发的权威 run 证据。
