# 方向 A「赛道石墨 / Graphite & Race-Orange」色板

代码唯一真源：`ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette`（18 键 × 浅/深 = 36 hex）。
逐对实测证据：`docs/evidence/palette-a-contrast.txt`（37 对 × 2 侧 = 74 行，含最薄 pair 与 accent/background）。

## 来源

- 色值真源：公司调研 digest `.../projects/ops_955931433a2c50ea/.munk/runs/trun_cff114e082a2fb0e/digest.md` §3「方向 A」+ §3.4 禁区表。
- V1.2 终版（2026-11-13 人拍板）：`accent` 浅/深同值 `#FF6B00`、`onAccent` 浅/深同值 `#2A1206`（实测 6.1932:1）、`danger` 浅/深同值 `#F53A48`、`onDanger` 浅/深同值 `#2A0608`（实测 4.9479:1）；`accentSoft` 浅色按同一派生口径从新主色重算为 `#FFE3CF`。旧砖红 `#B4400B`、旧品牌橙 `#FF9A5C`、设计稿候选 `#E85D04` 及一切压暗候选作废。
- Owner 批准的唯一非品牌色微调（同项决策）：`warning.dark` `#EECA2B` → `#EECF2B`（HSL H 48.9231 → 50.4615、S 85.1528 / L 55.0980 零漂移），使 `accent↔warning` 在 dark 侧 ΔH 25.285° 达标；其余 23 个非 accent/danger 槽位零漂移。
- 语义色修正：公司裁决 `owe_40221a8e983c7516`（warning/danger 重取 + 用途重映射）与 `owe_0b599686dc8f7475`（HSL 口径）。
- 深色中性判据：公司裁决（原「HSV S ≤4%」作废）。

逐键 hex 与代码逐键一致（测试 `DesignTokensTests.testPaletteHexMatchesDirectionATable` 用字面 UInt32 表钉住）。

## 18 键 × 浅/深

| 键 | light | dark |
|---|---|---|
| background | `#FAFAF9` | `#0B0C0D` |
| surface | `#FFFFFF` | `#16181A` |
| surfaceMuted | `#F2F2F1` | `#1E2124` |
| primary | `#17181A` | `#F2F3F4` |
| secondary | `#5C5F63` | `#A2A7AC` |
| accent | `#FF6B00` | `#FF6B00` |
| onAccent | `#2A1206` | `#2A1206` |
| accentSoft | `#FFE3CF` | `#3A1F12` |
| separator | `#D8D8D3` | `#33383D` |
| warning | `#6E5C00` | `#EECF2B` |
| onWarning | `#FFFFFF` | `#2B1A00` |
| warningSoft | `#FBF1DC` | `#3A2A0D` |
| success | `#1F6B45` | `#58CF9B` |
| onSuccess | `#FFFFFF` | `#042416` |
| successSoft | `#E7F2EB` | `#11311F` |
| danger | `#F53A48` | `#F53A48` |
| onDanger | `#2A0608` | `#2A0608` |
| dangerSoft | `#FBEAE8` | `#2C0A10` |

V1.2 终版后 `accent` / `onAccent` / `danger` / `onDanger` 允许 light==dark（同值白名单，恰 4 键），其余 14 键仍为浅/深双值（含 `warning` / `success` / `dangerSoft`）。
相对本项改动前：`accent` 两槽、`accentSoft.light`、`danger` 两槽、`onDanger.light`、`warning.dark`（Owner 批准）共 7 槽变化，其余 29 槽逐字节不变。

### `accentSoft.light` 派生口径（文档化公式）

同一口径贯穿旧新主色：**19% accent 叠在纯白上**，逐通道四舍五入：

```
channel(hex) = round(0.19 · accent.channel + 0.81 · 255)
```

- 旧值：`accent #FF9A5C` → `(255, 236, 224)` = `#FFECE0`。
- 新值：`accent #FF6B00` → `(255, 227, 207)` = `#FFE3CF`（H 25.0° / S 100% / L 90.6%），dark 仍 `#3A1F12`。
- 实测 `light accent/accentSoft = 2.3304`。协议里曾写的「≈2.49」只对旧 `#FFECE0` 的亮度成立，对新橙不成立，按作废处理；不为凑该值反推公式或改 hex。

## 关键对比度实测（WCAG 2.x，公式 `(L1+0.05)/(L2+0.05)`，4 位小数）

| 对 | light | dark | 档位 |
|---|---|---|---|
| `primary/background` | 17.0109 | 17.6221 | body 4.50 |
| `secondary/background` | 6.1449 | 8.0731 | body 4.50 |
| `primary/accentSoft` | 14.5014 | 13.6512 | body 4.50 |
| `secondary/accentSoft` | 5.2384 | 6.2540 | body 4.50 |
| `onAccent/accent` | 6.1932 | 6.1932 | body 4.50 |
| `onWarning/warning` | 6.5751 | 10.8722 | body 4.50 |
| `onSuccess/success` | 6.4670 | 8.5205 | body 4.50 |
| `onDanger/danger` | 4.9479 | 4.9479 | body 4.50 |
| `danger/background` | 3.6026 | 5.2034 | non-text 3.00 |
| `danger/surface` | 3.7626 | 4.7312 | non-text 3.00 |
| `danger/dangerSoft` | 3.2315 | 4.8198 | non-text 3.00 |
| `accentSoft/surface` | 1.2252 | 1.1737 | decorative 1.10 |
| `separator/background` | 1.3694 | 1.6537 | decorative 1.10 |

阈值常量：`bodyThreshold = 4.5`、`largeThreshold = 3.0`、`decorativeThreshold = 1.10`（本项零改动）。37 对 × 2 侧逐行见证据文件。

**light danger 仅作确认层填充主操作与 C2 图标着色，不作正文文字**：light `danger` 对 `background` / `surface` / `dangerSoft` 分别只有 3.6026 / 3.7626 / 3.2315，物理上到不了 4.50，故这三条在 `pairMatrix` 里改判非文本 3.0 档（不从矩阵移除，总数仍 37）；danger 的正文对比责任由 `onDanger/danger`（4.9479）承担。

## 品牌优先豁免（V1.2 唯一豁免族）

唯一品牌橙 `#FF6B00` 作为前景压不住浅色中性底，人的取舍是**品牌优先**；矩阵把同一关系展开为 light 侧 6 条（3 个浅色中性底 × body/large 两档），豁免登记表**只**含这 6 条，dark 侧零豁免：

| 对 | 实测 | 档位 |
|---|---|---|
| `light accent/background` | 2.7338 | body 4.50 |
| `light accent/surface` | 2.8552 | body 4.50 |
| `light accent/accentSoft` | 2.3304 | body 4.50 |
| `light accent/background@large` | 2.7338 | large 3.00 |
| `light accent/surface@large` | 2.8552 | large 3.00 |
| `light accent/surfaceMuted@large` | 2.5488 | large 3.00 |

- 拍板来源：V1.2 终版人拍板（唯一品牌橙作为前景 vs 浅色中性底，品牌优先）。
- 豁免只登记、不改公式：`ContrastPolicy.problems` 仍逐条真算，登记项单独放行；清空登记表后 6 条全部判红，未登记的低对比对仍 fail-closed。
- 补偿仅限描边 / 字重 / 尺寸，禁改色相或压暗；同色相更深一档（H 22–26）仅作 fallback，本轮未启用。

## 品牌色分离度（HSL，ΔH 口径）

| 对 | light | dark | 结论 |
|---|---|---|---|
| `accent↔danger` | ΔH 29.6685°（ΔL 9.4118pp / ΔS 9.6618pp） | ΔH 29.6685°（同色） | 靠 ΔH ≥25° 达标 |
| `accent↔warning` | ΔH 25.0053°（ΔL 28.4314pp） | ΔH 25.285°（ΔL 5.0980pp / ΔS 14.8472pp） | 两模式均 ΔH ≥25° |

- `accent` HSL：H 25.1765° / S 100% / L 50.0%；`danger`：H 355.508° / S 90.3382% / L 59.4118%；`warning.light`：H 50.1818°；`warning.dark`：H 50.4615°。
- 必红反例：旧 `warning.dark #EECA2B` 对新 accent 实测 ΔH 23.7466°、ΔL 5.0980pp、ΔS 14.8472pp，三项全不成立；旧 accent `#FF9A5C` 对旧 warning `#F0B44C`、旧 accent 对旧 danger 亦全红。
- 判据阈值 ΔH ≥ 25° 不变（另有 ΔL ≥15pp / ΔS ≥30pp 为同域既有 OR 口径）；danger 侧不再以 ΔL/ΔS 作为通过理由。

## 深色中性双度量（防回归）

| 键 | hex | HSV H | HSV S | chroma/255 | HSL H | 旧值 hex | 旧 H | 旧 chroma |
|---|---|---|---|---|---|---|---|---|
| background | `#0B0C0D` | 210.0° | 15.38% | 0.78% | 210.0° | `#0A1211` | 172.5° | 3.14% |
| surface | `#16181A` | 210.0° | 15.38% | 1.57% | 210.0° | `#141F1D` | 169.1° | 4.31% |
| surfaceMuted | `#1E2124` | 210.0° | 16.67% | 2.35% | 210.0° | `#1A2724` | 166.2° | 5.10% |

判据：HSV 色相落在 60–200° 之外，且 chroma/255 ≤ 3.0%（旧值三键全红）。
**HSV S 在深色 V≈5% 时分母极小（8.3–9.1%），不构成本轮判据**；原「HSV S ≤4%」条款已由公司作废。

## 与「早期 Android 青绿」禁区对照

- 旧 accent `#0B6F60`（HSV H171°/S82%）命中 H165–180°(S≥55) 禁区 → 现唯一品牌橙 `#FF6B00`(H25.2°/S100%/L50.0%) 在禁区外，浅/深同值。
- 旧三中性键落在泛绿区间（166–172°）→ 现三键 210° 石墨冷中性。
- success 系（`#1F6B45` / `#58CF9B`）保留语义绿，属 A 表明确定值；禁区扫描按裁决排除 success/onSuccess/successSoft，其余 15 键必须全部在禁区外。

## 语义用途重映射（裁决 owe_40221a8e983c7516）

- **结束 / 保存 = 主操作 → accent**（不再归 warning）。
- **丢弃 = danger**：确认层实心破坏性主操作 + 无填充次操作（C2 图标式紧凑版）；浅色侧只作填充与图标着色，不作正文文字；不与 accent 同屏同形状并列。
- **warning 只用于非阻断内联提示**（权限缺失 / GPS 弱 / 保存失败横幅），禁止做填充主按钮。
- 暂停/继续随主操作族走 accent；一屏一个主操作不变。
