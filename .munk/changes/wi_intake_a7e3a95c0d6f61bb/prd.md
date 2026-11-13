# 落地 V1.2 配色终版（2026-11-13 人拍板）：accent #FF6B00 / danger #F53A48 双模式同色

## Scope

把 2026-11-13 人拍板的 V1.2 配色终版一次性落进 `DesignTokens` 单一真源，并把它必然连带的
对比度重判、分离度断言口径、证据重出、文档同步、截图重出全部做完。**只动色 token 及其派生证据/期望值**，
不动布局、不加功能、不动其它语义色、不派生第二套橙。

### 定值（Key → light / dark，浅深同值，禁派生第二套）

| 键 | light | dark | 相对现状 |
|---|---|---|---|
| accent | `#FF6B00` | `#FF6B00` | 两侧由 `#FF9A5C` 改 |
| onAccent | `#2A1206` | `#2A1206` | 不变（实测 ≈6.19:1） |
| accentSoft | 由 `#FF6B00` 按既有派生口径重算 | `#3A1F12` | light 必须重算；dark 不动 |
| danger | `#F53A48` | `#F53A48` | light 由 `#660D09` 改（两模式同色） |
| onDanger | `#2A0608` | `#2A0608` | light 由 `#FFFFFF` 改（实测 ≈4.95:1） |
| dangerSoft | `#FBEAE8` | `#2C0A10` | 不变，**仅作背景**，不得再当 danger 文字底 |

其余 12 键（background / surface / surfaceMuted / primary / secondary / separator / warning /
onWarning / warningSoft / success / onSuccess / successSoft）共 24 hex 零改动。

`accentSoft` light 的派生口径锚点：旧 `#FFECE0` 即 `#FF9A5C` 约 19% 混白（`#FFECE0` 相对 `#FF9A5C`
的分通道向白插值恰 ≈19%）。新值必须用**同一口径**从 `#FF6B00` 重算并把公式写进文档，不得直接留旧橙派生值。

### 必须处理的连带后果（不得用改色/改阈值糊过去）

1. **light danger 作正文对白物理上到不了 4.50**：现状 `light danger/background ≈3.60`、
   `danger/surface ≈3.76`、`danger/dangerSoft ≈3.23`（本次以重跑实测为准）。三条必须改判为非文本档
   （图标/填充，≥3.0）或从 `pairMatrix` 移除，并写明「light danger 仅作确认层填充主操作与 C2 图标着色，
   不作正文文字」。`onDanger/danger` 按实测 ≈4.95 入表。
2. **6 条 light accent-as-text 豁免**（`accent/background`、`accent/surface`、`accent/accentSoft`、
   `accent/background@large`、`accent/surface@large`、`accent/surfaceMuted@large`）的 `measured`
   必须重测重记，预期量级：background ≈2.73 / surface ≈2.86 / surfaceMuted ≈2.55 / accentSoft ≈2.49；
   旧值 `2.0049 / 2.0940 / 1.8274 / 1.8693` 零残留。豁免仍恰 6 条、仍只命中 light 侧 accent 作前景。
3. **分离度改 ΔH 口径**：accent `#FF6B00`(H≈25.2) vs danger `#F53A48`(H≈355.5) 靠 ΔH≈29–30° 达标
   （ΔL 仅 ≈9pp、ΔS ≈10pp，不再构成通过理由）；vs warning `#6E5C00` ΔH 实测需记录。
   既有 `testDangerKeepsValuesAfterSinglePassSeparation` 现在断言 `0x660D09` 与 ΔL 46.27 / ΔH 27.31，
   必须按新值重写成 ΔH 口径，**判据阈值不放宽**（沿用既有 ΔH ≥ 25°）。
4. **语义单点同步**：`DesignTokens.swift` 注释、`docs/design/palette-a.md`、`docs/verification-matrix.md`、
   `docs/evidence/palette-a-contrast.txt` 与 `.sha256`（重跑重出）、`.munk/baseline/design/foundations.md`；
   `docs/design-draft-v12/token-diff.md` 若保留须标注「已被 V1.2 终版取代」。

### 交付面

代码/测试 + `docs/**`（证据、色板、矩阵、截图与 SHA256SUMS）。截图重出 14 张屏（7 屏 × 浅/深）+ 7 张并排，
绑本项 commit。

## Acceptance Criteria

- ac-accent-value: `Colors.palette["accent"]` 的 light 与 dark 均为 `#FF6B00`（0xFF6B00），两侧同值。
- ac-danger-value: `danger` light 与 dark 均为 `#F53A48`；`onDanger` light 与 dark 均为 `#2A0608`；浅色侧不再是 `#660D09`/`#FFFFFF`。
- ac-onaccent-value: `onAccent` 两模式仍为 `#2A1206`，且 `onAccent/accent` 实测 ≥4.50 并落在 6.19±0.05。
- ac-accentsoft-derived: `accentSoft` light 值由 `#FF6B00` 按文档化派生口径计算得出（非 `#FFECE0` 原值、非旧橙派生），dark 仍为 `#3A1F12`；派生公式出现在 `docs/design/palette-a.md`。
- ac-hex36-identity: `palette` 键集合恰 18 个且与 `purposes` 键集合完全相等，36 个 hex 与上表逐项相符；键名集合与本项改动前 `git show` 的集合逐名相等（identifier 零增删改）。
- ac-untouched-24: 其余 12 键的 24 个 hex 与改动前基线逐值相等（warning / success / 中性 / separator 零漂移）。
- ac-danger-nontext: `light danger/background`、`light danger/surface`、`light danger/dangerSoft` 三条不再以 4.50 断言——或被改判为非文本档（阈值 3.0，实测 ≥3.0），或从 `pairMatrix` 移除；矩阵总数相应等于 `37 − 移除条数`；证据与色板文档写明「light danger 仅作确认层填充主操作与 C2 图标着色，不作正文文字」。
- ac-ondanger-pair: `onDanger/danger` 在两侧矩阵中存在，实测 ≥4.50，light 实测落在 4.95±0.05；证据文件含该行。
- ac-exemptions-remeasured: 6 条 light accent-as-text 豁免的 `Exemption.measured` 与证据行同步为实测新值（量级 ≈2.73/≈2.86/≈2.49/≈2.55/≈2.73/≈2.55），且全仓 `grep` 旧值 `2.0049`、`2.0940`、`1.8274`、`1.8693` 零命中；豁免仍恰 6 条且仅命中 light 侧 accent 作前景。
- ac-separation-dh: `testDangerKeepsValuesAfterSinglePassSeparation` 改为 ΔH 口径（accent vs danger 实测 ΔH ≥ 25°，实测值记录在断言消息/证据），断言中不再出现 `0x660D09`、`46.27`、`27.31` 作为通过依据；阈值常量不变。
- ac-red-proof: 每条新增/改判断言附「构造错误输入→必须红」的反例（例如把 accent 置为 `#FF4000` 使 ΔH<25 必须失败；把某 hex 改回旧值必须失败；矩阵键集合缺失必须失败），反例自检可执行且实测红；禁止同源别名自证（比对照抄常量）与「因缺席而绿」。
- ac-no-threshold-relax: `bodyThreshold`=4.5、`largeThreshold`=3.0、`decorativeThreshold`=1.10 与 `code-gates.json` 门列表零改动；无 `continue-on-error`、无删腿、无新增门。
- ac-evidence-regen: `docs/evidence/palette-a-contrast.txt` 重跑重出，行结构仍为 `scheme pair fg bg ratio(4 位) threshold`，覆盖当前矩阵对数 ×2 侧，逐行与 `ContrastPolicy.ratio` 现场重算误差 ≤1e-4；保留「品牌优先豁免」段（6 条，新值）与「矩阵来源/公式/阈值来源」口径段。
- ac-evidence-bound: `docs/evidence/palette-a-contrast.sha256` 记录新证据文件 sha256 与本项 commit sha，`cd docs/evidence && shasum -a 256 -c palette-a-contrast.sha256` exit 0，且该 commit 上的 `DesignTokens.swift` 能读到同批新值。
- ac-docs-synced: `DesignTokens.swift` 注释、`docs/design/palette-a.md`（18×2 hex 表 + 对比度表 + 豁免段）、`docs/verification-matrix.md`、`.munk/baseline/design/foundations.md` 与新值一致；旧表述（`#FF9A5C` 作主色、`#660D09` 作 light danger、`8.44:1`、旧豁免实测值、旧最低值描述）零残留；`docs/design-draft-v12/token-diff.md` 顶部含「已被 V1.2 终版取代」标注。
- ac-screenshots: 14 张屏（7 屏 × light/dark）+ 7 张并排重出并绑本项 commit；`docs/screenshots/SHA256SUMS` 与 `docs/screenshots/side-by-side/SHA256SUMS` 用实取 sha256 更新（不猜、不复制），`shasum -a 256 -c` 两条均 exit 0；两份头部均写 build head sha、tree sha、采集时 HEAD、归属 workItem、以及「除色 token 外零布局 diff」声明。
- ac-scope-frozen: 改动路径集 ⊆ {`ios/PurePace/Design/DesignTokens.swift`, `ios/PurePace/Design/ContrastPolicy.swift`, `ios/PurePaceTests/DesignTokensTests.swift`, `ios/PurePaceTests/ContrastPolicyTests.swift`, `docs/**`, `.munk/changes/{workItemId}/**`}；`ios/PurePace/` 下视图/Draft 代码（`DesignDraft/**`、`Views/**` 等）`git diff` 为空；不新建 app 内/workbench 色块或选色器。
- ac-gates-green: 全量 `code_gates` + `.github/workflows/ios.yml` + `.github/workflows/android.yml` 在**同一 commit** 上绿（结论以 Owner 取到的权威运行结果为准；未取到即写「未闭合」，不得声称已绿）。
- ac-receipt-wording: 交付回执不出现「已发布 / 已分发 / 可分发 / UI 达标」字样。

## Non-Goals

- 不改布局、间距、字号、圆角、描边，不改任何视图/Draft 代码（`DesignDraftDiscard.swift` 等只读不改）。
- 不加功能、不加页面、不加 token 键、不删 token 键、不改 identifier。
- 不动 warning / onWarning / warningSoft / success / onSuccess / successSoft / 中性 / separator 任何 hex。
- 不派生第二套橙（含「同色相更深一档 fallback」本轮仍不启用）；不压暗主色换对比度。
- 不把色块/选色器做进 app 或 workbench，色板只作外部参考图。
- 不放宽阈值、不删测试腿、不 `continue-on-error`、不新增 gate、不改 `code-gates.json`。
- 真机项（锁屏定位、音频实听等）不在本轮；不声明发布/分发状态。

## Implementation Constraints

- 优先级：token + 测试期望 + 对比度证据 + 文档 → 门禁 → 截图重出。预算 ≤8M token / ≤90 分钟；到点未闭合按「已做 / 未做 / 已过门 / 未闭合点」交回执，不续命、不放宽断言、不重跑已绿门。
- 单一真源：所有色值只改 `ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette`；`ContrastPolicy` 只改矩阵档位/豁免 `measured` 与分离度口径，不改公式与阈值常量。
- 证据必须**先跑后写**：用单元测试现场打印逐对实测值，再落 `docs/evidence/palette-a-contrast.txt`；文件里禁出现与 `ContrastPolicy.ratio` 不一致的手写比值。
- 已知锚点：`ios/PurePace/Design/DesignTokens.swift` L54-L73（palette）、L75-L85（注释）、L88-L107（purposes）、L104（danger 用途文案）；`ios/PurePace/Design/ContrastPolicy.swift` L30-L70（pairMatrix，37 对 = body 30 + large 3 + decorative 4）、L63（live 注释含 `#660D09`）、L93-L99（豁免 6 条）；`ios/PurePaceTests/DesignTokensTests.swift` L297-L305、L378、分离度测试；`ios/PurePaceTests/ContrastPolicyTests.swift` L88、L174-L177。
- 数值口径：WCAG 2.x sRGB 线性化后 `(L1+0.05)/(L2+0.05)`，比值 4 位小数。预期量级（以重跑为准）：accent/background ≈2.73、accent/surface ≈2.86、accent/surfaceMuted ≈2.55、onAccent/accent ≈6.19、onDanger/danger ≈4.95、light danger/surface ≈3.76、light danger/background ≈3.60、light danger/dangerSoft ≈3.23。
- HSL 分离度以仓内既有 HSL 实现为准，原地记录实测 ΔH（accent vs danger 预期 ≈29–30°，vs warning 需实测记录）；ΔH 判据阈值 ≥25° 不变，不得改判据为 ΔL/ΔS 兜底。
- 截图：沿用既有 `scripts/capture-ios-screenshots.sh` 与 `scripts/compose-ios-screenshots-side-by-side.sh`；采集时 HEAD 必须是本项 commit（或声明工作树零 diff），否则 SHA256SUMS 头部记录不一致即判红。
- 反例自检落点：与既有 `scripts/check-ios-shell.sh` / `check-ios-core.sh` 等脚本内既有 `--self-test` 反例风格一致，新增反例必须可执行且实测红。
