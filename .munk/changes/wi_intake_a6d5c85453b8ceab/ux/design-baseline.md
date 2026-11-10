# 视觉基线（阶段 1）：纯 Pace 三屏

> token 真源：`ios/PurePace/Design/DesignTokens.swift`（唯一）。视图与组件只引用 token，不写字面色值与零散字体修饰符。

## 1. Token 源

### 颜色

表达方式：`SRGB`（0...1 三分量）+ `ColorPair { light, dark }`；动态 `Color` 通过 `UIColor { traits in ... }` 按系统外观解析，只 `import SwiftUI`。

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

主色取「松针青 / 跑道青」：既有运动感，又不与 iOS 默认蓝、警示橙、成功绿、危险红混淆。
`Appearance.supportsDarkMode = true`，18 个语义色全部 light/dark 成对，无缺侧。

### 字号 / 间距 / 圆角 / 描边

- `Typography`：`caption 12` → `body 15` → `title 20` → `primaryValue 34`（rounded semibold）→ `display 56`（rounded bold）；控件用 `control`，分组标题用 `sectionHeader`。
- `Spacing`：`xxs 4 / xs 8 / sm 12 / md 16 / lg 24 / xl 32`（严格递增）。
- `Radius`：`control 12 / card 16 / panel 20`（严格递增）。
- `Stroke.hairline = 1`：卡片内分隔线与控制区上沿描边。
- `Icon`：`inline 16 / row 20 / control 24`；`minTapTarget = 44`。

## 2. 组件清单（全部落在视图内，无新 target/依赖）

- `SurfaceCard`（内联修饰）：`surface` 填充 + `Radius.card` 圆角 + `separator` 描边 + `Spacing.*` 内边距。历史列表行、详情每节、导出区、历史空态共用同一套修饰。
- `HeroPanel`：`Radius.panel` 圆角 + `stateSoft` 弱底 + `separator` 描边，承载 hero 距离（`Typography.display`）。
- 主操作按钮：`actionTint` 填充 + `Radius.control` 圆角 + `onTint` 文字；次操作（结束）用 `warningSoft` 底 + `warning` 描边与文字。
- 提示胶囊：`caption` 字号 + 次要色/警示色文字 + `surfaceMuted`/`warningSoft` 弱底。
- `ContrastPolicy`：Foundation-only 纯函数，`ratio(foreground:background:) -> Double?`、`problems(for:) -> [String]`、`ratios(for:)`；阈值 body 4.5 / large 3.0，缺对、空名、分量越界一律 fail-closed。

## 3. 主屏：跑步页四层

1. **Hero 距离**：`Typography.display`，最大字号；底部色随三态（未开始 `primary` / 记录中 `accent` / 暂停 `warning` / 保存 `success`），底为对应弱底。
2. **次级指标**：`primaryValue`（用时 / 当前配速）+ `caption`（平均配速 / 分段），`safeAreaInset` 之外的内容区内垂直居中。
3. **提示**：`caption` + 次要色或警示色，带弱底；保存态额外显示 `success` 胶囊。
4. **主操作**：`safeAreaInset(edge: .bottom)` 固定底部，未开始与记录中共用 `accent`，暂停用 `warning`，保存用 `success`，`minHeight = 44`。

## 4. 关键取舍

- 只做 iOS 系统框架内的 token 体系，不引入 Asset Catalog 色彩集、自定义字体或图标资产管线；动态颜色用 `UIColor` trait 闭包解析，保持 `import SwiftUI` 单一入口。
- 历史 / 详情保留 `List` + `.plain`（`scrollContentBackground(.hidden)` + 卡片行）而非自绘卡片：`runDetail.export` 仍在首屏（实测 y=524.7pt、高 84pt），既有 UI 用例可直接点击。
- 排版层级用固定字号阶梯（不引入 `Dynamic Type` 缩放），换取可断言的字号阶梯与跨屏一致观感；大字号场景沿用既有 `ViewThatFits` 滚动退路。
- 视觉状态只通过颜色/弱底表达，不新增文案、不新增 identifier、不改状态机与主操作行为。
