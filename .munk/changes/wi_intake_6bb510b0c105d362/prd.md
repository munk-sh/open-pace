# 修复 UI 权威腿覆盖率缺口：新增 *UITests 套件必须入枚举，ScreenshotEvidenceUITests 收进 CI

## Scope

`main@cd68997` 中 `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`（2 条用例、24 处 XCTAssert，产出 14 张截图与逐屏断言）既不在 `scripts/test-ios.sh` 的 `ui_call "runflow"` 也不在 `ui_call "evidence"` 的目标枚举里；`.github/workflows/ios.yml` 只跑 `scripts/test-ios.sh`，因此 600s 分段改造后该套件静默掉出权威腿（分段≠放宽要防的退化）。

本项做两件事：
1. **覆盖守卫**：把 `scripts/check-ios-scripts.sh` 里 `ui_call 计数 == 2` 的弱断言换成「`ios/PurePaceUITests/*UITests.swift` 中全部 XCTestCase 套件都必须在 `ui_call` 的 `-only-testing` 目标里」的全覆盖断言；确需只在本机跑的套件必须显式进 allowlist（`scripts/ios-ui-local-only-suites.txt`）且每条带非空理由。同时保留既有结构断言（每段一次 xcodebuild、每段 ≤600s、顺序门控、失败即停）。
2. **把 ScreenshotEvidenceUITests 收进 CI 权威腿**：新增浅色段 `testEvidenceScreensLight` 与深色段 `testEvidenceScreensDark` 两个 `ui_call`（第 3/4 段），每段仍 ≤600s，深色段前 `xcrun simctl ui <udid> appearance dark`、段后恢复 `light`（与 `scripts/capture-ios-screenshots.sh` 同口径）。
3. 同步 `scripts/check-ios-shell.sh` 的计数断言（用例数=2、XCTAssert 下限）与反例自检；更新仓库 `AGENTS.md` 测试稳定性约定与 `docs/verification-matrix.md` 对应行；顺带清理误入库的 `.DS_Store`。

## Acceptance Criteria

- ac-ui-suite-coverage-guard: `scripts/check-ios-scripts.sh` 枚举 `ios/PurePaceUITests/*UITests.swift` 中声明的全部 XCTestCase 套件类名，并逐个确认其类名出现在 `scripts/test-ios.sh` 的 `ui_call` 目标（`PurePaceUITests/<Suite>` 形式的 `-only-testing` 参数）里；缺任意一个即该门非零退出并打印缺失套件名。判定只依赖仓库内文件内容，不需构建或跑模拟器。
- ac-ui-coverage-guard-counterexample: 该门自带反例自检——把某个已入枚举的套件名从沙箱副本的 `ui_call` 目标中删掉，守卫必须判红（非零/含该套件名）；未删除时判绿。（证明守卫不是恒真断言。）
- ac-ui-allowlist-requires-reason: 允许 `scripts/ios-ui-local-only-suites.txt` 作为本机-only 套件 allowlist；文件不存在或只有注释/空行视为空 allowlist 且正常通过；每个非注释行的有效套件名必须同行或紧随带非空理由（如 `SuiteName | 理由` 或 `SuiteName # 理由` 结构），缺有效套件名或缺理由即判红。反例自检：沙箱内写入一条无理由条目必须判红。
- ac-screenshot-evidence-in-ci-leg: `scripts/test-ios.sh` 的 `ui_call` 段数为 4，其中一段的 `-only-testing` 目标含 `PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensLight`，另一段含 `PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensDark`；两段各自独立日志文件、各自一次 `xcodebuild`、各自受 `IOS_XCODEBUILD_TIMEOUT`(≤600) 看门狗约束；脚本正文不出现 `continue-on-error`，既有段与预算参数值不变。
- ac-dark-appearance-gated: 深色段的 `xcodebuild` 调用前存在 `xcrun simctl ui <udid> appearance dark`，且该段结束后（成功与失败路径均）把外观恢复为 `light`；恢复动作不得被失败即停短路跳过。证据：脚本结构断言 + 本地实跑日志中该段确实在 dark 外观下执行且段后 `appearance` 查询为 `light`。
- ac-ui-legs-fail-fast-order: 4 段按固定顺序执行（runflow → evidence → screenshot-light → screenshot-dark），任一段失败即停止后续段并保留原始非零退出码；既有结构断言（每段一次 xcodebuild、每段 ≤600s、顺序门控、失败即停）仍由 `scripts/check-ios-scripts.sh` 校验，注入违规样本必须判红。
- ac-screenshot-evidence-counters: `scripts/check-ios-shell.sh` 中新增 `ScreenshotEvidenceUITests` 的计数断言——用例数恰为 2、`XCTAssert` 出现次数 ≥ 24（口径：`grep -c 'XCTAssert'`，实值 24，下限按实值写入）；并各配一个反例自检：沙箱副本删掉一条 `func testEvidenceScreensDark` 或删掉全部 `XCTAssert` 行后，对应断言必须判红，且反例只改沙箱测试文件、不改生产代码。
- ac-docs-and-matrix-sync: 仓库 `AGENTS.md` 的「测试稳定性约定（iOS UI 腿）」更新为四段口径，并写明「新增 *UITests 套件必须进入 `ui_call` 枚举，否则必须进 allowlist 且带理由」及其与 600s 分段上界的关系（拆分≠放宽）；`docs/verification-matrix.md` 新增/更新对应行，包含 守卫 × 现状 × 断言名 × 反例 × 证据路径 × 归属项 六列内容。
- ac-local-verification-green: 本地 `bash scripts/check-ios-shell.sh --self-test`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-shell-expansion.sh` 全部退出 0；`.munk/code-gates.json` 仍为 22 门且全绿；用一次性 `bash scripts/test-ios.sh` 跑齐 4 段 UI（含新增 2 段），留存各段日志与 `Executed N tests` 摘要（证据路径写入矩阵）。
- ac-dsstore-untracked: `.DS_Store` 与 `.munk/.DS_Store` 从 git 索引移除（`git ls-files | grep -i ds_store` 为空），`.gitignore` 含 `.DS_Store` 规则；该清理为单独一个 chore commit，不改动脚本/工程行为。
- ac-no-production-change: `ios/PurePace/**` 无任何生产视图、identifier 或行为改动（`git diff --name-only` 不含 `ios/PurePace/`）。

## Non-Goals

- 不删/减任何 UI 用例、断言、段数；不提高 `IOS_XCODEBUILD_TIMEOUT` 或任何单段预算；不加 `continue-on-error`；不调既有断言阈值。
- 不改 `.github/workflows/ios.yml` 的 trigger 或步骤结构（仍只跑 `scripts/test-ios.sh`）；不做发布/分发动作。
- 不改 `ios/PurePace/**` 生产代码（反范围），不改 Android/Shared 侧。
- 不引入第三方依赖，不重写 `capture-ios-screenshots.sh` 的采集逻辑（只复用其外观口径）。
- 不把截图产物再刷新一遍（本项只保证已有套件进 CI 并跑绿）。

## Implementation Constraints

- 覆盖守卫落点：`scripts/check-ios-scripts.sh` 现有 `ui_call_count == 2` 分支（约 242–245 行）替换为全覆盖枚举；保留其前后既有的 `-only-testing`、预算参数、分文件日志（`xcodebuild-ui.log`/`xcodebuild-ui-2.log`，新增段需再分文件）、拆分≠放宽注释、看门狗与 `IOS_XCODEBUILD_TIMEOUT ≤600` 断言。
- 新增两段落在 `scripts/test-ios.sh` 的 `ui_call` 调用区（约 648–658 行），沿用 `ui_call <group> <log> <targets...>` 形态；深色段前后用 `xcrun simctl ui "$sim_udid" appearance dark|light`，口径与 `scripts/capture-ios-screenshots.sh:166 set_appearance` 一致；恢复必须放在失败也执行的位置（如 `ui_call ... || { restore; ui_status=$?; }` 或段后无条件 restore）。
- 日志文件：沿用 `.build/logs/xcodebuild-ui-N.log` 命名，新增段用 3/4 后缀；`check-ios-scripts.sh` 的分文件日志断言同步扩展。
- 计数断言落点：`scripts/check-ios-shell.sh` 中现有 `ui_source_selftest` / `drop_assertions` / `drop_ui_case` 附近（约 2013–2160 行）新增 `ScreenshotEvidenceUITests` 对应断言与两个反例；反例只在 `mktemp` 沙箱副本上操作。
- allowlist 文件路径固定 `scripts/ios-ui-local-only-suites.txt`；空文件/仅注释是合法正常态。
- 文档锚点：`AGENTS.md` 的「测试稳定性约定（iOS UI 腿）」段；`docs/verification-matrix.md` 现有「iOS UI 腿确定性（重启导航状态判据 + 600s 单腿预算）」行之后追加本项行，证据路径指向 `.munk/logs/` 下的实跑日志与 `.build/logs/` 摘要。
- 提交拆分：功能改动一个 commit；`.DS_Store` 清理单独 chore commit（顺序在后）。
- 无 work-set 上下文（`.munk/work-set/` 不存在），本项为独立 WorkItem，kind=bugfix。
