# 真机手测手册补齐：锁屏 1 分钟 / 解锁续记 + 干净安装前提

## 范围

- 只改 `docs/device-manual-acceptance.md`（必要时在 `docs/release/stage4-prereqs.md` 最多加一行链接）。纯文档改动。
- 把手册补齐到 goal.md「阶段 3 交付终验」四项：真机开跑、锁屏 1 分钟、解锁看距离曲线、导出 GPX；人手按一页清单顺序执行即可，全程 ≤5 分钟。
- 新增「锁屏与解锁」一节，编号延续现有 `## N.` 结构（排在「核心闭环」之后，后续小节顺延编号）。
- 开头补「使用前提」：干净安装（先删 App 再装候选包）、版本号（根 `VERSION` 当前 0.1.0）、构建身份（候选 zip `sha256` + 来源 commit 全 sha）。
- 保留既有「核心闭环 / 构建身份 / 人耳判定 / 定位权限 / pending 语义」六节内容与口径，不重写。

## 验收标准

- ac-doc-exists: `docs/device-manual-acceptance.md` 存在且非空，改动后仍是一页可读清单（不新增解释性长文/章节膨胀）。
- ac-four-checkpoints-in-order: 文档按顺序给出四个可执行检查点——①真机开跑 ②开跑后按电源键锁屏并保持 ≥1 分钟 ③解锁回前台看距离与计时 ④结束保存 → 历史选中本次 → 导出 GPX；每条都写「做什么 + 看到什么算通过」的明确判据，无「大概 / 应该 / 视情况」等模糊措辞。
- ac-lock-section-numbered: 存在 `## N. 锁屏与解锁` 小节，N 紧接「核心闭环」小节；全篇 `##` 阿拉伯数字编号从 1 起连续，无跳号与重号。
- ac-lock-steps-complete: 该节写明执行序列：开跑 → 按电源键锁屏 → 记下锁屏前的距离与用时 → 锁屏 ≥60 秒 → 解锁回前台 → 记下解锁后的距离与用时。
- ac-lock-pass-criteria: 解锁后的通过判据只包括：仍处记录态（计时界面/记录态未退出）、计时继续走、App 未崩溃；距离增长仅作观察项，并以 GPS 漂移为上限。
- ac-no-static-distance-requirement: 文档含「静止段不要求距离增长」等价表述，明确不得把静止段距离增长当作通过条件。
- ac-prereq-clean-install: 开头「使用前提」含三条要素：干净安装（先删除 App 再安装候选包）、版本号（`VERSION` 0.1.0）、构建身份（候选 zip `sha256` + commit 全 sha）。
- ac-pending-semantics-kept: 保留「未做一律 `pending: 待人现场`」「禁写『真机已验证』」口径；全文不把未执行项写成通过/已验证，也不出现冒充真机结论的表述。
- ac-no-waveform-or-automation: 手测步骤不采集波形、不比对数表、不包含自动化驱动步骤（XCUITest / simctl / 脚本驱动）；如需提及只能作为「本手册不做」的说明，不得成为执行步骤。
- ac-operator-budget: 文档明确执行者按顺序 ≤5 分钟完成；失败时只记录现场现象与包/commit 身份，不改代码、不做现场调试。
- ac-doc-only-diff: 改动文件仅 `docs/device-manual-acceptance.md`（可含 `docs/release/stage4-prereqs.md` 至多一行链接）；`ios/`、`android/`、`shared/`、`scripts/`、`.github/` 零改动。
- ac-lint-green: 改动后本地 lint 门退出 0（至少 `bash -n scripts/version.sh`；若涉及既有门禁脚本则 `bash scripts/check-baseline.sh` 仍绿）。

## 非目标

- 不改任何代码、测试、CI，不出包，不做真机验收，不写「真机已验证」或任何真机结论。
- 不重写既有六节内容，不新增流程、脚本、证据目录或设备清单。
- 不引入主题系统/模板化改版，不扩写为多页文档。
- 不在本项解读 verification-matrix 或回填任何验证结论。

## 实现约束

- 纯文档改动，`docs/device-manual-acceptance.md` 为唯一必改文件；`docs/release/stage4-prereqs.md` 最多加一行指回手册的链接。
- 行文保持现有中文风格与 `## N.` 编号；新增「锁屏与解锁」排在「核心闭环」之后，原第 2~5 节顺延为 3~6，并保留「使用前提」在开头（可用不占序号的小节标题或首段）。
- 版本号以根 `VERSION`（当前 `0.1.0`）为单一真源，不在手册里写死其它版本；构建身份只记录、不做脚本校验或人工重算比对。
- 锁屏判据不得要求静止段距离增长：只判「计时继续 + 未崩溃 + 未退出记录态」，距离增长以 GPS 漂移为限。
- 口径对齐 `goal.md` 阶段 3 与 `AGENTS.md`：agent 不做真机验收，真机项一律 `pending: 待人现场`。
- 与 `README.md` / `AGENTS.md` 既有「交付后由人按 `docs/device-manual-acceptance.md` 手测」表述一致，不回改这些文件。
