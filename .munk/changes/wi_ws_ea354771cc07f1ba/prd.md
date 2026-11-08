# 历史列表补配速与跑次详情

## 范围

在既有 iOS 真实闭环（`Run / History / Settings` 三 Tab、`RunArchiveStore` 真实归档）之上，把 History 从「只列日期/距离/时长」补成可下钻的真实历史：

1. **历史行补平均配速**：`ios/PurePace/History/HistoryView.swift` 每行沿用 `RunArchiveStore.list()` 的倒序（`startedAt` 降序）渲染日期、距离、时长，并新增本条跑次的平均配速；配速只能由既有 `RunPace(distance:duration:)` 从 `record.distance` + `record.activeDuration` 派生，格式化走 `RunFormatting.paceText`，不足数据（派生为 `nil`）时用既有 `RunFormatting.emptyPace` 占位。
2. **跑次详情页**：新增 `RunDetailView`（`ios/PurePace/History/`），由列表行点击进入，展示本次跑次的起止时间、总距离、活跃时长、平均配速与全部分段（序号 + 分段配速）。所有字段直接取自被点击的 `RunRecord`（含 `splits`）与 `RunFormatting`，不重算距离、不重新聚合分段、不读任何样例。
3. **它们之间是纯展示映射**：新增 `RunDetailContent`（`ios/PurePace/History/`）把 `RunRecord` 映射为可直接绑定的展示字符串与分段行数组，视图零逻辑，映射可被 `PurePaceTests` 直接断言。
4. **契约同步**：`scripts/check-ios-shell.sh` 的真实 UI 文件清单、无障碍标识清单与测试落点清单同步纳入新文件与新标识；`RunFlowUITests` 在真实归档下补「行含配速 → 点击进入详情 → 详情含起止时间与分段区域」断言；`PurePaceTests` 补 `RunDetailContent` 的分段映射断言。
5. **空态不变**：`RunArchiveStore` 为空时仍只有 `history.empty` + 「去跑一次」，不渲染任何行、详情不可达。

## Acceptance Criteria

- ac-list-row-pace: 归档中存在 1 条 `distance = 1000 m`、`activeDuration = 300 s` 的记录时，History 行文本同时含日期、`1.00 km`、`05:00` 与 `5:00 /km`；行仍以 `history.row` 为唯一标识且可点击。
- ac-list-pace-nil-fallback: 记录 `distance` 为 0 或 `activeDuration` 为 0（`RunPace(distance:duration:)` 返回 `nil`）时，行与详情页配速文本均等于 `RunFormatting.emptyPace`（`--`），不出现 `inf`/`nan`/空串。
- ac-list-order-preserved: 归档中乱序写入 3 条记录后，History 行顺序与 `RunArchiveStore.list()` 的 `startedAt` 降序完全一致（首行 `startedAt` 最大），条数等于 `list()` 条数。
- ac-detail-from-record: 点击某一行后，详情页 `runDetail.distance` / `runDetail.activeDuration` / `runDetail.averagePace` 的文本分别等于 `RunFormatting.distanceText(record.distance)` / `RunFormatting.elapsedText(record.activeDuration)` / `RunFormatting.paceText(RunPace(distance: record.distance, duration: record.activeDuration))`，且等于列表该行的对应文本（详情与列表同源，不引入第二套计算）。
- ac-detail-start-end: 详情页 `runDetail.startedAt` / `runDetail.endedAt` 非空、互不相同，分别由 `record.startedAt` / `record.endedAt` 格式化得到；`endedAt` 早于 `startedAt` 的记录不存在（`RunRecord` 构造期已拒绝，不得在 App 侧另造）。
- ac-detail-splits-all: 对含 3 个分段（index 1/2/3，`duration` 分别 300/330/360 s）的合成记录，`RunDetailContent` 产出恰 3 条分段行，序号依次为 1、2、3，配速文本依次等于 `RunFormatting.paceText(split.pace)`（`5:00 /km`、`5:30 /km`、`6:00 /km`），不增不减、不重排。
- ac-detail-splits-empty: 记录 `splits` 为空时，详情页显示分段区域标题（`runDetail.splits`）与诚实空态 `runDetail.splitsEmpty`，`runDetail.splitRow` 元素数为 0。
- ac-ui-list-pace-real-run: `bash scripts/test-ios.sh` 的真实定位注入流程跑完一次跑次后，History 恰 1 行，且该行无障碍 label 含距离、时长与 `/km` 配速串。
- ac-ui-detail-navigable: 同一 XCUITest 中点击该行后出现 `runDetail.root`；`runDetail.startedAt`、`runDetail.endedAt` 存在且 label 不同；`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace` 与列表行一致；`runDetail.splits` 存在，且 `runDetail.splitRow` 元素数等于 `runDetail.splits` 摘要中给出的分段条数（真实亚公里跑次为 0，此时 `runDetail.splitsEmpty` 存在）。
- ac-ui-empty-no-detail: 开跑前（归档为空）History 仅 `history.empty` + `history.runAgain`，`history.row` 与任何 `runDetail.*` 元素数均为 0，空态文案不变。
- ac-no-recompute-no-sample: App 源码中详情/列表的距离、时长、配速与分段全部来自 `RunRecord` 字段与 `RunFormatting`；不出现自建距离公式、`Ingest`/`RunMetricsEngine` 调用、内置坐标序列、`shared/fixtures`、`.gpx`/`.tcx` 字面量或样例跑次。
- ac-shell-gate-synced: `scripts/check-ios-shell.sh` 的 `live_sources` 含 `ios/PurePace/History/RunDetailView.swift` 与 `ios/PurePace/History/RunDetailContent.swift`，其标识断言覆盖 `history.row`、`runDetail.root`、`runDetail.startedAt`、`runDetail.endedAt`、`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.splits`、`runDetail.splitsEmpty`；测试落点清单含新增/更新的 XCTest 与 XCUITest 文件；`--self-test` 仍退出 0。
- ac-gates-green: `bash scripts/check-ios-shell.sh`（lint-ios-shell）、`bash scripts/build-ios.sh`（build-ios）、`bash scripts/test-ios.sh`（test-ios）均退出 0；`.munk/code-gates.json` 门 id 集合仍为既有 22 个（只增不减、`command` 仍为单一 argv）；`swift test --package-path ios/RunCore` 与 `swift test --package-path ios/Core` 不回归。

## 非目标

- 不做 GPX 导出、`ShareLink`/`fileExporter`/系统分享面板、文件写入与 `RunGPXExporter` 接线（后续子项）。
- 不做地图、轨迹折线、轨迹摘要卡片与采样点回放；详情页不渲染 `record.samples`。
- 不做删除/编辑/重命名记录、分页/筛选/搜索、跨天分组、浮动详情动画或自定义视觉主题；沿用系统语义色、系统 List 与 Dynamic Type。
- 不改 `ios/RunCore`、`ios/Core`、`ios/PurePace/Harness/`、`ios/PurePace/Run/RunSessionViewModel.swift`、`Location/`、`Audio/` 的源码与契约；`RunRecord`/`RunArchiveStore`/`RunPace`/`RunSplit` 只读复用。
- 不改 `scripts/test-ios.sh` 的定位注入口径（仍 `--speed=3 --interval=1`）；不新增 launch-arg 假流、不注入预置归档文件来伪造分段。
- 不新增门禁 id、不改 `.munk/code-gates.json`、不碰 `android/`、`shared/`、CI workflow、`VERSION`、`AGENTS.md`。
- 不做真机验证、锁屏连续定位、音乐 duck 与 TTS 实听（`pending: 待人现场`）；对外只写「模拟器链路 + 代码层断言」。

## Implementation Constraints

- 落点（均在已有目录，避免新概念）：
  - 改：`ios/PurePace/History/HistoryView.swift`（行补配速 + `NavigationLink` 到详情；保留 `history.empty` / `history.runAgain` / `history.row` 与 `archiveStore.list()` 调用形态）。
  - 改：`ios/PurePace/Run/RunFormatting.swift`（在既有 `enum RunFormatting` 内新增日期/分段行文本等纯函数；不新建格式化模块，不加状态与时钟）。
  - 新：`ios/PurePace/History/RunDetailView.swift`、`ios/PurePace/History/RunDetailContent.swift`。
  - 改/新测试：`ios/PurePaceTests/RunFormattingTests.swift` 扩展配速/分段文本断言，新增 `ios/PurePaceTests/RunDetailContentTests.swift`；`ios/PurePaceUITests/RunFlowUITests.swift` 扩展现有单一真实流程（不新增第二套启动/注入链路）。
  - 改：`scripts/check-ios-shell.sh`（文件清单 + 标识清单 + 测试落点清单，纯字符串断言，保留 `--self-test` 反例自检行为）。
- 详情页导航用视图式 `NavigationLink { RunDetailView(record:) } label: { row }`，不要求 `RunRecord` 新增 `Hashable`，不改 RunCore。
- 详情页数据来源硬约束：`record.startedAt` / `endedAt` / `distance` / `activeDuration` / `splits`；平均配速只能 `RunPace(distance: record.distance, duration: record.activeDuration)`；分段配速只能 `split.pace`（内部同为既有 `RunPace` 派生）。禁止在 App 侧重算距离、重切分段或按 elapsed 自造数值。
- 稳定无障碍标识（新测试契约，加入 `check-ios-shell.sh` 断言）：`runDetail.root`、`runDetail.startedAt`、`runDetail.endedAt`、`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.splits`（含分段条数摘要）、`runDetail.splitRow`、`runDetail.splitsEmpty`。标识写成字符串字面量，避免门禁 grep 落空。
- 真实链路口径（XCUITest 不做假证据）：现有注入为 3 m/s、跑次仅数十米，不可能跨整公里，故真实链路断言分段区域可见 + `splitRow` 条数与详情摘要一致（本波为 0 + `splitsEmpty`）；非空分段的逐行内容由 `RunDetailContent` 的 L1 XCTest（合成 3 段记录）断言。若未来该 UI 测试能跑出 ≥1 km，同一断言无需修改即可覆盖非零行。
- 测试纪律：XCTest（禁 `import Testing`）；复用既有临时目录 + `UUID()` 约定；时间用 `Date(timeIntervalSince1970:)` 合成；不读夹具；不新增固定 `sleep` 作为成功判据（`check-ios-shell.sh` 会 grep）。
- 门禁红线：`ios/PurePace` 全目录不得出现 `shared/fixtures`、`.gpx`、`.tcx` 字面量；`ios/PurePace/Run` 不得出现 `Timer` / `DispatchQueue.asyncAfter` / `CADisplayLink`；`CoreLocation` 仍只允许 `Harness/` + `Location/`；App import 允许表不变（SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore）。
- 证据口径：只报脚本真实输出与用例数、`check-ios-shell.sh` 的 PASS 计数与 self-test 结果；不写「真机已验证」「阶段 3 已通过」。
