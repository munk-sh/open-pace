# 修复 test-ios-budget 墙钟采样伪红（确定性读次数驱动）

## 范围

只修 `scripts/tests/test-ios-budget.sh` 中 `ac-watchdog-not-iteration-counted` 用例的伪红：

- 现状（约 129–140 行）：冻结时钟下用子进程 `bash -c 'sleep 0.3'` + `IOS_WATCHDOG_POLL_SECONDS=0.02`，再以「取时次数 > 6」断言轮询次数足够。读取次数 = 子进程墙钟时长 ÷ 单轮实际开销，是机器速度的函数；CI runner 约 60ms/轮时只有 5 次读取，断言假失败，导致 `lint-ios-scripts` exit 1，后续 test/build 全 skipped。
- 修法方向：把读次数改为「测试侧确定性放行」。测试伪造时钟在完成第 N 次取时（N 为固定常量，建议 8，必须 ≥7）时创建 release 文件；冻结时钟用例的子进程改为等待该 release 文件后退出。于是「取时次数 ≥ N」成为必然下界，与机器速度无关；同时仍断言 `rc=0`（冻结时钟不得被判超时）与「无 waited 计数」。
- 被测属性本身未坏：同一 run 输出里 `rc=0` 与「无 waited 计数」两条 PASS 已证明 `run_with_watchdog` 不按轮询计数判超时。本项只消除采样伪红，不改判定语义。

## 验收

- ac-reads-deterministic-lower-bound: 冻结时钟用例的读次数下界由固定常量 N（N≥7）驱动且必然成立——`bash scripts/tests/test-ios-budget.sh` 每次运行都输出该用例 `[PASS]` 且读出 `reads >= N`，不存在「期望 >6」这类由子进程墙钟时长推导的下界失败分支。
- ac-frozen-clock-no-false-timeout: 冻结时钟下子进程被放行后正常退出，用例断言 `rc=0` 通过（看门狗未返回 124，即冻结时钟未被误判超时）。
- ac-no-iteration-counter: 保留原「无 waited 计数」断言，`scripts/test-ios.sh` 与 `scripts/lib/ios-budget.sh` 中不出现 `waited=$((waited` 形式的轮询计数记账。
- ac-assertions-not-weakened: 断言只增不删——不得删除任何既有 `ac-*` 断言、不得下调门限（读次数下界 N 严格大于原来的 5 次轮询意图）、不得加 `retry` / `continue-on-error` / `|| true` / 延长超时。
- ac-repeat-stable-20x: `bash scripts/tests/test-ios-budget.sh` 连续运行 20 次结果完全一致（每次 exit 0、断言项数与失败数 0、无 `[FAIL]`）；digest 记录执行命令、次数与时刻。
- ac-single-run-fast: 单次运行仍为纯 bash、无模拟器/Xcode/网络、耗时 <10s（不因等待 release 文件引入固定长睡）。
- ac-lint-ios-scripts-green: `bash scripts/check-ios-scripts.sh` 退出 0，包含其沙箱反例自检——把 `waited=$((waited + 1))` 追加到沙箱 `scripts/test-ios.sh` 后，预算单测仍必须失败。
- ac-check-ios-scripts-sandbox-compat: 预算单测在 `check-ios-scripts.sh` 的沙箱中（只拷入 `scripts/test-ios.sh`、`scripts/lib/ios-budget.sh`、`scripts/tests/test-ios-budget.sh`）仍能正常运行并给出与仓库内一致的结果（新增机制只依赖自身 `mktemp` 工作目录，不新增外部文件依赖）。
- ac-code-gates-green: 本次改动落地后 Host `code_gates` 全绿（含 lint 门与可执行的门）；若某门因本机环境缺失不可执行，必须在 digest 明写 blocked 原因，不得计为绿，也不得声称基于 `677e11a0` 的 iOS 已可用。
- ac-scope-frozen: 改动只落在 `scripts/tests/test-ios-budget.sh`（必要时对 `scripts/lib/ios-budget.sh` 的测试辅助做最小改动且不改变 `run_with_watchdog` 的墙钟差额判定语义）；产品 App 源码、`.github/workflows/**`、`scripts/verify-ios-*`、门禁定义均无改动。

## 非目标

- 不新增门腿、不改 `.github/workflows`、不动 `verify-ios-sim-runtime.sh` / `verify-ios-ui-e2e.sh` / `verify-ios-device-flow.sh`。
- 不删断言、不降门限、不加 retry / `continue-on-error` / `|| true` 混绿、不延长超时。
- 不重写看门狗算法，不引入 GNU `timeout` 或第三方依赖。
- 本项不出候选包；CI 新 run 的 test/build 信号由 Owner 经 guard 观测，本项不声明 iOS 可用性。
- 不做 drive-by 的脚本清理、格式重排或注释大改。

## 实现约束

- 技术锚点（现状）：`scripts/tests/test-ios-budget.sh:73-101` 伪造时钟（`ios_now_epoch` 重定义，状态落在 `${work_dir}/fake-clock`、`${work_dir}/fake-reads` 文件，跨子 shell 生效）；`:129-140` 待改用例；`:227-232` 「无 waited 计数」断言。被测实现：`scripts/lib/ios-budget.sh:76-107` `run_with_watchdog` 超时判定只看 `ios_now_epoch` 墙钟差额，`sleep "${poll_seconds}"` 仅为轮询粒度。
- 首选实现（确定性读次数驱动）：在测试伪造时钟里新增 gated 语义——第 N 次取时（N 固定常量，建议 8）`touch` release 文件；子进程改为 `while [ ! -f "${release}" ]; do sleep 0.01; done` 后退出。审计要点：`run_with_watchdog` 每轮先取时再 `sleep`，释放后子进程退出，下一轮再取时一次即退出循环，故 `reads >= N` 必然成立；冻结模式下 elapsed 恒为 0 < 超时，故 `rc=0` 必然成立。N 必须 > 原意「>5 次轮询」，即 N≥7。
- 约束：保持 `set -euo pipefail`、macOS bash 3.2 兼容（无 `mapfile`、无 `sleep 0.0xx` 依赖 GNU 扩展的用法已存在，沿用即可）、无网络、无 Xcode/模拟器。
- 约束：`scripts/check-ios-scripts.sh:324-344` 会执行本单测并做沙箱反例自检；新机制必须在该沙箱内同样可跑、且在注入 `waited` 计数时仍报 FAIL，否则等同削弱门禁。
- 约束：`scripts/lib/ios-budget.sh` 顶端声明「不加 `set -euo pipefail`、不产生主流程副作用」；若需最小测试辅助，只能加无副作用、不改判定语义的内容，且优先尝试完全不动该文件。
- 降级规则：若确定性方案实测确实不可行（必须先给出实测证据），允许退到「只保留 `rc=0` + 读次数上界」，但必须先 `munk_report_owner` 上报、获准后在 digest 明写「覆盖降级」，不得静默降级。
- 交付证据：`bash scripts/tests/test-ios-budget.sh` 连跑 20 次恒同（记录命令/次数/时刻）、`bash scripts/check-ios-scripts.sh` 通过、`code_gates` 结果；预算 ≤8M token / ≤90 分钟，超时停手回执。
