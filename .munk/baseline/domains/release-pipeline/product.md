# Domain: release-pipeline

发布前语义域：把「版本号唯一真源 → README 版本表 → CHANGELOG」的三源一致、仅手动触发的打 tag 工作流、以及 release notes 的「未发布」文案口径固化为可判红的结构断言。本域只做文字口径与流水线语义，不执行任何真实发布动作（不打 tag、不建 GitHub Release、不上传 ASC / TestFlight / 商店）。归档与 ASC 取证仍归 `ios-release`，仓库脚本契约底座归 `repo-baseline`。

## 范围

- 根 `VERSION` 保持单行 `0.1.0` 唯一真源，本域零改动；Android `versionName = repoVersion` 与 iOS `MARKETING_VERSION`（`scripts/sync-ios-version.sh` → `ios/Config/Version.xcconfig`）仍为派生，无新增硬编码。
- 根 `CHANGELOG.md`：Keep a Changelog 风格，首条 `## [0.1.0] - <YYYY-MM-DD>`，其下显式「未发布（候选）」状态行；条目只陈述已交付事实。
- `README.md`「版本」章节四列表格（版本 / 日期 / 状态 / CHANGELOG），首行 `0.1.0` / `2026-11-14` / 未发布（候选） / `[CHANGELOG](./CHANGELOG.md)`；README 其它正文不出现版本字面值，也不出现带版本号的 release notes 文件名（仍只链 `docs/release/` 目录）。
- `scripts/check-baseline.sh` 新增「接受 root 参数」的断言函数：`version_tri_source_problems` / `version_tri_source_red_selftest_problems` / `release_notes_problems` / `release_notes_wording_red_selftest_problems` / `workflow_parse_problems` / `workflow_trigger_problems` / `workflow_tag_problems` / `workflow_push_problems` / `release_workflow_red_selftest_problems`；反例副本一律落在 `mktemp -d`，不改生产文件。
- 禁字面值断言受控收窄：`scripts/check-baseline.sh` 的 `ac-no-hardcoded-version` 与 `scripts/check-ios-scripts.sh` 的 `ac-no-version-literal` 先剔除 README 版本表数据行再 grep，其余 README 正文与全部 `scripts/*.sh` 继续禁字面值，并保留「表格外写入字面值必判红」的反例自检。
- `.github/workflows/release.yml`：唯一触发 `workflow_dispatch`（可选 `inputs.tag` 覆盖），默认 tag `v$(bash scripts/version.sh)` 且校验 `^v[0-9]+\.[0-9]+\.[0-9]+$`；notes 路径由 tag 派生（`release-notes-${TAG#v}.md`）并做存在性校验；重复 tag 显式失败；`permissions: contents: write` 仅此一项；只 `git push origin "refs/tags/${TAG}"`。
- `docs/release/release-notes-0.1.0.md`：英文正文四节（`What's in this release` / `What's covered` / `Privacy` / `Known limitations`）+ 文末 `<details><summary>简体中文</summary>` 折叠 zh-CN 段；保留「尚未发布 / Not released yet」如实表述；构建不可复现事实迁入 `What's covered` 下的 Build reproducibility 短段。

## 验收

- ac-version-value-frozen: 根 `VERSION` 仍为单行 `0.1.0`（`^[0-9]+\.[0-9]+\.[0-9]+$`、无 BOM/CRLF），本项对 `VERSION` 零改动（`git diff -- VERSION` 为空）。
- ac-version-derivation-intact: `bash scripts/version.sh` 输出 `0.1.0`；`android/app/build.gradle.kts` 的 `versionName = repoVersion` 仍由根 `VERSION` 配置期派生；iOS `MARKETING_VERSION` 仍由 `scripts/sync-ios-version.sh` 从 `VERSION` 生成；三处均无新增硬编码数值。
- ac-changelog-exists: 根 `CHANGELOG.md` 存在，含 `# Changelog` 与 Keep a Changelog 段落；首条版本标题为 `## [0.1.0] - <YYYY-MM-DD>`，其下显式标注「未发布」，条目不声明任何已发布/已分发事实。
- ac-readme-version-table: README「版本」章节含四列表格（版本 / 日期 / 状态 / CHANGELOG），首条数据行版本 `0.1.0`、状态为未发布口径、CHANGELOG 列为 `./CHANGELOG.md` 相对链接；README 其它位置无版本字面值与带版本号 release notes 文件名。
- ac-version-tri-source-consistency: 断言校验 README 表首行版本、CHANGELOG 首条版本、`VERSION` 三者相等，且 README 日期列与 CHANGELOG 首条日期一致；一致时通过、任一不一致时非零退出。
- ac-version-drift-red-selftest: 判红自检在临时沙箱副本上执行（不改生产文件）：README 表首行版本改错、CHANGELOG 首条版本改错，两种输入都必须非零退出；自检通过时脚本整体仍判绿。
- ac-no-hardcoded-version-scope: `ac-no-hardcoded-version` 与 `ac-no-version-literal` 在新增版本表后仍为绿；豁免只对「README 版本表数据行」生效，表格外写入字面值仍判红；断言未被删除、未被无条件跳过。
- ac-release-workflow-exists-parses: `.github/workflows/release.yml` 存在且 YAML 可解析，顶层 `name` / `on` / `jobs` 非空（解析按原文/AST 处理 YAML 1.1 把裸 `on` 当布尔的坑）。
- ac-release-workflow-dispatch-only: `on` 只含 `workflow_dispatch`，不含 `push` / `pull_request` / `schedule`；不 dispatch 就不会动。
- ac-release-workflow-tag-derived: 默认 tag 由 `VERSION` 派生（`v` + `scripts/version.sh` 输出）并校验 `^v[0-9]+\.[0-9]+\.[0-9]+$`；`inputs.tag` 可显式覆盖；工作流文件内不出现任何 `x.y.z` 版本字面值（含带版本文件名）。
- ac-release-workflow-no-branch-push: `git push` 只出现显式 tag refspec（`refs/tags/$TAG`），不含分支 push、`--tags`、`--force`；`permissions` 只含 `contents: write`；不出现 ASC / TestFlight / 商店上传调用与任何凭据写入。
- ac-release-workflow-structure-red-selftest: 结构断言覆盖存在性、YAML 解析、仅 dispatch、tag 派生、无版本字面值、无分支 push、最小权限七类，并对三类反例副本（删掉 VERSION 派生 / 注入硬编码版本 / 加入分支 push）分别判红；反例只在临时副本上进行。
- ac-release-notes-structure-rewritten: release notes 为英文正文四节，文末为 `<details><summary>简体中文</summary>` 折叠 zh-CN 段，zh-CN 段与英文同构（未发布、能力、隐私、三条限制）。
- ac-release-notes-not-released-wording: 全文仅出现否定式未发布表述；对肯定式「已发布 / 已分发 / 可分发」与英文 `released` / `shipped` / `distributable` 的肯定用法零命中（否定上下文不算命中），并有反例自检。
- ac-release-notes-known-limitations: Known limitations 恰三条且如实（zh-Hans 单语；真机项 `pending: 待人现场`；Dynamic Type 固定 20pt 不跟随，不得表述为「AX5 已覆盖」）；原「构建产物不可逐字节复现」事实不删除，改为 `What's covered` 下 Build reproducibility 短段保留。
- ac-l1-gates-green: 本地 `lint` / `lint-baseline` / `lint-ios-core` / `lint-ios-scripts` / `lint-ios-release` / `lint-ios-shell` / `lint-ios-workflow` / `lint-android` / `lint-android-workflow` / `lint-ios-run-core` / `build-ios-core` / `build-ios-run-core` / `build-ios` / `test-ios-core` / `test-ios-run-core` / `test-ios` / `build-android` / `test-android` / `test` / `check-shared` / `check-gpx-export` / `check-shell-expansion` 全绿，且 `.munk/code-gates.json` 未被修改（不新增门）。
- ac-pipeline-untouched: `.github/workflows/ios.yml` 与 `.github/workflows/android.yml` 字节未变；不声称任何一次 `ios.yml` 全量腿结论，不引用未发生的 run。
- ac-no-release-actions: 未打 tag（`git tag --points-at HEAD` 不含新 tag）、未创建 GitHub Release、未上传 ASC / TestFlight、未改 `VERSION` 数值。
- ac-commit-face-split: 交付 commit 按面拆分且互不混合——`code`（`.github/workflows/release.yml`、`scripts/**`）、`fold`（`CHANGELOG.md`、`README.md`、`docs/release/**`）、`prd`（`.munk/changes/{workItemId}/**`）。

## 非目标

- 不打 tag、不建 GitHub Release、不上传 ASC / TestFlight、不触发任何真实分发动作。
- 不改 `VERSION` 数值（保持 `0.1.0`），不改候选口径、不重切候选。
- 不改 UI / 截图 / 配色 / `DesignTokens`，不重开 UI 讨论。
- 不新增产品功能，不改产品 `goal.md` 与待验卡。
- 不改 `ios.yml` / `android.yml` 既有腿（不合并、不拆段、不放宽 timeout、不加 `continue-on-error`）。
- 不新增门、不改 `.munk/code-gates.json`、不新建验证基建；只写本项需要的断言。
- 不修历史候选项与 `docs/release/candidates/**`，不动 `stage4-prereqs.md` / `testflight-runbook.md` 的状态结论。

## 实现约束

- 三源一致判定口径：README 表行按 `|` 拆列比对版本、状态含「未发布」、链接恰为 `[CHANGELOG](./CHANGELOG.md)`；CHANGELOG 首条标题解析版本与日期，版本须等于 `VERSION`、日期须等于 README 表首行日期；首条条目须含「未发布」且不含 `已发布|已分发|可分发`。
- 受控豁免口径：豁免实现是「先剔除版本表数据行再 grep」（`awk '!/^\| *[0-9]+\.[0-9]+\.[0-9]+ *\|/'`），不是白名单路径或整条删除；`check-baseline.sh` 与 `check-ios-scripts.sh` 两侧语义一致，补偿控制是三源一致断言 + 表格外字面值判红自检。
- `release.yml` 口径：`fetch-depth: 0`；重复 tag 用 `git rev-parse -q --verify` 显式失败而非覆盖；notes 路径由 tag 派生并校验存在；不写 `secrets.`，不出现 `fastlane` / `altool` / `transporter` / `notarytool` / `TESTFLIGHT`。
- 断言落点：全部进 `scripts/check-baseline.sh`（`test` 门即 `bash scripts/check-baseline.sh`），函数接受 root 参数以便沙箱副本复用；不新增门、不改 `code-gates.json`。
- YAML 校验口径：用本机已有 `ruby -ryaml`，按原文/AST 处理 `on` 键，避免 Psych 的 YAML 1.1 布尔化误判。
- 文案口径：release notes 全文否定式未发布表述；英文正文四节标题逐字命中；zh-CN 段只在 `<details>` 内，不重复英文全文。
- 执行纪律：本地只跑 L1 与结构门，`ios.yml` 全量腿靠 push（不跑、不改、不引用未发生的 run）；commit 三面拆分 `code` / `fold` / `prd`。

## 最近交付证明

- workItemId: wi_intake_88cbb6ddc16ce996 / at: 2026-11-14T00:24:23+08:00 / status: pass
- note: 新增 `release.yml`（dispatch-only、tag 由 `VERSION` 派生、只 push tag refspec、`contents: write`）、根 `CHANGELOG.md`、README 版本表，release notes 改为英文四节 + zh-CN 折叠段；`check-baseline.sh` 新增三源一致 / release notes 文案 / release.yml 结构断言与沙箱判红自检，`ac-no-hardcoded-version` 与 `ac-no-version-literal` 收窄为版本表行受控豁免。`VERSION`、`ios.yml`、`android.yml`、`code-gates.json` 零改动；22 门 code_gates attempt 001 全绿；未打 tag、未建 Release、未上传 ASC。
