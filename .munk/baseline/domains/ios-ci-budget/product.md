# Domain: ios-ci-budget

`scripts/test-ios.sh` 的**预算记账与进程级看门狗**口径域：超时判定只认墙钟差额（`sleep` 仅作轮询粒度），预算按「step 预算 → attempt 预算 → 腿预算」三级下发且 attempt 预算显式扣除一次 infra 重试余量（默认 2700 − 900 = 1800s，严格小于 `ios.yml` 的 45min step 超时），预算不足/硬超时统一以 124 归口承载层。断言集合、`-only-testing` 选择器、门禁清单与 `timeout-minutes` 均不变，只修记账。

## 范围

- `scripts/lib/ios-budget.sh`（新，可 source 纯逻辑库）：`ios_now_epoch`（唯一墙钟取时入口，测试可重定义注入伪造时钟）、`ios_seconds_or_default`、`ios_attempt_budget`、`ios_leg_budget`、`ios_budget_short`、`ios_budget_message`、`run_with_watchdog`。刻意不加 `set -euo pipefail`、无主流程副作用；由 `scripts/test-ios.sh` 在使用点之前 source。
- `scripts/test-ios.sh`：删除内联 `run_with_watchdog` 与 `waited=$((waited + N))` 轮询计数；锁等待（1200s）、quiescent 等待（600s）、warmup 确认（≤10s）三处循环全部改墙钟差额判定；引入 `attempt_started_at` / `attempt_budget` / `attempt_budget_remaining()`，腿预算 `min(单腿上界 600, attempt 剩余)`；单测腿 `124` 与 UI 腿 `124` 均改归口「承载层预算/硬超时」，不再写成产品断言失败。
- `scripts/tests/test-ios-budget.sh`（249 行）：不依赖模拟器/Xcode/网络的确定性单测，用伪造时钟覆盖墙钟超时、非计数判定、退出码透传、预算算术与承载层口径文案。冻结时钟用例的「读次数下界」由测试侧 **确定性放行** 驱动（伪造时钟第 N 次取时 `touch` release 文件，子进程等待该文件后退出），不依赖子进程墙钟时长与机器速度。
- `scripts/check-ios-scripts.sh`：追加「预算单测必须随 `lint-ios-scripts` 门执行」的正向/负向断言（沙箱注入 `waited=$((waited + 1))` 的违规样本必须被识别为失败）。门禁清单与门数（22）不动。
- env 契约：`PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS`（默认 2700，与 45min 对齐）、`PUREPACE_IOS_RETRY_RESERVE_SECONDS`（默认 900）、`PUREPACE_IOS_UI_MIN_BUDGET_SECONDS`（默认 300）、`IOS_XCODEBUILD_TIMEOUT`（单腿上界，默认 600）、`IOS_WATCHDOG_POLL_SECONDS`（默认 1，仅轮询粒度）、`PUREPACE_IOS_STEP_STARTED_AT`（step 起始 epoch）；非法值一律回落默认。
- 必须保留的原文特征串：`阶段 xcodebuild-test 硬超时`、`runner bootstrap 挂起`（`ios.yml` 的 `infra_pattern` 依赖它们触发一次承载层重试），并在同一路径追加承载层/预算口径说明。
- 超时归口**条件分类**（本项）：库内纯函数 `ios_log_has_failed_test_case <log>` 匹配 `Test Case .*failed` 与 `Executed [0-9]+ tests?, with [1-9][0-9]* failures?`（`with 0 failures` 不命中）；`run_with_watchdog` 超时分支与 `scripts/test-ios.sh` 单测腿/UI 腿两处 124 分支共用 `ios_timeout_classification_message`——同日志已有 failed 用例则归口「产品用例失败」、**不**输出 `runner bootstrap 挂起`；无 failed 才走原 infra 归口并保留原文。超时判定（墙钟差额）、退出码 124 与子进程退出码透传、三级预算算术一律不变。

## 验收

- ac-watchdog-wall-clock-budget: `run_with_watchdog` 以墙钟差额判定超时（起点 `ios_now_epoch` 与每次轮询差额 ≥ 超时秒数），`sleep` 只作轮询粒度；伪造时钟每次前进 5s、预算 10s、子进程 `sleep 30` → ≤3 次轮询内返回 124。
- ac-watchdog-not-iteration-counted: 时钟冻结、预算 5s、子进程被确定性放行后正常退出 → 返回 0；`scripts/test-ios.sh` 与 `scripts/lib/**` 中不再出现以轮询计数参与预算判定的写法（`waited=$((waited` 式计数）。
- ac-reads-deterministic-lower-bound: 冻结时钟用例的读次数下界由固定常量 N（N ≥ 7，实现取 8）驱动且必然成立——`bash scripts/tests/test-ios-budget.sh` 每次运行该用例都 `[PASS]` 并读出 `reads >= N`，不存在「期望 >6」这类由子进程墙钟时长推导的下界失败分支。
- ac-frozen-clock-no-false-timeout: 冻结时钟下子进程被放行后正常退出，用例断言 `rc=0` 通过（看门狗未返回 124，即冻结时钟未被误判超时）。
- ac-assertions-not-weakened: 断言只增不删——不删除任何既有 `ac-*` 断言、不下调门限（读次数下界 N 严格大于原「>5 次轮询」意图）、不加 `retry` / `continue-on-error` / `|| true` / 延长超时。
- ac-repeat-stable-20x: `bash scripts/tests/test-ios-budget.sh` 连续 20 次结果完全一致（每次 exit 0、断言项数与失败数 0、无 `[FAIL]`）；交付回执记录命令、次数与时刻。
- ac-single-run-fast: 单次运行仍为纯 bash、无模拟器/Xcode/网络，耗时 <10s（不因等待 release 文件引入固定长睡）。
- ac-lint-ios-scripts-green: `bash scripts/check-ios-scripts.sh` 退出 0，含沙箱反例自检——沙箱 `scripts/test-ios.sh` 追加 `waited=$((waited + 1))` 后预算单测仍必须失败。
- ac-check-ios-scripts-sandbox-compat: 预算单测在 `check-ios-scripts.sh` 沙箱（只拷入 `scripts/test-ios.sh`、`scripts/lib/ios-budget.sh`、`scripts/tests/test-ios-budget.sh`）中仍正常并给出与仓库内一致结果；放行机制只依赖自身 `mktemp` 工作目录，不新增外部文件依赖。
- ac-watchdog-passthrough-exit: 子进程以 65 退出时 `run_with_watchdog` 原样返回 65，真实产品/测试失败退出码不被改写。
- ac-step-budget-strictly-less: attempt 预算 = step 预算 − 重试余量，严格小于 step 超时；默认 2700 − 900 = 1800s 且 1800 < 2700。
- ac-retry-margin-determinable: 重试余量可判定且 ≥ `ios.yml` 起跑门槛 900s、≥ UI 最小阈值 300s；单测断言 reserve ≥ 900、reserve ≥ ui_min、`attempt_budget >= reserve`。
- ac-retry-attempt-no-double-reserve: attempt 起点的 step 剩余 ≤ 首次 attempt 预算时，该次 attempt 预算取 step 剩余、不再扣第二次余量；单测：剩余 900s → attempt=900s，UI 腿 `min(600,900)=600`s，且 900 < 2700。
- ac-budget-exhausted-names-carrier: 预算不足以起跑某腿时日志点名「承载层预算」（含可用值、阈值、step/重试余量来源）并以 124 退出；单测断言消息含「承载层预算」且不含「断言失败」。
- ac-leg-budget-bounded-by-attempt: 单测腿与 UI 腿硬超时均取 `min(600, 该次 attempt 剩余)`；attempt 剩余 200s → 两腿均 200s；UI 且 200 < 300（ui_min）→ 判预算不足并 124，而非产品失败。
- ac-env-overridable: `PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS` 与 `PUREPACE_IOS_RETRY_RESERVE_SECONDS` 均可覆盖，单测 step=3600 / reserve=1200 → attempt=2400；非数字回落默认。
- ac-timeout-message-preserved: 超时路径保留 `……阶段 xcodebuild-test 硬超时……`、`……runner bootstrap 挂起……` 原文，并在同一路径追加承载层/预算口径说明。
- ac-timeout-classification-by-summary: 硬超时分支按同日志测试摘要分类——日志含 `Test Case .*failed` 或 `Executed N tests, with M failures`（M ≥ 1）时输出产品用例失败归口、点名 failed 用例/失败数，输出**不含**「未进入产品断言」；无 failed 时保留「runner bootstrap 挂起」原文并追加承载层预算口径。两分支都打印「阶段 xcodebuild-test 硬超时」与「超时前已执行的测试摘要」，返回值仍 124。
- ac-timeout-classification-pure-fn: `ios_log_has_failed_test_case` 为库内可单测纯函数，命中 `Test Case .*failed` 与 `Executed N tests?, with [1-9][0-9]* failures?`；空日志与 `with 0 failures` 不命中（既有空日志 infra 用例继续通过）。
- ac-classification-reused-by-caller: `scripts/test-ios.sh` 单测腿与 UI 腿两处 124 分支均调用 `ios_timeout_classification_message`（命中数 ≥ 2），同一日志不出现「产品用例失败」与「归口承载层预算」并存；`return 124` 未改。
- ac-timeout-exit-code-passthrough: 超时仍返回 124；非超时子进程退出码原样透传（`exit 65` → 65）；无 `|| true` / `continue-on-error` / `allowed-failure` 吞退出码。
- ac-budget-defaults-not-raised: `IOS_XCODEBUILD_TIMEOUT` 默认仍 600s、attempt 预算仍 2700 − 900 = 1800s；不调预算的依据（run `42755648335` attempt1 587s / UI 腿 497s，600s 上限余量 103s）与样例日志、看门狗实际输出路径写入本域交付证明与交付回执。
- ac-tests-runnable-deterministic: `bash scripts/tests/test-ios-budget.sh` 可独立运行、失败非零退出、不依赖模拟器/Xcode/网络、用伪造时钟保持确定性、单次 <10s，并被 `bash scripts/check-ios-scripts.sh`（`lint-ios-scripts` 门）调用以纳入本地 `code_gates`，且门禁清单不变。
- ac-scope-freeze: `.github/workflows/ios.yml`（45min timeout、900s 重试门槛、`infra_pattern`）、`.munk/code-gates.json`（仍 22 门）、`ios/`、`shared/`、`android/` 零改动；无 skip / continue-on-error / allowed-failure / 删断言 / 删腿 / 新增门腿；两次 `xcodebuild test` 的 `-only-testing` 选择器与 `-skip-testing:PurePaceUITests/DeviceFlowUITests` 不变（后续 `wi_intake_0a4f30b4782ffdd1` 起 UI 腿按目标拆成两次 `ui_call` 分段，记账/看门狗语义不变，详见 `domains/ios-ui-leg-determinism`）。测试确定性修正只落在 `scripts/tests/test-ios-budget.sh`（必要时对 `scripts/lib/ios-budget.sh` 做不改判定语义的最小测试辅助）；产品 App 源码、`.github/workflows/**`、`scripts/verify-ios-*`、门禁定义零改动。
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
- 退出语义只改分类不改断言集合：124 路径统一打印含「承载层预算」/「承载层硬超时」口径；`unit_status == 124` 不得再写成「PurePaceTests 失败（退出 N）」；`-only-testing` 选择器、跳过项、日志文件名（`xcodebuild-unit.log` / `xcodebuild-ui.log`）、allowance 参数与调用次数（各 1 次）不变。例外（`wi_intake_0a4f30b4782ffdd1`）：UI 腿改两次 `ui_call` 分段、新增 `xcodebuild-ui-2.log`，每段预算仍取 `min(IOS_XCODEBUILD_TIMEOUT=600, attempt 剩余)`，分段契约见 `domains/ios-ui-leg-determinism`。
- 静态门字面量不得削弱：`scripts/test-ios.sh` 仍含 `run_with_watchdog`、`IOS_XCODEBUILD_TIMEOUT` 且默认 `:-600`、`xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:`、`simctl bootstatus/install/privacy/launch/terminate`；顺序锚点 install < privacy < 单测 < UI；无 `simctl location`、无 `timeout <数字>`、不 echo 伪造 `BUILD/TEST SUCCEEDED`。
- 远端 shell 为 macOS bash 3.2：变量展开一律 `${var}`，变量后紧跟中文/非 ASCII 字节时必须带花括号（`check-shell-expansion.sh` 守）；新增文件须带 `set -euo pipefail`、`--help` 约定，不得写入 `VERSION` 字面值。
- 本地验证口径（收口证据，不跑远端）：`bash -n scripts/test-ios.sh scripts/lib/*.sh scripts/tests/test-ios-budget.sh`、`bash scripts/tests/test-ios-budget.sh`、`check-ios-scripts.sh` / `check-ios-workflow.sh` / `check-shell-expansion.sh` / `check-baseline.sh`、`bash scripts/test-ios.sh --unit-only`。
- 单测确定性口径：伪造时钟状态落在 `${work_dir}/fake-clock` / `fake-reads` 文件（跨子 shell 生效）；新增 gated 语义——第 N 次取时 `touch` `${work_dir}/fake-release`，冻结时钟用例子进程改为 `while [ ! -f "<release>" ]; do sleep 0.01; done` 后退出。`run_with_watchdog` 每轮先取时再 sleep，释放后子进程退出、下一轮取时一次即退出循环，故 `reads >= N` 必然成立；冻结模式 elapsed 恒为 0 < 超时，故 `rc=0` 必然成立。禁止用「子进程真实睡一段时间」推导读次数下界（机器速度函数，CI runner 上会伪红）。
- 与 `domains/ios-ci-stability` 的边界：该域仍是 iOS 测试链路稳定性的总契约（预热/锁/确定性定位源）；本域只承接「预算记账与看门狗」明细，两者冲突时以本域 AC 为准。

## 最近交付证明

- workItemId: wi_intake_5bfc7f2e9537b5fa（2026-11-10，pass）
- 交付：超时归口条件分类——`scripts/lib/ios-budget.sh` 新增 `ios_log_has_failed_test_case`（`Test Case .*failed` / `Executed N tests?, with [1-9][0-9]* failures?`，`with 0 failures` 不命中）与 `ios_timeout_classification_message`；`run_with_watchdog` 超时分支有 failed 即归口「产品用例失败」且不输出 `runner bootstrap 挂起`，无 failed 才走原 infra 归口；`scripts/test-ios.sh` 两处 124 分支复用同一判定文案。超时判定（墙钟差额）、退出码语义与预算算术零改动。
- 证据：`artifacts/failed-sample.log` 经 `run_with_watchdog 1` 复现 rc=124、stderr 含产品失败归口且不含「未进入产品断言」（`product-watchdog.stderr`）；空日志对照保留 infra 原文（`infra-watchdog.stderr`）。`bash scripts/tests/test-ios-budget.sh` 39 项 0 失败、`check-ios-scripts.sh` 29 项 0 失败、`bash -n` 全绿。
- 预算依据（不抬高）：run `42755648335` attempt1 587s / UI 腿 497s，600s 上限余量 103s；attempt 预算仍 1800s。
- 零改动：`.github/workflows/**`、`.munk/code-gates.json`（22 门）、`ios/PurePace/**`、`shared/`、`android/`、业务源码与版本号。
