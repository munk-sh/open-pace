# Settings 分组与说明层级重建

第 3 波核心屏之一，只做 Settings 一屏的视觉与分组重建。现状 `ios/PurePace/Settings/SettingsView.swift` 用 `Form`（系统 grouped 观感）承载唯一的每公里语音播报开关；本项把它换成 token 化行背景 + hairline 分隔的分组结构，保持设置项数量、文案键、identifier 与开关行为完全不变。

## 范围

- 唯一实现面：`ios/PurePace/Settings/SettingsView.swift`。
- 分组结构：带分组标题的 Section（沿用 `settings.section.announcement`），行内为「标题 + 一句说明」两行，组尾说明沿用 `settings.footer.announcement`；分组标题、行背景、分隔、留白、圆角全部引用既有 `DesignTokens`。
- 去掉系统默认 grouped 观感：不再用 `Form`，改为与 History / RunDetail 同源的 `List` + `.plain` + `.scrollContentBackground(.hidden)`（或等价 token 化容器），行背景 `Colors.surface`，行间用 `Colors.separator` hairline 分隔，不留系统分隔/系统组底。
- 唯一可交互控件仍是播报 `Toggle`（`settings.announcementToggle`，绑定 `store.isEnabled`，tint 用 `accent`），不新增按钮、导航目的地或第二类控件。
- 证据只落本子项 digest：浅色与深色模拟器截图/可及树导到 `.munk/changes/wi_ws_a1f2df5be4d2f1dc/evidence/`，逐文件 sha256 入 digest。

## 验收

- ac-single-interactive-control: `SettingsView.swift` 恰有 1 个 `Toggle`，且 0 个 `Button(` / `NavigationLink(` / `Stepper` / `Slider`；`bash scripts/check-ios-shell.sh` 的 `validate_settings_view` 退 0（要求 `Toggle` 与 `"settings.announcementToggle"` 同时存在）。
- ac-toggle-behavior-preserved: `Toggle` 仍绑定 `$store.isEnabled` 且 `accessibilityLabel` 仍取 `L10n.settingsAnnouncementTitle`；`AnnouncementSettingsStore.swift` 与其单测零改动，`scripts/test-ios.sh --unit-only` 中 `AnnouncementSettingsStoreTests` 全绿（开关持久化行为不变）。
- ac-identifier-set-frozen: `check-ios-shell.sh` 的可及 identifier 冻结清单仍为 33 项、数量与逐项集合 diff = 0；本项不新增、不改名、不删除任何 `accessibilityIdentifier`（Settings 侧仍只有 `settings.announcementToggle` 与 `tab.settings`）。
- ac-no-system-grouped-look: 文件内 0 处 `Form`、0 处 `.listStyle(.grouped)` / `.listStyle(.insetGrouped)`；行背景引用 `DesignTokens.Colors.surface`、分隔引用 `DesignTokens.Colors.separator`，分组结构由显式 Section 标题 + token 化行容器建立（源码 grep 证据入 digest）。
- ac-row-hierarchy: 分组标题用 `Typography.sectionHeader` + `Colors.secondary` + `textCase(nil)`；行标题用 `Typography.body` + `Colors.primary`；行说明用 `Typography.caption` + `Colors.secondary`；Settings 内不出现小于 `caption` 的字号角色（不引用 `metricLabel` / `metricUnit`）；四个既有文案键 `settings.section.announcement` / `settings.announcement.title` / `settings.announcement.body` / `settings.footer.announcement` 逐字沿用。
- ac-styling-tokenized: 零字面色值（无 `Color(` / `Color.` / `UIColor` / `#colorLiteral` / `0x` 十六进制）、零零散字体修饰符、零动效字面量；零样式字面量（无 `spacing: <数字>`、`.padding(<数字>`、`minHeight: <数字>`、`.system(size: <数字>`）；零 `.shadow(`；圆角只取 `Radius.control` / `Radius.card`，最小高度只取 `minTapTarget`。上述每条由 `check-ios-shell.sh` 的受管 UI 面扫描退 0 承载。
- ac-accent-selection-only: `DesignTokens.Colors.accent` 在 Settings 内只出现在 `Toggle` 的 tint 与 NavigationStack `.tint` 上；不以 accent 做文字色、行底或组底（grep 证据入 digest）。
- ac-light-dark-isomorphic: Settings 内全部颜色引用语义色 token（light/dark 成对由 token 真源保证），无 `colorScheme` 分支或仅浅色写死的值；浅色与深色各一轮模拟器证据（截图 + `05-settings` 可及树）导到 `.munk/changes/wi_ws_a1f2df5be4d2f1dc/evidence/` 并逐文件 sha256 入 digest；若模拟器 UI 腿本轮跑不动，digest 必须逐条写 `pending: 待人现场` 与实际原因，不得自判达标。
- ac-ax5-no-truncation: 文件内 0 处 `lineLimit(`、0 处固定高度 `.frame(height:`；行标题与说明可换行（`fixedSize(horizontal: false, vertical: true)` 或等价不截断写法）。事实口径：本仓字号阶梯为固定字号（不随 Dynamic Type 缩放），所以「AX5 不截断」在本项的实现含义是「不引入任何截断机制且允许换行」，digest 必须写明这一点，不得声称做过运行态 AX5 渲染实测。
- ac-gates-green: `bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh --unit-only` 均退 0（真实输出与用例数入 digest）；`bash scripts/check-baseline.sh` 与 `.munk/code-gates.json` 的 22 门列表零改动。
- ac-scope-bounded: `git diff --name-only` 只含 `ios/PurePace/Settings/SettingsView.swift`（若 XcodeGen 产物因工程重生成而变化，仅允许 `ios/PurePace.xcodeproj/project.pbxproj` 且须说明为生成产物）；`ios/PurePace/Design/**`、`L10n.swift`、`Localizable.xcstrings`、`ios/project.yml`、`scripts/**`、`.munk/code-gates.json`、`Run/**`、`History/**`、`RunCore`、Android、`shared/**`、`docs/screenshots/**` 零改动。

## 非目标

- 不新增设置项、分组、行、按钮或导航目的地；不改任何文案与本地化键；不改 identifier 集合；不改 `AnnouncementSettingsStore` 及其持久化契约。
- 不改 `DesignTokens.swift` / `ContrastPolicy.swift`，不新增 token、不做配色微调、不新增组件库文件。
- 不改 `scripts/**`、`.munk/code-gates.json`、`.github/workflows/**`；不新增 gate id、不加扫描白名单。
- 不覆盖 `docs/screenshots/` 与其 `SHA256SUMS` / README 图集，不更新 `docs/verification-matrix.md`（证据收口属第 5 波）。
- 不动 Run / History / RunDetail / ContentView 与状态机、定位、音频、GPX、Tab 路由。
- 不引第三方依赖、自定义字体/图标资产或主题系统；不做 Reduce Motion 动画接线（本项无动画）。
- 不产真机结论、不做 ASC / ipa / TestFlight / tag / Release，真机类项一律 `pending: 待人现场`。

## 实现约束

- 动手前先读 `.agents/skills/swiftui-pro`（仓库 AGENTS.md 指定的 iOS 规范 skill）；只改 SwiftUI 视图层。
- 唯一真源：`ios/project.yml`；不改文件清单，正常情况下无需重生成工程，若必须生成则用 XcodeGen 产出，禁止手写 `project.pbxproj`。
- 门禁硬约束（不可绕）：`validate_design_tokens` 按目录派生扫描 `Settings/**`，任何字面色值 / `Font.system(size:` / 动效字面量立刻判红；`validate_settings_view` 要求文件内同时出现 `Toggle` 与 `"settings.announcementToggle"`；identifier 集合按 33 项逐项等值比对，多写一个也判红。
- 可直接消费的既有 token（不要自建常量）：`Typography.sectionHeader / body / caption / control`、`Colors.background / surface / surfaceMuted / primary / secondary / separator / accent`、`Spacing.xxs / xs / sm / md / lg`、`Radius.control / card`、`Stroke.hairline`、`minTapTarget`。
- UI 用例兼容：既有 `RunFlowUITests` 以 `app.switches["settings.announcementToggle"]` 定位并比对重启后取值，因此必须保留 SwiftUI `Toggle` 本体（映射到 UISwitch），不能改成自绘开关；`assertVisibleCopyZhHans` 会逐条检查可见文案，不得引入裸英文。
- 预算与收口时刻：Coding 开工先在 digest 顶部写本轮预算与期望收口时刻（建议 ≤90 分钟，覆盖 `build-ios` + `test-ios --unit-only` + 浅深色截图各一轮），超预算即停手回执，不靠长会话补绿。
- 截图与可及树证据只写 `.munk/changes/wi_ws_a1f2df5be4d2f1dc/evidence/`，逐文件 sha256 入 digest；不得写 `docs/screenshots/`。
- 若门禁暴露本文件里既有的违规，只允许把字面量等价替换为 token 引用并保持视觉等价，逐条记录；不得改规则精度或加白名单。
