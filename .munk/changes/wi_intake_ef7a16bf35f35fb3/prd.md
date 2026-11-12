# 截图证据刷新：当前 A 色板 + 轨迹地图（14 张 + AX5/可及树 + commit 绑定）

## 范围

唯一交付是在当前 main（b49c82d，`ios.yml` 权威 run 43152394621 全绿）之上重拍整套界面证据，不碰产品面：

1. `docs/screenshots/` 14 张 PNG：6 屏 × 浅/深 = 12 张（Run 未开始 / 跑步中 / 结束态总结 / History 列表 / History 详情 / Settings）+ 结束态丢弃确认 sheet 浅/深 2 张；整批替换 2026-11-11 15:30 的旧 12 张。
2. 截图全部由仓内 `xcodebuild` 驱动模拟器 UI 测试（新 `ScreenshotEvidenceUITests`）+ 代码断言产出：截前先断言 `run.mapPreview`（结束态与详情共用同一 identifier）存在且 frame 在窗内，再取图；每屏同时跑 zh-Hans/无裸英文判定。
3. `docs/evidence/a11y/` 六棵可及树与 `docs/evidence/evidence-freeze/ax5/` 的 AX5 实拍 + 实测树，沿用既有组织结构由本项构建重出。
4. 新增 `docs/evidence/screenshot-refresh/`：README（构建 head sha、命令、断言源路径、日志路径、逐图 sha）与 SHA 清单；`docs/screenshots/SHA256SUMS` 同步为 14 行且 `shasum -c` 全 OK。
5. 更新 `docs/verification-matrix.md` 证据行与根 `README.md` 图集数量说明（12 → 14，含确认层）。

## 验收

- ac-screenshot-set-14: `docs/screenshots/` 恰有本项新产出的 14 张 PNG——6 屏浅色 `<screen>.png`、深色 `<screen>-dark.png`（`screen` ∈ {run-not-started, run-running, run-finished, history-list, history-detail, settings}）加 `discard-confirmation.png` / `discard-confirmation-dark.png`，无其它新增图片文件。
- ac-all-fresh-from-head: 14 张均由 `scripts/capture-ios-screenshots.sh --stage screenshots` 在 clean 工作树（`git status --porcelain` 为空）的 `git rev-parse HEAD` 上，经 `xcodebuild test-without-building -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/...` 产出；`docs/evidence/screenshot-refresh/README.md` 记录该构建 head sha、构建命令、xcresult 路径与生成时间。
- ac-palette-and-map-ancestry: README 记录 `git merge-base --is-ancestor 67ff54b HEAD` 与 `git merge-base --is-ancestor 22b84ab HEAD` 均退出 0（构建包含 A 色板与 TrackMapView），并贴出实际命令与输出。
- ac-no-reuse-old: 记录生成前 `docs/screenshots/SHA256SUMS` 的 12 个旧 sha；生成后 14 张中与任一旧 sha 相同的文件数为 0，且不存在由旧文件复制/改名而来的图片（README 给出旧/新 sha 对照）。
- ac-map-asserted-before-capture: 截图 run-finished 与 history-detail 前，测试断言 `run.mapPreview` 存在、frame 非空且完整落在窗口内（详情不足时先滚动再判），断言通过后才调 `XCUIScreen` 截图；两屏日志各有 `evidence-map screen=... identifier=run.mapPreview frame=...` 且与对应 PNG 一一对应。
- ac-zh-hans-six-screens: 6 屏逐屏以 `VisibleTextPolicy.violations` 判定可见文案（地图卡内部注记按既有口径过滤），日志出现 6 条 `ac-visible-copy-zh-hans screen=... violations=0`；允许的拉丁 token 仅 `/km`、`km`、`GPX`、`PurePace`，其余 ASCII 字母即判红。
- ac-discard-confirmation: 2 张确认层截图均来自结束态 `run.discardRequest` 打开的 sheet；截图前断言 sheet 同时含 `run.discard` 与 `run.discardCancel` 且 label 非空；README 以 `grep -c '\.sheet(' ios/PurePace`（实测 1）说明仓内确认层仅此一个，并注明按 ac-discard 取「结束态丢弃确认」。
- ac-light-dark-same-flow: 浅/深两轮共用同一捕获驱动，仅 `simctl ui appearance` 不同；每屏两版都命中同一主操作 identifier（run.start / run.pause / run.save / history.row / runDetail.root / settings.announcementToggle），不允许缺一版或只出一种外观。
- ac-a11y-trees-current-build: `docs/evidence/a11y/` 仍恰 6 棵（01-run-not-started … 06-settings），由本项构建重出；每棵含对应屏主操作 identifier（run.start / run.pause / run.save / history.row / runDetail.export / settings.announcementToggle）且 label 非空。
- ac-ax5-refreshed: `docs/evidence/evidence-freeze/ax5/` 下 4 张 AX5 实拍与 4 棵实测树由本项构建重出，脚本日志记录 `content_size` before/after 且结束后还原原字号。
- ac-sha256sums-ok: `docs/screenshots/SHA256SUMS` 恰 14 行哈希（头部登记构建 head sha），仓库根执行 `shasum -a 256 -c docs/screenshots/SHA256SUMS` 退出 0；`docs/evidence/screenshot-refresh/SHA256SUMS` 覆盖 14 张 PNG 与入库日志且校验通过。
- ac-evidence-bundle: `docs/evidence/screenshot-refresh/README.md` 含构建 head sha、模拟器 UDID/runtime、xcodebuild 命令、断言源文件路径（`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`）、脚本路径、日志路径、14 张逐图 sha 与来源；`capture.log` 与浅/深两次 xcodebuild 日志同目录入库；README 明写「截图只证明素材与断言绿，人肉眼验收待办」。
- ac-no-product-change: 改动路径 ⊆ {`ios/PurePaceUITests/**`, `scripts/capture-ios-screenshots.sh`, `docs/**`, `README.md`, `.munk/changes/**`}；不改 `ios/PurePace/**`（无新 identifier、无 DesignTokens/布局/文案/启动参数变更）、不改 `.munk/code-gates.json`、不改 `.github/workflows/**`。
- ac-ui-case-count-13: `scripts/test-ios.sh` 的 UI 腿仍为两段共 13 条（RunFlow 6 + 取证/AX5/音频 7）；新增 `ScreenshotEvidenceUITests` 只由采集脚本显式 `-only-testing` 调起，不进入 CI 腿；`bash scripts/test-ios.sh --unit-only` 与 13 条 UI 腿本地全绿，另单跑新证据测试绿。
- ac-verification-matrix-row: 更新 `docs/verification-matrix.md` 的证据行（现状/证据路径/归属项），写入本项 workItemId、`docs/evidence/screenshot-refresh/README.md` 与 14 张截图、地图断言；接缝总数保持 22，不改 `DocsVerificationMatrixTests` 的 `expectedSeamCount`。
- ac-code-gates: `.munk/code-gates.json` 全部门退出码 0；若改动触及 `ios/PurePace/**` 受管视图/identifier，则 `bash scripts/check-ios-shell.sh --self-test` 必须跑并绿（本项预期不触及，README 记录实际跑/未跑及理由）。
- ac-budget-receipt: Coding 首条回执写明预算（≤8M token / ≤90 分钟）与期望收口时刻；到点未闭合即交回执，列已完成证据与缺口，不靠长会话补绿。

## 非目标

- 不改视觉/布局/产品行为：不改 `DesignTokens`、文案键值、`RunFinishedSummaryLayoutPolicy`、80/80/16、96pt、600s、identifier 冻结清单、`.munk/code-gates.json`、`.github/workflows/**`。
- 不新增 identifier（复用 `run.mapPreview` / `run.discardRequest` / `run.discard` / `run.discardCancel`），不改 13 条 CI UI 用例数，不重构 `RunFlowUITests`。
- 不做分发/ASC/ipa/TestFlight/tag/Release；不排真机验收；不对 UI 是否达标下结论（人肉眼验收）。
- 不适用 `-screenshotHistoryDemo` 演示注入；不用旧截图改名/复用；不对截图做裁切、改色或再编码。
- 不修改 `.munk/baseline/**`、不新增 workflow gate。

## 实现约束

- 设备固定 iPhone 16 UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`、iOS 18.6（runtime 18.6 build 22G86）；构建产物 `.build/ios`。
- 截图取图方式：`XCUIScreen.main.screenshot()` → `XCTAttachment`（`lifetime = .keepAlways`）→ `xcrun xcresulttool export attachments` 直接写入 `docs/screenshots/`；浅/深各一个测试方法（`testEvidenceScreensLight` / `testEvidenceScreensDark`）复用同一驱动，方法由脚本在设定 `appearance` 后分别 `-only-testing` 调起，不做导出后改名。
- 驱动流程：`-uiTestLocation -uiTestLocationTargetMeters 1200 -uiTestResetArchive` 启动 → 断言 `run.start` → 截图未开始 → `run.start` 后等 `run.pause` → 截图跑步中 → `run.finish` 等 `run.save` → 断言 `run.mapPreview` 在窗内 → 截图结束态 → `run.discardRequest` 等 `run.discard`+`run.discardCancel` → 截图确认层 → `run.discardCancel` → `run.save` 等 `run.saved`；再以既有 DEBUG 参数 `-screenshotInitialTab history` / `-screenshotOpenRunDetail` 重开，断言 `history.row` 截列表、进入详情后滚动到 `run.mapPreview` 在窗内截详情；`-screenshotInitialTab settings` 断言 `settings.announcementToggle` 截设置。所有等待用状态判据，禁止固定 `sleep` 决定断言期望。
- zh-Hans 判定复用 `VisibleTextPolicy`（已编入 UITests target）；地图区过滤照抄 `RunFlowUITests.assertVisibleCopyZhHans` 的口径（`run.mapPreview` 区域内非地图卡本身元素忽略），不改 `RunFlowUITests`。
- `scripts/capture-ios-screenshots.sh --stage screenshots` 改为上述 UI 测试驱动；`trees`/`ax5` 阶段保持既有命令与落点，`all` 仍按 trees → screenshots → ax5。
- 两次提交协议：C1 = 新测试 + 脚本改动（可含矩阵/README 文案），在 C1 的 clean 树上执行采集并记录 `git rev-parse HEAD`；C2 = 14 张 PNG、`docs/screenshots/SHA256SUMS`、`docs/evidence/**`、矩阵与 README 回填。README/SHA 清单写 C1 的 head sha，不猜。
- 证据目录：`docs/evidence/screenshot-refresh/`（README.md、capture.log、xcodebuild-light.log、xcodebuild-dark.log、SHA256SUMS）；运行原始 xcresult 仍只落 `.build/evidence/`（不入库）。
- 根 `README.md` 图集说明从「完整 12 张」改为「完整 14 张（含结束态丢弃确认浅/深各 1 张）」。
