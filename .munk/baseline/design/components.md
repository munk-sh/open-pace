# Design components

全部以视图内联修饰实现，无新 target / 依赖 / Asset Catalog 色彩集；只引用 `DesignTokens`（`ios/PurePace/Design/DesignTokens.swift`）。

- `SurfaceCard`：`surface` 填充 + `Radius.card` 圆角 + `separator` 描边 + `Spacing.*` 内边距。历史列表行、详情每节、导出区、历史空态共用。
- `HeroPanel`：`Radius.panel` 圆角 + 状态弱底（`accentSoft`/`warningSoft`/`successSoft`）+ `separator` 描边，承载 hero 距离（`Typography.display`）。
- 主操作按钮：`actionTint` 填充 + `Radius.control` 圆角 + `onTint` 文字 + `minHeight = minTapTarget`；次操作（结束）用 `warningSoft` 底 + `warning` 描边与文字。
- 提示胶囊：`caption` 字号 + 次要色 / 警示色文字 + `surfaceMuted` / `warningSoft` 弱底。
- 指标文本：距离 `display`、用时 / 当前配速 `primaryValue`、平均配速 / 分段 `caption`，全部 `.monospacedDigit()`。

约束：组件文件命中 `Color(`、`Color.`、`UIColor`、`#colorLiteral`、`.foregroundStyle(.` 与 `.font(.`、`.fontWeight(`、`.fontDesign(`、`.lineSpacing(<数字` 即静态门失败（`DesignTokens.Typography.*` 与 `.monospacedDigit()` 除外）。
