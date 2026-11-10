# UI 起点距离断言去竞态 + 硬超时归口条件分类

## 范围

1. **UI 起点距离断言去竞态**（`ios/PurePaceUITests/RunFlowUITests.swift`，仅 `testRunPauseResumeFinishAndHistory`，失败点 `:81`）
   实测：同一 `RunFlowUITests` 在未改测试代码的 `40f32a98` 上全绿（run `42757446045`），在 `3762aae` 上红在 `XCTAssertEqual("0.01 km", "0.00 km")`（run `42755648335`）。根因是 `start.tap()` 与 1Hz 确定性定位注入之间的竞态：tap 后、读 `run.distance` 前已进入一个定位样本。
   修法：**在 `start.tap()` 之前**读取并断言距离基线（此时跑步未开始，读数确定为零），把该基线交给首样本探针；删除「tap 后读值再断言等于 `0.00 km`」的竞态读法。断言不得弱化为范围/容差/集合放行，不得删除零值断言，不得引入固定 `sleep`。
2. **硬超时归口条件分类**（`scripts/lib/ios-budget.sh`，超时分支 `:88-104`）
   现状 `:96` 无条件输出「runner bootstrap 挂起……（未进入产品断言）」，与同日志「超时前已执行的测试摘要」里的 `failed` 用例自相矛盾，会把真失败按 infra 放行（`ios.yml` 的 `infra_pattern` 命中 `runner bootstrap 挂起` → 重试）。
   修法：超时分支按同日志测试摘要**条件分类**——摘要中已出现 failed 用例则归口「产品用例失败」，不输出 infra 触发措辞；未出现 failed 才走原 infra 归口。超时判定（墙钟差额）、退出码 124、子进程退出码透传一律不变。
3. **调用方 124 文案一致性**（`scripts/test-ios.sh` 单测腿/UI 腿 124 分支）
   同一次超时的最终归口行（「归口承载层预算，不计为产品用例」）必须复用第 2 条的分类结果，避免同一日志自相矛盾；只改文案选择，不改 124 判定、不加 `continue-on-error`、不吞退出码。
4. **UI 腿预算取值给依据**（不改默认值）
   本轮实测：attempt1 总耗时 587s、单腿 UI 497s。现有 `IOS_XCODEBUILD_TIMEOUT` 默认 600s / attempt 预算 1800s 对实测仍有 ≥100s 余量，故**不调预算**；依据写入本文件与交付 digest。

## 验收

- ac-ui-zero-baseline-before-tap: `testRunPauseResumeFinishAndHistory` 中 `run.distance` 的零值断言发生在 `start.tap()` **之前**（读取并 `XCTAssertEqual(..., "0.00 km")`）；tap 之后不再出现「读距离后与 `"0.00 km"` 相等」的断言。
- ac-ui-zero-semantics-preserved: 起点距离必须为零的断言语义不弱化——不删除该断言、不改成范围/容差/集合放行、不改成「允许 0.00 或 0.01」；断言条数与失败信息仍点名「距离必须为零」。
- ac-ui-no-fixed-sleep: 修复不引入固定 `sleep(`/`Thread.sleep`/以固定等待窗口作为成功判据；首样本仍由谓词式 `waitForFirstLocationSample`（`distance.label != baseline`）判定。
- ac-ui-first-sample-probe-intact: tap 前取得的基线作为 `baseline` 传入首样本探针；探针超时（10s）仍会失败并落 `location-probe-failed` 诊断，注入链路未投递样本时不会误绿。
- ac-ui-scope-one-case: `RunFlowUITests.swift` 其余 3 个用例（`testRunProducesTelemetryAcrossKilometerBoundary` / `testStartFinishExportGPXArtifact` / `testAnnouncementTogglePersistsAcrossRelaunch`）与其他测试文件零改动（`git diff` 仅落在目标用例区间）。
- ac-timeout-product-failure: 构造样例日志（含 `Test Case '-[...]' failed` 或 `Executed N tests, with 1 failure`）走 `run_with_watchdog` 硬超时 → 输出**不含**「未进入产品断言」，**含**产品用例失败归口（点名 failed 用例/失败数），仍打印「超时前已执行的测试摘要」与「阶段 xcodebuild-test 硬超时」，返回值仍为 124。
- ac-timeout-infra-preserved: 日志无 failed 用例时硬超时 → 仍输出「阶段 xcodebuild-test 硬超时」与「runner bootstrap 挂起」原文（`ios.yml` 的 `infra_pattern` 依赖不变），并追加承载层预算口径，返回值 124。
- ac-timeout-exit-code: 超时仍返回 124；非超时子进程退出码原样透传（`exit 65` → 65）；无 `|| true` / `continue-on-error` / `allowed-failure` 吞退出码。
- ac-classification-reused-by-caller: `scripts/test-ios.sh` 两处 124 分支的最终归口文案与 `ios-budget.sh` 的分类结果一致（有 failed → 产品用例失败；无 failed → 承载层预算），同一日志不出现自相矛盾结论。
- ac-budget-not-raised: `IOS_XCODEBUILD_TIMEOUT` 默认仍为 600s、attempt 预算仍为 2700−900=1800s；未以抬高预算掩盖失败；预算依据（attempt1 587s / UI 腿 497s / 余量 ≥100s）写入交付 digest。
- ac-sample-artifacts-kept: 第 2 条的样例日志与 `run_with_watchdog` 实际输出（含归口行）落盘到 `.munk/changes/wi_intake_5bfc7f2e9537b5fa/artifacts/` 并在 digest 中引用路径与命令。
- ac-gate-affected-legs: 门只跑受影响腿并留证据——`bash -n scripts/lib/ios-budget.sh scripts/test-ios.sh`、`bash scripts/tests/test-ios-budget.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/test-ios.sh --unit-only`，以及持锁串行本地选择性跑 `RunFlowUITests/testRunPauseResumeFinishAndHistory` **2 次**均绿；不重跑全量模拟器门。

## 非目标

- 不改 `ios/PurePace`（App target）、`ios/project.yml`、`project.pbxproj`、`ios/RunCore`、`ios/Core`。
- 不改其他 UI/单元用例（含同一文件里 `testStartFinishExportGPXArtifact` 的同类 tap 后读基线写法——它无零值断言，不构成该失败）。
- 不改 `.github/workflows/ios.yml`（`timeout-minutes`、900s 重试门槛、`infra_pattern` 文本）、不扩 `infra_pattern`、不改 `check-ios-workflow.sh` 分类断言。
- 不引入 skip / `continue-on-error` / `allowed-failure` / 删断言 / 删腿 / 新增门腿；不改 `-only-testing`/`-skip-testing` 选择器与 `.munk/code-gates.json`。
- 不改超时判定算法与三级预算算术（墙钟差额、step−重试余量、腿取 min）；不重跑全量模拟器门；不扩工具链、不加第三方依赖。

## 实现约束

- **竞态修法锚点**（`ios/PurePaceUITests/RunFlowUITests.swift:78-84`）：`start.tap()` 之前 `let startedDistance = distance.label` 并 `XCTAssertEqual(startedDistance, "0.00 km", "开跑起点距离必须为零")`；tap 之后只保留 `waitForFirstLocationSample(distance:baseline:timeout:)` 与时长增长探针；`startedElapsed` 同法在 tap 前读取（时长零值已在 `:47` 断言，避免重复读造成同类竞态）。断言文案保留「开跑起点距离必须为零」。
- **分类判定锚点**（`scripts/lib/ios-budget.sh`）：在库内提供可单测的纯函数（建议 `ios_log_has_failed_test_case <log>`），匹配 `Test Case .*failed` 与 `Executed [0-9]+ tests?, with [1-9][0-9]* failures?`（`with 0 failures` 不得命中）；`run_with_watchdog` 超时分支据其分支输出，摘要行两分支都保留。
- **调用方锚点**（`scripts/test-ios.sh:561-563`、`:640-641`）：124 分支复用同一判定选择归口文案；不改 `return 124`。
- **样例构造**：用 `printf` 生成含 `Test Case '-[PurePaceUITests.RunFlowUITests testX]' failed (0.1 seconds).` 与 `Executed 1 test, with 1 failure (0 failures expected)` 的临时日志，配 `run_with_watchdog 1 <log> bash -c 'sleep 30'`（或伪造时钟单测路径）复现；样例与 stderr 落 `.munk/changes/wi_intake_5bfc7f2e9537b5fa/artifacts/`。
- **预算依据**：run `42755648335`（`3762aae`，attempt1 总 587s、UI 单腿 497s）与 run `42757446045`（`40f32a98`，全绿：104 单测 + 6 UI + 125 RunCore）。600s 上限占用 497/600 ≈ 82.8%，余量 103s；不调整。
- **UI 腿本地门**：先取 `/tmp/purepace-ios-gate.lock`（沿用 `scripts/test-ios.sh` 的 `mkdir` 原子取锁 + pid + 陈旧判定 + trap 释放；或 `PUREPACE_IOS_GATE_LOCK_HELD=1` 重入），再串行执行：
  `xcodebuild test -project ios/PurePace.xcodeproj -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -derivedDataPath .build/ios -only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory CODE_SIGNING_ALLOWED=NO`
  连续 2 次；两次日志落 `.build/logs/` 并在 digest 记录 `TEST SUCCEEDED` 与耗时。
- **既有单测兼容**：`scripts/tests/test-ios-budget.sh` 现有断言只增不删（空日志超时仍走 infra 分支，`ac-timeout-message-preserved` 继续通过）；新增「摘要含 failed → 产品失败归口」用例。
