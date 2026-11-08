# 修复 main 上 iOS CI 真实定位 UI 用例红，恢复真绿（不降门禁、不删断言）

## 范围

- 目标 HEAD `26e68759e9f7029e84abaa0eb9f1c988e8258d96` 上 ios workflow run `42529526542` = completed/failure，android run `42529526614` = success。修到同一个 workflow 真实 `conclusion=success`。
- **A. 根因落盘（带证据，不许猜）**：在 hosted runner 上查清为何 `xcrun simctl location start --speed=3 --interval=1` 注入 exit 0 但 App 侧 60s 内 0 个真实定位样本，而本机干净模拟器 2 连绿。至少各验一次并留原始日志：
  - (i) 改用每秒一次 `xcrun simctl location set <lat>,<lon>` 直线推进循环，验证 App 是否收到样本；
  - (ii) App 侧 CoreLocation 授权/样本回调的实际诊断日志（授权 status 是否 denied/restricted/authorized、是否收到 samples、是否被 TCC 或 LocationServices 拦截），并让其在 xcresult / 脚本日志中可查；
  - (iii) 注入后加首样本探针：≤10s 无样本即快速失败并打印诊断，不再静默等 60s。
- **B. 修法优先级（按顺序，允许证据支持时选后者）**：
  - (1) 首选：用确定性注入把 CI 拉绿——每秒 `simctl location set` 直线推进 + 首样本探针 + 必要的模拟器预热/重装顺序修正；保留真实 CoreLocation 链路与全部 UI 断言。
  - (2) 兜底（仅当证据证明 hosted runner 无法稳定投递真实定位）：CI 的 UI 用例改走 App test harness 启动参数喂确定性样本，断言 UI 串联（开跑→距离/配速变化→暂停冻结→恢复→结束→历史可见）；**同时保留**真实注入路径为必过本地门（`scripts/test-ios.sh` 本机模式 + 干净模拟器 2 连绿）与真机 QA 项；该拆分必须写进仓库 `AGENTS.md` 与脚本说明，措辞只准「CI 确定性 harness ≠ 真机/真实注入」。
- **C. 收敛最坏耗时**：用 `xcodebuild` 支持的测试超时/执行预算参数（`-test-timeouts-enabled` / `-default-test-execution-time-allowance` / `-maximum-test-execution-time-allowance` 或等价）把单次 attempt 的静默等待压到 ≤10 分钟；承载层有界重试上限保持 1 次，不扩到多次。
- **D. 反范围**：不改业务功能，不改 CoreLocation / AudioSession / 持久化契约（阶段冻结项），不新增 allowed-failure / continue-on-error，不删或弱化任何 UI 断言，不摘 job，不改签名与工程配置主路径，不引入跨端框架。
- 允许改动：`scripts/test-ios.sh`、`ios/PurePaceUITests/*`、`.github/workflows/ios.yml`、为保持结构门一致可**只加强**的 `scripts/check-ios-scripts.sh` / `scripts/check-ios-workflow.sh`、以及 DEBUG/test-only 的诊断日志；B(2) 所需 App test harness 注入 seam 若必须改产品源码，先回执 Owner 确认。

## 验收

- ac-sim-location-untouched: 在修复前记录当前 main HEAD `26e68759` 的失败证据并归档：run `42529526542` attempt1 的 `Timed out while loading Accessibility.`（时间跨度 22:22:26Z→22:49:48Z）、attempt2 `RunFlowUITests.swift:81` 的 `开始后 60s 内距离没有随真实定位样本从 0.00 km 变化`、以及 android run `42529526614` success；结论必须引用原始日志，不得只写摘要。
- ac-set-loop-injection: `scripts/test-ios.sh` 的注入改为每秒一次 `xcrun simctl location <udid> set <lat>,<lon>` 直线推进循环（≥2 个不同坐标、循环推进足以覆盖首样本），并在退出 trap 中清理注入；保留真实 CoreLocation 链路。
- ac-location-callback-diagnostics: App 侧 CoreLocation 回调有可查诊断：记录授权状态（notDetermined/denied/restricted/authorizedWhenInUse/authorizedAlways）与是否收到样本；诊断出现在 xcresult 或脚本日志中，且只在 test/DEBUG 路径，不改变产品运行行为与业务契约。
- ac-first-sample-probe: 注入后先做 ≤10s 的首样本探针；10s 内无样本即非零失败并打印 udid、注入坐标、授权状态、样本计数等诊断，不以 60s 静默等待作为唯一反馈。
- ac-real-chain-or-harness-split: 二选一且必须有证据支撑：① CI 仍走真实 CoreLocation 注入，`RunFlowUITests` 两条用例真实执行且全过、全部既有断言保留；或 ② 仅当证据证明 hosted runner 无法稳定投递真实定位时，CI UI 用例改走 harness 启动参数喂确定性样本，仍断言完整 UI 串联（开跑→距离/配速变化→暂停冻结→恢复→结束→历史恰 1 条且详情同源），并保留真实注入为本机必过门与真机 QA 项；`AGENTS.md` 与脚本说明写明「CI 确定性 harness ≠ 真机/真实注入」。
- ac-attempt-silent-wait-bounded: 单次 attempt 的静默等待硬上限 ≤600s；`xcodebuild test` 带 `-test-timeouts-enabled YES` 与显式 `-default-test-execution-time-allowance` / `-maximum-test-execution-time-allowance`（或等价），且 `scripts/test-ios.sh` 看门狗默认超时同步收到 ≤600s；AX 初始化超时不再吃 27 分钟。
- ac-bounded-retry-unchanged: 承载层有界重试仍最多 1 次，仅命中 AX/FrontBoard/runner bootstrap 特征时重试；产品级断言失败不重试；源码中不存在无界重试循环。
- ac-gates-not-weakened: 不新增 `-skip-testing` / `continue-on-error` / `allowed-failure`，不删或弱化任何 UI 断言，不摘 job；`scripts/check-ios-scripts.sh`、`scripts/check-ios-workflow.sh`、`scripts/check-ios-shell.sh` 与 `.munk/code-gates.json` 全部门退出 0；改 workflow/脚本后结构门只可加强，反例自检保留。
- ac-local-two-clean-runs: 本机 iPhone 16 / iOS 18.6 干净模拟器（先 `xcrun simctl shutdown` + `xcrun simctl erase`）连续 2 次 `bash scripts/test-ios.sh` 退出 0，两次日志均含 `testRunPauseResumeFinishAndHistory` passed、`testAnnouncementTogglePersistsAcrossRelaunch` passed 与 `** TEST SUCCEEDED **`；日志归档。
- ac-remote-ios-green: push 后 `gh run list --repo munk-sh/open-pace --workflow ios.yml` 取到真实 run：`conclusion=success` + 数字 run id 且日志含 `** TEST SUCCEEDED **`；同一 run 日志给出两个测试套件实际执行的用例数（基线 PurePaceTests 58、PurePaceUITests 2，若数量变化如实记录）。若为 failure/cancelled，附 run id 与失败步骤日志摘要继续修，不以本地绿替代远端 run。
- ac-android-no-regression: 交付 HEAD 上 `gh run list --repo munk-sh/open-pace --workflow android.yml` 取到真实 run 且 `conclusion=success`；本地 `bash scripts/build-android.sh`、`bash scripts/test-android.sh` 退出 0；`.github/workflows/android.yml` 不变。
- ac-evidence-archived: 根因（(i)(ii)(iii) 三类实际验证）、修法、两次本机 clean run 日志、远端 run id/conclusion/用例数归档到 `.munk/runs/run_intake_c3e9dcf5599c9324/`，并在 Delivery digest 中给出该路径。
- ac-honest-wording: 回执与文档只用「模拟器 + CI 链路」措辞；无 run id 支撑不得写「CI 已通过」，不得写「真机已验证」；B(2) 拆分只能写「CI 确定性 harness ≠ 真机/真实注入」。
- ac-no-product-change: 不改业务功能与 UI 行为，不改 `RunLocationSource` 的 CoreLocation 授权/采样策略、`AudioSession`、TTS、UserDefaults/存档契约与阶段冻结项；不动 `ios/project.yml` 等工程配置主路径（非必要不动）、不改签名、不引入跨端框架/第三方运行时依赖、不动 `VERSION`/`README`、不推 tag、不改 Release。

## 非目标

- 不改产品功能与业务逻辑；不重构 `RunCore` / 编排器 / 历史 / 导出契约。
- 不用固定 sleep 冒充成功、不伪造 `TEST SUCCEEDED`、不以本机绿替代远端 run。
- 不使用 `-skip-testing`、`continue-on-error`、`allowed-failure`，不删 job/步骤/断言换绿。
- 不做无界重试到绿；不扩承载层重试次数。
- 不动 Android 侧与 `shared/`；不改 `.github/workflows/android.yml`。
- 不推 tag、不改 Release、不做真机签名与分发。

## 实现约束

- 现状锚点（main HEAD `26e68759`）：
  - `scripts/test-ios.sh:167-174` `start_location_injection()` 目前用 `xcrun simctl location start --speed=3 --interval=1 37.3349,-122.0090 37.5200,-122.0090`；`prepare_simulator_for_ui_tests()` L124-165 顺序为 uninstall → xcodebuild build → install → privacy grant → launch/terminate 预热；看门狗默认 `IOS_XCODEBUILD_TIMEOUT=1800`（L85）。
  - `ios/PurePaceUITests/RunFlowUITests.swift:13` `firstSampleTimeout=60`；L81-84 首样本断言；L314-329 `waitForFirstSample` / L332-352 `dismissLocationAlertsIfPresent` / L355-377 `allowLocationIfNeeded`。
  - `ios/PurePace/Location/RunLocationSource.swift:66-70` `start()` 首次 `requestWhenInUseAuthorization()`；L79-90 `apply()` 按授权启停；L92+ `deliver()` 精度过滤；当前无任何诊断日志。`ios/PurePace/Run/RunSessionViewModel.swift:153-160` 为 delegate 落点。
  - `.github/workflows/ios.yml:78-135` test 步骤 `timeout-minutes: 45`，有界重试特征 `infra_pattern` 与 `run_attempt 1/2`。
  - `scripts/check-ios-scripts.sh` 结构断言：`test-ios.sh` 含 `xcodebuild test`、`-scheme`、`iPhone 16` destination、`simctl bootstatus`、`simctl install`、`simctl privacy`、`grant location`、`simctl launch`、`simctl terminate`、`run_with_watchdog`，且 privacy 必须在 install 之后、xcodebuild test 之前；禁止 GNU `timeout`；含反例自检。`scripts/check-ios-workflow.sh` 断言单 job `macos-latest`、steps 顺序 install/lint/test/build、`timeout-minutes ≤45`、复用 `bash scripts/test-ios.sh`、workflow 内无第二套 `xcodebuild test/build`，含负向自检。改动后这些门必须仍退出 0，且只能加强。
- 已确认 `xcrun simctl location` 支持 `set <lat>,<lon>` 与 `start --speed --interval`；`xcodebuild` 支持 `-test-timeouts-enabled YES`、`-default-test-execution-time-allowance SECONDS`、`-maximum-test-execution-time-allowance SECONDS`（本机 Xcode 已核）。每秒 `set` 循环需后台进程 + trap 清理，且不得与 `start` 注入叠加。
- **B(2) 关键事实（必须知悉）**：现有 App harness 由 `ios/PurePace/Harness/HarnessArguments.swift` 的 `--harness direct|corelocation|resume` 驱动，但 `PurePaceApp.swift:7-12` 在有 `--harness` 时切换到 `HarnessRootView`（`Color.clear` 无业务 UI），并不驱动主 Run/History UI；`ContentView.swift:27-31` 硬编码 `locationSource: RunLocationSource()`。因此「App 已有 test harness 启动参数喂确定性样本」目前并不存在可用的主 UI 注入通路。若证据迫使走 B(2)，Coding 必须先回执 Owner 说明需新增 test-only/DEBUG 注入 seam（预计触及 `ContentView`/`PurePaceApp`），确认后再改；不得擅自扩大产品源码改动范围。
- 远端 macOS = bash 3.2：参数展开一律 `${var}`；不得依赖 GNU `timeout`，用 bash 看门狗 + `kill`；模拟器固定 `iPhone 16` / `iOS 18.6`，bundle `com.chaxiu.purepace`，UI runner `com.chaxiu.purepace.uitests.xctrunner`。
- 证据落点统一 `.munk/runs/run_intake_c3e9dcf5599c9324/`；不得写入仓库产品文件冒充证据。
- 本项为显式规格直派（bugfix 快速通道）：Intake → Coding → code_gates → Delivery；`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 false。
