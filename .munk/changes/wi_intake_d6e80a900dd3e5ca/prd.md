# iOS 门脚本：预算按腿独立 + 重试前算剩余 + 尝试日志不丢

## 范围

只修 iOS 门脚本的三处结构性缺陷，让 `ios` CI 的 UI 腿不再被预算饿死、重试不在 step 超时边缘起跑、失败 attempt 的日志不再被吞；不改产品代码、不新增门腿、不降任何断言。

1. `scripts/test-ios.sh` 预算按腿独立：单测腿与 UI 腿各自享有独立上限（`IOS_XCODEBUILD_TIMEOUT` 默认 600s，单测/UI 各一份），删除「UI 预算 = 600 - 单测已耗时」的共享聚合算法。UI 腿可用预算不得低于最小阈值 `PUREPACE_IOS_UI_MIN_BUDGET_SECONDS`（默认 300s）；当可用预算（含 step 剩余约束）低于该阈值时，输出明确一行并**失败退出**。
2. `scripts/test-ios.sh` / `.github/workflows/ios.yml` 重试前算剩余：`ios.yml` 向脚本传 step 预算与起点（`PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS` 默认 2700、`PUREPACE_IOS_STEP_STARTED_AT` epoch 秒）；attempt1 失败且命中承载层不稳定后，若剩余 step 预算 < 900s 则跳过 attempt2、打印明确一行并保留 attempt1 退出码。本地/无这两个 env 时行为与现状等价。
3. attempt 日志不再被吞：每次 attempt 输出改 `2>&1 | tee -a <log>`（或等价非 SIGPIPE 写法），进程被 SIGTERM 也能留下 partial 日志；`ios.yml` 用 `actions/upload-artifact`（`if: always()`、retention 3 天、只传 attempt 日志）上传，日志绝对路径在 step 开头 echo 一次。
4. 可选新增 `scripts/check-ios-test-budget.sh`：纯 bash 静态自检，不联网、不调 xcodebuild；若新增仅作手动证据腿，**不写入** `.munk/code-gates.json`。

## 验收标准

- ac-budget-per-leg-independent: 单测腿与 UI 腿各自获得独立上限（`IOS_XCODEBUILD_TIMEOUT` 默认 600s 各一份）；源码中不再用单测已耗时从 UI 预算里扣减（不存在把 `xcodebuild_timeout - (SECONDS - started_at)` 作为 UI 预算的表达式）。
- ac-ui-min-budget-threshold: `PUREPACE_IOS_UI_MIN_BUDGET_SECONDS` 未设置时最小阈值为 300s；显式设置为 N 时以 N 为准。
- ac-ui-budget-below-min-fails: 当 UI 腿可用预算 < 最小阈值时，脚本恰好输出一行前缀逐字为 `test-ios: 承载层预算不足：UI 腿可用 ` 的提示（形如 `test-ios: 承载层预算不足：UI 腿可用 120s < 最小阈值 300s`），并以非零退出；不得改写为通过、不得使用 `continue-on-error`。
- ac-retry-skip-low-step-budget: 当 `PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS` 与 `PUREPACE_IOS_STEP_STARTED_AT` 均存在且 attempt1 失败后剩余 step 预算 < 900s 时，不启动 attempt2，输出一行 `test-ios: 跳过重试，剩余 step 预算不足以跑完一轮`，最终退出码等于 attempt1 的退出码。
- ac-retry-default-unchanged: 未设置上述 step 预算 env（本地/旧调用）时，重试判定与现状一致：命中承载层特征仍重试 1 次，attempt1/attempt2 日志仍分文件。
- ac-step-budget-env-wired: `ios.yml` 的 test 步骤向 `scripts/test-ios.sh` 传递 `PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS`（默认 2700）与 `PUREPACE_IOS_STEP_STARTED_AT`（step 起始 epoch 秒）；step 超时仍为 45 分钟。
- ac-attempt-log-durable: 每次 attempt 的命令输出经 `2>&1 | tee -a <attempt log>`（或等价非 SIGPIPE 写法）落盘；进程被 SIGTERM/超时击杀后日志文件仍保留击杀前已产生的行；attempt 退出码仍取 `scripts/test-ios.sh` 的退出码，不被 tee 覆盖。
- ac-upload-artifact-always: `ios.yml` 含 `actions/upload-artifact` 步骤，配置 `if: always()`、`retention-days: 3`、只上传 attempt 日志文件（不上传整个目录），文件缺失时不额外判红。
- ac-log-abs-path-echoed: test step 开头 echo 一次 attempt 日志绝对路径（可执行 `$GITHUB_WORKSPACE` 或 `$PWD` 推导），不重复刷屏。
- ac-pass-fail-lines-unchanged: 同一输入下，改造前后 `scripts/test-ios.sh` 的 PASS/FAIL 行集合完全一致，仅允许多出 `test-ios: 承载层预算不足：…` 与 `test-ios: 跳过重试，剩余 step 预算不足以跑完一轮` 两条显式提示行。
- ac-no-sigpipe-and-syntax: 新增/改动的判定不得引入 `cmd | grep -q` 等在 `set -euo pipefail` 下可能触发 SIGPIPE(141) 的写法（用 here-string）；`bash -n scripts/test-ios.sh` 与可选自检脚本同为 0。
- ac-existing-gates-untouched-green: 不修改 `scripts/check-ios-scripts.sh` / `scripts/check-ios-workflow.sh` / `scripts/check-ios-shell.sh` 的前提下三者仍退出 0；`.munk/code-gates.json` 仍为 22 门且不改门列表。
- ac-no-scope-or-assertion-weakening: 不新增门腿、不改 workflow 触发条件/权限、不提高 45min step 超时、不删或弱化 `-only-testing` 集合、不新增 `continue-on-error`/`-skip-testing`、不扩 `infra_pattern`、不加自动分类/自动重试到绿逻辑。
- ac-determinism-and-evidence: 用 env 注入假时长演示三处行为并留 dry-run 输出；关键判定逻辑连跑 20 次结果恒同并留证；本地 `code_gates` 的 unit + build + lint 腿绿；UI E2E 权威结论只认 `ios.yml`，不得以本地绿替代。
- ac-honest-delivery-receipt: push 后回执写清改动文件、逐条证明路径、真实 run id + headSha + 绿/红原文；出结论即报，禁止重试凑绿，禁止无 run id 写「已修复远端 CI」。

## 非目标

- 不修 runner / 模拟器兼容性，不改模拟器预热、定位授权与锁逻辑。
- 不改产品代码：`ios/`、`ios/Core`、`shared/`、`android/`、`ios/project.yml` 一律不碰。
- 不改产品 UI 测试用例、任何测试断言文件与断言文案/判定语义（不减少 `PurePaceTests` 58 / `PurePaceUITests` 2）。
- 不新增门腿、不修改 `.munk/` 下任何文件（含 `code-gates.json`）、不改 workflow 触发条件与 permissions。
- 不扩 `infra_pattern` 分类、不新增 `check-ios-workflow.sh` 分类断言、不做自动分类/自动重试到绿。
- 不提高 45min step 超时、不删除/弱化 `-only-testing`、不引入 `continue-on-error` / `allowed-failure`。
- 不做 drive-by 美化、不重构无关代码、不扩大 CI 观测自动化。

## 实现约束

- 唯一可写集合：`scripts/test-ios.sh`、`.github/workflows/ios.yml`、可选新增 `scripts/check-ios-test-budget.sh`。其余文件一律不得改。
- 关键锚点：`scripts/test-ios.sh` 的 `xcodebuild_timeout`（L98）、`started_at`（L350）、共享剩余计算（L378-L383）、UI 调用预算（L404-L415）、`run_with_watchdog()`（L312-L339）；`.github/workflows/ios.yml` 的 test 步骤（L78-L136）、`run_attempt()`（L86-L98）、承载层重试判定（L100-L136）、build 步骤（L138-L153）。
- 必须保留现有结构门字面量（`scripts/check-ios-scripts.sh` L157-L246、`scripts/check-ios-workflow.sh` L134-L208 / L264-L297），不得为适配改动而删改门脚本：`IOS_XCODEBUILD_TIMEOUT:-600`（首个匹配行默认值 ≤600）、`-test-timeouts-enabled YES`、`-default-test-execution-time-allowance 300`、`-maximum-test-execution-time-allowance 540`（三者各出现 ≥2 次）、`xcodebuild-unit.log` / `xcodebuild-ui.log`、`-only-testing:PurePaceTests` / `-only-testing:PurePaceUITests`（保持 install → privacy → 单测 → UI 的行号顺序）、`run_with_watchdog`、`simctl bootstatus/install/privacy/launch/terminate`、`xcodebuild test`、`xcodegen generate`、`sync-ios-version.sh`、`blocked:`。
- `ios.yml` 必须保留 `timeout-minutes: 45` 原行、`run_attempt 1` / `run_attempt 2` 各恰一次、7 条 `infra_pattern` 与 `infra_unstable()` 判定；不得出现第二套 `xcodebuild test` / `xcodebuild build`；不得出现根 `VERSION` 字面值与不实措辞。
- 预算口径建议：单测腿与 UI 腿各自 `IOS_XCODEBUILD_TIMEOUT`（默认 600s）；若 step 预算 env 生效，UI 可用预算再取 `min(600, step 剩余)`，低于 `PUREPACE_IOS_UI_MIN_BUDGET_SECONDS`（默认 300s）时打印预算不足行并以非零（如 124）退出。
- 重试口径建议：在 `ios.yml` 的 test run 内、attempt2 之前计算 `remaining = PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS - (now - PUREPACE_IOS_STEP_STARTED_AT)`；仅当两个 env 都存在且 `remaining < 900` 时跳过 attempt2 并保留 attempt1 退出码；env 缺失时走原路径。避免 `while true` / `until false`。
- 日志口径建议：attempt 开始时先截断该 attempt 日志，再 `bash scripts/test-ios.sh 2>&1 | tee -a "$log_file"`，用 `PIPESTATUS[0]`（或 else 分支 `$?`）保留脚本退出码；`upload-artifact` 只指向 `.build/ci/test-ios-attempt*.log`，用 `if-no-files-found: ignore`。
- 远端 shell 为 macOS bash 3.2：参数展开统一 `${var}`，禁止 `$var` 紧邻全角字符；不得依赖 GNU `timeout`；新增判定用 here-string，不用 `printf | grep -q`。
- `upload-artifact` 步骤名不得取 `install`/`lint`/`test`/`build`，以免破坏步骤顺序断言；不得在 workflow 内新增 `xcodebuild` 调用。
- 可选 `scripts/check-ios-test-budget.sh` 采用 `set -euo pipefail`、支持 `--help`、不联网、不调 `xcodebuild`/`simctl`、不写 `code_gates.json`；内容不得含根 `VERSION` 字面值。
