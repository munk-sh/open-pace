# 补 docs/verification-matrix.md 的「iOS 权威腿是否真执行 ios/Core」接缝行（绑 CI run 43642162288 实证）

## Scope

`wi_intake_581095048330a7bb` 修掉了「文件里出现一处 `swift test --package-path ios/Core` 就算覆盖」的错读（该字面量原本只在降级分支，权威腿 0 执行却全绿），并在 `scripts/check-ios-scripts.sh` 新增 `ac-test-ios-core-normal-branch`（正常分支区域锚定 + 三态沙箱反例）。但 `docs/verification-matrix.md` 当时无该接缝行，该项按「无行可改」零改动，结论只存在于分片回执。

本项只做一件事：在 `docs/verification-matrix.md` **追加恰好 1 行**，把这处接缝的「现状 / 断言 / 反例 / 证据路径 / 归属项」落到矩阵里，并绑已实测的 CI 证据。不改任何断言、门、脚本、测试、产品代码。

已核实的 CI 实证（直接引用，不重跑 CI）：

- run `43642162288`（workflow `ios`，headSha `5925310999556285a7bb0ddee24ad5a65bcad913`，conclusion `success`；该 headSha 对应仓内 merge 提交 `5925310`「ios/Core 在 iOS 权威腿正常分支真实执行 + 结构守卫」）。
- test 步日志出现 `Compiling PurePaceCoreTests RunLayoutSamplingPolicyTests.swift` 与 `Test Suite 'RunLayoutSamplingPolicyTests'` 11 条用例全 passed，并有 `Test Suite 'All tests' passed`。
- 该步末行 `[timing] boot=211s prep=42s build=199s unit=44s ui=745s runcore=43s core=32s total=1144s`——`core=32s` 即 `swift test --package-path ios/Core` 的真实耗时段。
- 断言名：`ac-test-ios-core-normal-branch`；本机反例三态：删正常分支调用 → 红、函数体换 `true` → 红、未改副本 → 绿。

## Acceptance Criteria

- ac-matrix-exactly-one-row-appended: `git diff --numstat docs/verification-matrix.md` 为 `1 0`（仅新增 1 行、0 删除）；既有 27 条数据行逐字不变；不新增第二行、不改表头与分隔行。
- ac-matrix-row-six-columns: 新行以 `|` 开头结尾、按 `|` 切分后恰 8 段（6 列 + 首尾空段），6 个单元格 trim 后均非空；列序与表头 `| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |` 逐字对应；单元格内不含裸 `|`。
- ac-matrix-row-content: 「接缝」列为本项新接缝（`iOS 权威腿执行 ios/Core`，与既有已声明接缝名无子串互含）；「现状」列写明**正常分支并列执行** `swift test --package-path ios/Core`（与 `test_with_run_core` 并列）且**降级分支语义未动**；「断言名」列含 `ac-test-ios-core-normal-branch`；「反例」列写明三态（删正常分支调用 → 红、函数体换 `true` → 红、未改副本 → 绿）并附本地 `RunLayoutSamplingPolicyTests` 11 条实跑；「证据路径」列指向 ios CI run `43642162288` 的 test 步日志（含 `.munk/logs/` 归档截取文件名、或运行 URL + step 名），且包含 `core=32s` 这一实证时段；「归属项」列为 `wi_intake_581095048330a7bb`。
- ac-matrix-no-pending-and-no-gap: 新行不含 `pending: 待对应 item 回填`、不含 `缺口`、不含 `待补`；全文这两个标记的出现次数仍为 0（`DocsVerificationMatrixTests` 的 pending/缺口计数断言不受影响）。
- ac-matrix-structure-tests-green: `swift test --package-path ios/RunCore --filter DocsVerificationMatrixTests` 通过，覆盖用例 `testMatrixIsPureTableWithExpectedHeaderAndColumns` 与 `testMatrixCoversTenSeamsWithTenMeasuredRowsAndNoGap`；`swift test --package-path ios/Core` 通过（`RunLayoutSamplingPolicyTests` 11 条全绿）。
- ac-no-structure-test-change: `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift` 零改动；仓内不出现对矩阵行数 / 接缝总数的写死断言（不新增 `expectedRowCount`、不改 `seams` 清单）。
- ac-gates-green-and-scope-clean: `.munk/code-gates.json` 全部门退出 0；`git diff --name-only` 仅含 `docs/verification-matrix.md`（外加 `.munk/changes/**` 与本项 `.munk/logs/` 归档，后者被 `.munk/logs/.gitignore` 的 `*` 忽略不入库），不含 `scripts/test-ios.sh`、`scripts/check-ios-scripts.sh`、`ios/**`、`VERSION`、`.github/**`、`.munk/code-gates.json`、`docs/distribution/**`。
- ac-evidence-not-fabricated: 「证据路径」指向的日志是 run `43642162288` 的真实截取（经 `gh run view 43642162288 --repo munk-sh/open-pace --log` 抽取 test 步相关行后落 `.munk/logs/`），不是手写伪造；若无法取得日志，则只写运行 URL + step 名 + 引用上述数据，不虚构仓内文件路径；仓内不得放入整份日志。
- ac-commit-fold-only: 提交按面拆分，本项只落 `fold`（矩阵行 + 证据归档说明），不含 `code` 面改动，不与其他面混成一个提交。

## Non-Goals

- 不新增或修改任何断言、门、阈值；不动 `.munk/code-gates.json`。
- 不改 `scripts/test-ios.sh`、`scripts/check-ios-scripts.sh`、`scripts/check-ios-shell.sh`、其它脚本与 `AGENTS.md`。
- 不改 `ios/**`（含 `ios/Core`、`ios/RunCore`、`ios/PurePaceUITests`、`ios/project.yml`）与 `VERSION`。
- 不改 `.github/**`，不重跑、不 watch、不轮询 CI。
- 不动矩阵其它行，不改表头、不改分隔行、不重排表格。
- 不改 `DocsVerificationMatrixTests`，不写死行数或接缝条数。
- 不改产品代码与分发文档（`docs/distribution/**`、`docs/release/**`、`docs/device-manual-acceptance.md`）。

## Implementation Constraints

- 追加位置：文件末尾最后一条数据行之后（文件当前以换行结尾，共 27 条数据行），保持表格连续、不插空行。
- 逐字对齐列序：`接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项`；单元格内禁用裸 `|`（需要并列时用 `、` 或 `；`），避免列数被切断。
- 矩阵结构守护的硬约束（`DocsVerificationMatrixTests`，勿改该测试）：任一行含 `pending: 待对应 item 回填` 或 `缺口` 即判红——因此「现状」列描述历史时不得使用「缺口」二字（可写「此前无该接缝行」）。
- 接缝名选择需与既有已声明接缝无子串互含，否则会被「每条已声明接缝恰 1 行」的匹配逻辑误判（已声明接缝含 `iOS UI 腿确定性`、`UI 权威腿覆盖率守卫`、`地图壳`、`RDP 抽稀`、`隐私政策正文真源` 等）。
- 证据归档：`.munk/logs/.gitignore` 内容为 `*`，归档文件不入库；建议文件名 `.munk/logs/ci-run-43642162288-test-step.excerpt.log`，只保留 test 步中与 `ios/Core` 相关的行（`Compiling PurePaceCoreTests`、`Test Suite 'RunLayoutSamplingPolicyTests'`、`Executed N tests`、`Test Suite 'All tests' passed`、`[timing] ... core=32s`），严禁把整份约 1.6 万行日志放进仓库。
- 参考既有行文风格：同类行以「本项实测」开头并在现状列给出口径（参考 `docs/verification-matrix.md` 中 `UI 权威腿覆盖率守卫` 行与 `可安装 APK 产物与获取路径` 行）。
- 验收命令锚点：`swift test --package-path ios/RunCore --filter DocsVerificationMatrixTests`、`swift test --package-path ios/Core`、`bash scripts/check-baseline.sh`，以及 `.munk/code-gates.json` 其余门。
- 回执须给出「表头列数 = 新行列数」的实测证据（例如 `awk` 切分计数输出）与两条结构测试用例名的实跑输出。
