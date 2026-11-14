# 回执：ios/Core 在 iOS 权威腿 0 执行修复

workItemId: wi_intake_581095048330a7bb

## 代码面

- `scripts/test-ios.sh`：新增 `test_with_core()`（缺包非零、测试失败保留原始退出码），
  两条正常分支（`xcodeproj` 存在 / `xcodegen` 生成）在 `test_with_run_core` 之后并列调用；
  降级分支原文案与语义不动；`[timing]` 追加 `core=` 段；Help 同步真实口径。
- `scripts/check-ios-scripts.sh`：新增 `test_ios_core_normal_branch_problems()`
  与 `ac-test-ios-core-normal-branch`，只在正常分支区域（锚点至首个 `exit 0`）要求
  `swift test --package-path ios/Core` 或调用其封装函数且函数体含该字面量；降级分支不计入。
  同 commit 带沙箱反例自检：删正常分支调用 → 红；保留调用但函数体换成 `true` → 红；未改副本 → 绿。

## 守卫两态证据（实际输出，日志见 `.munk/logs/`）

改前红（`git archive HEAD` 旧 `test-ios.sh` + 新守卫，日志 `.munk/logs/guard-before-red.log`）：

```
[FAIL] ac-test-ios-core-normal-branch:  正常分支（第 719 行起至首个 exit 0）缺少 'swift test --package-path ios/Core'（降级分支不计入）; 正常分支（第 725 行起至首个 exit 0）缺少 'swift test --package-path ios/Core'（降级分支不计入）;
EXIT=1
```

改后绿（日志 `.munk/logs/guard-after-green.log`）：

```
[PASS] ac-test-ios-core-normal-branch
[PASS] ac-test-ios-core-normal-branch (untouched sandbox green)
[PASS] ac-test-ios-core-normal-branch (self-test)
[PASS] ac-test-ios-core-wrapper-body (self-test)
38 项断言，0 项失败
EXIT=0
```

## 本地同口径实跑（日志 `.munk/logs/test-ios-local.log`）

- `bash scripts/test-ios.sh` 走正常分支（xcodeproj 存在），退出码 `0`。
- 正常分支实际执行 `info: 执行 swift test --package-path ios/Core`（日志第 15925 行，
  晚于 RunCore 第 15422 行，且无 `blocked:` 前置）。
- ios/Core 真实输出：
  - `Test Suite 'RunLayoutSamplingPolicyTests' ... Executed 11 tests, with 0 failures`
  - `Test Suite 'All tests' ... Executed 20 tests, with 0 failures (0 unexpected)`
- `[timing] boot=0s prep=3s build=14s unit=9s ui=477s runcore=14s core=11s total=535s`

## 其他本地门

- `bash scripts/check-ios-scripts.sh`：38 项断言 0 失败，退出 0。
- `bash scripts/check-ios-shell.sh --self-test`：102 项断言 0 失败，退出 0。
- `bash scripts/check-baseline.sh`：29 项断言 0 失败，退出 0。

## 口径与边界

- `docs/verification-matrix.md` 无该接缝行，零改动、行数口径不变。
- 未改 `.github/workflows/**`、`ios/PurePace/**`、`ios/Core/Sources/**`、`ios/RunCore/Sources/**`、`VERSION`；
  无 `continue-on-error`、无超时/预算阈值调整、无 skip/xfail。
- 本项只证明本地正常分支实跑到 Core；该腿在 CI 是否真执行 Core 需由合入后的下一次
  CI run 复核（查看 test 步日志中的 Core `Executed N tests` 行）。本会话不 watch/轮询 CI。
