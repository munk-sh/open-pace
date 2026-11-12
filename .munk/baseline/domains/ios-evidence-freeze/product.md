# Domain: ios-evidence-freeze

PurePace iOS 证据冻结域：在已交付的六屏 UI 之上，产出一套可复核、可复算的模拟器证据——14 张浅/深 UI 测试实拍截图（`docs/screenshots/`，6 屏 × 浅/深 + 结束态丢弃确认浅/深）、六棵新构建可及树（`docs/evidence/a11y/`）、AX5 最大辅助字号实拍与 frame 实测（`docs/evidence/evidence-freeze/ax5/`），以及只含实测事实、路径、命令、sha256 与退出码的 digest（`docs/evidence/evidence-freeze/digest.md`）。本域只产证据，不改产品面：业务逻辑、文案键值、`DesignTokens` 取值、`.munk/code-gates.json` 门列表均为只读。唯一例外（2026-11-12 起）是结束态 AX5 溢出的共享布局策略 `RunFinishedSummaryLayoutPolicy`，只在辅助字号档生效、标准档取值不变。证据采集入口 `scripts/capture-ios-screenshots.sh --stage all`（截图阶段与只读 `verify` 自检同脚本）；取证用例 `ios/PurePaceUITests/EvidenceCaptureUITests.swift`（六树 / AX5）与 `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`（14 张截图）；截图重出登记与日志落 `docs/evidence/screenshot-refresh/`。

## 范围

- `docs/screenshots/`：六屏（`run-not-started` / `run-running` / `run-finished` / `history-list` / `history-detail` / `settings`）× 浅/深 = 12 张，加结束态丢弃确认层 `discard-confirmation.png` / `discard-confirmation-dark.png`，共 14 张 PNG；命名 `<screen>.png` 与 `<screen>-dark.png`，同一台模拟器原生竖屏分辨率、无裁切/改色/再编码；取图链路为 `XCUIScreen.main.screenshot()` → `XCTAttachment(name:)`（`lifetime = .keepAlways`）→ `xcrun xcresulttool export attachments` 直接写入本目录（附件名即文件名，导出后不改名）；`history-empty.png` 退役（历史列表改真实归档列表），`SHA256SUMS` 为 14 行逐文件 sha256 + 头部登记构建 head sha 与 tree sha；7 张浅/深并排对照落 `docs/screenshots/side-by-side/<screen>-side-by-side.png`（左浅右深、等高、1:1 不缩放、无分隔线）并附同款 `SHA256SUMS`，由 `scripts/compose-ios-screenshots-side-by-side.sh` 合成。
- `docs/evidence/screenshot-refresh/`：本批截图的重出登记——`README.md`（构建 head sha、模拟器 UDID/runtime、xcodebuild 命令、断言源 `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`、脚本路径、日志路径、14 张逐图 sha 与来源、旧/新 sha 对照、`git merge-base --is-ancestor` 实测输出、边界声明「人肉眼验收待办」）、`capture.log`、`xcodebuild-light.log`、`xcodebuild-dark.log`、`SHA256SUMS`（覆盖 14 张 PNG 与入库日志）；运行原始 xcresult 仍只落 `.build/evidence/`（不入库）。
- `docs/evidence/a11y/`：恰六棵与六屏一一对应的可及树（`01-run-not-started` / `02-run-running` / `03-run-finished` / `04-history-list` / `05-history-detail` / `06-settings`），由 `XCTAttachment(string: app.debugDescription)` 产出并 `xcrun xcresulttool export attachments` 导出；不对应六屏的旧树（`03-history-empty` / `06-tabs`）不在该目录。
- `docs/evidence/evidence-freeze/ax5/`：`content_size accessibility-extra-extra-extra-large` 档下 4 张关键屏实拍（Run 首屏 / 结束总结 / History 详情 / Settings）与同档实测树。
- `docs/evidence/evidence-freeze/digest.md`：预算回执、环境与构建、逐张生成命令、History 归档来源、六树与「一屏一主操作」清单、AX5 frame 实测、Dynamic Type 既有口径、22 门退出码、commit 绑定、改动范围。
- `docs/evidence/ax5-order-independence/digest.md`：AX5 取证腿顺序无关回执，含「干净容器单用例绿 / 同容器整包腿状态 / 反例与正向对照」三条口径，只写实测事实、日志文件名与未修清单。
- `scripts/capture-ios-screenshots.sh`：唯一采集入口（`--stage all|trees|screenshots|ax5|verify`），只用 `xcrun simctl` / `xcodebuild`，不做后处理；`screenshots` 阶段设 `simctl ui appearance light|dark` 后分别 `-only-testing` 调起 `ScreenshotEvidenceUITests` 两个方法，导出后重写 `docs/screenshots/SHA256SUMS` 并登记构建 head sha；`verify` 阶段只读校验 14 张命名、SHA 清单与 `shasum -c`、旧 sha 零复用、六树、AX5 4+4、7 张并排 + 其清单与 README 必填项；`assert_screenshot_log` 另强制校验 `evidence-inline-hint` 与 `evidence-c2-discard` 实测行（浅/深各一份）；`all` 仍按 trees → screenshots → ax5。并排合成脚本 `scripts/compose-ios-screenshots-side-by-side.sh`：仅系统 `swift` + CoreGraphics，零第三方依赖，同一输入两次运行输出字节相同。
- `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`：14 张截图的唯一驱动（`testEvidenceScreensLight` / `testEvidenceScreensDark` 共用 `captureAllScreens()`；浅/深只由宿主机 `appearance` 区分），截图前断言 `run.mapPreview` 在可见区、逐屏跑 `VisibleTextPolicy` zh-Hans 判定；`run-finished` 前断言 B1 inline 权限胶囊（`RunFinishedSummaryLayoutPolicy.meetsInlineHint`），`discard-confirmation` 前断言 C2 确认层（`run.discard` / `run.discardCancel` 同行、44pt、顶边 ≥70% 屏高、高 ≤200pt，禁用 `app.sheets`）；由 `scripts/test-ios.sh` 分段 3/4（浅/深）调起，也可由采集脚本显式 `-only-testing` 重跑。
- `ios/PurePaceUITests/EvidenceCaptureUITests.swift`：取证用例（真实记录链路造归档、六树导出、AX5 布局实测、主操作记录）。
- DEBUG-only 截图门控：`ios/PurePace/Run/RunLaunchArguments.swift` 的 `-screenshotRunFinished`（配合 `-autoStartRecording`，真实采样约 30s 后结束到待保存总结态、不落盘、`#if DEBUG` 内）与既有 `-screenshotInitialTab` / `-screenshotOpenRunDetail` / `-autoStartRecording` / `-uiTestLocation` / `-uiTestResetArchive`；`-screenshotHistoryDemo` 本域禁用。
- `README.md`：仅图集数量与描述（「完整 14 张：六屏浅色与深色 + 结束态丢弃确认浅/深各 1 张」）与指向 `docs/evidence/screenshot-refresh/README.md` 的一句链接，其余章节不动。

## 验收

- ac-screenshot-set-14: `docs/screenshots/` 恰有本批产出的 14 张 PNG——6 屏浅色 `<screen>.png`、深色 `<screen>-dark.png`（`screen` ∈ {`run-not-started`, `run-running`, `run-finished`, `history-list`, `history-detail`, `settings`}）加 `discard-confirmation.png` / `discard-confirmation-dark.png`，无其它新增图片文件；每张为同一模拟器原生竖屏分辨率，无裁切、改色、再编码或缩放。
- ac-all-fresh-from-head: 14 张均由 `scripts/capture-ios-screenshots.sh --stage screenshots` 在 clean 工作树（`git status --porcelain` 为空）的 `git rev-parse HEAD` 上经 `xcodebuild test-without-building -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/...` 产出；`docs/evidence/screenshot-refresh/README.md` 记录该构建 head sha、构建命令、xcresult 路径与生成时间。
- ac-palette-and-map-ancestry: README 记录 `git merge-base --is-ancestor 67ff54b HEAD` 与 `git merge-base --is-ancestor 22b84ab HEAD` 均退出 0（构建含 A 色板与 `TrackMapView`），并贴出实际命令与输出，不靠口述。
- ac-no-reuse-old: 记录本批之前一轮（`cbebc19` 批次）的 14 个旧 sha；生成后 14 张逐张比对，与旧 sha 重合数 == 0（README 贴 `comm -12` 实测输出与比对来源）；`--stage verify` 逐张比对同一份旧 sha 清单。
- ac-same-simulator-os: digest / README 记录唯一 UDID 与唯一 runtime（版本号 + build），14 张截图与 6 棵可及树的采集命令中 UDID 完全一致；证据命令中不出现第二台设备或第二个 runtime。
- ac-xcuiscreen-attachment-capture: 每张截图由用例内 `XCUIScreen.main.screenshot()` → `XCTAttachment`（`lifetime = .keepAlways`，附件名即目标文件名）产出，再由 `xcrun xcresulttool export attachments` 直接导出到 `docs/screenshots/`；宿主侧不做改名、裁切、改色或再编码，`--stage screenshots` 只在导出后重写 SHA 清单。
- ac-history-from-real-archive: 截图阶段的 History 列表与详情读取的跑次，来自同一会话内先跑完 `run.start → run.finish → run.save → run.saved` 并真实落盘到容器 `Documents/Runs/` 的归档（以 `-uiTestResetArchive` 保证干净容器起步、该跑次即列表唯一一条），不是演示注入；证据生成命令与用例源码中 `-screenshotHistoryDemo` 出现次数为 0（贴出命令原文与 grep 结果）。逐步可及树 / AX5 阶段的归档来源仍按既有 seed 口径。
- ac-a11y-trees-six: `docs/evidence/a11y/` 下恰有六棵对应六屏的新构建可及树（`01-run-not-started` / `02-run-running` / `03-run-finished` / `04-history-list` / `05-history-detail` / `06-settings`），每棵包含该屏主操作的 identifier 与非空 label；旧集合中不对应六屏的树（`03-history-empty` / `06-tabs`）从该目录移除。
- ac-one-primary-per-screen: digest / README 的「一屏一主操作」清单恰六行，每屏一行，列该屏主操作的 identifier 与可读 label，两者均非空；identifier 依次为 `run.start`（Run 首屏）/ `run.pause`（跑步中）/ `run.save`（结束总结）/ `history.row`（History 列表首行）/ `runDetail.export`（History 详情）/ `settings.announcementToggle`（Settings）；若新构建实测与此不符，按实测值记录并列明偏差，不得改写期望值或补造标识。
- ac-map-asserted-before-capture: 截图 `run-finished` 与 `history-detail` 前，用例断言 `run.mapPreview` 存在、frame 非空且完整落在「窗口扣除固定底部主操作区」的可见区内（详情不足时先滚动 ≤4 次再判），断言通过后才调 `XCUIScreen` 截图；两屏日志各有 `evidence-map screen=... identifier=run.mapPreview frame=... visible=...` 且与对应 PNG 一一对应。
- ac-zh-hans-six-screens: 6 屏逐屏以 `VisibleTextPolicy.violations` 判定可见文案（地图卡内部注记按 `RunFlowUITests` 既有口径过滤、`run.telemetry` 与 SF Symbol 标识排除），日志出现 6 条 `ac-visible-copy-zh-hans screen=... violations=0`；允许的拉丁 token 仅 `/km`、`km`、`GPX`、`PurePace`，其余 ASCII 字母即判红。
- ac-discard-confirmation: 2 张确认层截图均来自结束态 `run.discardRequest` 打开的 sheet；截图前断言 sheet 同时含 `run.discard` 与 `run.discardCancel` 且 label 非空；README 以 `grep -rn '\.sheet(' ios/PurePace`（实测 1 处）说明仓内确认层仅此一个，并注明取「结束态丢弃确认」。
- ac-light-dark-same-flow: 浅/深两轮共用同一 `captureAllScreens()` 驱动，仅宿主机 `simctl ui appearance` 不同；每屏两版都命中同一主操作 identifier（`run.start` / `run.pause` / `run.save` / `history.row` / `runDetail.export` / `settings.announcementToggle`），不允许缺一版或只出一种外观。
- ac-evidence-head-binding: `docs/screenshots/SHA256SUMS` 头部以 40 位 hex 登记同一构建 head sha（`git rev-parse HEAD` 实取）与 tree sha（`git rev-parse HEAD^{tree}` 实取），README 与并排 `SHA256SUMS` 记录同值；14 张与 7 张并排均绑定该 head/tree，`--stage verify` 校验头部 tree sha 与 README 一致。
- ac-sha-manifest-14: `docs/screenshots/SHA256SUMS` 恰 14 行 `^[0-9a-f]{64}  docs/screenshots/[^/]+\.png$`，`shasum -a 256 -c` 全 OK；`docs/evidence/screenshot-refresh/SHA256SUMS` 校验同样全 OK；`capture.log` 含 14 条 `shot: docs/screenshots/...` 行并逐张记录像素尺寸。
- ac-side-by-side-7: `docs/screenshots/side-by-side/` 恰 7 张 `<screen>-side-by-side.png`（屏幕集合同 14 张的 7 屏）；每张宽 == 2 × 浅色宽、高 == 浅色高（1:1 无缩放），左半逐像素等于浅色原图、右半等于深色原图；目录内无多余 PNG 且 `SHA256SUMS` 7 行 `shasum -c` 全 OK。
- ac-side-by-side-deterministic: 合成脚本零第三方依赖（仅系统 `swift` + CoreGraphics / 系统命令），同一输入连跑两次输出 sha 一致；满足仓内脚本约定（`#!/usr/bin/env bash`、`set -euo pipefail`、`BASH_SOURCE` 推导仓库根、`--help` 退出 0 且含「用法」、未知参数退出 2）。
- ac-b1-inline-assert: `run-finished` 取图**之前**断言 `run.backgroundDegraded` 存在、`frame.height ≤ 32`、`frame.width <` 实测内容宽，并打印 `evidence-inline-hint hint=<frame> maxHeight=<…> contentWidth=<…>` 实测行（复用 `RunFinishedSummaryLayoutPolicy.meetsInlineHint`）；`assert_screenshot_log` 在浅/深两份日志强制校验该行，旧「整行 39.33pt」形态判红。
- ac-c2-sheet-assert: `discard-confirmation` 取图**之前**断言 `run.discard` 与 `run.discardCancel` 同时存在、`abs(midY 差) ≤ 2`、`run.discard` 高 44±1、由 `确认层标题.frame.minY − DesignTokens.Spacing.xs` 推导的顶边 ≥ `0.70 × 屏高`、推导高度 ≤ 200，并打印 `evidence-c2-discard screenHeight=… sheetTop=… sheetHeight=…` 实测行；判据不得回退到 `app.sheets`（`grep -c 'app.sheets' ios/PurePaceUITests/ScreenshotEvidenceUITests.swift` == 0）。
- ac-ci-authoritative-green: 证据 commit 推送后其 head sha 的 `ios.yml` run 为 `completed`/`success`，4 段 UI 腿覆盖 5 个套件，run id / head sha / conclusion / 各腿耗时回填证据 README；若基线或证据 commit 判红，按失败腿原文（run id + 断言行 + 日志片段）原样记录并上报阻塞，不得伪造绿，不得提高 timeout / 删腿 / 加 `continue-on-error` / 放宽断言。
- ac-ax5-refreshed: `docs/evidence/evidence-freeze/ax5/` 下 4 张 AX5 实拍与 4 棵实测树由本项构建重出，脚本日志记录 `content_size` before/after 且结束后还原原字号。
- ac-ui-legs-4segments: `scripts/test-ios.sh` 的 UI 腿仍 4 段（RunFlow 6 条 / 取证+AX5+音频 7 条 / 截图浅色 1 条 / 截图深色 1 条），覆盖 `ios/PurePaceUITests` 全部 5 个套件；段前切外观、段后恢复 light，预算/阈值常量与 `-only-testing` 覆盖不减，不删腿、不加 `continue-on-error`。
- ac-evidence-bundle: `docs/evidence/screenshot-refresh/README.md` 含构建 head sha、模拟器 UDID/runtime、xcodebuild 命令、断言源文件路径、脚本路径、日志路径、14 张逐图 sha 与来源；`capture.log` 与浅/深两次 xcodebuild 日志同目录入库；README 明写「截图只证明素材与断言绿，人肉眼验收待办」。
- ac-ax5-capture-and-fit: 最大辅助字号档（`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`）下实拍至少 4 张关键屏（Run 首屏 / 结束总结 / History 详情 / Settings），digest 记录该命令与设置前后 `content_size` 实读值；同档可及树中每个元素 frame 均落在屏内，主操作 frame 与其它内容 frame 无相交，digest 贴出实测 frame 数值与判定结果。
- ac-dynamic-type-limitation-disclosed: digest 明写「`DesignTokens.Typography` 全部为固定 `Font.system(size:)`，字号阶梯不随 Dynamic Type 缩放」这一既有口径，并说明 AX5 证据只能证明固定字号布局在最大系统字号档不截断不重叠；全文不出现「无障碍适配已完成 / 达标」之类结论。
- ac-sha256-manifest: `docs/screenshots/SHA256SUMS` 恰 14 行哈希（头部登记构建 head sha），`shasum -a 256 -c docs/screenshots/SHA256SUMS` 在仓库根退出 0；`docs/evidence/screenshot-refresh/SHA256SUMS` 覆盖 14 张 PNG 与入库日志且校验通过；README 逐图 sha 表与该输出逐行一致（无冲突或占位值）。
- ac-verification-matrix-row: `docs/verification-matrix.md` 证据行（现状 / 证据路径 / 归属项）写入本项 workItemId、`docs/evidence/screenshot-refresh/README.md` 与 14 张截图、地图断言；接缝总数保持 22，不改 `DocsVerificationMatrixTests` 的 `expectedSeamCount`。
- ac-commit-binding: digest 记录被测构建 commit SHA（`git rev-parse HEAD` 实取，与截图构建对应）与每个证据文件的最近改动 commit 全 SHA（`git log --format=%H -1 -- <file>` 实取）；不得出现猜测值或沿用旧值；若「被测构建 SHA」与「证据入库 SHA」不同，须分列标注成因。
- ac-gates-green: `.munk/code-gates.json` 门列表不变（22 门），digest 逐门记录 id 与真实退出码，全部为 0；未触及 `ios/PurePace/**` 受管视图 / identifier 时 `check-ios-shell.sh --self-test` 可不跑，但须在 README 写明实际跑 / 未跑及理由。
- ac-no-scope-creep: 改动路径 ⊆ {`ios/PurePaceUITests/**`, `scripts/capture-ios-screenshots.sh`, `docs/**`, `README.md`, `.munk/changes/**`}；不改 `ios/PurePace/**`（无新 identifier、无 `DesignTokens` / 布局 / 文案 / 启动参数变更）、不改 `.munk/code-gates.json` 门列表、不改 `.github/workflows/**`。
- ac-claims-discipline: digest 只写实测事实、路径、命令、sha256 与退出码，不含「达标 / 可以给用户用 / 发布就绪」等自判，也不含真机验收与分发动作（ASC / ipa / TestFlight / tag / Release）。
- ac-budget-receipt: 开工首条回执写明预算（预计耗时与门禁轮次上限）与期望收口时刻；超预算即停手并在回执写明已完成的证据与缺口，不靠长会话补绿。
- ac-evidence-seed-single-source: `ios/PurePaceUITests/EvidenceCaptureUITests.swift` 的真实 seed 链路（`launchApp(["-uiTestLocation"])` → `run.start` → `run.elapsed >= "00:30"` → `run.finish` → `run.save` → `run.saved`）只存在一处 `private seedRealArchive(onNotStarted:onRunning:onFinished:)` 实现，`testEvidenceTreesAndRealArchive` 与 `testEvidenceAx5Layout` 共用；断言中等待 `run.saved` 的次数为 1（无内联副本）。
- ac-trees-order-unchanged: `testEvidenceTreesAndRealArchive` 仍按 01→06 顺序产出同六棵 `attachTree`（`01-run-not-started` / `02-run-running` / `03-run-finished` / `04-history-list` / `05-history-detail` / `06-settings`）与 6 条 `evidence-primary` 打印，取证点由闭包回调保留在原位置；该用例在干净容器下单独跑绿。
- ac-ax5-clean-container-green: 清空容器（`simctl uninstall` 后全新安装、容器内无 `Documents/Runs`）单跑 `-only-testing:PurePaceUITests/EvidenceCaptureUITests/testEvidenceAx5Layout` 退出码 0；日志出现 4 条 `AX5-FIT screen=` 且含 `screen=05-history-detail`（确实进入详情而非停空态）。
- ac-ax5-conditional-seed: 详情步前先只读检测归档（`history.row` 计数或 `history.empty`，该 launch 本身不写盘），非空只打印 `AX5-SEED action=skip reason=archive-present rows=<n>`；仅空态调用 seed（`AX5-SEED action=seed reason=archive-empty`），同容器连跑第二遍 `Documents/Runs` 文件数不变。
- ac-seed-launch-args: seed 及其后所有 launch 的 `launchArguments` 不含 `-uiTestResetArchive`、不含 `-screenshotHistoryDemo`；seed 链路必须走 `-uiTestLocation` 以产生真实采样距离。
- ac-explicit-terminate: AX5 每次换新 `XCUIApplication` 前（含 seed 前后、详情检测前后、设置页前）都有显式 `app.terminate()`，跨 launch 不残留上一进程状态。
- ac-assertions-only-added: 断言只增不减——AX5 的 4 处 `assertFitsAndNoOverlap` 与超时值（30 / 60 / 30 / 30）及「缺少…」失败文案逐字保留，trees 的 6 处 `XCTAssertTrue` 保留；不靠放宽超时或用例重排转绿。
- ac-counterexample-red-proof: 反例必须真跑并留同 commit 日志 `docs/evidence/ax5-order-independence/ax5-counterexamples.log`：滚动感知口径的两条合成反例（静态文本宽 420 > 窗宽 393、交互元素 `isHittable=false`）各红在不同判据，另有正向对照（仅静态文本垂直滚出视口）不误判；红/绿日志同 commit 入库，不得只口述。
- ac-verification-matrix-row: `docs/verification-matrix.md` 对应接缝行六列齐备（接缝 / 现状 / 断言名 / 反例 / 证据路径 / 归属项），归属项写明本项 workItemId，证据路径指向实际存在的日志；`DocsVerificationMatrixTests` 的接缝计数与归属断言同步（20→21，新增接缝「详情导出固定底部」）。
- ac-ax5-finished-summary-policy: 结束态溢出只允许以共享策略修复——`ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift` 唯一承载取值：辅助字号档地图 96 / 区块间距 `xxs` / 卡内边距 `xs` / 行距 `xxs`；标准字号档在可用内容区 < 688pt（实测溢出 75.3pt）时同样压缩，地图取 `finishedMapFloor` = 96pt（与 AX5 同值；2026-11-12 的 32pt 细条已回退），预算充足仍 180pt。由 `RunView` 按 `dynamicTypeSize.isAccessibilitySize` + 可用内容区消费，不新增 `DesignTokens` 取值或字号档，`run.save` 固定底部位置不变；三件套（实测溢出值 → 命名参数 → 复用点）写在策略内。
- ac-ax5-no-overlap-standard-and-ax5: `testEvidenceAx5Layout` 的 03-run-finished 屏 `run.backgroundDegraded` 与主操作 `run.save` 互不相交，标准字号档与 AX5 档同时成立（AX5 实测 bottom 858.3→730.3），四屏 `AX5-FIT`（outOfBounds=0 / overlaps=0）保持；判据不放宽 `assertFitsAndNoOverlap`。
- ac-trees-export-realized: `testEvidenceTreesAndRealArchive` 的 `recordPrimaryAction(app.buttons["runDetail.export"], screen: "05-history-detail")` 在 30s 内取到元素并点击成功——导出已移出惰性 `List` 到固定底部主操作区，realize 不再影响可见性；`AX5-SEED` 归档行计数在 `terminate()` 前只读一次，避免非空归档分支假红。
- ac-pack-leg: 同容器紧接整包（`-only-testing:PurePaceUITests`，或至少 `EvidenceCaptureUITests` 两用例按默认字母序）退出码 0 且两用例全过；未跑齐时按 `ac-pack-leg-explicit` 的无条件事实口径记录并列出未闭合点，不得静默缺失或用条件句省略事实。
- ac-pack-leg-explicit: `docs/evidence/ax5-order-independence/digest.md` 第 5 节「腿状态」的整包条目为无条件事实表述，同时含三要素——「整包腿未跑齐」、`ax5-pack-standard.log` 被截断且末行停在后续用例 `t = 7.67s`（`Waiting 10.0s for NavigationBar (First Match) to exist`）无整包结论、已绿范围仅到单用例 `testEvidenceAx5Layout` exit 0 与两条反例/正向对照（`ax5-counterexamples.log`）；条件句「跑不齐则如实记未跑」不再出现。
- ac-digest-no-green-wording: digest 全文不出现「整包绿」「整包通过」字样；`grep -n "整包" docs/evidence/ax5-order-independence/digest.md` 的输出含「未跑齐」。
- ac-digest-summary-consistent: digest 顶部标题/摘要区若出现整包相关描述，口径与第 5 节一致（明确未跑齐、不写绿）；原本无整包描述则保持不新增整包结论。
- ac-no-other-production-change: 除上述策略与 `RunView` 取值替换外，改动路径 ⊆ {`ios/PurePaceUITests/**`, `ios/PurePaceTests/**`, `ios/RunCore/Tests/**`, `docs/evidence/**`, `docs/verification-matrix.md`}；不改 `RunStorage` / `HistoryViewState` / `HistoryView` / 归档格式，不改 `.munk/code-gates.json` 门列表，不新增 DEBUG 启动参数或测试脚手架。

## 非目标

- 不改业务逻辑、状态机、归档格式、GPX 导出、History / Settings / Run 的交互行为；不改门禁规则与 `.munk/code-gates.json` 门列表/命令，不新增 gate id。
- 不改文案键与文案值（`Localizable.xcstrings` / `L10n`）、不改设计令牌取值、不加动效。
- 不做任何分发动作（ASC / ipa / TestFlight / tag / Release）；不排真机验收，真机项（锁屏定位、音频实听、授权弹窗观感）继续 `pending: 待人现场`。
- 不手绘、不改色、不裁切、不重排任何截图；不使用第三方素材。
- 不新增 Tab、屏或二级入口；不为截图新增用户可达的演示/示例入口（demo 入口数仍为 0，Release 不可达）。
- 不把 History 空态纳入这套截图（空态由既有 UI 断言覆盖）；确认层只取结束态丢弃确认，不扩充其它 sheet。
- 不宣称无障碍适配完成，不写发布就绪结论。

## 实现约束

- 设备与 OS：一律沿用 iPhone 16 / iOS 18.6（UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`，runtime `18.6` build `22G86`）以与既有 `393.0 × 852.0` 可及树可比；全部证据只允许一台机、一个 runtime，最终以实取 UDID 与 `simctl list runtimes` 写入 digest 为准。
- 采集能力只用系统工具：截图走用例内 `XCUIScreen.main.screenshot()` + `xcrun xcresulttool export attachments`；`xcrun simctl ui <udid> appearance light|dark` / `content_size <档位>` 设定状态，AX5 实拍仍用 `xcrun simctl io <udid> screenshot <path>`；构建产物来自 `xcodebuild build-for-testing ... -derivedDataPath .build/ios`，采集日志与 xcresult 落 `.build/evidence/`（不入库）。
- 截图启动参数：截图驱动以 `-uiTestLocation -uiTestLocationTargetMeters 1200 -uiTestResetArchive` 起步（干净容器 + 距离 canonical），History 两屏复用同会话真实落盘的归档；不得使用 `-screenshotHistoryDemo`，不得对 PNG 做裁切/改色/再编码；新增截图门控只能在 `#if DEBUG` 内且 Release 不可达。
- 干净树硬约束：`--stage screenshots` 默认要求 `git status --porcelain` 为空（否则 fail 并指出不满足 `ac-all-fresh-from-head`），`CAPTURE_ALLOW_DIRTY=1` 仅供本地调试、证据不入库。
- 真实归档优先：History 列表/详情必须由 App 真实「开始记录 → 跑步中 → 结束 → 保存」产生并落盘，再以真实归档渲染；`-screenshotHistoryDemo`（固定 5.12 km / `startedAt = 1_760_000_000`、不落盘）禁用，其固定值组合是「演示注入 vs 真实归档」判据。
- 可及树来源：复用 `ios/PurePaceUITests/RunFlowUITests.swift` 的 `XCTAttachment(string: app.debugDescription)` + `xcrun xcresulttool export attachments` 范式（`scripts/verify-ios-ui-e2e.sh` 同类），树的归属屏必须与六屏一一对应。
- 门禁与 UI 腿：`.munk/code-gates.json` 22 门保持不变，iOS 相关 test 门只跑 `test-ios.sh --unit-only`；UI 驱动腿权威在 `.github/workflows/ios.yml`。`RunFlowUITests` 历史 signal-kill 崩溃属环境 flake（stash 回 HEAD 同复现），不得当作回归结论，遇崩溃如实记录实测输出与重试次数。
- 字号事实：`DesignTokens.Typography` 全部为固定 `Font.system(size:weight:)`，`sizes = [11, 13, 15, 20, 36, 64]`，不随 Dynamic Type 缩放——digest 必须如实写明，AX5 只证明固定字号布局不截断不重叠。
- 提交绑定可拆两次提交（先产证据记被测构建 SHA，再回填证据文件最近改动 SHA），但两列都必须实取，不许猜；文件无法内嵌承载自身 commit SHA，digest 自身以其最近改动 commit 单独列出。
- AX5 取证腿自给自足口径：详情步前只读检测 → 仅空态 seed → `terminate()` → 再 `-screenshotInitialTab history -screenshotOpenRunDetail`；`05-history-detail` 用滚动感知判定（`ios/PurePaceUITests/Ax5ScrollAudit.swift`：交互元素须滚动可达 + frame 完整落在视口内 + 不被另一交互元素覆盖；静态文本只判水平溢出；视口 = window 去掉底部 Tab 栏），不得靠放宽超时或改生产 `List` 转绿。反例与绿日志同 commit 入 `docs/evidence/ax5-order-independence/`，运行时原始日志只落 `.munk/logs/`（gitignore）。
- 整包腿事实源冻结（2026-11-12 起草更正）：`ax5-pack-standard.log` 共 1708 行、末行 `t = 7.67s Waiting 10.0s for NavigationBar (First Match) to exist`、无整包结论行；`ax5-single-green.log` 对应单用例 exit 0；`ax5-counterexamples.log` 对应两条反例 + 正向对照。digest 一律据此写无条件事实，不补跑、不产出新 log。

## 最近交付证明

- workItemId: wi_intake_85d08fa7106efc3f（2026-11-12，pass）
- 交付：在产品面基线 `a677e17`（tree `400c010`）上整批重出 14 张浅/深截图并新增 7 张浅/深并排对照（`docs/screenshots/side-by-side/`，左浅右深、1:1 不缩放、零第三方依赖合成）。`ScreenshotEvidenceUITests.swift` 补强截前断言：B1 inline 权限胶囊（`meetsInlineHint` + 打印 `evidence-inline-hint`）与 C2 丢弃确认层（`run.discard`/`run.discardCancel` 同行、44pt、顶边 ≥70% 屏高、高 ≤200pt，禁用 `app.sheets`），并修正「不进 CI 腿」注释。`capture-ios-screenshots.sh` 换成本批前 14 个旧 sha、写入 tree sha、新增两类实测行校验与 7 张并排 verify；新增 `scripts/compose-ios-screenshots-side-by-side.sh`。
- 判定与证据：`code_gates` 22 门 attempt 001 全绿；`shasum -a 256 -c` 三份清单（14 张 / 并排 7 张 / 证据目录）全 OK；旧 14 sha 逐张重合数 0；`check-ios-shell.sh --self-test` 100/0、`check-ios-shell.sh` 33/0、`check-ios-scripts.sh` 34/0、`--stage verify` OK。
- 偏离与边界：**ac-ci-authoritative-green 未达成**——基线 `a677e17` 的 `ios.yml` run `43234566773` 为 `completed`/`failure`，红因是产品层「运行中/暂停指标区未垂直居中」（`RunFlowUITests.swift:890`），已另立 `wi_intake_caf0abdb2486d501` 修红；本项按原样记录失败腿原文，不伪造绿。证据 commit 已推送（合并提交 `8a6c2af`），其 `ios.yml` run `43242965553` 查询时 `in_progress`、结论待跑完，不轮询预写绿。产品面零改动（`ios/PurePace/**` 零 diff、22 门与 `ios.yml` 不变、identifier 42/33 冻结计数不变）；排版/配色观感与真机表现 `pending: 待人现场`。
