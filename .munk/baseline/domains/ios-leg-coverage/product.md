# Domain: ios-leg-coverage

iOS 权威腿的覆盖完整性子域：只回答「脚本正常分支是否真的跑到了每一层测试」，并用结构守卫拦住「缺席而绿」。脚本入口/退出码/`blocked:` 文案契约归 `repo-baseline`，`ios/Core` 包内容与 L1 用例归 `ios-core`，权威腿拓扑与预算归 `ios-ci-stability` / `ios-ci-budget`；本域只持有覆盖结论与守卫判据。

## 范围

- `scripts/test-ios.sh` 正常/主分支共两条：`ios/PurePace.xcodeproj` 存在；或 `ios/project.yml` 存在且本机有 `xcodegen`（`xcodegen generate` 后继续）。两条分支在 `test_with_xcodebuild` → `test_with_run_core` 之后并列调用 `test_with_core()`，任一失败即整体非零退出并保留原始退出码。
- `test_with_core()` 语义：`ios/Core` 目录缺失时显式报错并返回非零（不得静默成功）；否则真实执行 `swift test --package-path ios/Core`，失败打印退出码后透传。
- 降级分支（工程与 xcodegen 均不可用）语义与文案保留：仍输出 `blocked:` 并真实执行 `swift test --package-path ios/Core`；但降级分支不得顶替正常分支的覆盖要求。
- `[timing]` 汇总行追加 `core=` 段（与 `runcore=` 并列）；`--help` 用法段按「两个分支都会执行 RunCore 与 Core」的真实口径描述。
- `scripts/check-ios-scripts.sh` 新增结构守卫：`test_ios_core_normal_branch_problems()` + 断言 `ac-test-ios-core-normal-branch`。锚点为 `if [ -d "$project_path" ]` 与 `if [ -f "$spec_path" ] && command -v xcodegen` 两行，各截取到其后首个 `exit 0` 的区域（即正常分支区）；区域内必须直接出现 `swift test --package-path ios/Core`，或调用 `test_with_core` 且该函数体含同一字面量；两处锚点缺任一即判红。
- 反例自检：同一次运行在 `mktemp -d` 沙箱副本内做三态验证——未改副本必须判绿；删掉正常分支的 `test_with_core` 调用行（保留降级分支入口）必须判红；保留调用但把函数体 `swift test --package-path ios/Core` 换成 `true` 必须判红。反例只改沙箱副本，不靠改仓库生产脚本才变红。
- 证据落点：Core 腿真实输出（SwiftPM `Executed N tests, with M failures` 原文）与守卫两态输出随回执留档（`.munk/logs/`）。

## 验收

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

## 非目标

- 不改产品功能、不改 `ios/PurePace/**` 生产代码、不改 `ios/Core/Sources/**` 与 `ios/RunCore/Sources/**`。
- 不改 `VERSION`、不改版本同步/发布口径（`scripts/sync-ios-version.sh`、TF/上传脚本）。
- 不动 `.github/workflows/**`（尤其不删既有腿、不改 step 结构、不改成只在 workflow 里额外跑 Core 来绕过脚本）。
- 不加 `continue-on-error`、不提高任何超时/预算阈值、不把重 UI 腿改成 `--unit-only`、不把测试改成 skip/xfail、不减少断言数量。
- 不重构 `scripts/test-ios.sh` 的分支/看门狗/分段结构，不顺手改其他脚本或 UI 测试稳定性约定。
- 不在 `docs/verification-matrix.md` 新增接缝行，也不改 `DocsVerificationMatrixTests` 的接缝清单。
- 不在本会话内 watch/轮询 CI，不做发布/分发。

## 实现约束

- 执行落点：沿用现有封装风格，在 `test_with_run_core()` 旁新增同构 `test_with_core()`，由两条正常分支在其后调用；`ios/Core` 是必存在的 SwiftPM 包，缺包按既有 `blocked:` 口径显式说明并非零返回，不得静默成功。
- 降级分支逻辑与文案保留，只允许在不改变语义的前提下对齐 Help/注释措辞。
- 守卫落点：不弱化既有 `ac-test-ios-xcodebuild-path`（全文件字面量契约）与 `test_ios_preparation_problems()`；新增独立 `test_ios_core_normal_branch_problems()`，锚点区域截断用首个 `exit 0` 界定，函数体抽取以 `test_with_core() {` 到行首 `}` 为界，与既有 self-test 的 `pass`/`fail` 口径一致。
- 反例只作用于 `mktemp -d` 沙箱副本并在用后 `rm -rf`；不得在仓库内落地临时夹具。
- 失败语义：Core 腿失败保留原始退出码；不新增 `set +e`、不新增 `|| true`、不加 retry。
- 证据口径：只报真实 `swift test` 的 `Executed N tests` 与失败数原文、守卫 `[PASS]`/`[FAIL]` 行与断言计数；不得以本地绿替代远端 CI run，不得出现「CI 通过 / 真机已验证」。

## 最近交付证明

- workItemId: wi_intake_581095048330a7bb（2026-11-15，pass）
- 交付：`scripts/test-ios.sh` 新增 `test_with_core()`（缺包非零、失败透传原始退出码），两条正常分支在 `test_with_run_core` 之后并列调用；降级分支原文案与语义不动；`[timing]` 追加 `core=` 段；`--help` 同步真实口径。`scripts/check-ios-scripts.sh` 新增 `test_ios_core_normal_branch_problems()` 与 `ac-test-ios-core-normal-branch`，只在正常分支区域（锚点至首个 `exit 0`）要求 Core 调用或含该字面量的 `test_with_core` 函数体，降级分支不计入；同 commit 带三态沙箱反例自检（删调用 → 红；函数体换 `true` → 红；未改副本 → 绿）。
- 验证：`code_gates` 23 门 attempt 001 全绿。本地 `bash scripts/test-ios.sh` 走正常分支退出 0，日志出现「执行 swift test --package-path ios/Core」且无 `blocked:` 前置，Core 输出 `RunLayoutSamplingPolicyTests Executed 11 tests, with 0 failures`、`All tests Executed 20 tests, with 0 failures`，`[timing] … runcore=14s core=11s total=535s`；`check-ios-scripts.sh` 38 项断言 0 失败、`check-ios-shell.sh --self-test` 102 项 0 失败、`check-baseline.sh` 29 项 0 失败。守卫两态：旧 `test-ios.sh` + 新守卫判红（点名两处正常分支缺 Core 调用，`EXIT=1`），修好后判绿。
- 边界 / 有意未做：`docs/verification-matrix.md` 无该接缝行，零改动、行数口径不变；未改 `.github/workflows/**`、`ios/PurePace/**`、`ios/Core/Sources/**`、`ios/RunCore/Sources/**`、`VERSION`，无 `continue-on-error`、无阈值调整、无 skip/xfail。本项只证明本地正常分支实跑到 Core；CI 是否真执行 Core 需由合入后下一次 CI run 的 test 步日志复核，会话内未 watch/轮询。
