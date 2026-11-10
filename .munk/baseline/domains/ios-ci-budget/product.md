# Domain: ios-ci-budget

`scripts/test-ios.sh` 的**预算记账与进程级看门狗**口径域：超时判定只认墙钟差额（`sleep` 仅作轮询粒度），预算按「step 预算 → attempt 预算 → 腿预算」三级下发且 attempt 预算显式扣除一次 infra 重试余量（默认 2700 − 900 = 1800s，严格小于 `ios.yml` 的 45min step 超时），预算不足/硬超时统一以 124 归口承载层。断言集合、`-only-testing` 选择器、门禁清单与 `timeout-minutes` 均不变，只修记账。

## 范围

- `scripts/lib/ios-budget.sh`（新，可 source 纯逻辑库）：`ios_now_epoch`（唯一墙钟取时入口，测试可重定义注入伪造时钟）、`ios_seconds_or_default`、`ios_attempt_budget`、`ios_leg_budget`、`ios_budget_short`、`ios_budget_message`、`run_with_watchdog`。刻意不加 `set -euo pipefail`、无主流程副作用；由 `scripts/test-ios.sh` 在使用点之前 source。
- `scripts/test-ios.sh`：删除内联 `run_with_watchdog` 与 `waited=$((waited + N))` 轮询计数；锁等待（1200s）、quiescent 等待（600s）、warmup 确认（≤10s）三处循环全部改墙钟差额判定；引入 `attempt_started_at` / `attempt_budget` / `attempt_budget_remaining()`，腿预算 `min(单腿上界 600, attempt 剩余)`；单测腿 `124` 与 UI 腿 `124` 均改归口「承载层预算/硬超时」，不再写成产品断言失败。
- `scripts/tests/test-ios-budget.sh`（新，249 行）：不依赖模拟器/Xcode/网络的确定性单测，用伪造时钟覆盖墙钟超时、非计数判定、退出码透传、预算算术与承载层口径文案。
- `scripts/check-ios-scripts.sh`：追加「预算单测必须随 `lint-ios-scripts` 门执行」的正向/负向断言（沙箱注入 `waited=$((waited + 1))` 的违规样本必须被识别为失败）。门禁清单与门数（22）不动。
- env 契约：`PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS`（默认 2700，与 45min 对齐）、`PUREPACE_IOS_RETRY_RESERVE_SECONDS`（默认 900）、`PUREPACE_IOS_UI_MIN_BUDGET_SECONDS`（默认 300）、`IOS_XCODEBUILD_TIMEOUT`（单腿上界，默认 600）、`IOS_WATCHDOG_POLL_SECONDS`（默认 1，仅轮询粒度）、`PUREPACE_IOS_STEP_STARTED_AT`（step 起始 epoch）；非法值一律回落默认。
- 必须保留的原文特征串：`阶段 xcodebuild-test 硬超时`、`runner bootstrap 挂起`（`ios.yml` 的 `infra_pattern` 依赖它们触发一次承载层重试），并在同一路径追加承载层/预算口径说明。

## 验收

- ac-watchdog-wall-clock-budget: `run_with_watchdog` 以墙钟差额判定超时（起点 `ios_now_epoch` 与每次轮询差额 ≥ 超时秒数），`sleep` 只作轮询粒度；伪造时钟每次前进 5s、预算 10s、子进程 `sleep 30` → ≤3 次轮询内返回 124。
- ac-watchdog-not-iteration-counted: 时钟冻结、预算 5s、子进程真实运行约 0.3s（轮询次数 >5）→ 返回 0；`scripts/test-ios.sh` 与 `scripts/lib/**` 中不再出现以轮询计数参与预算判定的写法（`waited=$((waited` 式计数）。
- ac-watchdog-passthrough-exit: 子进程以 65 退出时 `run_with_watchdog` 原样返回 65，真实产品/测试失败退出码不被改写。
- ac-step-budget-strictly-less: attempt 预算 = step 预算 − 重试余量，严格小于 step 超时；默认 2700 − 900 = 1800s 且 1800 < 2700。
- ac-retry-margin-determinable: 重试余量可判定且 ≥ `ios.yml` 起跑门槛 900s、≥ UI 最小阈值 300s；单测断言 reserve ≥ 900、reserve ≥ ui_min、`attempt_budget >= reserve`。
- ac-retry-attempt-no-double-reserve: attempt 起点的 step 剩余 ≤ 首次 attempt 预算时，该次 attempt 预算取 step 剩余、不再扣第二次余量；单测：剩余 900s → attempt=900s，UI 腿 `min(600,900)=600`s，且 900 < 2700。
- ac-budget-exhausted-names-carrier: 预算不足以起跑某腿时日志点名「承载层预算」（含可用值、阈值、step/重试余量来源）并以 124 退出；单测断言消息含「承载层预算」且不含「断言失败」。
- ac-leg-budget-bounded-by-attempt: 单测腿与 UI 腿硬超时均取 `min(600, 该次 attempt 剩余)`；attempt 剩余 200s → 两腿均 200s；UI 且 200 < 300（ui_min）→ 判预算不足并 124，而非产品失败。
- ac-env-overridable: `PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS` 与 `PUREPACE_IOS_RETRY_RESERVE_SECONDS` 均可覆盖，单测 step=3600 / reserve=1200 → attempt=2400；非数字回落默认。
- ac-timeout-message-preserved: 超时路径保留 `……阶段 xcodebuild-test 硬超时……`、`……runner bootstrap 挂起……` 原文，并在同一路径追加承载层/预算口径说明。
- ac-tests-runnable-deterministic: `bash scripts/tests/test-ios-budget.sh` 可独立运行、失败非零退出、不依赖模拟器/Xcode/网络、用伪造时钟保持确定性、单次 <10s，并被 `bash scripts/check-ios-scripts.sh`（`lint-ios-scripts` 门）调用以纳入本地 `code_gates`，且门禁清单不变。
- ac-scope-freeze: `.github/workflows/ios.yml`（45min timeout、900s 重试门槛、`infra_pattern`）、`.munk/code-gates.json`（仍 22 门）、`ios/`、`shared/`、`android/` 零改动；无 skip / continue-on-error / allowed-failure / 删断言 / 删腿 / 新增门腿；两次 `xcodebuild test` 的 `-only-testing` 选择器与 `-skip-testing:PurePaceUITests/DeviceFlowUITests` 不变。
- ac-unit-leg-unchanged: 本地 `bash scripts/test-ios.sh --unit-only` 仍真实执行 `-only-testing:PurePaceTests`，退出码语义（0/1/2/124）不变，且不出现伪造 `TEST SUCCEEDED` 行。

## 非目标

- 不修 UI runner Accessibility/AX 挂起本身（承载层不稳定，由 `ios.yml` 的 `infra_pattern` + 有界重试处理）；本域只让重试「拿得到时间」。
- 不改 `.github/workflows/ios.yml` 的 `timeout-minutes: 45`、900s 重试门槛、`infra_pattern` 分类体系与 `scripts/check-ios-workflow.sh` 断言。
- 不在脚本内新增重试循环/重试次数；重试权威仍在 `ios.yml`。
- 不调整 `-default-test-execution-time-allowance` / `-maximum-test-execution-time-allowance`，不改 `IOS_XCODEBUILD_TIMEOUT` 默认 600s 的单腿上界。
- 不缩短、跳过或删减 UI 腿与任何用例；不做「重跑到绿」；不动 `scripts/verify-ios-ui-e2e.sh` / `scripts/verify-ios-sim-runtime.sh` 等模拟器重腿、业务源码与版本号。

## 实现约束

- 计时：`run_with_watchdog` 内 `started_at=$(ios_now_epoch)`，每轮 `elapsed=$(( $(ios_now_epoch) - started_at ))` 判 `-ge timeout_seconds`；取时收敛到 `ios_now_epoch` 一处，便于测试重定义注入伪造时钟（不改生产语义）。
- 预算数值与依据：`retry_reserve` 取 900 是因 `ios.yml` 起跑门槛为「剩余 ≥900s 才起 attempt2」；同时 ≥ UI 最小阈值 300 与单腿上界 600，保证一次 UI 腿可完整跑完。`attempt_budget = step_budget - retry_reserve`，`< ui_min(300)` 时直接以 124 判承载层预算不足，不空转。
- 重试 attempt 判定：`step_remaining_at_start = max(0, step_budget - (now - PUREPACE_IOS_STEP_STARTED_AT))`，`step_remaining_at_start <= attempt_budget` 时本次 attempt 预算取该剩余。
- 退出语义只改分类不改断言集合：124 路径统一打印含「承载层预算」/「承载层硬超时」口径；`unit_status == 124` 不得再写成「PurePaceTests 失败（退出 N）」；`-only-testing` 选择器、跳过项、日志文件名（`xcodebuild-unit.log` / `xcodebuild-ui.log`）、allowance 参数与调用次数（各 1 次）不变。
- 静态门字面量不得削弱：`scripts/test-ios.sh` 仍含 `run_with_watchdog`、`IOS_XCODEBUILD_TIMEOUT` 且默认 `:-600`、`xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:`、`simctl bootstatus/install/privacy/launch/terminate`；顺序锚点 install < privacy < 单测 < UI；无 `simctl location`、无 `timeout <数字>`、不 echo 伪造 `BUILD/TEST SUCCEEDED`。
- 远端 shell 为 macOS bash 3.2：变量展开一律 `${var}`，变量后紧跟中文/非 ASCII 字节时必须带花括号（`check-shell-expansion.sh` 守）；新增文件须带 `set -euo pipefail`、`--help` 约定，不得写入 `VERSION` 字面值。
- 本地验证口径（收口证据，不跑远端）：`bash -n scripts/test-ios.sh scripts/lib/*.sh scripts/tests/test-ios-budget.sh`、`bash scripts/tests/test-ios-budget.sh`、`check-ios-scripts.sh` / `check-ios-workflow.sh` / `check-shell-expansion.sh` / `check-baseline.sh`、`bash scripts/test-ios.sh --unit-only`。
- 与 `domains/ios-ci-stability` 的边界：该域仍是 iOS 测试链路稳定性的总契约（预热/锁/确定性定位源）；本域只承接「预算记账与看门狗」明细，两者冲突时以本域 AC 为准。

## 最近交付证明

- workItemId: wi_intake_3fc087442ebae47d（2026-11-10，pass）
- 交付：新增 `scripts/lib/ios-budget.sh`（墙钟看门狗 + 预算算术 + 承载层口径文案）与 `scripts/tests/test-ios-budget.sh`（确定性单测）；`scripts/test-ios.sh` 改墙钟差额计时（删除 `waited=$((waited + N))`，锁/quiescent/warmup 三处一并收敛）、显式 attempt 预算（2700 − 900 = 1800s，重试 attempt 取 step 剩余不重复扣余量）、腿预算 `min(600, attempt 剩余)`、124 归口承载层；`scripts/check-ios-scripts.sh` 增加预算单测正反例自检。
- 口径变更（推翻旧约束）：`ios-ci-stability` 的 `ac-budget-per-leg-independent`（腿各享一份独立 600s）与 `ac-ui-budget-below-min-fails`（失败行为逐字前缀 `UI 腿可用 `）作废，改由本域 `ac-leg-budget-bounded-by-attempt` / `ac-budget-exhausted-names-carrier` 定义（腿预算改为 `min(600, attempt 剩余)`，文案改为 `承载层预算不足：<scope> 可用 Xs < 阈值 Ys（来源：step 预算 2700s − 重试余量 900s）`）。根因：`sleep 1` 轮询计数在 runner 卡顿时系统性低估墙钟，一次性 attempt 可耗尽至 step 硬超时，`ios.yml` 的重试门槛因此结构性拿不到时间。
- 验证：本 worktree `code_gates` 已通过（含 `lint-ios-scripts` 内的预算单测与其反例自检）；`bash scripts/test-ios.sh --unit-only` 本地实跑结论见本轮交付回执；CI 侧 run 结论仍由 guard 观测，未取到不写「CI 已通过」。
- 零改动：`.github/workflows/ios.yml`、`.munk/code-gates.json`（22 门）、`ios/`、`shared/`、`android/`、`scripts/check-ios-workflow.sh`、业务源码与版本号。
