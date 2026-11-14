# 修复 ios/Core 在 iOS 权威腿里 0 执行：test-ios.sh 正常分支并列执行 Core，并加结构守卫

## Scope

CI 实证缺口（`ios@2873ae2/707da7f`）：`.github/workflows/ios.yml` 的 `test` 步只跑 `bash scripts/test-ios.sh`，而 `scripts/test-ios.sh` 中的 `swift test --package-path ios/Core` 只出现在**降级分支**（`blocked:` 之后，约 744–751 行）；正常分支（`if [ -d "$project_path" ]` 与 `project.yml + xcodegen` 两处，约 719–731 行）只调 `test_with_xcodebuild` 与 `test_with_run_core`，从不执行 ios/Core。因此 `ios/Core/Tests/PurePaceCoreTests/RunLayoutSamplingPolicyTests.swift` 的 11 条断言在权威腿里 0 执行，「全绿」属于缺席而绿。

本项做三件事（不改产品功能、不改 VERSION、不改 UI、不动 workflow）：

1. **执行面**：`scripts/test-ios.sh` 的正常/主分支（xcodeproj 存在、以及 xcodegen 从 `ios/project.yml` 生成工程两条路径）都执行 `swift test --package-path ios/Core`，与该处已有的 `test_with_run_core` 并列；任一失败即整体非零退出（不加 `continue-on-error`、不加长任何超时、不改成「只在缺失时跑」）。降级分支保留现有语义（`blocked:` + `swift test --package-path ios/Core`），但 Core 不得只有降级分支这一个执行入口。日志保留 SwiftPM 真实的 `Executed N tests` 与失败数原文。
2. **守卫**：`scripts/check-ios-scripts.sh` 增加结构断言——`scripts/test-ios.sh` 的正常/主分支必须包含执行 `swift test --package-path ios/Core` 的调用（仅全文件出现一次不再算通过，降级分支不能顶替），缺失即判红；并在同 commit 附反例自检（沙箱副本删掉正常分支那条调用 → 守卫判红；未删 → 判绿），反例只改沙箱副本、不靠改生产代码才变红。同时贴出「改前守卫红 / 改后守卫绿」两态证据。
3. **本地同口径实跑**：本地跑一次 `bash scripts/test-ios.sh`，把 ios/Core 的真实 `Executed N tests`（RunLayoutSamplingPolicyTests 11 条在内）与 0 失败写进回执；并在回执明确：该腿是否真正在 CI 跑到 Core，需由下一次 CI run 复核（会话内不 watch/轮询 CI）。

`docs/verification-matrix.md`：当前无该接缝行（接缝列无 test-ios/Core 相关条目），因此**零改动**；若实现时确认已有该行，只更新自己那几行的「断言/证据」列，不新增行、不改行数口径。

## Acceptance Criteria

- ac-core-runs-on-normal-branch: 当 `ios/PurePace.xcodeproj` 存在、或 `ios/project.yml` 存在且本机有 xcodegen、脚本走正常分支时，`bash scripts/test-ios.sh` 的实际执行路径中包含一次 `swift test --package-path ios/Core`（日志出现该命令与 SwiftPM 输出的 `Executed N tests` 行），且该调用出现在脚本正常分支区域、早于降级分支的 `blocked:` 输出行。
- ac-core-failure-fails-run: 正常分支里 Core 的 `swift test` 返回非零时，`scripts/test-ios.sh` 整体非零退出（不吞错、不提前 `exit 0`），且脚本中不存在 `continue-on-error`、不存在把 Core 调用放到 `|| true` / `if ...; then :` 之类会掩盖失败的写法。
- ac-run-core-still-runs: 正常分支的 `test_with_run_core`（`ios/RunCore`）语义不变，仍按原顺序/原失败语义执行；新增 Core 腿不删除、不禁用、不短路 RunCore 腿。
- ac-degrade-branch-kept: 工程与 xcodegen 都不可用时仍输出 `blocked:` 并执行 `swift test --package-path ios/Core`（降级语义保留），但守卫判定不得把降级分支视为满足正常分支要求。
- ac-guard-normal-branch-structural: `bash scripts/check-ios-scripts.sh` 对 `scripts/test-ios.sh` 做结构断言：正常分支区域（工程存在 / xcodegen 生成两条路径的调用区，或其中一个被正常分支调用的封装函数）必须含 `swift test --package-path ios/Core` 的调用；缺失即非零退出并打印缺失原因。断言不得退化为「全文件 grep 到该字面量即通过」。
- ac-guard-counterexample: 该守卫自带反例自检：在 `mktemp` 沙箱副本里删掉正常分支的 Core 调用行（或整个 Core 封装函数调用），守卫必须判红；未删的副本判绿。反例不改仓库内生产脚本/源码即可触发，且断言非恒真。
- ac-guard-before-after-evidence: 回执贴出守卫两态证据：在未修 `test-ios.sh` 的版本上（新守卫 + 旧脚本）判红（点名缺正常分支 Core 调用），在修好后的版本上判绿；两态由脚本实际输出/日志留存，不是描述性断言。
- ac-no-collateral-changes: `git diff --name-only` 不含 `.github/workflows/**`、`ios/PurePace/**`（App 生产源码）、`ios/Core/Sources/**`、`ios/RunCore/Sources/**`、`VERSION`；既有断言阈值、`IOS_XCODEBUILD_TIMEOUT`(≤600) 与各腿预算值不变；无测试被改为 skip/xfail；`docs/verification-matrix.md` 的行数口径不变（本项若无需修改则文件零改动）。
- ac-local-gates-green: 本地 `bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-shell.sh --self-test`、`bash scripts/check-baseline.sh` 全部退出 0；`bash scripts/test-ios.sh` 实跑通过，回执含 ios/Core 的真实 `Executed N tests` 与 `0 failures`（RunLayoutSamplingPolicyTests 11 条在内），证据日志路径写入回执。
- ac-ci-recheck-note: 回执明确写出「本项只能证明本地腿跑到 Core；该腿在 CI 是否真执行 Core 需由合入后的下一次 CI run 复核（查看 test 步日志中的 Core `Executed N tests` 行）」，且会话内不 watch/轮询 CI。
- ac-commit-split: 提交按面拆分：`code`（`scripts/test-ios.sh` + `scripts/check-ios-scripts.sh` 及其反例）与 `fold`（回执/证据/必要的矩阵或文档收敛）分开，不混成一个大 commit。

## Non-Goals

- 不改产品功能、不改 `ios/PurePace/**` 生产代码、不改 `ios/Core/Sources/**` 与 `ios/RunCore/Sources/**`。
- 不改 `VERSION`、不改版本同步/发布口径（`scripts/sync-ios-version.sh`、TF/上传脚本）。
- 不动 `.github/workflows/**`（尤其不删既有腿、不改 step 结构、不改成只在 workflow 里额外跑 Core 来绕过脚本）。
- 不加 `continue-on-error`、不提高任何超时/预算阈值、不把重 UI 腿改成 `--unit-only`、不把测试改成 skip/xfail、不减少断言数量。
- 不重构 `scripts/test-ios.sh` 的分支/看门狗/分段结构，不顺手改其他脚本或 UI 测试稳定性约定。
- 不在 `docs/verification-matrix.md` 新增接缝行，也不改 `DocsVerificationMatrixTests` 的接缝清单。
- 不在本会话内 watch/轮询 CI，不做发布/分发。

## Implementation Constraints

- 执行落点：`scripts/test-ios.sh` 现有两条正常分支（约 719–731 行，`test_with_xcodebuild` + `test_with_run_core`）各追加一次 Core 执行；建议沿用现有封装风格，在 `test_with_run_core()`（约 683–700 行）旁新增 `test_with_core()` 同构函数（`ios/Core` 是必存在的 SwiftPM 包：包目录缺失时按现有 `blocked:` 风格显式说明并返回非零或明确 blocked，取决于实现时对「缺包」的既有口径，不得静默成功），并在两条正常分支里调用 `test_with_core` 与 `test_with_run_core`；任一失败即非零退出，保留原始退出码。
- 降级分支（约 743–751 行）逻辑与文案保留；只允许在不改变语义的前提下对齐 Help/注释措辞（用法段 41–44 行「两个分支都会追加执行 RunCore」需同步为「两个分支都会执行 RunCore 与 Core」的真实口径）。
- 守卫落点：`scripts/check-ios-scripts.sh` 既有 `ac-test-ios-xcodebuild-path` 契约（约 162–184 行，目前只做全文件字面量）与 `test_ios_preparation_problems()`（约 187–297 行）。建议新增独立 `test_ios_core_normal_branch_problems()`：定位正常分支锚点（`if [ -d "$project_path" ]` 到首个 `exit 0`、以及 xcodegen 生成路径同样到 `exit 0`）或「正常分支调用的 Core 封装函数体」，在其中断言存在 `swift test --package-path ios/Core`；再配 `mktemp` 沙箱反例（删正常分支调用、删封装函数调用两种变体），与既有 self-test 的 `pass/fail` 口径一致。
- 只改 `.munk/changes/**` 之外的仓库文件属于实现阶段（Coding）；Intake 不写 `tech.md`、不预写代码。
- 证据：Core 腿日志建议与现有分文件日志并列（如 `.build/logs/test-ios.log` 或独立 `core` 段日志），保留 SwiftPM 原始 `Executed N tests, with M failures` 行；守卫两态输出留 `.munk/logs/`。
- 本地验收命令：`bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-shell.sh --self-test`、`bash scripts/check-baseline.sh`、`bash scripts/test-ios.sh`（本机 xcodeproj 由 xcodegen 生成，正常分支可达；`IOS_XCODEBUILD_TIMEOUT` 保持 600）。
