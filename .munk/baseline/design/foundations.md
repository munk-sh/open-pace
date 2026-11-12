# Design foundations

Token 真源：`ios/PurePace/Design/DesignTokens.swift`（唯一）。视图与组件只引用 token，不写字面色值与零散字体修饰符。

## 颜色

表达方式 `SRGB`（0...1 三分量）+ `ColorPair { light, dark }`；动态 `Color` 走 `Color(uiColor: UIColor { trait in ... })`，只 `import SwiftUI`。18 个语义色全部 light/dark 成对，`Appearance.supportsDarkMode = true`。

| 语义 token | Light | Dark | 用途 |
|---|---|---|---|
| background | `#FAFAF9` | `#0B0C0D` | 页面底色 |
| surface | `#FFFFFF` | `#16181A` | 卡片面 / 底部控制区 |
| surfaceMuted | `#F2F2F1` | `#1E2124` | 提示弱底 / 次级面板 |
| primary | `#17181A` | `#F2F3F4` | 正文 / hero 数字 |
| secondary | `#5C5F63` | `#A2A7AC` | 次文 / 字段标签 |
| accent | `#FF9A5C` | `#FF9A5C` | 唯一品牌橙（V1.2 定稿，浅深同值）：开始/暂停/继续/结束/保存与选中态 |
| onAccent | `#2A1206` | `#2A1206` | 主色底上的文字（浅深同值，vs accent 8.44） |
| accentSoft | `#FFECE0` | `#3A1F12` | 记录态弱底（light 按新主色重算） |
| separator | `#D8D8D3` | `#33383D` | 卡片描边 / 分隔 |
| warning / onWarning / warningSoft | `#6E5C00` / `#FFFFFF` / `#FBF1DC` | `#EECA2B` / `#2B1A00` / `#3A2A0D` | 非阻断内联提示（权限缺失 / GPS 弱 / 保存失败），不作填充主按钮 |
| success / onSuccess / successSoft | `#1F6B45` / `#FFFFFF` / `#E7F2EB` | `#58CF9B` / `#042416` / `#11311F` | 已保存 |
| danger / onDanger / dangerSoft | `#660D09` / `#FFFFFF` / `#FBEAE8` | `#F53A48` / `#2A0608` / `#2C0A10` | 确认层实心破坏性主操作（丢弃）+ 无填充次操作（C2 图标式紧凑版） |

色板为方向 A「赛道石墨 + 竞速橙」：中性骨架（深色三中性键 HSL 色相 210°、chroma/255 ≤ 2.35%）+ 唯一品牌橙单点强调，明确避开早期「青绿 brand」与泛绿中性；warning/danger 与 accent 的色相区分靠 ΔH/ΔL/ΔS 判据（见域 `design-palette-a`）。`accent` 与 `onAccent` 是唯一允许 light==dark 的色键；同色相更深一档橙仅作 fallback，须人拍板后才可启用（当前未启用）。

## 字号 / 间距 / 圆角 / 描边

- `Typography`：`metricLabel 11` = `metricUnit 11`（指标三行角色，label 为 semibold）→ `caption 13` → `body 15` → `title 20` → `primaryValue 36`（monospaced semibold）→ `display 64`（monospaced bold）；另有 `control`（控件）与 `sectionHeader`（分组标题）。`sizes` 为严格递增 6 档 `[11,13,15,20,36,64]`；`roleLadder` 按字号非递减描述 7 角色（非相邻重复仅 label/unit）；`numericRoleNames = ["primaryValue","display"]` 是唯一的等宽数字角色集合，其余角色不得标记；字重集合恰 `[.regular, .semibold, .bold]`。
- `Spacing`：`xxs 4 / xs 8 / sm 12 / md 16 / lg 24 / xl 32`（严格递增）；语义项 `screenTop 24` / `cardGap 16` / `sectionGap 12` / `metricGroupSpacing 8`（指标组内）/ `metricGroupGap 16`（指标组之间）/ `cardPadding 16`，全部落在上述档位。
- `Radius`：`control 10 / card 14 / panel 20`（严格递增）。
- `Stroke.hairline = 1`：卡片内分隔线与控制区上沿描边。
- `Icon`：`inline 16 / row 20 / control 24`；`minTapTarget = 44`。
- `Motion`：`durationShort 0.2s`（数值/色块原地过渡）、`durationState 0.32s`（记录态切换）、`reducedMotionDuration = 0`，降级解析是纯函数 `Motion.duration(_:reduceMotion:)`（`reduceMotion == true` 一律 0）。本域只提供常量，动画接线在视图层后续落地。

## 对比度（WCAG 2.x）

`ios/PurePace/Design/ContrastPolicy.swift` 为 Foundation-only 纯函数：`ratio(foreground:background:) -> Double?`、`problems(for:) -> [String]`、`ratios(for:)`；阈值常量 body 4.5 / large 3.0，缺对、空名、分量越界一律 fail-closed。

成对矩阵单点声明在该文件（`pairMatrix`，37 对、18 个语义键全覆盖、只引用 palette 键、零十六进制），按 `Tier` 分三档：正文/小字 4.5、非文本 UI 3.0、装饰分隔 1.10（`separator` 仅装饰，不作为唯一信息载体；`accentSoft/surface` 为轨迹光晕叠卡片面的可辨识下限）；`checks(for:)` 在 light 与 dark 两侧求解整张矩阵。18 个语义键的机器可读用途注册表为 `DesignTokens.Colors.purposes`（键集必须等于 `palette`）。

**品牌优先豁免**：唯一豁免登记表 `brandPriorityExemptions` 恰 6 条，只登记 light 侧 `accent` 作前景的 3 个浅色中性底 × body/large 两档（`accent/background` 2.0049、`accent/surface` 2.0940、`accent/accentSoft` 1.8274、`accent/background@large` 2.0049、`accent/surface@large` 2.0940、`accent/surfaceMuted@large` 1.8693），dark 侧零豁免。豁免是登记而非改公式：`problems` 仍逐条真算比值，清空登记表则 6 条全部判红，未登记的低对比对仍 fail-closed；补偿手段只允许描边/字重/尺寸，禁改色相或压暗。

实测最低值：light 5.0667（secondary/dangerSoft）之上的豁免组 1.8274–2.0940，dark 4.7312（danger/surface）；装饰档 1.1266 / 1.1737（accentSoft/surface）；onAccent/accent 8.4446 两侧同值（浅深同色）。逐对实测落 `docs/evidence/palette-a-contrast.txt`（37 对 × 2 侧 = 74 行 + 豁免段 + 口径段，旁挂 `.sha256`），任何 hex 微调必须用同一函数重算并写入证据，不得低于阈值。
