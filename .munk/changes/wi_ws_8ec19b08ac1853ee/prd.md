# 无 UI 的 CoreLocation/直接流运行 Harness 与状态输出

## 范围

在已交付的 `ios/RunCore`（`PurePaceRunCore`）之上，为 App target 增加一个**仅由 launch arg 激活、无业务 UI** 的运行 Harness，把「采样来源 → 状态机/度量/播报/checkpoint」真正串起来，并把运行期事实写成稳定的机读 status JSON，供下游 `verify-ios-sim-runtime.sh` 直接断言：

1. `ios/PurePace/Harness/` 新增 Harness（薄平台适配 + 可单测的纯逻辑内核）：
   - launch arg 解析：`--harness direct|corelocation|resume` + `--status/--stream/--checkpoint/--max-duration`，无 `--harness` 时完全不激活；
   - 直接流模式：读取 JSONL 文件（`sample` / `start` / `pause` / `resume` / `finish` 行），逐点喂 `RunMetricsEngine.ingest`，按状态驱动 `RunSessionMachine`、`AnnouncementScheduler` 与 `RunCheckpointStore`；
   - CoreLocation 模式：`CLLocationManager` 采集 → 精度过滤/首点锚点处理后转成 `RunSample` 喂同一引擎；显式请求并记录定位授权状态；采样频率不重采样；
   - resume 模式：从 `RunCheckpointStore.loadLatest()` 恢复引擎、状态机与播报序号，输出恢复标志与恢复值，不得重复播报已完成公里；
   - status JSON：原子落盘，含原始采样、样本计数、阈值与实际度量、分段采样索引、播报队列、恢复标志、错误。
2. `ios/PurePace/PurePaceApp.swift`：仅改入口判定——无 launch arg 走既有 `ContentView`（占位首屏零变化）；有合法 `--harness` 时进入无业务 UI 的 Harness root（空白视图），不新增页面/路由。
3. `ios/project.yml`：声明定位用途说明与后台定位模式（非空 `NSLocationWhenInUseUsageDescription` 文案 + `UIBackgroundModes` 含 `location`），重新 `xcodegen generate` 并入库 `.xcodeproj`；**只声明配置，不声称真机后台行为**。
4. `ios/PurePaceTests/`：新增 Harness 纯逻辑 XCTest（参数解析、JSONL 控制行、status 字段完整性/原子写、direct 度量与播报 exactly-once、checkpoint 追加节奏、resume 恢复值），不依赖真实定位。
5. `scripts/check-ios-shell.sh`：import 允许表新增 `CoreLocation` 且**只允许**出现在 `ios/PurePace/Harness/`；新增 project.yml 定位配置与 Harness 文件清单静态断言及对应反例自检；占位页断言保持不放松。
6. 下游（本项不做）：`scripts/verify-ios-sim-runtime.sh` 负责 `simctl location` 注入、写 JSONL 到 App 容器、terminate→relaunch 编排与报告；本项只交付它需要的 launch-arg、status 与 checkpoint 契约。

对齐检查点：`cp-metrics-contract` / `cp-persistence-contract` / `cp-tts-audio-contract` 由本项补齐 App 侧串联证据；`cp-stage2-exit` **不关闭**（真机项仍 `pending: 待人现场`）。

## 验收

### 基础与模式

- ac-placeholder-default: 无 launch args 启动时首屏与现状完全一致（`PurePace` + tagline + Run/History/Log/Settings 四个空 `TabView`）；`PlaceholderCopyTests`、`PlaceholderUITests`、`check-ios-shell.sh` 占位页断言通过；Harness 代码不含任何内置样例/夹具数据。
- ac-harness-args-parse: 参数解析为纯逻辑并可单测：合法 `direct`（需 `--stream`、`--checkpoint`、`--status`）、`corelocation`（需 `--checkpoint`、`--status`）、`resume`（需 `--checkpoint`、`--status`）均解析成功；无 `--harness` 返回「不激活」（即使存在其他 flag）；缺必需参数、未知模式返回带稳定错误码的失败；给了 `--status` 时失败也写出 error status，不崩溃。
- ac-mode-dispatch: 三个模式分别进入对应采样源：`direct` 只读 `--stream` 文件，`corelocation` 只走 `CLLocationManager`，`resume` 只读 checkpoint 且不接入任何新采样；任一模式的 status `mode` 字段与 launch arg 一致。

### 直接流与度量

- ac-direct-stream-order: 给定含 `start` → 采样 → `pause` → 采样 → `resume` → 采样 → `finish` 的 JSONL，暂停区间内累计距离/elapsed 冻结、播报队列不增长；`finish` 后 status `state == "finished"`，其后的行不再改变度量与播报队列；空行忽略，损坏行/未知 `type` 写 `error.code == "invalidStreamLine"`（message 含行号）且不静默跳过；缺失 `start` 时首个采样隐式 `start`。
- ac-direct-metrics-within-threshold: 用测试内生成的 1 Hz、5:00–7:00/km 流驱动 Harness，status 的累计距离与参照路线累加相对误差 ≤ 1%、平均/当前配速误差 ≤ 2 s/km、每个 1 km 分段采样索引与期望差 ≤ 1 个采样点；同一输入重复运行（除时间戳外）结果一致。
- ac-announcement-exactly-once: 每个完成的整公里在 status `announcements` 中恰好 1 条；`ready`/`paused` 区间与重复 tick 不新增；`finished` 后不再新增公里播报；命令只入队（本项不发声），字段含 trigger/splitIndex/distanceMeters/paceSecondsPerKilometer/elapsedSeconds。

### status JSON 契约

- ac-status-schema-complete: 每个成功写出的 status JSON 顶层均包含（不要求顺序、允许新增键，但下列键必须存在，值可为 null）：
  `schemaVersion`（=1）、`mode`、`state`、`startedAt`、`updatedAt`、`finishedAt`、`resumed`、`restored{nil|checkpointPath,completedDistanceMeters,elapsedSeconds,splitCount,announcedSplitIndex}`、`rawSamples[]`、`sampleCounts{received,accepted,rejectedByAccuracy,rejectedByFirstPoint}`、`actual{distanceMeters,elapsedSeconds,averagePaceSecondsPerKilometer,currentPaceSecondsPerKilometer,completedKilometers,splitCount,splitSampleIndexes[]}`、`thresholds{distanceRelativeErrorMax,paceErrorMaxSecondsPerKilometer,splitBoundaryToleranceSamples,accuracyFilterMeters,checkpointEveryAcceptedSamples}`、`splits[]`、`announcements[]`、`error`；`corelocation` 模式额外含 `locationAuthorization`。所有时间字段为 epoch 秒（Double）。
- ac-status-raw-samples: `rawSamples` 与输入（direct 的 JSONL / corelocation 的 delegate 回调）按接收顺序一一对应，元素含 `latitude/longitude/timestamp/accepted`，corelocation 元素含 `accuracyMeters`，被拒样本 `accepted=false` 并带拒绝原因；`sampleCounts` 各项与 `rawSamples` 实际计数一致。
- ac-status-atomic-write: status 每次都先写同目录临时文件再原子替换为目标文件；单测在临时目录反复写入并对每次结果解码，均得到完整合法 JSON（不出现半截/空文件）。
- ac-threshold-values: status `thresholds` 写死为 `distanceRelativeErrorMax=0.01`、`paceErrorMaxSecondsPerKilometer=2.0`、`splitBoundaryToleranceSamples=1`、`accuracyFilterMeters=50.0`、`checkpointEveryAcceptedSamples=10`，不得随模式变化或放宽。

### checkpoint 与 resume

- ac-checkpoint-cadence: `direct` 模式在「新增一个已完成分段」「每次状态迁移」「每 10 个被接受采样」三种时机向 `--checkpoint` 真实追加一行 `RunCheckpoint`（JSONL，非内存伪造）；文件可由 `RunCheckpointStore.loadLatest()` 读回；最后一行的 `lastSample` 与 `announcedSplitIndex` 与同期引擎/调度器一致（`announcedSplitIndex` 不小于已产生播报的最大 splitIndex）。
- ac-resume-restore: 以 `direct` 产出的 checkpoint 启动 `--harness resume`，status `resumed == true` 且 `restored.*` 与 checkpoint 的 `completedDistance/elapsed/splits.count/announcedSplitIndex ?? splits.count` 一致，`state` 为引擎归一后的状态（`running/paused → paused`，`finished → finished`），`announcements` 为空且不重复播报已完成公里；checkpoint 缺失/全损时 `error.code == "checkpointMissing"`、`resumed == false`，不伪造恢复值。
- ac-resume-no-new-checkpoint: `resume` 模式只恢复与输出，不追加新的 checkpoint 行、不改写既有文件内容。

### CoreLocation 适配

- ac-corelocation-filter-pure: 精度过滤与首点锚点逻辑为纯逻辑单测覆盖：`horizontalAccuracy < 0` 或 `> 50.0 m` 的样本被拒并计入 `rejectedByAccuracy`；首个被接受样本仅作锚点、不计入距离并计入 `rejectedByFirstPoint`；后续样本正常累计；不重采样、不改写原始时间戳。
- ac-corelocation-authorization: 启动时请求定位授权并记录 `locationAuthorization`（`notDetermined/restricted/denied/authorizedWhenInUse/authorizedAlways`）；未获授权时停止采集并写 `error.code == "locationUnauthorized"`；权限回调后才开始 `startUpdatingLocation`；`finish`/`--max-duration` 到达后停止采集并写最终 status。
- ac-corelocation-config-declared: `ios/project.yml` 同时声明非空的 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` 与 `UIBackgroundModes` 含 `location`（`info.properties` 或 `INFOPLIST_KEY_*` 任一形式均可）；`check-ios-shell.sh` 静态断言两者存在且非空；`xcodegen generate` 产物可解析到这两项（下游模拟器脚本复核含键）。
- ac-corelocation-isolation: `CLLocationManager`/`CoreLocation` 只出现在 `ios/PurePace/Harness/`，且 Harness 内核（参数解析、流解析、驱动编排、status 构建、checkpoint 节奏）不 import CoreLocation/SwiftUI，可用 fake 采样源在 `PurePaceTests` 中单测。

### 工程、门禁与证据

- ac-imports-scoped: `check-ios-shell.sh` 的 App import 允许表新增 `CoreLocation`，且 `CoreLocation` 仅允许出现在 `ios/PurePace/Harness/*.swift`；`AVFoundation` 仍只允许在 `ios/PurePace/Audio/`；`MapKit/HealthKit/CoreMotion/UserNotifications/URLSession` 等仍判失败；占位页显式文件清单断言不放松；新增断言带 `--self-test` 反例自检。
- ac-project-regenerable: 连续两次 `xcodegen generate --spec ios/project.yml` 后 `ios/PurePace.xcodeproj` 零 diff；pbxproj 仅含 `XCLocalSwiftPackageReference`、无远程依赖；`PurePace`/`PurePaceTests` 仍显式依赖 `PurePaceRunCore`；无新增第三方/远程 SwiftPM 依赖、无新增 target。
- ac-build-test-green: `bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 退出码 0；`xcodebuild test -only-testing:PurePaceTests` 在 iPhone 16 / iOS 18.6 模拟器通过，既有占位/音频用例不减少且新增 Harness 用例 ≥ 1（无 `XCTSkip` 或条件跳过）；`.munk/code-gates.json` 门数不减少、既有门语义不放宽。
- ac-runcore-unchanged: `ios/RunCore/**` 默认零改动；`bash scripts/check-ios-run-core.sh`、`swift test --package-path ios/RunCore` 全绿；RunCore 仍只 `import Foundation`。若确需为装配补一个可选字段，必须保持旧 JSONL 可解码且同步补 RunCore 单测（默认路径不改）。
- ac-evidence-wording: 交付结论只写「模拟器契约通过」「配置与调度契约通过」；「后台锁屏连续定位」「音乐不打断与 duck 恢复」「TTS 实听」一律 `pending: 待人现场`；不得出现「已验证」「实听通过」「真机后台定位可用」。

## 非目标

- **不写 `scripts/verify-ios-sim-runtime.sh`**、不跑 `xcrun simctl`（location 注入、privacy grant、terminate/relaunch）、不生成验证报告与阈值比对脚本——全部归下游子项；本项只保证契约可被其驱动。
- 不实现真实语音/TTS、不激活 `AVAudioSession` 发声、不改 `ios/PurePace/Audio/AudioSessionAdapter.swift`；播报只入队不播放。
- 不做真机验证与后台移入后的连续采集；后台模式只是 `Info.plist` 声明，不得据此写「后台定位可用」。
- 不铺任何 UI：不新增跑步页/历史/设置/导出/地图页，不改占位页文案与布局，不加路由、样例数据或内置种子数据。
- 不改 `ios/RunCore` 公开契约、状态迁移矩阵、度量算法与硬阈值（除非为装配确需且不破坏旧格式，见 ac-runcore-unchanged）。
- 不修改 GPX 导出、`shared/` 夹具、Android、`.github/workflows/*`、`VERSION`、README 与 `scripts/build-ios.sh` 入口语义。
- 不做 HealthKit/地图/CoreMotion/UserNotifications/网络请求；不引入第三方或远程 SwiftPM 依赖。
- 不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- **工作树既有状态（重要）**：本分支 `munk/wi_ws_8ec19b08ac1853ee` 上已存在上一轮中断遗留的未提交改动——`ios/PurePace/Harness/`（7 个 swift 文件）、`ios/PurePace/Info.plist`、`ios/PurePaceTests/Harness*.swift`（5 个测试文件）、以及 `ios/project.yml`、`ios/PurePace/PurePaceApp.swift`、`ios/PurePace.xcodeproj/project.pbxproj`、`scripts/check-ios-shell.sh` 的修改。Coding 必须先用 `git status` / `git diff` 审计这些文件：符合本 PRD 的复用并在其上补齐缺口，不符合的修正，**不得重复新建同名/同职责文件**；交付需把这些路径全部纳入变更清单。
- **launch arg 契约（下游脚本据此驱动，不得改名）**：
  - `--harness <direct|corelocation|resume>` 出现即进入 Harness；缺省则完全不激活（占位页原样）。
  - `--status <绝对路径>` 必填（三模式）。`--stream <绝对路径>` 仅 `direct` 必填。`--checkpoint <绝对路径>` 三模式必填（direct/corelocation 追加、resume 读取）。`--max-duration <秒>` 可选，按活跃时长到点自动 `finish`。
  - 路径均为模拟器 App 容器内绝对路径，由下游用 `simctl get_app_container` 取得后写入/传入；Harness 需自行创建 status/checkpoint 父目录。
- **JSONL 直接流契约**：UTF-8、一行一个 JSON 对象、`\n` 结尾；时间基准统一 **epoch 秒（Double）**。采样行 `{"type":"sample","lat":..,"lon":..,"timestamp":..,"altitude":..?,"accuracy":..?,"heartRate":..?,"cadence":..?}`（`type` 省略视为 `sample`）；控制行 `{"type":"start"|"pause"|"resume"|"finish","timestamp":..}`。缺失 `start` 时首个采样隐式 `start(at:)`；重复 `start`/`pause`/`resume` 幂等；`finish` 后忽略剩余行并写最终 status。空行忽略，其余解析失败必须落 error status，不得静默丢弃。
- **status 契约**：顶层键见 ac-status-schema-complete，`schemaVersion` 固定 1，时间全部 epoch 秒；原子写（同目录临时文件 + rename/`replaceItemAt`），每次接受采样与每次状态迁移后更新，`corelocation` 在无新采样时也要保持 `updatedAt` 可观测（定时或事件驱动均可，但不得停写导致下游误判卡死）。status 是唯一对外可观测面，禁止依赖 App 日志或 UI 文本做断言。
- **checkpoint 节奏与顺序**：`ingest` → `AnnouncementScheduler.tick` → `RunCheckpointStore.append`；`RunCheckpoint` 必须带 `lastSample`（引擎 `lastAcceptedSample`）与 `announcedSplitIndex`（调度器当前值），保证恢复后不重复播报。`resume` 用 `announcedSplitIndex ?? splits.count` 播种调度器，避免旧格式 checkpoint 重播。checkpoint 只经 `RunCheckpointStore` 读写，禁止自建 JSON 拼接或内存态伪文件。
- **CoreLocation 适配**：`CLLocationManager` 只在 `ios/PurePace/Harness/` 使用，经一个最小采样源协议注入到纯逻辑内核（单测用 fake，不触真实定位）；请求 `requestWhenInUseAuthorization()`，授权后才 `startUpdatingLocation()`；精度阈值 50 m、首点仅锚点；取消采样在 `finish`/超时/去初始化时执行。不得引入后台持续采集的运行时承诺（后台模式仅配置声明）。
- **分层**：Harness 内核（参数解析、流解析、驱动/编排、status 文档构建、checkpoint 节奏）必须是与 CoreLocation/SwiftUI 解耦的纯逻辑，可 `@testable import PurePace` 单测；`ContentView`/`Placeholder*` 保持零业务引用，只允许 `PurePaceApp.swift` 增加入口判定并渲染空白 Harness root（无 Tab、无业务控件）。
- **`check-ios-shell.sh` 改动边界**：只做「import 允许表 + CoreLocation 限定目录 + project.yml 定位键 + Harness 文件清单」增量，保留既有两次生成零 diff、本地包断言、占位页显式文件清单与 `--self-test` 语义；不得放宽为任意目录可 import CoreLocation。
- **工程**：定位用途说明与后台模式通过 `ios/project.yml` 的 `info.properties` / `settings.base` 声明，文案为非空中文用途说明；`GENERATE_INFOPLIST_FILE: YES` 保持不变；不新增 dependency/target；`xcodegen` 仍是唯一真源。
- **测试**：新增用例全部走既有 `test-ios` 门真实执行；status 原子写、流解析、驱动、checkpoint 节奏、resume 恢复均用临时目录真实文件断言；禁止 `XCTSkip`；不把 CoreLocation 注入链路塞进单测（它归下游模拟器脚本）。
- **证据口径**：只报真实命令输出摘要与用例数；结论限「模拟器契约通过」「配置与调度契约通过」；真机三项 `pending: 待人现场`。
