# 方向 A「赛道石墨 / Graphite & Race-Orange」色板

代码唯一真源：`ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette`（18 键 × 浅/深 = 36 hex）。
逐对实测证据：`docs/evidence/palette-a-contrast.txt`（37 对 × 2 侧 = 74 行，含最薄 pair 与 accent/background）。

## 来源

- 色值真源：公司调研 digest `.../projects/ops_955931433a2c50ea/.munk/runs/trun_cff114e082a2fb0e/digest.md` §3「方向 A」+ §3.4 禁区表。
- V1.2 定稿（人逐像素取样拍板）：唯一品牌橙 `accent` 浅/深同值 `#FF9A5C`、`onAccent` 浅/深同值 `#2A1206`（8.44:1）、`accentSoft` 浅色重算 `#FFECE0`；旧砖红 `#B4400B`、设计稿候选 `#E85D04` 及一切压暗候选作废。
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
| accent | `#FF9A5C` | `#FF9A5C` |
| onAccent | `#2A1206` | `#2A1206` |
| accentSoft | `#FFECE0` | `#3A1F12` |
| separator | `#D8D8D3` | `#33383D` |
| warning | `#6E5C00` | `#EECA2B` |
| onWarning | `#FFFFFF` | `#2B1A00` |
| warningSoft | `#FBF1DC` | `#3A2A0D` |
| success | `#1F6B45` | `#58CF9B` |
| onSuccess | `#FFFFFF` | `#042416` |
| successSoft | `#E7F2EB` | `#11311F` |
| danger | `#660D09` | `#F53A48` |
| onDanger | `#FFFFFF` | `#2A0608` |
| dangerSoft | `#FBEAE8` | `#2C0A10` |

accent / 三中性键 / success 系 / on* / *Soft 逐键锁 A 表；warning 与 danger 系按裁决重取，数量仍 18 键、36 hex。
V1.2 定稿后仅 `accent` / `onAccent` 允许 light==dark（同值白名单），其余 16 键仍为浅/深双值；`warning` / `danger` / `success` 系维持双值。

## 品牌优先豁免（V1.2 唯一豁免族）

唯一品牌橙 `#FF9A5C` 作为前景压不住浅色中性底，人的取舍是**品牌优先**；矩阵把同一关系展开为 light 侧 6 条（3 个浅色中性底 × body/large 两档），豁免登记表**只**含这 6 条，dark 侧零豁免：

| 对 | 实测 | 档位 |
|---|---|---|
| `light accent/background` | 2.0049 | body 4.50 |
| `light accent/surface` | 2.0940 | body 4.50 |
| `light accent/accentSoft` | 1.8274 | body 4.50 |
| `light accent/background@large` | 2.0049 | large 3.00 |
| `light accent/surface@large` | 2.0940 | large 3.00 |
| `light accent/surfaceMuted@large` | 1.8693 | large 3.00 |

- 拍板来源：V1.2 定稿人拍板（唯一品牌橙作为前景 vs 浅色中性底，品牌优先）。
- 豁免只登记、不改公式：`ContrastPolicy.problems` 仍逐条真算，登记项单独放行；清空登记表后 6 条全部判红，未登记的低对比对仍 fail-closed。
- 补偿仅限描边 / 字重 / 尺寸，禁改色相或压暗；同色相更深一档（H 22–26）仅作 fallback，本轮未启用。

## 深色中性双度量（防回归）

| 键 | hex | HSV H | HSV S | chroma/255 | HSL H | 旧值 hex | 旧 H | 旧 chroma |
|---|---|---|---|---|---|---|---|---|
| background | `#0B0C0D` | 210.0° | 15.38% | 0.78% | 210.0° | `#0A1211` | 172.5° | 3.14% |
| surface | `#16181A` | 210.0° | 15.38% | 1.57% | 210.0° | `#141F1D` | 169.1° | 4.31% |
| surfaceMuted | `#1E2124` | 210.0° | 16.67% | 2.35% | 210.0° | `#1A2724` | 166.2° | 5.10% |

判据：HSV 色相落在 60–200° 之外，且 chroma/255 ≤ 3.0%（旧值三键全红）。
**HSV S 在深色 V≈5% 时分母极小（8.3–9.1%），不构成本轮判据**；原「HSV S ≤4%」条款已由公司作废。

## 与「早期 Android 青绿」禁区对照

- 旧 accent `#0B6F60`（HSV H171°/S82%）命中 H165–180°(S≥55) 禁区 → 现唯一品牌橙 `#FF9A5C`(H22.8°/S100%) 在禁区外，浅/深同值。
- 旧三中性键落在泛绿区间（166–172°）→ 现三键 210° 石墨冷中性。
- success 系（`#1F6B45` / `#58CF9B`）保留语义绿，属 A 表明确定值；禁区扫描按裁决排除 success/onSuccess/successSoft，其余 15 键必须全部在禁区外。

## 语义用途重映射（裁决 owe_40221a8e983c7516）

- **结束 / 保存 = 主操作 → accent**（不再归 warning）。
- **丢弃 = danger**：确认层实心破坏性主操作 + 无填充次操作（C2 图标式紧凑版）；不与 accent 同屏同形状并列。
- **warning 只用于非阻断内联提示**（权限缺失 / GPS 弱 / 保存失败横幅），禁止做填充主按钮。
- 暂停/继续随主操作族走 accent；一屏一个主操作不变。
