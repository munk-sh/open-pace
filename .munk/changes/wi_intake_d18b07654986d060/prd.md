# v0.1.0 发布口径收口：已推 tag + 未分发

## 范围

把仓库里仍写着「当前尚未发布 / Not released yet / 未发布（候选）」的四处发布口径，改成**「已推 tag、未分发」**的准确事实口径，并同步把钉住旧字面量的既有断言改成同一口径的正负两向断言。

事实基线（外部已核验，本项不重跑）：

- tag `v0.1.0` 已于 2026-11-14 推送到远端，指向 commit `501ba9e3fa324100db32436a71db2a80719735c9`。
- tag push 触发的两场 GitHub Actions 均 success，同一 sha：ios run `43599497314`、android run `43599497253`。
- `main` 仍为 `501ba9e`。
- 未上传 TestFlight / 商店，未提供安装包，未建 GitHub Release。

改动落点（恰好四处文档 + 必要的脚本断言）：

1. `README.md` 第 5 行「当前状态」段：删去「当前尚未发布」，写入已推 tag（`501ba9e`，2026-11-14）与 CI 双绿（`43599497314` / `43599497253`）以及**尚未分发**（未上传 TestFlight / 商店、未提供安装包）。
2. `README.md` 第 35 行版本表首行状态列：`未发布（候选）` → `已推 tag、未分发`。
3. `docs/release/release-notes-0.1.0.md` 第 3 行 Status 段：写明 tag `v0.1.0` @ `501ba9e` 已推（2026-11-14）、两次 CI run id、以及 **not distributed**（no TestFlight / App Store / Play upload, no install package, no GitHub Release）。
4. `docs/release/release-notes-0.1.0.md` 第 43 行中文段：同步同一口径（已推 tag + 尚未分发）。

## 验收

- ac-readme-status-tag-pushed-not-distributed: `README.md`「当前状态」段同时出现「已推 tag」与「未分发」两项事实，并写明 tag 指向 `501ba9e`、日期 2026-11-14、两个 CI run id（`43599497314` / `43599497253`）；该段不出现「已发布 / 已分发 / 可下载 / 已上架」。
- ac-readme-version-table-status: README 版本表首行状态列同时含「已推 tag」与「未分发」（空格归一后判定），版本列仍等于根 `VERSION`、日期列仍为 `2026-11-14`、CHANGELOG 列仍为 `./CHANGELOG.md`，三源一致断言仍绿。
- ac-release-notes-tag-pushed-not-distributed: `docs/release/release-notes-0.1.0.md` 的英文 Status 段与 `简体中文` 折叠段各自同时具备「已推 tag（tag v0.1.0 @ 501ba9e, 2026-11-14）」与「未分发（not distributed / 尚未分发）」两项事实，且均写明无 TestFlight / 商店上传、无安装包、无 GitHub Release。
- ac-release-notes-forbidden-wording-zero: release notes 全文（中文 + 英文）在剔除否定式后对 `released / shipped / distributed / distributable / available for download / live on store / 已发布 / 已分发 / 可下载 / 已上架 / 可分发` 零命中。
- ac-release-notes-known-limitations-preserved: release notes 的 `Known limitations` 与 zh-CN 已知限制各仍为 3 条且逐条保留原有事实（zh-Hans 单语、`pending: 待人现场` + `docs/device-manual-acceptance.md`、Dynamic Type 固定 20pt），本项不得删条或弱化。
- ac-release-wording-red-selftest: 对 release notes 的三类反例注入必须判红——(a) 追加肯定式 `This build was shipped.`；(b) 追加 `Released to TestFlight.`；(c) 删除「未分发 / not distributed」事实（只留已推 tag）。未改动副本必须判绿。
- ac-readme-status-red-selftest: 对 README 的同类反例必须判红——(a) 删去「已推 tag」；(b) 删去「未分发」；(c) 注入「已分发」。未改动副本必须判绿。
- ac-version-tri-source-status-red-selftest: 三源一致断言在沙箱里把 README 表首行状态改成只含「已推 tag」（删掉「未分发」）时必须判红，未改动副本判绿（保留既有版本漂移 / 日期漂移两类反例）。
- ac-no-hardcoded-version-unchanged: `ac-no-hardcoded-version`（`check-baseline.sh`）与 `ac-no-version-literal`（`check-ios-scripts.sh`）强度不变——README 版本表数据行仍是唯一受控豁免，表格外正文与 `scripts/*.sh` 出现版本字面量仍判红，既有反例自检保留。
- ac-changelog-and-version-untouched: 根 `VERSION` 仍为 `0.1.0`；`CHANGELOG.md` 首条状态仍含「未发布」且未被本项改动（`ac-changelog-exists` 仍绿）。
- ac-scope-no-pipeline-change: `.github/workflows/{release,ios,android}.yml`、`scripts/archive-ios.sh` 与本项文档口径无关的部分零改动；不新增 gate id、不改 `.munk/code-gates.json` 的 gate 列表。

## 非目标

- 不重推 tag、不补建 GitHub Release、不改 `.github/workflows/release.yml`。
- 不动 `ios.yml` / `android.yml` 既有腿，不改 `VERSION` 数值（仍 0.1.0）。
- 不动 UI、截图、功能面；不新增门或验证基建；不扩范围做新功能。
- 不改 `CHANGELOG.md`（不在四处范围内，其首条仍为「未发布（候选）」；与 README 新口径的字面差异留待下一个写项收口）。
- 不在 release notes 里**新增**已知限制条目（详见「实现约束」中的口径差异说明）。
- 不改 `.munk/baseline/**`（只读参考，不是门）。

## 实现约束

### 文件与行锚点

- `README.md:5`：「当前状态」段（单段，保持一句话结构，末尾仍保留「版本以根 `VERSION` 为唯一真源」与 `docs/release/` 指针）。
- `README.md:35`：版本表首行数据行，状态列。
- `docs/release/release-notes-0.1.0.md:3`：`> Status:` 引用块；`:43`：zh-CN「本版是什么」段。
- 断言改动只落在 `scripts/check-baseline.sh` 的三个函数与其调用点/`usage()` 文案：
  - `version_tri_source_problems`（首行状态判据）
  - `version_tri_source_red_selftest_problems`（新增状态反例）
  - `release_notes_problems`（英文/中文口径 + 禁词）
  - `release_notes_wording_red_selftest_problems`（三类反例）

### 关键口径决定（请 Coding 严格执行，勿自行扩大）

- **README 正文不写版本字面量**：`README.md:5` 不出现 `0.1.0` / `v0.1.0`，改用「已推 tag（`501ba9e`，2026-11-14）」表达同一事实。原因：`ac-no-hardcoded-version` 与 `ac-no-version-literal` 两条既有控制明确禁止 README 版本表之外出现版本字面量，且要求「不新增门 / 不放宽断言」。tag sha + 日期 + run id 已唯一标识该次发布；版本值由同一句的 `VERSION` 指针与下方版本表行承载。release notes 内写 `tag v0.1.0` 不受该控制限制（notes 不在字面量禁令范围内）。
- **两事实必须同现**：任何一处只写「已推 tag」不写「未分发」（或反之）都算不合格；断言必须两向可判红。
- **禁用词**（任何位置、任何语言）：已发布 / 已分发 / 可下载 / 已上架 / `released`（含 `not released` 里被剥离后的正向用法）/ `available for download` / `live on store`。允许的否定表达：尚未分发 / 未分发 / not distributed / no TestFlight / no GitHub Release / 未上传 / 未提供安装包。剔除否定式后再做零命中判定，不得靠删断言或放宽转绿。
- **已知限制口径差异（请如实处理，勿擅自补写）**：本仓 release notes 当前只有 3 条已知限制，仓内不存在「中国区上架 / 审图号（首版不上中国区）」与「轨迹属行踪轨迹敏感个人信息（分发前须补单独同意与隐私政策条目）」这两条文字。本写项按「恰好四处」处理为**保留现状、不新增条目**，并保持 `count = 3` 断言。若产品层要求把这两条落到 release notes，需另开写项，并把 `Known limitations` 的条数断言从 3 同步调整为 5（不得只加文字不改断言）。
- **commit 分面**：`code`（`scripts/check-baseline.sh`）与 `fold`（`README.md` + `docs/release/release-notes-0.1.0.md`）分开提交，不得混面。

### 验证入口（Coding 自证）

- `bash scripts/check-baseline.sh`（含 `ac-readme-*` / `ac-release-notes-*` / `ac-version-*` / `ac-no-hardcoded-version`）
- `bash scripts/check-ios-scripts.sh`（`ac-no-version-literal` 必须仍绿）
- `.munk/code-gates.json` 全绿（不改 gate 列表）
