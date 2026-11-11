# Domain: ios-settings-visual

Settings 屏的视觉与分组层级重建子域：只改 `ios/PurePace/Settings/SettingsView.swift`，把系统 `Form`（grouped 观感）换成与 History / RunDetail 同源的 `List` + `.plain` + `.scrollContentBackground(.hidden)`，分组由显式 Section 标题 + token 化行容器（`surface` 行底 / `separator` hairline / `Radius.card`）建立；行内为「标题 + 一句说明」两行，组尾说明落在页面底色上而不借用系统组底。设置项数量、文案键、`accessibilityIdentifier` 集合与 `Toggle` 绑定行为零改动。令牌取值与三屏通用层级归 `ios-ui-design`，令牌静态门禁规则归 `design-token-gates`，History 屏视觉归 `ios-history-visual`。

## 范围

- `ios/PurePace/Settings/SettingsView.swift`：唯一实现面。`NavigationStack` → `List`（`.listStyle(.plain)` / `.scrollContentBackground(.hidden)` / `.background(Colors.background)`）→ 单个显式 `Section`（header 沿用 `settings.section.announcement`）；Section 内容为「播报行（`Toggle` + 标题 + 说明）」与「组尾只读说明行」两行。
- 行容器：行底 `Colors.surface` + `RoundedRectangle(cornerRadius: Radius.card)`，描边 `Colors.separator` + `Stroke.hairline`；行内外留白只取 `Spacing.xxs / xs / md`，最小高度只取 `minTapTarget`；`listRowSeparator(.hidden)` + `listRowBackground(Colors.background)` + `listRowInsets` 去掉系统分隔与系统组底。
- 唯一可交互控件是播报 `Toggle`（`$store.isEnabled`，`tint` = `Colors.accent`，identifier `settings.announcementToggle`）；根容器带 `tab.settings`。不新增按钮、导航目的地或第二类控件。
- 证据只落本子项 change pack：浅 / 深色模拟器截图与 `05-settings` 可及树入 `.munk/changes/<workItemId>/evidence/`，逐文件 sha256 入 digest；不写 `docs/screenshots/**`。
- 不新增源文件，因此 `ios/project.yml` 与 `PurePace.xcodeproj` 零 diff、无需重生成工程。

## 验收

- ac-single-interactive-control: `SettingsView.swift` 恰有 1 个 `Toggle`，且 0 个 `Button(` / `NavigationLink(` / `Stepper` / `Slider`；`scripts/check-ios-shell.sh` 的 `validate_settings_view` 退 0（要求 `Toggle` 与 `"settings.announcementToggle"` 同时存在）。
- ac-toggle-behavior-preserved: `Toggle` 仍绑定 `$store.isEnabled` 且 `accessibilityLabel` 仍取 `L10n.settingsAnnouncementTitle`；`AnnouncementSettingsStore.swift` 与其单测零改动，`scripts/test-ios.sh --unit-only` 中 `AnnouncementSettingsStoreTests` 全绿。
- ac-identifier-set-frozen: `check-ios-shell.sh` 的可及 identifier 冻结清单仍为 33 项、数量与逐项集合 diff = 0；Settings 侧仍只有 `settings.announcementToggle` 与 `tab.settings`。
- ac-no-system-grouped-look: 文件内 0 处 `Form`、0 处 `.listStyle(.grouped)` / `.listStyle(.insetGrouped)`；行背景引用 `DesignTokens.Colors.surface`、分隔引用 `DesignTokens.Colors.separator`，分组结构由显式 Section 标题 + token 化行容器建立。
- ac-row-hierarchy: 分组标题 `Typography.sectionHeader` + `Colors.secondary` + `.textCase(nil)`；行标题 `Typography.body` + `Colors.primary`；行说明与组尾说明 `Typography.caption` + `Colors.secondary`；Settings 内不引用 `metricLabel` / `metricUnit`；四个文案键 `settings.section.announcement` / `settings.announcement.title` / `settings.announcement.body` / `settings.footer.announcement` 逐字沿用。
- ac-styling-tokenized: 零字面色值（无 `Color(` / `Color.` / `UIColor` / `#colorLiteral` / `0x` 十六进制）、零零散字体修饰符、零动效字面量；零样式字面量（无 `spacing: <数字>` / `.padding(<数字>` / `minHeight: <数字>` / `.system(size: <数字>`）；零 `.shadow(`；圆角只取 `Radius.control` / `Radius.card`，最小高度只取 `minTapTarget`；由 `check-ios-shell.sh` 受管 UI 面扫描承载。
- ac-accent-selection-only: `DesignTokens.Colors.accent` 在 Settings 内只出现在 `Toggle` 的 tint 与 `NavigationStack` 的 `.tint` 上，不做文字色、行底或组底。
- ac-light-dark-isomorphic: 全部颜色引用语义色 token（light/dark 成对由 token 真源保证），无 `colorScheme` 分支；浅色与深色各一轮模拟器证据（截图 + `05-settings` 可及树）并记 sha256；模拟器 UI 腿跑不动时逐条写 `pending: 待人现场` 与实际原因，不自判达标。
- ac-ax5-no-truncation: 文件内 0 处 `lineLimit(`、0 处固定高度 `.frame(height:`；标题与说明可换行（`fixedSize(horizontal: false, vertical: true)` 或等价不截断写法）。事实口径：本仓字号阶梯为固定字号（不随 Dynamic Type 缩放），「AX5 不截断」的实现含义仅为「不引入截断机制且允许换行」，不得声称做过运行态 AX5 渲染实测。
- ac-gates-green: `scripts/check-ios-shell.sh`、`scripts/build-ios.sh`、`scripts/test-ios.sh --unit-only` 均退 0；`scripts/check-baseline.sh` 与 `.munk/code-gates.json` 的 22 门列表零改动。
- ac-scope-bounded: 代码 diff 只含 `ios/PurePace/Settings/SettingsView.swift`（若工程重生成，仅允许 `PurePace.xcodeproj/project.pbxproj` 并说明为生成产物）；`Design/**`、`L10n.swift`、`Localizable.xcstrings`、`ios/project.yml`、`scripts/**`、`.munk/code-gates.json`、`Run/**`、`History/**`、`RunCore`、Android、`shared/**`、`docs/screenshots/**` 零改动。

## 非目标

- 不新增设置项、分组、行、按钮或导航目的地；不改文案与本地化键；不改 identifier 集合；不改 `AnnouncementSettingsStore` 及其持久化契约。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`，不新增 token、不做配色微调、不新增组件库文件。
- 不改 `scripts/**`、`.munk/code-gates.json`、`.github/workflows/**`；不新增 gate id、不加扫描白名单。
- 不覆盖 `docs/screenshots/` 与其 `SHA256SUMS` / README 图集；证据收口属第 5 波。
- 不动 Run / History / RunDetail / ContentView 与状态机、定位、音频、GPX、Tab 路由；不引第三方依赖、自定义字体/图标资产或主题系统；不做 Reduce Motion 动画接线（本项无动画）。
- 不产真机结论、不做 ASC / ipa / TestFlight / tag / Release，真机类项一律 `pending: 待人现场`。

## 实现约束

- 唯一真源：`ios/project.yml`；不改文件清单，正常无需重生成工程，若必须生成则用 XcodeGen，禁止手写 `project.pbxproj`。
- 门禁硬约束（不可绕）：`validate_design_tokens` 按目录派生扫描 `Settings/**`，任何字面色值 / `Font.system(size:` / 动效字面量立刻判红；`validate_settings_view` 要求文件内同时出现 `Toggle` 与 `"settings.announcementToggle"`；identifier 集合按 33 项逐项等值比对。
- 可消费的既有 token（不自建常量）：`Typography.sectionHeader / body / caption / control`、`Colors.background / surface / surfaceMuted / primary / secondary / separator / accent`、`Spacing.xxs / xs / sm / md / lg`、`Radius.control / card`、`Stroke.hairline`、`minTapTarget`。
- UI 用例兼容：`RunFlowUITests` 以 `app.switches["settings.announcementToggle"]` 定位并比对重启后取值，必须保留 SwiftUI `Toggle` 本体（映射到 `UISwitch`），不能改自绘开关；`assertVisibleCopyZhHans` 逐条检查可见文案，不得引入裸英文。
- 系统 footer 槽位会给 footer cell 画整条 `systemBackground` 色带（与页面底色不同，即 PRD 要禁的「系统组底」），组尾说明必须放在同 Section 内的只读行并显式设 `listRowBackground(Colors.background)`。
- 证据只写 `.munk/changes/<workItemId>/evidence/` 并逐文件 sha256 入 digest；不得写 `docs/screenshots/`。
- 若门禁暴露既有违规，只允许把字面量等价替换为 token 引用并保持视觉等价，逐条记录；不得改规则精度或加白名单。

## 最近交付证明

- workItemId: wi_ws_a1f2df5be4d2f1dc（2026-11-11，pass）
- 交付：Settings 屏去 `Form`，改 `List` + `.plain` + `.scrollContentBackground(.hidden)`；单个显式 Section（header `sectionHeader` + `secondary` + `textCase(nil)`）；播报行 = `Toggle`（`accent` tint、`minTapTarget` 最小高、`Radius.card` + `hairline` 描边）+ `body`/`primary` 标题 + `caption`/`secondary` 说明；组尾说明改为同 Section 只读行（原 `Section footer:` 槽位会带 `systemBackground` 色带）。+64 / −22，仅一个源文件。
- 判定与断言：22 门全绿（`lint-ios-shell` 30 项断言 0 失败、`build-ios` BUILD SUCCEEDED、`test-ios --unit-only` 179 例 0 失败且 `AnnouncementSettingsStoreTests` 5 例通过、`check-baseline` 11 项 0 失败）；identifier 33 项不变，四个文案键逐字沿用。
- 证据与边界：浅 / 深色截图与 `05-settings` 可及树取 iPhone 17 / iOS 26.3.1（仓内钉住的 iPhone 16 / iOS 18.6 深色轮次连续 `Lost connection to the application`，换实例后稳定）；真机观感 `pending: 待人现场`；未做运行态 AX5 渲染实测，仅静态保证不截断。
