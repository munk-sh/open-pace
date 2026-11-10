# Screens index

三屏（Run / History / Settings）+ 跑次详情，zh-Hans 单语；文案唯一真源 `ios/PurePace/Resources/Localizable.xcstrings`，视图只引用 `L10n` 键。

## 跑步页（RunView）

四层自上而下：

1. **Hero 距离**：`Typography.display`，最大字号；HeroPanel 弱底随三态（未开始 `primary` / 记录中 `accent` / 暂停 `warning` / 保存 `success`）。
2. **次级指标**：`primaryValue`（用时 / 当前配速）+ `caption`（平均配速 / 分段）。四层在「导航栏下沿 → 控制区上沿」间等量分布：固定间距只取 `Spacing.screenTop` / `cardGap` / `sectionGap` 语义 token，剩余余量由 4 个等权 `Spacer(minLength:)` 吸收；小屏/大字号退回 `ScrollView`。平衡判据 `maximumTopGap` / `maximumBottomGap` / `maximumGap = 80pt`、`maximumImbalance = 16pt`。
3. **提示**：`caption` + 次要色或警示色，带弱底；保存态额外显示 `success` 胶囊。
4. **主操作**：`.safeAreaInset(edge: .bottom)` 固定底部，未开始与记录中共用 `accent`，暂停 `warning`，保存 `success`，`minHeight = 44`。

三态（running / paused / saved）只用颜色与弱底区分，不新增文案、identifier 与行为。
DEBUG `run.telemetry` 诊断摘要为内容区底部 overlay，不挤偏居中块。

## 历史页（HistoryView）

`List` + `.plain` + `scrollContentBackground(.hidden)`；行 = `SurfaceCard`：第一行日期（`title`），第二行距离 / 时长 / 配速（`caption` + 次要色）。空态 = 标题 + 一句说明 + CTA「去跑一次」（`history.runAgain`），不含示例跑次。

## 跑次详情（RunDetailView）

同为 `List` + `.plain` + 卡片节；节内数值 `caption` + 次要色，「导出 GPX」（`runDetail.export`）保持在首屏可直接点击（实测 y=524.7pt、高 84pt），导出流程与状态标识不变。

## 设置页（SettingsView）

带分组标题的 Section（含「播报」组），每项一句说明；`Toggle` tint 用 `accent`；保留 `settings.announcementToggle`，不新增控件与文案。

## 关键取舍

- 只做系统框架内的 token 体系，不引入自定义字体、图标资产管线或主题系统。
- 排版用固定字号阶梯（不做 Dynamic Type 缩放）换取可断言阶梯与跨屏一致观感。
- 保留 `List` + `.plain` 而非全自绘卡片，保住 `runDetail.export` 的 UI 用例可点性。
- 可及 identifier 集合冻结为 33 项（`run.*` / `runDetail.*` / `history.*` / `tab.*` / `settings.*`），不新增、不改名、不删除。
