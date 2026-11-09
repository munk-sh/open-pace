# iOS CI 承载层分类补全 + 模拟器预热竞态根治

## 范围

本项只修 iOS CI 的**承载层分类**与**模拟器预热竞态**，不动任何 iOS 产品源码、测试断言或门禁强度。生产改动面仅两处；验收强制要求的表驱动断言落在一个既有脚本门本体（仅加强，不新增门）。

1. `.github/workflows/ios.yml`（`test` 步 `infra_pattern`，约 L66）：在现有承载层族基础上并列增补两个特征
   - `Application failed preflight checks`
   - `Failed to install or launch the test runner`

   两者与现有族同等进入「首次失败命中 → `simctl shutdown all` 重置 → 有界重试 1 次」分支；`run_attempt 1/2`、`timeout-minutes: 45`、`blocked:` 判失败口径均不变，重试后仍红即真红。

2. `scripts/test-ios.sh`（`prepare_simulator_for_ui_tests()` 的 `simulator-warmup` 段，约 L156–L164）：消除「`simctl launch` 后立即 `simctl terminate`」的拆进程窗口。
   - 采用**保留预热 + 终止后轮询确认进程消失**：`simctl terminate` 之后轮询 `xcrun simctl spawn "$sim_udid" launchctl list`，确认 `$bundle_id` 不再出现才返回 warmup；轮询有界（上限约 10s），超界打印 `simulator-warmup` 阶段失败并非零退出。
   - 不采用「直接删除 warmup」：`scripts/check-ios-scripts.sh`（既有门）断言 `test-ios.sh` 内含 `simctl launch` / `simctl terminate`；删除 warmup 会迫使改动第三个门脚本或削弱门禁，违背「不得降门禁」。轮询方案直接堵死 UTC 竞态窗口，且保留门禁断言。
   - 不使用裸 `sleep` 定时器糊、不使用无限重试。

3. 测试落点（验收强制，仅加强）：`scripts/check-ios-workflow.sh`（既有 `lint-ios-workflow` 门本体）
   - 在 `flaky_patterns` 表补入上述两个特征，使门禁要求 workflow 确实包含它们。
   - 新增表驱动断言：从 workflow 里提取**真实的** `infra_pattern='...'`，用与 CI 相同的 `grep -Eq` 语义求值：
     - 期望命中（承载层）：`Application failed preflight checks`、`Failed to install or launch the test runner`；
     - 期望不命中（非承载层，不重试）：`XCTAssert... failed` 行、`TEST FAILED` 行、带具体断言行（如 `RunFlowUITests.swift:NN: error: -[...] : XCTAssert...`）。
   - 加负向自检：从 workflow 中抹掉任一新增特征后，该表驱动断言必须非零退出。
   - 不新增 `.munk/code-gates.json` 门（保持现有门数），不新增第三方 action / 依赖，不新建文件类型。

## 验收

- ac-infra-preflight-pattern: `.github/workflows/ios.yml` 的 `infra_pattern` 对 `Application failed preflight checks` 返回命中（承载层）。
- ac-infra-runner-launch-pattern: `infra_pattern` 对 `Failed to install or launch the test runner` 返回命中（承载层）。
- ac-infra-existing-family-kept: 现有承载层族（`Timed out while loading Accessibility.` / `unknown to FrontBoard` / `Timed out waiting for AX loaded notification` / `Failed to initialize for UI testing` / `operation never finished bootstrapping` / `while preparing to run tests` / `runner bootstrap 挂起`）仍全部命中，未被替换或删除。
- ac-product-failure-not-infra: `infra_pattern` 对 `XCTAssert... failed` 断言行与 `TEST FAILED` 汇总行返回**不命中**（非承载层），因此产品断言失败不触发重试。
- ac-bounded-retry-once: `run_attempt` 仍为 `1`、`2` 两次序列，重试上限 1 次；无 `while true` / `until false` 无限重试；第二次仍红即 `exit` 非零。
- ac-no-gate-downgrade: `test` 步无 `continue-on-error` / `allowed-failure` / `-skip-testing`，`timeout-minutes` 不放大（≤45），未新增第三方 action；`.github/workflows/android.yml` 零改动。
- ac-warmup-no-race: `simctl terminate "$bundle_id"` 之后、`xcodebuild test` 之前，脚本轮询 `simctl spawn "$sim_udid" launchctl list` 直到 `$bundle_id` 消失才返回；源码中不存在「`terminate` 后立即进入 `xcodebuild`」的直线路径。
- ac-warmup-bounded: warmup 轮询有明确上界（约 ≤10s，有限迭代），超界打印 `simulator-warmup` 阶段失败并 `exit` 非零；不依赖裸 `sleep` 定时器、不无限重试。
- ac-warmup-keeps-gate-strings: `scripts/test-ios.sh` 仍含 `simctl launch` 与 `simctl terminate`，`bash scripts/check-ios-scripts.sh` 通过（未被削弱）。
- ac-classification-table-test: `scripts/check-ios-workflow.sh` 含表驱动分类断言，覆盖「两行原文 → 承载层」「XCTAssert 断言行 / TEST FAILED → 非承载层」，且负向自检（抹掉新增特征）会非零退出；`bash scripts/check-ios-workflow.sh` 退出 0。
- ac-local-gates-green: `bash scripts/test-ios.sh` 或等价路径跑通（`** TEST SUCCEEDED **` 或降级路径真实通过），且本地 `code_gates` 全绿；回执贴改动前后 warmup 相关命令与输出。
- ac-remote-two-green: 连续两次 push 触发的 `ios` run 均 `conclusion=success`；第二次日志可见重试机制未被误触（或按预期工作）。若两次期间偶发一次承载层红，须证明重试把该次拉回绿，并贴 run id 与日志行；未取得两次连续绿前不得写「已修复远端 CI」。
- ac-no-product-change: `ios/`、`Sources/`、`ios/project.yml`、`ios/Package.swift`、`ios/PurePaceUITests/**` 零改动（`git diff --stat` 可证）。
- ac-honest-wording: 回执只用「CI 绿 + 本地门绿」措辞；真机相关一律 `pending`；未绑定候选构建 sha256 前不写「真机已验证」；无 run id 不写「CI 已通过」。

## 非目标

- 不改 iOS 业务源码、测试断言、`ios/project.yml`、`ios/PurePace.xcodeproj`、`ios/Core`、`ios/RunCore`。
- 不删腿、不把 `test` 步骤降级为 `continue-on-error` / `allowed-failure`、不加长超时蒙过。
- 不动 `.github/workflows/android.yml`；不引入新第三方 action；不新增 `.munk/code-gates.json` 门。
- 不重构 CI 全局、不调整模拟器机型/系统（iPhone 16 / iOS 18.6）、不修 hosted runner 的 `simctl location` 投递差异。
- 不做真机签名、分发、Release；不推 tag。

## 实现约束

- 一手证据（CI 观测场 `trun_e034000970f2ac67`）：run `42560986821`（ios，main@`d0e8f22`）install/lint/build 全过，`test` 在 launch test runner 阶段被 `SBMainWorkspace` 拒（`Application failed preflight checks` / `BSErrorCodeDescription=Busy` / `Failed to install or launch the test runner`），exit 65，`PurePaceTests` 断言 0 条执行；`d0a8560..d0e8f22` 仅改 `.munk/`、`README.md`、`docs/`、`scripts/`，iOS 源码零改动，同源码 run `42553984559` 为绿。近 6 次 ios run 2 绿 4 红，4 次均承载层族。
- 竞态根因锚点：`scripts/test-ios.sh` L156–L164 的 warmup 是 `simctl launch` 后立即 `simctl terminate`，随后 `xcodebuild test` 以 `terminate_running_process = 1` 拉起同一 bundle；`SBMainWorkspace` 在拆进程窗口内返回 `Busy`。选择「保留 warmup + 有界轮询 launchctl list」而非删除 warmup，理由见「范围」第 2 条（删除会撞 `check-ios-scripts.sh` 的 `simctl launch`/`simctl terminate` 门禁断言）。
- `infra_pattern` 为 shell 单引号 ERE，新增特征用空格分隔字面量即可；保持与现有族并列（`|` 连接），不得混入产品断言措辞（`check-ios-workflow.sh` 的 `ac-test-bounded-retry-scope` 负向自检会拦「距离/开关/History/休整/run.distance」等词）。
- 表驱动断言应抽取 workflow 里**真实** `infra_pattern=` 行求值（与 CI 同一 `grep -Eq`），避免在测试里另写一份容易与生产漂移的平行正则。
- 远端 macOS runner 为 bash 3.2：参数展开一律 `${var}`，禁止 `$var` 紧邻全角字符；禁止依赖 GNU `timeout`；轮询用 `kill -0`/有限 `seq` 循环，禁止无限循环。
- 门禁口径：`scripts/check-ios-workflow.sh` 仅加强（补 `flaky_patterns` + 新表驱动用例 + 负向自测），不替换/放宽既有断言；`.munk/code-gates.json` 门数与 id 不变。
- 改动范围边界：生产编辑仅 `.github/workflows/ios.yml` 与 `scripts/test-ios.sh` 两处；`scripts/check-ios-workflow.sh` 是验收强制的「脚本级静态断言」落点（既有 `lint-ios-workflow` 门本体），属测试加强，不视为产品改动扩围。超出此三处即打回。
- 推送口径：push 只走 Delivery 阶段 Host 工具，只推本分支；不推 tag、不改 remote。
- 本项为显式规格直派（bugfix 快速通道）：Intake → Coding → code_gates → Delivery；`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 均为 `false`。
