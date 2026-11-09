# iOS CI 转绿：默认 UI 腿显式排除真机取证套件 DeviceFlowUITests

## 范围

main@`4e66ab9` 的 ios run 42603245651 红（47m26s）。根因：`ios/PurePaceUITests/DeviceFlowUITests.swift`（4 条真机/分阶段取证用例）被编进 `PurePaceUITests` 目标，而默认 CI UI 腿以 `-only-testing:PurePaceUITests` 整包执行 → 4/4 确定性失败并撞满 600s 预算（attempt1 exit 124，重试被预算跳过）。同 sha 单测 77/0、android 绿，无业务回归。

只做一件事：`scripts/test-ios.sh` 的默认 UI 腿显式 `-skip-testing:PurePaceUITests/DeviceFlowUITests`，且选择器在 **usage 帮助文本 / echo 行 / 实际 xcodebuild 参数** 三处一致。单元腿（`-only-testing:PurePaceTests`）保持不变。

## 验收

- ac-diff-single-file: `git diff --name-only origin/main...HEAD` 的输出只含 `scripts/test-ios.sh` 一个路径
- ac-skip-in-xcodebuild-args: `scripts/test-ios.sh` 中 UI 腿的 `xcodebuild test-without-building` 参数块同时含 `-only-testing:PurePaceUITests` 与 `-skip-testing:PurePaceUITests/DeviceFlowUITests`（同一次调用内）
- ac-skip-in-echo: UI 腿的 `echo "info: xcodebuild ..."` 行含 `-skip-testing:PurePaceUITests/DeviceFlowUITests`，且与 `-only-testing:PurePaceUITests` 在同一行
- ac-skip-in-usage: `usage()` 文本中 `-only-testing:PurePaceUITests` 那一行（或其紧邻续行）含 `-skip-testing:PurePaceUITests/DeviceFlowUITests`
- ac-unit-leg-unchanged: 单元腿仍为 `-only-testing:PurePaceTests`，且其参数块内**不含** 任何 `-skip-testing:`
- ac-check-scripts-green: `bash scripts/check-ios-scripts.sh` 全绿（其 `ac-test-ios-simulator-preparation` 顺序锚点要求 `-only-testing:PurePaceTests` 行先于 `-only-testing:PurePaceUITests` 行；skip 行必须加在后者之后，不得移动/合并这两行）
- ac-no-ci-weakening: `.github/workflows/ios.yml`、`scripts/test-ios.sh` 均未引入 `continue-on-error` / allowed-failure，未删腿，未抬高 600s 预算或任何超时字面量，未弱化断言
- ac-device-suite-intact: `ios/PurePaceUITests/DeviceFlowUITests.swift` 保持 4 条用例原样，仍由 `scripts/verify-ios-device-flow.sh` 分阶段驱动

## 非目标

- 不修改 `ios/PurePaceUITests/DeviceFlowUITests.swift`、`scripts/verify-ios-device-flow.sh`
- 不修改 `docs/**`（含 `device-assertion-matrix.md`、prd）
- 不修改 `ios/project.yml`、`Info.plist`、`.github/workflows/**`
- 不迁移 Bundle ID（`sh.munk.purepace` 另立项）
- 不改音乐源策略
- 不删除 `wip/wi_0384603f-pending` ref，不动其它分支或远端 ref
- 不在本地长跑重 UI E2E；不以抬预算/删腿/降断言换绿

## 实现约束

- 单点窄修：只改 `scripts/test-ios.sh` 一个文件。
- 现成补丁已存在：`refs/heads/wip/wi_0384603f-pending` 的 stash 提交 `d92d3fc`（其 base 为 `9693f0d`，与当前 HEAD 的 `scripts/test-ios.sh` 完全一致）。取该 hunk 的唯一安全方式：

  ```bash
  git diff 9693f0d d92d3fc -- scripts/test-ios.sh | git apply -
  # 或：git checkout d92d3fc -- scripts/test-ios.sh
  ```

  **禁止** `git checkout wip/wi_0384603f-pending` / 整分支 cherry-pick / merge：该 ref 含 `artifacts/device-audit/**`、`.munk/changes/**` 等大量无关文件。
- 三处必须一致（补丁已保证）：
  1. `usage()` 第 16 行区：`2) -only-testing:PurePaceUITests -skip-testing:PurePaceUITests/DeviceFlowUITests（…；` + 续行说明「只由 verify-ios-device-flow.sh 分阶段驱动，不进默认 CI UI 腿」
  2. UI 腿 `echo "info: ..."`（原第 457 行区）：插入 `-skip-testing:...` 于 `-only-testing:PurePaceUITests` 之后、`-scheme` 之前
  3. 实际参数块（原第 464 行 `-only-testing:PurePaceUITests \` 之后）：新增一行 `-skip-testing:PurePaceUITests/DeviceFlowUITests \`
- 冲突风险低但必须保序：`scripts/check-ios-scripts.sh` 用
  `^[[:space:]]*-only-testing:PurePaceUITests[[:space:]]*\\?[[:space:]]*$` 定位顺序锚点，因此 `-only-testing:PurePaceUITests \` 必须独占一行、skip 行紧随其后，不可写成同一行或调换顺序。
- 重试路径复用同一函数 `test_with_xcodebuild`，选择器天然一致，不需额外改动。
- 本地快门只跑快门：`bash -n scripts/test-ios.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-baseline.sh`、`bash scripts/check-ios-workflow.sh`、`bash scripts/check-shell-expansion.sh`；重 UI E2E 交 CI。
- 交付：推分支，由 Host 合入 main；CI 结果由 guard 观测，**禁止** `gh run watch` / `sleep` 轮询。
- 已归档原始失败证据：`projects/ops_75c530285b695ccb/.munk/runs/trun_20f6a7dd0ef179b2/digest.md`。
