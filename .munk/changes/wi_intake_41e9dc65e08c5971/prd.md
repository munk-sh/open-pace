# iOS 三屏中文本地化与主操作底部锚定

## 范围

公司裁决 `owe_bd22c86ba9f83139` 已核阶段 1 交付（main `e26e264` / commit `9b54b85`），本条仅批准三类窄改动：

- **A. 用户可见文案 zh-Hans 单语 + 单一本地化来源**
  - 新增 String Catalog（`ios/PurePace/Resources/Localizable.xcstrings`，`sourceLanguage=zh-Hans`）作为唯一本地化来源。
  - `ios/project.yml` 增补 resources、`CFBundleDevelopmentRegion` / `knownRegions`，经 XcodeGen 重新生成工程（禁手改 `project.pbxproj`）。
  - Tab（跑步/历史/设置）、导航标题、返回键、字段标签（距离/用时/当前配速/平均配速/分段）、空态、提示、按钮、「已保存」等状态文案全部改走该来源；视图内不得保留裸英文字面量。
  - a11y label 用中文且与可见文字语义一致；既有 `accessibilityIdentifier`（`run.start` / `tab.run` / `runDetail.export` 等）一律不改名。
  - 本期不做英文、不做双语。
- **B. 日期 zh-Hans（详情页 + 历史行）**
  - 详情页时间固定 zh-Hans 格式（示例「2025年10月9日 16:53」），不得出现英文月份或 `at`。
  - 历史列表行日期同样 zh-Hans。
  - 实现须显式指定 `zh_Hans` locale 与时区无关的稳定格式，便于固定 fixture 断言。
- **C. 主操作固定底部控制区**
  - 首屏「开始」、运行中「暂停/结束」、结束保存态主按钮统一下沉到安全区上方、TabBar 之上固定间距（`safeAreaInset(edge: .bottom)` 或等价底部容器）。
  - 点按区高 ≥44pt（复用 `DesignTokens.minTapTarget`）。
  - 上方指标区与权限提示随之下沉收紧，消除约 200pt 空白；三态都必须满足。

## 验收

- ac-visible-copy-zh-hans：模拟器 UI 用例读取三屏（跑步/历史/设置）可及树中全部可见 label/text，逐条匹配 zh-Hans 白名单（仅允许 `km`、`/km`、单位与数字），零裸英文；判定抽成纯函数 `VisibleTextPolicy`，其单测用固定列表通过 + 一条英文反例证明能红；UI 用例把真实可及树喂给同一判定，反例自测证明断言可反向失败。
- ac-run-detail-date-zh-hans：单测以固定 `Date` + 固定 `TimeZone` 断言详情时间形如「2025年10月9日 16:53」，不含英文月份集合与 `at`；历史行日期同样为 zh-Hans；同一判定对英文 locale/abbreviated 反例样本必须返回拒绝（反向用例能红）。
- ac-primary-action-bottom-anchored：UI 用例在首屏「开始」、运行中「暂停/结束」、结束保存态三态读取主操作按钮 `frame`，判定（a）高 ≥44pt；（b）按钮底边距底部安全区 ≤ 阈值（≤24pt，digest 记录实测值）；（c）位于 TabBar 之上；判定抽成纯函数 `PrimaryActionLayoutPolicy`，单测用「距 safe area 200pt / 高 30pt」反例证明能红。

## 非目标（越界即停并回报）

- 不改视觉体系：不重设计 `DesignTokens` 数值与层级，不新增 token。
- 不改算法/状态机；不碰定位/音频/TTS/持久化/GPX 导出链路。
- 不改 `accessibilityIdentifier` 命名；不加英文/双语。
- 不动 demo 的 `#if DEBUG` 门控与既有反向用例；不降任何既有断言。
- 不新增 CI workflow 腿；不做真机验收（真机项仍 `pending: 待人现场`）。
- 不改 Android、`shared/`、`ios/RunCore`、`ios/Core`、`Harness/` 的源码与契约。

## 实现约束

**预算与收口（开工先落）**：本条预算 ≤10M token、墙钟 ≤90 分钟。开工时刻 2026-11-11 02:02 CST，期望收口时刻 2026-11-11 03:32 CST；超时即停手并回执，不硬撑。

**A 的锚点**
- 现有裸字面量落点（Coding 需全面清理，不止这些）：`ios/PurePace/ContentView.swift`（`Label("Run"/"History"/"Settings")` 与导航标题）、`ios/PurePace/Run/RunView.swift`（`"Time"/"Current"/"Average"/"Splits"/"Distance"/"Run"`、状态提示、`"已保存"` 及 开始/暂停/继续/结束）、`ios/PurePace/History/HistoryView.swift`（空态、`"History"`）、`ios/PurePace/History/RunDetailView.swift`（字段标签、导出段、`"跑次详情"`）、`ios/PurePace/Settings/SettingsView.swift`（开关与说明文案）。格式化函数 `RunFormatting` 内的单位拼接（`km`、`/km`）属白名单，不改成硬编码文案。
- String Catalog 只新增 `ios/PurePace/Resources/Localizable.xcstrings`；`project.yml` 用 `sources`/`resources` 与 `INFOPLIST_KEY_CFBundleDevelopmentRegion`、`knownRegions` 声明，生成物 `PurePace.xcodeproj` 仍由 XcodeGen 产出并入库。
- 既有 identifier 清单保持原样（`run.*` / `tab.*` / `history.*` / `runDetail.*` / `settings.announcementToggle`），只允许改可见文案与 a11y label 文本。

**B 的锚点**
- 详情时间当前由 `RunFormatting.dateTimeText`（`date.formatted(.abbreviated/.standard)`）产出；历史行在 `HistoryView.row(for:)` 内直接 `record.startedAt.formatted(date: .abbreviated, time: .shortened)`。两处必须统一走显式 `zh_Hans` locale + 固定 pattern 的纯函数，并固定 `TimeZone` 参数以便 fixture 断言。
- 判定逻辑（如 `VisibleDatePolicy` / `zhHansDateTimeText` + 反例拒绝）放纯类型/纯函数，`PurePaceTests` 直测，不写进 `RunCore`。

**C 的锚点**
- `RunView` 当前为 `VStack + Spacer()` 顶部堆叠；改为主内容区 + `.safeAreaInset(edge: .bottom)`（或等价底部容器）承载 `controls`，并在指标区与操作区之间收紧留白，不改 `DesignTokens` 数值。
- 三态均需覆盖：`.ready`（开始）、`.running`/`.paused`（暂停/继续 + 结束）、`didSave` 保存态；主按钮 `frame(minHeight: DesignTokens.minTapTarget)` 保持 ≥44pt。
- UI 断言读取按钮 `frame` 与 TabBar / 底部安全区关系；`PrimaryActionLayoutPolicy` 纯函数单测覆盖 200pt 间距与 30pt 高度反例。

**门禁与证据**
- 推荐在 `scripts/check-ios-shell.sh` 增加 `validate_localization` 静态断言（扫描 `ios/PurePace` 视图残留裸英文文案），并纳入 `--self-test` 正负例；`pipefail` 下禁用 `cmd | grep -q`，改用 here-string/内建匹配。
- 证据同名覆盖并用 `shasum -a 256` 逐文件入 digest，注明可复现生成命令（真实模拟器构建，非手绘）：
  - `docs/screenshots/` 5 图：`run-not-started.png` / `run-running.png` / `history-detail.png` / `history-empty.png` / `settings.png`。
  - `docs/evidence/a11y/` 6 树：`01-run-not-started` / `02-run-running` / `03-history-empty` / `04-history-detail` / `05-settings` / `06-tabs`。
  - 截图与 a11y 需在文案/布局改动后重新生成；可复用 `RunLaunchArguments` 的截图门控与 `scripts/verify-ios-ui-e2e.sh` 的 `xcresulttool export attachments` 导出路径，或等价的 `simctl io screenshot` + 可及树 dump 流程。
- 若 `code_gates` 出现 attempt ≥2，digest 必须逐条写清上一 attempt 的失败项或作废原因（树变化 or 环境），不得只写「重跑后绿」。
- 交付回执只要三样：① 新 5 图 + 6 树路径；② 三条新断言的门名与通过日志（命令 + 关键输出行）；③ diff 范围（只含 A/B/C 三类改动 + 对应测试与证据）。
