# V1.2 定稿：唯一品牌橙 token 与对比度豁免策略落地

## Scope

人已对 V1.2 返工稿做最终判定（公司书面确认，逐像素取样核对）。本项只落 token 值、对比度策略、单测与证据，**不动任何视图/版式/布局**。

1. **唯一品牌橙**：`DesignTokens.Colors.palette` 的 `accent` 浅/深同为 `#FF9A5C`（H 22.8 / S 100 / L 68.0）；`onAccent` 浅/深同为 `#2A1206`（vs accent 8.44:1）；`accentSoft` 浅色按新主色重算为 `#FFECE0`（HSL 23.2 / 100 / 93.9），dark `accentSoft` 保持 `#3A1F12`。旧砖红 `#B4400B`、设计稿候选 `#E85D04` 及一切压暗候选作废。
2. **非品牌色保留双值**：`warning` / `danger` / `success` 系维持浅/深双值；`danger` 浅色做一次明度分离校验（最多一档、不新增方案），本项实测维持 `#660D09`；dark `danger` 仍须 H≤8 或 ≥352、S≥55、L≤60。
3. **语义与策略**：`danger` 语义注释改为「确认层实心破坏性主操作 + 无填充次操作（C2 图标式紧凑版）」；`ContrastPolicy.pairMatrix` 的 `onDanger/danger` 保留为 body 4.5 对并补阈值推导注释；把「品牌橙作为前景 vs 浅色中性底」的低于阈值组合登记为**唯一**品牌优先豁免族（恰 6 条，见下），其他阈值零放宽、零删对、37 对数量不变。
4. **单测与反例**：改/加断言同 commit 附「构造错误输入必须红」反例，且不靠改生产代码才红。
5. **证据**：同名覆盖 `docs/evidence/palette-a-contrast.txt`（37×2=74 行 + 豁免段 + 口径段），附 sha256、绑 commit；同步 `docs/design/palette-a.md` 的 18×2 表。
6. **门禁执行面同步**：`scripts/check-ios-shell.sh` 仅做期望表值同步、`accent/onAccent` 同值白名单、自检正/负例三类改动（见实现约束），不改任何对比度阈值或公式。

## Acceptance Criteria

- ac-accent-single-orange: `palette["accent"]` 的 light 与 dark 同为 `0xFF9A5C`，HSL 实测 H 22.8°/S 100%/L 68.0%，且不等于旧 `0xB4400B`、不等于设计稿候选 `0xE85D04`；不存在第二个橙键或压暗 fallback 值。
- ac-onaccent-single-deep: `palette["onAccent"]` 的 light 与 dark 同为 `0x2A1206`；`ratio(onAccent, accent)` 在 light 与 dark 均实测 8.44（容差 ±0.01）且 ≥4.5。
- ac-palette-shape-frozen: `palette` 仍恰 18 键、18 条 `ColorPair`、light/dark 共 36 个 hex 槽位；仅 `accent` 与 `onAccent` 允许 light==dark，其余 16 键 light≠dark，`warning`/`danger`/`success` 系仍为双值。
- ac-accentsoft-light-recomputed: light `accentSoft` == `0xFFECE0`（HSL 23.2/100/93.9）且 ≠ 旧 `0xFCEFE7`；`accentSoft` vs light `background` = 1.0971（≥1.05）、vs `surface` = 1.1459（≥1.10）；`primary` 与 `secondary` 在其上分别为 15.50 / 5.60（≥4.5）；dark `accentSoft` 保持 `0x3A1F12`。
- ac-danger-one-pass-separation: light `danger` 维持 `0x660D09`（本次校验 0 档调整）、dark 维持 `0xF53A48`；`accent↔danger` 两模式均满足 ΔH≥25° 或 ΔL≥15pp 或 ΔS≥30pp（light 靠 ΔL 46.27pp，dark 靠 ΔH 27.31°）。
- ac-danger-semantics: `purposes["danger"]` 与 `Colors.danger` 的文档注释均改为「确认层实心破坏性主操作（丢弃）+ 无填充次操作（C2 图标式紧凑版）」，不再出现「仅文本或描边」；`warning`/`success` 的语义与 hex 不变。
- ac-dark-danger-red: dark `danger` ∈ H≤8° 或 ≥352°（实测 355.5°）、S≥55%（90.3%）、L≤60%（59.4%）。
- ac-ondanger-matrix-pair: `pairMatrix` 中 `onDanger/danger` 恰 1 条、body 4.5 档；light 白字实测 12.91、dark 实测 4.95（均 ≥4.5）；注释写明「实心按钮文字按正文/小字 4.5」的推导依据，并说明 dark 侧保留深字 `onDanger`（白字 vs dark danger 仅 3.76，不达标）；`pairMatrix` 总数仍 37。
- ac-brand-exemption-scoped: 品牌优先豁免以显式登记表存在，且**只**命中 light 侧 `accent` 作前景的 6 条：`accent/background` 2.0049、`accent/surface` 2.0940、`accent/accentSoft` 1.8274（body 4.5），`accent/background@large` 2.0049、`accent/surface@large` 2.0940、`accent/surfaceMuted@large` 1.8693（large 3.0）；每条带实测比值与拍板来源；dark 侧零豁免。
- ac-exemption-not-formula: 豁免是登记表而非改公式：清空登记表后上述 6 条必须全部判红；未登记的低对比 synthetic pair 必须判红；`bodyThreshold`/`largeThreshold`/`decorativeThreshold` 与 37 对数量零改动。
- ac-no-other-hex-drift: 相对本项起始提交，`DesignTokens.swift` 的 palette 仅 3 个 hex 槽位变化（`accent.light`、`onAccent.light`、`accentSoft.light`），其余 33 个 hex 逐字节不变。
- ac-token-tests-red-both-ways: accent/onAccent 同值、accentSoft 新值、danger 语义与分离、onDanger 对比度、6 条豁免均有同 commit 反例：旧 `0xB4400B`/`0xFFFFFF`/`0xFCEFE7`、白字 vs dark danger、未登记低对比对、删登记项，均在不改生产代码的前提下判红；把新值改错也必须红。
- ac-contrast-tests-single-orange: 原钉住 light `onAccent/accent=5.71`、light `accent/background=5.47`、`accent` 浅深不同的断言同步改为同值口径（8.44 / 2.0049 且入豁免），正负两向仍可判红。
- ac-gate-execution-sync: `scripts/check-ios-shell.sh` 期望表同步为新值；同值白名单仅放行 `accent`/`onAccent`（`surface` 等非白名单同值仍判「色对 light/dark 相同」）；`--self-test` 必有 accent 同值绿例 + 非白名单同值红例 + accent 回退红例，退出 0 且断言数 ≥94、0 失败。
- ac-evidence-overwritten: `docs/evidence/palette-a-contrast.txt` 同名覆盖为 37 对×2 侧 = 74 行，逐行 `scheme pair fg bg ratio(4 位) threshold`，与 `ContrastPolicy.ratio` 现场重算误差 ≤1e-4；附「品牌优先豁免」段（6 条 + 拍板来源 + 「补偿仅限描边/字重/尺寸，禁改色相或压暗」）与「矩阵来源/公式/阈值来源」口径段。
- ac-evidence-bound: 证据旁挂 manifest（`.sha256` 或 digest）记录 `palette-a-contrast.txt` 的 sha256 与 commit sha，`shasum -a 256 -c` 通过，且 `git show <sha>:ios/PurePace/Design/DesignTokens.swift` 能读到同批新值。
- ac-doc-palette-sync: `docs/design/palette-a.md` 的 18×2 表与代码一致（accent 两侧 `#FF9A5C`、onAccent 两侧 `#2A1206`、accentSoft light `#FFECE0`），并注明 V1.2 单一橙定稿与豁免来源。
- ac-gates-green: `code_gates` 全绿（含 `lint`、`lint-ios-shell`、`lint-ios-scripts`、`test-ios`（`--unit-only`）、`build-ios`、`test`、`check-shared`）；不靠放宽断言、删对或加宽实现补绿。
- ac-scope-frozen: 变更文件仅限 `ios/PurePace/Design/DesignTokens.swift`、`ios/PurePace/Design/ContrastPolicy.swift`、`ios/PurePaceTests/DesignTokensTests.swift`、`ios/PurePaceTests/ContrastPolicyTests.swift`、`scripts/check-ios-shell.sh`、`docs/evidence/palette-a-contrast.txt`（+旁挂 sha/manifest）、`docs/design/palette-a.md`、`.munk/changes/{workItemId}/digest.md`；其余路径零改动。
- ac-no-fallback-enabled: 代码注释明确「同色相更深一档（H 22–26）仅作 fallback，必须人看过拍板后才可启用，本轮未启用」；palette 中不存在压暗候选/第二套橙。

## Non-Goals

- 不改 Layout、`RunFinishedSummaryLayoutPolicy`、结束态视图、丢弃确认弹窗视图（下一项做）；本项不获得任何视图改动的授权。
- 不改 `ios/PurePaceUITests/**`、`scripts/test-ios.sh` 的 UI 套件枚举、`docs/screenshots/**`、`docs/design-draft-v12/**`、`ios/PurePace/DesignDraft/**`（其中 `DesignDraftTheme.swift` 的 `#E85D04` 仅是静态稿候选，不是生产 token）、identifier 冻结集、`VERSION`、Info.plist、签名与 CI workflow。
- 不改 `.munk/code-gates.json` 的 gate 列表/命令，不新增 gate id，不加 `continue-on-error`、不删测试腿、不提高超时。
- 不重算 `warning`/`success` 或新增第 19 个色键；不改 dark `accentSoft`；不改字号/间距/圆角/动效/图标档位。
- 不启用「更深一档橙」fallback，不做截图/真机肉眼验收，不做分发与合并（由 Host Delivery 处理）。

## Implementation Constraints

### 精确取值（先定后测，已按 WCAG 2.x 复算）

| 键/对 | light | dark | 实测 |
|---|---|---|---|
| `accent` | `#FF9A5C` | `#FF9A5C` | HSL 22.8 / 100 / 68.0 |
| `onAccent` | `#2A1206` | `#2A1206` | `onAccent/accent` 8.4446（记 8.44） |
| `accentSoft` | `#FFECE0` | `#3A1F12`（不变） | vs `background` 1.0971；vs `surface` 1.1459；primary 15.5047；secondary 5.6008 |
| `danger` | `#660D09`（不变） | `#F53A48`（不变） | 白字 12.9114；dark onDanger 4.9479；accent↔danger light ΔL 46.27pp / dark ΔH 27.31° |

豁免族实测：light `accent/background` 2.0049、`accent/surface` 2.0940、`accent/accentSoft` 1.8274、`accent/background@large` 2.0049、`accent/surface@large` 2.0940、`accent/surfaceMuted@large` 1.8693。

### 口径解释（必须显式写进代码注释与证据，不许偷偷放宽）

- 人拍板的取舍是「唯一品牌橙作为前景压不住浅色中性底，品牌优先」；当前 37 对矩阵把同一关系展开为 light 侧 6 条（3 个浅色中性底 × body/large 两档）。因此豁免登记表**只**含这 6 条，不多不少；dark 侧与其余任何 pair/scheme 组合一律按原阈值 fail-closed。
- 豁免只登记、不改公式：`problems` 仍对每条真算；登记项单独可列出（证据里逐条给实测值 + 拍板来源），未登记的低对比仍判红。禁止把 `bodyThreshold`/`largeThreshold`/`decorativeThreshold` 改小，禁止删 pair。
- 补偿手段只允许描边 / 字重 / 尺寸，绝不改色相或压暗；更深一档橙（H 22–26 不变）仅作人拍板后才可用的 fallback，本轮不得启用。

### 代码锚点

- `ios/PurePace/Design/DesignTokens.swift`：`Colors.palette` L54-L73（`accent` L60、`onAccent` L61、`accentSoft` L62、`danger` 系 L70-L72）；`purposes` L89-L101（`danger` L99）；`Colors.danger` 文档注释 L160。
- `ios/PurePace/Design/ContrastPolicy.swift`：`pairMatrix` L30-L72（`onAccent/accent` L58、`onDanger/danger` L61、装饰对 L70-L71）；豁免登记与 `problems` 的消费点在 L128-L149 附近。
- `ios/PurePaceTests/DesignTokensTests.swift`：全键 light≠dark 断言 L87-L105、方向 A hex 表 L284-L316、accent↔warning/danger 分离 L377-L407。
- `ios/PurePaceTests/ContrastPolicyTests.swift`：矩阵全过 L44-L57、钉住比值 L61-L108、fail-closed 反例 L110-L178。
- `scripts/check-ios-shell.sh`：方向 A 期望表 L668、同值判红分支 L710-L712、自检夹具 L1614-L1640。
- 证据/文档：`docs/evidence/palette-a-contrast.txt`、`docs/design/palette-a.md` L23-L32。

### 门禁执行面同步边界

`scripts/check-ios-shell.sh` 的改动只允许三类：(a) 期望表 3 个新值同步；(b) 同值白名单仅放行 `accent`/`onAccent`，其余键同值仍判红；(c) `--self-test` 夹具随之更新并补「accent 同值绿例 / 非白名单同值红例 / accent 回退红例」。这是执行面同步，不是放宽：对比度阈值与 pair 数不在这条门里，也不得借机改动。

### 证据与提交

- 先用单元测试打印 74 条 `ac-contrast` 实测值，再写 `docs/evidence/palette-a-contrast.txt`；文件内避免出现与矩阵不一致的手写比值。
- commit 后再生成旁挂 manifest（sha256 + `git rev-parse HEAD`），manifest 引用的 commit 必须包含新 token 值；回执（`.munk/changes/{workItemId}/digest.md`）记录每项 `ac-*` 的命令/退出码/关键输出，不只写结论。
- 已知风险（本项不修，留待视图项）：`ios/PurePace/Run/RunView.swift` 仍有 `Colors.accent` 作正文/链接前景的用法（约 L345/L409/L419），浅色下会落到约 2.00:1；本项只登记豁免与补偿约束，不改视图。

### 预算

≤8M token / ≤90 分钟墙钟；到点即停手交「已做 / 未做 / 未闭合点」回执，不降断言、不放宽阈值。
