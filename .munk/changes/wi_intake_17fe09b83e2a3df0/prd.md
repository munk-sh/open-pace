# AX5 取证用例去掉顺序依赖（EvidenceCaptureUITests/testEvidenceAx5Layout 自给自足）

## Scope

只改 `ios/PurePaceUITests/EvidenceCaptureUITests.swift`（外加 `docs/verification-matrix.md` 一行与同 commit 证据日志）。
把"历史详情必须已有归档"的隐式前置，改成用例自给自足：

- 根因（已诊断，直接采信）：AX5 第 3 步 `-screenshotInitialTab history -screenshotOpenRunDetail` 依赖归档里已有跑次；
  `HistoryViewState.openFirstDetailIfNeeded`（`ios/PurePace/History/HistoryViewState.swift:71`）在 `summaries.first == nil` 时是 no-op，
  空容器下停在 `history.empty`，`runDetail.export` 等 30s 超时。建归档的只有同类 `testEvidenceTreesAndRealArchive`
  （`EvidenceCaptureUITests.swift:25-92`，实际 seed 段 26-64）与 `scripts/capture-ios-screenshots.sh` 的 `restore_archive`；
  `scripts/test-ios.sh` 先 `simctl uninstall` 再整包跑，且 XCTest 字母序让 AX5 排在 trees 之前 → 整包必红、单跑必绿。
- 交付物：seed helper 抽取 + AX5 详情步前按需调用 + 相邻 launch 间显式收尾 + 反例判红证据 + 验证矩阵新增行。

## Acceptance Criteria

- ac-seed-helper-extracted: `EvidenceCaptureUITests.swift` 中真实 seed 链路（`launchApp(["-uiTestLocation"])` → `run.start` → `run.elapsed >= "00:30"` → `run.finish` → `run.save` → `run.saved`）只存在一处实现（类内 `private` helper），`testEvidenceTreesAndRealArchive` 与 `testEvidenceAx5Layout` 共用；文件中 `waitForExistence` 等 `run.saved` 的断言出现次数为 1（无第二份内联复制）。
- ac-trees-behaviour-unchanged: `testEvidenceTreesAndRealArchive` 仍按 01→06 顺序产出同一组 `attachTree`（`01-run-not-started` / `02-run-running` / `03-run-finished` / `04-history-list` / `05-history-detail` / `06-settings`）与同 6 条 `recordPrimaryAction` 的 `evidence-primary` 打印，顺序与改前一致；该用例在干净容器下单独跑仍绿。
- ac-ax5-clean-container-green: 干净容器（`xcrun simctl uninstall <udid> <bundle>` 后全新安装、容器内无 `Documents/Runs`）下单独执行 `-only-testing:PurePaceUITests/EvidenceCaptureUITests/testEvidenceAx5Layout` 退出码 0；日志出现 4 条 `AX5-FIT screen=` 行，其中含 `screen=05-history-detail`（即确实进入了详情，而非停空态）。
- ac-ax5-conditional-seed-no-double-write: AX5 详情步前先判定归档是否存在（`history.row` 计数 ≥1 或 `history.empty` 出现，identifier 见 `ios/PurePace/History/HistoryView.swift:32,72`）；已有归档时**不**新建跑次（同容器连跑第二遍，日志出现跳过 seed 的可检索行，且容器 `Documents/Runs` 文件数不变）；归档为空时才调用 seed。
- ac-seed-no-reset-arg: seed 及其后所有 launch 的 `launchArguments` 均不含 `-uiTestResetArchive`（该字符串在 `EvidenceCaptureUITests.swift` 只出现在注释里，不进入任何 `launchApp([...])` 实参）。
- ac-explicit-terminate-between-launches: AX5 每次换新 `XCUIApplication` 之前都有显式 `app.terminate()`（含 seed 前后与第 4 步设置页之前）；用例内 `launchApp(` 调用数 - 1 ≤ `terminate()` 调用数，跨 launch 不残留上一进程状态。
- ac-assertions-only-added: 断言只增不减——`testEvidenceAx5Layout` 原有 4 处 `assertFitsAndNoOverlap` 与 4 处 `waitForExistence` 超时值（30 / 60 / 30 / 30）及"缺少…"失败文案逐字保留，`testEvidenceTreesAndRealArchive` 的 6 处 `XCTAssertTrue` 亦保留；不靠放宽超时或用例重排转绿。
- ac-counterexample-red-proof: 同 commit 内留"归档为空且不 seed"反例的判红记录：对修复后代码施加逆补丁（移除 AX5 的 seed 调用，等价于空容器无 seed）单独跑该用例，必须红，失败点停在 `runDetail.export` 30s 未出现；红日志与绿日志同 commit 落 `docs/evidence/ax5-order-independence/`（运行时副本另落 `.munk/logs/`）。
- ac-pack-leg: 同一容器内紧接执行整包（`-only-testing:PurePaceUITests`，或至少 `PurePaceUITests/EvidenceCaptureUITests` 两个用例按默认字母序）退出码 0，`testEvidenceTreesAndRealArchive` 与 `testEvidenceAx5Layout` 均通过；若受 25 分钟墙钟预算限制未能跑完，回执必须显式记"未跑整包"并列出未闭合点（不得静默缺失），此时本 ac 以"未闭合记录已落盘"判过。
- ac-verification-matrix-row: `docs/verification-matrix.md` 新增一行且六列齐备——接缝 / 现状 / 断言 / 反例 / 证据路径 / 归属项（归属项 = `wi_intake_17fe09b83e2a3df0`）；"证据路径"指向实际存在的日志或结果包。
- ac-no-production-change: `git diff --name-only` 不含 `ios/PurePace/**`（生产代码零语义改动，尤其 `RunStorage.swift`、`HistoryViewState.swift`、`HistoryView.swift`），identifier 冻结集不变；`.munk/code-gates.json` 无新增/修改条目，未新增 DEBUG 启动参数或测试脚手架。

## Non-Goals

- 不产出 C（12 屏复评截图）与确认层 2 张截图；本项只修取证腿前置。
- 不改 `scripts/capture-ios-screenshots.sh` 的产物命名、evidence 目录结构与阶段编排（`trees → screenshots → ax5`、`restore_archive` 快照机制）。
- 不动 A/B 已交付的地图壳、结束态轨迹预览/分段明细与 History 轻量索引代码。
- 不改生产代码（`RunStorage` / `HistoryViewState` / `HistoryView` / `RunLaunchArguments`），不新增门禁、不加测试脚手架、不改 CI workflow。
- 不靠"调整用例顺序 / 放宽超时 / 删除断言"把问题转绿；真机项（锁屏定位、音频实听、定位授权）仍归人现场，不在本项范围。

## Implementation Constraints

- 锚点（改前，行号以当前 HEAD 为准）：
  - `ios/PurePaceUITests/EvidenceCaptureUITests.swift:25-92`：`testEvidenceTreesAndRealArchive`，seed 链路在 26-64（`launchApp(["-uiTestLocation"])`、`run.start`、`waitUntil(timeout: 90) { run.elapsed >= "00:30" }`、`run.finish`、`run.save`、`run.saved`）。
  - 同文件 `:98-126`：`testEvidenceAx5Layout` 四次 launch（`:100` 首屏、`:107` `-autoStartRecording -screenshotRunFinished`、`:114` `-screenshotInitialTab history -screenshotOpenRunDetail`、`:121` `-screenshotInitialTab settings`）。
  - 同文件 `:130-146` `launchApp`、`:186-191` `attachTree`、`:193-197` `recordPrimaryAction`、`:203-256` `assertFitsAndNoOverlap`、`:258-267` `waitUntil`——helper 复用这些既有件，不新造平行工具。
  - `ios/PurePace/History/HistoryViewState.swift:71` `openFirstDetailIfNeeded` 在 `summaries.first == nil` 时 no-op（根因，禁改）；`ios/PurePace/History/HistoryView.swift:32` `history.row`、`:72` `history.empty`（空态判定锚点，禁改）。
- helper 形态（由 Coding 落地，粒度可微调，不变量固定）：把 seed 抽成 1 个或数个 `private` 步骤 helper（如 起跑→推进到 ≥00:30 / 结束→待保存 / 保存→`run.saved`），`testEvidenceTreesAndRealArchive` 在**原位置**组合它们，使 `attachTree` / `recordPrimaryAction` 的调用点与产出顺序逐字不变（可用闭包 hook 保留原调用点）。
- AX5 判定顺序固定：先做空/非空检测（`-screenshotInitialTab history` 的一次 launch，读 `history.row` 数或 `history.empty`）→ `app.terminate()` → 空则 seed（seed 内同样在结束时 `terminate()`）→ 再 `-screenshotInitialTab history -screenshotOpenRunDetail`。检测 launch 不得写入归档。
- seed 链路必须沿用 `-uiTestLocation`（确定性定位源，可产生真实采样距离），**不得**使用 `-screenshotHistoryDemo`（演示注入不落盘，不能冒充真实归档），**不得**带 `-uiTestResetArchive`。
- 保留"每屏 `attachTree` 落可及树"的取证语义：AX5 的四棵 `ax5-*` 树名与 trees 的六个树名均不改。
- 预算与取证口径：墙钟 ≤25 分钟、≤3M token，到点即停手交未闭合回执（已做 / 未做 / 已过门 / 未闭合点），不续命。两条腿命令示例（干净容器 → 单用例 → 同容器整包）：
  - `xcrun simctl uninstall <udid> com.chaxiu.purepace`（或工程实际 bundle id）→ `xcodebuild test-without-building -project ios/PurePace.xcodeproj -scheme PurePace -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath .build/ios -only-testing:PurePaceUITests/EvidenceCaptureUITests/testEvidenceAx5Layout CODE_SIGNING_ALLOWED=NO`
  - 紧接同容器：同上命令改为 `-only-testing:PurePaceUITests`（或 `-only-testing:PurePaceUITests/EvidenceCaptureUITests`）。
  - AX5 需先把系统字号调到 `accessibility-extra-extra-extra-large`（参照 `scripts/capture-ios-screenshots.sh` 的 ax5 阶段做法），否则实测口径与既有证据不一致。
- 证据落点：运行时原始 xcodebuild 日志落 `.munk/logs/`（该目录 gitignore，仅回执引用）；同 commit 可检索的反例红日志 + 绿日志复制到 `docs/evidence/ax5-order-independence/`（只放日志/摘要文本，不新增 PNG，不动 `docs/screenshots/` 与 `docs/evidence/evidence-freeze/` 结构）。
- 反例构造（必须真跑，不得口述）：改后代码上临时移除 AX5 的 seed 调用（逆补丁，不提交该补丁本身），空容器下跑单用例 → 记录红（`runDetail.export` 30s 超时）→ 还原 → 再跑绿；两条日志都要留档，矩阵行"反例"列写明该构造方式。
- 已知残留风险，需在回执中明示：`scripts/capture-ios-screenshots.sh` 的 `stage_ax5` 先 `restore_archive` 再跑 AX5；若采用"无条件 seed"，会在快照归档之上多写一条跑次，改变后续 `ax5-history-detail` 实拍图指向的记录。因此优先采用"仅空态时 seed"，并在回执里给出该路径仍保持记录中性的证据（如连跑两遍文件数不变）。
