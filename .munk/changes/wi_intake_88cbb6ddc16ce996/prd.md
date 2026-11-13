# Release prep：0.1.0 版本语义与发布流水线语义收敛（不打 tag / 不发布）

## 范围

只做发布前的**文字口径**与**流水线语义**收敛，版本数值零改动（仍是 `0.1.0`，候选已定，只允许 `x.y.z`）。

1. **版本语义单点收敛**：根 `VERSION` 仍为唯一真源且数值不变；Android `versionName` / iOS 工程版本 / `scripts/version.sh` 读取链路保持派生，不新增硬编码。新增根 `CHANGELOG.md`（Keep a Changelog 风格，首条 `0.1.0`，注明未发布）；README「版本」章节加版本表（版本 / 日期 / 状态 / CHANGELOG 链接），并新增一条**三源一致断言**（README 表首行版本 == CHANGELOG 首条版本 == `VERSION`），断言必须可判红（构造不一致输入即红），且判红不依赖改生产代码。
2. **新增 `.github/workflows/release.yml`**：仅 `workflow_dispatch` 触发；tag 默认从根 `VERSION` 派生（`v` + 版本号），dispatch 可显式覆盖 tag；文件内零硬编码版本号；不得 push 任何分支；permissions 只给创建 tag / Release 的最小集；不自动发布。配套结构断言：缺 VERSION 派生 / 出现硬编码版本 / 出现分支 push 任一即红。
3. **`docs/release/release-notes-0.1.0.md` 改写**：英文正文（`What's in this release` / `What's covered` / `Privacy` / `Known limitations`）+ 文末 zh-CN 折叠段（`<details><summary>简体中文</summary>…</details>`）；保留「尚未发布」如实表述；禁写「已发布 / 已分发 / 可分发」；已知限制三条如实保留（zh-Hans 单语、真机项 `pending: 待人现场`、Dynamic Type 不跟随）。
4. **L1 本地必验全绿**：lint / static / 结构契约 / `swift build|test` / 单测 / Android build+test；`ios.yml` 权威腿（全量 UI / 模拟器）本项不在本地跑、不改腿，靠 push 触发。

## 验收

- ac-version-value-frozen: 根 `VERSION` 仍为单行 `0.1.0`（`^[0-9]+\.[0-9]+\.[0-9]+$`、无 BOM/CRLF），本项对 VERSION 零改动（`git diff -- VERSION` 为空）。
- ac-version-derivation-intact: `bash scripts/version.sh` 输出 `0.1.0`；`android/app/build.gradle.kts` 的 `versionName = repoVersion` 仍由根 `VERSION` 配置期派生；iOS `MARKETING_VERSION` 仍由 `scripts/sync-ios-version.sh` 从 `VERSION` 生成到 `ios/Config/Version.xcconfig`；三处均无新增硬编码数值。
- ac-changelog-exists: 根 `CHANGELOG.md` 存在，含 `# Changelog` 与 Keep a Changelog 风格段落；首条版本标题为 `## [0.1.0] - <YYYY-MM-DD>`，其下显式标注未发布状态（含「未发布」字样），条目不声明任何已发布/已分发事实。
- ac-readme-version-table: README「版本」章节含四列表格（版本 / 日期 / 状态 / CHANGELOG），首条数据行版本列为 `0.1.0`、状态列为未发布口径、CHANGELOG 列为 `./CHANGELOG.md` 的相对链接；README 其它任何位置不出现版本字面值，且不出现带版本号的 release notes 文件名（仍只链 `docs/release/` 目录）。
- ac-version-tri-source-consistency: 新增断言校验 README 表首行版本、CHANGELOG 首条版本、`VERSION` 三者相等，并校验 README 日期列与 CHANGELOG 首条日期一致；三者一致时通过、任一不一致时非零退出。
- ac-version-drift-red-selftest: 上述断言的判红自检在临时沙箱副本上执行（不修改生产文件）：把 README 表首行版本改成与 `VERSION` 不同、把 CHANGELOG 首条版本改成不同值，两种输入都必须非零退出；自检通过时脚本整体仍判绿。
- ac-no-hardcoded-version-scope: `scripts/check-baseline.sh` 的 `ac-no-hardcoded-version` 与 `scripts/check-ios-scripts.sh` 的 `ac-no-version-literal` 在新增版本表后仍为绿；禁字面值范围只对「README 版本表数据行」开一个受控例外，README 其余正文与全部 `scripts/*.sh` 仍回归即红；断言未被删除、未被无条件跳过。
- ac-release-workflow-dispatch-only: `.github/workflows/release.yml` 存在且 YAML 可解析，顶层 `name` / `on` / `jobs` 非空，`on` 只含 `workflow_dispatch`（不含 `push` / `pull_request` / `schedule`），因此不 dispatch 就不会动。
- ac-release-workflow-tag-derived: 工作流默认 tag 由 `VERSION` 派生（经 `scripts/version.sh` 或等价读取），形态为 `v` + `x.y.z` 并在解析后校验匹配 `^v[0-9]+\.[0-9]+\.[0-9]+$`；`workflow_dispatch` 的 `inputs.tag` 可显式覆盖默认值；工作流文件内不含任何 `x.y.z` 版本字面值（含不允许出现 `release-notes-0.1.0.md` 之类带版本文件名，notes 路径由 tag 派生）。
- ac-release-workflow-no-branch-push: 工作流内 `git push` 只出现显式 tag refspec（`refs/tags/$TAG`），不含分支 push、`--tags`、`--force`；`permissions` 只给 `contents: write`（创建 tag / Release 最小集），不出现其它写权限；不出现 ASC / TestFlight / 商店上传调用，不写入任何凭据。
- ac-release-workflow-structure-red-selftest: 结构断言覆盖存在性、YAML 解析、仅 dispatch 触发、tag 派生、无版本字面值、无分支 push、最小权限七类，并对三类反例副本（删掉 VERSION 派生 / 注入硬编码版本 / 加入分支 push）分别判红；反例只在临时副本上进行，不改生产文件。
- ac-release-notes-structure-rewritten: `docs/release/release-notes-0.1.0.md` 为英文正文四节（`What's in this release` / `What's covered` / `Privacy` / `Known limitations`），文末为 `<details><summary>简体中文</summary>` 折叠 zh-CN 段落；zh-CN 段落内含与英文同构的事实（未发布、能力、隐私、三条限制）。
- ac-release-notes-not-released-wording: 全文仅出现否定式未发布表述（如 “Not released yet” / 「尚未发布」）；对肯定式「已发布 / 已分发 / 可分发」与英文 `released` / `shipped` / `distributable` 的肯定用法零命中（否定上下文不算命中）。
- ac-release-notes-known-limitations: Known limitations 恰三条且逐条如实：zh-Hans 单语无其它本地化；真机项 `pending: 待人现场`（锁屏 / 定位授权 / 人耳听感按 `docs/device-manual-acceptance.md`）；Dynamic Type 固定 20pt 不随系统缩放（不得表述为「AX5 已覆盖」）。原「构建产物不可逐字节复现」事实不以删除方式消失，改为 What's covered 下的 Build reproducibility 短段保留。
- ac-l1-gates-green: 本地以下门全绿：`lint` / `lint-baseline` / `lint-ios-core` / `lint-ios-scripts` / `lint-ios-release` / `lint-ios-shell` / `lint-ios-workflow` / `lint-android` / `lint-android-workflow` / `lint-ios-run-core` / `build-ios-core` / `build-ios-run-core` / `build-ios` / `test-ios-core` / `test-ios-run-core` / `test-ios` / `build-android` / `test-android` / `test` / `check-shared` / `check-gpx-export` / `check-shell-expansion`，且 `.munk/code-gates.json` 未被修改（不新增门）。
- ac-pipeline-untouched: `.github/workflows/ios.yml` 与 `.github/workflows/android.yml` 字节未变；本项不声称任何一次 `ios.yml` 全量腿结论（不引用未发生的 run）。
- ac-no-release-actions: 本项未打 tag（`git tag --points-at HEAD` 不含新 tag）、未创建 GitHub Release、未上传 ASC/TestFlight、未改 `VERSION` 数值。
- ac-commit-face-split: 交付 commit 按面拆分且互不混合——`code`（`.github/workflows/release.yml`、`scripts/**`）、`fold`（`CHANGELOG.md`、`README.md`、`docs/release/**`）、`prd`（`.munk/changes/{workItemId}/**`）；任一 commit 的 `--name-only` 只落在一面内。

## 非目标

- 不打 tag、不建 GitHub Release、不上传 ASC / TestFlight、不触发任何真实分发动作。
- 不改 `VERSION` 数值（保持 `0.1.0`），不改候选口径，不重切候选。
- 不改 UI / 截图 / 配色 / `DesignTokens`，不重开 UI 讨论。
- 不新增产品功能，不改产品 `goal.md` 与待验卡。
- 不改 `ios.yml` / `android.yml` 既有腿（不合并、不拆段、不放宽 timeout、不加 `continue-on-error`）。
- 不新增门、不改 `.munk/code-gates.json`、不新建验证基建；只写本项需要的断言。
- 不修历史候选项与 `docs/release/candidates/**`、不动 `stage4-prereqs.md` / `testflight-runbook.md` 的状态结论。

## 实现约束

**版本链路现状（保持派生，勿改）**
- `VERSION`：单行 `0.1.0`，唯一真源。
- `scripts/version.sh`：唯一读取入口（`0.1.0` 输出，非法格式非零退出）。
- Android：`android/app/build.gradle.kts:11` `val repoVersion = rootProject.file("../VERSION").readText().trim()`，`:22` `versionName = repoVersion`。
- iOS：`scripts/sync-ios-version.sh` 生成 `ios/Config/Version.xcconfig` 的 `MARKETING_VERSION`；`ios/project.yml` 经 `configFiles` 引用，`CURRENT_PROJECT_VERSION: "1"` 为 build 号（非版本号）。

**已知红灯冲突（必须先处理，否则本项不可能全绿）**
- `scripts/check-baseline.sh:142-150` `ac-no-hardcoded-version`：对 `README.md` + `scripts/*.sh` 做 `grep -Fn` 版本字面值。
- `scripts/check-ios-scripts.sh:817-828` `ac-no-version-literal`：对 `scripts/*.sh` + `README.md` 同样 `grep -Fn`。
- README 版本表一旦写入 `0.1.0`，上述两条必红。处理方式只能是**受控收窄**：先剔除「版本表数据行」再 grep，其余 README 正文与全部 `scripts/*.sh` 继续禁字面值；禁止整条删除 / 无条件跳过，并须保留或补反例自检（表格外写入字面值仍判红）。新三源一致断言即是该例外的补偿控制。

**断言落点（不新增门、不改 code-gates.json）**
- 三源一致 + CHANGELOG/README 结构 + `release.yml` 结构断言统一加进 `scripts/check-baseline.sh`（已被 `test` 门执行）；断言实现为「接受 root 参数」的函数，反例自检在 `mktemp -d` 副本上跑，不改生产文件。
- 反例最少覆盖：README 表首行版本不符、CHANGELOG 首条版本不符、`release.yml` 删派生 / 注入字面值 / 加分支 push。

**README 版本表形态**
- 列：版本 / 日期 / 状态 / CHANGELOG；首行 `0.1.0` / `2026-11-14` / 「未发布（候选）」/ `[CHANGELOG](./CHANGELOG.md)`。
- 不得写出 `docs/release/release-notes-0.1.0.md` 这类带版本文件名（继续只链 `docs/release/` 目录），否则命中字面值断言。

**CHANGELOG 形态**
- `# Changelog` + Keep a Changelog 说明段；首条 `## [0.1.0] - 2026-11-14`，其下显式「未发布（候选）」状态行；条目只陈述已交付事实（V1 闭环、隐私、三条已知限制指针），不写发布日期已过/已分发话术。

**`release.yml` 契约**
- `on: workflow_dispatch` 唯一触发（`inputs.tag` 可选，默认空）；checkout `fetch-depth: 0`。
- 默认 tag：`v$(bash scripts/version.sh)`；覆盖分支同样校验 `^v[0-9]+\.[0-9]+\.[0-9]+$`；重复 tag 时显式失败而非覆盖。
- notes 路径由 tag 派生（`notes="docs/release/release-notes-${TAG#v}.md"`）并做存在性校验——不得出现带版本的文件名。
- `permissions: contents: write`（仅此一项）；push 只允许 `git push origin "refs/tags/$TAG"`；无分支 push、无 `--tags` / `--force`；无 ASC/TestFlight/商店上传；不写凭据。

**release notes 改写决策**
- Known limitations 恰三条（按指令：zh-Hans 单语 / 真机 `pending: 待人现场` / Dynamic Type 不跟随）。
- 原第 4 条「构建产物不可逐字节复现（57 处派生路径 + `LC_UUID` 随机）」不得删除事实：迁到 `What's covered` 下的 Build reproducibility 短段，不列为第 4 条限制；在回执中显式标注该决策供人复核。

**执行与交付纪律**
- 本地只跑 L1 与结构门；`ios.yml` 全量腿靠 push，本项不跑、不改、不引用未发生的 run。
- commit 三面拆分：`code` / `fold` / `prd` 互不混面（本产品 2026-11-13 已发生过混面拦截）。
- 预算：≤8M token、≤90 分钟墙钟；到点即停，交「已做 / 未做 / 已过门 / 未闭合点」回执，不续命、不重跑已绿门、不弱化断言。
