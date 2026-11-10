# 修复 iOS CI 预算记账缺陷：墙钟计时 + 结构性重试余量，消除“零断言失败却报产品红”

## Scope

范围冻结在 `scripts/test-ios.sh` 及其测试（新增测试落 `scripts/tests/`，必要时抽出 `scripts/lib/` 内的可 source 纯逻辑），只修两处记账缺陷：

1. `run_with_watchdog` 用 `sleep 1` 轮询次数当计时（`waited=$((waited + 1))`）。runner 卡顿时每次 `sleep 1` 的真实墙钟远大于 1s，导致预算记账系统性偏低、外部 step 到期被硬杀。
2. 内部软预算 `PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS=2700`（`.github/workflows/ios.yml` 注入）与 step `timeout-minutes: 45`（=2700s）完全相等，没有任何余量，导致：
   - 单次 attempt 可以在基座层耗到 step 硬超时（run 42737438947：unit 腿 `** TEST EXECUTE SUCCEEDED **` 真实通过，红在 45min step 超时）；
   - ios.yml 的重试门槛（step 剩余 ≥900s 才起 attempt2）结构性拿不到时间（run 42738916859：UI runner `Timed out while loading Accessibility` exit 65，重试被饿死）。

做法：看门狗改用墙钟差额判定（`sleep` 只作轮询粒度）；内部 attempt 预算显式扣除“重试余量”，保证严格小于 step 超时并为一次 infra 重试保留可判定的余量；预算耗尽/被挂起诉求改名为承载层预算/硬超时口径（保留原文特征串），实际执行的断言集合零变化；为预算算术与墙钟计时补确定性单测。

实测依据（ops CI 观测 run trun_e9d7f49ef15ba10f）：
- ios run 42737438947（fce19dc）：unit 腿 `** TEST EXECUTE SUCCEEDED **`（真实用例 24.9s），红在 GitHub 45min step 超时；同 sha android 1m24s 绿。
- ios run 42738916859（279cbc2）：unit 腿同样成功，红在 UI runner `Timed out while loading Accessibility` exit 65；命中 `infra_pattern` 的重试因剩余预算 < 门槛未起跑。

## Acceptance Criteria

- ac-watchdog-wall-clock-budget: `run_with_watchdog` 的超时判定必须由墙钟差额驱动（起点 `date +%s`/`SECONDS` 与每次轮询时的差额 ≥ 超时秒数）；`sleep` 只作轮询粒度。单测：伪造时钟每次读取前进 5s、预算 10s、子进程 `sleep 30` → ≤3 次轮询内返回 124。
- ac-watchdog-not-iteration-counted: 时钟冻结（不前进）、预算 5s、子进程真实运行约 0.3s（轮询次数 >5）→ 返回 0，不判超时；且 `scripts/test-ios.sh`、`scripts/lib/**` 中不再出现以轮询计数参与预算判定的写法（`waited=$((waited` 式计数）。
- ac-watchdog-passthrough-exit: 子进程以 65 退出时 `run_with_watchdog` 原样返回 65（真实产品/测试失败的退出码与断言集合不被改写）。
- ac-step-budget-strictly-less: 内部 attempt 预算 = step 预算 − 重试余量，必须严格小于 step 超时；默认 step=2700s（与 ios.yml 45min 对齐）、重试余量=900s → attempt=1800s，且 1800 < 2700 严格成立。
- ac-retry-margin-determinable: 重试余量必须可判定且不小于 ios.yml 的起跑门槛 900s 与 UI 最小阈值 300s；单测断言 reserve ≥ 900 且 reserve ≥ ui_min、`attempt_budget >= reserve`（保证至少一次满载单腿 600s 的 UI 腿能起跑）。
- ac-retry-attempt-no-double-reserve: 当 attempt 起点的 step 剩余 ≤ 首次 attempt 预算（即本次已是重试 attempt）时，该次 attempt 预算取 step 剩余、不再扣第二次余量；单测：step 剩余 900s → attempt=900s，UI 腿可用 `min(600,900)=600`s，且 900 < 2700 仍严格成立。
- ac-budget-exhausted-names-carrier: attempt 剩余预算不足以起跑某腿时，日志必须点名“承载层预算”（含可用值、阈值、step/重试余量来源）并以 124 退出，不得以“产品断言失败”口径收场；单测断言该消息含“承载层预算”且不含“断言失败”。
- ac-leg-budget-bounded-by-attempt: 单测腿与 UI 腿的硬超时均取 `min(600s, 该次 attempt 剩余)`；单测：attempt 剩余 200s → 两腿预算均 200s；UI 且 200 < 300（ui_min）→ 判预算不足并 124，而不是以产品失败退出。
- ac-env-overridable: `PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS` 与新 `PUREPACE_IOS_RETRY_RESERVE_SECONDS` 均可覆盖；单测：step=3600 / reserve=1200 → attempt=2400，且非法值（非数字）回落到默认值。
- ac-timeout-message-preserved: 超时路径必须保留 ios.yml `infra_pattern` 依赖的原文特征串“……阶段 xcodebuild-test 硬超时……”、“……runner bootstrap 挂起……”（不得删改），并在同一路径追加承载层/预算口径说明。
- ac-tests-runnable-deterministic: 新增 `scripts/tests/test-ios-budget.sh` 可独立 `bash scripts/tests/test-ios-budget.sh` 运行，且失败非零退出；不依赖模拟器/Xcode/网络，用伪造时钟保持确定性，单次运行 <10s；并随现有的 `bash scripts/check-ios-scripts.sh`（`lint-ios-scripts` 门）一起执行，使本地 `code_gates` 覆盖新增单测而不改门禁清单。
- ac-scope-freeze: `.github/workflows/ios.yml`（45min timeout 与 900s 重试门槛、`infra_pattern`）、`.munk/code-gates.json`（门数仍 22）、`ios/`、`shared/`、`android/` 零改动；无 skip / continue-on-error / allowed-failure / 删断言 / 删腿 / 新增门腿；两次 `xcodebuild test` 的 `-only-testing` 选择器与 `-skip-testing:PurePaceUITests/DeviceFlowUITests` 保持不变。
- ac-unit-leg-unchanged: 本地 `bash scripts/test-ios.sh --unit-only` 仍真实执行 `-only-testing:PurePaceTests` 单测腿（断言集合不变），退出码语义（0/1/2/124）不变，且不得出现伪造 `TEST SUCCEEDED` 行。

## Non-Goals

- 不修真实存在的 UI runner Accessibility/AX 挂起本身（属承载层不稳定，由 ios.yml `infra_pattern` + 有界重试处理）；本项只修记账与余量，让重试“拿得到时间”。
- 不改 `.github/workflows/ios.yml` 的 `timeout-minutes: 45`、重试门槛 900s、`infra_pattern` 分类体系与 `scripts/check-ios-workflow.sh` 断言。
- 不在脚本内新增重试循环/重试次数；重试权威仍在 ios.yml。
- 不调整 `-default-test-execution-time-allowance` / `-maximum-test-execution-time-allowance` 数值，不改 `IOS_XCODEBUILD_TIMEOUT` 默认 600s 的单腿上界。
- 不缩短、跳过或删减 UI 腿与任何用例；不做“重跑到绿”；远端 run 结论由 CI guard 观测，不在会话内轮询。
- 不动 `scripts/verify-ios-ui-e2e.sh` / `scripts/verify-ios-sim-runtime.sh` 等模拟器重腿，不动业务源码与版本号。

## Implementation Constraints

用户已冻结的约束（不是正式技术方案，Architect 不上场）：

1. 计时与记账
   - `run_with_watchdog` 循环内改为：`started_at=$(date +%s)`，每轮 `elapsed=$(( $(date +%s) - started_at ))`，用 `elapsed -ge timeout_seconds` 判定；`sleep` 仅作轮询粒度（默认 1s，可保留）。
   - 为可测性，把墙钟取时收敛到一个可覆盖函数（如 `ios_now_epoch`，默认 `date +%s`）；测试通过重定义该函数注入伪造时钟，不改生产语义。
   - 删除 `waited=$((waited + 1))` 式计数参与预算判定的写法。
2. 预算数值与依据（同时写进 PR 说明）
   - `step_budget`：`PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS`（ios.yml 注入 2700），未设置/非法时回落 2700，与 45min step 超时对齐。
   - `retry_reserve`：`PUREPACE_IOS_RETRY_RESERVE_SECONDS`，默认 900。依据：ios.yml 起跑门槛为“剩余 ≥900s 才起 attempt2”，余量取 900 才能让重试在门槛上方起跑；同时 ≥ UI 最小阈值 300 且 ≥ 单腿上界 600，保证一次 UI 腿可完整跑完。
   - `attempt_budget = step_budget - retry_reserve`（默认 1800），必须严格小于 step_budget；若 `attempt_budget < ui_min(300)` 则直接判“承载层预算不足”并以 124 退出，不空转。
   - 重试 attempt 判定：`step_remaining_at_start = max(0, step_budget - (now - PUREPACE_IOS_STEP_STARTED_AT))`；若 `step_remaining_at_start <= attempt_budget`，本次 attempt 预算取 `step_remaining_at_start`（不重复扣余量）。
   - 腿预算：`leg_budget = min(600, attempt_budget - elapsed_in_attempt)`；UI 腿 `<300` → 124（承载层预算不足）；单测腿无独立最小阈值（被 124 命中时同样归口承载层预算）。
3. 退出语义（只改分类，不改断言集合）
   - 124 路径统一打印含“承载层预算”/“承载层硬超时”的口径，并保留原文“阶段 xcodebuild-test 硬超时”“runner bootstrap 挂起”；不得出现“产品断言失败”措辞。
   - 单测腿 `unit_status == 124` 时不得再写成“PurePaceTests 失败（退出 N）”的断言失败口径，应点名承载层预算/硬超时并返回 124。
   - `-only-testing` 选择器、跳过项、日志文件名（`xcodebuild-unit.log` / `xcodebuild-ui.log`）、`-test-timeouts-enabled`/allowance 参数与调用次数（各 1 次）保持不变。
4. 结构与既有静态门必须同时满足（改坏即打回）
   - `scripts/test-ios.sh` 必须仍含字面量：`run_with_watchdog`、`IOS_XCODEBUILD_TIMEOUT` 且默认 `:-600`（`check-ios-scripts.sh` 用 sed 抓首个默认值并断言 ≤600）、`xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:`、`simctl bootstatus`、`simctl install`、`simctl privacy`、`simctl launch`、`simctl terminate`；顺序锚点 install < privacy < 单测 < UI 必须保持；不得出现 `simctl location`；不得出现 `timeout <数字>` 形式（macOS 无 GNU timeout）；不得 echo/printf 伪造 `BUILD SUCCEEDED`/`TEST SUCCEEDED`。
   - 若抽出 `scripts/lib/*.sh`：只放纯逻辑/看门狗函数，不加 `set -euo pipefail` 之外的主流程副作用，由 `test-ios.sh` 在定义使用点之前 source。
   - 新增测试文件与库文件须符合 `scripts/check-shell-expansion.sh`（`${VAR}` 花括号 + 变量后紧跟中文/非 ASCII 字节时必须带花括号）、`set -euo pipefail`、`--help` 约定，且不得写入 `VERSION` 字面值。
   - 不新增/不改 `.munk/code-gates.json`（门数 22 断言在 `check-ios-scripts.sh` 内），新增单测由 `scripts/check-ios-scripts.sh` 调用接入。
5. 本地验证（收口证据，不跑远端）
   - `bash -n scripts/test-ios.sh scripts/lib/*.sh scripts/tests/test-ios-budget.sh`
   - `bash scripts/tests/test-ios-budget.sh`
   - `bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-workflow.sh`、`bash scripts/check-shell-expansion.sh`、`bash scripts/check-baseline.sh`
   - `bash scripts/test-ios.sh --unit-only`
   - 预算：≤10M token、90 分钟内收口。
6. PR 说明必须写清：“改的是预算记账（墙钟）与余量（step − 900s 重试余量 = 1800s），不是放宽门禁”——45min 不变、断言集合不变、无 skip/continue-on-error。
