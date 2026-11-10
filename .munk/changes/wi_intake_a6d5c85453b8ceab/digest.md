# 交付回执：iOS 三屏视觉体系阶段 1 收口

基线 `main 01b5f28`；本项不新增 gate id、不改 `.munk/code-gates.json` 门列表（22 门）。

## 1) 结论

- 唯一品牌主色 `DesignTokens.Colors.accent`（松针青 `#0B6F60` / 暗色薄荷青 `#5ED6C4`）：记录态、主操作、强调共用同一 token。
- 18 个语义色全部 light/dark 成对，`Appearance.supportsDarkMode == true`，暗色为真实运行产物（非改色旧图）。
- 跑步页四层（hero 距离 → 次级指标 → 提示 → 底部主操作）+ 三态可视（记录中 accent / 暂停 warning / 保存 success）。
- 历史列表、跑次详情、设置页统一 `surface` 卡片面 / `Radius.card` / `Spacing.*` / `separator`，移除系统 grouped 默认观感。
- 全部数字 `.monospacedDigit()`；字号 / 字重 / 行距只从 `Typography` 取。
- 新增 `ContrastPolicy`（Foundation-only 纯函数）与 7 条对比度单测；静态门新增字面色值、零散字体、暗色、卡片面、四层、等宽数字、三态、identifier 冻结共 9 类断言及 8 条反例自检。
- a11y identifier 集合与基线完全一致（33 项），6 棵可及树重采后集合 diff 为 0。

## 2) 证据：新截图 + sha256

设备：iPhone 16 模拟器（`B3F00298-E08A-41E0-876E-6E8A75C730FD`，iOS 18.6）；Xcode 26.3（Build 17C529）。

```
acd9325d3c273593e5a7df57fc3fdefc287700db232f2f3322427e019d8d54f6  docs/screenshots/run-running-dark.png   (新增)
1bfd4dd6a3eea0e2434371ff6e035fda7f7733a99dde3a312282bd457b5c43d1  docs/screenshots/run-not-started.png
ea2c15043b304f668a672f6116f086d7e359766236843910cff04a94dbe7ba40  docs/screenshots/run-running.png
e1cce1a5274460b9865b2d6e646401fcd3aed1d13471ca1906fc0e81c20536f9  docs/screenshots/history-detail.png
83b59bcb3612a4971ff8bdaebdca6fa0537bab1d9736f3446d596c3237fabeb1  docs/screenshots/history-empty.png
bafd46da477952f54ebdf0956ef7f0ea8e75b8fd71988cf50cd00734c44ef7de  docs/screenshots/settings.png
```

可及树（identifier 集合与基线逐棵相同，见 §5）：

```
8a3ea4a878fbc307d564afbe67eb78c1737ad643842e54580ed4800c69ab29e2  docs/evidence/a11y/01-run-not-started.txt
9b38df0415caa86d6d375f16ab7443286dee9f88da8198fbbf3ac0fd3a4e8756  docs/evidence/a11y/02-run-running.txt
25d3e6636cfd64051a4b1e4d562039cd18284af9ba7046715083249f9e094687  docs/evidence/a11y/03-history-empty.txt
eded1453495ff4bf226a019941eaca70725340b2c927da8fa8e364e4945d3ae2  docs/evidence/a11y/04-history-detail.txt
e38d258e27236bd5115a7a9bb371652d7bd81bc69bc5898c3d21abc25ebce375  docs/evidence/a11y/05-settings.txt
57a57c43ba705ca12f28a0ff490b693400254618dea30332e774d5e83e449e15  docs/evidence/a11y/06-tabs.txt
```

## 3) 生成命令（本轮真实执行）

```bash
# 工程生成（project.yml 唯一真源，未手改 pbxproj）
cd ios && xcodegen generate

# 真实构建
bash scripts/build-ios.sh                       # ** BUILD SUCCEEDED **

# L1 单测（token 不变量 + 对比度）
cd ios && xcodebuild test -only-testing:PurePaceTests/ContrastPolicyTests \
  -only-testing:PurePaceTests/DesignTokensTests -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'

# L2 UI 用例 + 5 图 / 6 树证据（light）
cd ios && xcodebuild test \
  -only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction \
  -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -resultBundlePath /var/folders/.../opencode/vi-2/Light.xcresult

# 暗色：真实切换模拟器外观后重跑同一用例，取 run-running 附件
xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD appearance dark
# （同一条 xcodebuild test 命令，resultBundlePath .../vi-3/Dark.xcresult）
# run-running 附件 → docs/screenshots/run-running-dark.png
xcrun simctl ui B3F00298-E08A-41E0-876E-6E8A75C730FD appearance light

# 附件导出
xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>
# manifest.json 的 suggestedHumanReadableName 去掉 `_0_<uuid>` 后缀即目标文件名
```

## 4) 断言名与关键日志（含反例判红）

### 4.1 单测（`** TEST SUCCEEDED **`，`PurePaceTests` 125 tests / 0 failures）

```
ac-contrast light primary/background 15.76
ac-contrast light primary/surface 16.79
ac-contrast light secondary/background 5.67
ac-contrast light secondary/surface 6.04
ac-contrast light accent/background 5.70
ac-contrast light onAccent/accent 6.07
ac-contrast light accent/accentSoft 5.52
ac-contrast light warning/warningSoft 4.93
ac-contrast light success/successSoft 4.81
ac-contrast light danger/dangerSoft 5.66
ac-contrast dark primary/background 16.95
ac-contrast dark primary/surface 15.10
ac-contrast dark secondary/background 9.15
ac-contrast dark secondary/surface 8.15
ac-contrast dark accent/background 10.74
ac-contrast dark onAccent/accent 9.57
ac-contrast dark accent/accentSoft 6.99
ac-contrast dark warning/warningSoft 7.81
ac-contrast dark success/successSoft 7.78
ac-contrast dark danger/dangerSoft 6.86
ac-contrast light hero primary/background 15.76
ac-contrast dark hero primary/background 16.95
ac-contrast 反例 low #AAAAAA/#FFFFFF 2.32
```

反例：`testLowContrastPairIsRejected`（2.32 < 4.5 判红）、`testOutOfRangeComponentsFailClosed`（分量越界返回 `nil` + 「分量越界」问题）、`testMissingPairFailsClosed`（缺色对）、`testEmptyNameFailsClosed`（空对照名）。

### 4.2 L2 UI 用例（light，`** TEST SUCCEEDED **`）

```
ac-visible-copy-zh-hans 跑步页（未开始）: labels=18 violations=0
ac-primary-action-bottom-anchored 未开始: height=44.0 bottomGap=12.0
ac-run-metrics-balanced 未开始: top=128.33333333333334 bottom=128.33333333333326 largest=128.33333333333334 imbalance=8.526512829121202e-14
ac-visible-copy-zh-hans 历史空态: labels=8 violations=0
ac-visible-copy-zh-hans 跑步页（运行中）: labels=19 violations=0
ac-primary-action-bottom-anchored 运行中: height=44.0 bottomGap=12.0
ac-run-metrics-balanced 运行中: top=128.33333333333334 bottom=128.33333333333326 largest=128.33333333333334 imbalance=8.526512829121202e-14
ac-visible-copy-zh-hans 跑步页（保存态）: labels=19 violations=0
ac-primary-action-bottom-anchored 保存态: height=44.0 bottomGap=12.0
ac-run-metrics-balanced 保存态: top=108.33333333333334 bottom=108.33333333333337 largest=108.33333333333337 imbalance=2.842170943040401e-14
ac-visible-copy-zh-hans 历史列表: labels=10 violations=0
ac-run-detail-date-zh-hans started="2026年11月11日 03:21:20" ended="2026年11月11日 03:21:25"
ac-visible-copy-zh-hans 跑次详情: labels=22 violations=0
ac-visible-copy-zh-hans 设置页: labels=11 violations=0
```

暗色同一用例同样 `** TEST SUCCEEDED **`（`ac-run-metrics-balanced` 三态数值与 light 完全一致）。
详情导出按钮在首屏：`{{0.0, 524.7}, {393.0, 84.0}}, identifier: 'runDetail.export'`。

### 4.3 静态门（`bash scripts/check-ios-shell.sh` → `28 项断言，0 项失败`）

新增/扩展断言（均写在既有 `validate_design_tokens` 内，不新增 gate id）：

| 断言 | 判据 |
|---|---|
| 字面色值 | 四视图 + ContentView + `Design/**`（除 token 真源）命中 `Color(`/`Color.`/`UIColor`/`#colorLiteral`/`.foregroundStyle(.` 即失败 |
| 零散字体修饰符 | 同扫描面命中 `.font(.`/`.fontWeight(`/`.fontDesign(`/`.lineSpacing(<数字>` 即失败 |
| 暗色 | token 必须 `supportsDarkMode = true`，`light:` 与 `dark:` 计数一致且 ≥1 |
| 卡片面 | HistoryView 与 RunDetailView 必须引用 `Colors.surface` / `Radius.card` / `Colors.separator`，且不得 `.listStyle(.grouped/.insetGrouped)` |
| 四层 | RunView 必须含 `Typography.display` / `primaryValue` / `caption`、`Colors.accent`、`safeAreaInset(edge: .bottom)` |
| 三态 | `case .running: return DesignTokens.Colors.accent`、`case .paused: return DesignTokens.Colors.warning`、`if viewModel.didSave { return DesignTokens.Colors.success }` 三行缺任一即失败 |
| 等宽数字 | RunView ≥3 处 `.monospacedDigit()`，HistoryView / RunDetailView 各 ≥1 |
| identifier 冻结 | 提取 `accessibilityIdentifier("…")` 与 `identifier: "…"` 的 `run./runDetail./history./tab./settings.` 值，排序去重后必须与固定 33 项完全相等且总数相等 |

`--self-test`：`46 项断言，0 项失败 / self-test OK`（原 39 项 + 新增 7 类反例自检：字面色值、零散字体、暗色关闭、移除 surface、记录态改错为 warning、identifier 重命名、identifier 追加）。

反例实测判红（把同一函数跑在单点破坏的副本上，输出非空）：

```
### literal-color
 ios/PurePace/Settings/SettingsView.swift 含字面色值: 49:private let x = EmptyView().foregroundStyle(Color.red)
### scattered-font
 ios/PurePace/History/RunDetailView.swift 含零散字体修饰符: 184:private let y = EmptyView().fontWeight(.bold)
### dark-off
 深色模式必须开启（supportsDarkMode = true）
### no-surface
 ios/PurePace/History/HistoryView.swift 缺少卡片 token DesignTokens.Colors.surface
### wrong-running
 记录态未用 accent
### renamed-id
 可及 identifier 集合与冻结清单不一致（实际: … run.started …）
 ios/PurePace/Run/RunView.swift 缺少可及标识 run.start
### extra-id
 可及 identifier 数量必须为 33（实际 34: … run.extra …）
```

## 5) 可及 identifier 集合冻结（33 项）

`history.empty`、`history.row`、`history.runAgain`、`run.averagePace`、`run.backgroundDegraded`、`run.currentPace`、`run.distance`、`run.elapsed`、`run.finish`、`run.pause`、`run.resume`、`run.saved`、`run.splits`、`run.start`、`run.telemetry`、`run.viewHistory`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.distance`、`runDetail.endedAt`、`runDetail.export`、`runDetail.exportFailed`、`runDetail.exported`、`runDetail.root`、`runDetail.share`、`runDetail.splitRow`、`runDetail.splits`、`runDetail.splitsEmpty`、`runDetail.startedAt`、`settings.announcementToggle`、`tab.history`、`tab.run`、`tab.settings`。

6 棵可及树重采后 identifier 集合 diff：`01` 12/12、`02` 13/13、`03` 7/7、`04` 14/14、`05` 6/6、`06` 14/14，added=[]、removed=[]（全部为 0）。

## 6) diff 范围

```
ios/PurePace/Design/DesignTokens.swift        (重写：SRGB/ColorPair/palette/动态色/Appearance=true/Stroke)
ios/PurePace/Design/ContrastPolicy.swift      (新增)
ios/PurePace/Run/RunView.swift                (四层 + 三态视觉 + 等宽数字)
ios/PurePace/History/HistoryView.swift        (surface 卡片行 + 空态卡片)
ios/PurePace/History/RunDetailView.swift      (plain + 卡片节 + token 行)
ios/PurePace/Settings/SettingsView.swift      (token 化 + accent tint)
ios/PurePace/ContentView.swift                (TabView tint = accent，1 行)
ios/PurePaceTests/DesignTokensTests.swift     (暗色 true + 调色板完整性)
ios/PurePaceTests/ContrastPolicyTests.swift   (新增，7 例)
scripts/check-ios-shell.sh                    (validate_design_tokens 扩展 + 8 条反例自检)
docs/screenshots/*.png                        (5 张同名覆盖 + 新增 run-running-dark.png)
docs/evidence/a11y/01..06-*.txt               (重采，identifier 集合不变)
.munk/changes/wi_intake_a6d5c85453b8ceab/ux/design-baseline.md  (新增)
```

未触碰：`RunSessionViewModel` / `RunSessionOrchestrator` / `RunLocationSource` / 音频 / TTS / 持久化 / GPX / `project.yml` / 本地化键 / 路由 / CI / Android / `shared/` / `ios/Core` / `ios/RunCore`；`RunLayoutBalancePolicy`(160/40)、`PrimaryActionLayoutPolicy`(44/24)、`VisibleTextPolicy`、`VisibleDatePolicy` 策略文件零 diff；`.munk/baseline/**` 未改；`code-gates.json` 未改。

## 7) 对比度数值（light / dark，WCAG 2.x）

| 对照 | Light | Dark |
|---|---|---|
| primary/background | 15.76 | 16.95 |
| primary/surface | 16.79 | 15.10 |
| secondary/background | 5.67 | 9.15 |
| secondary/surface | 6.04 | 8.15 |
| accent/background | 5.70 | 10.74 |
| onAccent/accent | 6.07 | 9.57 |
| accent/accentSoft | 5.52 | 6.99 |
| warning/warningSoft | 4.93 | 7.81 |
| success/successSoft | 4.81 | 7.78 |
| danger/dangerSoft | 5.66 | 6.86 |

body 阈值 4.5:1、hero 大数字 3:1，全部达标。

## 8) pending

- 真机验收（锁屏后台定位、音频实听、定位授权弹窗观感）：`pending: 待人现场`。
- 深色以外的主题、动效专项、截图回归基线、Android 视觉对齐：非目标，未做。
