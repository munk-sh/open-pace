# Domain: ios-finished-summary

PurePace iOS 跑步「结束待保存态（B1）」版式与「丢弃确认层（C2）」形态的单域契约。垂直预算由 `RunFinishedSummaryLayoutPolicy` 单点定义（地图 hero 360、内容 ≤ 691、操作条 68、inline 胶囊 ≤ 32、辅助字号档 96），确认层形态由 `RunInteractionPlan` 的 `Emphasis` / `DiscardConfirmation` 单点定义（`dangerFilled` 实心唯一填充 + `text` 无填充文字次操作）。token 与三屏层级见域 `ios-ui-design`，plan 的交互接线见域 `ios-run-interaction`，证据归档见域 `ios-evidence-freeze`。

## 范围

- `ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift`：`standardMapHeroHeight = 360`、`referenceScreenHeight = 852`、`mapHeroMinimumRatio = 0.40`、`finishedContentHeightBudget = 691`、`inlineHintMaxHeight = 32`、`accessibilityTrackPreviewHeight = 96`、`discardSheetFallbackHeight = 144`、`actionBarHeight = minTapTarget + 2 × Spacing.sm`（68）；判据 `meetsMapHero` / `meetsContentBudget` / `meetsInlineHint` / `trackPreviewHeight(isAccessibilitySize:)` / `compressesFinishedSummary(isAccessibilitySize:availableContentHeight:)`（后者只对辅助字号档为真）。槽位函数（`topBreathing` / `heroTopPadding` / `heroMetricsGap` / `metricCardPadding` / `metricCardBottomPadding` / `metricGroupGap` / `blockSpacing`）只在辅助字号档回收，取值全为既有 `DesignTokens.Spacing` 派生。
- `ios/PurePace/Run/RunView.swift`：`finishedContent` 四块纵向序 = 地图 hero（`TrackMapView` 真实轨迹 + 左下常显 `run.distance`）→ 指标行（时长 + 平均配速）→ 分段明细（空态 `run.finished.splitsEmpty`）→ inline 提示；地图空轨迹给 `run.mapEmpty` / `run.mapEmpty.single` 中文空态，不构造裸 `Map`、不留白；主操作区 `.frame(minHeight: RunFinishedSummaryLayoutPolicy.actionBarHeight)`；确认层 sheet 用 `.onGeometryChange(for: CGFloat.self)` 实测内容高度驱动 `.presentationDetents([.height(discardSheetContentHeight)])`，iOS 17 兜底 `discardSheetFallbackHeight`。
- `ios/PurePace/Run/RunInteractionPlan.swift`：`Emphasis.text` → `Style.textSecondary`（无填充 / 无描边文字次操作）、`Emphasis.danger` → `Style.dangerFilled`（`danger` 实底 + `onDanger` 前景，`fillsWithTint == true`）；`discardRequest` 与确认层 `cancel` 取 `text`，确认层 `confirm` 取 `danger`；`heroTint` 在未保存的四态恒 `.primary`，`didSave` 时 `.success`。
- `ios/PurePace/Resources/Localizable.xcstrings`：新增 `run.location.backgroundDegradedHintShort`（图标 + 短文案单行胶囊），完整长句仍作 `accessibilityLabel`。
- `ios/project.yml`：`RunFinishedSummaryLayoutPolicy.swift` 显式列入 `PurePaceUITests` sources（UI 腿与单测共用同一策略源）。
- 断言：`PurePaceTests/RunFinishedSummaryLayoutPolicyTests.swift`（360/40% 门槛、691 预算、68 操作条、inline 胶囊判据与历史值反例）+ `PurePaceTests/RunInteractionPlanTests.swift`（`textSecondary` / `dangerFilled` / `fillsWithTint` / heroTint）+ `PurePaceUITests/RunFlowUITests.swift`（`assertFinishedMapFloor` / `assertFinishedContentBudget` / `assertFinishedActionBar` / `assertFinishedItemsVisible` / `assertDiscardSheetC2` / `assertRenderedDanger`）+ `ScreenshotEvidenceUITests`（浅/深 B1·C2 四图）。
- 静态门禁：`scripts/check-ios-shell.sh` 的 B1/C2 段（策略常量与 `actionBarHeight` 引用、`.presentationDetents([.height(...)])` 与 `onGeometryChange` 存在、禁 `.medium` 固定档、`run.finished.splitsEmpty` / `run.mapEmpty` 空态、hero tint 锚点、accent 不作文字前景）与 `--self-test` 正负反例沙箱。

## 验收

- ac-finished-map-hero-360: 结束待保存态地图 hero 实测 = 361pt（容差 1 内即 360），且 `meetsMapHero` 门槛 ≥ `referenceScreenHeight × 0.40` = 340.8pt；历史 96 / 180 / 340.7 一律判红；标准字号档地图恒 360，不因内容预算或压缩分支变化。
- ac-finished-content-budget: 内容合计（地图 + 指标行 + 分段 + inline 提示 + 固定间距）≤ `finishedContentHeightBudget`(691)，实测 593.8；内容底沿不越过 `run.save` 顶边（实测 703.0 < 762.0）；691.1 与改前溢出组合必须判红。
- ac-finished-action-bar-68: 主操作条高度 = `actionBarHeight` = 44（`minTapTarget`）+ 2 × 12 = 68pt，`run.save` 仍 44pt；改值必须判红。
- ac-finished-blocks-always-visible: 四块（地图 hero / 指标行 / 分段 / inline 提示）在结束待保存态同屏可见；`run.distance` 常显在地图上且仍是同一 identifier；0 分段给 `run.finished.splitsEmpty` 替代文案，不留空卡；`run.mapEmpty` 覆盖空轨迹。
- ac-inline-hint-capsule: `-uiTestLocation` 固定 `authorizedWhenInUse` → `run.backgroundDegraded` 胶囊确定性出现；实测 248.0 × 23.67pt，满足 `meetsInlineHint`（高度 ≤ 32 且宽 248.0 < 内容宽 361，不占满整行）；改前整行 360 × 39.33（zh-Hans 长句两行）作反例；完整长句挂 `accessibilityLabel`。
- ac-c2-sheet-autosize-detent: 确认层高度由 `onGeometryChange` 实测内容高度驱动 `.presentationDetents([.height(...)])`，不写 `.presentationDetents([.medium])` 固定档，也不依赖 `.presentationSizing(.fitted)`（iPhone 上不生效）；sheet 顶边由确认层标题静态文本 `frame.minY − Spacing.xs` 推导（`app.sheets` 在 iOS 18.6 不匹配 SwiftUI detent sheet，已弃用并写入证据 README），实测 top = 682.33 ≥ 852 × 70% = 596.4、height = 169.67 ≤ 200；取消回结束待保存态且距离 / 会话状态不变、未触发丢弃。
- ac-c2-confirm-filled-danger: 确认层 `run.discard` 是唯一填充控件（`dangerFilled` = `danger` 实底 + `onDanger`，44pt，像素采样容差 ≤ 2/255），`run.discardCancel` 无填充无描边，二者同行且中心差 ≤ 2pt（实测 0pt）；结束待保存屏上 `plan.items` 无 `danger`，`run.discard` 在 sheet 打开前不存在；旧 `dangerOutline` + `secondary` 映射喂形态判据必须判红。
- ac-hero-tint-primary: 未保存四态（ready / running / paused / finished）hero 主值色恒 `.primary`，`didSave` 取 `.success`，永不为 `warning`；静态门禁锚点 `case .running, .paused: return .primary` / `case .ready, .finished: return .primary` 与 `valueTint: color(for: plan.heroTint)`；回退 accent 颜色或暂停切 warning 必须判红。
- ac-identifiers-frozen-42: 冻结 33 项零改名零删除，去重计数保持 42；本轮不新增 identifier 集合。
- ac-gates-and-evidence: 22 门全绿（含 `lint-ios-shell` 33 项 0 失败、`--self-test` 100 项 0 失败、`test-ios` 265 + 173 例 0 失败）；`docs/evidence/wi_intake_93f2857d51330b9d/` 入仓（4 PNG + 4 日志 + `SHA256SUMS` + README），`shasum -a 256 -c` 通过，README 绑定实现 commit 与 tree sha。

## 非目标

- 不重排 B1 / C2 之外任何页面，不新增页面、组件、颜色键、字号档或 identifier 集合。
- 不改 token 色值与对比度阈值（`accent` 仍只作填充，不作正文 / 数字前景）。
- 不改状态机 / 持久化 / 播报 / GPX 逻辑，不改 binding / DB。
- 不改 CI 预算、超时、分段策略；不跑 `.github/workflows/ios.yml` 权威腿；不出 14 张复评截图。
- 不改版本号（`VERSION` 固定 `0.1.0`）；真机观感一律 `pending: 待人现场`。

## 实现约束

- 结束态路径零裸数字：视图只读 `RunFinishedSummaryLayoutPolicy` 属性或既有 `DesignTokens` token；新增槽位必须落成命名参数并附实测来源，不得在视图内写字号 / 间距 / 高度字面量。
- 地图 hero 是真实轨迹块而非占位：`TrackMapView` 提供空轨迹 / 单点中文空态，禁止裸 `Map`、禁止用固定占位矩形冒充轨迹预览。
- 压缩只服务辅助字号档：`compressesFinishedSummary` 只读 `isAccessibilitySize`，标准档不得因预算压图；历史 96 / 180 只能作为反例输入。
- 确认层唯一填充：每屏最多一个填充控件（待保存屏 = `run.save`，确认层 = `run.discard`），二者不同屏同形状并列；`fillsWithTint` 是唯一判据。
- identifier 与文案：只复用既有 identifier（`run.distance` / `run.discard` / `run.discardRequest` / `run.discardCancel` 等），新增文案只进 `Localizable.xcstrings` 并经 `L10n` 引用。
- 工程真源：`ios/project.yml` 变更后必须 `xcodegen generate`，禁手改 `project.pbxproj`。
- 证据：只写模拟器实测结论；截图必须来自本项实现 commit 的同一构建树，哈希变更时同步 `SHA256SUMS` 与 README 实测值。

## 最近交付证明

- workItemId: wi_intake_677e501cd4f74e4f（2026-11-12，pass）
- 交付：V1.2 B1 结束态与 C2 丢弃确认以 patch（sha256 `f3ed82…ccae`，15 文件 / +759 −208）机械 apply 到 `eceedb9`，单一实现 commit `96b7d01`（parent = `eceedb9`），证据 commit 只改 `docs/evidence/**`（tree `c06abaf`）。B1 地图 hero 恒 360（实测 361.0 ≥ 852×40%）、内容 593.83 ≤ 691 且底沿 703.0 不压 `run.save`(762.0)、操作条 68、inline 权限胶囊由整行两行改为单行 248.0×23.67（≤32）；C2 确认层改 `dangerFilled` 唯一填充 + 无填充 `text` 次操作、`onGeometryChange` 实测高度 detent（top 682.33 ≥ 596.4、height 169.67 ≤ 200、confirm 44pt、中心差 0）；`heroTint` 未保存四态恒 primary（浅色 accent 仅作填充）。
- 判定与证据：`code_gates` 22 门 attempt 001 全绿；`check-ios-shell` 33 项 / `--self-test` 100 项 0 失败；`test-ios` PurePaceTests 265 + RunCore 173 例 0 失败；四张证据图哈希全变（inline 胶囊改动）→ 按新构建重出并更新 `SHA256SUMS`，README 记录构建 head `96b7d01` / tree `c06abaf` / patch sha256。
- 偏离与边界：patch 落到本项后补了 inline 胶囊单行化与 C2 取数闭环（`ac-inline-hint-measured` / `ac-c2-sheet-probe-unambiguous`）；未跑 `ios.yml` 权威腿、未出 14 张复评截图（后续写项③）；`VERSION` 仍 0.1.0；真机观感 `pending: 待人现场`。
