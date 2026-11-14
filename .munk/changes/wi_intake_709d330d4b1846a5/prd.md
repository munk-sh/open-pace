# CHANGELOG 首条状态行对齐 README「已推 tag、未分发」口径并加断言

## 范围

上一写项（`wi_intake_d18b07654986d060`，已合入 main `3ed8bd5`）已把 README「当前状态」段、README 版本表首行状态列、release notes 英文 Status 段、zh-CN「本版是什么」段四处统一为「已推 tag（v0.1.0 @ `501ba9e`，2026-11-14，CI ios `43599497314` / android `43599497253`）+ 未分发」。但 `CHANGELOG.md` 首条仍写「状态：**未发布（候选）**」，与 README 对外口径矛盾（tag 已推 = 版本已标记，只有分发未发生）。

本项只收这一处口径缺口：

1. 改写 `CHANGELOG.md` `## [0.1.0] - 2026-11-14` 首条状态行为与 README 同口径，并保留「本条目只陈述已交付事实，不构成任何发布声明」的等价声明。
2. 在 `scripts/check-baseline.sh` 增加一条新断言，钉住「CHANGELOG 首条状态行与 README 版本表首行状态列同口径」，并配内联反例自检（3 组负例必须判红）。
3. 同步修正既有 `ac-version-tri-source-consistency` 里要求 CHANGELOG 含「未发布」的陈旧判据（否则改文档后该断言自相矛盾判红）。

## 验收

- ac-changelog-status-tag-pushed-not-distributed: `CHANGELOG.md` 首条（`## [0.1.0] - 2026-11-14`）状态行同时出现「已推 tag」「tag 指向 sha `501ba9e`」「日期 `2026-11-14`」「未分发」四项事实，并保留「本条目只陈述已交付事实，不构成任何发布声明」等价声明；`bash scripts/check-baseline.sh` 中对应断言为 `[PASS]`。
- ac-changelog-no-forbidden-wording: `CHANGELOG.md` 全文对「已发布 / 已分发 / 可分发 / 已上传 TestFlight / shipped / Released to TestFlight」零命中（英文两词大小写不敏感）；同时「未分发」「未上传 TestFlight」这类否定式不得被判为命中（禁词判据须区分否定式与肯定式）。
- ac-changelog-status-parity-with-readme: `scripts/check-baseline.sh` 新增断言从 README 版本表首行状态列与 CHANGELOG 首条状态行分别独立取值后交叉比对：两侧都必须含「已推 tag」与「未分发」，tag sha 取自两侧实际文本（`grep -Eo '[0-9a-f]{7,40}'` 动态提取）必须一致且两侧都存在，tag 日期必须与 README 表首行日期列 / CHANGELOG 首条标题日期一致；任一侧缺失或不一致即判红（不得用同一 helper 的输出自证，须两份文件各自取证）。
- ac-changelog-status-red-selftest: 同一条断言自带内联反例自检，在 `mktemp` 沙箱副本上必须满足四项：(0) 未改动副本判绿；(a) CHANGELOG 状态行改回「未发布（候选）」判红；(b) CHANGELOG 状态行注入「已分发」类禁词判红；(c) 从 README 删去 tag sha `501ba9e`（使两文档事实不一致）判红。四项任一不成立即该断言判红（不带自检视为缺断言）。
- ac-baseline-two-locale-green: `env LANG= LC_ALL= bash scripts/check-baseline.sh` 与 `LANG=en_US.UTF-8 bash scripts/check-baseline.sh` 均退出码 0，且输出里 ac-changelog-status-tag-pushed-not-distributed / ac-changelog-status-parity-with-readme / ac-changelog-status-red-selftest 三条均为 `[PASS]`。
- ac-no-regression-shell-and-ios-scripts: `bash scripts/check-shell-expansion.sh` 与 `bash scripts/check-ios-scripts.sh` 均退出码 0（新增 shell 代码零裸变量紧跟非 ASCII 字节）。
- ac-version-and-out-of-scope-untouched: `git diff` 证明本项未改 `VERSION`（仍 `0.1.0`）、未改 `README.md`、未改 `docs/release/**`、未改 `.github/workflows/**`、未改 `.munk/code-gates.json`（腿列表与阈值不变，不新增 gate）。
- ac-commit-surface-split: 提交按面拆分且无混面——`code` commit 只含 `scripts/check-baseline.sh`；`fold` commit 只含 `CHANGELOG.md`（`.munk/` 记录独立提交）；任一 commit 不跨面。

## 非目标

- 不打 tag、不建 GitHub Release、不上传 ASC / TestFlight、不改分发状态。
- 不改 `VERSION`（仍 0.1.0），不改 README 任一段（含版本表首行状态列与「当前状态」段），不改 `docs/release/` 双语 release notes。
- 不改 `.github/workflows/**`；不改 `.munk/code-gates.json` 的腿列表、命令与阈值；不新增门禁。
- 不重构 `check-baseline.sh` 既有断言体系，不动 README / release notes / workflow 相关断言。
- 不做 CHANGELOG 结构改版（不新增版本条目、不调整 Added / Known limitations 内容）。

## 实现约束

已确认的事实锚点与偏好（非正式技术方案，Architect 不需要重扫）：

- 文档改动唯一落点：`CHANGELOG.md:7`（当前 `状态：**未发布（候选）**。本条目只陈述已交付事实，不构成任何发布声明。`）。README 版本表首行状态列现状为 `| 0.1.0 | 2026-11-14 | 已推 tag、未分发 | [CHANGELOG](./CHANGELOG.md) |`（README:35，表内状态列不含 sha；sha 在 README:5「当前状态：」段）。因此「同口径」判据按事实集比对：表内状态列负责 已推 tag + 未分发 + 日期列，CHANGELOG 状态行负责 已推 tag + 未分发 + tag sha + 日期，sha 必须在 README 正文（当前状态段）中被佐证且与 CHANGELOG 提取值相等；「删掉 README 里的 tag sha」即判红（负例 (c) 的落点）。
- 脚本改动落点：`scripts/check-baseline.sh`
  - `version_tri_source_problems()` 第 286–289 行：现有判据要求 CHANGELOG 首条含「未发布」且禁 `已发布|已分发|可分发`，必须改为「含未分发 + 禁词零命中」，否则与新文档自相矛盾；其自检用例「README 表首行状态删去未分发未判红」（第 317–320 行）依赖该函数的状态判定，改后须仍然判红。
  - 新增 `changelog_status_parity_problems(root)` 与 `changelog_status_parity_red_selftest_problems(root)`，放在 `version_tri_source_red_selftest_problems()` 之后（约第 337 行后），沿用现有 `pass`/`fail`/`problems` 风格与 `mktemp -d "${TMPDIR:-/tmp}/purepace-*.XXXXXX"` 沙箱惯例。
  - 新增两条断言注册：`ac-changelog-status-parity-with-readme`、`ac-changelog-status-red-selftest`，接在 `ac-version-tri-source-status-red-selftest` 之后（约第 690 行）。另可把「CHANGELOG 首条状态事实」并入同一条断言，避免重复实现同一事实两次。
  - 顶部 `usage()` 第 14–15 行说明同步补充新断言口径（保持 --help 与实现一致）。
- 断言写法卫生（硬约束，已由现有门禁逼出）：
  - 变量展开一律 `${var}` 花括号形式，禁止裸 `$var` 紧跟中文/全角字节（`scripts/check-shell-expansion.sh` 字节级判据）。
  - 空白归一用 `tr -d ' '`（只删 ASCII 空格），不用 `[[:space:]]`，保证 `LANG=`（C locale）与 `LANG=en_US.UTF-8` 下判定一致；中文匹配统一 `grep -F`（字节匹配，不依赖 locale 的编码表）。
  - 反例自检全部在 `mktemp` 副本上执行，不改生产文件；未改动副本必须先判绿（防「恒红假断言」）。
  - 断言不得同源别名自证：README 与 CHANGELOG 事实由各自独立读取取得后比对。
- 禁用词口径（本项硬口径，逐字）：已发布、已分发、可分发、已上传 TestFlight、shipped、Released to TestFlight；否定式（未分发 / 未上传 TestFlight）不算命中。字数与表述可自拟，但四项事实（已推 tag、tag 指向 sha、日期、未分发）与保留声明不得缺。
- 提交纪律：`code`（`scripts/check-baseline.sh`）与 `fold`（`CHANGELOG.md`）分开提交，`.munk/` 记录单独提交；混面会被 delivery 的 `mixed_commit_surface` 拦下。
- 交付必须附证据：改前/改后原文、三组反例判红证据、两种 locale 全绿日志、`check-shell-expansion.sh` 与 `check-ios-scripts.sh` 全绿日志、commit sha。
- 无需 Design / Architect / PM / Change Pack Review；本项按 `Intake → Coding → code_gates → Delivery` 直通。
