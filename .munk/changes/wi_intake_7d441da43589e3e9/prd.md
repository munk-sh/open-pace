# iOS CI 在全新 macOS runner + 全新 iOS 18.6 模拟器上稳定跑绿（不降门禁）

## 范围

- 修复 `scripts/test-ios.sh` 的模拟器前置状态准备：干净设备 boot 等待（`simctl bootstatus`）、构建安装 App 后用 `xcrun simctl privacy <udid> grant location com.chaxiu.purepace` 预置定位授权、再注入 `simctl location` 航点，最后才跑 `xcodebuild test`。
- 修复 `ios/PurePaceUITests/RunFlowUITests.swift` 的首次运行稳定性：授权兜底（UIInterruptionMonitor + SpringBoard 弹窗处理）、等待首个真实定位样本落地后再断言距离变化；保留全部既有断言。
- 修复 `.github/workflows/ios.yml` 的 `test` 步骤：加 `timeout-minutes` 硬上限，挂死快速失败；仅对 GitHub 承载层不稳定（无障碍初始化超时 / FrontBoard `unknown to FrontBoard`）做**最多 1 次**有界重试，两次完整日志与首次失败原因都打印。
- 在干净 iOS 18.6 模拟器（先 `simctl shutdown` + `simctl erase`）上复现并留存证据，修复后连续 2 次 `bash scripts/test-ios.sh` 通过，交付 push 后取真实绿色 run id。
- 允许改动：`scripts/test-ios.sh`、`ios/PurePaceUITests/*`、`.github/workflows/ios.yml`；为保持结构门与新契约一致，可同步加强（不得放宽）`scripts/check-ios-scripts.sh` / `scripts/check-ios-workflow.sh`。

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

- 现状事实（Owner 一手核对）：main 自真实 CoreLocation UI 用例进 CI 起连续 4 次 ios run 全红：42497785537(ac98bca)、42501736365(bccc07a)、42505929787(d941f0c)、42508006469(7a866a6)；此前 15:14 及以前全绿。head d280c5d8 的 run 42511873416 的 `test` 步 >35 分钟未结束，证明 `xcodebuild test` 无超时保护。
- 失败三类原文：①`RunFlowUITests.testRunPauseResumeFinishAndHistory`：`开始后距离没有随真实定位变化`；②`testAnnouncementTogglePersistsAcrossRelaunch`：`翻转后开关应关闭`；③`Failed to initialize for UI testing: Timed out while loading Accessibility.` 与 `Simulator device failed to launch com.chaxiu.purepace.uitests.xctrunner ... unknown to FrontBoard`。
- 关键锚点：`scripts/test-ios.sh:start_location_injection()`（bootstatus → uninstall → location start → `xcodebuild test`，当前缺安装后授权与超时）；`ios/PurePaceUITests/RunFlowUITests.swift`（两用例在 L11/L230，`allowLocationIfNeeded()` L295、`waitUntil()` L320）；`ios/PurePace/Location/RunLocationSource.swift:73-75` 首次运行 `requestWhenInUseAuthorization()`；`ios/project.yml:57` `NSLocationWhenInUseUsageDescription`；`.github/workflows/ios.yml` steps 顺序 install → lint → test → build。
- `simctl privacy` 顺序约束：授权只对已安装 App 生效，`simctl uninstall` 会清掉该 bundle 的 TCC 状态，因此必须「卸载清容器 → 安装 → grant location → 注入定位 → xcodebuild test」；不要授权后再 uninstall。
- 结构门不得放宽：`scripts/check-ios-scripts.sh` 断言 `test-ios.sh` 含 `xcodebuild test`、`-scheme`、`-destination 'platform=iOS Simulator,name=iPhone 16'`，且严格模式 / `BASH_SOURCE` / `--help` / 未知参数退出 2 均须保留；`scripts/check-ios-workflow.sh` 断言单 job `runs-on: macos-latest`、steps 顺序 install/lint/test/build、install 含 xcodegen + iPhone 16 + iOS 18.6 + `simctl create` + `downloadPlatform iOS`、test 步复用 `bash scripts/test-ios.sh` 且对 `blocked:` `exit 1`、workflow 内不得出现第二套 `xcodebuild test/build`。改动后这些断言仍须退出 0；如需新增断言只可加强。
- `scripts/test-ios.sh` 仍须保留 blocked 降级分支语义（工程不可用时显式 `blocked:` + `swift test`），CI test 步骤仍对 `blocked:` 判失败。
- 远端 shell 为 macOS bash 3.2：参数展开一律 `${var}`，禁止 `$var` 紧邻全角字符；不得依赖 GNU `timeout`（macOS 默认无），用 bash 子进程 watchdog + `kill` 实现硬超时。
- 模拟器固定 `iPhone 16` / `iOS 18.6`、bundle id `com.chaxiu.purepace`、UI test runner `com.chaxiu.purepace.uitests.xctrunner`；destination 字面量不得为适配 runner 删除。
- 证据落点：`.munk/runs/<当前 runId>/`（复现日志、根因说明、连续两次通过日志摘要、远端 run id 与结论）；不得写入仓库产品文件。
- 本项为显式规格直派：Intake 之后直接进 Coding，`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 false；如遇必须改产品源码才能修的根因，先回执 Owner 确认，不得自行扩围。
