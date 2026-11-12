# V1.2 复评证据重出（14 张 + 7 张并排）与 ios.yml 同 commit 权威绿

## 范围

- 在 `main` 当前 head `a677e17`（tree `400c010`，已含 B1 结束态与 C2 丢弃确认层，实现 commit `96b7d01`）的树上，只做**证据与 CI 验证**：
  1. 用现有 `scripts/capture-ios-screenshots.sh --stage screenshots` 在生产用模拟器上重出 14 张界面截图（6 屏 × 浅/深 + 结束态丢弃确认层浅/深），更新 `docs/screenshots/SHA256SUMS` 与 `docs/evidence/screenshot-refresh/README.md`（构建 head sha + tree sha、14 张逐图 sha、与本批之前 14 个 sha 的逐张重合数 = 0、断言源路径、可复跑命令）。
  2. 新增 7 张浅/深并排对照图（`run-not-started` / `run-running` / `run-finished` / `discard-confirmation` / `history-list` / `history-detail` / `settings`），左浅右深、等高、1:1 像素不缩放，落 `docs/screenshots/side-by-side/` 并附 `SHA256SUMS`；合成确定性、零第三方依赖。
  3. 补强截图前断言：B1 inline 权限胶囊（存在 / 高 ≤32 / 宽 < 内容宽且打印实测值）与 C2 确认层（`run.discard` + `run.discardCancel` 同行、confirm 44pt、由标题 `frame.minY − Spacing.xs` 推导顶边与高度、顶边 ≥70% 屏高、≤200pt，禁用 `app.sheets`），六屏 zh-Hans `violations=0` 口径不变。
  4. 取证据 commit 同 head sha 的 `ios.yml` 权威腿结论（completed/success、覆盖全部 UI 套件）并写回证据 README 回执。
  5. 跑本地门与自检并如实记录：`check-ios-shell.sh --self-test`、`check-ios-shell.sh`、`test-ios.sh --unit-only`、脚本改动后的 `lint-ios-scripts`、`capture-ios-screenshots.sh --stage verify`。
- 允许改动面：`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`、`scripts/capture-ios-screenshots.sh`、新增 `scripts/` 下并排合成脚本、`docs/screenshots/**`、`docs/evidence/screenshot-refresh/**`。

## 验收

- ac-evidence-head-binding: `docs/screenshots/SHA256SUMS` 头部登记同一构建 head sha（40 位 hex，实取 `git rev-parse HEAD`）与同一 tree sha（实取 `git rev-parse HEAD^{tree}`），`docs/evidence/screenshot-refresh/README.md` 记录同值；14 张截图与 7 张并排图均绑定该 head/tree sha。
- ac-screenshot-set-14: `docs/screenshots/` 顶层恰 14 张 PNG，文件名集合精确等于 `{run-not-started, run-running, run-finished, discard-confirmation, history-list, history-detail, settings} × {<base>.png, <base>-dark.png}`，无多余 PNG；`capture.log` 含 14 条 `shot: docs/screenshots/...` 行且逐张记录像素尺寸。
- ac-sha-manifest-14: `docs/screenshots/SHA256SUMS` 恰 14 行 `^[0-9a-f]{64}  docs/screenshots/[^/]+\.png$`，`shasum -a 256 -c docs/screenshots/SHA256SUMS` 输出全 OK；`docs/evidence/screenshot-refresh/SHA256SUMS` 校验同样全 OK。
- ac-no-reuse-prev-batch: 新 14 张逐张 sha 与本批之前一轮（`cbebc19` 批次、旧清单 14 个 sha）逐张比对，重合数 == 0；README 写明「重合数 0」并列出比对来源。
- ac-no-postprocess: 14 张 PNG 由 `ScreenshotEvidenceUITests` 的 `XCTAttachment` 按附件名直接导出到 `docs/screenshots/`，导出链无裁切 / 改色 / 再编码 / 改名；`docs/evidence/screenshot-refresh/xcodebuild-light.log` 与 `-dark.log` 均含对应 14 个 `evidence-shot screen=` 行。
- ac-b1-inline-assert: 在 `run-finished` 取图**之前**断言 `run.backgroundDegraded` 存在、`frame.height ≤ 32`、`frame.width <` 实测内容宽（约 361pt，内容宽从窗口宽与左右内边距实取并打印），并打印 `evidence-inline-hint hint=<frame> maxHeight=<…>` 实测行；宿主 `assert_screenshot_log` 在浅/深两份日志中强制校验该行存在；旧「整行 39.33pt」形态（高度 ≥ 32 或宽 ≥ 内容宽）判红。
- ac-c2-sheet-assert: 在 `discard-confirmation` 取图**之前**断言 `run.discard` 与 `run.discardCancel` 同时存在、`abs(midY 差) ≤ 2`、`run.discard.frame.height` == 44 ± 1、由 `确认层标题.frame.minY − DesignTokens.Spacing.xs` 推导的顶边 ≥ `0.70 × 屏高`、推导高度（`屏高 − 顶边`）≤ 200，并打印 `evidence-c2-discard …` 实测行；`ScreenshotEvidenceUITests.swift` 中确认层判据不得回退到 `app.sheets`（`grep -c 'app.sheets' ios/PurePaceUITests/ScreenshotEvidenceUITests.swift` == 0）。
- ac-zh-hans-violations-zero: 六屏在浅色与深色各打印一条 `ac-visible-copy-zh-hans screen=<screen> labels=… violations=0 ` 行（共 12 条），白名单口径不变（仅放行 `/km`、`km`、`GPX`、`PurePace`）。
- ac-side-by-side-7: `docs/screenshots/side-by-side/` 恰 7 张 `<screen>-side-by-side.png`（屏幕集合同上）；每张宽 == 2 × 对应截图宽、高 == 对应截图高（1:1 无缩放），左半逐像素等于浅色原图、右半逐像素等于深色原图，并附 `SHA256SUMS` 且 `shasum -a 256 -c` 全 OK。
- ac-side-by-side-deterministic: 合成脚本零第三方依赖（仅系统 Swift + CoreGraphics / 系统命令），同一输入连续运行两次输出字节相同（逐张 sha 一致）；脚本满足仓内脚本约定：`#!/usr/bin/env bash`、`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根、`--help` 退出 0 且含「用法」、未知参数退出 2。
- ac-gates-no-drift: `.munk/code-gates.json` 仍 22 门；`ios/PurePace/**` 零 diff（identifier 两款冻结计数 42 / 33、token、字号、间距、圆角、文案、VERSION、`0.1.0(1)` 均不变）；`scripts/test-ios.sh` 的 `ui_call` 仍 4 段且预算/阈值常量不变；`.github/workflows/ios.yml` 零 diff。
- ac-local-gates: `bash scripts/check-ios-shell.sh --self-test` 100 断言 / 0 失败；`bash scripts/check-ios-shell.sh` 33 项 identifier 冻结零改动且全绿；`bash scripts/test-ios.sh --unit-only` 记录 PurePaceTests 265/0 与 RunCore 173/0；`bash scripts/check-ios-scripts.sh` 全绿（含 `ui_call` 枚举覆盖 5 个 UI 套件）；`bash scripts/capture-ios-screenshots.sh --stage verify` 全绿。
- ac-ci-authoritative-green: 证据 commit 推送后，其 head sha 对应的 `ios.yml` run 为 `status=completed` 且 `conclusion=success`；该 run 的 4 段 UI 腿覆盖 `ios/PurePaceUITests` 全部 5 个套件（`RunFlowUITests`、`EvidenceCaptureUITests`、`Ax5ScrollAuditCounterexampleTests`、`MusicSourceSelfCheckUITests`、`ScreenshotEvidenceUITests` 浅/深），回执写入证据 README：run id、head sha、conclusion、各腿耗时。CI 查询不得在会话内 watch/sleep 轮询（一次查不到就挂一次性 alarm 或常驻等待任务，出结论再继续）。
- ac-ci-no-weakening: 为换绿不得提高 timeout、删腿、加 `continue-on-error` 或放宽断言；若 `a677e17`（run `43234566773`）或证据 commit 的 `ios.yml` 判红，按失败腿原文（run id + 断言行 + 日志片段）作为阻塞上报，不得伪造绿。

## 非目标

- 不改任何视图 / token / 字号 / 间距 / 圆角 / 文案；不改 `VERSION` 与验收候选 `0.1.0(1)`。
- 不动 identifier（新增 / 改名 / 删除一律不做）、不加新屏。
- 不碰旧目录 `docs/evidence/wi_intake_93f2857d51330b9d`；不改 `shared/`、`android/`、`ios/Core`、`ios/RunCore`。
- 不新增门禁机制与阈值（`.munk/code-gates.json` 保持 22 门），不改 `.github/workflows/ios.yml`。
- 不做真机验收、不做分发（ipa / TestFlight / tag / Release / ASC）。
- 不对「UI 是否达标」下结论：人肉眼复评待办，产品不得自判 UI 达标。

## 实现约束

- 归属项 `wi_intake_85d08fa7106efc3f`；基线 `main = a677e17`（tree `400c010`），实现 commit `96b7d01`（tree `c06abaf`）。本项按显式快速通道：`needPm/needDesign/needArchitect/needChangePackReview = false`。
- 采集前置：`.build/ios` 当前不存在，需先 `xcodebuild build-for-testing`（见 `docs/evidence/screenshot-refresh/README.md` 既有命令）。模拟器固定 iPhone 16 / UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD` / iOS 18.6；Xcode 26.3。
- 采集顺序必须是「先提交代码改动 → 工作树 clean → 跑采集 → 再提交证据」，因为 `stage_screenshots` 在非 clean 工作树直接 fail（防旧图冒充）。采集 head sha 由脚本 `git rev-parse HEAD` 实取，勿手填。
- `scripts/capture-ios-screenshots.sh` 必改点：
  - `old_shot_shas`（当前为 2026-11-11 的 12 个旧 sha）替换为**本批之前一轮的 14 个 sha**（当前 `docs/screenshots/SHA256SUMS` 的 14 条，来自 `cbebc19` 批次），`stage_verify` 逐张比对改为 14 个；
  - `write_sha256sums` 头部补 tree sha、归属项、README 路径；
  - `assert_screenshot_log` 增加 `evidence-inline-hint` 与 `evidence-c2-discard` 行校验（浅/深各一份），保留既有 `evidence-map`、`evidence-discard`、`ac-visible-copy-zh-hans` 校验；
  - `stage_verify` 增加并排目录 7 张 + `SHA256SUMS` 校验与 README 必填项（保留现有 tokens：`构建 head sha`、`ScreenshotEvidenceUITests.swift`、`capture.log`、`xcodebuild-light.log`、`xcodebuild-dark.log`、`run.mapPreview`、`肉眼`、`14`）。
- `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift` 必改点：
  - 复用产品侧判据 `RunFinishedSummaryLayoutPolicy.meetsInlineHint(height:width:contentWidth:)` 与 `inlineHintMaxHeight`（`ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift:20,44`），断言放在 `capture(base: "run-finished")` 之前；
  - C2 断言放在 `capture(base: "discard-confirmation")` 之前，顶边推导沿用 `确认层标题.frame.minY - DesignTokens.Spacing.xs`（同 `RunFlowUITests.swift:1082` 口径），新增 `≥ 0.70 × 屏高` 判据（实测参考：屏高 852、顶边 682.33、高 169.67）；
  - 文件头注释「本用例不进 CI 腿」与现状不符需修正为「由 `scripts/test-ios.sh` 分段 3/4 调起」。
- 并排合成：新增单一 bash 脚本（建议 `scripts/compose-ios-screenshots-side-by-side.sh`），内部用 `swift` 执行 CoreGraphics 位图拼接（水平拼接、不插分隔线、不缩放），输出 `docs/screenshots/side-by-side/<screen>-side-by-side.png` 并重写该目录 `SHA256SUMS`；不得引入新门、不得改 22 门；脚本需满足 `check-ios-scripts.sh` 的 `targets` 之外不被索引，保持 shell/id 计数守卫不破。
- CI 现状事实（Intake 实取）：`gh run list --workflow=ios.yml` 中 `a677e17` 的 run 为 `43234566773`，当前 `status=queued`（非失败，故不构成阻塞）；证据 commit 的权威腿结论须在推送后按 ac-ci-authoritative-green 取证写入 README。
- 预算：≤8M token / ≤90 分钟；14 张与 7 张并排必须同 head/tree sha；完成回执必须写明「人肉眼复评待办，产品不得自判 UI 达标」。
