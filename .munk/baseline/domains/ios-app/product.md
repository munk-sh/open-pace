# Domain: ios-app

PurePace iOS App 运行域：把 `ios/PurePace` 从空壳占位页换成真实跑步单页——Run / History / Settings 三 Tab、`CLLocationManager` 真实定位数据源、`RunSessionOrchestrator` 驱动的会话 ViewModel、真实归档历史（行配速 + 跑次详情）、带真实播报偏好开关的设置页与 `AVSpeechSynthesizer` 每公里语音播报，并用 `xcrun simctl location` 注入的真实 CoreLocation 更新跑通 XCUITest。App 侧只做接线与展示，距离/时长/配速/分段与播报调度一律来自 `PurePaceRunCore` 既有契约，不重写 RunCore、不自建计时器或距离公式。

## 范围

- `ios/PurePace/ContentView.swift`：`TabView` 收敛为 Run / History / Settings 三项（`Log` 删除）；非 Harness 启动直落 Run 页，0 秒可用，无登录/引导/样例加载；`@StateObject` 持有播报偏好存储并注入两个子页面。
- `ios/PurePace/Location/RunLocationSource.swift`：`CLLocationManager` 唯一 App 侧采点入口（`.fitness` / `desiredAccuracyBest` / `distanceFilter = kCLDistanceFilterNone` / `pausesLocationUpdatesAutomatically = false` / 不自动暂停）；授权与采集经可注入 seam（`RunLocationManaging` / `RunLocationManagerHandler`，生产实现 `SystemLocationManager` 包装真实 `CLLocationManager`，测试注入桩）；`.notDetermined` 时请求「使用期间」授权，已 WhenInUse 时再发起一次「始终允许」升级请求；跑步进行态置 `allowsBackgroundLocationUpdates = true` 并在结束/停止/失权时复位为 `false`；`WhenInUse` 降级态由 `authorization.backgroundCapable == false` + `backgroundDegradationHint` 明示，拒绝时显示诚实等待态。
- `ios/PurePace/Run/`：`RunSessionViewModel`（主线程可观测，持有 `RunSessionOrchestrator` + `RunCheckpointStore` + `RunArchiveStore` + 播报器，delegate 采样 → `ingest`，start/pause/resume/finish → 编排器动作，`RunSessionUpdate.announcements` 逐条转播报器，播报开关经 `setAnnouncementsEnabled` 同步编排器）、`RunView` 单页 UI（距离、活跃时长、当前/平均配速、已完成分段数 + 开始/暂停/恢复/结束互斥按钮 + 结束「已保存」反馈）、`RunFormatting` 纯函数格式化、`RunStorage` 沙盒路径（`Documents/Runs/` 归档 + `Caches/` checkpoint，路径由 ViewModel 注入）。
- `ios/PurePace/History/HistoryView.swift`：读 `RunArchiveStore.list()`，空态 `history.empty` + `history.runAgain` 入口；有记录按 `startedAt` 倒序展示真实日期/距离/时长，并补本行平均配速（只由 `RunPace(distance:duration:)` 从 `record.distance` + `record.activeDuration` 派生，`RunFormatting.paceText` 格式化，派生为 `nil` 时用 `RunFormatting.emptyPace`）；行可点击进入详情。
- `ios/PurePace/History/RunDetailView.swift` + `RunDetailContent.swift`：行点击进入的跑次详情（起止时间、总距离、活跃时长、平均配速、全部分段序号 + 分段配速）；`RunDetailContent` 只把被点击的 `RunRecord`（含 `splits`）映射为展示字符串与分段行数组，视图零逻辑，`splits` 为空时显示 `runDetail.splits` 标题 + `runDetail.splitsEmpty` 诚实空态。
- `ios/PurePace/History/RunExportState.swift` + `RunDetailView.swift` 导出区：`RunExportState` 只调用注入的 `RunGPXExporter.export(record)` 把该跑次归档中的真实 `RunRecord.samples` 写成 `.gpx`，落盘后校验扩展名 `.gpx` 且文件真实存在、字节数 > 0，成功才暴露 `.exported(url)`；视图仅绑定「导出 GPX」按钮（`runDetail.export`）、成功态文本（`runDetail.exported`，含文件名）、`ShareLink`（`runDetail.share`）与失败态（`runDetail.exportFailed`），不拼 GPX 内容、不注册清理动作、不引入 UIKit。
- `ios/PurePace/Run/RunStorage.swift`：新增 `documentsDirectory` / `exportDirectory`（App 沙盒 `Documents/Exports/`）/ `makeExporter`，目录一律由可注入 `FileManager` 推导，不写死绝对路径；`makeStores` 额外返回 `exporter`，经 `ContentView` → `HistoryView` → `RunDetailView(record:exporter:)` 注入。
- `ios/PurePace/Settings/AnnouncementSettingsStore.swift`：`@MainActor final class ... : ObservableObject`，构造注入 `UserDefaults`（默认 `.standard`），单一常量键 + 默认 `true`，`isEnabled` / `setEnabled(_:)` 读写同一键。
- `ios/PurePace/Settings/SettingsView.swift`：渲染真实「每公里语音播报」`Toggle`（无障碍标识 `settings.announcementToggle`），无「暂无可配置项」/`settings.empty`，无示例数值与 `Stepper`/`Slider`。
- `ios/PurePace/Audio/AnnouncementSpeaker.swift`：`AnnouncementSpeaking` 协议 + `SpeechSynthesizing` 最小合成接缝 + `SpeechAnnouncementSpeaker`（`AVSpeechSynthesizer` + 既有 `AudioSessionAdapter`）；顺序固定「激活会话 → 一次 speak → 结束/取消回调停用」，文案为仅依赖 Foundation 的纯函数（含公里序号与用时）。
- `ios/PurePaceTests/`：`RunSessionViewModelTests`（编排器一致性、暂停冻结、恢复锚点、结束单条归档、播报开关关断零播报/重开不补播/暂停结束静默）、`RunLocationSourceTests`（注入 `RunLocationManaging` 桩驱动授权迁移、跑步态后台开关、Always 升级一次性、降级提示、后台恢复 ingest 连续性、bundle 内 `UIBackgroundModes` 读回）、`RunFormattingTests`（格式化纯函数，含配速/分段文本）、`RunDetailContentTests`（`RunRecord` → 详情展示映射与分段行）、`RunExportStateTests`（临时目录真实落盘、`.gpx` 回读逐点对齐、重复导出不覆盖、空采样失败不新增文件、`Documents/Exports` 目录推导）、`AnnouncementSettingsStoreTests`（默认开启、持久化、键唯一）、`AnnouncementSpeakerTests`（speak 次数/文案、会话激活停用序列、取消路径、无命令零调用）；`ios/PurePaceUITests/RunFlowUITests.swift`：真实定位注入下的全流程断言（含 History 行配速 → 详情 → 起止时间与分段区域 → 导出 → 完成态/分享入口）与 Settings 开关可见 + 重启保持。
- `scripts/check-ios-shell.sh`：真实 UI 结构断言（文件清单含全部真实源文件与测试落点、无障碍标识清单、History/Settings 诚实态、Run 无 `Timer` 假计时、Settings 必须有 `Toggle` 且禁止示例数值与 `Stepper`/`Slider`、导出必须经 `RunGPXExporter` 且目录由 `RunStorage` 构造、App 源码仅禁 `shared/fixtures`/样例引用与 `.tcx`）+ `validate_no_fixture_data` 正负自检（`.gpx` 扩展名字面量合法，引用夹具即失败）+ `CoreLocation` 仅 `Harness/` 与 `Location/` 双作用域正负反例 + Settings 断言正负自检 + `validate_location_config` 增加非空 `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription` 断言 + `validate_background_location_source` 断言后台开关置位/复位、Always 升级、`backgroundCapable`、`backgroundDegradationHint` 与 `run.backgroundDegraded`（各带单点破坏反例自检）。
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
- ac-export-writes-real-file: 以临时目录注入导出目录后，对含非空 `samples` 的 `RunRecord` 执行导出，返回 URL 在磁盘上真实存在、扩展名为 `.gpx`、字节数 > 0，且 `GPXCodec.read(from:)` 回读的点位数量与时间戳序列与 `record.samples` 完全一致。
- ac-export-no-overwrite: 同一 `RunRecord` 连续导出两次返回两个不同路径，两个文件同时存在，首次导出的文件内容回读仍与原始采样一致（未被覆盖）。
- ac-export-empty-samples-fails: `samples` 为空的记录导出抛错，且导出目录中不新增任何 `.gpx` 文件；详情页对应展示失败态标识 `runDetail.exportFailed` 且不出现 `runDetail.share`。
- ac-export-dir-documents-exports: 未注入目录时 `RunStorage` 构造的导出目录等于注入 `FileManager` 的 `Documents/Exports`（用临时目录伪造 `.documentDirectory` 断言），源码中不出现写死的绝对路径。
- ac-share-after-landing: 导出成功后详情页出现导出完成态 `runDetail.exported`（文本含导出文件名且以 `.gpx` 结尾）与分享入口 `runDetail.share`；未导出成功时这两个标识都不存在（分享入口严格晚于落盘）。
- ac-no-fixture-no-network: 导出链路不读取 `shared/fixtures`/内置样例、不用内存字符串直接当文件返回、不使用网络（App 源码无 `URLSession`/`Network` import）；App import 允许表不新增 UIKit。
- ac-xcuitest-export: 真实跑次详情页点击 `runDetail.export` 后，`runDetail.exported` 出现且文件名以 `.gpx` 结尾、`runDetail.share` 存在；若系统分享面板出现则额外确认，不作为唯一判据（不使用固定 `sleep`）。
- ac-no-recompute-no-sample: App 源码中详情/列表的距离、时长、配速与分段全部来自 `RunRecord` 字段与 `RunFormatting`；不出现自建距离公式、`Ingest`/`RunMetricsEngine` 调用、内置坐标序列、`shared/fixtures` 或样例跑次引用；`.gpx` 仅作为真实导出目标的扩展名/文件名校验出现，不得用于夹具路径。
- ac-settings-toggle-default-on: 从未写入过偏好键的全新 `UserDefaults` 域构造 `AnnouncementSettingsStore` 时 `isEnabled == true`；`SettingsView` 渲染 `Toggle` 且其无障碍标识为 `settings.announcementToggle`，初始值与存储值一致。
- ac-settings-toggle-persists: 置关闭后用同一 `UserDefaults` 域新建存储实例读回关闭；再置开启读回开启；写入固定为单一常量键，不额外写入其它键。
- ac-settings-honest-copy: App 源码不再出现「暂无可配置项」与 `settings.empty` 标识；Settings 页除该真实播报开关外不含示例数值、内置样例与 `Stepper`/`Slider`（由 `check-ios-shell.sh` 静态断言兜底）。
- ac-speaker-one-speak-per-command: 对一条 `AnnouncementCommand`（`trigger == .kilometerCompleted`、`splitIndex == 1`）播报器恰好调用一次 `speak`，文案包含该公里序号；重复投递同一条命令不多出第二条语音。
- ac-speaker-session-sequence: 每条播报的平台调用序列为「激活 → 一次 `speak` → 语音结束/取消回调 → 停用」：激活阶段 spy 记录 `setCategory(.playback, .spokenAudio, [.duckOthers, .mixWithOthers])` 且随后一次 `setActive(true)`；结束回调后恰好一次 `setActive(false, [.notifyOthersOnDeactivation])`；`didCancel` 同样触发停用；无命令时不产生任何音频会话调用。
- ac-announcement-off-zero-speak: 编排器播报关闭时跨整公里摄入采样，ViewModel 侧 `speak` 调用数为 0 且音频会话激活调用数为 0。
- ac-toggle-immediate-no-backfill: 运行中关闭开关后跨下一个整公里 `speak` 数为 0；重新开启不补播被抑制的公里；再跨下一个整公里恰好一次 `speak`，`splitIndex` 为最新公里。
- ac-pause-finish-silent: 暂停期间摄入采样不触发 `speak`；结束动作不触发 `speak`（编排器不对外返回收尾命令）；View 层不自行发起播报。
- ac-no-duplicated-run-logic: App 侧不新增公里判定、计时或播报去抖逻辑，`speak` 只由 `RunSessionUpdate.announcements` 驱动（`ios/PurePace/Run` 仍无 `Timer` / `DispatchQueue.asyncAfter` / `CADisplayLink`）；`ios/RunCore` 无源码改动。
- ac-audio-scope-preserved: `AVFoundation` 仍只出现在 `ios/PurePace/Audio/`；App import 允许表不变（SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore），不新增 `Speech` 等框架；`check-ios-shell.sh --self-test` 的 AVFoundation 越界反例仍判失败。
- ac-ui-toggle-restart: XCUITest 在 Settings Tab 断言 `settings.announcementToggle` 存在且可点击；翻转开关后 `terminate()` + `launch()`，再次进入 Settings 断言开关值与翻转后一致（用 `waitForExistence` 等待，不以固定 `sleep` 作判据）。
- ac-shell-gate-updated: `bash scripts/check-ios-shell.sh` 断言 Settings 源码含 `Toggle` 与 `settings.announcementToggle`、不含「暂无可配置项」、不含示例数值与 `Stepper`/`Slider`；`live_sources` 含 `Settings/AnnouncementSettingsStore.swift` 与 `Audio/AnnouncementSpeaker.swift`，`unit_tests` 含两个新测试文件；`--self-test` 含 Settings 断言的正负反例且全部通过。
- ac-shell-gate-synced: `scripts/check-ios-shell.sh` 的 `live_sources` 含 `RunDetailView.swift`、`RunDetailContent.swift`、`RunExportState.swift`，标识断言覆盖 `history.row`、`runDetail.root` / `startedAt` / `endedAt` / `distance` / `activeDuration` / `averagePace` / `splits` / `splitRow` / `splitsEmpty` / `export` / `exported` / `share` / `exportFailed`；单元测试落点清单含 `RunExportStateTests`，UI 测试标识清单同步扩展；`--self-test` 仍退出 0。
- ac-shell-export-positive: `check-ios-shell.sh` 正向断言 `RunStorage` 以 `RunGPXExporter(directoryURL: exportDirectory` 统一构造导出器、`RunExportState` 走 `exporter.export(record)` 且含 `isLandedGPXFile` 落盘校验、`ContentView` 注入 `stores.exporter`、`HistoryView` 以 `exporter: exporter` 透传；原「App 源码出现 `.gpx` 即失败」收窄为 `validate_no_fixture_data`（仅禁 `shared/fixtures` / `sample*.gpx` / `.tcx`），并用正例（合法 `.gpx` 扩展名）+ 反例（引用夹具路径）自检，未退化为通配放宽。
- ac-no-fake-data: App 源码不含内置坐标序列、fixture 引用或 GPX/TCX 样例文件路径，也不存在以固定步长递增距离或用定时器伪造时长的逻辑（`.tcx` 与 `sample*.gpx` 字面量仍禁止；裸 `.gpx` 扩展名合法）；距离与时长只能来自 `ingest` 后的 `metrics`，导出文件只能来自真实归档采样。
- ac-location-scope: `CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`；其它目录出现即判失败（`check-ios-shell.sh --self-test` 保留该反例并通过）。App import 允许表仍为 SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore，不新增其它系统框架。
- ac-harness-intact: `ios/PurePace/Harness/` 七个文件仍存在且行为不变，`--harness direct|corelocation|resume` 的 launch-arg 路径仍可用；Harness 清单与「无夹具引用」断言保留。
- ac-gates-preserved: `.munk/code-gates.json` 原有 22 个门 id 全部保留（只增不减、command 仍为单一 argv）；`bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 全部退出 0。
- ac-gates-green: `bash scripts/check-ios-shell.sh`（lint-ios-shell）、`bash scripts/build-ios.sh`（build-ios）、`bash scripts/test-ios.sh`（test-ios）均退出 0；`.munk/code-gates.json` 门 id 集合仍为既有 22 个；`swift test --package-path ios/RunCore` 与 `swift test --package-path ios/Core` 不回归。
- ac-ui-flow-e2e: `bash scripts/test-ios.sh` 在 iPhone 16 / iOS 18.6 模拟器真实 `simctl location` 注入下，XCUITest 依次断言：开始时距离与时长从零起、运行时二者发生变化、暂停后 4 秒内距离文本不变且当前配速为空、恢复后距离再次增长、结束后出现 `run.saved`、History 出现且仅出现 1 条记录；全程不存在的样例卡片、不使用固定 `sleep` 作为成功判据。
- ac-auth-tolerated: 定位授权弹窗在「首次未授权」与「已授权」两种初始状态下，UI 测试均能继续到真实数据增长，不因系统弹窗失败。
- ac-plist-background-mode: `ios/PurePace/Info.plist` 与 `ios/project.yml` 都声明 background mode `location`；`check-ios-shell.sh` 的 `validate_location_config` 断言通过，缺 plist / 后台模式非 `location` / 用途说明为空的反例仍判失败。
- ac-bg-enabled-while-running: 会话进入跑步进行态（`start()` 后已授权）时，定位管理器 `allowsBackgroundLocationUpdates == true` 且 `pausesLocationUpdatesAutomatically == false`。
- ac-bg-disabled-after-stop: 调用 `stop()`（结束/停止）或授权失效后 `allowsBackgroundLocationUpdates == false`，且不再继续后台更新。
- ac-always-request-path: 授权为 `notDetermined` 时走 `requestWhenInUseAuthorization`；已 WhenInUse 且未获 Always 时走 `requestAlwaysAuthorization` 升级路径（同一实例只发起一次），且 `project.yml` 声明非空 `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription`。
- ac-wheninuse-degraded-visible: 仅授予 WhenInUse 时授权状态对外带降级标记（`backgroundCapable == false`），`backgroundDegradationHint` 非空，Run 页渲染 `run.backgroundDegraded` 提示；进程不 crash、不静默无提示。
- ac-auth-transitions-injectable: 注入 `RunLocationManaging` 桩可驱动授权变化，XCTest 覆盖 `notDetermined → authorizedWhenInUse → authorizedAlways` 与 `denied`/`restricted` 分支，每次变化都回调 delegate；生产默认使用真实 `CLLocationManager` 包装（`SystemLocationManager` 强引用 manager 且 delegate 绑定到自身）。
- ac-bg-ingest-continuous: 模拟锁屏/进后台/进程挂起后恢复（重叠时间窗与重复投递）时，ingest 最终样本无重复、无丢失段落，与既有 checkpoint 重启恢复结果一致；不重写持久化格式。
- ac-ios-local-gates-green: `bash scripts/build-ios.sh` + `bash scripts/test-ios.sh`（`xcodebuild build` / `xcodebuild test`）全绿并输出 `** TEST SUCCEEDED **`，`check-ios-shell.sh`、`check-ios-scripts.sh` 等 iOS 相关门全绿，`.munk/code-gates.json` 门数不减、既有门语义不放宽。
- ac-delivery-artifacts: Delivery 阶段产出候选 zip 与可执行 `sha256` 校验值，供真机硬门绑定（不构成真机验收结论）。

## 非目标

- 不做导出文件的**外部**解析验证（`xmllint` / 独立解析器）与模拟器容器内真实文件取证脚本（波 3「端到端脚本」）；只保证 App 内 `GPXCodec` 回读一致。
- 不做导出文件列表页、导出历史、删除/清理导出文件、批量导出、iCloud 或 AirDrop 专门适配；不引入 UIKit / `UIActivityViewController` / `UIDocumentPicker`，不替换成自定义分享 UI。
- 不改 RunCore 契约：`RunGPXExporter`、`RunRecordNaming`、`GPXCodec` 字段顺序与命名规则原样复用；不新增编码器、不在 App 侧重算或补造采样点。
- 不做地图、轨迹折线、轨迹摘要卡片与采样点回放；详情页不渲染 `record.samples`。
- 不做删除/编辑/重命名记录、分页/筛选/搜索、跨天分组、浮动详情动画或自定义视觉主题。
- 不做播报语速 / 音量 / 语言 / 音色设置 UI，不做 TTS 试听按钮；文案与语音参数沿用系统默认。
- 不做暂停播报、结束播报、整公里合并播报等新调度语义，也不做后台 / 锁屏播报与音频中断恢复后的重播策略（沿用既有编排器与调度器规则，App 侧不自建）。
- 不做 `scripts/verify-ios-ui-e2e.sh` 与新增端到端门禁（波 3）；只保证既有 `test-ios` 门绿。
- 不改 `ios/RunCore`、`ios/Core`、`ios/PurePace/Harness/` 的源码与契约；不改 Android、`shared/`、`.github/workflows/*`；不推 tag、不动 Release。
- 不做视觉设计系统 / 自定义 token / 主题；沿用系统语义色、系统控件与 Dynamic Type。
- 不做真机验证与真机锁屏连续定位验收（`pending: 待人现场`）；后台/Always 只交付代码层能力、配置声明与模拟器/单测断言，不写「真机后台定位可用」类结论。

## 实现约束

- 复用优先：`RunSessionOrchestrator` / `RunCheckpointStore` / `RunArchiveStore` / `RunRecord` / `RunMetrics` 为既有公开契约，直接使用，不改 `project.yml` 依赖。
- 视图零逻辑：`View` 只做绑定与格式化；格式化放 `RunFormatting` 纯函数，在 `PurePaceTests` 直接断言，不写进 `RunCore`。
- 时间来源：编排器动作一律传 `Date`；UI 时长只能随 `ingest` 后的 `metrics.elapsed` 变化，禁止 `Timer` 自增或伪造空闲变化（`check-ios-shell.sh` 对 `ios/PurePace/Run` 断言无 `Timer`/`DispatchQueue.asyncAfter`/`CADisplayLink`）。
- 存储路径：归档与 checkpoint 放 App 沙盒（`Documents/Runs/`、`Caches/` 下 JSONL），`URL` 由 `FileManager` 构造并由 ViewModel 注入，生产代码不留硬编码绝对路径，测试用临时目录断言。
- 播报偏好：键名只在 `AnnouncementSettingsStore` 内单点定义（单一常量键，默认 `true`），`UserDefaults` 构造注入（测试用独立 suite 并自行清理）；`ContentView` 用 `@StateObject` 持有并注入 `RunSessionViewModel` / `SettingsView`，以 `.onChange(of:)` 调 `runModel.setAnnouncementsEnabled(_:)`，不引入 Combine。
- 播报器接缝：`SpeechAnnouncementSpeaker` 持有可注入的 `AudioSessionAdapter`（测试传 `observesInterruptions: false`）与 `SpeechSynthesizing`；顺序固定 `beginAnnouncement()` → 一次 `speak` → 结束/取消回调 `endAnnouncement()`；会话调用抛错即吞掉并继续（不打断跑次、不重复停用）；`ViewModel.finish()` 路径不额外播报。
- 详情导航与数据源：用视图式 `NavigationLink { RunDetailView(record:exporter:) } label: { row }`，不要求 `RunRecord` 新增 `Hashable`；详情只读 `record.startedAt` / `endedAt` / `distance` / `activeDuration` / `splits`，平均配速只 `RunPace(distance:duration:)`、分段配速只 `split.pace`，禁止 App 侧重算距离、重切分段或按 elapsed 自造数值。
- 导出复用与薄层：导出必须走 `RunGPXExporter(directoryURL:).export(record)`，文件名/去重由 Core 的 `RunRecordNaming` 决定，App 侧不自造命名；导出目录只由 `RunStorage.exportDirectory(fileManager:)` 推导（`Documents/Exports/`），可注入 `FileManager` 指向临时目录；状态与落盘校验放 `RunExportState`（纯类型，可单测），`RunDetailView` 只做按钮绑定、`ShareLink(item:)` 渲染与状态展示，不在 View 内拼 GPX 内容。
- 定位注入是 XCUITest 唯一真实链路：`scripts/test-ios.sh` 选 UDID 并 boot，`xcrun simctl location start --speed=3 --interval=1 <p1> <p2>`（航点总长 ≥ 20 km）后跑 `xcodebuild test`，`trap` 中 `simctl location clear`；禁止用 `--harness direct --stream` 假流替代。
- 后台/Always 定位约束：授权请求与采集只经 `RunLocationManaging` seam（生产 `SystemLocationManager` 自任 delegate 并强引用 manager），测试注入桩；`allowsBackgroundLocationUpdates` 仅在跑步进行态为 `true`，`stop()`/失权必须复位为 `false`；`CoreLocation` 仍只允许出现在 `Harness/` 与 `Location/`；实机后台行为不在代码层承诺。
- 授权处理：测试内用 SpringBoard 弹窗或 interruption monitor 点击「使用 App 期间允许」；弹窗缺失时继续执行而非失败。
- 无障碍标识为稳定测试契约：`run.distance`、`run.elapsed`、`run.currentPace`、`run.averagePace`、`run.splits`、`run.start`、`run.pause`、`run.resume`、`run.finish`、`run.saved`、`history.empty`、`history.runAgain`、`history.row`、`runDetail.root`、`runDetail.startedAt`、`runDetail.endedAt`、`runDetail.distance`、`runDetail.activeDuration`、`runDetail.averagePace`、`runDetail.splits`（含分段条数摘要）、`runDetail.splitRow`、`runDetail.splitsEmpty`、`runDetail.export`、`runDetail.exported`（成功态文本含文件名）、`runDetail.share`、`runDetail.exportFailed`、`settings.announcementToggle`；标识写成字符串字面量，距离文本含单位可比较字符串变化，配速空态用固定占位（`RunFormatting.emptyPace` = `--`），开关值断言用 `value as? String` 的 `"1"`/`"0"`。
- 门禁写法：不新增门、不改 `.munk/code-gates.json`；`check-ios-shell.sh` 保持真实脚本断言（`grep -Fq 'xcodebuild test'` 等）并保留 `--self-test` 反例自检，`Location/` 加入 import 允许表并补「其它目录出现 CoreLocation 判失败」反例；Settings 段改为「必须有 `Toggle` + `settings.announcementToggle`、禁止示例数值与 `Stepper`/`Slider`」并补对应正负自检；夹具禁令抽为 `validate_no_fixture_data`（禁 `shared/fixtures` / `sample*.gpx` / `.tcx`，允许真实导出用 `.gpx` 扩展名）并补正反例，导出侧补「必须经 `RunGPXExporter`、目录由 `RunStorage` 构造」正向断言，不得退化为通配允许表。
- 证据口径：只写「模拟器链路通过」「代码层断言通过」，不得出现「真机已验证」「阶段 2/3 已通过」。

## 最近交付证明

- workItemId: wi_intake_6b267814f7d23323（2026-11-09，pass）
- 交付：`RunLocationSource` 拆出可注入 seam（`RunLocationManaging` / `RunLocationManagerHandler`，生产 `SystemLocationManager` 包装真实 `CLLocationManager` 并自任 delegate），跑步进行态 `beginUpdating()` 置 `allowsBackgroundLocationUpdates = true`，`endUpdating()`（stop / 失权）复位为 `false`；`start()` 在 `notDetermined` 请求 WhenInUse、已 WhenInUse 时每实例一次 `requestAlwaysAuthorization` 升级；`RunLocationAuthorization` 新增 `backgroundCapable` 与 `backgroundDegradationHint`，`RunView` 渲染 `run.backgroundDegraded` 提示；`project.yml` 补 `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription`，既有 `UIBackgroundModes: location` 保留。
- 门禁与测试同步：`check-ios-shell.sh` 新增 `validate_background_location_source`（后台开关置位/复位、Always 升级、`backgroundCapable`、`backgroundDegradationHint`、`run.backgroundDegraded`）+ 4 个单点破坏反例自检，`validate_location_config` 增加 Always 用途说明非空断言与空值反例，`unit_tests` 纳入 `RunLocationSourceTests`。新增 8 例：plist 后台模式读回、跑步态后台开关、stop/失权复位、notDetermined 先 WhenInUse、WhenInUse 升级一次性、授权迁移与降级提示、denied/restricted、后台恢复 ingest 无重复无丢段。
- 实测：`code_gates` 23 门全绿（含 `lint-ios-shell` / `build-ios` / `test-ios` / `test-ios-run-core`）；`test-ios` 单元 131 例 0 失败（含 8 例新增）+ UI 2 例通过、两段均 `** TEST SUCCEEDED **`；`ios/RunCore`、`ios/PurePace/Harness/` 与 import 允许表零改动，门数与 command 未变。结论口径：模拟器与代码层契约通过；真机锁屏连续定位、授权 Always 实机路径仍为 `pending: 待人现场`（未做真机验收）。
