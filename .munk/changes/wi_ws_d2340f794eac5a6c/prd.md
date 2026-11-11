# 设计令牌真源：动效与字号角色补齐 + 对比度契约

WorkSet 第 2 波第一子项（`token-core`）。唯一输入是前任子项 `wi_ws_29e408731605ee3a` 已交付的 `docs/design/competitor-teardown.md`「映射到本产品」表（L253–L274）与「字号层级」「动效节奏」两节结论。本子项只把 `ios/PurePace/Design/DesignTokens.swift` + `ContrastPolicy.swift` 补齐为全应用可被门禁消费的唯一真源，**不动任何视图、交互、文案、可及性标识与状态机，不在本子项接动画**。

## 范围

1. **色彩**：保持 `DesignTokens.Colors.palette` 现有 18 个语义键、键名与 light/dark 成对结构不变；为每对补一份机器可读、非空的「语义用途」注册表，与该 palette 同源（键集必须完全相等）。
2. **对比度**：把现在散落在单测里的 10 条临时对照，升级为 Design 层单点声明的「成对矩阵 + 阈值分档」，覆盖全部 18 个语义键、每个键至少参与一对，light 与 dark 两侧逐对判定；`ContrastPolicy` 提供从矩阵解析出 `Check` 的纯函数，缺键/空名/分量越界/低于阈值一律 fail-closed 并给出可读原因。
3. **字号**：按拆解结论补 `Typography` 的指标三行角色 `metricLabel 11` / `metricUnit 11`（mapping 表 L262 的两个「拟新增」），保持既有 `caption 12 → body 15 → title 20 → primaryValue 34 → display 56` 不变；字号阶梯 `Typography.sizes` 扩展为严格递增的 6 档；另声明一份按字号非递减排列的角色阶梯与「数值角色」元数据（`primaryValue` / `display` 需等宽数字），供第 3 波视图直接引用。
4. **间距**：沿用 `4/8/12/16/24/32` 六档，补齐映射表隐含的语义项（指标组内、指标组之间、卡片内边距），取值只能落在既有档位；`screenTop / cardGap / sectionGap` 取值不变，`Spacing.scale` 仍为严格递增 6 档。
5. **动效**：新增 `Motion` 分组：`durationShort 0.2s`（数值/色块原地过渡）与 `durationState 0.32s`（记录态切换），来自拆解结论「动效节奏」L243、mapping 表 L272；再加 `reducedMotionDuration = 0` 与纯函数降级解析（`reduceMotion == true` 一律返回 0），作为 Reduce Motion 降级策略的唯一常量来源。
6. **单测**：`ios/PurePaceTests/DesignTokensTests.swift` 与 `ios/PurePaceTests/ContrastPolicyTests.swift` 扩展/对齐上述不变量，全部断言必须是可执行的反例可判红（真实调用并断言判红，不得只在注释里声称）。

### 复用的既有文件锚点（不新建同类文件）

- `ios/PurePace/Design/DesignTokens.swift`：`SRGB` / `ColorPair` / `Colors.palette`+18 个静态色 / `Typography` / `Spacing` / `Radius` / `Stroke` / `Icon` / `Appearance` / `minTapTarget`。
- `ios/PurePace/Design/ContrastPolicy.swift`：`bodyThreshold 4.5` / `largeThreshold 3.0` / `Check` / `ratio` / `problems` / `ratios` / `formatted`。
- 既有断言落点：`ios/PurePaceTests/DesignTokensTests.swift`、`ios/PurePaceTests/ContrastPolicyTests.swift`；由既有门 `test-ios`（`bash scripts/test-ios.sh --unit-only`）与 `lint-ios-shell` 承载，不需要新 gate。

## 验收

- ac-token-single-source: 全仓仍只有一处 `enum DesignTokens`，新增内容全部落在既有 `ios/PurePace/Design/DesignTokens.swift` 与 `ios/PurePace/Design/ContrastPolicy.swift` 两个文件内；不新建 DesignSystem / 组件库 / 令牌分片文件；`lint-ios-shell` 的 `validate_design_tokens` 对三屏零字面色值、零散字体修饰符的正例断言仍为绿。
- ac-color-purpose-registry: 18 个语义色键名与数量不变，且每个键在机器可读的用途注册表中有非空、去空白后非空、且不等于键名本身的语义用途；单测断言「注册表键集 == palette 键集」，把某个用途改成空串、只复读键名或从注册表删掉一个键都必须判红；每对 light/dark 仍不相等且分量在 `0...1` 内。
- ac-contrast-matrix-exhaustive: 前景/背景成对矩阵只在 Design 层单点声明（不得在单测里另抄一份），且只以 palette 键引用颜色、不重复写十六进制；矩阵至少覆盖：正文/小字 4.5 档（`primary`/`secondary` 对 `background`/`surface`/`surfaceMuted` 及四种 `*Soft`；`accent`/`warning`/`success`/`danger` 对 `background`/`surface` 及各自 `*Soft`；四个 `on*` 对其底色）、非文本 UI 边界 3.0 档（`accent` 对 `background`/`surface`/`surfaceMuted`）、装饰分隔 1.10 档（`separator` 对 `background`/`surface`/`surfaceMuted`），合计 ≥36 对且 18 个键每个至少出现一次；单测在 light 与 dark 两侧都对整张矩阵求解并断言 `problems == []`，逐对打印 `ac-contrast <scheme> <name> <ratio>`。
- ac-contrast-fail-closed-red: 缺键（矩阵引用了 palette 里不存在的键，解析结果为 `nil`）、空对照名、分量越界、低于阈值四类输入在单测里被真实执行，并各自断言判红且原因串分别含「缺色对」「缺对照名」「分量越界」「对比度不足」；低对比反例固定为 `#AAAAAA` on `#FFFFFF`（实测 2.32），空名、越界、缺键各一条。删除或改名任一 palette 键后，整张矩阵必须因「缺色对」而红——该行为由解析函数结构性保证，不靠单测里手工塞 `nil` 模拟。
- ac-contrast-values-locked: 至少锁定四组精确实测值（容差 0.01），任何 hex 或 WCAG 公式漂移即红：`onAccent/accent` light `6.07`、dark `9.57`；light 最低对 `success/successSoft` `4.81`；dark 最低对 `danger/dangerSoft` `6.86`；并断言 `bodyThreshold == 4.5`、`largeThreshold == 3.0`。
- ac-typography-metric-roles: `Typography.metricLabelSize` 与 `Typography.metricUnitSize` 均为 `11`、两者相等，且 `< captionSize`、`>= 10`；`Typography.sizes` 变为严格递增 6 档 `[11, 12, 15, 20, 34, 56]`，`caption/body/title/primaryValue/display` 取值一个不变；`primaryValue >= 2 × body`、`display >= 2 × body` 仍成立；把 `metricLabel` 改成 13、或删掉 `metricUnit`、或让 `sizes` 不再严格递增，对应单测必须判红。
- ac-typography-role-ladder: 声明一份按字号非递减的角色阶梯（`metricLabel == metricUnit == 11` < `caption 12` < `body 15` < `title 20` < `primaryValue 34` < `display 56`），单测断言阶梯长度固定、按 size 非递减、且所有非相邻重复只允许出现在 label/unit 这一对；同时声明「数值角色」集合恰为 `[primaryValue, display]` 且标记需要等宽数字，其余角色不得标记；把某个数值角色移出集合或给 `caption` 打上等宽数字标记都必须判红。
- ac-motion-tokens-and-degrade: `Motion.durationShort == 0.2`、`Motion.durationState == 0.32`（单位秒，`TimeInterval`），且 `0 < durationShort < durationState <= 0.4`；`Motion.reducedMotionDuration == 0`；纯函数降级解析对两个常量都满足「`reduceMotion == true` 返回 0、`false` 返回原值」；把 0.2 改成 0.25、把 `durationState` 改到小于 `durationShort`、或让降级解析在 `true` 时返回非零，对应单测必须判红。
- ac-no-animation-wiring: 本子项内 `ios/PurePace/**` 除 `DesignTokens.swift` 外对 `Motion.` 的引用数为 0，`ios/PurePace/**` 中 `.animation(` / `withAnimation(` / `UIAccessibility.isReduceMotionEnabled` 的新增数为 0（动画接线留给第 3 波；本子项只提供常量与纯函数）。
- ac-semantic-spacing: 新增语义间距项至少包含指标组内、指标组之间、卡片内边距三项（命名由实现定，需为 `Spacing` 内 `CGFloat` 常量），取值必须落在既有档位 `{4, 8, 12, 16, 24, 32}` 内；`screenTop == 24`、`cardGap == 16`、`sectionGap == 12` 与 `Spacing.scale` 严格递增 6 档全部保持；把任一新增语义项改成 20（档位外）必须判红。
- ac-existing-tiers-frozen: `Radius.scale == [12, 16, 20]`、`Icon.scale == [16, 20, 24]`、`Stroke.hairline == 1`、`minTapTarget == 44`、`Appearance.supportsDarkMode == true` 全部逐值锁定；不新增圆角 / 图标 / 描边数值档，`Radius.scale` 与 `Icon.scale` 的档数不增加。
- ac-views-copy-a11y-untouched: 相对工作树起始提交，`ios/PurePace/Run/**`、`ios/PurePace/History/**`、`ios/PurePace/Settings/**`、`ios/PurePace/ContentView.swift`、`ios/PurePace/Resources/**`、`ios/PurePace/Design/L10n.swift`、本地化 catalog、`ios/project.yml`、`ios/RunCore/**`、`android/**`、`shared/**`、`scripts/**`、`.munk/code-gates.json` 的 `git diff --name-only` 均为空；`validate_design_tokens` 里 33 项 accessibility identifier 固定集合断言仍为绿（集合零增删改名）。
- ac-gates-green: `.munk/code-gates.json` 中 `lint-ios-shell`（含 `--self-test`，断言数不减少）、`test-ios`（`--unit-only`，真实执行到新增与改写的 `DesignTokensTests` / `ContrastPolicyTests`）、`build-ios`、`test-ios-core`、`test-ios-run-core`、`lint`、`test` 均退出 0；不新增 gate id、不改门列表。
- ac-budget-receipt: `digest.md` 首节写明开工时刻、预算时长与期望收口绝对时刻（建议预算 90 分钟：实现 ≤45、测试与反例 ≤30、校验收口 ≤15）；预算耗尽仍未完成时，仍须落盘已完成改动并在该节写「超时停手」+ 未完成项清单，不得静默延长会话或靠放宽断言补绿。

## 非目标

- 不改任何视图、交互行为、文案、可及性 identifier、页面结构、路由与 `RunSessionViewModel` / 状态机；不改本地化键与资源。
- 不在本子项接动画：不写 `.animation(...)`、`withAnimation`，不读 `UIAccessibility.isReduceMotionEnabled`，不新增 SwiftUI 过渡/回弹/数字滚动。
- 不新增独立组件库 / DesignSystem 目录 / 令牌分片文件，不新增屏，不引入第三方字体或图标（继续只用系统字体与 SF Symbols）。
- 不做配色体系重做：不新增、不删除、不重命名 `palette` 的 18 个语义键；light 值不动；dark 仅在「新纳入的成对组合实测不达标」时允许最小幅度微调，并须在回执里记录前后值，否则一律不改 hex。
- 不新增圆角 / 图标 / 描边的数值档，不改 `minTapTarget`、不改深色开关。
- 不改 `scripts/**`、`.munk/code-gates.json`、CI workflow、`Android`、`shared/**`；不为本子项新增 gate 或新脚本。
- 不写 `tech.md`；不排第 3 波以后的屏幕重建与交互闭环细节。
- 不做真机与模拟器截图验收（本子项无可见 UI 变化，`pending: 待人现场` 不适用）。

## 实现约束

- **成对矩阵只声明一次**：建议落在 `ContrastPolicy`（阈值与矩阵同源，`Pair` 持有 `name` / `foregroundKey` / `backgroundKey` / `minimum` / 分档标签），key 只引用 `DesignTokens.Colors.palette` 的字符串键；单测通过解析函数拿到 `Check`，不自己复制配对表。矩阵内不得出现 `0x` 十六进制。
- **解析函数形状**：`ContrastPolicy` 增加一个返回 `[Check]` 的纯函数（按 light/dark 解析 palette 键，缺键产出 `nil` 侧），`problems(for:)` 保持现有的四种原因串（「缺对照名」「缺色对」「分量越界」「无法计算对比度」「对比度不足」），不改既有 `ratio` / `ratios` / `formatted` 语义——既有调用点只增不改。
- **实测已核对（开工前用现网 hex 复算，勿凭印象）**：现有 light/dark 取值下，上表要求的全部 4.5 档与 3.0 档组合均已达标（最低为 light `success/successSoft` 4.81、dark `danger/dangerSoft` 6.86，`accent` 对三面 light 5.44–6.07 / dark 8.75–10.74）。因此**默认零 hex 改动**；若实现时新增组合不达标，按非目标里的「dark 微调 + 记录」处理，禁止顺手改 light。
- **`separator` 与面间对比口径**：`separator` 实测对三面仅 1.15–1.44，属装饰性 hairline，不承担信息语义，故按「装饰分隔 1.10 下界」判定并在用途注册表里写明「仅装饰，不作为唯一信息载体」；`surface` / `surfaceMuted` / `background` 之间不设 WCAG 阈值，改用「两者在 light 与 dark 下均不相等」的可区分性断言，避免为了凑阈值重做配色。
- **字号阶梯改法**：把 11 提进 `Typography.sizes`（得到严格递增 6 档），label 与 unit 共享 11 这一档；角色阶梯另用一份按 size 非递减的描述列表表达（允许 label/unit 重复一次）。不要为了维持「严格递增 5 档」而把 `sizes.count` 断言删掉或放宽成 `>= 1`——断言只可等价重述，不可弱化。
- **动效单位**：`Motion` 常量用 `TimeInterval`（秒）并注释对应毫秒值（`0.2` = 200ms、`0.32` = 320ms），避免秒/毫秒混用；降级解析须是纯函数（无 UIKit/SwiftUI 环境依赖），不做全局开关、不读环境。
- **门禁口径**：不新增 gate；本子项的全部不变量由既有 `test-ios --unit-only`（`PurePaceTests`）真实执行；`lint-ios-shell` 只作为「未被破坏」的正向回归（零字面色值、identifier 集合、三屏 token 引用）。
- **预算与回执**：开工即写预算与期望收口绝对时刻；超时按 `ac-budget-receipt` 落回执，不许以放宽阈值、删断言或延长会话的方式补绿。
- 本子项是 WorkSet 子项，不开启 Design / Architect / PM 阶段的追加工作；后续第 3 波视图接线由后继子项消费本子项产出的 token 名称与本 PRD 的 ac-*。
