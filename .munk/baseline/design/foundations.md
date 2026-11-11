# Design foundations

Token 真源：`ios/PurePace/Design/DesignTokens.swift`（唯一）。视图与组件只引用 token，不写字面色值与零散字体修饰符。

## 颜色

表达方式 `SRGB`（0...1 三分量）+ `ColorPair { light, dark }`；动态 `Color` 走 `Color(uiColor: UIColor { trait in ... })`，只 `import SwiftUI`。18 个语义色全部 light/dark 成对，`Appearance.supportsDarkMode = true`。

| 语义 token | Light | Dark | 用途 |
|---|---|---|---|
| background | `#F7F8F6` | `#0A1211` | 页面底色 |
| surface | `#FFFFFF` | `#141F1D` | 卡片面 / 底部控制区 |
| surfaceMuted | `#F0F3F1` | `#1A2724` | 提示弱底 / 次级面板 |
| primary | `#12201E` | `#ECF4F1` | 正文 / hero 数字 |
| secondary | `#566663` | `#A6B8B3` | 次文 / 字段标签 |
| accent | `#0B6F60` | `#5ED6C4` | 唯一品牌主色：记录态 / 主操作 / 强调 |
| onAccent | `#FFFFFF` | `#06211C` | 主色底上的文字 |
| accentSoft | `#EDF6F3` | `#123B34` | 记录态弱底 |
| separator | `#DCE5E1` | `#25332F` | 卡片描边 / 分隔 |
| warning / onWarning / warningSoft | `#9A5B00` / `#FFFFFF` / `#FDF3E1` | `#F5B84C` / `#2B1A00` / `#3A2A0D` | 暂停 / 结束 / 降级提示 |
| success / onSuccess / successSoft | `#147A4E` / `#FFFFFF` / `#E8F6EF` | `#5BD69B` / `#042416` / `#11311F` | 已保存 |
| danger / onDanger / dangerSoft | `#B3261E` / `#FFFFFF` / `#FCEBE9` | `#FF8A80` / `#3A0906` / `#3A1A17` | 失败态 |

主色取「松针青 / 跑道青」：有运动感且不与 iOS 默认蓝、警示橙、成功绿、危险红混淆。

## 字号 / 间距 / 圆角 / 描边

- `Typography`：`metricLabel 11` = `metricUnit 11`（指标三行角色）→ `caption 12` → `body 15` → `title 20` → `primaryValue 34`（rounded semibold）→ `display 56`（rounded bold）；另有 `control`（控件）与 `sectionHeader`（分组标题）。`sizes` 为严格递增 6 档 `[11,12,15,20,34,56]`；`roleLadder` 按字号非递减描述 7 角色（非相邻重复仅 label/unit）；`numericRoleNames = ["primaryValue","display"]` 是唯一的等宽数字角色集合，其余角色不得标记。
- `Spacing`：`xxs 4 / xs 8 / sm 12 / md 16 / lg 24 / xl 32`（严格递增）；语义项 `screenTop 24` / `cardGap 16` / `sectionGap 12` / `metricGroupSpacing 8`（指标组内）/ `metricGroupGap 16`（指标组之间）/ `cardPadding 16`，全部落在上述档位。
- `Radius`：`control 12 / card 16 / panel 20`（严格递增）。
- `Stroke.hairline = 1`：卡片内分隔线与控制区上沿描边。
- `Icon`：`inline 16 / row 20 / control 24`；`minTapTarget = 44`。
- `Motion`：`durationShort 0.2s`（数值/色块原地过渡）、`durationState 0.32s`（记录态切换）、`reducedMotionDuration = 0`，降级解析是纯函数 `Motion.duration(_:reduceMotion:)`（`reduceMotion == true` 一律 0）。本域只提供常量，动画接线在视图层后续落地。

## 对比度（WCAG 2.x）

`ios/PurePace/Design/ContrastPolicy.swift` 为 Foundation-only 纯函数：`ratio(foreground:background:) -> Double?`、`problems(for:) -> [String]`、`ratios(for:)`；阈值常量 body 4.5 / large 3.0，缺对、空名、分量越界一律 fail-closed。

成对矩阵单点声明在该文件（`pairMatrix`，36 对、18 个语义键全覆盖、只引用 palette 键、零十六进制），按 `Tier` 分三档：正文/小字 4.5、非文本 UI 3.0、装饰分隔 1.10（`separator` 仅装饰，不作为唯一信息载体）；`checks(for:)` 在 light 与 dark 两侧求解整张矩阵。18 个语义键的机器可读用途注册表为 `DesignTokens.Colors.purposes`（键集必须等于 `palette`）。

实测最低值：light 4.81（success/successSoft）、dark 6.86（danger/dangerSoft）；onAccent/accent 6.07（light）/ 9.57（dark）。任何 hex 微调必须用同一函数重算并写入 digest，不得低于阈值。
