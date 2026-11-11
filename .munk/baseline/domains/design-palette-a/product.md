# Domain: design-palette-a

方向 A「赛道石墨 / 竞速橙」色板子域：管 18 个语义色键 × 浅/深共 36 个 hex 的取值与用途语义、对比度矩阵（37 对 × 2 侧）、以及把这两者落成可复算证据的文档。只碰 `ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette` / `Colors.purposes`、`ios/PurePace/Design/ContrastPolicy.swift` 的 `pairMatrix`、对应单测、`docs/**` 证据与 `scripts/check-ios-shell.sh` 内嵌的方向 A 期望表；字号/字重/圆角档位数值归 `design-token-gates`，视图与信息层级归 `ios-ui-design`，轨迹渲染归 `ios-track-render`。

## 范围

- `Colors.palette`：18 键 × 浅/深 = 36 hex 整体替换为方向 A（石墨中性骨架 + 烤橙单点强调）；键集、键名、`static let` 数量不增不减。
- `Colors.purposes`：键集不变，用途文本按新色板重映射——accent = 唯一主操作色（开始/暂停/继续/结束/保存）、warning = 非阻断内联提示（不作填充主按钮）、danger = 破坏性操作（只出现在确认层文本或描边按钮）。
- `ContrastPolicy.pairMatrix`：既有 36 对不删不改，新增恰 1 对 `accentSoft/surface`（decorative 1.10，对应轨迹光晕叠在卡片面上的可辨识下限）→ 37 对。
- 文档两处：`docs/design/palette-a.md`（18×2 hex 表 + 来源 + 深色中性双度量 + 禁区对照）、`docs/evidence/palette-a-contrast.txt`（37 对 × 2 侧 = 74 条逐对实测）。
- 门：`scripts/check-ios-shell.sh` 的 `validate_design_tokens` 内嵌方向 A 36 hex 期望表（逐键比 light/dark），`run_self_test` 增「accent 回退青绿」反例。
- 单测落点：`ios/PurePaceTests/DesignTokensTests.swift`（表驱动 hex 锁值 / 中性双度量 / 禁区扫描 / accent 与 warning·danger 区分）、`ios/PurePaceTests/ContrastPolicyTests.swift`（37 对双侧阈值）。

## 验收

- ac-palette-hex-exact: `Colors.palette` 36 hex 与方向 A 表逐键逐侧完全相等；表驱动断言把期望值写成字面 `UInt32`，任一键改回旧值或改任一分量即红（accent light 改回 `#0B6F60` 必红）。
- ac-palette-keys-frozen: 调色板仍恰 18 键、键集与冻结清单相等、无重复、每键 light/dark 成对且两侧不等；`purposes` 键集等于 palette 键集，用途非空且不复读键名；`static let <key> = color("<key>")` 数量 = 18。
- ac-palette-neutral-purity: 深色中性三键 `#0B0C0D` / `#16181A` / `#1E2124` 判据为「HSL 色相 = 210°，落在 60–200° 之外」且「chroma/255 = 0.78% / 1.57% / 2.35% ≤ 3.0%」；回退旧值 `#0A1211`(H≈166°,3.14%) / `#141F1D`(≈168°,4.31%) / `#1A2724`(≈172°,5.10%) 必须判红。浅色三键 `#FAFAF9` / `#FFFFFF` / `#F2F2F1` 饱和度 ≤4%（实测 0.40% / 0.00% / 0.41%）一并断言。
- ac-palette-no-green: 36 hex 全部落在禁区外——不得命中 H 72–85°(S≥90%)、H 120–150°(S≥45%)、H 165–180°(S≥55%)、泛绿中性（中性三键色相 60–200° 或 chroma 超限）任一。
- ac-accent-separation: accent 与 warning、accent 与 danger 在 HSL 口径下至少满足 ΔH≥25° / ΔL≥15 / ΔS≥30 之一；深色 danger 必须是鲜红而非暖橙。warning/danger 系数值按公司裁决 `owe_40221a8e983c7516` 重取（不复用早期 `#7A5A00` / `#A5231C` 组合）。
- ac-palette-doc: `docs/design/palette-a.md` 存在且含 18×2 hex 表、来源（公司调研 digest 路径）、深色中性双度量（HSV 与 HSL/chroma 口径说明）、禁区对照；文件内 hex 与代码逐键一致。
- ac-contrast-matrix-pass: `pairMatrix` 恰 37 对（既有 36 对不删不改），`checks(for:)` 对 light 与 dark 各 37 对全部 PASS（body 4.5 / large 3.0 / decorative 1.10）；删任一对或改任一 hex 使任一对跌破阈值即红。
- ac-contrast-evidence: `docs/evidence/palette-a-contrast.txt` 逐行给出 `scheme pair 前景hex 背景hex 实测比值(4 位小数) 阈值`，覆盖 37 对 × 2 侧 = 74 行，且与 `ContrastPolicy.ratio` 现场重算值一致（1e-4 内）。
- ac-gate-direction-a-hex-lock: `scripts/check-ios-shell.sh` 内嵌方向 A 期望表（18 条 `key:light:dark`）并逐键比对源码；accent 回退青绿的反例必须判红且原因串含「方向 A 表不一致」；删键原因串含「方向 A 期望表缺键」。

## 非目标

- 不新增第 19 个色键、不改键集与 `purposes` 键数、不引入第二个 token 真源文件。
- 不靠截图取色、不自行微调 hex（warning/danger 系例外，按公司裁决重取并留痕）。
- 不改字号档、字重集合、间距、圆角、动效常量（归 `design-token-gates`）；不改视图结构、交互、文案与 identifier（归 `ios-ui-design` 等）。
- 不做主题切换器、用户自定义色板、双 SDK 地图配色、Android 侧色板同步。
- 不做真机取色与「真机已验证」表述；不以截图肉眼判定达标。

## 实现约束

- 唯一真源：`ios/PurePace/Design/DesignTokens.swift` 的 `palette` 是唯一合法字面色值位置；其余受管 UI 面只能引用 token（执行面见 `design-token-gates`）。
- 判据口径：深色中性不再用 HSV S —— 深色 V≈5% 时分母极小，实测 8.3–9.1% 会把正确实现判红；公司裁决 `owe_0b599686dc8f7475` 定的 HSL 口径（色相 + chroma/255）为准，口径理由写进代码注释与 `palette-a.md`，避免复评误判为「放宽门」。
- 对比度：WCAG 2.x 相对亮度；比值保留 4 位小数；`pairMatrix` 是单一真源，测试与证据文件都从它派生，不另立期望表。
- 反例纪律：新增断言必须同 commit 附反例，反例不得依赖改生产代码才红（改回旧值 / 改分量 / accent 回退都能独立判红）。
- 证据口径：只写命令、退出码、实测比值与断言数，不把「已按方向 A 对齐」当证据。

## 最近交付证明

- workItemId: wi_intake_1d3cee7d621efc36（2026-11-11，pass）
- 交付：36 hex 整体换为方向 A（中性骨架 `#FAFAF9/#FFFFFF/#F2F2F1` 与 `#0B0C0D/#16181A/#1E2124`、accent `#B4400B/#FF9A5C`、success/danger 系重取），`purposes` 语义按新色板重映射；`pairMatrix` 36 → 37（新增 `accentSoft/surface` decorative 1.10）；新增 `docs/design/palette-a.md` 与 `docs/evidence/palette-a-contrast.txt`；`check-ios-shell.sh` 增方向 A 36 hex 期望表与 accent 回退反例。
- 实测：`test-ios` 中 `DesignTokensTests` 24 例、`ContrastPolicyTests` 7 例全通过；`bash scripts/check-ios-shell.sh` 30 项断言 0 失败、`--self-test` 92 项断言 0 失败；`code_gates` 22 门全绿（attempt 001，`.munk/runs/run_intake_1d3cee7d621efc36/code-gates/attempts/001/`）。
- 边界：warning/danger 系数值与 brief 原始建议不同（按公司裁决重取，深色中性判据由 HSV S≤4% 改为 HSL 色相 + chroma）；地图壳、结束态总结、12 屏截图与可及树仍 `pending`（归后续子项），本域未产截图证据。
