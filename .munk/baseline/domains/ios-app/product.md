# Domain: ios-app

PurePace iOS App 运行域（波 1 最小闭环）：把 `ios/PurePace` 从空壳占位页换成真实跑步单页——Run / History / Settings 三 Tab、`CLLocationManager` 真实定位数据源、`RunSessionOrchestrator` 驱动的会话 ViewModel、真实归档历史与诚实空态设置页，并用 `xcrun simctl location` 注入的真实 CoreLocation 更新跑通 XCUITest。App 侧只做接线与展示，距离/时长/配速/分段一律来自 `PurePaceRunCore` 既有契约，不重写 RunCore、不自建计时器或距离公式。

## 范围

- `ios/PurePace/ContentView.swift`：`TabView` 收敛为 Run / History / Settings 三项（`Log` 删除）；非 Harness 启动直落 Run 页，0 秒可用，无登录/引导/样例加载。
- `ios/PurePace/Location/RunLocationSource.swift`：`CLLocationManager` 唯一 App 侧采点入口（`.fitness` / `desiredAccuracyBest` / `distanceFilter = kCLDistanceFilterNone` / `pausesLocationUpdatesAutomatically = false` / 不自动暂停）；`.notDetermined` 时请求「使用期间」授权，授权后自动继续，拒绝时显示诚实等待态。
- `ios/PurePace/Run/`：`RunSessionViewModel`（主线程可观测，持有 `RunSessionOrchestrator` + `RunCheckpointStore` + `RunArchiveStore`，delegate 采样 → `ingest`，start/pause/resume/finish → 编排器动作）、`RunView` 单页 UI（距离、活跃时长、当前/平均配速、已完成分段数 + 开始/暂停/恢复/结束互斥按钮 + 结束「已保存」反馈）、`RunFormatting` 纯函数格式化、`RunStorage` 沙盒路径（`Documents/Runs/` 归档 + `Caches/` checkpoint，路径由 ViewModel 注入）。
- `ios/PurePace/History/HistoryView.swift`：读 `RunArchiveStore.list()`，空态 `history.empty` + 「去跑一次」入口；有记录按 `startedAt` 倒序展示真实日期/距离/时长，并补本条跑次平均配速（只由 `RunPace(distance:duration:)` 从 `record.distance` + `record.activeDuration` 派生，`RunFormatting.paceText` 格式化，派生为 `nil` 时用 `RunFormatting.emptyPace`）；行可点击进入详情。
- `ios/PurePace/History/RunDetailView.swift` + `RunDetailContent.swift`：行点击进入的跑次详情（起止时间、总距离、活跃时长、平均配速、全部分段序号 + 分段配速）；`RunDetailContent` 只把被点击的 `RunRecord`（含 `splits`）映射为展示字符串与分段行数组，视图零逻辑，`splits` 为空时显示 `runDetail.splits` 标题 + `runDetail.splitsEmpty` 诚实空态。
- `ios/PurePace/Settings/SettingsView.swift`：明确声明本阶段无可配置项，无任何可交互开关或示例数值。
- `ios/PurePaceTests/`：`RunSessionViewModelTests`（编排器一致性、暂停冻结、恢复锚点、结束单条归档）、`RunFormattingTests`（格式化纯函数，含配速/分段文本）、`RunDetailContentTests`（`RunRecord` → 详情展示映射与分段行）；`ios/PurePaceUITests/RunFlowUITests.swift`：真实定位注入下的全流程断言（含 History 行配速 → 点击进入详情 → 详情起止时间与分段区域）。
- `scripts/check-ios-shell.sh`：真实 UI 断言（文件清单、无障碍标识、History/Settings 诚实态、无 `shared/fixtures|.gpx|.tcx`、Run 无 `Timer` 假计时）+ `CoreLocation` 仅 `Harness/` 与 `Location/` 双作用域正负反例；清单同步纳入 `History/RunDetailView.swift`、`History/RunDetailContent.swift`、`runDetail.*` 标识与新增/更新的 XCTest / XCUITest 落点。
- `scripts/test-ios.sh`：测试前 boot iPhone 16 / iOS 18.6 并 `xcrun simctl location start --speed=3 --interval=1` 注入 ≥20 km 直线航点，`trap` 收尾 `clear`；设备/runtime 缺失显式失败。

## 验收

- ac-tabs-converged: 非 Harness 启动时 Tab 栏恰为 Run / History / Settings 三项，`Log` Tab 不再存在。
- ac-live-metrics-from-orchestrator: 注入 N 条采样后，ViewModel 对外暴露的距离 / 时长 / 平均配速 / 当前配速 / 分段数与同一批采样喂给 `RunSessionOrchestrator` 得到的 `metrics` 逐字段相等；未开始时距离为 0、当前与平均配速均为空。
- ac-pause-zero-growth: 进入暂停后继续摄入时间递增且位移非零的采样，距离与活跃时长均保持不变，当前配速为空。
- ac-resume-continues: 恢复后的首条采样只重建位置锚点、不跨越暂停空档累计位移；其后的采样继续使距离与活跃时长单调增长。
- ac-finish-single-archive: 结束一次跑次后 `RunArchiveStore.list()` 恰返回 1 条且字段来自本次会话；对同一会话重复调用结束（含视图重复点击）不新增记录、`list()` 仍为 1 条。
- ac-saved-feedback: 结束成功后 UI 出现可被无障碍标识定位的「已保存」反馈（`run.saved`）；未结束时该元素不存在。
- ac-history-honest: 归档目录为空时 History 显示空态（`history.empty`）且不渲染任何示例跑次；存在归档时按 `startedAt` 倒序渲染真实日期 / 距离 / 时长，条数与 `RunArchiveStore.list()` 一致。
- ac-list-row-pace: 归档中存在 1 条 `distance = 1000 m`、`activeDuration = 300 s` 的记录时，History 行文本同时含日期、`1.00 km`、`05:00` 与 `5:00 /km`；行仍以 `history.row` 为唯一标识且可点击。
- ac-list-pace-nil-fallback: 记录 `distance` 为 0 或 `activeDuration` 为 0（`RunPace(distance:duration:)` 返回 `nil`）时，行与详情页配速文本均等于 `RunFormatting.emptyPace`（`--`），不出现 `inf`/`nan`/空串。
- ac-list-order-preserved: 归档中乱序写入 3 条记录后，History 行顺序与 `RunArchiveStore.list()` 的 `startedAt` 降序完全一致（首行 `startedAt` 最大），条数等于 `list()` 条数。
- ac-detail-from-record: 点击某一行后，详情页 `runDetail.distance` / `runDetail.activeDuration` / `runDetail.averagePace` 文本分别等于 `RunFormatting.distanceText(record.distance)` / `RunFormatting.elapsedText(record.activeDuration)` / `RunFormatting.paceText(RunPace(distance: record.distance, duration: record.activeDuration))`，且与列表该行对应文本一致（详情与列表同源，不引入第二套计算）。
- ac-detail-start-end: 详情页 `runDetail.startedAt` / `runDetail.endedAt` 非空、互不相同，分别由 `record.startedAt` / `record.endedAt` 格式化得到；`endedAt` 早于 `startedAt` 的记录不存在（`RunRecord` 构造期已拒绝，不在 App 侧另造）。
- ac-detail-splits-all: 对含 3 个分段（index 1/2/3，`duration` 分别 300/330/360 s）的合成记录，`RunDetailContent` 产出恰 3 条分段行，序号依次 1、2、3，配速文本依次等于 `RunFormatting.paceText(split.pace)`（`5:00 /km`、`5:30 /km`、`6:00 /km`），不增不减、不重排。
- ac-detail-splits-empty: 记录 `splits` 为空时，详情页显示分段区域标题（`runDetail.splits`）与诚实空态 `runDetail.splitsEmpty`，`runDetail.splitRow` 元素数为 0。
- ac-ui-list-pace-real-run: `bash scripts/test-ios.sh` 的真实定位注入流程跑完一次跑次后，History 恰 1 行，且该行无障碍 label 含距离、时长与 `/km` 配速串。
- ac-ui-detail-navigable: 同一 XCUITest 中点击该行后出现 `runDetail.root`；`runDetail.startedAt`、`runDetail.endedAt` 存在且 label 不同；`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace` 与列表行一致；`runDetail.splits` 存在，且 `runDetail.splitRow` 元素数等于 `runDetail.splits` 摘要中的分段条数（真实亚公里跑次为 0，此时 `runDetail.splitsEmpty` 存在）。
- ac-ui-empty-no-detail: 开跑前（归档为空）History 仅 `history.empty` + `history.runAgain`，`history.row` 与任何 `runDetail.*` 元素数均为 0，空态文案不变。
- ac-no-recompute-no-sample: App 源码中详情/列表的距离、时长、配速与分段全部来自 `RunRecord` 字段与 `RunFormatting`；不出现自建距离公式、`Ingest`/`RunMetricsEngine` 调用、内置坐标序列、`shared/fixtures`、`.gpx`/`.tcx` 字面量或样例跑次。
- ac-shell-gate-synced: `scripts/check-ios-shell.sh` 的 `live_sources` 含 `ios/PurePace/History/RunDetailView.swift` 与 `ios/PurePace/History/RunDetailContent.swift`，标识断言覆盖 `history.row`、`runDetail.root`、`runDetail.startedAt`、`runDetail.endedAt`、`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.splits`、`runDetail.splitsEmpty`；测试落点清单含新增/更新的 XCTest 与 XCUITest 文件；`--self-test` 仍退出 0。
- ac-settings-honest: Settings 不包含任何可切换控件、示例数值或内置样例，并明确说明本阶段无可配置项。
- ac-no-fake-data: App 源码不含内置坐标序列、fixture 引用或 GPX/TCX 样例文件路径，也不存在以固定步长递增距离或用定时器伪造时长的逻辑（源码中不得出现 `.gpx` / `.tcx` 字面量）；距离与时长只能来自 `ingest` 后的 `metrics`。
- ac-location-scope: `CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`；其它目录出现即判失败（`check-ios-shell.sh --self-test` 保留该反例并通过）。App import 允许表仍为 SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore，不新增其它系统框架。
- ac-harness-intact: `ios/PurePace/Harness/` 七个文件仍存在且行为不变，`--harness direct|corelocation|resume` 的 launch-arg 路径仍可用；Harness 清单与「无夹具引用」断言保留。
- ac-gates-preserved: `.munk/code-gates.json` 原有 22 个门 id 全部保留（只增不减、command 仍为单一 argv）；`bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 全部退出 0。
- ac-gates-green: `bash scripts/check-ios-shell.sh`（lint-ios-shell）、`bash scripts/build-ios.sh`（build-ios）、`bash scripts/test-ios.sh`（test-ios）均退出 0；`.munk/code-gates.json` 门 id 集合仍为既有 22 个；`swift test --package-path ios/RunCore` 与 `swift test --package-path ios/Core` 不回归。
- ac-ui-flow-e2e: `bash scripts/test-ios.sh` 在 iPhone 16 / iOS 18.6 模拟器真实 `simctl location` 注入下，XCUITest 依次断言：开始时距离与时长从零起、运行时二者发生变化、暂停后 4 秒内距离文本不变且当前配速为空、恢复后距离再次增长、结束后出现 `run.saved`、History 出现且仅出现 1 条记录；全程不存在的样例卡片、不使用固定 `sleep` 作为成功判据。
- ac-auth-tolerated: 定位授权弹窗在「首次未授权」与「已授权」两种初始状态下，UI 测试均能继续到真实数据增长，不因系统弹窗失败。

## 非目标

- 不做 GPX 文件导出、系统分享面板，也不在 App 内调用 `RunGPXExporter`（波 2）。
- 不做地图、轨迹折线、轨迹摘要卡片与采样点回放；详情页不渲染 `record.samples`。
- 不做删除/编辑/重命名记录、分页/筛选/搜索、跨天分组、浮动详情动画或自定义视觉主题。
- 不做每公里播报开关、真实 TTS 播放与 AudioSession 接线（波 2）；本阶段不新增 Settings 持久化偏好。
- 不做 `scripts/verify-ios-ui-e2e.sh` 与新增端到端门禁（波 3）；只保证既有 `test-ios` 门绿。
- 不改 `ios/RunCore`、`ios/Core`、`ios/PurePace/Harness/` 的源码与契约；不改 Android、`shared/`、`.github/workflows/*`；不推 tag、不动 Release。
- 不做视觉设计系统 / 自定义 token / 主题；沿用系统语义色、系统控件与 Dynamic Type。
- 不做真机验证、锁屏连续定位、音乐 duck 与 TTS 实听（`pending: 待人现场`）。

## 实现约束

- 复用优先：`RunSessionOrchestrator` / `RunCheckpointStore` / `RunArchiveStore` / `RunRecord` / `RunMetrics` 为既有公开契约，直接使用，不改 `project.yml` 依赖。
- 视图零逻辑：`View` 只做绑定与格式化；格式化放 `RunFormatting` 纯函数，在 `PurePaceTests` 直接断言，不写进 `RunCore`。
- 时间来源：编排器动作一律传 `Date`；UI 时长只能随 `ingest` 后的 `metrics.elapsed` 变化，禁止 `Timer` 自增或伪造空闲变化（`check-ios-shell.sh` 对 `ios/PurePace/Run` 断言无 `Timer`/`DispatchQueue.asyncAfter`/`CADisplayLink`）。
- 存储路径：归档与 checkpoint 放 App 沙盒（`Documents/Runs/`、`Caches/` 下 JSONL），`URL` 由 `FileManager` 构造并由 ViewModel 注入，生产代码不留硬编码绝对路径，测试用临时目录断言。
- 定位注入是 XCUITest 唯一真实链路：`scripts/test-ios.sh` 选 UDID 并 boot，`xcrun simctl location start --speed=3 --interval=1 <p1> <p2>`（航点总长 ≥ 20 km）后跑 `xcodebuild test`，`trap` 中 `simctl location clear`；禁止用 `--harness direct --stream` 假流替代。
- 授权处理：测试内用 SpringBoard 弹窗或 interruption monitor 点击「使用 App 期间允许」；弹窗缺失时继续执行而非失败。
- 无障碍标识为稳定测试契约：`run.distance`、`run.elapsed`、`run.currentPace`、`run.averagePace`、`run.splits`、`run.start`、`run.pause`、`run.resume`、`run.finish`、`run.saved`、`history.empty`、`history.runAgain`、`history.row`、`runDetail.root`、`runDetail.startedAt`、`runDetail.endedAt`、`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.splits`（含分段条数摘要）、`runDetail.splitRow`、`runDetail.splitsEmpty`；标识写成字符串字面量，距离文本含单位可比较字符串变化，配速空态用固定占位（`RunFormatting.emptyPace` = `--`）。
- 详情导航与数据源：用视图式 `NavigationLink { RunDetailView(record:) } label: { row }`，不要求 `RunRecord` 新增 `Hashable`；详情只读 `record.startedAt` / `endedAt` / `distance` / `activeDuration` / `splits`，平均配速只 `RunPace(distance:duration:)`、分段配速只 `split.pace`，禁止 App 侧重算距离、重切分段或按 elapsed 自造数值。
- 门禁写法：不新增门、不改 `.munk/code-gates.json`；`check-ios-shell.sh` 保持真实脚本断言（`grep -Fq 'xcodebuild test'` 等）并保留 `--self-test` 反例自检，`Location/` 加入 import 允许表并补「其它目录出现 CoreLocation 判失败」反例。
- 证据口径：只写「模拟器链路通过」「代码层断言通过」，不得出现「真机已验证」「阶段 2/3 已通过」。

## 最近交付证明

- workItemId: wi_ws_ea354771cc07f1ba（2026-11-09，pass）
- 交付：History 每行补平均配速（`RunPace(distance:duration:)` 派生、`RunFormatting.paceText` 格式化、`nil` 回退 `RunFormatting.emptyPace`），并新增 `History/RunDetailView.swift` + `History/RunDetailContent.swift` 跑次详情（起止时间、距离、活跃时长、平均配速、全部分段序号 + 配速；`splits` 空显示 `runDetail.splitsEmpty`）；`RunDetailContent` 为纯展示映射，视图零逻辑，列表与详情同源不引入第二套计算。
- 契约与测试同步：`check-ios-shell.sh` 文件/标识/测试落点清单纳入两个新文件与 `runDetail.*` 稳定标识（门禁 9 项断言 0 失败；`--self-test` 18 项断言 0 失败、退出 0）；`RunFormattingTests` 扩配速/分段文本，新增 `RunDetailContentTests`（4 例），`RunFlowUITests` 单一真实链路补「行含配速 → 点击详情 → 起止时间 + 分段区域与摘要条数一致」；`Run/`、`ios/RunCore`、`ios/Core` 未改。
- 实测：`code_gates` 22 门全绿（attempt 003，含 `lint-ios-shell` / `build-ios` / `test-ios`）；`test-ios` 下 `PurePaceTests` 40 例 + `RunFlowUITests` 1 例全通过，`swift test` RunCore 123 例、Core 全通过。结论口径：模拟器链路通过、代码层断言通过；真机、锁屏连续定位、音乐 duck 与 TTS 实听仍为 `pending: 待人现场`。
