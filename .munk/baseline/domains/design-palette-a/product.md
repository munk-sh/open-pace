# Domain: design-palette-a

方向 A「赛道石墨 / 竞速橙」色板子域：管 18 个语义色键 × 浅/深共 36 个 hex 槽位的取值与用途语义、对比度矩阵（37 对 × 2 侧）、品牌优先豁免登记表（恰 6 条），以及把这三者落成可复算证据的文档。只碰 `ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette` / `Colors.purposes`、`ios/PurePace/Design/ContrastPolicy.swift` 的 `pairMatrix` 与 `brandPriorityExemptions`、对应单测、`docs/**` 证据与 `scripts/check-ios-shell.sh` 内嵌的方向 A 期望表；字号/字重/圆角档位数值归 `design-token-gates`，视图与信息层级归 `ios-ui-design`，轨迹渲染归 `ios-track-render`。

## 范围

- `Colors.palette`：18 键 × 浅/深 = 36 hex 槽位（石墨中性骨架 + 唯一品牌橙单点强调）；键集、键名、`static let` 数量不增不减。V1.2 定稿后 `accent` 与 `onAccent` 浅深同值，其余 16 键仍须 light≠dark。
- `Colors.purposes`：键集不变，用途文本按新色板重映射——accent = 唯一主操作色（开始/暂停/继续/结束/保存）、warning = 非阻断内联提示（不作填充主按钮）、danger = 确认层实心破坏性主操作（丢弃）+ 无填充次操作（C2 图标式紧凑版）。
- `ContrastPolicy.pairMatrix`：37 对，按 body 4.5 / large 3.0 / decorative 1.10 三档求解；`onDanger/danger` 恰 1 条、body 档。
- `ContrastPolicy.brandPriorityExemptions`：唯一豁免登记表，恰 6 条，只登记 light 侧 `accent` 作前景的 3 个浅色中性底 × body/large 两档；dark 侧零豁免；豁免是登记而非改公式。
- 文档两处：`docs/design/palette-a.md`（18×2 hex 表 + 来源 + 深色中性双度量 + 禁区对照 + 豁免段）、`docs/evidence/palette-a-contrast.txt`（37 对 × 2 侧 = 74 条逐对实测 + 豁免段 + 口径段）与旁挂 `.sha256` manifest。
- 门：`scripts/check-ios-shell.sh` 的 `validate_design_tokens` 内嵌方向 A 36 hex 期望表（逐键比 light/dark）+ 同值白名单（仅放行 `accent`/`onAccent`），`run_self_test` 保 accent 回退红例并补同值绿/红例。
- 单测落点：`ios/PurePaceTests/DesignTokensTests.swift`（表驱动 hex 锁值 / 中性双度量 / 禁区扫描 / 单橙与 danger 分离 / 语义文本）、`ios/PurePaceTests/ContrastPolicyTests.swift`（37 对双侧阈值 / onDanger 档位 / 豁免表规模与 fail-closed 反例）。

## 验收

- ac-palette-hex-exact: 36 hex 槽位与方向 A 表逐键逐侧完全相等；表驱动断言把期望值写成字面 `UInt32`，任一键改回旧值或改任一分量即红（accent light 改回 `0xB4400B` 或设计稿候选 `0xE85D04` 必红）。
- ac-accent-single-orange: `palette["accent"]` light 与 dark 同为 `0xFF9A5C`（HSL 22.8/100/68.0），不等于旧 `0xB4400B`、不等于 `0xE85D04`；全色板橙区间扫描只命中 accent 两个槽位，不存在第二套橙或压暗 fallback 值。
- ac-onaccent-single-deep: `palette["onAccent"]` light 与 dark 同为 `0x2A1206`；`ratio(onAccent, accent)` 两侧均 8.44（±0.01）且 ≥4.5；旧白字 `0xFFFFFF` 作为反例必须判红。
- ac-palette-keys-frozen / shape-frozen: 调色板恰 18 键、18 条 `ColorPair`、36 个 hex 槽位；键集等于冻结清单、无重复、`purposes` 键集等于 palette 键集、`static let <key> = color("<key>")` 数量 = 18；**仅 `accent` 与 `onAccent` 允许 light==dark**，其余 16 键同值必红，`warning`/`danger`/`success` 系仍为双值。
- ac-accentsoft-light-recomputed: light `accentSoft` == `0xFFECE0`（HSL 23.2/100/93.9）且 ≠ 旧 `0xFCEFE7`；vs light `background` 1.0971（≥1.05）、vs `surface` 1.1459（≥1.10）；`primary`/`secondary` 在其上 15.50 / 5.60（≥4.5）；dark `accentSoft` 保持 `0x3A1F12`。
- ac-palette-neutral-purity: 深色三中性键 `#0B0C0D` / `#16181A` / `#1E2124` 判据为「HSL 色相 210°，落在 60–200° 之外」且「chroma/255 = 0.78% / 1.57% / 2.35% ≤ 3.0%」；旧值 `#0A1211`(166°) / `#141F1D`(168°) / `#1A2724`(172°) 必须判红。浅色三键 `#FAFAF9` / `#FFFFFF` / `#F2F2F1` 饱和度 ≤4% 一并断言。
- ac-palette-no-green: 36 hex 全部落在禁区外——不得命中 H 72–85°(S≥90%)、H 120–150°(S≥45%)、H 165–180°(S≥55%)、泛绿中性任一项。
- ac-accent-separation: accent 与 warning、accent 与 danger 在 HSL 口径下至少满足 ΔH≥25° / ΔL≥15pp / ΔS≥30pp 之一；warning/danger 系数值按公司裁决 `owe_40221a8e983c7516` 取。
- ac-danger-one-pass-separation: light `danger` 维持 `0x660D09`、dark 维持 `0xF53A48`；`accent↔danger` 两模式均满足 ΔH≥25° / ΔL≥15pp / ΔS≥30pp 之一（light 靠 ΔL 46.27pp，dark 靠 ΔH 27.31°）；明度分离最多一档且不新增方案。
- ac-danger-semantics: `purposes["danger"]` 与 `Colors.danger` 文档注释均为「确认层实心破坏性主操作（丢弃）+ 无填充次操作（C2 图标式紧凑版）」，不再出现「仅文本或描边」；旧文案作为反例判红；`warning`/`success` 语义与 hex 不变。
- ac-dark-danger-red: dark `danger` ∈ H≤8° 或 ≥352°（实测 355.5°）、S≥55%（90.3%）、L≤60%（59.4%）；暖橙近似值必红。
- ac-ondanger-matrix-pair: `pairMatrix` 中 `onDanger/danger` 恰 1 条、`.body` 档、minimum == `bodyThreshold`；light 12.91、dark 4.95（均 ≥4.5）；注释写明「实心按钮文字按正文/小字 4.5」的推导，并说明 dark 保留深字 `onDanger`（白字 vs dark danger 仅 3.76，不达标）；`pairMatrix` 总数仍 37。
- ac-brand-exemption-scoped: 豁免以显式登记表存在，恰 6 条且只命中 light 侧 `accent` 作前景：`accent/background` 2.0049、`accent/surface` 2.0940、`accent/accentSoft` 1.8274（body 4.5），`accent/background@large` 2.0049、`accent/surface@large` 2.0940、`accent/surfaceMuted@large` 1.8693（large 3.0）；每条带实测比值与拍板来源；dark 侧零豁免。
- ac-exemption-not-formula: 清空登记表后上述 6 条必须全部判红；删 1 条只红 1 条；未登记的低对比 synthetic pair 必须判红；`bodyThreshold`/`largeThreshold`/`decorativeThreshold` 与 37 对数量零改动（禁止改小阈值或删对补绿）。
- ac-no-other-hex-drift: 相对 V1.2 起始提交，palette 仅 3 个 light 槽位变化（`accent.light`、`onAccent.light`、`accentSoft.light`），其余 33 个 hex 逐字节不变。
- ac-contrast-matrix-pass: `checks(for:)` 对 light 与 dark 各 37 对全部 PASS；删任一对或改任一 hex 使任一对跌破阈值（且未登记豁免）即红。
- ac-contrast-evidence / evidence-bound: `docs/evidence/palette-a-contrast.txt` 逐行 `scheme pair fg bg ratio(4 位) threshold`，覆盖 74 行且与 `ContrastPolicy.ratio` 现场重算误差 ≤1e-4；含「品牌优先豁免」（6 条 + 拍板来源 + 补偿仅限描边/字重/尺寸）与「矩阵来源/公式/阈值来源」段；旁挂 `.sha256` 记录证据 sha256 与 commit sha，`shasum -a 256 -c` 通过且该 commit 能读到同批新值。
- ac-gate-direction-a-hex-lock / gate-execution-sync: `scripts/check-ios-shell.sh` 期望表同步为新值；同值白名单仅放行 `accent`/`onAccent`（`surface` 等非白名单同值仍判「色对 light/dark 相同」）；`--self-test` 含 accent 同值绿例 + 非白名单同值红例 + accent 回退红例（原因串含「方向 A 表不一致」），退出 0；删键原因串含「方向 A 期望表缺键」；对比度阈值与公式不在这条门里、不得借机改动。
- ac-doc-palette-sync: `docs/design/palette-a.md` 18×2 表与代码一致（accent 两侧 `#FF9A5C`、onAccent 两侧 `#2A1206`、accentSoft light `#FFECE0`），并注明 V1.2 单一橙定稿与豁免来源，文件内 hex 与代码逐键一致。
- ac-token-tests-red-both-ways: 上述单橙 / onAccent / accentSoft / danger 语义与分离 / onDanger 对比度 / 6 条豁免均有同 commit 反例：旧 `0xB4400B`·`0xFFFFFF`·`0xFCEFE7`、白字 vs dark danger、未登记低对比对、删登记项，均在不改生产代码的前提下判红；把新值改错也必须红。
- ac-no-fallback-enabled: 代码注释明确「同色相更深一档（H 22–26）仅作 fallback，必须人看过拍板后才可启用，本轮未启用」；palette 中不存在压暗候选/第二套橙。

## 非目标

- 不新增第 19 个色键、不改键集与 `purposes` 键数、不引入第二个 token 真源文件。
- 不靠截图取色、不自行微调 hex（warning/danger 系例外，按公司裁决重取并留痕）。
- 不改 Layout、结束态总结、丢弃确认弹窗等视图结构与交互（归 `ios-ui-design` 等后续子项）；本域不获得视图改动授权。
- 不改字号档、字重集合、间距、圆角、动效常量（归 `design-token-gates`）；不改 `ios/PurePaceUITests/**`、identifier 冻结集、`VERSION`、Info.plist、签名与 CI workflow。
- 不做主题切换器、用户自定义色板、双 SDK 地图配色、Android 侧色板同步。
- 不启用「更深一档橙」fallback；不做真机取色与「真机已验证」表述，不以截图肉眼判定达标。

## 实现约束

- 唯一真源：`ios/PurePace/Design/DesignTokens.swift` 的 `palette` 是唯一合法字面色值位置；其余受管 UI 面只能引用 token（执行面见 `design-token-gates`）。
- 判据口径：深色中性不用 HSV S（深色 V≈5% 时分母极小，实测 8.3–9.1% 会把正确实现判红）；公司裁决 `owe_0b599686dc8f7475` 定的 HSL 口径（色相 + chroma/255）为准，口径理由写进代码注释与 `palette-a.md`，避免复评误判为「放宽门」。
- 对比度：WCAG 2.x 相对亮度；比值保留 4 位小数；`pairMatrix` 是单一真源，测试与证据都从它派生，不另立期望表。
- 豁免纪律：只登记不改公式——`problems` 对每条真算比值，仅对登记名放行；禁止改小 `bodyThreshold`/`largeThreshold`/`decorativeThreshold`、禁止删 pair 或放宽 dark 侧；补偿手段只允许描边/字重/尺寸，绝不改色相或压暗。
- 同值白名单边界：`check-ios-shell.sh` 只允许 `accent`/`onAccent` light==dark，其余键同值仍判红；期望表值同步与自检夹具更新属执行面同步，不是放宽门。
- 反例纪律：新增断言必须同 commit 附反例，反例不得依赖改生产代码才红（改回旧值 / 改分量 / 清空豁免都能独立判红）。
- 证据口径：只写命令、退出码、实测比值与断言数，不把「已按 V1.2 对齐」当证据。
- 已知遗留风险：`RunView` 仍有 `Colors.accent` 作正文/链接前景（约 L345/L409/L419），浅色下约 2.00:1；本域只登记豁免与补偿约束，视图修正归下一子项。

## 最近交付证明

- workItemId: wi_intake_029a7f0234099ff4（2026-11-12，pass）
- 交付（V1.2 定稿）：`accent` 浅深同值 `0xFF9A5C`、`onAccent` 浅深同值 `0x2A1206`（8.44）、`accentSoft` light 重算为 `0xFFECE0`，其余 33 个 hex 零漂移；`purposes`/`Colors.danger` 语义改为「实心破坏性主操作 + 无填充次操作」；新增 `ContrastPolicy.brandPriorityExemptions` 恰 6 条 light accent 豁免（2.0049 / 2.0940 / 1.8274 / 2.0049 / 2.0940 / 1.8693），阈值与 37 对零改动；证据文件 74 行同名覆盖 + `.sha256` 旁挂；`check-ios-shell.sh` 期望表同步并加同值白名单与三类自检夹具。
- 实测：`test-ios --unit-only` 262 例 0 失败（含 `DesignTokensTests` 新增单橙/onAccent/单遍分离/语义/同值反例、`ContrastPolicyTests` 新增 onDanger 档位与豁免 fail-closed 反例）；`check-ios-shell.sh` 33 项断言 0 失败、`--self-test` 95 项 0 失败；`code_gates` 22 门全绿（attempt 001，`.munk/runs/run_redispatch_bb33c32e51919014/code-gates/attempts/001/`）。
- 边界：本轮只落 token + 策略 + 单测 + 证据，未动任何视图/版式/布局；`RunView` 的 accent 前景低对比与更深一档橙 fallback 均为有意未启用项。
