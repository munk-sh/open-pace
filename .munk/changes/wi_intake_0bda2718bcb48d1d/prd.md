# 交付前文档口径收口（候选身份 / 已知限制 / README 现状 / 双语 release notes / 版本口径）

## Scope

只改文档与 README，把「已知限制、候选身份、README 口径、双语 release notes、版本口径」一次对齐。四处落点：

1. `docs/device-manual-acceptance.md`：第 3 节「构建身份标注」改为本次验收候选实录；新增「已知限制（如实）」章节（两条：Dynamic Type 现状、exec sha 不可复现）。
2. `README.md`：删除「阶段 1：工程骨架初始化 … 尚无业务功能」过期描述，改为当前真实状态；新增「界面语言与截图」小节（zh-Hans 单语 + 截图登记规则 + 图集入口）。
3. `docs/release/release-notes-0.1.0.md`（新建，双语草稿）：中文段 + English 段。
4. `docs/screenshots/SHA256SUMS`（新建）：逐文件 sha256 + 逐文件最近改动 commit 全 sha。

## Acceptance Criteria

- ac-doc-only-diff: `git diff --name-only` 与 `git status --porcelain` 只出现 `README.md`、`docs/device-manual-acceptance.md`、`docs/release/release-notes-0.1.0.md`、`docs/screenshots/SHA256SUMS`（外加 `.munk/changes/wi_intake_0bda2718bcb48d1d/**`）。
- ac-code-untouched: `git diff --exit-code -- ios VERSION scripts .github shared android` 退出 0。
- ac-no-banned-literal: `README.md` 与两份文档 grep 结果为 0 命中「已发布」「已上架」「真机已验证」「可复现构建」「已支持 AX5」五个字面（**含「禁止写…」这类负面引用也不得出现原文**，必须换写成不含该字面的表述）。
- ac-readme-current-state: README 不再出现「阶段 1：工程骨架初始化」「尚无业务功能」；明确写出 V1 闭环已实现、已过代码层门与模拟器门、真机终验待人现场（按 `docs/device-manual-acceptance.md`）、当前尚未发布。
- ac-readme-no-version-literal: `README.md` 不含根 `VERSION` 字面值 `0.1.0`（`scripts/check-ios-scripts.sh` 的 `ac-no-version-literal` 会因命中而红）；因此 README 只链 `docs/release/` 目录，不直接写带版本号的文件名或版本号。
- ac-readme-lang-screenshots: README 存在「界面语言与截图」小节，且至少覆盖：界面语言 zh-Hans 单语；内嵌中文界面截图只允许出现在中文正文；将来新增英文 README 时不得内嵌 UI 截图，只写一句 `Interface language: Simplified Chinese` 并链到中文图集；新增/替换截图必须同步登记 sha256 与该文件最近改动 commit 全 sha（`git log --format=%H -1 -- <file>` 实取，不许猜）。
- ac-screenshots-manifest: `docs/screenshots/SHA256SUMS` 存在，含 6 行 `<sha256>  docs/screenshots/<file>`，在仓库根执行 `shasum -a 256 -c docs/screenshots/SHA256SUMS` 全部 `OK`；并逐文件记录最近改动 commit 全 sha（现测 6 张全为 `56aad8954cc6e64d36c716bcaa79ecf333078464`）。
- ac-manual-candidate-identity: `docs/device-manual-acceptance.md` 第 3 节含：候选包 `artifacts/candidates/Release-candidate-dac291a.zip`、zip sha256 `15b9043c2d0d78835cbcc1e4d59b76e3b12eb55d6c6f846814124487cce13415`、`535634` 字节、commit `dac291a22044ed7c69d659361112cee69ec98c6b`、版本 `0.1.0(1)`、bundle id `sh.munk.purepace`、包内 Info.plist `UIBackgroundModes = ["location","audio"]`；并原文写死「验收键 = zip sha256 + 包内 Info.plist 的 UIBackgroundModes 实际数组；exec sha 只作辅助记录」。
- ac-manual-known-limits: 手册新增「已知限制」章节，两条都在：① Dynamic Type——生产 `Typography.control` 为固定 20pt 档（`Font.system(size:)`，取自 `DesignTokens.Typography.titleSize = 20`），不随 Dynamic Type 缩放，AX5 仅由注入式几何断言（门断言）覆盖，属测试注入几何而非运行态实测；② 构建不可复现——exec sha 跨派生数据路径不可复现（主二进制内嵌 57 处派生数据路径字符串，且 `LC_UUID` 每次链接随机、连带 CDHash 变化），因此不声明任何「可复现」的构建属性，验收只认 zip sha256 + 包内 Info.plist。
- ac-release-notes-bilingual: `docs/release/release-notes-0.1.0.md` 存在，含中文段与 `## English` 段；写明本版是 V1 收口候选、尚未发布；列闭环能力（一键开跑 → 后台记录 → 每公里语音播报不打断音乐 → 结束保存 → 历史 → GPX 导出/分享）；写明无账号 / 无广告 / 无社交 / 数据本地；列已知限制（UI 中文单语、真机终验待人现场、Dynamic Type 现状、exec sha 不可复现）。
- ac-version-policy-recorded: 版本口径写入 release notes（或手册）：验收候选 = `0.1.0(1)`；发布用版本号提升必须在新切点重出候选并重算 zip sha；旧包原样保留并在记录里注明作废原因（不覆盖、不删除、不改名）；`VERSION` 文件零改动。
- ac-no-release-side-effects: 本项未打 tag、未 push、未上传 ASC/TestFlight、未重出候选包、未重算任何 sha、未改 `docs/verification-matrix.md`。

## Non-Goals

- 不改任何代码：`ios/PurePace/**`、`ios/project.yml`、`ios/Core`、`ios/RunCore`、`android/**`、`shared/**`、`scripts/**`、`.github/**`、`.munk/code-gates.json` 全部零改动；不改 `VERSION`。
- 不重出候选包、不重算 zip/exec sha、不打 tag、不 push、不建 GitHub Release、不碰 ASC / TestFlight。
- 不改 `docs/verification-matrix.md`（被 `DocsVerificationMatrixTests` 结构守护：纯表格、恰 10 行）。
- 不改 `docs/release/candidates/*.md` 历史候选记录、不改 `docs/release/testflight-runbook.md`（`check-ios-release.sh` 校验其占位符口径）。
- 不做 UI / 文案之外的产品改动，不新增页面、不新增截图二进制。

## Implementation Constraints

### 候选身份事实（Intake 实测，Coding 直接引用，勿重算）

| 字段 | 实录值 | 取证方式 |
| --- | --- | --- |
| zip | `artifacts/candidates/Release-candidate-dac291a.zip`（仓外 `…/products/codebase_19e8ad47434ff059/artifacts/candidates/`，本体不入 git） | `ls` |
| zip sha256 | `15b9043c2d0d78835cbcc1e4d59b76e3b12eb55d6c6f846814124487cce13415` | `shasum -a 256` |
| zip 字节数 | `535634` | `stat -f%z` |
| commit | `dac291a22044ed7c69d659361112cee69ec98c6b`（短 `dac291a`） | 出包记录 + `git log` |
| 版本 / bundle id | `0.1.0`、build `1`、`sh.munk.purepace` | 解包后 `PlistBuddy` 实读 |
| `UIBackgroundModes` | `Array { location, audio }` | 解包 `PurePace.app/Info.plist` 实读 |
| exec sha256 | `7b0a5b7288de7ac2d0e353a21b3475dd50bd6f070784b2a188758cf74bc23165`（2127088 B；辅助记录，不作验收依据） | 同目录 `.txt` 记录 |
| 不可复现差异来源 | 主二进制内嵌 57 处派生数据路径字符串（每处随路径长度变化）+ `LC_UUID` 每次链接随机（连带 CDHash/CMS 摘要不同） | 出包记录双次对照实测 |

### 门禁硬约束（这两个坑必须避开，否则 code_gates 或验收漫游会红）

1. **README 不得出现 `0.1.0` 字面值**：`scripts/check-ios-scripts.sh` 的 `ac-no-version-literal`（约 602–612 行）会 `grep -Fn -- "$(cat VERSION)" README.md`，命中即 fail。所以 README 不写版本号、不写 `docs/release/release-notes-0.1.0.md` 这种带版本的文件名——只链 `docs/release/` 目录。版本号只出现在两份 `docs/` 文档里（`scripts/` + `README.md` 才受限）。
2. **现有 `docs/device-manual-acceptance.md` 第 6 节原文含被禁字面**：「禁写「真机已验证」：…」这句自身就含 `真机已验证`。必须改写为不含该字面的等价句（例如「没有现场记录就没有真机结论，模拟器通过不等于真机通过」），否则 `ac-no-banned-literal` 必红。同理写禁止项时用「不得表述为『AX5 档已覆盖』或『辅助字号已支持』」这类不含被禁字面的措辞。
3. 手册章节编号保持 1–6 不变，新增「已知限制」作为**第 7 节**追加在末尾，并在第 3 节末尾加一句「原因见第 7 节」——避免重排既有编号打断「第 3 节」等引用。

### README 落点建议

- 第 3 行后的现状段替换为：V1 闭环已实现（一键开跑 → 后台记录 → 每公里语音播报不打断音乐 → 结束保存 → 历史 → GPX 导出/分享）；已过代码层门（`.munk/code-gates.json`）与模拟器门（`.github/workflows/ios.yml`）；真机终验由人按 `docs/device-manual-acceptance.md` 执行；当前尚未发布，版本以根 `VERSION` 为唯一真源。
- 新增「界面语言与截图」小节置于「跑步链路验收自动化」之后、门禁段落之前更自然；图集可内嵌 2–3 张关键屏（`run-not-started.png`、`run-running-dark.png`、`history-detail.png`），并链 `docs/screenshots/` 与 `docs/screenshots/SHA256SUMS`。
- 其余既有小节（冻结技术栈 / 版本 / 构建与测试入口 / 跑步链路验收自动化）保留，只修正已过期措辞。

### SHA256SUMS 格式

- 6 行 coreutils 风格：`<sha256>  docs/screenshots/<file>`（两空格分隔），路径相对仓库根，保证在仓库根 `shasum -a 256 -c docs/screenshots/SHA256SUMS` 可校验。
- `#` 开头注释行用于登记逐文件 commit 全 sha 与生成/校验命令说明（`shasum -c` 会忽略注释行）。
- 现测 shas：
  - `d1c8e2c1bb89945ab10096a200bbb82fcdd663eaa4333a81dccc9afa2a7cd040` history-detail.png
  - `c61cb8141df27d530eada63fe0ebc56e1d458d2954a9367076b79694a50b7a0b` history-empty.png
  - `17d1d40a3d87d2ed8523855b0c4c5f4037a7dd02f1c37854b790e6b2861467b1` run-not-started.png
  - `35a35473cb1c89bd8ba88f8578507621a084d02aaf2558fd9dfe304b3b472164` run-running-dark.png
  - `7e36859873059359840e9cd46815e51ab718e905b9a912af20efefa75c1f2b53` run-running.png
  - `18dfd87c9483eaa94ba0165cff041daa191be53dadac85e43ae59a050cd6a30a` settings.png
  - 六张最近改动 commit 全 sha：`56aad8954cc6e64d36c716bcaa79ecf333078464`（`git log --format=%H -1 -- <file>` 实取）

### 文字口径

- 只写可核对的事实；未在真机执行的一律 `pending: 待人现场`。
- 收口时跑一次：`grep -nE "已发布|已上架|真机已验证|可复现构建|已支持 AX5" README.md docs/device-manual-acceptance.md docs/release/release-notes-0.1.0.md` 必须 0 命中，并把该命令与空输出写进 digest。
