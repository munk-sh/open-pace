# Domain: ios-ci-stability

PurePace iOS 测试链路稳定性域：让 `bash scripts/test-ios.sh` 在**全新 macOS runner + 全新 iOS 18.6 模拟器**上可重复跑绿。当前契约已从「CI 内真实 `simctl location` 注入」切换为**UI 测试走 DEBUG + launch-arg 门控的确定性测试源**（`-uiTestLocation`），真实 CoreLocation 链路由 `scripts/verify-ios-sim-runtime.sh` 门独立覆盖；单测与 UI 测试拆成两次 `xcodebuild test`，单测结论先落盘不被 UI 失败吞掉，单次 attempt 静默等待 ≤600s，承载层重试仍最多 1 次。真实定位/距离计算、`RunLocationSource` 授权与采样契约、RunCore 与持久化/导出契约零改动，UI 断言一条不减。

## 范围

- `ios/PurePace/Location/RunTestLocationSource.swift`（新文件，整类型身处 `#if DEBUG ... #endif`）：实现既有 `RunLocationProviding`（`delegate` / `authorization` / `start()` / `stop()`），`start()` 后 ≤1s 产出首个 `RunSample`，之后约 1s 一个、纬度约 +0.000090°/s（≈10 m/s）推进，`horizontalAccuracy` 合法、授权等价 `authorizedWhenInUse`；不读写磁盘、不做播报。`ios/project.yml` 目录级 glob 自动纳入，需刷新时只 `xcodegen generate`。
- `ios/PurePace/ContentView.swift` 组合根（`@MainActor init()`）：`#if DEBUG` 分支内 `CommandLine.arguments.contains("-uiTestLocation")` → 注入测试源，否则保持 `RunLocationSource()`；生产路径不得引用测试源类型。
- `ios/PurePaceUITests/RunFlowUITests.swift`：`app.launchArguments += ["-uiTestLocation"]`；仍恰 2 个 `func test...`、≥68 处 `XCTAssert`；保留 ≤10s 首样本探针（`firstSampleProbeTimeout = 10`）、授权弹窗兜底与全部距离/暂停/恢复/结束/History/详情/导出/分享/播报持久化断言。
- `scripts/test-ios.sh`：`simctl bootstatus -b` → `simctl uninstall`（清容器与 TCC）→ `xcodebuild build` + `simctl install` → `simctl privacy grant location` → `simctl launch` + `terminate` 预热 → **两次** `xcodebuild test`（先 `-only-testing:PurePaceTests`，再 `-only-testing:PurePaceUITests`），复用同一 `derivedDataPath`，日志分文件 `.build/logs/xcodebuild-unit.log` / `xcodebuild-ui.log`，单测 `Executed N tests` 摘要先 echo；脚本正文不含任何 `simctl location` 调用，改输出 `info: location-source=deterministic(-uiTestLocation)` 证据。
- `scripts/verify-ios-ui-e2e.sh`：UI 流不再依赖 `simctl location start`；默认证据根 `.build/verify-ios-ui-e2e/evidence`，仅显式 `--refresh-evidence` 才 copy 到 `docs/evidence/stage3-e2e/`；报告文案明确「UI/导出对齐由确定性测试源覆盖，真实 CoreLocation 由 verify-ios-sim-runtime 覆盖」；`--help` / 未知参数退出码契约不变。
- `scripts/verify-ios-sim-runtime.sh`：保持 1Hz 真实 `xcrun simctl location set` 注入，仍作为 `verify-ios-sim-runtime` 门存在。
- 结构门（只可加强）：`scripts/check-ios-scripts.sh` / `scripts/check-ios-shell.sh` 断言两次 `-only-testing` 调用与顺序、test-ios 无 `simctl location`、launch arg 存在、测试源 `#if DEBUG`、2 用例与 ≥68 断言、sim-runtime 真实注入仍在，每条新断言带负向自检。
- `.github/workflows/ios.yml`：`timeout-minutes: 45`、`infra_pattern`、`run_attempt 1/2` 均不变；`runner bootstrap 挂起` 字样继续由 `test-ios.sh` 输出以触发承载层重试。
- `AGENTS.md`：长期约定「CI UI 测试禁止依赖隐藏式 simulator 定位投递；UI 测试用 launch-arg 门控确定性测试源，真实 CoreLocation 覆盖放 `verify-ios-sim-runtime`（模拟器）/真机门」。
- 证据落点：`.munk/runs/<runId>/`（失败原始日志、`root-cause.md`、fix 说明、本机 clean run 日志、远端 run id 与 conclusion）；不写入仓库产品文件冒充证据。

## 验收

- ac-ui-tests-deterministic-source: `RunFlowUITests` 通过 `app.launchArguments` 传入 `-uiTestLocation` 启动 App；在没有任何 `simctl location` 投递的 hosted runner 上，开跑后 10s 内距离从 `0.00 km` 发生变化。
- ac-ui-assertions-intact: `RunFlowUITests` 仍恰有 2 个 `func test...`，`XCTAssert*` 出现次数不低于 68；距离增长、暂停/继续、结束保存、History 出现 1 条、详情/导出/分享、播报开关跨重启持久化等断言全部保留。
- ac-test-source-debug-and-arg-gated: 确定性测试源整体位于 `#if DEBUG`；仅当启动参数 `-uiTestLocation` 存在时由 `ContentView` 组合根注入；参数缺失或 Release 构建时仍使用 `RunLocationSource`；测试源只实现既有 `RunLocationProviding` / delegate 契约，首个样本 ≤1s、之后约 1s 一个、约 10 m/s 推进，授权等价 `authorizedWhenInUse`。
- ac-production-location-unchanged: `RunLocationSource` 仍用 `CLLocationManager`、`requestWhenInUseAuthorization`、`activityType = .fitness`、`distanceFilter = kCLDistanceFilterNone`、`pausesLocationUpdatesAutomatically = false`；RunCore 距离/配速/分段、播报、持久化、GPX 导出契约零改动。
- ac-test-ios-two-invocations: `scripts/test-ios.sh` 在 bootstatus 之后先跑 `-only-testing:PurePaceTests` 再跑 `-only-testing:PurePaceUITests`；两次调用日志/结果分文件，单测摘要先于 UI 输出；任一失败脚本非零退出，单测通过结论不被 UI 失败覆盖；脚本正文不再出现任何 `simctl location` 调用。
- ac-watchdog-and-retry-preserved: `IOS_XCODEBUILD_TIMEOUT` 默认值仍 ≤600s（单次 attempt 聚合预算），两个 `xcodebuild test` 调用仍带 `-test-timeouts-enabled YES` / `-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540`；`.github/workflows/ios.yml` 的 `timeout-minutes` 不放大，承载层重试仍为 1 次。
- ac-real-corelocation-gate-kept: `scripts/verify-ios-sim-runtime.sh` 仍以 1Hz `xcrun simctl location set` 真实驱动 corelocation 链路，且仍作为 `verify-ios-sim-runtime` 门存在于 `.munk/code-gates.json`。
- ac-structure-gates-strengthened: `check-ios-scripts.sh` / `check-ios-shell.sh` 新增断言覆盖上述契约（UI 路径无 `simctl location`、存在 `-uiTestLocation`、测试源 `#if DEBUG`、2 个用例与 ≥68 断言、sim-runtime 真实注入仍在），每条断言都有会失败的负向自检样本；`.munk/code-gates.json` 仍为 23 门且全绿。
- ac-evidence-no-churn: 直接运行 `scripts/verify-ios-ui-e2e.sh` 只更新 `.build/` 产物，`docs/evidence/stage3-e2e/` 保持 git 干净；带 `--refresh-evidence` 时才覆盖仓库证据目录，且 `--help` / 未知参数退出码契约不变。
- ac-agens-ci-rule: 仓库 `AGENTS.md` 含长期约定：CI 的 UI 测试禁止依赖隐藏式 simulator 定位投递，UI 测试用确定性测试源，真实定位覆盖放 e2e（模拟器）/真机门。
- ac-boot-warmup: 脚本在 `simctl bootstatus <udid> -b` 通过后才继续；随后完成一次安装/启动预热（`simctl launch` + `terminate`），boot 或预热失败即非零退出并打印设备 udid 与阶段，不静默跳过、不降级为通过。
- ac-sim-privacy-granted: 顺序铁律「`simctl uninstall` 清容器 → 构建安装 → `simctl privacy grant location` → `xcodebuild test`」，授权命令在安装之后、测试之前且可被脚本源码断言。
- ac-location-callback-diagnostics: 模拟器下仍记录 CoreLocation 授权状态与样本/过滤计数到 App 沙盒 `Documents/location-diagnostics.log`，仅 `#if targetEnvironment(simulator)` 路径，不改变真机行为与业务契约。
- ac-e2e-no-hidden-injection: `scripts/verify-ios-ui-e2e.sh` 与 `scripts/test-ios.sh` 均不再调用 `simctl location set/start` 驱动 UI 断言；真实注入只允许出现在 `verify-ios-sim-runtime.sh`。
- ac-local-two-green: 本机干净模拟器（先 `simctl shutdown all` + `simctl erase <udid>`）连续 2 次 `bash scripts/test-ios.sh` 全绿，日志含确定性测试源证据与 `** TEST SUCCEEDED **`。
- ac-remote-ci-green: main push 触发的 ios run `conclusion=success`，日志含 `** TEST SUCCEEDED **`（`PurePaceTests` 58 + `PurePaceUITests` 2），交付回执给出真实 run id 与 head sha（远端结论由 Owner 复核）；不得以本机绿替代远端绿。
- ac-android-no-regression: `bash scripts/test-android.sh` 与 `bash scripts/build-android.sh` 退出 0，`.github/workflows/android.yml` 不变。
- ac-gates-not-weakened: 不新增 `-skip-testing`、`continue-on-error`、`allowed-failure`、不删 job/步骤/断言；`check-ios-scripts.sh` / `check-ios-workflow.sh` / `check-ios-shell.sh` 与 `.munk/code-gates.json`（23 门）全部退出 0；结构门只可加强且保留反例自检。
- ac-honest-wording: 回执与文档只用「模拟器 + CI 链路」措辞；无 run id 不得写「CI 已通过」，不得写「真机已验证」；测试源只能写「CI 确定性测试源 ≠ 真机/真实注入」。

## 非目标

- 不修复 hosted runner 的 `simctl location` 投递差异，不再围绕它做注入实验。
- 不改产品定位/采样/授权/精度契约，不改 RunCore 距离/配速/分段、音频播报、持久化与 GPX 导出契约（阶段 3 技术路径冻结）。
- 不删除或弱化任何断言；不减少 `PurePaceTests` 58 / `PurePaceUITests` 2 的用例数；不新增 UI 用例掩盖问题。
- 不用 `continue-on-error` / `allowed-failure` / `skip` / 只跑单测混绿；不放大 `.github/workflows/ios.yml` 的 `timeout-minutes`；不改 `CODE_SIGNING_ALLOWED` 主干；不做无限重试。
- 不新增 `.munk/code-gates.json` 门（保持 23 门）；不改 Android、不改模拟器机型/系统（iPhone 16 / iOS 18.6）；不引入第三方运行时依赖（含 fastlane / actionlint）；不手写 `project.pbxproj`。
- 不动 `VERSION`/`README`、不推 tag、不改 Release、不做真机签名与分发；不追求美化或重构无关代码，不做 drive-by 清理。

## 实现约束

- 根因（一手证据，main@`e0dc912` 的 ios run 42537904591）：attempt1 命中 600s bootstrap 看门狗；attempt2 `PurePaceTests` 58 全绿，`RunFlowUITests.swift:95` 10s 内距离未离开 `0.00 km`。App 容器 `Documents/location-diagnostics.log` 显示授权 `authorizedWhenInUse`、`updating=true` 正常，但每个 session 只 `sample count=1` 且 session 间 lat 跳变——hosted runner 的 `simctl location set` 仅首次投递一个缓存点；同脚本本机干净模拟器（iPhone 16 / iOS 18.6，shutdown+erase）2 连绿。结论：缺陷在隐藏式模拟器定位投递，不在产品定位/距离计算（只有 1 个样本时距离不变是正确行为）。
- 关键锚点：`RunTestLocationSource.swift`（整类型 `#if DEBUG`）、`ContentView.swift` 的 `@MainActor init()`、`RunFlowUITests` 的 `-uiTestLocation` / `allowLocationIfNeeded()` / `dismissLocationAlertsIfPresent()` / `attachLocationDiagnostics()` / `firstSampleProbeTimeout=10`；`test-ios.sh` 的 `wait_for_simulator_boot()` / `prepare_simulator_for_ui_tests()` / `run_with_watchdog()` / `test_with_xcodebuild()`（原 `start_location_injection()` / `dump_location_diagnostics()` 已移除），日志路径 `.build/logs/xcodebuild-unit.log` / `xcodebuild-ui.log`；`verify-ios-ui-e2e.sh` 的 `--refresh-evidence`；`ios.yml` 的 `run_attempt` / `infra_unstable` / `reset_simulator`。
- 承载层措辞随 Xcode/runner 版本漂移：`Timed out while loading Accessibility.`、`Timed out waiting for AX loaded notification`、`Early unexpected exit, operation never finished bootstrapping`、`unknown to FrontBoard`、`runner bootstrap 挂起` 都必须命中重试判定；判定串只放承载层特征，禁止混入产品断言措辞（`check-ios-workflow.sh` 有负向自测锁死）。
- `simctl location start --speed --interval` 在 hosted runner 上 exit 0 却不投递样本（见 `.munk/runs/<runId>/root-cause.md`）：一律不再用模拟器注入驱动 UI 断言；真实注入仅保留在 `verify-ios-sim-runtime.sh` 的每秒 `simctl location set`。
- `simctl privacy` 只对已安装 bundle 生效，而 `simctl uninstall` 会清掉该 bundle 的 TCC 状态；顺序铁律「卸载清容器 → 安装 → grant location → `xcodebuild test`」，不得授权后再 uninstall。**runner 实测补充**：`xcodebuild test` 会用自己构建的产物再安装一次 App，脚本预置的 TCC 可能在测试开始时失效；UI 用例必须自己在首样本探针循环里处理弹窗。
- 硬超时用 bash 子进程看门狗（`kill -0` 轮询 → `TERM` → `KILL` → `124`），禁止依赖 GNU `timeout`；默认 600s（≤600s 硬上限），可用 `IOS_XCODEBUILD_TIMEOUT` 覆盖；两次 `xcodebuild test` 均带 `-test-timeouts-enabled YES`、`-default-test-execution-time-allowance 300`、`-maximum-test-execution-time-allowance 540`；UI 调用预算为聚合剩余时间，不得单独突破 600s；`build` 步仍走 `scripts/build-ios.sh`。
- 远端 shell 为 macOS bash 3.2：参数展开一律 `${var}`，禁止 `$var` 紧邻全角字符（否则 `unbound variable`）；固定字面量不得为适配 runner 删除：`iPhone 16` / `iOS 18.6`、`com.chaxiu.purepace`、`com.chaxiu.purepace.uitests.xctrunner`、`-destination 'platform=iOS Simulator,name=iPhone 16'`。
- 工程文件如需刷新只能 `xcodegen generate`，禁止手改 `.xcodeproj`；`RunFlowUITests` 禁用 `Thread.sleep` 作为成功判据。
- 本项为显式规格直派（bugfix 快速通道）：Intake → Coding → code_gates → Delivery；`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 false；若根因必须进一步改产品源码，先回执 Owner 确认，不得自行扩围。

## 最近交付证明

- workItemId: wi_intake_527803f0a406cf3d（2026-11-09，pass）
- 交付：新增 `ios/PurePace/Location/RunTestLocationSource.swift`（整类型 `#if DEBUG`，`-uiTestLocation` 门控、≈10 m/s 1Hz 样本）；`ContentView` 组合根 DEBUG 分支按启动参数注入，生产仍走 `RunLocationSource()`；`RunFlowUITests` 加 `-uiTestLocation` 并保留 2 用例 / 68 断言 / 10s 首样本探针；`scripts/test-ios.sh` 删除全部 `simctl location` 注入与诊断回读，改为 `-only-testing:PurePaceTests` → `-only-testing:PurePaceUITests` 两次调用（分文件日志、共享 derivedDataPath、聚合 ≤600s 看门狗）；`verify-ios-ui-e2e.sh` 默认只写 `.build/` 并新增 `--refresh-evidence`；`check-ios-scripts.sh` / `check-ios-shell.sh` 同步加强（含负向自检）；`AGENTS.md` 写入 CI 定位约定；门数仍 23。
- 验证：本 worktree `code_gates` 全绿（23 门）；真实 CoreLocation 覆盖仍由 `verify-ios-sim-runtime` 门承担。远端 ios run 结论待 Owner 复核（`ac-remote-ci-green`），未取到前不以本机绿替代。
