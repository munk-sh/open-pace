# Domain: device-manual-acceptance

## 范围

- 承载 `docs/device-manual-acceptance.md` 这一页真机手测手册的契约：`## N.` 小节结构与编号、四个检查点顺序与判据、锁屏与解锁判据、开头使用前提三条、`pending: 待人现场` 口径。
- 纯文档域：不含代码、脚本、CI 门腿、证据目录与设备清单；真机执行由人手在交付后按手册完成，agent 与 CI 一律不代跑。
- 与 `ios-device-verification` / `ios-device-run`（已下线的 agent 真机域）方向互补：本域只定义人手手册的可用性，不恢复任何 agent 侧真机脚本、UI 用例或门禁。
- 手册对齐 `goal.md` 阶段 3「交付终验」四项（真机开跑 / 锁屏 1 分钟 / 解锁看距离曲线 / 导出 GPX），并与 `README.md`、`AGENTS.md` 的「交付后由人按手册手测」表述一致。

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
- ac-doc-only-diff：改动文件仅 `docs/device-manual-acceptance.md`（可含 `docs/release/stage4-prereqs.md` 至多一行链接）；`ios/`、`android/`、`shared/`、`scripts/`、`.github/` 零改动。
- ac-lint-green：改动后本地 lint 门退出 0（至少 `bash -n scripts/version.sh`；若涉及既有门禁脚本则 `bash scripts/check-baseline.sh` 仍绿）。

## 非目标

- 不改任何代码、测试、CI；不出包、不做真机验收、不写「真机已验证」或任何真机结论。
- 不重写既有「核心闭环 / 构建身份 / 人耳判定 / 定位权限 / pending 语义」内容与口径，只做补齐与编号顺延。
- 不新增流程、脚本、证据目录或设备清单；不引入主题系统 / 模板化改版，不扩写为多页文档。
- 不在本域解读 verification-matrix 或回填任何验证结论。

## 实现约束

- 单一必改文件：`docs/device-manual-acceptance.md`；`docs/release/stage4-prereqs.md` 最多加一行指回手册的链接，其余文件不动。
- 行文保持现有中文风格与 `## N.` 编号；新增「锁屏与解锁」排在「核心闭环」之后，原第 2~5 节顺延为 3~6；开头「使用前提」可用不占序号的小节标题或首段。
- 版本号以根 `VERSION`（当前 `0.1.0`）为单一真源，手册内不写死其它版本；构建身份（zip `sha256` + commit 全 sha）只记录，不做脚本校验或人工重算比对。
- 锁屏判据不得要求静止段距离增长：只判「计时继续 + 未崩溃 + 未退出记录态」，距离变化以 GPS 漂移为限。
- 口径不得与 `README.md` / `AGENTS.md` 冲突，不回改这些文件；真机项恒为 `pending: 待人现场`。
- 手册本身不得成为门禁依据：不新增 `.munk/code-gates.json` 门、不新增 `scripts/**` 断言来校验手册措辞。

## 最近交付证明

- workItemId: wi_intake_1892d8ecf659a1f8（2026-11-11，pass）
- 交付：`docs/device-manual-acceptance.md` 由原 5 节（核心闭环一条 / 编号 1~5）补齐为「开头使用前提三条 + 1 核心闭环（四个检查点）→ 2 锁屏与解锁 → 3 构建身份 → 4 人耳判定 → 5 定位权限 → 6 状态语义」，编号连续无跳号。四个检查点各自带「做什么 + 通过判据」；锁屏节给出「记锁屏前距离/用时 → 锁屏 ≥60 秒 → 解锁记数」序列，通过只看「仍处记录态 / 计时继续走 / 未崩溃」三条，并显式写明「静止段不要求距离增长」、距离变化以 GPS 漂移为上限；开头补干净安装、`VERSION` 0.1.0、zip `sha256` + commit 全 sha 三条前提；末尾补「本手册不含自动化驱动步骤」一句。
- 偏离与未做：无代码、测试、CI、脚本、`ios/`、`android/`、`shared/` 改动；`docs/release/stage4-prereqs.md` 未加链接（该文件已不再提及手册，无需指回，留作后续需要时再补）；真机四项全部保持 `pending: 待人现场`，未产生任何真机结论。
- 验证：`code_gates` 22 门 attempt 001 全绿（含 `lint`、`lint-ios-shell`、`test`），本项 diff 仅一个 markdown 文件（38 增 7 删）。
