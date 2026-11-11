# Run 三态重建：首屏 / 跑步中 / 结束总结

## 范围

只重建 `ios/PurePace/Run/RunView.swift` 一个文件的视觉层级，三态口径固定为：

- **未开始（ready）**
- **跑步中（running + paused，暂停是跑步中子态）**
- **已保存总结（finished && didSave == true）**

输入是已冻结的令牌真源（`DesignTokens.swift` 的 `Colors` / `Typography` / `Spacing` / `Radius` / `Stroke` / `Icon`，其中 `metricLabel` / `metricUnit` / `metricGroupSpacing` / `metricGroupGap` / `cardPadding` 已在 token-core 落地）与 `docs/design/competitor-teardown.md` 的「映射到本产品」表；不重新设计令牌、不重新调研竞品。

每态自上而下固定四层，且只有四层：

1. **hero**：距离，唯一 `Typography.display` 主值（等宽数字）。
2. **次级主值**：用时 / 当前配速，`Typography.primaryValue`。
3. **caption 层**：平均配速 / 分段，`Typography.caption`。
4. **提示**：状态说明与已保存胶囊（`run.saved`），`caption` + 小面积弱底。
5. **主操作**：`safeAreaInset(edge: .bottom)` 底部控制区，每态恰好一个填充主操作；结束（破坏性）操作必须明显弱于主操作。

指标块排版统一为三行：上置标签（`metricLabel`）→ 数值（`display` / `primaryValue`，`monospacedDigit()`）→ 下置单位（`metricUnit`）。分组只用 `Stroke.hairline` + `surface` / `surfaceMuted` 明度差 + `Radius.card` / `Radius.panel`，零投影；`accent` 只用于可执行（主操作）与选中/记录态，不用作大块面板底色。

## 验收

- ac-gate-lint-green: `bash scripts/check-ios-shell.sh` 退出 0；同门 `--self-test` 全绿；`bash scripts/check-baseline.sh` 与 `bash scripts/test-ios.sh --unit-only` 均退出 0。
- ac-token-zero-literals: 改后 `RunView.swift` 仍零字面色值（`Color(` / `Color.` / `UIColor` / `#colorLiteral` / `0x…`）、零零散字体修饰符（`.font(.` / `Font.system(` / `.fontWeight(` 等）、零动效时长字面量与零样式字面量（`spacing: 0` 用 `.zero`，`padding` / `minHeight` / `spacing` 只取 `DesignTokens.*`）。
- ac-identifier-set-frozen: 全仓 `run.* / runDetail.* / history.* / tab.* / settings.*` 可及 identifier 集合仍等于门禁冻结的 33 项；`RunView` 内 `run.distance / run.elapsed / run.currentPace / run.averagePace / run.splits / run.start / run.pause / run.resume / run.finish / run.saved / run.viewHistory / run.backgroundDegraded / run.telemetry` 不新增、不改名、不删除。
- ac-label-unit-roles: 距离、用时、当前配速、平均配速、分段五个指标块的标签字号为 `DesignTokens.Typography.metricLabel`；有单位的两项（距离 `km`、配速 `/km`）单位走 `Typography.metricUnit`；距离值仍是 `Typography.display`，用时与当前配速仍是 `Typography.primaryValue`，平均配速与分段值仍是 `Typography.caption`；`RunView` 内 `monospacedDigit()` ≥ 3 处（门禁下限）。
- ac-unit-split-a11y-stable: 单位从数值行拆出展示后，`run.distance` 的可及 label 仍等于 `RunFormatting.distanceText`（未开始为 `0.00 km`），`run.elapsed` 仍为 `00:00`，`run.currentPace` / `run.averagePace` 空值仍为 `--`（不带 `/km`）；现有 RunFlowUI 用例断言字符串不需要改。
- ac-single-primary-action: 每态控制区恰好一个填充主操作并走同一 helper：ready = `run.start`（accent）、running = `run.pause`（accent）、paused = `run.resume`（warning）、saved = `run.viewHistory`（success）；四者 `minHeight = DesignTokens.minTapTarget`，同一 `safeAreaInset(edge: .bottom)` 锚点、同一行高。
- ac-destructive-weaker: running / paused 下 `run.finish` 不与主操作等宽等重：无填充主色底（只描边/文字，`warning` 系）、水平宽度小于主操作（不得 `frame(maxWidth: .infinity)`）、视觉字号与对比弱于主操作，同时仍满足 ≥ 44pt 点按区与既有 `accessibilityLabel(Text(label))`。
- ac-three-states-distinguishable: 门禁依赖的三行状态取色原文保持可匹配（`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }`），即 hero 数值色仍按 ready=primary / running=accent / paused=warning / saved=success 区分；saved 态仍渲染 `run.saved` 胶囊。
- ac-neutral-grouping: `RunView` 内零 `.shadow(`、零渐变、零嵌套双描边卡片；hero 面板底色只取中性 `surface` / `surfaceMuted`（不再用 `accentSoft` / `warningSoft` / `successSoft` 铺满 hero），状态弱底只出现在提示胶囊这类小面积元素上。
- ac-ax5-no-truncation: 保留 `ViewThatFits(in: .vertical)` → `ScrollView` 退路与等权 `Spacer(minLength:)` 分布；不引入固定高度、`lineLimit(1)`、`fixedSize(horizontal: true)`；`DynamicTypeLayoutTests` 与 `PrimaryActionLayoutPolicy` 现有用例全绿。
- ac-l10n-zero-diff: `ios/PurePace/Design/L10n.swift` 与 `Resources/Localizable.xcstrings` 零 diff，`RunView` 内仍存在 ≥ 4 个互不相同的 `label: L10n.*` 与 `accessibilityLabel(Text(label))`，且 `L10n.runActionStart / Pause / Resume / Finish` 四个键仍被引用。

## 非目标

- 不改状态机、`RunSessionViewModel`、`RunCore`、持久化、定位、音频、GPX、导出、遥测。
- 不改 `L10n.swift` / `Localizable.xcstrings`（不新增、不改文案键），不改 `DesignTokens.swift` / `ContrastPolicy.swift`、`scripts/**`、`.munk/code-gates.json`、`ios/project.yml` 与 `.xcodeproj`。
- 不改 `HistoryView` / `RunDetailView` / `SettingsView` / `ContentView`（同波其它子项负责）。
- 不新增屏、Tab、路由、组件库文件、第三方字体或图标资产。
- 不新增或改名任何 accessibility identifier，不改现有可及 label 契约。
- 不做保存/丢弃二选一（第 4 波），不处理 `finished && didSave == false` 的空控制区（第 4 波交互闭环）。
- 不做动效接线（`Motion` 常量的视图层使用）、不做 Reduce Motion 视图接线、不做截图归档到 `docs/screenshots`、不做真机验收。
- 不扩功能面：不新增指标、不新增数据字段、不新增空态/权限态分支。

## 实现约束

- 改动面收敛在 `ios/PurePace/Run/RunView.swift`；若需拆分数值/单位，只在 `ios/PurePace/Run/RunFormatting.swift` **新增**纯函数（如 `distanceValueText` / `distanceUnitText` / `currentPaceValueText` / `currentPaceUnitText`），保留现有 `distanceText` / `paceText` / `elapsedText` / `splitCountText` 的签名与输出不变，L1 用例补在 `ios/PurePaceTests/RunFormattingTests.swift`，不得改动既有断言。
- 门禁是字符串级断言，以下原文行必须仍能在 `RunView.swift` 中 `grep -Fq` 命中，重构只能围绕它们进行：`case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }`、`safeAreaInset(edge: .bottom)`、`DesignTokens.Typography.display`、`DesignTokens.Typography.primaryValue`、`DesignTokens.Typography.caption`、`DesignTokens.Colors.accent`、`DesignTokens.minTapTarget`、`accessibilityLabel(Text(label))`。
- 样式数字一律取 token；`spacing: 0` 会被「样式字面量」规则判红，必须写 `.zero`；不得出现 `.padding(12)`、`minHeight: 44` 一类字面量。
- 三行排版规则：标签在上（`metricLabel` + `secondary`）、数值居中（`display` / `primaryValue`，`monospacedDigit()`）、单位在下（`metricUnit` + `secondary`）；无单位项（用时、分段、空配速）不渲染空单位行；指标组内用 `Spacing.metricGroupSpacing`，组间用 `Spacing.metricGroupGap`，卡片内边距用 `Spacing.cardPadding`。
- 单位拆分后必须用显式 `accessibilityLabel` 复原合并串（距离 `Text(viewModel.distanceText)`，配速只在非空时拼 `/km`），保证既有 UI 用例的 label 相等断言不改；空配速仍为 `--`。
- 控制区结构：复用同一 `primaryControl` 填充按钮 + 一个紧凑 `secondaryControl`；running / paused 同排时主操作 `frame(maxWidth: .infinity)`，`run.finish` 用内在宽度 + `Spacing` 内边距与 `warning` 描边，禁止 `maxWidth: .infinity`，禁止与主操作同底色。
- AX5：保留 `ViewThatFits` → `ScrollView` 与四段等权 `Spacer(minLength:)`，不新增固定高度或截断修饰符；`RunLayoutBalancePolicy` 的 `maximumGap = 80` / `maximumImbalance = 16` 判据与 `PrimaryActionLayoutPolicy` 阈值不动。
- 开工先在本子项 digest 首行写预算与期望收口时刻，超时即停手回执，不靠长会话补绿；如需截图证据只落 `.munk/changes/wi_ws_42e16c64648066eb/`，不覆盖 `docs/screenshots`。
