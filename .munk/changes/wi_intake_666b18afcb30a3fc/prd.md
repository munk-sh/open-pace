# 三屏视觉达发布线（设置 / 历史列表 / 历史详情）

## 范围

- 先令牌与线框、后改屏：先定三屏的分组与卡片层级（写进 `docs/design/` 或本项 prd 附段），再改视图。
- 改动范围仅限：`ios/PurePace/Design/DesignTokens.swift`（既有档位值）、`ios/PurePace/Settings/SettingsView.swift`、`ios/PurePace/History/HistoryView.swift`、`ios/PurePace/History/RunDetailView.swift` + `RunDetailContent.swift`，以及对应 UI 测试（`RunFlowUITests` / `Ax5ScrollAuditCounterexampleTests` / `ScreenshotEvidenceUITests`）。
- 间距：卡片间距 ≥16、分组间距 ≥24、卡片内边距 ≥16；数值一律 tabular figures；每组有分组标题 + 说明。
- 设置页诊断区收进「高级」分组，默认折叠，展开后可复制导出。
- 06-settings 的 AX5 越界（基线 `90bb205` 实测 16.67pt）必须清零。
- 深浅色各出一套固定模拟器（iPhone 16 / iOS 18.6）截图 + 运行日志，落 `docs/evidence/<本项 workItemId>/`，附 `SHA256SUMS`，全部绑同一 commit。

## 验收

- ac-ax5-zero: 06-settings 在 AX5 的越界由 16.67pt 降为 0，用同一断言、不放宽阈值，附改前失败原文与改后同一断言绿。
- ac-spacing: 三屏满足卡片间距 ≥16 / 分组间距 ≥24 / 卡片内边距 ≥16，数值用 tabular figures，每组有分组标题与说明；对应断言可构造错误输入判红。
- ac-advanced: 设置页诊断区在「高级」组内且默认折叠，展开后复制导出可用；组标题与说明齐全。
- ac-screenshots: light / dark 各一套 iPhone 16 / iOS 18.6 截图 + 日志 + `SHA256SUMS`，路径写进回执，绑同一 commit。
- ac-tokens: 只改既有令牌档位值（圆角 10 / 14 / 20、display 64、间距档位等），18 键 × 深浅 36 hex 的键数不增不减、色相与对比度策略不动；视图层零字面色值、零裸 magic number。
- ac-guards: identifier 只增不改；改动受管视图后 `bash scripts/check-ios-shell.sh --self-test` 全绿且计数同步；`bash scripts/check-ios-scripts.sh` 不红。

## 非目标

- 不改跑步首页与记录态既有结构，不改 W1 定位语义与 W2 再跑入口语义（只复用其入口）。
- 不加第二套橙、不改 danger / warning 色相分离口径、不降任何断言阈值。
- 不新增功能、不动 `VERSION`、不打 tag、不出包、不做真机验收。
- 不以压字号 / 压间距兜底信息密度，不删分组标题或说明来省空间。

## 实现约束

- 仓库地图（勿重复探查）：令牌 `ios/PurePace/Design/DesignTokens.swift`；三屏 `ios/PurePace/Settings/SettingsView.swift`、`ios/PurePace/History/HistoryView.swift`、`ios/PurePace/History/RunDetailView.swift` + `RunDetailContent.swift`；字符串唯一来源 `ios/PurePace/Resources/Localizable.xcstrings`；UI 套件 5 个在 `ios/PurePaceUITests/`。
- 命令：单 XCTest 类 `xcodebuild test -only-testing:PurePaceTests/<Class> -scheme PurePace -destination "platform=iOS Simulator,name=iPhone 16"`（已构建过用 `test-without-building` + `-derivedDataPath .build/ios`）；单 UI 套件 `xcodebuild test-without-building -project ios/PurePace.xcodeproj -scheme PurePace -destination "platform=iOS Simulator,name=iPhone 16,OS=18.6" -derivedDataPath .build/ios -only-testing:PurePaceUITests/<Suite> CODE_SIGNING_ALLOWED=NO`；结构自检 `bash scripts/check-ios-shell.sh --self-test`。
- 廉价反馈环：开工第一件事跑通「单个测试类 ≤60 秒」的命令，之后每轮靠编译 / 单测判定；整文件批量改写，禁逐点微编辑；同一文件重读 >1 次即停，用编译错误定位。
- 变异红证不逐条跑：新增断言同 commit 附「构造错误输入 → 必红」的反例路径即可，整体并入后续证据项。
- 确认层 / sheet 的尺寸断言只用内容几何推导，禁用 `app.sheets` 探测。

## 本单执行约束（不 fold）

- 预算 ≤8M token / ≤90 分钟墙钟；到 5M 或 60 分钟先 WIP commit + 一条进度回执（已做 / 未做 / 红在哪），再决定继续或交未闭合回执。
- commit 按面拆分：code（视图 / 令牌 / 测试）/ fold（docs、evidence、baseline）/ prd 不混面。
- 不与在飞研究项重叠（它只碰 docs/ 与 docs/evidence/）；若发现需改 W1 / W2 语义，写未闭合点交回执，不自行扩面。
- 截图只能来自 iPhone 16 / iOS 18.6 模拟器；设备使不出就记未跑齐，禁以其他机型或截图凑数。
