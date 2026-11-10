# 证据：硬超时归口条件分类（wi_intake_5bfc7f2e9537b5fa）

## 样例与命令

既有样例日志（PHP 无关，纯 printf 构造）：

- `artifacts/failed-sample.log`：含 `Test Case '-[PurePaceUITests.RunFlowUITests testX]' failed (0.1 seconds).` 与 `Executed 1 test, with 1 failure (0 failures expected)`。
- `artifacts/no-failed-sample.log`：空日志（对照 infra 分支）。

复现命令（在 `artifacts/` 下执行，源库后直接调看门狗，1s 硬超时 + `sleep 30` 子进程）：

```bash
. ../../../../scripts/lib/ios-budget.sh
run_with_watchdog 1 product-watchdog.log bash -c 'cat "$1" >> "$2"; sleep 30' _ failed-sample.log product-watchdog.log \
  > product-watchdog.stdout 2> product-watchdog.stderr; echo rc=$?
run_with_watchdog 1 infra-watchdog.log bash -c 'cat "$1" >> "$2"; sleep 30' _ no-failed-sample.log infra-watchdog.log \
  > infra-watchdog.stdout 2> infra-watchdog.stderr; echo rc=$?
```

## 实际输出

产品失败分支（`artifacts/product-watchdog.stderr`、`artifacts/product-watchdog.rc`）：

```
test-ios: 阶段 xcodebuild-test 硬超时（1s），强制终止 PID ...
test-ios: 产品用例失败：硬超时前已执行用例中已有 failed（摘要见下），归口产品用例失败，不计为承载层预算
Test Case '-[PurePaceUITests.RunFlowUITests testX]' failed (0.1 seconds).
Executed 1 test, with 1 failure (0 failures expected) in 0.2 (0.2) seconds
test-ios: 硬超时：墙钟已用 1s ≥ 腿预算 1s（硬超时归因于已出现的失败用例）
test-ios: 超时前已执行的测试摘要：
...
```

- 不含「未进入产品断言」；rc=124（`product-watchdog.rc`）。

infra 分支（`artifacts/infra-watchdog.stderr`、`artifacts/infra-watchdog.rc`）：

```
test-ios: 阶段 xcodebuild-test 硬超时（1s），强制终止 PID ...
test-ios: runner bootstrap 挂起：xcodebuild test 在 1s 硬超时前未完成（未进入产品断言）
test-ios: 承载层硬超时：墙钟已用 1s ≥ 腿预算 1s，归口承载层预算/硬超时
test-ios: 超时前已执行的测试摘要：
```

- `ios.yml` 的 `infra_pattern` 依赖的「runner bootstrap 挂起」原文保留；rc=124（`infra-watchdog.rc`）。

## 单测覆盖（L1）

`bash scripts/tests/test-ios-budget.sh` 新增断言（断言只增不删，39 项 0 失败）：

- `ios_log_has_failed_test_case`：命中 `Test Case ... failed`、命中 `Executed N tests, with 1 failure`；空日志与 `with 0 failures` 不命中。
- `run_with_watchdog` 超时 + 同日志 failed → rc=124、不含「未进入产品断言」、点名 `testX` 与 `with 1 failure`、保留「阶段 xcodebuild-test 硬超时」与「超时前已执行的测试摘要」。
- `ios_timeout_classification_message`：无 failed → `归口承载层预算`；有 failed → `产品用例失败` 且不含 `归口承载层预算`。
- `scripts/test-ios.sh` 两处 124 分支均调用同一分类函数（count=2）。

## 预算依据（不抬高默认值）

- run `42755648335`（`3762aae`）attempt1 总 587s、UI 单腿 497s。
- `IOS_XCODEBUILD_TIMEOUT` 默认 600s：占用 497/600 ≈ 82.8%，余量 103s（≥100s）。
- attempt 预算仍为 `2700 − 900 = 1800s`，未改动；本轮不以抬高预算掩盖失败。

## UI 起点距离去竞态

`ios/PurePaceUITests/RunFlowUITests.swift` 的 `testRunPauseResumeFinishAndHistory`：
`startedDistance` / `startedElapsed` 与 `XCTAssertEqual(startedDistance, "0.00 km", "开跑起点距离必须为零")`
全部前移到 `start.tap()` 之前；tap 之后只保留 `waitForFirstLocationSample(distance:baseline:)`
（基线传入 tap 前读数）与时长增长探针；未引入固定 sleep、未弱化断言、其余 3 个用例未改。

本地 UI 腿持锁串行 2 次（锁 `/tmp/purepace-ios-gate.lock`，`xcodebuild test … -only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory`，
`CODE_SIGNING_ALLOWED=NO`、destination `iPhone 16 / iOS 18.6`）：

| run | rc | 日志 | 结论 |
|---|---|---|---|
| 1 | 0 | `.build/logs/ui-runflow-race-1.log` | `** TEST SUCCEEDED **`，Executed 1 test, with 0 failures（用例 40.208s，含构建 56s） |
| 2 | 0 | `.build/logs/ui-runflow-race-2.log` | `** TEST SUCCEEDED **`，Executed 1 test, with 0 failures（用例 37.190s，40s 全程） |

其余受影响腿：`bash -n scripts/lib/ios-budget.sh scripts/test-ios.sh scripts/tests/test-ios-budget.sh`、
`bash scripts/tests/test-ios-budget.sh`（39 项 0 失败）、`bash scripts/check-ios-scripts.sh`（29 项 0 失败）、
`bash scripts/check-shell-expansion.sh`（7 项 0 失败）、`bash scripts/test-ios.sh --unit-only`（rc=0，单测 6s / RunCore 13s，total 25s）。
未重跑全量模拟器门。
