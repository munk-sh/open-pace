# Digest：Settings 分组与说明层级重建（wi_ws_a1f2df5be4d2f1dc）

- 开工时刻：2026-11-11 12:29（本地，接手时点）
- 本轮预算：≤90 分钟（含 build-ios、test-ios --unit-only、浅/深色模拟器截图各一轮 + 可及树导出一轮）
- 期望收口：2026-11-11 14:00；实际收口：2026-11-11 13:10

## 1) 改动面

`git diff --name-only`：

```
ios/PurePace/Settings/SettingsView.swift
```

唯一实现面 `ios/PurePace/Settings/SettingsView.swift`（+64 / −22）。`git status --short` 另见 `?? .munk/changes/wi_ws_a1f2df5be4d2f1dc/`（本子项证据目录，不进代码仓跟踪范围）。`ios/PurePace/Design/**`、`L10n.swift`、`Localizable.xcstrings`、`ios/project.yml`、`PurePace.xcodeproj`、`scripts/**`、`.munk/code-gates.json`、`Run/**`、`History/**`、`RunCore`、Android、`shared/**`、`docs/screenshots/**` 零改动；工程未重生成，`project.pbxproj` 零 diff。

## 2) 实现要点

- 去掉 `Form`，改 `List` + `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + `.background(Colors.background)`，与 History / RunDetail 同源。
- 分组结构 = 显式 `Section` header（`Typography.sectionHeader` + `Colors.secondary` + `.textCase(nil)`）。
- 行容器：`Toggle` 本体（`$store.isEnabled`，tint `Colors.accent`）+ 标题 `Typography.body`/`Colors.primary` + 说明 `Typography.caption`/`Colors.secondary`；行底 `Colors.surface` + `RoundedRectangle(cornerRadius: Radius.card)` + `stroke(Colors.separator, lineWidth: Stroke.hairline)`；行内边距与行外留白只取 `Spacing.xs/md/xxs`；`minHeight = minTapTarget`。
- 组尾说明 `settings.footer.announcement` 用 `Typography.caption` + `Colors.secondary`；实测首版把它放在 `Section footer:` 槽位时，系统给 footer cell 画了一整条 `systemBackground` 色带（浅色 `#FFFFFF`、深色 `#000000`，与页面底 `#F7F8F6` / `#0A1211` 明显不同），即 PRD 要禁的「系统组底」；因此改为同一 Section 内的一行只读文字，`listRowBackground(Colors.background)` + `listRowSeparator(.hidden)`，色带消失（见 §4 截图）。
- 零投影、零字面色值、零零散字体、零动效字面量；accent 仅 2 处（`Toggle` tint 与 `NavigationStack` 的 `.tint`）。

## 3) 门禁真实输出

| 门 | 命令 | 结果 |
|---|---|---|
| lint-ios-shell | `bash scripts/check-ios-shell.sh` | exit 0，`30 项断言，0 项失败` / `ios shell OK`（含 Settings `Toggle` + `"settings.announcementToggle"` 正例、受管 UI 面字面量扫描、identifier 33 项等值） |
| build-ios | `bash scripts/build-ios.sh` | exit 0，`** BUILD SUCCEEDED **`，产物 `.build/ios/Build/Products/Debug-iphonesimulator/PurePace.app` |
| test-ios | `bash scripts/test-ios.sh --unit-only` | exit 0，`Executed 179 tests, with 0 failures`；其中 `AnnouncementSettingsStoreTests` 5 个用例全 passed（`testBindingStyleWritesPersistToo` / `testDisabledStatePersistsAcrossInstances` / `testEnabledStatePersistsAcrossInstances` / `testFreshDomainDefaultsToEnabled` / `testOnlySingleConstantKeyIsWritten`） |
| test（基线） | `bash scripts/check-baseline.sh` | exit 0，`11 项断言，0 项失败`，`baseline OK (VERSION=0.1.0)` |

`.munk/code-gates.json` 22 门列表零改动。

## 4) 截图与可及树证据（本子项目录，未触碰 `docs/screenshots/`）

来源：`xcodebuild test-without-building -only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction`（既有 UI 用例，未改一行测试代码），`xcrun xcresulttool export attachments` 取的 XCTest attachment，非手绘。

| 文件 | 设备 / 运行时 / 外观 | 用例结果 |
|---|---|---|
| `evidence/settings-light.png` | iPhone 17 / iOS 26.3.1 / light | 1 test, 0 failures（58.6s） |
| `evidence/05-settings-light.txt` | 同上（`05-settings` 可及树） | 同上 |
| `evidence/settings-dark.png` | iPhone 17 / iOS 26.3.1 / dark | 1 test, 0 failures（57.2s） |
| `evidence/05-settings-dark.txt` | 同上（`05-settings` 可及树） | 同上 |

sha256：

```
262cda837a2aed73da84ad2ff34b3ef0aaa26d52a8a7d1458598f365f6ada220  evidence/settings-light.png
6804ae8497ebe14010cd1046c8b23f40a7035fea82df3633eaa0b49f24890480  evidence/05-settings-light.txt
cf96bbed06b2ff053986ebf8c0edb839f4404cbf240456339247aba74356dd67  evidence/settings-dark.png
947f38a8d83ff8d472959711b2e00bfe232e983a7a32bb5d5944ef39065570c5  evidence/05-settings-dark.txt
```

可及树事实（浅/深两棵一致）：`tab.settings` 容器 → NavigationBar`设置`；Section header `播报`；`Switch` `identifier: 'settings.announcementToggle'`、`label: '每公里语音播报'`、`value: 1`，其下标题 `每公里语音播报` 与说明 `每跑满一公里时朗读当前配速与累计时长。`；组尾 `关闭后跑步过程中的语音播报会立即停止。`；TabBar 三个按钮 `跑步 / 历史 / 设置(Selected)`。树内 `identifier:` 仍只有 `tab.settings` / `settings.announcementToggle` / `gearshape.fill`（系统符号）。

设备口径说明（如实记录）：先在本仓钉住的 iPhone 16 / iOS 18.6 上跑同一用例，浅色一轮通过（12:42）；随后切 `simctl ui ... appearance dark` 连续 3 轮出现承载层失败——`Failed to get matching snapshot: Lost connection to the application` 与 `Test crashed with signal kill before establishing connection`（日志 `/tmp/pp-dark-3.log`、`/tmp/pp-dark-5.log`），`simctl erase` 后仍复现，属该模拟器实例的 UI 腿不稳；改用同机 iPhone 17 / iOS 26.3.1 后浅色与深色各一轮均通过，故最终证据全部来自 iPhone 17 / iOS 26.3.1。真机观感类结论不下（`pending: 待人现场`）。

## 5) 逐条 AC 自查（源码/门禁证据）

| AC | 证据 |
|---|---|
| ac-single-interactive-control | `grep -c "Toggle(" = 1`；`Button(` / `NavigationLink(` / `Stepper` / `Slider` = 0；`check-ios-shell.sh` 退 0（`validate_settings_view` 正例在位） |
| ac-toggle-behavior-preserved | `Toggle(isOn: $store.isEnabled)` + `.accessibilityLabel(Text(L10n.settingsAnnouncementTitle))` 原样保留；`AnnouncementSettingsStore.swift` 与其单测零改动；单测腿 179/0 失败，该类 5 用例全通过 |
| ac-identifier-set-frozen | `check-ios-shell.sh` identifier 段（33 项逐项等值 + 总数）退 0；本文件只有 `settings.announcementToggle` 与 `tab.settings` |
| ac-no-system-grouped-look | `grep -c "Form" = 0`；`listStyle(.grouped)` / `.insetGrouped` = 0；`DesignTokens.Colors.surface` 1 处、`DesignTokens.Colors.separator` 1 处（行底 + hairline 描边）；Section footer 的系统色带已按 §2 移除，浅/深截图均无系统组底与系统分隔 |
| ac-row-hierarchy | 见 §2/§5 源码行：sectionHeader+secondary+`textCase(nil)`（L17-L20）、body+primary（L36-L38）、caption+secondary（L40-L43、L74-L76）；`metricLabel` / `metricUnit` 引用 0 处；四个文案键 `settings.section.announcement` / `settings.announcement.title` / `settings.announcement.body` / `settings.footer.announcement` 逐字沿用 |
| ac-styling-tokenized | `check-ios-shell.sh` 受管 UI 面扫描（字面色值 / 零散字体 / 动效字面量）退 0；样式字面量扫描（`spacing: 数字` / `.padding(数字` / `minHeight: 数字` / `.system(size: 数字`）退 0；`grep -c ".shadow(" = 0`；圆角仅 `Radius.card`；最小高度仅 `minTapTarget` |
| ac-accent-selection-only | `grep -n "DesignTokens.Colors.accent"` = L28（NavigationStack `.tint`）、L47（Toggle tint）两处，无 accent 文字色 / 行底 / 组底 |
| ac-light-dark-isomorphic | 颜色全为语义 token（`background` / `surface` / `primary` / `secondary` / `separator` / `accent`），无 `colorScheme` 分支；浅/深各一轮真实截图 + `05-settings` 可及树已入 `evidence/` 并记 sha256（设备口径见 §4） |
| ac-ax5-no-truncation | `grep -c "lineLimit(" = 0`、`grep -c ".frame(height:" = 0`，三处 `fixedSize(horizontal: false, vertical: true)` 允许标题与说明换行。事实口径：本仓字号阶梯为固定字号（不随 Dynamic Type 缩放），本项的实现含义仅是「不引入任何截断机制且允许换行」，**未做运行态 AX5 渲染实测**，也不声称做过 |
| ac-gates-green | 见 §3 四条退出码 0 的真实输出；`.munk/code-gates.json` 22 门零改动 |
| ac-scope-bounded | 见 §1 |

源码 grep 留证（最终文件）：

```
$ grep -c "Form" ios/PurePace/Settings/SettingsView.swift            → 0
$ grep -c "listStyle(.grouped)\|listStyle(.insetGrouped)" ...        → 0
$ grep -c "lineLimit(" ...                                          → 0
$ grep -c "\.frame(height:" ...                                     → 0
$ grep -c "\.shadow(" ...                                           → 0
$ grep -c "metricLabel\|metricUnit" ...                             → 0
$ grep -c "Button(\|NavigationLink(\|Stepper\|Slider" ...            → 0
```

## 6) 偏离 / 有意未做

- 组尾说明从 `Section footer:` 槽位改为同组只读行（原因见 §2：footer 槽位会带系统 `systemBackground` 色带，违反「不留系统组底」）；文案键、字号角色、可见文字零变化。
- 单行分组下没有「行间」分隔线，hairline 以行容器描边形式呈现（`stroke(separator, lineWidth: hairline)`），不引入第二条假行。
- 证据来自 iPhone 17 / iOS 26.3.1（而非仓内钉住的 iPhone 16 / iOS 18.6），原因与失败现象见 §4；真机项一律 `pending: 待人现场`。
- 未改 `docs/screenshots/`、未更新 `docs/verification-matrix.md`（证据收口属第 5 波）。
