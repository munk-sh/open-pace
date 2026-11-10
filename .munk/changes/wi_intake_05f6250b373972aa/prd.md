# iOS CI 承载层时间膨胀：把模拟器 boot 等待压到 ≤150s（复用已启动设备 + 有界轮询 + 分段计时）

## 范围

只治理 iOS CI 的「承载层预热」这一条链路：`scripts/test-ios.sh` 的模拟器准备段（bootstatus / shutdown / 预热 / 复用），外加（仅在实测证明必要时）`.github/workflows/ios.yml` 一个最小预热或缓存 hunk。

一手基线（2026-11-09 远端绿 run `ios 42663791618` @ d6f46d9，同 commit；日志时间戳换算）：

| 段 | 耗时 | 区间 |
|---|---|---|
| install（含下载 iOS 18.6 运行时 8.86GB） | 160s | 17:21:30→17:24:10 |
| lint | 153s | 17:24:23→17:26:56 |
| **test 步内 bootstatus（`simctl bootstatus -b`）** | **1192s** | 17:27:13→17:47:05 |
| build-for-testing | 157s | 17:47:05→17:49:42 |
| install App / install UI Runner / warmup / privacy | 56 + 77 + 92 + 6s | 17:49:43→17:53:34 |
| 单测腿（78 tests，测试本体仅 30s） | 276s | 17:53:35→17:58:11 |
| UI 腿（4 tests，测试本体 400s） | 558s | 17:59:05→18:08:23 |
| RunCore SwiftPM | 98s | 18:08:23→18:10:01 |
| **test 步合计** | **2585s / 预算 2700s（余量 4.3%）** | 17:26:57→18:10:01 |

结论性事实：boot 一步占 test 步 46%，且当前脚本每次都先 `simctl shutdown all` 再冷启，同一 job 内（含重试）会把这段成本重复支付；设备一旦已 booted 却仍被无条件关掉重建。

## 验收

- ac-boot-explicit-bounded: 冷启路径改为显式 `xcrun simctl boot <udid>`（非阻塞；对已 Booted 设备返回非零不得判失败）+ 有界轮询 `xcrun simctl bootstatus <udid>`：每轮打印 `[boot] elapsed=<n>s`，上限由 `PUREPACE_IOS_BOOT_TIMEOUT_SECONDS`（默认 1200）控制，超限打印 `simulator-boot` 阶段超时与 udid 并以非零退出；脚本仍保留字面量 `simctl bootstatus`，不用裸 `sleep` 当唯一同步原语。
- ac-boot-reuse-booted: 目标设备已是 `Booted` 且锁已持有、已 quiescent 时，不再执行 `xcrun simctl shutdown all`，改为打印 `[sim] reuse booted <udid>` 并把同一台设备复用给单测与 UI 两腿；仅在设备非 Booted 或确需清场时才 shutdown。锁原语逐条不变：`mkdir` 原子加锁 + pid 文件 + `PUREPACE_IOS_GATE_LOCK_HELD=1` 可重入 + 1200s 有界等待 + 陈旧锁清理 + `trap` 释放，且不引入未持锁的 `simctl`/`xcodebuild` 并发。
- ac-boot-parallel-build: 冷启时先发起 boot，再在同一 attempt 内执行 `xcodebuild build-for-testing`，build 结束之后才有界等待 bootstatus 就绪；计时证据能看出两段重叠（boot 起点早于 build 结束）。
- ac-timing-line: 每次运行输出一行分段计时 `[timing] boot=<n>s prep=<n>s build=<n>s unit=<n>s ui=<n>s runcore=<n>s total=<n>s` 并追加写入 `.build/logs/test-ios-timing.log`；脚本退出码语义不变（成功 0 / 断言失败 1 / 参数 2 / 硬超时或预算不足 124）。
- ac-warm-boot-150: 本地同机连续 2 次 `bash scripts/test-ios.sh`（第 1 次前先 `xcrun simctl shutdown all` 制造冷启，且此时无其它 worktree 持锁）：第 2 次 `[timing] boot` ≤150s；两次的 boot / build / unit / ui / total 实秒数与日志路径写进回执。
- ac-assertion-count-preserved: 两次运行均 `TEST SUCCEEDED`，PurePaceTests `Executed 78 tests`（≥78 且 0 failures）、PurePaceUITests `Executed 4 tests`（≥4 且 0 failures）；UI 腿仍带 `-skip-testing:PurePaceUITests/DeviceFlowUITests`，单测腿不含任何 `-skip-testing`；`DeviceFlowUITests.swift` 与 `verify-ios-device-flow.sh` 零改动。
- ac-gates-green: `.munk/code-gates.json` 全部 22 门退出 0（重点 `lint-ios-scripts`、`lint-ios-workflow`、`lint-ios-shell`、`test-ios`）；未修改任何 `scripts/check-*.sh` 断言、未新增门、未改门拓扑。
- ac-scope-minimal: `git diff --stat` 只含 `scripts/test-ios.sh`（必要时加一个预热入口脚本）与可选的最小 `ios.yml` 预热/缓存 hunk；`ios/**`（含 `project.yml`）、`shared/**`、`android/**`、`.github/workflows/android.yml` 零改动；若动 `ios.yml`，不得改触发条件、不得删 job、不得改判定语义、`timeout-minutes` 仍 ≤45、不得新增 `xcodebuild` 字面量、新增 step 名不得取 `install`/`lint`/`test`/`build`。
- ac-honest-ci-report: 回执只写本地实测数字与日志路径；CI 侧 boot 秒数与 test 步总时长以 guard 观测的同 commit run 为准，未取到即写 `pending: 待 guard 观测`，不得编造 run id、不得声称已达 150s。

## 非目标

- 不靠加 `timeout-minutes`、抬 2700s 预算、删腿、降/减断言、`continue-on-error`、`-skip-testing` 扩面、多跑重试凑绿；不改承载层重试判定串与次数（仍最多 1 次有界重试）。
- 不改本地门分层：`code_gates` 仍只跑快而确定腿，`test-ios` 仍固定 `--unit-only`；`verify-ios-sim-runtime.sh` / `verify-ios-ui-e2e.sh` 仍是非阻断旁证腿。
- 不改 destination 契约（iPhone 16 / iOS 18.6）、模拟器机型/系统、`bundle_id` 常量、`CODE_SIGNING_ALLOWED=NO` 主干。
- 不动 `VERSION`/`README`/Release/远端仓库设置，不 push tag，不产出也不认领 run id；不做 drive-by 重构与无关格式化。

## 实现约束

- 必须保留的结构门字面量（`scripts/check-ios-scripts.sh` L180-L247）：`simctl bootstatus`、`simctl privacy`、`grant location`、`simctl install`、`simctl launch`、`simctl terminate`、`run_with_watchdog`、`IOS_XCODEBUILD_TIMEOUT`（首个匹配行默认值 ≤600）、`-only-testing:PurePaceTests` / `-only-testing:PurePaceUITests`、`-test-timeouts-enabled YES`、`-default-test-execution-time-allowance 300`、`-maximum-test-execution-time-allowance 540`（后三者各出现 ≥2 次）、`xcodebuild-unit.log` / `xcodebuild-ui.log`；行号顺序仍须 `xcrun simctl install` < 首个 `xcrun simctl privacy` < `-only-testing:PurePaceTests` 独占行 < `-only-testing:PurePaceUITests` 独占行；`-skip-testing:PurePaceUITests/DeviceFlowUITests` 必须紧随 UI 的 `-only-testing` 行。
- `scripts/check-ios-shell.sh` L877-L891：`bash scripts/test-ios.sh --help` 必须退 0；`test-ios.sh` 内必须仍含 `xcodegen generate`、`xcodebuild test`、`sync-ios-version.sh` 字面量。`check-baseline.sh` L145：`scripts/*.sh` 不得出现根 `VERSION` 字面值。
- `scripts/check-ios-workflow.sh`：`steps` 中 `install`/`lint`/`test`/`build` 顺序不变（其余 step 名不受限，但不得与之同名），test 步 `timeout-minutes ≤45`，workflow 内不得出现第二处 `xcodebuild test|build` 字面量，`blocked:` 判失败口径不变。
- shell 可移植性：远端为 macOS bash 3.2，变量展开一律 `${var}`，不得紧邻全角字符；新增循环必须有界（禁止 `while true` / `until false` 形态的无限等待）。
- 测量协议（必须持锁执行，靠脚本自身取锁，避免踩同机其它 worktree）：`xcrun simctl shutdown all` → 立刻 `bash scripts/test-ios.sh`（第 1 次，冷启）→ 立刻再跑一次（第 2 次，应命中 reuse 路径）；分别记录起止时刻、`.build/logs/test-ios-timing.log` 的两次 `[timing]` 行、`.build/logs/xcodebuild-unit.log` 与 `xcodebuild-ui.log` 的 `Executed N tests` 行，作为回执证据。
- 改造顺序建议（先测后改，逐手段取数）：①分段计时（先量化）→ ②reuse 已 booted 设备（去掉无条件 `shutdown all`）→ ③显式 boot + 有界轮询 → ④boot 与 `build-for-testing` 并行；每步都记录 `[timing]` 变化，只保留实测有收益的最小组合。
- 决策规则（诚实交付口径）：若 scripts-only 组合仍让冷启轮次的 boot 远高于 150s（当前证据强烈指向「ephemeral runner 首次安装运行时后的首启成本」），允许加**一个**最小预热 step（持同一把锁；test 侧必须真正复用已 booted 设备，否则预热无意义），并在回执逐条说明「为何必要」；若连预热 step 也无法让 test 步内 boot ≤150s，**不得伪造**，按实测交付并列出未闭合项与下一杠杆（设备数据/运行时缓存、prewarm job 拆分）交 Owner 决策。
