# Domain: ios-ci-stability

PurePace iOS 测试链路稳定性域：让 `bash scripts/test-ios.sh` 在**全新 macOS runner + 全新 iOS 18.6 模拟器**上可重复跑绿——把模拟器前置状态（boot 就绪、空容器、已安装 bundle 的定位授权、启动预热）显式编入脚本，给 `xcodebuild test` 加进程级硬超时，只对 GitHub 承载层不稳定做**最多 1 次**有界重试，并让 UI 用例先等首个真实定位样本再断言。不放宽任何既有断言或门禁；不改产品源码与 RunLocationSource 授权/采样策略。

## 范围

- `scripts/test-ios.sh`：固定顺序 `simctl bootstatus <udid> -b` → `simctl uninstall`（清容器与 TCC）→ `xcodebuild build` + `simctl install` → `simctl privacy <udid> grant location com.chaxiu.purepace` → `simctl launch` + `terminate` 预热 → `simctl location start --speed=3 --interval=1` 注入 → 带看门狗硬超时的 `xcodebuild test`；每个阶段失败时非零退出并打印设备 udid 与阶段名。保留 `blocked:` 降级分支语义（工程不可用显式 `blocked:` + 真实 `swift test`）。
- `ios/PurePaceUITests/RunFlowUITests.swift`：点击 `run.start` 后先有界等待（≤60s）真实定位样本使 `run.distance` 从 `0.00 km` 变化，再做距离/时长断言；授权兜底扩到 UIInterruptionMonitor + SpringBoard 弹窗统一文案表，并在冷启动弹窗吞掉首次点击时有界重试一次；既有断言一条不减。
- `.github/workflows/ios.yml`：`test` 步加 `timeout-minutes: 45` 硬上限；仅当输出命中 `Timed out while loading Accessibility.` 或 `unknown to FrontBoard` 时重置模拟器后有界重试 1 次；两次完整日志与首次失败原因都保留在日志中；`blocked:` 仍判失败。
- 结构门同步（只可加强）：`scripts/check-ios-scripts.sh` 新增 `test-ios.sh` 的授权时序/看门狗/阶段失败断言；`scripts/check-ios-workflow.sh` 新增 `timeout-minutes`、有界重试特征串与「未放宽门禁」断言。
- 证据落点：`.munk/runs/<runId>/`（干净模拟器复现日志、`root-cause.md`、连续两次通过日志、远端 run id 与 conclusion）；不写入仓库产品文件。

## 验收

- ac-clean-sim-repro-evidence: 对 iPhone 16 / iOS 18.6 执行 `xcrun simctl shutdown <udid>` + `xcrun simctl erase <udid>` 后跑一次 `bash scripts/test-ios.sh`，把完整命令、退出码、失败用例名与失败断言原文（或当次为绿的真实结果）存到 `.munk/runs/<runId>/`；复现结论必须基于该日志，不得只写摘要或编造失败。
- ac-root-cause-recorded: 证据目录内写明三类现象的实际触发条件与判定依据（首次定位授权/TCC 未预置、`Failed to initialize for UI testing: Timed out while loading Accessibility.`、`Simulator device failed to launch ... unknown to FrontBoard`），并区分「产品/脚本可修」与「GitHub 承载层不稳」。
- ac-sim-privacy-granted: `scripts/test-ios.sh` 在测试前先 `simctl uninstall` 清容器 → 构建并安装 App → 对已安装 bundle 执行 `simctl privacy <udid> grant location com.chaxiu.purepace` → `simctl location start` 注入；授权命令出现在安装之后、`xcodebuild test` 之前（顺序可被脚本源码断言）。
- ac-location-first-sample: UI 用例点击 `run.start` 后，先保持有界等待（≤60s）直到真实定位样本使 `run.distance` 从 `0.00 km` 变化，再做距离/时长断言；等待期间不把固定 sleep 当成功判据，不使用 launch-arg 假流、内置样例坐标或假计时。
- ac-existing-ui-assertions-kept: `RunFlowUITests` 既有断言一条不减：距离随注入变化、暂停冻结距离与时长、恢复后继续增长、结束后 History 恰 1 条、详情与列表同源、分段行数一致、GPX 导出完成态、系统分享面板出现、播报开关翻转并跨重启保持关闭。
- ac-boot-warmup: 脚本在 `simctl bootstatus <udid> -b` 通过后才继续；随后完成一次安装/启动预热（例如构建安装后 `simctl launch` + `terminate`），boot 失败或预热失败时非零退出并打印设备 udid 与阶段，不静默跳过、不降级为通过。
- ac-test-timeout: `xcodebuild test` 有硬超时（脚本内 watchdog 或等效进程级上限，macOS runner 不依赖 GNU `timeout`），超时后非零退出并打印超时阶段、已执行的测试摘要；`.github/workflows/ios.yml` 的 `test` 步骤设置 `timeout-minutes`（≤45），使 35 分钟级挂死必然失败而非无限等待。
- ac-bounded-retry: 仅当输出命中 `Timed out while loading Accessibility.` 或 `unknown to FrontBoard` 时允许 `test` 步骤最多 1 次重试，重试前重建/重置模拟器状态；两次完整日志与首次失败原因都保留在日志中；产品级断言失败（距离不变化、开关状态不符等）不重试；源码中不存在无界重试循环。
- ac-two-consecutive-clean-runs: 干净 iOS 18.6 模拟器上连续 2 次 `bash scripts/test-ios.sh` 均退出 0，两次日志都包含 `Test Case '-[PurePaceUITests.RunFlowUITests testRunPauseResumeFinishAndHistory]' passed`、`testAnnouncementTogglePersistsAcrossRelaunch` passed 与 `** TEST SUCCEEDED **`（非仅 PurePaceTests）。
- ac-gates-not-weakened: 不新增 `-skip-testing`、`continue-on-error`、`allowed-failure`、不删 job/步骤/断言；`bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-workflow.sh`、`bash scripts/check-ios-shell.sh` 与 `.munk/code-gates.json` 全部门退出 0。
- ac-remote-green-run: 交付 push 后 `gh run list --repo munk-sh/open-pace --workflow ios.yml` 取到真实 run：`conclusion=success`、带数字 run id，日志含 `** TEST SUCCEEDED **`；若为 `failure`/`cancelled`，本项不交付，附失败 run id 与失败步骤日志摘要后继续修，不以本地绿替代远端 run。
- ac-android-no-regression: `bash scripts/test-android.sh` 与 `bash scripts/build-android.sh` 退出 0，`.github/workflows/android.yml` 不变。
- ac-no-product-change: diff 只落在 `scripts/test-ios.sh`、`ios/PurePaceUITests/*`、`.github/workflows/ios.yml`（及必要的结构门断言同步）；不改产品源码/UI 行为/RunLocationSource 授权逻辑/Info.plist 权限用途/持久化/TTS 契约与阶段 2 冻结项，不动 `VERSION`/`README`，不引入第三方运行时依赖，不推 tag、不动 Release。
- ac-honest-wording: 若最终确认部分根因属 GitHub 承载层缺陷而非产品，回执必须附 run id 级原始日志证据，措辞限定「模拟器 + CI 链路」；不得出现无 run id 支撑的「CI 已通过」「真机已验证」。

## 非目标

- 不改产品功能与 UI 行为，不改 `RunLocationSource` 的 CoreLocation 授权/采样策略，不改 AudioSession、TTS、UserDefaults 持久化契约与阶段 2 冻结项。
- 不用 launch-arg 假流、内置样例坐标、固定 sleep 替代真实 CoreLocation；不删/弱化任何现有 UI 断言。
- 不使用 `-skip-testing`、`continue-on-error`、`allowed-failure`、不摘 job 换绿；不做无限重试到绿。
- 不动 `VERSION`/`README`、不引入第三方框架（含 fastlane / actionlint 等新工具）、不推 tag、不改 Release、不做真机签名与分发。
- 不重构 Android 侧、不改 `.github/workflows/android.yml`、不改 `shared/`。

## 实现约束

- 失败三类原文（Owner 一手核对，main 自真实 CoreLocation UI 用例进 CI 起 4 连红：42497785537 / 42501736365 / 42505929787 / 42508006469；run 42511873416 的 `test` 步 >35 分钟未结束）：①`开始后距离没有随真实定位变化`；②`翻转后开关应关闭`；③`Timed out while loading Accessibility.` / `Simulator device failed to launch ... unknown to FrontBoard`。
- 承载层措辞随 Xcode/runner 版本漂移（实测教训）：同族不稳定在 runner 上也会打印 `Failed to initialize for UI testing:` + `Timed out waiting for AX loaded notification`，以及 `PurePaceUITests-Runner ... Early unexpected exit, operation never finished bootstrapping`（`Test crashed with signal abrt while preparing to run tests`）。重试判定必须覆盖这些措辞（`Timed out while loading Accessibility.` / `unknown to FrontBoard` / `AX loaded notification` / `Failed to initialize for UI testing` / `operation never finished bootstrapping` / `while preparing to run tests`），否则真挂死时不会触发那唯一一次重试；判定串只放承载层特征，禁止混入产品断言措辞（`check-ios-workflow.sh` 有 `ac-test-bounded-retry-scope` 断言与负向自测）。
- 关键锚点：`scripts/test-ios.sh` 的 `wait_for_simulator_boot()` / `prepare_simulator_for_ui_tests()` / `start_location_injection()` / `run_with_watchdog()` / `test_with_xcodebuild()`；`RunFlowUITests` 的 `allowLocationIfNeeded()`、`waitUntil()`、`firstSampleTimeout`；`.github/workflows/ios.yml` test 步的 `run_attempt` / `infra_unstable` / `reset_simulator`。
- `simctl privacy` 只对已安装 bundle 生效，而 `simctl uninstall` 会清掉该 bundle 的 TCC 状态；顺序铁律「卸载清容器 → 安装 → grant location → 注入定位 → xcodebuild test」，不得授权后再 uninstall。**runner 实测补充**：`xcodebuild test` 会用自己构建的产物再安装一次 App，脚本预置的 TCC 可能在测试开始时已失效、授权弹窗出现在点击 `run.start` 之后；UI 用例必须自己在首个样本等待循环里处理弹窗，不能只依赖启动时的一次兜底。
- 硬超时用 bash 子进程看门狗（`kill -0` 轮询 → `TERM` → `KILL` → `124`），禁止依赖 GNU `timeout`；默认 1800s，可用 `IOS_XCODEBUILD_TIMEOUT` 覆盖，`build` 步仍走 `scripts/build-ios.sh`。
- 远端 shell 为 macOS bash 3.2：参数展开一律 `${var}`，禁止 `$var` 紧邻全角字符（否则 `unbound variable`）。
- 固定字面量不得为适配 runner 删除：`iPhone 16` / `iOS 18.6`、`com.chaxiu.purepace`、`com.chaxiu.purepace.uitests.xctrunner`、`-destination 'platform=iOS Simulator,name=iPhone 16'`。
- 结构门只可加强：`check-ios-scripts.sh` 仍断言 `xcodebuild test` / `-scheme` / iPhone 16 destination / 严格模式 / `BASH_SOURCE` / `--help` / 未知参数退出 2；`check-ios-workflow.sh` 仍断言单 job `runs-on: macos-latest`、steps 顺序 install/lint/test/build、install 含 xcodegen + iPhone 16 + iOS 18.6 + `simctl create` + `downloadPlatform iOS`、test 步复用 `bash scripts/test-ios.sh` 且对 `blocked:` `exit 1`、workflow 内无第二套 `xcodebuild test/build`。
- 本项为显式规格直派：Intake 后直接进 Coding，`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 false；若根因必须改产品源码，先回执 Owner 确认，不得自行扩围。

## 最近交付证明

- workItemId: wi_intake_7d441da43589e3e9（2026-11-09，pass）
- 交付：`scripts/test-ios.sh` 拆出 bootstatus 等待 / 安装后 `simctl privacy grant location` / 启动预热 / 进程级看门狗（默认 1800s，超时 124 并打印已执行测试摘要）阶段化链路；`RunFlowUITests` 增加「先等首个真实样本使距离离开 `0.00 km`（≤60s）」与冷启动弹窗有界兜底，既有断言全保留；`.github/workflows/ios.yml` test 步 `timeout-minutes: 45` + 仅承载层不稳定特征（Accessibility 超时 / `unknown to FrontBoard`）最多 1 次重试并保留两次日志；`check-ios-scripts.sh` / `check-ios-workflow.sh` 同步加强断言。
- 验证：`.munk/runs/run_intake_7d441da43589e3e9/` 存有四连红 CI 原始日志、`repro-clean-sim.log`、`root-cause.md`；`simctl erase` 后的 `clean-run-1.log` / `clean-run-2.log` 均含两条 UI 用例 `passed` 与 `** TEST SUCCEEDED **`；`bash scripts/test-android.sh` / `build-android.sh` 退出 0。
- 远端 run：首次交付 run 42517733837（main@fd39b5e）install/lint 通过，`test` 步失败——UI 测试 runner 报 `Failed to initialize for UI testing: Timed out waiting for AX loaded notification`（承载层），但当时重试判定只认 AC 原文两条措辞，未命中故未重试即判红；已把同族措辞并入 `infra_pattern` 并用 `ac-test-bounded-retry-scope` 断言锁死「只认承载层特征、不认产品断言」，重试次数仍为最多 1 次。
- 远端 run：第二次 run 42521260339 不再挂死，UI 用例真跑起来后失败于 `开始后 60s 内距离没有随真实定位样本从 0.00 km 变化`（产品级断言，重试判定正确地未触发）；判定为 `xcodebuild test` 重新安装 App 使脚本预置 TCC 失效、授权弹窗出现在点击 `run.start` 之后而无人处理，已把弹窗处理并入首个样本等待循环（`waitForFirstLocationSample` + `dismissLocationAlertsIfPresent`）。
- 远端 run：第三次 run 42525386686（main@dddaf9c）install/lint/`PurePaceTests` 58 例全绿，`PurePaceUITests-Runner` 在启动引导阶段崩溃——`Early unexpected exit, operation never finished bootstrapping`（`Test crashed with signal abrt while preparing to run tests`），属承载层 bootstrap 失败但当时 `infra_pattern` 未覆盖该措辞，故未触发那唯一一次重试即判红；现已把该措辞并入 `infra_pattern` 与 `check-ios-workflow.sh` 的必需特征集（重试上限仍为 1，负向自测仍拒绝产品断言措辞）。
- 远端 run：下一次 push 后需重取 `gh run list --repo munk-sh/open-pace --workflow ios.yml` 的真实 run id 与 conclusion；未取到绿色 run 前该项保持 `pending: 待 remote 验证`，不以本地绿替代。
