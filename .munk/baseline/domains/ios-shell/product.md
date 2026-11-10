# Domain: ios-shell

PurePace iOS 工程与运行期契约域：以 XcodeGen 规格 `ios/project.yml` 为唯一真源生成 `ios/PurePace.xcodeproj`，承载无 UI 运行 Harness、XCTest/XCUITest 两个测试 target、真实 `xcodebuild` 构建/测试脚本与结构门禁。面向用户的跑步 UI 与定位数据源由 `ios-app` 域承接；本域只管骨架、Harness 契约与验证路径，不含视觉设计与第三方运行时依赖。

## 范围

- `ios/project.yml`：XcodeGen 规格，声明 App target `PurePace`、单元测试 target `PurePaceTests`、UI 测试 target `PurePaceUITests` 与共享 scheme `PurePace`；deployment target iOS 17.0、`SWIFT_VERSION = 6.2`、唯一允许的依赖是仓库内本地 path package `PurePaceRunCore`（`path: RunCore`，无远程/第三方依赖）、模拟器构建 `CODE_SIGNING_ALLOWED=NO`。
- `ios/PurePace.xcodeproj`：`xcodegen generate` 生成物，整目录由 `.gitignore` 忽略、**不入库**（`project.pbxproj` / workspace / shared scheme 均不跟踪）；生成后 `git status --porcelain` 必须干净，**禁止手写 `project.pbxproj`**。
- `ios/Config/Version.xcconfig`：由 `scripts/sync-ios-version.sh` 从根 `VERSION` 派生 `MARKETING_VERSION`；`project.yml` 以 `configFiles` 引用，版本不在规格或源码中写死。
- `ios/PurePace/`：App 源码目录——页面职责与行为 AC 见 `ios-app` 域，本域只约束骨架事实（目录分层、import 允许表、无内置样例/网络请求/夹具引用）；`ios/PurePace/Audio/` 只放 `AudioSessionAdapter` + `AnnouncementSpeaker` 两个音频平台接缝（行为归 `ios-app` 域），本域只管 `AVFoundation` 目录限定不破。
- `ios/PurePace/Harness/`：仅由 launch arg（`--harness direct|corelocation|resume`）激活的无业务 UI 运行 Harness——参数解析、JSONL 直接流、status 原子落盘、checkpoint 节奏与 resume 恢复为可单测纯逻辑内核，`CLLocationManager` 仅经最小采样源协议注入；`CoreLocation` 只允许出现在该目录。
- `ios/PurePace/PurePaceApp.swift`：只做入口判定——无 `--harness` 走既有 `ContentView`（真实跑步首屏，页面细节见 `ios-app` 域），有合法参数时渲染空白 Harness root（无 Tab、无业务控件、无路由）。
- `ios/project.yml` 定位/后台模式配置：非空 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`（及 AlwaysAndWhenInUse）、`targets.PurePace.info.properties.UIBackgroundModes: [location, audio]`，且**禁止** `INFOPLIST_KEY_UIBackgroundModes` 设置项（该标量会在构建期覆盖数组）；`ios/PurePace/Info.plist`（`INFOPLIST_FILE`）承载同一数组。仅配置声明，不承诺真机后台行为。
- `ios/PurePaceTests/`：XCTest 用例，覆盖音频适配器、Harness 纯逻辑（参数、流解析、status、checkpoint、resume）与会话 ViewModel/格式化（行为 AC 见 `ios-app` 域）；`ios/PurePaceUITests/`：XCUITest 用例，真实定位注入下走通跑步全流程（见 `ios-app` 域 ac-ui-flow-e2e）。
- `scripts/build-ios.sh`、`scripts/test-ios.sh`：先由根 `VERSION` 同步 `Config/Version.xcconfig`，工程缺失且有 xcodegen 时从 spec 生成，再对 iPhone 16 / iOS 18.6 执行真实 `xcodebuild build|test`（无签名）；工程不可用输出 `blocked:` 并降级真实 `swift build|test --package-path ios/Core`，绝不伪造成功行。`scripts/check-ios-shell.sh` 承载结构断言（import 允许表、`CoreLocation` 目录限定、定位/后台模式配置、Harness 文件清单），`scripts/check-ios-scripts.sh` 承载脚本契约断言。
- `scripts/verify-ios-sim-runtime.sh`：模拟器三链路编排（direct / terminate-relaunch / corelocation）已拆至 `ios-sim-runtime` 域；本域只保证该脚本消费的工程与 Harness 契约不变。
- 门禁：`.munk/code-gates.json` 的 `lint-ios-shell` / `build-ios` / `test-ios`（均为单一 argv，指向上述脚本）；`scripts/verify-ios-sim-runtime.sh` / `scripts/verify-ios-ui-e2e.sh` 自 `wi_intake_11dc6b68d0c7555d` 起移出本地阻断门、保留为可手动串行的证据腿（权威覆盖回 CI `.github/workflows/ios.yml` 全量 `test-ios.sh`）；既有 `lint` / `lint-baseline` / `lint-ios-core` / `build-ios-core` / `test-ios-core` / `test` 语义不变。

## 验收

- ac-xcodegen-single-source: `ios/project.yml` 存在且 `xcodegen generate --spec ios/project.yml --project ios` 成功；`ios/PurePace.xcodeproj` 整体为 ignored 生成物，执行同一命令后 `git status --porcelain` 为空（工程是生成产物，既非手写也不入库）。
- ac-no-tracked-pbxproj: `git ls-files` 中匹配 `project.pbxproj` 的条目为空（含 `ios/PurePace.xcodeproj/project.pbxproj` 已不在索引）；仓库内不存在第二份工程或「有工程却无 `project.yml`」的孤立工程。
- ac-generated-artifacts-ignored: `git check-ignore -v ios/PurePace.xcodeproj/project.pbxproj` 退出 0；忽略方案为 A（整目录 `ios/PurePace.xcodeproj/`：pbxproj / workspace / scheme 全部不入库），以此保证重生成后 `git status` 干净。
- ac-scheme-generated-shared: `xcodegen generate` 后 `ios/PurePace.xcodeproj/xcshareddata/xcschemes/PurePace.xcscheme` 存在且非空，`xcodebuild -list -project ios/PurePace.xcodeproj` 输出包含 `PurePace` scheme；scheme 随生成物不入库，无例外。
- ac-regen-from-spec-passes-unit-leg: `rm -rf ios/PurePace.xcodeproj` 后由 `ios/project.yml` 重新生成工程成功（退出 0），随后 `bash scripts/test-ios.sh --unit-only` 单测腿真实通过（真实 `xcodebuild test`，而非 `blocked:` 降级）。
- ac-build-settings: `xcodebuild -showBuildSettings -scheme PurePace`（iPhone 16 / iOS 18.6 destination）输出 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`、`SWIFT_VERSION = 6.2`，且 `MARKETING_VERSION` 等于根 `VERSION` 内容。
- ac-build-app: `xcodebuild build`（`-scheme PurePace`、同 destination、`CODE_SIGNING_ALLOWED=NO`）返回 0 并在构建目录产出 `PurePace.app`。
- ac-app-targets-and-frameworks: 工程含 `PurePace` / `PurePaceTests` / `PurePaceUITests` 三个 target，依赖仅限本地 path package `PurePaceRunCore`（无远程/第三方 SwiftPM 声明）；App 源码 import 仅限 `SwiftUI` / `Foundation` / `AVFoundation` / `CoreLocation` / `PurePaceRunCore`，`AVFoundation` 只允许出现在 `ios/PurePace/Audio/`，`CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`，页面不得引用网络请求。
- ac-local-package-wired: `ios/project.yml` 以 `path: RunCore` 声明 `PurePaceRunCore`，`PurePace` 与 `PurePaceTests` 均显式依赖；连续两次 `xcodegen generate` 后 `ios/PurePace.xcodeproj` 零 diff，生成的 pbxproj 仅含 `XCLocalSwiftPackageReference`、不含 `url:`/`https://`/远程 package 引用；`xcodebuild -resolvePackageDependencies` 只解析仓库内 `ios/RunCore`。
- ac-project-regenerable: 连续两次 `xcodegen generate --spec ios/project.yml --project ios` 后 `git status --porcelain` 为空（ignored 生成物不计入）；生成的 pbxproj 仅含 `XCLocalSwiftPackageReference`、无远程依赖；`PurePace`/`PurePaceTests` 仍显式依赖 `PurePaceRunCore`；无新增第三方/远程 SwiftPM 依赖、无新增 target。
- ac-app-audio-session-adapter: `ios/PurePace/Audio/AudioSessionAdapter.swift` 把 `AudioSessionSettings.defaultAnnouncement` 落到真实 `AVAudioSession`（`.playback` / `.spokenAudio` / `[.duckOthers, .mixWithOthers]`），播报结束仅下发一次 `setActive(false, options: [.notifyOthersOnDeactivation])`，`interruptionNotification` 的 began/ended（含 `ShouldResume`）映射到 `AudioSessionCoordinator` 并执行其动作；平台调用抽到 `AudioSessionControlling` 协议后面，`PurePaceTests` 在 iPhone 16 / iOS 18.6 上以真实读回 + spy 断言，不使用 `XCTSkip`。
- ac-shell-lists-updated: `check-ios-shell.sh` 的 `live_sources` 含 `Settings/AnnouncementSettingsStore.swift`、`Audio/AnnouncementSpeaker.swift`，`unit_tests` 含 `AnnouncementSettingsStoreTests.swift` / `AnnouncementSpeakerTests.swift`；Settings 段断言真实 `Toggle` + `settings.announcementToggle`、禁止「暂无可配置项」/示例数值/`Stepper`/`Slider`，`--self-test` 含对应正负反例且全绿；`AVFoundation` 目录限定（仅 `Audio/`）与越界反例不变，import 允许表不扩。
- ac-live-run-ui: App 首屏为 Run / History / Settings 三个真实 Tab（无 `Log`），Run 页数值一律读 `orchestrator.metrics`，源码无内置样例/种子数据、无网络请求、无夹具引用；结构断言在 `check-ios-shell.sh`，行为 AC 见 `ios-app` 域。
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
- ac-bundle-id-single-source: `ios/project.yml` 中 bundle id 字面值仅一处 `PUREPACE_BUNDLE_ID: sh.munk.purepace`；三 target 的 `PRODUCT_BUNDLE_IDENTIFIER` 分别派生为 `$(PUREPACE_BUNDLE_ID)`、`$(PUREPACE_BUNDLE_ID).tests`、`$(PUREPACE_BUNDLE_ID).uitests`，不写死完整 id；`project.pbxproj` 中该值同为 `sh.munk.purepace` 且 diff 只可能来自 `xcodegen generate`，连续两次生成零 diff 断言仍通过。
- ac-bundle-readback: hosted 单测 `RunLocationSourceTests.testInfoPlistBundleIdentifierIsFinalProductId` 断言 `Bundle.main.bundleIdentifier == "sh.munk.purepace"`；既有背景模式用例补 `audio` 后，`Bundle.main` 读回 `UIBackgroundModes` 同时含 `location` 与 `audio`。两者失败均打印实际读回值。
- ac-signing-unchanged: `ios/project.yml` 仍含 `CODE_SIGNING_ALLOWED: NO`；bundle id 迁移 diff 中不出现 `DEVELOPMENT_TEAM`、`PROVISIONING_PROFILE`、证书/签名身份相关新增行。
- ac-ios-scripts-final-id: `scripts/test-ios.sh`、`verify-ios-sim-runtime.sh`、`verify-ios-ui-e2e.sh` 内所有 bundle id 字面值为 `sh.munk.purepace`（含 usage 文案与报告兜底字段），各脚本 `--help` 退出 0、`bash -n` 通过。
- ac-legacy-bundle-id-grep-exempt: `git grep -n 'com\.chaxiu\.purepace' -- ios scripts README.md docs` 在豁免清单外零命中；豁免仅限历史证据（`docs/evidence/**`、`artifacts/**`），历史记录不改写。
- ac-bundle-id-rename-no-business-change: `ios/PurePace/**` 源码零改动；唯一 Swift 源码改动在 `ios/PurePaceTests/RunLocationSourceTests.swift`（新增读回归断言）；定位、音频、持久化、UI 文案、GPX 导出行为零变化，无顺手重构。
- ac-built-plist-readback-both: `ios/PurePaceTests` 中存在经 `code_gates` 的 `test-ios` unit 腿执行的用例，用 `Data(contentsOf:)` + `PropertyListSerialization` 读取已构建 `PurePace.app/Info.plist` **文件本体**，断言 `UIBackgroundModes` 实际数组同时包含 `location` 与 `audio`；缺任一值断言失败，并有同一读取路径的负向自检（夹具缺 location / 缺 audio / 空数组）。禁止只断言 `project.yml` 文本、禁止 `XCTSkip`。既有 `RunLocationSourceTests.testInfoPlistBackgroundModesContainsLocation` 保留不弱化。
- ac-background-modes-shell-assertion: `scripts/check-ios-shell.sh` 的 `validate_location_config` 与 `--self-test` 改为校验「project.yml 无 `INFOPLIST_KEY_UIBackgroundModes` + 数组含 `location`/`audio` + Info.plist 数组含两者」，并保留正例与缺 location / 缺 audio / 重复 setting / 缺数组反例；强度不降，不改 `scripts/*` 其它逻辑。
- ac-no-business-source-change: `ios/PurePace/` 业务源码（Audio/播报、AudioSession 适配器、CoreLocation/定位、持久化、UI）零改动；`ios/Core`、`ios/RunCore` 业务逻辑零改动；本项只改 plist 声明、工程生成产物、测试与上述直接耦合的 shell 断言。
- ac-corelocation-isolation: `CLLocationManager`/`CoreLocation` 只出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`，且 Harness 内核（参数解析、流解析、驱动编排、status 构建、checkpoint 节奏）不 import CoreLocation/SwiftUI，可用 fake 采样源在 `PurePaceTests` 中单测。
- ac-imports-scoped: `check-ios-shell.sh` 的 App import 允许表新增 `CoreLocation`，且 `CoreLocation` 仅允许出现在 `ios/PurePace/Harness/*.swift` 与 `ios/PurePace/Location/*.swift`；`AVFoundation` 仍只允许在 `ios/PurePace/Audio/`；`MapKit/HealthKit/CoreMotion/UserNotifications/URLSession` 等仍判失败；页面显式文件清单断言不放松（已改为真实 UI 清单）；新增断言带 `--self-test` 反例自检。
- ac-build-test-green: `bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 退出码 0；`xcodebuild test -only-testing:PurePaceTests` 在 iPhone 16 / iOS 18.6 模拟器通过，既有音频/Harness 用例不减少且真实跑步 UI 用例 ≥ 1（无 `XCTSkip` 或条件跳过）；`.munk/code-gates.json` 既有门语义不放宽（门数自 `wi_intake_11dc6b68d0c7555d` 起收敛为 22 门快腿拓扑，重腿移出本地阻断，见 `ios-ci-stability`）。
- ac-runcore-unchanged: `ios/RunCore/**` 默认零改动；`bash scripts/check-ios-run-core.sh`、`swift test --package-path ios/RunCore` 全绿；RunCore 仍只 `import Foundation`。若确需为装配补一个可选字段，必须保持旧 JSONL 可解码且同步补 RunCore 单测（默认路径不改）。
- ac-evidence-wording: 交付结论只写「模拟器契约通过」「配置与调度契约通过」；「后台锁屏连续定位」「音乐不打断与 duck 恢复」「TTS 实听」一律 `pending: 待人现场`；不得出现「已验证」「实听通过」「真机后台定位可用」。
- ac-shell-gate-consistent: `bash scripts/check-ios-shell.sh` 退出 0；pbxproj 相关断言为「生成后 pbxproj 确实存在 + `git ls-files` 无 tracked pbxproj + `.gitignore` 命中该生成物 + 额外/游离 pbxproj（排除 ignored 生成物）仍判失败」；两次 generate 零 diff、本地包引用与无远程包断言保留，不得因 ignored 生成物伪红。
- ac-scripts-gate-consistent: `bash scripts/check-ios-scripts.sh` 退出 0；`build-ios.sh` / `test-ios.sh` 的分支判定与 `--help` 文案一致（工程缺失且有 xcodegen 时由 spec 生成，仍不可用才 `blocked:` + SwiftPM 降级），脚本字面量与顺序锚点断言（含 `xcodegen generate`）保持或加强，未删除、未放宽。
- ac-code-gates-22-green: `.munk/code-gates.json` 仍为 22 门（不新增门腿），本地先 `xcodegen generate` 并刷新 `.build/ios` 后 22 门全绿；`ac-built-plist-readback` 不得因陈旧产物伪红，也不得以改产品代码掩盖。
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
- bundle id 统一 `sh.munk.purepace`（与 Android `PUREPACE_APPLICATION_ID` 口径一致、同一产品标识），只在 `project.yml` 一处 `PUREPACE_BUNDLE_ID` 定义，`.tests` / `.uitests` 由该变量派生；改名后 App Store Connect 记录需人侧新建/更新（仓库只在 `docs/release/testflight-runbook.md` 提示）。
- 版本派生：`MARKETING_VERSION` 只能来自根 `VERSION`（经 `scripts/sync-ios-version.sh` → `ios/Config/Version.xcconfig`），`project.yml`、源码与脚本均不得写死当前版本字面值；`CURRENT_PROJECT_VERSION` 用常量构建号。
- 依赖/分层：仅允许以本地 path package 依赖 `ios/RunCore`（`PurePaceRunCore`），不得声明远程/第三方 SwiftPM 依赖；`AVFoundation` 只允许出现在 `ios/PurePace/Audio/` 适配器，`CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`；`ContentView` 只做 Tab 容器与入口分支，跑步数值只经 `RunSessionOrchestrator.metrics`；`ios/PurePace/` 不放样例数据，示例数据只允许出现在测试代码中。
- Harness launch arg 契约（下游脚本据此驱动，不得改名）：`--harness <direct|corelocation|resume>` 出现即激活，缺省完全不激活；`--status <绝对路径>` 三模式必填，`--stream <绝对路径>` 仅 `direct` 必填，`--checkpoint <绝对路径>` 三模式必填（direct/corelocation 追加、resume 读取），`--max-duration <秒>` 可选按活跃时长自动 `finish`；Harness 自行创建 status/checkpoint 父目录。
- Harness 内核与契约：JSONL 直接流为 UTF-8 一行一对象、时间统一 epoch 秒；status 为唯一对外可观测面（原子写：同目录临时文件 + 原子替换），`schemaVersion=1`，每次接受采样/状态迁移后更新，禁止依赖日志或 UI 文本断言；顺序固定 `ingest` → `AnnouncementScheduler.tick` → `RunCheckpointStore.append`，checkpoint 只经 `RunCheckpointStore` 读写（禁自建 JSON 拼接/内存伪文件），resume 用 `announcedSplitIndex ?? splits.count` 播种调度器。
- CoreLocation 适配：`CLLocationManager` 只在 Harness 目录使用并经最小采样源协议注入纯逻辑内核（单测用 fake，不触真实定位）；`requestWhenInUseAuthorization()` 授权后才 `startUpdatingLocation()`；精度阈值 50 m、首点仅锚点；`finish`/超时/去初始化时停止采样；不引入后台持续采集的运行时承诺。
- 门禁形态：`command` 保持单一 argv，多步流程封装进 `scripts/` 下 bash 脚本（`set -euo pipefail`、幂等、支持 `--help`、以仓库根为路径基准）；构建/测试产物（含整个 `ios/PurePace.xcodeproj/`）由忽略规则覆盖，不入库。
- destination 钉住 iPhone 16 且必须带 `OS=18.6`（或等价 UDID）：只写 `name=iPhone 16` 会被解析成 `latest` 运行时（本机为 iOS 26.3.1，无 iPhone 16 机型）而构建失败；工程缺失时脚本先按 spec 生成，仍不可用才走 `blocked:` + SwiftPM 降级分支，不得让门禁因此失败。
- 门禁共存：本域 `lint-ios-shell` 与脚本契约门 `lint-ios-scripts` 必须同时通过；后者对 destination 的断言按「iPhone 16 + 可选 OS/UDID」校验，不得放宽为任意机型。
- 证据口径：只报真实命令输出摘要与用例数，不写「CI 通过」「真机已验证」；本地门通过不替代远端 run；结论限「模拟器契约通过」「配置与调度契约通过」。模拟器三链路编排与报告契约见 `ios-sim-runtime` 域。

## 最近交付证明

- workItemId: wi_intake_1aa34f98b6e5f9a3（2026-11-10，pass）
- 交付：`ac-legacy-bundle-id-grep-exempt` 的豁免清单删去已移除的 device 取证脚本与 `docs/device-assertion-matrix.md`，只保留历史证据 `docs/evidence/**`、`artifacts/**`；bundle id 技术结论与其余断言不变，`scripts/**`、`ios/**` 零改动。
- 实测：`code_gates` 22 门全绿（`lint-ios-shell` 27 项断言 0 失败）；`bash scripts/test-ios.sh` 全量腿退出 0，单测 125 例 + UI 6 例 0 失败。真机与 TestFlight 仍为 `pending: 待人现场`。
