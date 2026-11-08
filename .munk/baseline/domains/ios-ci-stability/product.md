# Domain: ios-ci-stability

PurePace iOS 测试链路稳定性域：让 `bash scripts/test-ios.sh` 在**全新 macOS runner + 全新 iOS 18.6 模拟器**上可重复跑绿——把模拟器前置状态（boot 就绪、空容器、已安装 bundle 的定位授权、启动预热）显式编入脚本，用**每秒一次 `simctl location set` 直线推进**做确定性真实定位注入，用**≤10s 首样本探针** fail-fast 并落诊断，用进程级看门狗 + `xcodebuild` 测试预算把单次 attempt 静默等待压到 ≤600s，只对 GitHub 承载层不稳定做**最多 1 次**有界重试。不放宽任何既有断言或门禁；不改业务功能、不改 `RunLocationSource` 授权/采样策略（仅允许 `#if targetEnvironment(simulator)` 的诊断日志）。

## 范围

- `scripts/test-ios.sh`：固定顺序 `simctl bootstatus <udid> -b` → `simctl uninstall`（清容器与 TCC）→ `xcodebuild build` + `simctl install` → `simctl privacy <udid> grant location com.chaxiu.purepace` → `simctl launch` + `terminate` 预热 → 首帧 `simctl location <udid> set <lat>,<lon>` + 后台每秒推进循环（trap 内 `kill` + `location clear` 清理）→ `xcodebuild test`（带 `-test-timeouts-enabled YES` / allowance + ≤600s 看门狗）→ 回读 App 沙盒 `Documents/location-diagnostics.log` 打印到脚本日志；每个阶段失败时非零退出并打印设备 udid 与阶段名。保留 `blocked:` 降级分支语义（工程不可用显式 `blocked:` + 真实 `swift test`）。
- `ios/PurePaceUITests/RunFlowUITests.swift`：点击 `run.start` 后先做 ≤10s 首样本探针——距离未离开 `0.00 km` 即非零失败并 `attachLocationDiagnostics`（把 distance/elapsed、弹窗状态、诊断文件落进 xcresult），再无样本才进入原有距离/时长断言；探针期间继续兜授权弹窗；既有断言一条不减。
- `ios/PurePace/Location/RunLocationSource.swift`：仅在 `#if targetEnvironment(simulator)` 下新增诊断（授权状态 + 样本计数 + 精度过滤计数），不改授权请求、采样策略、精度阈值与 `RunSample` 契约。
- `.github/workflows/ios.yml`：`test` 步 `timeout-minutes: 45` 硬上限；仅当输出命中承载层特征（Accessibility/AX 初始化超时、`unknown to FrontBoard`、runner bootstrap 崩溃、`runner bootstrap 挂起`）时重置模拟器后有界重试 1 次；两次完整日志与首次失败原因都保留在日志中；`blocked:` 仍判失败。
- 结构门同步（只可加强）：`scripts/check-ios-scripts.sh` 断言 `set` 循环注入、`start` 不残留、三个 `xcodebuild` 测试预算参数、看门狗 ≤600s 与授权时序；`scripts/check-ios-workflow.sh` 断言 `timeout-minutes`、有界重试特征串（含负向自检）与「未放宽门禁」。
- 证据落点：`.munk/runs/<runId>/`（修复前失败原始日志、`root-cause.md`、`fix.md`、本机 clean run 日志、首样本 fail-fast 实证、远端 run id 与 conclusion）；不写入仓库产品文件冒充证据。

## 验收

- ac-clean-sim-repro-evidence: 对 iPhone 16 / iOS 18.6 执行 `xcrun simctl shutdown <udid>` + `xcrun simctl erase <udid>` 后跑一次 `bash scripts/test-ios.sh`，把完整命令、退出码、失败用例名与失败断言原文（或当次为绿的真实结果）存到 `.munk/runs/<runId>/`；复现结论必须基于该日志，不得只写摘要或编造失败。
- ac-root-cause-recorded: 证据目录内写明三类现象的实际触发条件与判定依据（首次定位授权/TCC 未预置、`Failed to initialize for UI testing: Timed out while loading Accessibility.`、`Simulator device failed to launch ... unknown to FrontBoard`），并区分「产品/脚本可修」与「GitHub 承载层不稳」。
- ac-sim-location-untouched: 修复前先把 main HEAD 的失败证据归档到 `.munk/runs/<runId>/raw/`：ios run attempt1 的 `Timed out while loading Accessibility.`、attempt2 的 `RunFlowUITests.swift:81` 首样本 60s 未变化、同 HEAD 的 android run success；结论必须引用原始日志片段，不得只写摘要。
- ac-sim-privacy-granted: `scripts/test-ios.sh` 在测试前先 `simctl uninstall` 清容器 → 构建并安装 App → 对已安装 bundle 执行 `simctl privacy <udid> grant location com.chaxiu.purepace` → 注入定位；授权命令出现在安装之后、`xcodebuild test` 之前（顺序可被脚本源码断言）。
- ac-set-loop-injection: 注入改为先一次 `simctl location <udid> set <lat>,<lon>`，再后台每秒一次 `set` 沿直线推进（≥2 个不同坐标、纬度步进足以覆盖首样本、循环有界）；退出 trap 内停止后台循环并 `simctl location clear`；不再使用 `simctl location start`，保留真实 CoreLocation 链路（模拟器定位服务 → `RunLocationSource` → 编排器）。
- ac-location-callback-diagnostics: 模拟器下记录 CoreLocation 授权状态（notDetermined/denied/restricted/authorizedWhenInUse/authorizedAlways）与样本/过滤计数，写入 App 沙盒 `Documents/location-diagnostics.log`，由脚本回读进 xcresult 或脚本日志；仅 `#if targetEnvironment(simulator)` 的 test/DEBUG 路径，不改变真机行为与业务契约。
- ac-first-sample-probe: 注入后先做 ≤10s 首样本探针；10s 内无样本即非零失败，打印 udid、注入坐标、授权状态、样本计数（并 `XCTAttachment` 落 xcresult），不以 60s 静默等待作为唯一反馈；不把固定 sleep 当成功判据，不使用 launch-arg 假流、内置样例坐标或假计时。
- ac-existing-ui-assertions-kept: `RunFlowUITests` 既有断言一条不减：距离随注入变化、暂停冻结距离与时长、恢复后继续增长、结束后 History 恰 1 条、详情与列表同源、分段行数一致、GPX 导出完成态、系统分享面板出现、播报开关翻转并跨重启保持关闭。
- ac-real-chain-or-harness-split: 二选一且必须有证据支撑：① CI 仍走真实 CoreLocation 注入，`RunFlowUITests` 两条用例真实执行且全过、全部既有断言保留；或 ② 仅当证据证明 hosted runner 无法稳定投递真实定位时，CI UI 用例改走 harness 启动参数喂确定性样本，仍断言完整 UI 串联（开跑→距离/配速变化→暂停冻结→恢复→结束→历史恰 1 条且详情同源），并把真实注入保留为本机必过门与真机 QA 项；该拆分须写入 `AGENTS.md` 与脚本说明，措辞只准「CI 确定性 harness ≠ 真机/真实注入」。
- ac-boot-warmup: 脚本在 `simctl bootstatus <udid> -b` 通过后才继续；随后完成一次安装/启动预热（例如构建安装后 `simctl launch` + `terminate`），boot 失败或预热失败时非零退出并打印设备 udid 与阶段，不静默跳过、不降级为通过。
- ac-attempt-silent-wait-bounded: 单次 attempt 静默等待硬上限 ≤600s：脚本看门狗默认超时收到 ≤600s，`xcodebuild test` 带 `-test-timeouts-enabled YES` 与显式 `-default-test-execution-time-allowance` / `-maximum-test-execution-time-allowance`（或等价）；超时非零退出并打印「未进入产品断言」与已执行测试摘要；AX 初始化超时不再吃 27 分钟级时间。
- ac-bounded-retry-unchanged: `test` 步仍最多 1 次重试（`run_attempt 1` + 至多 `run_attempt 2`），仅命中承载层特征（Accessibility/AX 初始化超时、`unknown to FrontBoard`、runner bootstrap 崩溃、`runner bootstrap 挂起`）才重试；产品级断言失败不重试；源码中不存在无界重试循环。
- ac-two-consecutive-clean-runs: 干净 iOS 18.6 模拟器上连续 2 次 `bash scripts/test-ios.sh` 均退出 0，两次日志都包含 `Test Case '-[PurePaceUITests.RunFlowUITests testRunPauseResumeFinishAndHistory]' passed`、`testAnnouncementTogglePersistsAcrossRelaunch` passed 与 `** TEST SUCCEEDED **`（非仅 PurePaceTests）。
- ac-gates-not-weakened: 不新增 `-skip-testing`、`continue-on-error`、`allowed-failure`、不删 job/步骤/断言；`bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-workflow.sh`、`bash scripts/check-ios-shell.sh` 与 `.munk/code-gates.json` 全部门退出 0；改 workflow/脚本后结构门只可加强且保留反例自检。
- ac-remote-ios-green: 交付 push 后 `gh run list --repo munk-sh/open-pace --workflow ios.yml` 取到真实 run：`conclusion=success`、带数字 run id，日志含 `** TEST SUCCEEDED **`，并给出两套件实际执行用例数（基线 PurePaceTests 58 / PurePaceUITests 2，变化如实记录）；若为 `failure`/`cancelled`，本项不交付，附失败 run id 与失败步骤日志摘要后继续修，不以本地绿替代远端 run。
- ac-android-no-regression: `bash scripts/test-android.sh` 与 `bash scripts/build-android.sh` 退出 0，`.github/workflows/android.yml` 不变，交付 HEAD 上 android run 为 `success`。
- ac-evidence-archived: 根因三类验证（注入方式对比、App 侧回调诊断、首样本探针）、修法、两次本机 clean run 日志、远端 run id/conclusion/用例数归档到 `.munk/runs/<runId>/`，并在 Delivery digest 中给出该路径。
- ac-no-product-change: 不改业务功能与 UI 行为，不改 `RunLocationSource` 的授权请求/采样策略/精度过滤、`AudioSession`、TTS、UserDefaults/存档契约与阶段冻结项；除 `#if targetEnvironment(simulator)` 诊断日志外不新增产品源码改动（B(2) 所需 harness seam 须先回执 Owner）；不动 `ios/project.yml` 主路径/签名、不改 `VERSION`/`README`、不推 tag、不改 Release、不引入跨端框架或第三方运行时依赖。
- ac-honest-wording: 回执与文档只用「模拟器 + CI 链路」措辞；无 run id 支撑不得写「CI 已通过」，不得写「真机已验证」；B(2) 拆分只能写「CI 确定性 harness ≠ 真机/真实注入」。

## 非目标

- 不改产品功能与 UI 行为，不改 `RunLocationSource` 的 CoreLocation 授权/采样策略与精度过滤，不改 AudioSession、TTS、UserDefaults 持久化契约与阶段冻结项（允许的例外仅限 `#if targetEnvironment(simulator)` 诊断日志）。
- 不用 launch-arg 假流、内置样例坐标、固定 sleep 替代真实 CoreLocation；不删/弱化任何现有 UI 断言；不以本机绿替代远端 run。
- 不使用 `-skip-testing`、`continue-on-error`、`allowed-failure`、不摘 job/步骤换绿；不做无限重试到绿，不扩承载层重试次数。
- 不动 `VERSION`/`README`、不引入第三方框架（含 fastlane / actionlint 等新工具）、不推 tag、不改 Release、不做真机签名与分发。
- 不重构 Android 侧、不改 `.github/workflows/android.yml`、不改 `shared/`。

## 实现约束

- 失败三类原文（Owner 一手核对，main 自真实 CoreLocation UI 用例进 CI 起多连红）：①`开始后距离没有随真实定位样本从 0.00 km 变化`；②`翻转后开关应关闭`；③`Timed out while loading Accessibility.` / `Simulator device failed to launch ... unknown to FrontBoard`。
- 承载层措辞随 Xcode/runner 版本漂移（实测教训）：同族不稳定在 runner 上也会打印 `Failed to initialize for UI testing:` + `Timed out waiting for AX loaded notification`、`Early unexpected exit, operation never finished bootstrapping`（`Test crashed with signal abrt while preparing to run tests`），以及 600s 看门狗打印的 `runner bootstrap 挂起`。重试判定必须覆盖这些措辞，否则真挂死时不会触发那唯一一次重试；判定串只放承载层特征，禁止混入产品断言措辞（`check-ios-workflow.sh` 有负向自测锁死）。
- `simctl location start --speed --interval` 在 hosted runner 上 exit 0 却不投递样本（见 `.munk/runs/<runId>/root-cause.md`）：注入一律用每秒 `simctl location <udid> set` 直线推进，后台循环必须有界（约 1200 次）并由 trap `kill` + `location clear` 清理，不得与 `start` 叠加。
- 关键锚点：`scripts/test-ios.sh` 的 `wait_for_simulator_boot()` / `prepare_simulator_for_ui_tests()` / `start_location_injection()` / `dump_location_diagnostics()` / `run_with_watchdog()` / `test_with_xcodebuild()`；`RunFlowUITests` 的 `allowLocationIfNeeded()`、`dismissLocationAlertsIfPresent()`、`attachLocationDiagnostics()`、`firstSampleProbeTimeout=10`；`.github/workflows/ios.yml` test 步的 `run_attempt` / `infra_unstable` / `reset_simulator`；`RunLocationSource` 的 `RunLocationDiagnostics`（simulator-only）。
- `simctl privacy` 只对已安装 bundle 生效，而 `simctl uninstall` 会清掉该 bundle 的 TCC 状态；顺序铁律「卸载清容器 → 安装 → grant location → 注入定位 → `xcodebuild test`」，不得授权后再 uninstall。**runner 实测补充**：`xcodebuild test` 会用自己构建的产物再安装一次 App，脚本预置的 TCC 可能在测试开始时已失效、授权弹窗出现在点击 `run.start` 之后；UI 用例必须自己在首样本探针循环里处理弹窗，不能只依赖启动时的一次兜底。
- 硬超时用 bash 子进程看门狗（`kill -0` 轮询 → `TERM` → `KILL` → `124`），禁止依赖 GNU `timeout`；默认 600s（≤600s 硬上限），可用 `IOS_XCODEBUILD_TIMEOUT` 覆盖；`xcodebuild test` 同时带 `-test-timeouts-enabled YES`、`-default-test-execution-time-allowance 300`、`-maximum-test-execution-time-allowance 540`；`build` 步仍走 `scripts/build-ios.sh`。
- 远端 shell 为 macOS bash 3.2：参数展开一律 `${var}`，禁止 `$var` 紧邻全角字符（否则 `unbound variable`）；坐标整数化推进用 `lat_micro` 微度整数运算避免浮点误差。
- 固定字面量不得为适配 runner 删除：`iPhone 16` / `iOS 18.6`、`com.chaxiu.purepace`、`com.chaxiu.purepace.uitests.xctrunner`、`-destination 'platform=iOS Simulator,name=iPhone 16'`。
- 结构门只可加强：`check-ios-scripts.sh` 仍断言 `xcodebuild test` / `-scheme` / iPhone 16 destination / 严格模式 / `BASH_SOURCE` / `--help` / 未知参数退出 2，并新增 `location "$sim_udid" set`、禁止 `location "$sim_udid" start`、三个测试预算参数、看门狗 ≤600s 断言与反例自检；`check-ios-workflow.sh` 仍断言单 job `runs-on: macos-latest`、steps 顺序 install/lint/test/build、install 含 xcodegen + iPhone 16 + iOS 18.6 + `simctl create` + `downloadPlatform iOS`、test 步复用 `bash scripts/test-ios.sh` 且对 `blocked:` `exit 1`、workflow 内无第二套 `xcodebuild test/build`。
- 本项为显式规格直派（bugfix 快速通道）：Intake → Coding → code_gates → Delivery；`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 false；若根因必须改产品源码，先回执 Owner 确认，不得自行扩围。

## 最近交付证明

- workItemId: wi_intake_c3e9dcf5599c9324（2026-11-09，pass）
- 修复前归因（main@26e68759）：ios run 42529526542 attempt1 `Timed out while loading Accessibility.`、attempt2 UI 用例 60s 首样本无变化；android run 42529526614 success；原始日志与 `root-cause.md` 在 `.munk/runs/run_intake_c3e9dcf5599c9324/raw/`。
- 交付：`scripts/test-ios.sh` 注入改为每帧同步 `simctl location set` + 后台每秒直线推进（trap 清理），新增 `dump_location_diagnostics()` 回读 App 沙盒诊断，看门狗 1800s→600s 并给 `xcodebuild test` 加 `-test-timeouts-enabled YES` / `-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540`；`RunFlowUITests` 首样本等待 60s→10s 探针 + `XCTAttachment` 诊断，既有断言全保留；`RunLocationSource` 仅 simulator 分支新增授权/样本/过滤计数诊断日志；`ios.yml` `infra_pattern` 补 `runner bootstrap 挂起`（重试上限仍 1）；`check-ios-scripts.sh` / `check-ios-workflow.sh` 同步加强并有反例自检。
- 验证：`.munk/runs/run_intake_c3e9dcf5599c9324/local/clean-run-1.log` / `clean-run-2.log`（`simctl erase` 后连续 2 次 `EXIT=0`，两条 UI 用例 passed，PurePaceTests 58 / PurePaceUITests 2 executed，`** TEST SUCCEEDED **`）；`local/probe-fail-fast.log` 证明无注入时 10s 内即失败并落附件；三个结构门全 PASS。
- 远端：本 worktree 交付 push 后取真实 ios run（`conclusion=success` + `** TEST SUCCEEDED **`）补齐；未取到前保持 `pending: 待 remote 验证`，不以本机绿替代。
