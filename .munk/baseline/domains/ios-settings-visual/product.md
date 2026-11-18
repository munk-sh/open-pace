# Domain: ios-settings-visual

Settings 屏的视觉与分组层级重建子域：只改 `ios/PurePace/Settings/SettingsView.swift`，把系统 `Form`（grouped 观感）换成与 History / RunDetail 同源的 `List` + `.plain` + `.scrollContentBackground(.hidden)`，分组由显式 Section 标题 + token 化行容器（`surface` 行底 / `separator` hairline / `Radius.card`）建立；行内为「标题 + 一句说明」两行，组尾说明落在页面底色上而不借用系统组底。分组固定「播报 / 高级 / 关于」三段：诊断区收进「高级」`DisclosureGroup` 且默认折叠（折叠态不占首屏高度，AX5 零越界），展开后可复制导出。identifier 只增不改，`Toggle` 绑定行为不变。令牌取值与三屏通用层级归 `ios-ui-design`，令牌静态门禁规则归 `design-token-gates`，History 屏视觉归 `ios-history-visual`。

## 范围

- `ios/PurePace/Settings/SettingsView.swift`：唯一实现面。`NavigationStack` → `List`（`.listStyle(.plain)` / `.listSectionSpacing(Spacing.sectionGap)` / `.scrollContentBackground(.hidden)` / `.background(Colors.background)`）→ 三个显式 `Section`：播报（`Toggle` + 标题 + 说明，加组尾只读说明）、高级（折叠行 + 组尾说明）、关于（政策全文入口，已同意时追加同意状态行与撤回行）。
- 「高级」组 = `DisclosureGroup(isExpanded: $isAdvancedExpanded)`，`@State isAdvancedExpanded = false` 默认折叠；label 为 `settings.section.diagnostics` 文案（`body` / `primary` / `minTapTarget`，identifier `settings.advanced`），折叠层内容为诊断卡（快照文本 `settings.diagnostics` + 复制按钮 `settings.diagnostics.copy`，写 `UIPasteboard` 后切 `settings.diagnostics.copied` 文案）。
- 行容器：行底 `Colors.surface` + `RoundedRectangle(cornerRadius: Radius.card)`，描边 `Colors.separator` + `Stroke.hairline`；卡片内边距 `Spacing.md` 16（= `cardPadding`），行内外留白只取 `Spacing.xxs / xs / md`，最小高度只取 `minTapTarget`；`listRowSeparator(.hidden)` + `listRowBackground(Colors.background)` + `listRowInsets` 去掉系统分隔与系统组底。
- 交互控件集合：播报 `Toggle`（`$store.isEnabled`，`tint` = `Colors.accent`，`settings.announcementToggle`）、「高级」折叠行、诊断复制按钮、关于组政策入口（`settings.privacyPolicy`）与撤回按钮（`settings.consentRevoke`）、工具栏回起跑（`settings.rerun`）；根容器带 `tab.settings`。不新增设置项类型或导航目的地。
- 证据只落 `docs/evidence/<workItemId>/`：浅 / 深色 iPhone 16 / iOS 18.6 模拟器截图 + `SHA256SUMS` + 运行日志，同 commit 绑定；不写 `docs/screenshots/**`。
- 不新增源文件，因此 `ios/project.yml` 与 `PurePace.xcodeproj` 零 diff、无需重生成工程。

## 验收

- ac-advanced-group-collapsed: 诊断区在「高级」组内，由 `DisclosureGroup(isExpanded:)` 承载且 `@State isAdvancedExpanded = false` 默认折叠；折叠态不渲染诊断卡与复制按钮，展开后 `settings.diagnostics` 文本与 `settings.diagnostics.copy` 可用（点击写剪贴板并切已复制文案）；组标题 `settings.section.advanced` 与组尾说明 `settings.footer.advanced` 齐全。默认值改 `true`、或把诊断卡移到折叠层之外必须判红。
- ac-ax5-zero: 06-settings 在 AX5（`simctl ui <udid> content_size accessibility-extra-extra-extra-large`）下 `assertFitsAndNoOverlap` 越界 0、重叠 0；同一断言与 `window±1` 阈值零放宽。改前基线（诊断卡与同意行同屏）实测 `outOfBounds=2`、底边 860.67 > 852（越界 8.67pt）判红原文必须留档，改后同一断言绿。
- ac-spacing-floor: 三组走 `.listSectionSpacing(DesignTokens.Spacing.sectionGap)`（= `lg` 24），卡片内边距 `Spacing.md` 16，相邻卡片留白只取 `Spacing.xs`；分组间距 ≥24 / 卡片间距 ≥16 / 卡片内边距 ≥16，判据与反例由 `DesignTokens.ScreenSpacingPolicy.problems` 承载（12/12/12 同输入三项全红）。
- ac-single-toggle-contract: `SettingsView.swift` 恰 1 个 `Toggle`，0 个 `Stepper` / `Slider`；`scripts/check-ios-shell.sh` 的 `validate_settings_view` 退 0（要求 `Toggle` 与 `"settings.announcementToggle"` 同时存在）。
- ac-toggle-behavior-preserved: `Toggle` 仍绑定 `$store.isEnabled` 且 `accessibilityLabel` 仍取 `L10n.settingsAnnouncementTitle`；`AnnouncementSettingsStore.swift` 与其单测零改动，`scripts/test-ios.sh --unit-only` 中 `AnnouncementSettingsStoreTests` 全绿。
- ac-identifier-append-only: 冻结 33 项 identifier 逐项存在、只增不改；当前去重计数 63（本轮新增 `settings.advanced`），新增项非空 + 全局唯一 + 带非空可读 label；`--self-test` 的计数断言随真实源码同步（63 / 递增 64）。改名或删除任一冻结项必须判红。
- ac-no-system-grouped-look: 文件内 0 处 `Form`、0 处 `.listStyle(.grouped)` / `.listStyle(.insetGrouped)`；行背景引用 `DesignTokens.Colors.surface`、分隔引用 `DesignTokens.Colors.separator`，分组结构由显式 Section 标题 + token 化行容器建立。
- ac-row-hierarchy: 分组标题 `Typography.sectionHeader` + `Colors.secondary` + `.textCase(nil)`；行标题 `Typography.body` + `Colors.primary`；行说明与组尾说明 `Typography.caption` + `Colors.secondary`；Settings 内不引用 `metricLabel` / `metricUnit`；既有 `settings.*` 文案键逐字沿用，本轮只增 `settings.section.advanced` / `settings.footer.advanced`（`Localizable.xcstrings` 与 `L10n.swift` 同步）。
- ac-styling-tokenized: 零字面色值（无 `Color(` / `Color.` / `UIColor` / `#colorLiteral` / `0x` 十六进制）、零零散字体修饰符、零动效字面量；零样式字面量（无 `spacing: <数字>` / `.padding(<数字>` / `minHeight: <数字>` / `.system(size: <数字>`）；零 `.shadow(`；圆角只取 `Radius.control` / `Radius.card`，最小高度只取 `minTapTarget`；由 `check-ios-shell.sh` 受管 UI 面扫描承载。
- ac-accent-selection-only: `DesignTokens.Colors.accent` 在 Settings 内只作播报 `Toggle` 的 tint；`NavigationStack` 的 `.tint` 取 `Colors.primary`；不做文字色、行底或组底。
- ac-light-dark-isomorphic: 全部颜色引用语义色 token（light/dark 成对由 token 真源保证），无 `colorScheme` 分支；浅色与深色各一轮 iPhone 16 / iOS 18.6 模拟器截图证据并记 sha256；模拟器 UI 腿跑不动时逐条写 `pending: 待人现场` 与实际原因，不自判达标。
- ac-ax5-no-truncation: 文件内 0 处 `lineLimit(`、0 处固定高度 `.frame(height:`；标题与说明可换行（`fixedSize(horizontal: false, vertical: true)` 或等价不截断写法）。事实口径：本仓字号阶梯为固定字号（不随 Dynamic Type 缩放），AX5 结论只来自本仓越界/重叠断言（见 `ac-ax5-zero`），不得据此声称做过 Dynamic Type 缩放实测。
- ac-gates-green: `scripts/check-ios-shell.sh`（含 `--self-test`）、`scripts/build-ios.sh`、`scripts/test-ios.sh --unit-only`、`scripts/test-ios.sh` 均退 0；`scripts/check-baseline.sh` 与 `.munk/code-gates.json` 的 23 门列表零改动（不新增 gate id）。
- ac-scope-bounded: 代码 diff 只含 `ios/PurePace/Settings/SettingsView.swift` + 配套 `Design/DesignTokens.swift`（`sectionGap` 语义值与 `ScreenSpacingPolicy`）、`Design/L10n.swift`、`Resources/Localizable.xcstrings`、`PurePaceTests/**`、`scripts/check-ios-shell.sh` 的计数与 token 期望同步；`ios/project.yml`、`.munk/code-gates.json`、`Run/**`、`RunCore`、Android、`shared/**`、`docs/screenshots/**` 零改动。

## 非目标

- 不新增设置项类型或导航目的地；不改 `AnnouncementSettingsStore` 及其持久化契约；不改隐私同意存储语义。
- 不改语义色 hex 与 18 键 × 浅深 36 槽位（只允许语义间距 token `sectionGap` 由 `sm` 12 调到 `lg` 24，档位集合不变）。
- 不改 `.github/workflows/**`、不新增 gate id、不加扫描白名单。
- 不覆盖 `docs/screenshots/` 与其 `SHA256SUMS` / README 图集；证据收口属第 5 波。
- 不动 Run / History / RunDetail / ContentView 与状态机、定位、音频、GPX、Tab 路由；不引第三方依赖、自定义字体/图标资产或主题系统；不做 Reduce Motion 动画接线（本项无动画）。
- 不产真机结论、不做 ASC / ipa / TestFlight / tag / Release，真机类项一律 `pending: 待人现场`。

## 实现约束

- 唯一真源：`ios/project.yml`；不改文件清单，正常无需重生成工程，若必须生成则用 XcodeGen，禁止手写 `project.pbxproj`。
- 门禁硬约束（不可绕）：`validate_design_tokens` 按目录派生扫描 `Settings/**`，任何字面色值 / `Font.system(size:` / 动效字面量立刻判红；`validate_settings_view` 要求文件内同时出现 `Toggle` 与 `"settings.announcementToggle"`；identifier 冻结 33 项逐项存在 + 只增不改（当前 63），`--self-test` 的计数期望必须随真实源码同步。
- 可消费的既有 token（不自建常量）：`Typography.sectionHeader / body / caption / control`、`Colors.background / surface / surfaceMuted / primary / secondary / separator / accent`、`Spacing.xxs / xs / sm / md / lg`、`Radius.control / card`、`Stroke.hairline`、`minTapTarget`。
- UI 用例兼容：`RunFlowUITests` 以 `app.switches["settings.announcementToggle"]` 定位并比对重启后取值，必须保留 SwiftUI `Toggle` 本体（映射到 `UISwitch`），不能改自绘开关；`assertVisibleCopyZhHans` 逐条检查可见文案，不得引入裸英文。
- 系统 footer 槽位会给 footer cell 画整条 `systemBackground` 色带（与页面底色不同，即 PRD 要禁的「系统组底」），组尾说明必须放在同 Section 内的只读行并显式设 `listRowBackground(Colors.background)`。
- 证据只写 `docs/evidence/<workItemId>/`（截图 + 日志 + `SHA256SUMS`）并逐文件 sha256 入库；不得写 `docs/screenshots/`。
- 若门禁暴露既有违规，只允许把字面量等价替换为 token 引用并保持视觉等价，逐条记录；不得改规则精度或加白名单。
- AX5 首屏约束：诊断区默认折叠是首屏零越界的实现手段——折叠态不渲染诊断卡；不得以压字号、删组标题或说明、缩减 consent 行来回退到「靠内容变少塞进首屏」。

## 最近交付证明

- workItemId: wi_intake_666b18afcb30a3fc（2026-11-19，pass）
- 交付：诊断区收进新的「高级」`Section`（`DisclosureGroup` + `@State isAdvancedExpanded = false` 默认折叠，label `settings.advanced`，展开后诊断快照 + 复制按钮），组尾说明改 `settings.footer.advanced` 只读行；三组统一 `.listSectionSpacing(Spacing.sectionGap)`（`sectionGap` 由 `sm` 12 → `lg` 24）；06-settings AX5 越界 `outOfBounds=2`（8.67pt）→ 0 / 重叠 0，同一断言与阈值零放宽；identifier 63（新增 `settings.advanced`）。
- 判定与证据：`DesignTokensTests` 33 例 0 失败（含 `ScreenSpacingPolicy` 正反例）、`check-ios-shell --self-test` 102 项 0 失败、`code_gates` 23 门 attempt 001 全绿；截图 + AX5 改前/改后原文 + `SHA256SUMS` 全部同 commit 落 `docs/evidence/wi_intake_666b18afcb30a3fc/`。
- 偏离与边界：未跑 CI 全量 UI 腿（只跑本项三屏截图 / AX5 腿与单测）；真机观感 `pending: 待人现场`；字号阶梯仍为固定字号（不随 Dynamic Type 缩放），AX5 结论仅限本仓口径的越界/重叠断言。
