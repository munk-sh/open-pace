---
workItemId: wi_intake_837f0c6ab9066cf5
stage: coding
verdict: pass
---

# 交付摘要（coding → delivery）

三屏视觉层级与设计 token 收敛已落地；复用上一 run worktree 改动并按公司裁决 `owe_8bea26dc07c9c10e` 补齐可及标识与证据。

## 证据路径

- 截图（真实 simctl，非手绘）：
  - `docs/screenshots/run-not-started.png`（首屏 / 未开始态）
  - `docs/screenshots/run-running.png`（运行中 / 记录态）
  - `docs/screenshots/history-detail.png`（历史详情，含导出 GPX 入口）
  - 附：`history-empty.png` / `settings.png`
- 可及树导出（文本）：
  - `docs/evidence/a11y/01-run-not-started.txt`
  - `docs/evidence/a11y/02-run-running.txt`
  - `docs/evidence/a11y/03-history-empty.txt`
  - `docs/evidence/a11y/04-history-detail.txt`
  - `docs/evidence/a11y/05-settings.txt`
  - `docs/evidence/a11y/06-tabs.txt`

可及树中可按 identifier 定位：`run.start` / `run.pause` / `run.finish` / `history.runAgain` / `runDetail.export` / `settings.announcementToggle`，以及 Tab 内容根 `tab.run` / `tab.history` / `tab.settings`；主操作同时带非空 `accessibilityLabel`。

## 造态口径

运行中与历史详情截图由既有 DEBUG 启动参数（`-uiTestLocation`、`-screenshotHistoryDemo`、`-screenshotOpenRunDetail`、`-screenshotInitialTab`）注入；种子数据不入发布路径（演示数据不入发布路径）。首屏截图亦用 `-uiTestLocation` 规避系统定位授权弹窗，画面仍为真实构建的未开始态。

## 本地验证（模拟器 / 单测 / 静态断言）

- `bash -n scripts/check-ios-shell.sh`：通过。
- `bash scripts/check-ios-shell.sh`：28 项断言 0 失败；`--self-test` 36 项断言 0 失败（含新增正例与负例）。
- `bash scripts/test-ios.sh --unit-only`：125 用例 0 失败（含 `DesignTokensTests` 9 例）。
- `bash scripts/build-ios.sh`：`** BUILD SUCCEEDED **`。
- 未改动 `scripts/test-ios.sh` 与 `.github/workflows/*` 的 UI 腿；未新增 XCUITest 用例。

## 范围与剩余

- 未动定位 / 音频 / TTS / 持久化 / GPX 契约与状态机；未新增/修改既有 identifier 字符串。
- 真机项：`pending: 待人现场`；本项未开真机与设备场。
