# 根治 iOS CI 真实定位 UI 用例：DEBUG 门控测试定位源 + 单测/UI 拆分

## 背景与根因（一手证据）

- run 42537904591 / head `e0dc9126cb26a29a7b84ecf3a6f4e981dee3153b` 失败：attempt1 命中 600s bootstrap 看门狗；attempt2 `PurePaceTests` 58 全绿，`RunFlowUITests.swift:95` 断言失败（10s 内距离未从 `0.00 km` 变化），`** TEST FAILED **`。
- App 容器 `Documents/location-diagnostics.log`：授权 `authorizedWhenInUse`、`updating=true` 均正常，但每个 session 只有 `sample count=1`；四个 session 间 lat 跳变。即 hosted runner 的 `simctl location <udid> set` 只在首次请求投递一个缓存点，后续每秒 set 不产生连续回调。
- 同一脚本在本机干净模拟器（iPhone 16 / iOS 18.6，shutdown+erase）2 连绿；本机注入是连续样本流。结论：缺陷在 hosted runner 的隐藏式定位投递，不在产品定位/距离计算；只有 1 个样本时距离不变化是正确行为。

## 范围

按 A → B → C → D → E 顺序落地，UI 测试不再与 hosted runner 的 simulator 定位投递搏斗：

- **A（必做）** 在 App 组合根增加 `#if DEBUG` + 启动参数门控的确定性测试定位源（`-uiTestLocation`），由 `RunFlowUITests` 用 launch args 驱动；生产路径（`RunLocationSource` 的授权/采样/精度契约）一律不变。UI 断言一条不删。
- **B（必做）** 真实 CoreLocation 覆盖继续由模拟器脚本门 `scripts/verify-ios-sim-runtime.sh`（real `simctl location set`，stage2 harness corelocation）承担并保持门禁；`scripts/verify-ios-ui-e2e.sh` 的 UI 流改走确定性测试源，报告/帮助明确「真实定位覆盖在 sim-runtime 门」。
- **C（必做）** `scripts/test-ios.sh` 在 `xcrun simctl bootstatus <udid> -b` 后把单元测试与 UI 测试拆成两次 `xcodebuild test`（先 `-only-testing:PurePaceTests`，再 `-only-testing:PurePaceUITests`），单测结果先落盘；UI 失败不再吞掉单测结论。看门狗 ≤600s 与 `-test-timeouts-enabled YES` / `-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540` 保留；承载层重试仍最多 1 次。
- **D（必做）** 结构门同步加强：断言 UI 测试链路不再调用 `simctl location`、断言 launch-arg 测试源只在 DEBUG 生效、断言既有 UI 断言数量与用例数不回退、断言 sim-runtime 门仍保留真实 CoreLocation 注入；每条新断言带反例自检。
- **E（必做，低风险）** 消除 `docs/evidence/stage3-e2e/*` 每次门禁重写造成的 churn：`verify-ios-ui-e2e.sh` 默认只写 `.build/`，仅在显式 `--refresh-evidence` 时更新仓库证据目录。
- 更新仓库 `AGENTS.md`：写入「CI UI 测试禁止依赖隐藏式 simulator 定位投递」的长期约定。

## 验收

- ac-ui-tests-deterministic-source: `RunFlowUITests` 通过 `app.launchArguments` 传入 `-uiTestLocation` 启动 App；在没有任何 `simctl location` 投递的 hosted runner 上，开跑后 10s 内距离从 `0.00 km` 发生变化。
- ac-ui-assertions-intact: `RunFlowUITests` 仍恰有 2 个 `func test...`，`XCTAssert*` 出现次数不低于当前的 68 次；距离增长、暂停/继续、结束保存、History 出现 1 条、详情/导出/分享、播报开关跨重启持久化等断言全部保留。
- ac-test-source-debug-and-arg-gated: 确定性测试源整体位于 `#if DEBUG`；仅当启动参数 `-uiTestLocation` 存在时由 `ContentView` 组合根注入；参数缺失或 Release 构建时仍使用 `RunLocationSource`。测试源只实现既有 `RunLocationProviding` / delegate 契约，首个样本 ≤1s、之后约 1s 一个、约 10 m/s 推进，授权等价 `authorizedWhenInUse`。
- ac-production-location-unchanged: `RunLocationSource` 仍使用 `CLLocationManager`、`requestWhenInUseAuthorization`、`activityType = .fitness`、`distanceFilter = kCLDistanceFilterNone`、`pausesLocationUpdatesAutomatically = false`；RunCore 距离/配速/分段、播报、持久化、GPX 导出契约零改动。
- ac-test-ios-two-invocations: `scripts/test-ios.sh` 在 bootstatus 之后先跑 `-only-testing:PurePaceTests` 再跑 `-only-testing:PurePaceUITests`；两次调用的日志/结果分文件，单测摘要先于 UI 输出；任一失败脚本非零退出，单测通过结论不被 UI 失败覆盖；脚本正文不再出现任何 `simctl location` 调用。
- ac-watchdog-and-retry-preserved: `IOS_XCODEBUILD_TIMEOUT` 默认值仍 ≤600s（单次 attempt 聚合预算），两个 `xcodebuild test` 调用仍带 `-test-timeouts-enabled YES` / `-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540`；`.github/workflows/ios.yml` 的 `timeout-minutes` 不放大，承载层重试仍为 1 次。
- ac-real-corelocation-gate-kept: `scripts/verify-ios-sim-runtime.sh` 仍以 1Hz `xcrun simctl location set` 真实驱动 corelocation 链路，且仍作为 `verify-ios-sim-runtime` 门存在于 `.munk/code-gates.json`。
- ac-structure-gates-strengthened: `check-ios-scripts.sh` / `check-ios-shell.sh` 新增断言覆盖上述契约（UI 路径无 `simctl location`、存在 `-uiTestLocation`、测试源 `#if DEBUG`、2 个用例与 ≥68 断言、sim-runtime 真实注入仍在），每条断言都有会失败的负向自检样本；`.munk/code-gates.json` 仍为 23 门且全绿。
- ac-evidence-no-churn: 直接运行 `scripts/verify-ios-ui-e2e.sh` 只更新 `.build/` 产物，`docs/evidence/stage3-e2e/` 保持 git 干净；带 `--refresh-evidence` 时才覆盖仓库证据目录，且 `--help` / 未知参数退出码契约不变。
- ac-agens-ci-rule: 仓库 `AGENTS.md` 新增长期约定：CI 的 UI 测试禁止依赖隐藏式 simulator 定位投递，UI 测试用确定性测试源，真实定位覆盖放 e2e（模拟器）/真机门。
- ac-local-two-green: 本机干净模拟器（先 shutdown+erase）连续 2 次 `bash scripts/test-ios.sh` 全绿，日志含新测试源证据与 `** TEST SUCCEEDED **`。
- ac-remote-ci-green: main push 触发的 ios run `conclusion=success`，日志含 `** TEST SUCCEEDED **`（`PurePaceTests` 58 + `PurePaceUITests` 2），交付回执给出真实 run id 与 head sha（远端结论由 Owner 复核）。

## 非目标

- 不修复 hosted runner 的 `simctl location` 投递差异，不再围绕它做注入实验。
- 不改产品定位/采样/授权/精度契约，不改 RunCore 距离/配速/分段、音频播报、持久化与 GPX 导出契约（阶段 3 技术路径冻结）。
- 不删除或弱化任何断言；不减少 PurePaceTests 58 / PurePaceUITests 2 的用例数；不新增 UI 用例来掩盖问题。
- 不用 `continue-on-error` / `allowed-failure` / `skip` / 只跑单测混绿；不放大 `.github/workflows/ios.yml` 的 `timeout-minutes`；不改 `CODE_SIGNING_ALLOWED` 主干。
- 不新增 `.munk/code-gates.json` 门（保持 23 门）；不改 Android、不改模拟器机型/系统（iPhone 16 / iOS 18.6）；不引入第三方运行时依赖；不手写 `project.pbxproj`。
- 不追求美化或重构无关代码；不做 drive-by 清理。

## 实现约束

- **Fast-track**：本 WorkItem 的处置口径已由 Owner 指定到文件与实现方式，跳过 PM / Design / Architect，直接 Coding → code_gates → Delivery。
- 新文件落点：`ios/PurePace/Location/RunTestLocationSource.swift`（整个类型体在 `#if DEBUG ... #endif` 内，import `Foundation` / `PurePaceRunCore`；`CoreLocation` 不必须）。`ios/project.yml` 的 `sources: - path: PurePace` 是目录级 glob，新文件自动纳入；如工程文件需刷新，只能 `xcodegen generate`，禁止手改 `.xcodeproj`。
- 组合根：`ios/PurePace/ContentView.swift` 的 `@MainActor init()`（约 20–33 行）当前固定构造 `RunLocationSource()`；改为 `#if DEBUG` 分支：参数存在则注入测试源，否则保持 `RunLocationSource()`。生产代码路径不得引用测试源类型。
- 启动参数：统一 `-uiTestLocation`（存在即启用）；`RunFlowUITests.testRunPauseResumeFinishAndHistory()` 在 `app.launch()` 前追加 `app.launchArguments += ["-uiTestLocation"]`。播报开关用例可不加，但不得因此依赖 simctl 投递。
- 测试源行为：实现 `RunLocationProviding`（`delegate` / `authorization` / `start()` / `stop()`）；`start()` 后 ≤1s 产出首个 `RunSample`，随后约 1s 一个、纬度约 +0.000090°/s（≈10 m/s）推进，`horizontalAccuracy` 取合法值；`stop()` 停止；不读写磁盘、不做播报。`RunSessionOrchestrator.ingest` 只在 `running` 生效（`RunSessionOrchestrator.swift:150`），暂停断言语义不变。
- `RunFlowUITests.swift` 保持 2 个测试方法、68 处 `XCTAssert` 不回退、禁用 `Thread.sleep` 成功判据；授权弹窗兜底逻辑保留（真机/本机干净设备仍可能弹窗）。
- `scripts/test-ios.sh`：保留 `simctl bootstatus` → `uninstall` → `xcodebuild build` → `simctl install` → `simctl privacy grant location` → `simctl launch/terminate` 预热；删除 `start_location_injection` / `location-diagnostics` 相关注入与回读（或改为输出一行 `info: location-source=deterministic(-uiTestLocation)` 证据）。两次 `xcodebuild test` 复用同一 `derivedDataPath`，各自 `run_with_watchdog`；单次 attempt 的聚合硬超时仍由 `IOS_XCODEBUILD_TIMEOUT`（默认 600）控制，UI 调用不得单独突破 600s；单测日志与 UI 日志分文件（如 `.build/logs/xcodebuild-unit.log` / `xcodebuild-ui.log`），单测 `Executed N tests` 摘要必须在 UI 调用前 echo。保留 `-test-timeouts-enabled YES` / `-default-test-execution-time-allowance 300` / `-maximum-test-execution-time-allowance 540`。
- `scripts/verify-ios-ui-e2e.sh`（约 72–88 行证据目录、722–726 行定位注入）：移除 UI 流对 `simctl location start` 的依赖（UI 已由 launch arg 驱动），默认证据根改为 `.build/verify-ios-ui-e2e/evidence`；新增 `--refresh-evidence` 才 copy 到 `docs/evidence/stage3-e2e/`。报告文案改为「UI/导出对齐由确定性测试源覆盖；真实 CoreLocation 由 verify-ios-sim-runtime 覆盖」，不改 report 的通过/失败判定强度。
- `scripts/verify-ios-sim-runtime.sh` 保持真实 `simctl location set` 注入不动；`check-ios-scripts.sh` 增加「该脚本仍含 `simctl location ... set`」断言 + 反例自检，防止真实覆盖被误删。
- 结构门：
  - `scripts/check-ios-scripts.sh`（约 151–266 行 test-ios 契约）改为断言：存在 `-only-testing:PurePaceTests` 与 `-only-testing:PurePaceUITests`、单测调用行先于 UI 调用行、`test-ios.sh` 不含 `simctl location`（含 `set`/`start`）、看门狗默认 ≤600s、两次调用均带三个 test-timeout 参数；各配负向自检（注入 `simctl location set`、交换调用顺序、放大超时、删 launch arg 等样本必须被判失败）。
  - `scripts/check-ios-shell.sh`（约 574–616 行 `ac-live-run-ui` / `ac-tests-present`）增加：`RunFlowUITests.swift` 含 `-uiTestLocation`；`RunLocationSource.swift` 契约字面量仍在；测试源文件存在且含 `#if DEBUG` 与 `#endif`；`ContentView.swift` 对测试源的引用只出现在 DEBUG 分支；UI 用例数 ≥2、`XCTAssert` 计数 ≥68。用沙箱反例自检（去掉 `#if DEBUG`、删除 launch arg、删断言）验证断言非恒真。
- 不改 `.github/workflows/ios.yml`：`timeout-minutes: 45`、`infra_pattern`、`run_attempt 1/2` 均保持不变；`runner bootstrap 挂起` 字样继续由 `test-ios.sh` 输出以触发承载层重试。
- `.munk/code-gates.json` 保持 23 门，不增不减；只在脚本门内部加强断言。
- `AGENTS.md`：在协作基线中新增一条（建议放在“测试金字塔”或“目录约定”之后）：「CI 的 UI 测试禁止依赖隐藏式 simulator 定位投递；UI 测试用 launch-arg 门控的确定性测试源，真实 CoreLocation 覆盖放 `verify-ios-sim-runtime`（模拟器）/真机门。」
- 交付验证（Owner 复核）：本机先 `xcrun simctl shutdown all && xcrun simctl erase <udid>`，连续 2 次 `bash scripts/test-ios.sh` 全绿并留日志；推送 main 后给出 ios run 的 run id / head sha / `** TEST SUCCEEDED **` / 58 + 2 用例数。本机绿不能替代远端绿。
