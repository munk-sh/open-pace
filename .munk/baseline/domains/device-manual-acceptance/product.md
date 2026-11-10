# Domain: device-manual-acceptance

## 范围

- 承载 `docs/device-manual-acceptance.md` 这一页真机手测手册的契约：`## N.` 小节结构与编号、四个检查点顺序与判据、锁屏与解锁判据、开头使用前提三条、`pending: 待人现场` 口径。
- 纯文档域：不含代码、脚本、CI 门腿、证据目录与设备清单；真机执行由人手在交付后按手册完成，agent 与 CI 一律不代跑。
- 与 `ios-device-verification` / `ios-device-run`（已下线的 agent 真机域）方向互补：本域只定义人手手册的可用性，不恢复任何 agent 侧真机脚本、UI 用例或门禁。
- 手册对齐 `goal.md` 阶段 3「交付终验」四项（真机开跑 / 锁屏 1 分钟 / 解锁看距离曲线 / 导出 GPX），并与 `README.md`、`AGENTS.md` 的「交付后由人按手册手测」表述一致。
- 兼管**交付前文档口径收口**：`README.md` 的当前状态段与「界面语言与截图」小节、`docs/release/release-notes-<version>.md` 双语草稿、`docs/screenshots/SHA256SUMS` 截图校验清单、以及候选身份与版本口径的落纸一致性。四处落点只写事实与可核对值，不承担出包、发布与验证结论。

## 验收

- ac-doc-exists：`docs/device-manual-acceptance.md` 存在且非空，改动后仍是一页可读清单，不新增解释性长文或造成章节膨胀。
- ac-four-checkpoints-in-order：文档按顺序给出四个可执行检查点——①真机开跑 ②开跑后按电源键锁屏并保持 ≥1 分钟 ③解锁回前台看距离与计时 ④结束保存 → 历史选中本次 → 导出 GPX；每条都写「做什么 + 看到什么算通过」的明确判据，无「大概 / 应该 / 视情况」等模糊措辞。
- ac-lock-section-numbered：存在 `## N. 锁屏与解锁` 小节，N 紧接「核心闭环」小节；全篇 `##` 阿拉伯数字编号从 1 起连续，无跳号与重号。
- ac-lock-steps-complete：该节写全执行序列：开跑 → 按电源键锁屏 → 记下锁屏前的距离与用时 → 锁屏 ≥60 秒 → 解锁回前台 → 记下解锁后的距离与用时。
- ac-lock-pass-criteria：解锁后的通过判据只有三条——仍处记录态（计时界面 / 记录态未退出）、计时继续走、App 未崩溃；距离增长仅作观察项。
- ac-no-static-distance-requirement：文档含「静止段不要求距离增长」等价表述，明确不得把静止段距离增长当作通过条件，距离变化以 GPS 漂移为上限。
- ac-prereq-clean-install：开头「使用前提」含三条要素——干净安装（先删除 App 再安装候选包）、版本号（根 `VERSION`，当前 0.1.0）、构建身份（候选 zip `sha256` + 来源 commit 全 sha）。
- ac-pending-semantics-kept：保留「未做一律 `pending: 待人现场`」「禁写『真机已验证』」口径；全文不把未执行项写成通过 / 已验证，也不出现冒充真机结论的表述。
- ac-no-waveform-or-automation：手测步骤不采集波形、不比对数表、不含自动化驱动步骤（XCUITest / simctl / 脚本）；提及自动化只允许作为「本手册不做」的说明，不得成为执行步骤。
- ac-operator-budget：文档明确执行者按顺序 ≤5 分钟完成；失败时只记录现场现象与包 / commit 身份，不改代码、不做现场调试。
- ac-doc-only-diff：改动落点白名单 = `README.md`、`docs/device-manual-acceptance.md`、`docs/release/release-notes-<version>.md`、`docs/screenshots/SHA256SUMS`（另可含 `.munk/changes/<workItemId>/**`）；`git diff --name-only` 与 `git status --porcelain` 不得出现白名单外路径。
- ac-code-untouched：`git diff --exit-code -- ios VERSION scripts .github shared android` 退出 0；本轮不动任何代码、工程配置、脚本与门禁定义。
- ac-lint-green：改动后本地 lint 门退出 0（至少 `bash -n scripts/version.sh`；若涉及既有门禁脚本则 `bash scripts/check-baseline.sh` 仍绿）。
- ac-no-banned-literal：`README.md` 与本次两份 `docs/` 文档对「已发布」「已上架」「真机已验证」「可复现构建」「已支持 AX5」五个字面 0 命中；写禁止项时也必须换写成不含该字面的等价措辞（负面引用同样算命中）。
- ac-readme-current-state：`README.md` 不再出现「阶段 1：工程骨架初始化」「尚无业务功能」；明确写出 V1 闭环已实现、已过代码层门（`.munk/code-gates.json`）与模拟器门（`.github/workflows/ios.yml`）、真机终验由人按手册执行、当前尚未发布且版本以根 `VERSION` 为唯一真源。
- ac-readme-no-version-literal：`README.md` 不含根 `VERSION` 字面值（`scripts/check-ios-scripts.sh` 的 `ac-no-version-literal` 以 `grep -Fn` 判定，命中即红）；README 只链 `docs/release/` 目录，不写带版本号的文件名或版本号。
- ac-readme-lang-screenshots：`README.md` 含「界面语言与截图」小节，覆盖界面语言 zh-Hans 单语、内嵌中文界面截图只允许出现在中文正文、将来新增英文 README 时不得内嵌 UI 截图且只写一句 `Interface language: Simplified Chinese` 并链到中文图集、新增或替换截图必须同步登记 sha256（`shasum -a 256 <file>` 实取）与该文件最近改动 commit 全 sha（`git log --format=%H -1 -- <file>` 实取，不许猜）。
- ac-screenshots-manifest：`docs/screenshots/SHA256SUMS` 存在，含 6 行 `<sha256>  docs/screenshots/<file>`（两空格分隔、路径相对仓库根），在仓库根 `shasum -a 256 -c docs/screenshots/SHA256SUMS` 全部 `OK`；`#` 注释行登记逐文件最近改动 commit 全 sha 与生成/校验命令。
- ac-manual-candidate-identity：手册第 3 节「构建身份标注（本次候选实录）」以表格给出候选包路径、zip sha256、zip 字节数、来源 commit 全 sha（可附短 sha）、版本 / 构建号、bundle id、包内 `Info.plist` 的 `UIBackgroundModes` 实际数组、exec sha（标注仅辅助记录）；并原文写死「验收键 = zip sha256 + 包内 Info.plist 的 UIBackgroundModes 实际数组；exec sha 只作辅助记录」。
- ac-manual-known-limits：手册新增「已知限制」章节且两条都在——① Dynamic Type：生产 `Typography.control` 为固定 20pt 档（`Font.system(size:)`，取自 `DesignTokens.Typography.titleSize = 20`），不随 Dynamic Type 缩放，AX5 仅由注入式几何断言（门断言）覆盖、属测试注入几何而非运行态实测，且不得表述为「AX5 档已覆盖」或「辅助字号已支持」；② 构建不可复现：exec sha 跨派生数据路径不可复现（主二进制内嵌 57 处派生数据路径字符串，`LC_UUID` 每次链接随机并连带 CDHash 变化），因此不声明任何逐字节可复现的构建属性。
- ac-release-notes-bilingual：`docs/release/release-notes-<version>.md` 存在，含中文段与 `## English` 段；写明本版是 V1 收口候选、尚未发布；列闭环能力（一键开跑 → 后台记录 → 每公里语音播报不打断音乐 → 结束保存 → 历史 → GPX 导出/分享）；写明无账号 / 无广告 / 无社交 / 数据本地；列已知限制（UI 中文单语、真机终验待人现场、Dynamic Type 现状、exec sha 不可复现）。
- ac-version-policy-recorded：版本口径写入 release notes（或手册）：验收候选 = 具体 `版本(构建号)`；发布用版本号提升必须在新切点重出候选并重算 zip sha；旧包原样保留并在候选记录里注明作废原因（不覆盖、不删除、不改名）；`VERSION` 文件零改动。
- ac-no-release-side-effects：本域动作不打 tag、不 push、不上传 ASC / TestFlight、不重出候选包、不重算任何既有 sha、不改 `docs/verification-matrix.md` 与历史候选记录。

## 非目标

- 不改任何代码、测试、CI；不出包、不做真机验收、不写「真机已验证」或任何真机结论。
- 不重写既有「核心闭环 / 构建身份 / 人耳判定 / 定位权限 / pending 语义」的判据框架，只做补齐、实录替换与编号顺延。
- 不新增流程、脚本、证据目录或设备清单；不引入主题系统 / 模板化改版，不扩写为多页文档。
- 不在本域解读 verification-matrix 或回填任何验证结论；不改 `docs/verification-matrix.md`、`docs/release/candidates/*.md` 历史候选记录与 `docs/release/testflight-runbook.md`。
- 不重出候选包、不重算 zip / exec sha、不打 tag、不 push、不建 GitHub Release、不碰 ASC / TestFlight（发布与出包属 `ios-release`）。
- 不新增 UI 页面、不改界面文案；不新增或替换截图二进制，只登记现有图集的 sha256 与来源 commit。

## 实现约束

- 必改文件集：`docs/device-manual-acceptance.md` + `README.md` + `docs/release/release-notes-<version>.md` + `docs/screenshots/SHA256SUMS`；其余文件不动。
- 行文保持现有中文风格与 `## N.` 编号；手册章节编号 1–6 保持不变，「已知限制」作为第 7 节追加在末尾，并在第 3 节末尾加一句「原因见第 7 节」，避免打断既有「第 3 节」等引用。
- 版本号以根 `VERSION` 为单一真源，手册与 release notes 只写候选实录值，不写死其它版本；例外禁区：`README.md` 不得出现 `VERSION` 字面值（门禁会 `grep -Fn` 判定），只链 `docs/release/` 目录。
- 写禁止项时必须改写措辞：手册原「禁写『真机已验证』」一句自身含被禁字面，需替换为「没有现场记录就没有真机结论，模拟器通过不等于真机通过」这类等价句。
- 候选身份只引用实测值（zip 路径 / sha256 / 字节数 / commit 全 sha / 版本构建号 / bundle id / `UIBackgroundModes` 数组），现场以解包后 `PurePace.app/Info.plist` 实读为准，不以构建产物或以往记录代替。
- 锁屏判据不得要求静止段距离增长：只判「计时继续 + 未崩溃 + 未退出记录态」，距离变化以 GPS 漂移为限。
- 口径不得在四处落点间互相冲突；真机项恒为 `pending: 待人现场`，模拟器通过不表述为真机通过。
- 文档本身不得成为门禁依据：不新增 `.munk/code-gates.json` 门、不新增 `scripts/**` 断言来校验文档措辞（README 的既有 `ac-no-version-literal` 是唯一相关既有门，须遵守而非扩张）。

## 最近交付证明

- workItemId: wi_intake_0bda2718bcb48d1d（2026-11-11，pass）
- 交付：交付前文档口径一次收口，四周落点。①手册 §3 改为「构建身份标注（本次候选实录）」表格（候选 zip 路径、zip sha256、字节数 535634、commit `dac291a220…`、`0.1.0(1)`、`sh.munk.purepace`、`UIBackgroundModes` 实测数组、exec sha 辅助记录），并写死验收键口 + 指回第 7 节；②手册新增 §7「已知限制（如实）」两条（Dynamic Type 固定 20pt 不随系统缩放、AX5 仅注入式几何断言；exec sha 跨派生数据路径不可复现，57 处路径字符串 + `LC_UUID` 随机）；③`README.md` 现状段改为 V1 闭环真实状态并新增「界面语言与截图」小节（zh-Hans 单语、中文截图只进中文正文、英文 README 不带图只写一句并链图集、截图 sha256 + 来源 commit 登记规则）；④新建双语 `docs/release/release-notes-0.1.0.md`（中文 + `## English`，含闭环能力 / 隐私 / 四条已知限制 / 版本口径）与 `docs/screenshots/SHA256SUMS`（6 行 sha256 + 逐文件来源 commit 注释）。
- 偏离与未做：无代码 / 工程配置 / 脚本 / CI / `VERSION` / `shared` / `android` 改动；未打 tag、未 push、未上传 ASC/TestFlight、未重出候选包、未重算既有 zip/exec sha；未改 `docs/verification-matrix.md`、历史候选记录与 runbook；未新增或替换截图二进制（只登记现有 6 张）；`README.md` 按门禁约束只链 `docs/release/` 目录、不写版本号与带版本文件名。
- 验证：`code_gates` 22 门 attempt 001 全绿；`shasum -a 256 -c docs/screenshots/SHA256SUMS` 6/6 `OK`；禁字面 `grep -nE` 三文档 0 命中；`grep -Fn "$(cat VERSION)" README.md` 0 命中；diff 仅白名单 4 个文档路径。
