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

- `Typography`：`caption 12` → `body 15` → `title 20` → `primaryValue 34`（rounded semibold）→ `display 56`（rounded bold）；另有 `control`（控件）与 `sectionHeader`（分组标题）。
- `Spacing`：`xxs 4 / xs 8 / sm 12 / md 16 / lg 24 / xl 32`（严格递增）。
- `Radius`：`control 12 / card 16 / panel 20`（严格递增）。
- `Stroke.hairline = 1`：卡片内分隔线与控制区上沿描边。
- `Icon`：`inline 16 / row 20 / control 24`；`minTapTarget = 44`。

## 对比度（WCAG 2.x）

`ios/PurePace/Design/ContrastPolicy.swift` 为 Foundation-only 纯函数：`ratio(foreground:background:) -> Double?`、`problems(for:) -> [String]`、`ratios(for:)`；阈值常量 body 4.5 / large 3.0，缺对、空名、分量越界一律 fail-closed。

实测最低值：light 4.81（success/successSoft）、dark 6.86（danger/dangerSoft）；onAccent/accent 6.07（light）/ 9.57（dark）。任何 hex 微调必须用同一函数重算并写入 digest，不得低于阈值。
