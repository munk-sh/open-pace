# Domain: ios-app

PurePace iOS App 运行域：把 `ios/PurePace` 从空壳占位页换成真实跑步单页——Run / History / Settings 三 Tab、`CLLocationManager` 真实定位数据源、`RunSessionOrchestrator` 驱动的会话 ViewModel、真实归档历史与带真实播报偏好开关的设置页、`AVSpeechSynthesizer` 每公里语音播报，并用 `xcrun simctl location` 注入的真实 CoreLocation 更新跑通 XCUITest。App 侧只做接线与展示，距离/时长/配速/分段与播报调度一律来自 `PurePaceRunCore` 既有契约，不重写 RunCore、不自建计时器或距离公式。

## 范围

- `ios/PurePace/ContentView.swift`：`TabView` 收敛为 Run / History / Settings 三项（`Log` 删除）；非 Harness 启动直落 Run 页，0 秒可用，无登录/引导/样例加载。
- `ios/PurePace/Location/RunLocationSource.swift`：`CLLocationManager` 唯一 App 侧采点入口（`.fitness` / `desiredAccuracyBest` / `distanceFilter = kCLDistanceFilterNone` / `pausesLocationUpdatesAutomatically = false` / 不自动暂停）；`.notDetermined` 时请求「使用期间」授权，授权后自动继续，拒绝时显示诚实等待态。
- `ios/PurePace/Run/`：`RunSessionViewModel`（主线程可观测，持有 `RunSessionOrchestrator` + `RunCheckpointStore` + `RunArchiveStore` + 播报器，delegate 采样 → `ingest`，start/pause/resume/finish → 编排器动作，`RunSessionUpdate.announcements` 逐条转播报器，播报开关经 `setAnnouncementsEnabled` 同步编排器）、`RunView` 单页 UI（距离、活跃时长、当前/平均配速、已完成分段数 + 开始/暂停/恢复/结束互斥按钮 + 结束「已保存」反馈）、`RunFormatting` 纯函数格式化、`RunStorage` 沙盒路径（`Documents/Runs/` 归档 + `Caches/` checkpoint，路径由 ViewModel 注入）。
- `ios/PurePace/History/HistoryView.swift`：读 `RunArchiveStore.list()`，空态 `history.empty` + 「去跑一次」入口；有记录按 `startedAt` 倒序展示真实日期/距离/时长。
- `ios/PurePace/Settings/AnnouncementSettingsStore.swift`：`@MainActor final class ... : ObservableObject`，构造注入 `UserDefaults`（默认 `.standard`），单一常量键 + 默认 `true`，`isEnabled` / `setEnabled(_:)` 读写同一键。
- `ios/PurePace/Settings/SettingsView.swift`：渲染真实「每公里语音播报」`Toggle`（无障碍标识 `settings.announcementToggle`），无「暂无可配置项」/`settings.empty`，无示例数值与 `Stepper`/`Slider`。
- `ios/PurePace/Audio/AnnouncementSpeaker.swift`：`AnnouncementSpeaking` 协议 + `SpeechSynthesizing` 最小合成接缝 + `SpeechAnnouncementSpeaker`（`AVSpeechSynthesizer` + 既有 `AudioSessionAdapter`）；顺序固定「激活会话 → 一次 speak → 结束/取消回调停用」，文案为仅依赖 Foundation 的纯函数（含公里序号与用时）。
- `ios/PurePaceTests/`：`RunSessionViewModelTests`（编排器一致性、暂停冻结、恢复锚点、结束单条归档、播报开关关断零播报/重开不补播）、`RunFormattingTests`、`AnnouncementSettingsStoreTests`（默认开启、持久化、键唯一）、`AnnouncementSpeakerTests`（speak 次数/文案、会话激活停用序列、取消路径、无命令零调用）；`ios/PurePaceUITests/RunFlowUITests.swift`：真实定位注入下的全流程断言 + Settings 开关可见与重启保持。
- `scripts/check-ios-shell.sh`：真实 UI 结构断言（文件清单含两个新源文件与两个新测试文件、无障碍标识含 `settings.announcementToggle`、History/Settings 诚实态、无 `shared/fixtures|.gpx|.tcx`、Run 无 `Timer` 假计时、Settings 必须有 `Toggle` 且禁止示例数值与 `Stepper`/`Slider`）+ `CoreLocation` 仅 `Harness/` 与 `Location/` 双作用域正负反例 + Settings 断言正负自检。
- `scripts/test-ios.sh`：测试前 boot iPhone 16 / iOS 18.6 并 `xcrun simctl location start --speed=3 --interval=1` 注入 ≥20 km 直线航点，`trap` 收尾 `clear`；设备/runtime 缺失显式失败。

## 验收

- ac-tabs-converged: 非 Harness 启动时 Tab 栏恰为 Run / History / Settings 三项，`Log` Tab 不再存在。
- ac-live-metrics-from-orchestrator: 注入 N 条采样后，ViewModel 对外暴露的距离 / 时长 / 平均配速 / 当前配速 / 分段数与同一批采样喂给 `RunSessionOrchestrator` 得到的 `metrics` 逐字段相等；未开始时距离为 0、当前与平均配速均为空。
- ac-pause-zero-growth: 进入暂停后继续摄入时间递增且位移非零的采样，距离与活跃时长均保持不变，当前配速为空。
- ac-resume-continues: 恢复后的首条采样只重建位置锚点、不跨越暂停空档累计位移；其后的采样继续使距离与活跃时长单调增长。
- ac-finish-single-archive: 结束一次跑次后 `RunArchiveStore.list()` 恰返回 1 条且字段来自本次会话；对同一会话重复调用结束（含视图重复点击）不新增记录、`list()` 仍为 1 条。
- ac-saved-feedback: 结束成功后 UI 出现可被无障碍标识定位的「已保存」反馈（`run.saved`）；未结束时该元素不存在。
- ac-history-honest: 归档目录为空时 History 显示空态（`history.empty`）且不渲染任何示例跑次；存在归档时按 `startedAt` 倒序渲染真实日期 / 距离 / 时长，条数与 `RunArchiveStore.list()` 一致。
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
- ac-no-fake-data: App 源码不含内置坐标序列、fixture 引用或 GPX/TCX 样例文件路径，也不存在以固定步长递增距离或用定时器伪造时长的逻辑（源码中不得出现 `.gpx` / `.tcx` 字面量）；距离与时长只能来自 `ingest` 后的 `metrics`。
- ac-location-scope: `CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`；其它目录出现即判失败（`check-ios-shell.sh --self-test` 保留该反例并通过）。App import 允许表仍为 SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore，不新增其它系统框架。
- ac-harness-intact: `ios/PurePace/Harness/` 七个文件仍存在且行为不变，`--harness direct|corelocation|resume` 的 launch-arg 路径仍可用；Harness 清单与「无夹具引用」断言保留。
- ac-gates-preserved: `.munk/code-gates.json` 原有 22 个门 id 全部保留（只增不减、command 仍为单一 argv）；`bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 全部退出 0。
- ac-ui-flow-e2e: `bash scripts/test-ios.sh` 在 iPhone 16 / iOS 18.6 模拟器真实 `simctl location` 注入下，XCUITest 依次断言：开始时距离与时长从零起、运行时二者发生变化、暂停后 4 秒内距离文本不变且当前配速为空、恢复后距离再次增长、结束后出现 `run.saved`、History 出现且仅出现 1 条记录；全程不存在的样例卡片、不使用固定 `sleep` 作为成功判据。
- ac-auth-tolerated: 定位授权弹窗在「首次未授权」与「已授权」两种初始状态下，UI 测试均能继续到真实数据增长，不因系统弹窗失败。

## 非目标

- 不做历史详情页、分段详情、轨迹摘要与地图（波 2）。
- 不做 GPX 文件导出、系统分享面板，也不在 App 内调用 `RunGPXExporter`（波 2）。
- 不做播报语速 / 音量 / 语言 / 音色设置 UI，不做 TTS 试听按钮；文案与语音参数沿用系统默认。
- 不做暂停播报、结束播报、整公里合并播报等新调度语义，也不做后台 / 锁屏播报与音频中断恢复后的重播策略（沿用既有编排器与调度器规则，App 侧不自建）。
- 不做 `scripts/verify-ios-ui-e2e.sh` 与新增端到端门禁（波 3）；只保证既有 `test-ios` 门绿。
- 不改 `ios/RunCore`、`ios/Core`、`ios/PurePace/Harness/` 的源码与契约；不改 Android、`shared/`、`.github/workflows/*`；不推 tag、不动 Release。
- 不做视觉设计系统 / 自定义 token / 主题；沿用系统语义色、系统控件与 Dynamic Type。
- 不做真机验证、锁屏连续定位、音乐 duck 与 TTS 实听（`pending: 待人现场`）。

## 实现约束

- 复用优先：`RunSessionOrchestrator` / `RunCheckpointStore` / `RunArchiveStore` / `RunRecord` / `RunMetrics` 为既有公开契约，直接使用，不改 `project.yml` 依赖。
- 视图零逻辑：`View` 只做绑定与格式化；格式化放 `RunFormatting` 纯函数，在 `PurePaceTests` 直接断言，不写进 `RunCore`。
- 时间来源：编排器动作一律传 `Date`；UI 时长只能随 `ingest` 后的 `metrics.elapsed` 变化，禁止 `Timer` 自增或伪造空闲变化（`check-ios-shell.sh` 对 `ios/PurePace/Run` 断言无 `Timer`/`DispatchQueue.asyncAfter`/`CADisplayLink`）。
- 存储路径：归档与 checkpoint 放 App 沙盒（`Documents/Runs/`、`Caches/` 下 JSONL），`URL` 由 `FileManager` 构造并由 ViewModel 注入，生产代码不留硬编码绝对路径，测试用临时目录断言。
- 播报偏好：键名只在 `AnnouncementSettingsStore` 内单点定义（单一常量键，默认 `true`），`UserDefaults` 构造注入（测试用独立 suite 并自行清理）；`ContentView` 用 `@StateObject` 持有并注入 `RunSessionViewModel` / `SettingsView`，以 `.onChange(of:)` 调 `runModel.setAnnouncementsEnabled(_:)`，不引入 Combine。
- 播报器接缝：`SpeechAnnouncementSpeaker` 持有可注入的 `AudioSessionAdapter`（测试传 `observesInterruptions: false`）与 `SpeechSynthesizing`；顺序固定 `beginAnnouncement()` → 一次 `speak` → 结束/取消回调 `endAnnouncement()`；会话调用抛错即吞掉并继续（不打断跑次、不重复停用）；`ViewModel.finish()` 路径不额外播报。
- 定位注入是 XCUITest 唯一真实链路：`scripts/test-ios.sh` 选 UDID 并 boot，`xcrun simctl location start --speed=3 --interval=1 <p1> <p2>`（航点总长 ≥ 20 km）后跑 `xcodebuild test`，`trap` 中 `simctl location clear`；禁止用 `--harness direct --stream` 假流替代。
- 授权处理：测试内用 SpringBoard 弹窗或 interruption monitor 点击「使用 App 期间允许」；弹窗缺失时继续执行而非失败。
- 无障碍标识为稳定测试契约：`run.distance`、`run.elapsed`、`run.currentPace`、`run.averagePace`、`run.splits`、`run.start`、`run.pause`、`run.resume`、`run.finish`、`run.saved`、`history.empty`、`history.row`、`settings.announcementToggle`；距离文本含单位可比较字符串变化，配速空态用固定占位（如 `--`），开关值断言用 `value as? String` 的 `"1"`/`"0"`。
- 门禁写法：不新增门；`check-ios-shell.sh` 保持真实脚本断言（`grep -Fq 'xcodebuild test'` 等），`Location/` 加入 import 允许表并补「其它目录出现 CoreLocation 判失败」反例；Settings 段改为「必须有 `Toggle` + `settings.announcementToggle`、禁止示例数值与 `Stepper`/`Slider`」并补对应正负自检。
- 证据口径：只写「模拟器链路通过」「代码层断言通过」，不得出现「真机已验证」「阶段 2/3 已通过」。

## 最近交付证明

- workItemId: wi_ws_83cc527f6e15a8eb（2026-11-09，pass）
- 交付：波 1 遗留的两处空白补齐——新增 `Settings/AnnouncementSettingsStore.swift`（`UserDefaults` 单键偏好，默认开启、重启保持）与 `Audio/AnnouncementSpeaker.swift`（`AVSpeechSynthesizer` + 既有 `AudioSessionAdapter`，固定「激活 → 一次 speak → 结束/取消停用」，文案为纯函数短句）；`SettingsView` 由「暂无可配置项」改为真实 `settings.announcementToggle` 开关；`RunSessionViewModel` 逐条转发 `RunSessionUpdate.announcements` 并透传 `setAnnouncementsEnabled`；`ContentView` 以 `@StateObject` 装配 + `.onChange` 同步开关（未引入 Combine）。
- 门禁与测试同步：`check-ios-shell.sh` Settings 段改为断言真实 `Toggle` + 标识、禁止「暂无可配置项」/示例数值/`Stepper`/`Slider`，`live_sources` 与 `unit_tests` 纳入两个新源文件与两个新测试文件，`--self-test` 补 1 正 3 负反例；`AnnouncementSettingsStoreTests`、`AnnouncementSpeakerTests` 新增，`RunSessionViewModelTests` 补关断零播报/重开不补播/暂停结束静默，`RunFlowUITests` 补开关可见 + terminate/launch 保持。`ios/RunCore`、`ios/Core` 与 import 允许表零改动。
- 实测：`code_gates` 22 门全绿（attempt 001，含 `lint-ios-shell` / `build-ios` / `test-ios`），门 id 与 command 逐字未变。结论口径：配置与调度契约通过、代码层断言通过；TTS 实听、音乐 duck 恢复、真机与锁屏连续播报仍为 `pending: 待人现场`。
