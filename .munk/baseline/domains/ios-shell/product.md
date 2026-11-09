# Domain: ios-shell

PurePace iOS 工程与运行期契约域：以 XcodeGen 规格 `ios/project.yml` 为唯一真源生成 `ios/PurePace.xcodeproj`，承载无 UI 运行 Harness、XCTest/XCUITest 两个测试 target、真实 `xcodebuild` 构建/测试脚本与结构门禁。面向用户的跑步 UI 与定位数据源由 `ios-app` 域承接；本域只管骨架、Harness 契约与验证路径，不含视觉设计与第三方运行时依赖。

## 范围

- `ios/project.yml`：XcodeGen 规格，声明 App target `PurePace`、单元测试 target `PurePaceTests`、UI 测试 target `PurePaceUITests` 与共享 scheme `PurePace`；deployment target iOS 17.0、`SWIFT_VERSION = 6.2`、唯一允许的依赖是仓库内本地 path package `PurePaceRunCore`（`path: RunCore`，无远程/第三方依赖）、模拟器构建 `CODE_SIGNING_ALLOWED=NO`。
- `ios/PurePace.xcodeproj`：由 `xcodegen generate` 生成的产物入库，**禁止手写 `project.pbxproj`**。
- `ios/Config/Version.xcconfig`：由 `scripts/sync-ios-version.sh` 从根 `VERSION` 派生 `MARKETING_VERSION`；`project.yml` 以 `configFiles` 引用，版本不在规格或源码中写死。
- `ios/PurePace/`：App 源码目录——页面职责与行为 AC 见 `ios-app` 域，本域只约束骨架事实（目录分层、import 允许表、无内置样例/网络请求/夹具引用）；`ios/PurePace/Audio/` 只放音频平台接缝：`AudioSessionAdapter`（`AVAudioSession` 适配器）+ `AnnouncementSpeaker`（`AVSpeechSynthesizer` 播报器），二者均属 `ios-app` 域的接线实现，本域只管 `AVFoundation` 目录限定不被破坏。
- `ios/PurePace/Harness/`：仅由 launch arg（`--harness direct|corelocation|resume`）激活的无业务 UI 运行 Harness——参数解析、JSONL 直接流、status 原子落盘、checkpoint 节奏与 resume 恢复为可单测纯逻辑内核，`CLLocationManager` 仅经最小采样源协议注入；`CoreLocation` 只允许出现在该目录。
- `ios/PurePace/PurePaceApp.swift`：只做入口判定——无 `--harness` 走既有 `ContentView`（真实跑步首屏，页面细节见 `ios-app` 域），有合法参数时渲染空白 Harness root（无 Tab、无业务控件、无路由）。
- `ios/project.yml` 定位/后台模式配置：非空 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`（及 AlwaysAndWhenInUse）、`targets.PurePace.info.properties.UIBackgroundModes: [location, audio]`，且**禁止** `INFOPLIST_KEY_UIBackgroundModes` 设置项（该标量会在构建期覆盖数组）；`ios/PurePace/Info.plist`（`INFOPLIST_FILE`）承载同一数组。仅配置声明，不承诺真机后台行为。
- `ios/PurePaceTests/`：XCTest 用例，覆盖音频适配器、Harness 纯逻辑（参数、流解析、status、checkpoint、resume）与会话 ViewModel/格式化（行为 AC 见 `ios-app` 域）；`ios/PurePaceUITests/`：XCUITest 用例，真实定位注入下走通跑步全流程（见 `ios-app` 域 ac-ui-flow-e2e）。
- `scripts/build-ios.sh`、`scripts/test-ios.sh`：先由根 `VERSION` 同步 `Config/Version.xcconfig`，工程缺失且有 xcodegen 时从 spec 生成，再对 iPhone 16 / iOS 18.6 执行真实 `xcodebuild build` / `xcodebuild test`（无签名）；工程不可用时输出 `blocked:` 并降级真实 `swift build|test --package-path ios/Core`，绝不伪造成功行。`scripts/check-ios-shell.sh` 承载本域结构断言（含 import 允许表与 `CoreLocation` 目录限定、定位配置、Harness 文件清单），`scripts/check-ios-scripts.sh` 承载脚本契约断言。
- `scripts/verify-ios-sim-runtime.sh`：模拟器三链路编排（direct / terminate-relaunch / corelocation）唯一入口，真实驱动已交付 Harness、用 `python3` 独立复算距离与配速、产出机读报告 `.build/verify-ios-sim-runtime/report.json`；不碰 `ios/RunCore/**` 与 `ios/PurePace/Harness/**` 的契约字段。
- 门禁：`.munk/code-gates.json` 的 `lint-ios-shell` / `build-ios` / `test-ios`（均为单一 argv，指向上述脚本）；`scripts/verify-ios-sim-runtime.sh` / `scripts/verify-ios-ui-e2e.sh` 自 `wi_intake_11dc6b68d0c7555d` 起移出本地阻断门、保留为可手动串行的证据腿（权威覆盖回 CI `.github/workflows/ios.yml` 全量 `test-ios.sh`）；既有 `lint` / `lint-baseline` / `lint-ios-core` / `build-ios-core` / `test-ios-core` / `test` 语义不变。

## 验收

- ac-xcodegen-single-source: `ios/project.yml` 存在且 `xcodegen generate --spec ios/project.yml` 成功；生成后 `ios/PurePace.xcodeproj/project.pbxproj` 入库，再次执行同一命令后 `git status --porcelain ios/PurePace.xcodeproj` 为空（工程是生成产物而非手写）。
- ac-no-handwritten-pbxproj: `project.pbxproj` 仅存在于 `ios/PurePace.xcodeproj/` 且可由 `project.yml` 再生成；不存在第二份工程或「有工程却无 `project.yml`」的孤立工程。
- ac-build-settings: `xcodebuild -showBuildSettings -scheme PurePace`（iPhone 16 / iOS 18.6 destination）输出 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`、`SWIFT_VERSION = 6.2`，且 `MARKETING_VERSION` 等于根 `VERSION` 内容。
- ac-build-app: `xcodebuild build`（`-scheme PurePace`、同 destination、`CODE_SIGNING_ALLOWED=NO`）返回 0 并在构建目录产出 `PurePace.app`。
- ac-app-targets-and-frameworks: 工程含 `PurePace` / `PurePaceTests` / `PurePaceUITests` 三个 target，依赖仅限本地 path package `PurePaceRunCore`（无远程/第三方 SwiftPM 声明）；App 源码 import 仅限 `SwiftUI` / `Foundation` / `AVFoundation` / `CoreLocation` / `PurePaceRunCore`，`AVFoundation` 只允许出现在 `ios/PurePace/Audio/`，`CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`，页面不得引用网络请求。
- ac-local-package-wired: `ios/project.yml` 以 `path: RunCore` 声明 `PurePaceRunCore`，`PurePace` 与 `PurePaceTests` 均显式依赖；连续两次 `xcodegen generate` 后 `ios/PurePace.xcodeproj` 零 diff，生成的 pbxproj 仅含 `XCLocalSwiftPackageReference`、不含 `url:`/`https://`/远程 package 引用；`xcodebuild -resolvePackageDependencies` 只解析仓库内 `ios/RunCore`。
- ac-project-regenerable: 连续两次 `xcodegen generate --spec ios/project.yml` 后 `ios/PurePace.xcodeproj` 零 diff；pbxproj 仅含 `XCLocalSwiftPackageReference`、无远程依赖；`PurePace`/`PurePaceTests` 仍显式依赖 `PurePaceRunCore`；无新增第三方/远程 SwiftPM 依赖、无新增 target。
- ac-app-audio-session-adapter: `ios/PurePace/Audio/AudioSessionAdapter.swift` 把 `AudioSessionSettings.defaultAnnouncement` 落到真实 `AVAudioSession`（`.playback` / `.spokenAudio` / `[.duckOthers, .mixWithOthers]`），播报结束仅下发一次 `setActive(false, options: [.notifyOthersOnDeactivation])`，`interruptionNotification` 的 began/ended（含 `ShouldResume`）映射到 `AudioSessionCoordinator` 并执行其动作；平台调用抽到 `AudioSessionControlling` 协议后面，`PurePaceTests` 在 iPhone 16 / iOS 18.6 上以真实读回 + spy 断言，不使用 `XCTSkip`。
- ac-shell-lists-updated: `check-ios-shell.sh` 的 `live_sources` 含 `Settings/AnnouncementSettingsStore.swift`、`Audio/AnnouncementSpeaker.swift`，`unit_tests` 含 `AnnouncementSettingsStoreTests.swift` / `AnnouncementSpeakerTests.swift`；Settings 段断言真实 `Toggle` + `settings.announcementToggle`、禁止「暂无可配置项」/示例数值/`Stepper`/`Slider`，`--self-test` 含对应正负反例且全绿；`AVFoundation` 目录限定（仅 `Audio/`）与越界反例不变，import 允许表不扩。
- ac-live-run-ui: App 首屏为 Run / History / Settings 三个真实 Tab（无 `Log`），Run 页数值一律读 `orchestrator.metrics`，源码无内置样例/种子数据、无网络请求、无夹具引用；结构断言在 `check-ios-shell.sh`，行为 AC 见 `ios-app` 域。
- ac-placeholder-default (superseded): 占位页与四 Tab 契约已随真实跑步 UI 废止，由 `ac-live-run-ui` 及 `ios-app` 域 AC 取代。
- ac-xctest-pass: `xcodebuild test -only-testing:PurePaceTests` 在 iPhone 16 (iOS 18.6) 模拟器通过，执行用例数 ≥ 1。
- ac-xcuitest-pass: `xcodebuild test -only-testing:PurePaceUITests` 在同一模拟器通过，用例真实启动 App 并在真实定位注入下走通跑步流程（断言细节见 `ios-app` 域 ac-ui-flow-e2e），不再断言四 Tab。
- ac-scripts-and-gates: `bash scripts/build-ios.sh --help` 与 `bash scripts/test-ios.sh --help` 退出码 0 且打印说明；两脚本真实执行构建/测试（非 `echo` / `true` 空转）；`.munk/code-gates.json` 中 iOS 门全部单一 argv 且本机全绿，既有门语义未放宽。
- ac-harness-args-parse: 参数解析为纯逻辑并可单测：合法 `direct`（需 `--stream`、`--checkpoint`、`--status`）、`corelocation`（需 `--checkpoint`、`--status`）、`resume`（需 `--checkpoint`、`--status`）均解析成功；无 `--harness` 返回「不激活」（即使存在其他 flag）；缺必需参数、未知模式返回带稳定错误码的失败；给了 `--status` 时失败也写出 error status，不崩溃。
- ac-mode-dispatch: 三个模式分别进入对应采样源：`direct` 只读 `--stream` 文件，`corelocation` 只走 `CLLocationManager`，`resume` 只读 checkpoint 且不接入任何新采样；任一模式的 status `mode` 字段与 launch arg 一致。
- ac-direct-stream-order: 给定含 `start` → 采样 → `pause` → 采样 → `resume` → 采样 → `finish` 的 JSONL，暂停区间内累计距离/elapsed 冻结、播报队列不增长；`finish` 后 status `state == "finished"`，其后的行不再改变度量与播报队列；空行忽略，损坏行/未知 `type` 写 `error.code == "invalidStreamLine"`（message 含行号）且不静默跳过；缺失 `start` 时首个采样隐式 `start`。
- ac-direct-metrics-within-threshold: 用测试内生成的 1 Hz、5:00–7:00/km 流驱动 Harness，status 的累计距离与参照路线累加相对误差 ≤ 1%、平均/当前配速误差 ≤ 2 s/km、每个 1 km 分段采样索引与期望差 ≤ 1 个采样点；同一输入重复运行（除时间戳外）结果一致。
- ac-announcement-exactly-once: 每个完成的整公里在 status `announcements` 中恰好 1 条；`ready`/`paused` 区间与重复 tick 不新增；`finished` 后不再新增公里播报；命令只入队（不发声），字段含 trigger/splitIndex/distanceMeters/paceSecondsPerKilometer/elapsedSeconds。
- ac-status-schema-complete: 每个成功写出的 status JSON 顶层均包含（不要求顺序、允许新增键，但下列键必须存在，值可为 null）：`schemaVersion`（=1）、`mode`、`state`、`startedAt`、`updatedAt`、`finishedAt`、`resumed`、`restored{nil|checkpointPath,completedDistanceMeters,elapsedSeconds,splitCount,announcedSplitIndex}`、`rawSamples[]`、`sampleCounts{received,accepted,rejectedByAccuracy,rejectedByFirstPoint}`、`actual{distanceMeters,elapsedSeconds,averagePaceSecondsPerKilometer,currentPaceSecondsPerKilometer,completedKilometers,splitCount,splitSampleIndexes[]}`、`thresholds{distanceRelativeErrorMax,paceErrorMaxSecondsPerKilometer,splitBoundaryToleranceSamples,accuracyFilterMeters,checkpointEveryAcceptedSamples}`、`splits[]`、`announcements[]`、`error`；`corelocation` 模式额外含 `locationAuthorization`。所有时间字段为 epoch 秒（Double）。
- ac-status-raw-samples: `rawSamples` 与输入（direct 的 JSONL / corelocation 的 delegate 回调）按接收顺序一一对应，元素含 `latitude/longitude/timestamp/accepted`，corelocation 元素含 `accuracyMeters`，被拒样本 `accepted=false` 并带拒绝原因；`sampleCounts` 各项与 `rawSamples` 实际计数一致。
- ac-status-atomic-write: status 每次都先写同目录临时文件再原子替换为目标文件；单测在临时目录反复写入并对每次结果解码，均得到完整合法 JSON（不出现半截/空文件）。
- ac-threshold-values: status `thresholds` 写死为 `distanceRelativeErrorMax=0.01`、`paceErrorMaxSecondsPerKilometer=2.0`、`splitBoundaryToleranceSamples=1`、`accuracyFilterMeters=50.0`、`checkpointEveryAcceptedSamples=10`，不得随模式变化或放宽。
- ac-checkpoint-cadence: `direct` 模式在「新增一个已完成分段」「每次状态迁移」「每 10 个被接受采样」三种时机向 `--checkpoint` 真实追加一行 `RunCheckpoint`（JSONL，非内存伪造）；文件可由 `RunCheckpointStore.loadLatest()` 读回；最后一行的 `lastSample` 与 `announcedSplitIndex` 与同期引擎/调度器一致（`announcedSplitIndex` 不小于已产生播报的最大 splitIndex）。
- ac-resume-restore: 以 `direct` 产出的 checkpoint 启动 `--harness resume`，status `resumed == true` 且 `restored.*` 与 checkpoint 的 `completedDistance/elapsed/splits.count/announcedSplitIndex ?? splits.count` 一致，`state` 为引擎归一后的状态（`running/paused → paused`，`finished → finished`），`announcements` 为空且不重复播报已完成公里；checkpoint 缺失/全损时 `error.code == "checkpointMissing"`、`resumed == false`，不伪造恢复值。
- ac-resume-no-new-checkpoint: `resume` 模式只恢复与输出，不追加新的 checkpoint 行、不改写既有文件内容。
- ac-corelocation-filter-pure: 精度过滤与首点锚点逻辑为纯逻辑单测覆盖：`horizontalAccuracy < 0` 或 `> 50.0 m` 的样本被拒并计入 `rejectedByAccuracy`；首个被接受样本仅作锚点、不计入距离并计入 `rejectedByFirstPoint`；后续样本正常累计；不重采样、不改写原始时间戳。
- ac-corelocation-authorization: 启动时请求定位授权并记录 `locationAuthorization`（`notDetermined/restricted/denied/authorizedWhenInUse/authorizedAlways`）；未获授权时停止采集并写 `error.code == "locationUnauthorized"`；权限回调后才开始 `startUpdatingLocation`；`finish`/`--max-duration` 到达后停止采集并写最终 status。
- ac-corelocation-config-declared: `ios/project.yml` 同时声明非空 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` 与 `info.properties.UIBackgroundModes` 数组含 `location`；`check-ios-shell.sh` 静态断言两者存在且非空；`xcodegen generate` 产物可解析到这两项（下游模拟器脚本复核含键）。旧口径「`INFOPLIST_KEY_UIBackgroundModes` 与 `info.properties` 任一形式均可」已废止——该标量会覆盖数组声明，其存在即判失败。
- ac-project-yml-array-both: `ios/project.yml` 的 `targets.PurePace.info.properties.UIBackgroundModes` 解析后为数组且同时包含 `location` 与 `audio`。
- ac-project-yml-no-duplicate-setting: `ios/project.yml` 中不存在任何 `INFOPLIST_KEY_UIBackgroundModes` 设置项（避免构建期标量覆盖数组声明）。
- ac-xcodeproj-regenerated: `ios/PurePace.xcodeproj/project.pbxproj` 由 `xcodegen generate --spec ios/project.yml` 重新生成（无手工编辑痕迹），生成后 App target 构建设置不含 `INFOPLIST_KEY_UIBackgroundModes`，且仍以 `PurePace/Info.plist` 作为 `INFOPLIST_FILE`。
- ac-built-plist-readback-both: `ios/PurePaceTests` 中存在经 `code_gates` 的 `test-ios` unit 腿执行的用例，用 `Data(contentsOf:)` + `PropertyListSerialization` 读取已构建 `PurePace.app/Info.plist` **文件本体**，断言 `UIBackgroundModes` 实际数组同时包含 `location` 与 `audio`；缺任一值断言失败，并有同一读取路径的负向自检（夹具缺 location / 缺 audio / 空数组）。禁止只断言 `project.yml` 文本、禁止 `XCTSkip`。既有 `RunLocationSourceTests.testInfoPlistBackgroundModesContainsLocation` 保留不弱化。
- ac-background-modes-shell-assertion: `scripts/check-ios-shell.sh` 的 `validate_location_config` 与 `--self-test` 改为校验「project.yml 无 `INFOPLIST_KEY_UIBackgroundModes` + 数组含 `location`/`audio` + Info.plist 数组含两者」，并保留正例与缺 location / 缺 audio / 重复 setting / 缺数组反例；强度不降，不改 `scripts/*` 其它逻辑。
- ac-no-business-source-change: `ios/PurePace/` 业务源码（Audio/播报、AudioSession 适配器、CoreLocation/定位、持久化、UI）零改动；`ios/Core`、`ios/RunCore` 业务逻辑零改动；本项只改 plist 声明、工程生成产物、测试与上述直接耦合的 shell 断言。
- ac-corelocation-isolation: `CLLocationManager`/`CoreLocation` 只出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`，且 Harness 内核（参数解析、流解析、驱动编排、status 构建、checkpoint 节奏）不 import CoreLocation/SwiftUI，可用 fake 采样源在 `PurePaceTests` 中单测。
- ac-imports-scoped: `check-ios-shell.sh` 的 App import 允许表新增 `CoreLocation`，且 `CoreLocation` 仅允许出现在 `ios/PurePace/Harness/*.swift` 与 `ios/PurePace/Location/*.swift`；`AVFoundation` 仍只允许在 `ios/PurePace/Audio/`；`MapKit/HealthKit/CoreMotion/UserNotifications/URLSession` 等仍判失败；页面显式文件清单断言不放松（已改为真实 UI 清单）；新增断言带 `--self-test` 反例自检。
- ac-build-test-green: `bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 退出码 0；`xcodebuild test -only-testing:PurePaceTests` 在 iPhone 16 / iOS 18.6 模拟器通过，既有音频/Harness 用例不减少且真实跑步 UI 用例 ≥ 1（无 `XCTSkip` 或条件跳过）；`.munk/code-gates.json` 既有门语义不放宽（门数自 `wi_intake_11dc6b68d0c7555d` 起收敛为 22 门快腿拓扑，重腿移出本地阻断，见 `ios-ci-stability`）。
- ac-runcore-unchanged: `ios/RunCore/**` 默认零改动；`bash scripts/check-ios-run-core.sh`、`swift test --package-path ios/RunCore` 全绿；RunCore 仍只 `import Foundation`。若确需为装配补一个可选字段，必须保持旧 JSONL 可解码且同步补 RunCore 单测（默认路径不改）。
- ac-evidence-wording: 交付结论只写「模拟器契约通过」「配置与调度契约通过」；「后台锁屏连续定位」「音乐不打断与 duck 恢复」「TTS 实听」一律 `pending: 待人现场`；不得出现「已验证」「实听通过」「真机后台定位可用」。
- ac-script-hygiene: `scripts/verify-ios-sim-runtime.sh` 用 `#!/usr/bin/env bash` + `set -euo pipefail` + `BASH_SOURCE` 推导仓库根；`--help` 退出 0 且输出含「用法」，未知参数退出 2，`bash -n` 通过；`bash scripts/check-shell-expansion.sh`、`bash scripts/check-baseline.sh` 仍绿（无非 ASCII 裸展开、无版本字面值）。
- ac-direct-run-real: iPhone 16 / iOS 18.6 上真实安装启动 App 跑完 direct 链路，status 满足 `schemaVersion==1`、`mode=="direct"`、`state=="finished"`、`rawSamples` 非空、`sampleCounts.received==rawSamples.count`；脚本自生成并写入 App 容器的 JSONL ≥ 3000 行（3 km/1 Hz），零引用 `shared/fixtures`。
- ac-direct-distance-within-1pct: 脚本对 `rawSamples` 中被接受样本独立 Haversine 累加得 `recomputedDistanceMeters`，判 `|actual.distanceMeters - recomputed|/recomputed ≤ 0.005`（收紧自 0.01）且 `|recomputed - 3000|/3000 ≤ 0.01`；报告同时写出阈值与实测三项数值。
- ac-direct-pace-within-2s: 脚本独立按 `elapsedSeconds/(recomputed/1000)` 复算平均配速，与 `actual.averagePaceSecondsPerKilometer` 差 ≤ 2.0 s/km；`currentPaceSecondsPerKilometer` 非 null 且落在 `[300, 420]`。
- ac-direct-split-boundary-pm1: `actual.completedKilometers == 3`、`splitSampleIndexes` 长 3，每段索引与脚本按 1 Hz + 生成路线算出的期望索引差 ≤ 1 个采样点；`splits[].distanceMeters` 单调递增且每段 1000 m（±1%）。
- ac-announcement-exactly-once-runtime: 模拟器 direct 链路的 `announcements` 条数 == `completedKilometers`，`splitIndex` 集合恰为 `1...completedKilometers` 且无重复；`finished` 后不再新增（只允许至多一条 `finished` 触发）；流中暂停窗口不产生播报。
- ac-location-injection-real: corelocation 链路真实执行 `xcrun simctl privacy grant`，再用 `xcrun simctl location set` 按 1 Hz 确定性逐点推进 250 m 路线（每 tick 3.0 m，先推首点等 App 采到首个样本，再按 status 实际采集距离确认推进；停滞 >5 s 用当前进度重算剩余点并重推，最多 2 轮；进度型超时总预算 300 s），不依赖 `simctl location start` 的播放时长；status `mode=="corelocation"`、`locationAuthorization` 为已授权取值、`error==null`、`rawSamples` 非空；结束前执行 `xcrun simctl location clear`，不得用夹具或硬编码坐标冒充捕获点。
- ac-location-distance-within-1pct: 排除首点锚点后对 corelocation `rawSamples` 独立 Haversine 累加，判 `|actual-recomputed|/recomputed ≤ 0.005`（收紧自 0.01），且与注入路线 250 m 偏差 ≤ 1%。
- ac-location-capture-coverage: 捕获轨迹长度 / 注入路线长度 ≥ 0.99（阈值写死 99%），报告记录 `capturedMeters`、`injectedMeters`、`coverage` 实际值。
- ac-location-pace-within-2s: `|actual.averagePaceSecondsPerKilometer - 300| <= 2.0` 的文案目标按物理换算为 3.0 m/s ⇒ 333.33 s/km：实际判定 `|actual.averagePace - 333.33| <= 2.0` 且独立复算与之相差 ≤ 2.0 s/km（以物理换算为准，不放宽）。
- ac-terminate-relaunch-restores: 对 `completedKilometers >= 2` 且 checkpoint 文件存在非空的一次 direct 运行，真实 `xcrun simctl terminate` 后以 `--harness resume` relaunch；resume status `resumed==true`、`restored.completedDistanceMeters >= 杀进程前末个 checkpoint 的 completedDistanceMeters`、`restored.splitCount >= 该 checkpoint 的 splits.count`、`restored.announcedSplitIndex >= 已播报最大 splitIndex`。
- ac-terminate-relaunch-no-duplicate-announcement: relaunch 后 `announcements` 不含 `splitIndex <= restored.announcedSplitIndex` 的条目，且 resume status `error==null`。
- ac-checkpoint-on-disk-real: 杀进程前后读取的是 App 容器内真实 checkpoint 文件（JSONL，每行可被 `RunCheckpointStore` 语义解析；行数 ≥ 2，末行 `completedDistanceMeters`/`splits` 与 resume 快照一致），拒绝内存态或脚本伪造文件充当证据。
- ac-report-machine-readable: `.build/verify-ios-sim-runtime/report.json` 为合法 JSON（`python3 -c 'json.load'` 可解析），含 `schemaVersion`、`device{name,udid,runtime}`、`links[]{id,status,thresholds,actual,verdict,durationSeconds}` 与顶层 `verdict`；每类阈值同时写出「阈值」与「实际值」；`deviceVerification` 的 `backgroundLocationContinuous`/`audioNotInterrupted`/`ttsLiveListen` 恒为 `"pending: 待人现场"`，全文不出现「已验证」「实听通过」。
- ac-failure-nonzero: 任一链路失败、阈值越界、status 缺失/无法解析、`xcrun`/`xcodebuild`/模拟器运行时缺失、App 安装或启动失败时脚本非零退出（不 `exit 0`、不静默 skip），并在 stderr 与 `links[].failureReason` 写明失败指标。
- ac-gate-registered: `.munk/code-gates.json` 曾追加 `{"id": "verify-ios-sim-runtime", "cwd": ".", "command": "bash scripts/verify-ios-sim-runtime.sh"}`；`wi_intake_11dc6b68d0c7555d` 起该门移出本地阻断（脚本与 command 契约不变、可手动执行，见 `ios-ci-stability` 域拓扑收敛），既有其余门 `id`/`command` 逐字不变；门 command 仍为单一 argv（不含 `&&`/`||`/`|`/`;`/`>`/`<`）。
- ac-existing-gates-green: `check-ios-shell.sh`、`check-ios-scripts.sh`、`check-ios-run-core.sh`、`check-shared.sh`、`check-gpx-export.sh`、`check-shell-expansion.sh`、`check-baseline.sh` 全部退出 0；本项不改 `ios/RunCore/**` 与 `ios/PurePace/Harness/**` 契约字段。

## 非目标

- 本域不定义面向用户的跑步业务 UI（Run/History/Settings 与真实定位数据源已由 `ios-app` 域承接）；不新增历史详情/导出/地图页、不加路由与内置样例数据；`ios/PurePace/Harness/` 仍只是仅由 launch arg 激活的验证接缝（无 Tab、无业务控件）。
- 不实现真实语音/TTS 语义（播报调度仍由 `ios/RunCore` 决定）；本域不扩 `AVFoundation` 目录限定、不改 `AudioSessionAdapter.swift` 的会话配置值，`Audio/AnnouncementSpeaker.swift` 的行为 AC 归 `ios-app` 域。
- Harness 交付项本身不写 `scripts/verify-ios-sim-runtime.sh`、不跑 `xcrun simctl`（模拟器三链路编排已由后续项在 `scripts/verify-ios-sim-runtime.sh` 补齐，见下节）；不替换 `ios/RunCore` 的状态机/度量算法与硬阈值。
- 不做真机验证与后台移入后的连续采集、不做真机签名/provision/TestFlight；后台模式只是 `Info.plist` 配置声明。
- 不做视觉设计、设计 token、多语言框架、账号/云/社交，不引入跨端框架与第三方运行时依赖。
- 不做 Android 骨架、`shared/` 夹具与 schema；iOS CI workflow 与远端 run 验证已由 `ci` 域承接，不在本域扩展。
- 不重构既有 `ios/Core` 包、不向其新增业务 API；不改写 `scripts/check-baseline.sh` / `scripts/check-ios-core.sh` 既有断言；不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- 环境事实：Xcode 26.3 / Swift 6.2，iOS 18.6 运行时与 iPhone 16 模拟器已安装（destination 以 UDID 固定），构建与测试统一 `CODE_SIGNING_ALLOWED=NO`。
- XcodeGen 为构建期工具，已由 Owner 批准一次安装（`brew install xcodegen` 或等价官方二进制）；本域不允许手写 pbxproj 绕过工具缺失，也不允许在无 xcodegen 时伪造工程入库。
- bundle id 统一 `com.chaxiu.purepace`（与 Android applicationId 口径一致），只在 `project.yml` 一处定义，测试 target 以其为前缀派生。
- 版本派生：`MARKETING_VERSION` 只能来自根 `VERSION`（经 `scripts/sync-ios-version.sh` → `ios/Config/Version.xcconfig`），`project.yml`、源码与脚本均不得写死当前版本字面值；`CURRENT_PROJECT_VERSION` 用常量构建号。
- 依赖/分层：仅允许以本地 path package 依赖 `ios/RunCore`（`PurePaceRunCore`），不得声明远程/第三方 SwiftPM 依赖；`AVFoundation` 只允许出现在 `ios/PurePace/Audio/` 适配器，`CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`；`ContentView` 只做 Tab 容器与入口分支，跑步数值只经 `RunSessionOrchestrator.metrics`；`ios/PurePace/` 不放样例数据，示例数据只允许出现在测试代码中。
- Harness launch arg 契约（下游脚本据此驱动，不得改名）：`--harness <direct|corelocation|resume>` 出现即激活，缺省完全不激活；`--status <绝对路径>` 三模式必填，`--stream <绝对路径>` 仅 `direct` 必填，`--checkpoint <绝对路径>` 三模式必填（direct/corelocation 追加、resume 读取），`--max-duration <秒>` 可选按活跃时长自动 `finish`；Harness 自行创建 status/checkpoint 父目录。
- Harness 内核与契约：JSONL 直接流为 UTF-8 一行一对象、时间统一 epoch 秒；status 为唯一对外可观测面（原子写：同目录临时文件 + 原子替换），`schemaVersion=1`，每次接受采样/状态迁移后更新，禁止依赖日志或 UI 文本断言；顺序固定 `ingest` → `AnnouncementScheduler.tick` → `RunCheckpointStore.append`，checkpoint 只经 `RunCheckpointStore` 读写（禁自建 JSON 拼接/内存伪文件），resume 用 `announcedSplitIndex ?? splits.count` 播种调度器。
- CoreLocation 适配：`CLLocationManager` 只在 Harness 目录使用并经最小采样源协议注入纯逻辑内核（单测用 fake，不触真实定位）；`requestWhenInUseAuthorization()` 授权后才 `startUpdatingLocation()`；精度阈值 50 m、首点仅锚点；`finish`/超时/去初始化时停止采样；不引入后台持续采集的运行时承诺。
- 门禁形态：`command` 保持单一 argv，多步流程封装进 `scripts/` 下 bash 脚本（`set -euo pipefail`、幂等、支持 `--help`、以仓库根为路径基准）；构建/测试产物由忽略规则覆盖，不入库。
- destination 钉住 iPhone 16 且必须带 `OS=18.6`（或等价 UDID）：只写 `name=iPhone 16` 会被解析成 `latest` 运行时（本机为 iOS 26.3.1，无 iPhone 16 机型）而构建失败；工程缺失时脚本走 `blocked:` + SwiftPM 降级分支，不得让门禁因此失败。
- 门禁共存：本域 `lint-ios-shell` 与脚本契约门 `lint-ios-scripts` 必须同时通过；后者对 destination 的断言按「iPhone 16 + 可选 OS/UDID」校验，不得放宽为任意机型。
- 证据口径：只报真实命令输出摘要与用例数，不写「CI 通过」「真机已验证」；本地门通过不替代远端 run；结论限「模拟器契约通过」「配置与调度契约通过」。

### 模拟器运行时验证编排（`scripts/verify-ios-sim-runtime.sh`）

- 入口：`bash scripts/verify-ios-sim-runtime.sh`（`--help` 退出 0，未知参数或多参数退出 2；`set -euo pipefail`；仓库根由 `BASH_SOURCE` 推导）；该脚本与 `verify-ios-ui-e2e.sh` 共用 `/tmp/purepace-ios-gate.lock` 串行化，`wi_intake_11dc6b68d0c7555d` 起不再作为本地阻断门（command 契约不变，权威覆盖回 CI `ios.yml`）。
- 设备固定 iPhone 16 / iOS 18.6（`com.apple.CoreSimulator.SimRuntime.iOS-18-6`），复用 `scripts/build-ios.sh` 产物与 `CODE_SIGNING_ALLOWED=NO`；容器经 `xcrun simctl get_app_container <udid> com.chaxiu.purepace data` 取得。
- 三链路（按 direct → terminate-relaunch → corelocation 执行）：
  - direct：脚本生成 3 km、1 Hz、5:00–7:00/km 的 JSONL 直接流写入 App 容器（×3 km ≈ 3000+ 行，含暂停窗口），以 `--harness direct --status --stream --checkpoint` 启动；独立 Haversine 复算距离/配速，判定距离相对误差 ≤1%、配速误差 ≤2 s/km、分段采样索引 ±1、每公里播报恰好一次（只允许 `kilometerCompleted` 与至多一条 `finished` 触发），finished 后静置复读断言 announcement 不再增长。
  - terminate-relaunch：direct 达到 ≥2 个已完成分段后 `xcrun simctl terminate`，再 `--harness resume` relaunch；比对 App 容器内真实 checkpoint 末行（`formatVersion=1`、`splits` 索引连续 1..n）与 `restored{completedDistanceMeters,splitCount,announcedSplitIndex}`，断言不重复播报。
  - corelocation：`xcrun simctl privacy grant` 后以 1 Hz `xcrun simctl location set` 确定性逐点推进约 250 m（每 tick 3.0 m ⇒ 3.0 m/s ⇒ 333.33 s/km，PRD 中「5:00/km」为文案近似；判定以物理换算为准）；App 采到首点后再开始推，每 tick 按 status 已采距离确认推进，停滞 >5 s 用当前进度重算剩余点并重推（最多 2 轮），超时为进度型、总预算 300 s，`--max-duration 200` 兜底；结束时 `xcrun simctl location clear`；排除首点锚点后判定距离相对误差 ≤0.5%、与 250 m 偏差 ≤1%、覆盖率 ≥99%、配速误差 ±2 s/km；不用夹具或硬编码坐标冒充捕获点。该门曾在 `location start` 播放式注入下偶发只采到 148 m，故改为确定性推点（阈值未放松，距离相对误差由 1% 收紧到 0.5%）。
- 报告：`.build/verify-ios-sim-runtime/report.json`（机读 JSON，含 `schemaVersion`、`device{name,udid,runtime}`、`links[]{id,status,thresholds,actual,checks,verdict,durationSeconds,failureReason}`、顶层 `verdict`）；任一链路/阈值/环境失败即非零退出并在 stderr 与 `failureReason` 写明指标；`deviceVerification` 的 `backgroundLocationContinuous` / `audioNotInterrupted` / `ttsLiveListen` 恒为 `pending: 待人现场`。

## 最近交付证明

- workItemId: wi_intake_2772ca1f27982358（2026-11-09，pass）
- 交付：补齐后台音频声明并加构建产物读回断言——`ios/project.yml` 的 `info.properties.UIBackgroundModes` 改为 `[location, audio]`，删除重复的 `INFOPLIST_KEY_UIBackgroundModes: location`（构建期标量覆盖数组，是此前「改了也没生效」的根因），`ios/PurePace/Info.plist` 同步补 `audio`，工程由 `xcodegen generate` 重新生成；`ios/PurePaceTests/BackgroundModesPlistTests.swift` 用 `Data(contentsOf:)` + `PropertyListSerialization` 读 App 包内 Info.plist 文件本体断言两者并存，并以同一路径做缺 location / 缺 audio / 空数组负向自检；`check-ios-shell.sh` 的 `validate_location_config` 与自检夹具改为「无重复 setting + 数组含两者」，保留正负反例。业务源码零改动。
- 实测：`code_gates` 全绿（含 `lint-ios-shell` / `build-ios` / `test-ios`），门 id 与 `command` 未变。结论口径：模拟器契约通过、配置契约通过；真机锁屏后台音频实听仍为 `pending: 待人现场`。
- 候选包口径：仅改 plist 时 exec sha 可能与旧包相同，候选验收键为 zip sha256 + 构建产物 `UIBackgroundModes` 实际数组（见 `ios-release` 域 ac-candidate-evidence-keys）。
