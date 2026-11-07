# Domain: ios-runcore

跑步域纯逻辑包：独立 SwiftPM package `ios/RunCore`（模块名 `PurePaceRunCore`）。承载值类型契约（状态、距离/配速、采样点、分段、播报命令、音频配置镜像、错误）、会话状态机、JSONL checkpoint 存储/恢复、距离/配速/分段度量引擎、每公里播报调度与音频会话动作契约、GPX 1.1 编解码与无 UI 校验 CLI；纯逻辑 + `Foundation` 文件 IO，不接 UI/平台框架/网络。与 `ios-core`（`PurePaceCore`）边界分离，不合并。

## 范围

- `ios/RunCore/Package.swift`：`// swift-tools-version: 6.0`，`name: "PurePaceRunCore"`，platforms 同时声明 `.iOS(.v17)` 与 `.macOS(.v14)`（macOS host 上可直接 `swift build` / `swift test`），零外部依赖；targets 为 `PurePaceRunCore` + `PurePaceRunCoreTests`，另加唯一可执行 target `PurePaceGpxTool`（product 同名，仅依赖 `PurePaceRunCore`）。
- 布局固定 `ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Sources/PurePaceGpxTool/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
- `Sources/PurePaceRunCore/` 全部 `public`、值语义、显式 `Sendable`，仅 `import Foundation`，无平台框架；契约类型与度量引擎不含 IO，IO 只出现在 `RunCheckpointStore` 与 `GPXCodec.write/read`：
  - `RunSessionState`（`ready/running/paused/finished`，`String` 原始值）及派生只读 `isActive`、`isTerminal`；枚举本身不含迁移逻辑。
  - `RunDistance`（`meters`）、`RunPace`（`secondsPerKilometer`，并可由距离+时长派生）。
  - `RunSample`（经纬度/海拔/时间戳/心率/步频）、`RunSplit`（`index` + 距离 + 时长，派生 `pace`）。
  - `AnnouncementTrigger`、`AnnouncementCommand`（触发源 / 分段序号 / 距离 / 配速 / 已用时长）。
  - `AudioCategory` / `AudioMode` / `AudioCategoryOption` 与 `AudioSessionSettings`：纯数据镜像，**不 import AVFoundation**；`AudioCategoryOption` 含 `notifyOthersOnDeactivation`（追加在末尾，既有 case rawValue/顺序不变），`AudioSessionSettings.defaultAnnouncement` 冻结公告配置。
  - `RunCoreError`（`Error, Equatable, Sendable`，`CustomStringConvertible`）。
- 播报调度与音频会话契约（纯逻辑，全 `struct`/`enum` + `mutating`，不用 `Date()` 时钟源）：
  - `AnnouncementScheduler`：唯一输入口 `mutating func tick(_ update: RunMetricsUpdate, state: RunSessionState) -> [AnnouncementCommand]`；公里边界按 `newlyCompletedSplits` 一次且仅一次播报，内部 `lastAnnouncedSplitIndex` 去抖，`ready`/`paused` 恒空，`finished` 只补 1 条收尾（已完成公里数为 0 则无），`paused→running` 对未播公里最多补播 1 条 `.resumedAfterPause`。
  - `AudioSessionCoordinator` + `AudioSessionState` / `AudioSessionAction`：不 `import AVFoundation`，只产出动作值供波 2 App target 执行；激活幂等、`deactivate()` 携带 `.notifyOthersOnDeactivation`、interruption `began`/`ended(shouldResume:)` 状态机冻结。
- 会话与持久化（同包内，`struct` 全 `Sendable`）：
  - `RunSessionMachine`（持有 `state: RunSessionState`）：`init(state:)`、`canTransition(to:)`、`mutating transition(to:) throws`、语义化 `start()/pause()/resume()/finish()`，以及 `init(restoring:)`；非法迁移抛 `RunCoreError.invalidStateTransition(from:to:)` 且状态不变。
  - `RunCheckpoint`（手写 `Codable`）：`formatVersion`（唯一合法 1）/`state`/`completedDistance`/`elapsed`/`splits`/`recordedAt`，`init?` 校验有限非负 `elapsed`、`splits` 索引从 1 连续、时间非 `distantPast`/`distantFuture`、`ready` 时零距离零分段。
  - `RunCheckpointStore`（持有 `fileURL: URL`）：JSONL 追加写盘（每行 UTF-8 JSON + `\n`）、`loadAll()`、`loadLatest()`、`reset()`；缺失文件视为空，尾行损坏静默丢弃，非尾行损坏抛 `corruptedCheckpoint`。
- 度量引擎（纯逻辑，全 `Sendable`、无 `class`/`actor`/全局可变状态）：
  - `GeoDistance.swift`：公开 Haversine 纯函数（输入两组经纬度返回米），地球平均半径命名常量 `6_371_000.0`，`min(1.0, sqrt(h))` 防 `asin` 越界。
  - `RunMetrics.swift`：快照值类型（累计 `RunDistance`、活跃 `elapsed`、`averagePace`/`currentPace: RunPace?`、`splits: [RunSplit]`、整公里计数）与 `RunMetricsUpdate`（快照 + `newlyCompletedSplits`）。
  - `RunMetricsEngine.swift`：唯一输入口 `ingest(_ sample: RunSample) -> RunMetricsUpdate`，外加 `start(at:)`/`pause(at:)`/`resume(at:)`/`finish(at:)` 四个幂等锚点；不解析 JSONL、不接 CoreLocation、不含时间格式化。
  - 阈值以命名常量硬编码、不配置化：分段 `1000.0` m、当前配速窗口 `10.0` s 活跃时间、窗口最小有效距离 `5.0` m 且最小活跃时长 `3.0` s。
- GPX 编解码（仅 Foundation）：`GPXTrack`（`name`/`description?`/`createdAt`/`activityType`/`points: [RunSample]`，**复用 `RunSample`** 不另建点类型；空名/空点/相邻点时间戳递减为 `nil`）、`GPXCodecError`（`invalidDocument`/`missingTrack`/`unsupportedNamespace`/`invalidPoint(index:reason:)`/`ioFailure`，`description` 非空且互不相同，**不改** `RunCoreError` case 集合）、`GPXCodec`（`encode`/`decode`/`write`/`read`）。
- GPX 1.1 输出契约：默认命名空间 `http://www.topografix.com/GPX/1/1` 与 `gpxtpx` 扩展命名空间 `.../TrackPointExtension/v1`；`metadata/name`、可选 `metadata/desc`、`metadata/time`（首点时间）；`trk/name`、`trk/type`、`trk/trkseg/trkpt[@lat,@lon]`，子元素顺序固定 `ele?/time/extensions?`；`hr`/`cad` 仅在存在时写入 `gpxtpx:TrackPointExtension`；UTC 秒级 ISO 8601 以 `Z` 结尾、坐标 ≥ 6 位小数、同一输入输出确定。
- GPX 1.1 回读契约：`XMLParser` 开启 `shouldProcessNamespaces`，精确匹配上述两个命名空间；命名空间不符、缺 `trk/trkseg`、`trkpt` 缺 `lat/lon` 或越界、`time` 不可解析一律抛 `GPXCodecError`，不返回部分结果。
- `Sources/PurePaceGpxTool/main.swift`：无 UI 的校验用 CLI，`--input <path>` 读、`--output <path>` 写；参数缺失或未知退 2，解析/IO 失败退 3 并 stderr 打 `error:`，成功退 0，`--help` 退 0；源码不含任何夹具路径字面量。
- `scripts/check-gpx-export.sh`：结构沿用 `check-ios-core.sh`（`set -euo pipefail`、`BASH_SOURCE` 推根、pass/fail 计数 +「N 项断言，M 项失败」、`--help`、未知参数退 2）；`mktemp -d` + `trap` 真实跑工具，`xmllint --noout` + `python3` 逐字段比对 `shared/fixtures/sample-run.gpx`（`trkpt` 恰 4 个；坐标/海拔 `abs(delta) <= 1e-6`；时间按同一瞬间；`hr`/`cad` 整数相等）。
- 门禁：`.munk/code-gates.json` 保留既有 19 个 `id`/`command`（含 `lint-ios-run-core`、`build-ios-run-core`、`test-ios-run-core`），新增 `check-gpx-export`（`bash scripts/check-gpx-export.sh`，单一 argv）；`scripts/check-ios-run-core.sh` 恰好放行一个 `PurePaceGpxTool` executable target（self-test 含改名/第二个 executable 反例）；`scripts/test-ios.sh` 保留既有 RunCore 入口。

## 验收

- ac-run-core-package-builds: 仓库根执行 `swift build --package-path ios/RunCore` 退出码 0，且不解析任何外部依赖（无 `.package(url:)`、无网络包解析）。
- ac-run-core-tests-pass: 仓库根执行 `swift test --package-path ios/RunCore` 退出码 0，实际执行用例数 ≥ 1、失败数 = 0，命令不含 `xcodebuild` / `-destination` / 模拟器 UDID / `-sdk iphonesimulator`。
- ac-run-core-package-shape: `Package.swift` 含 `// swift-tools-version: 6.0`、`name: "PurePaceRunCore"`、`.iOS(.v17)`、`.macOS(.v14)`、`PurePaceRunCoreTests`、唯一可执行 target `PurePaceGpxTool`；存在 `Sources/PurePaceRunCore/`、`Sources/PurePaceGpxTool/` 与 `Tests/PurePaceRunCoreTests/`。
- ac-run-core-zero-deps: `swift package dump-package --package-path ios/RunCore` 的 `dependencies` 为空数组，且 `Package.swift` 无 `.package(` / `url:` / `path:` 依赖声明。
- ac-run-core-foundation-only: `ios/RunCore/Sources/**`（含可执行 target）的全部 `import` 仅 `Foundation`；且不出现 `CoreLocation|CLLocationManager|AVFoundation|AVFAudio|AVAudioSession|CoreMotion|MapKit|HealthKit|SwiftUI|UIKit|UserNotifications|URLSession|CoreData|SQLite|SwiftData|Timer` 任一符号。
- ac-run-core-no-fixture-tokens: `ios/RunCore/**` 不出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌（`bash scripts/check-shared.sh` 仍 PASS）。
- ac-run-core-no-version-literal: `ios/RunCore/**`（排除 `.build`/`.swiftpm`）不出现根 `VERSION` 的当前字面值；`scripts/check-ios-run-core.sh` 自身亦不含该字面值。
- ac-run-core-xctest-only: `Tests/` 至少 1 个 `test*` 方法、`import XCTest` 存在、`import Testing` 不存在；每个公开契约类型均有合法/非法两条以上断言，且公开类型均通过编译期 `Sendable` 约束（泛型辅助函数锁定）。
- ac-run-core-domain-contracts: 单测锁定公开面行为——`RunSessionState.allCases` 恰为 `ready/running/paused/finished` 且 `ready.isActive==false`、`running.isActive==true`、`paused.isActive==true`、`finished.isTerminal==true`、`finished.isActive==false`；`RunDistance(meters: -1)`/`.infinity` 为 `nil` 而 `0` 合法；`RunPace(secondsPerKilometer: 0)`/负值/`nan` 为 `nil`，`RunPace(distance:duration:)` 在零距离或零时长时为 `nil`；`RunSample` 对纬度 `91`、经度 `181`、负心率、零步频为 `nil`，对合法点非 `nil` 且字段一致；`RunSplit(index: 0)`/非正时长为 `nil`，合法值 `pace` 非 `nil`；`AnnouncementCommand(splitIndex: 0)`/负 `elapsed` 为 `nil`；`AudioSessionSettings` 的 `options`/`deactivationOptions` 与入参一致且相等性判断正确；`RunCoreError` 每个 case 的 `description` 非空且互不相同。
- ac-run-core-gate-script: `bash scripts/check-ios-run-core.sh` 在当前树退出 0 且逐条打印 `[PASS]`；`--help` 退出 0 且含「用法」；未知参数退出 2；`bash -n` 通过；文件可执行。
- ac-run-core-gate-self-test: `bash scripts/check-ios-run-core.sh --self-test` 退出 0，并在注入 `import UIKit` / `.package(url:)` / 版本字面值等违规后真实报出失败（反例自检，不靠跳过或 `true` 冒充）。
- ac-code-gates-ios-run-core: `.munk/code-gates.json` 既有门禁 `id` 与 command 全部保留，新增 `lint-ios-run-core` / `build-ios-run-core` / `test-ios-run-core` / `check-gpx-export`，command 为单一 argv、无 shell 分隔符/重定向；`bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-test-ios-runcore-entry: `scripts/test-ios.sh` 直接包含字面量 `swift test --package-path ios/RunCore`，同时保留 `xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:` 与 iPhone 16 destination；`--help` 说明新增 RunCore 分支；RunCore 测试失败时脚本退出码非 0；`ios/RunCore` 缺失时打印 `blocked:` 并继续，不伪造成功行。
- ac-build-artifacts-ignored: `swift build` / `swift test` / `check-gpx-export` 之后 `git status --porcelain` 不出现 `ios/RunCore/.build/`、`ios/RunCore/.swiftpm/`（复用根 `.gitignore`，不新增或放宽忽略规则）。
- ac-session-legal-matrix: 5 条合法迁移（`ready→running`、`running→paused`、`running→finished`、`paused→running`、`paused→finished`）全部成功且落点状态正确；`canTransition(to:)` 对 16 种组合的返回值与 `transition(to:)` 实际成功/抛错逐对穷举一致。
- ac-session-illegal-rejected: 其余 11 种组合（含全部自迁移、`ready→paused/finished`、`finished→*`）抛 `RunCoreError.invalidStateTransition`，`error.from`/`error.to` 与实际一致，抛错后 `machine.state` 不变。
- ac-session-event-entrypoints: `start()` 仅 `.ready`、`pause()` 仅 `.running`、`resume()` 仅 `.paused`、`finish()` 仅 `.running`/`.paused` 成功；错误状态调用抛错且状态不变。
- ac-checkpoint-real-file: `append` 后磁盘真实存在 `fileURL`，每次 append 恰一行、以 `\n` 结尾、可独立 UTF-8 解码为 JSON；追加 N 次后行数 N，旧行字节前缀不变（不整文件重写）。
- ac-checkpoint-roundtrip: 新 `RunCheckpointStore` 实例 `loadLatest()` 与最后 append 相等（含 `state`/`completedDistance`/`elapsed`/`splits`/`recordedAt`）；`loadAll()` 按写入顺序返回全部记录。
- ac-checkpoint-missing-and-empty: 文件不存在或 0 字节时 `loadLatest()` 返回 `nil`、`loadAll()` 返回空数组且不抛错。
- ac-checkpoint-partial-tail-discarded: 末行被截断（无结尾换行或 JSON 不完整）时 `loadLatest()`/`loadAll()` 不抛错，只返回截断前的有效完整记录。
- ac-checkpoint-corrupt-tail-discarded: 末行为合法 JSON 但违反契约（负距离、非有限 `elapsed`、未知 `formatVersion`、`splits` 序号断裂）时按尾行丢弃，返回前一条有效记录且不抛错。
- ac-checkpoint-middle-corruption-throws: 非末行损坏/非法时 `loadLatest()`/`loadAll()` 抛 `RunCoreError.corruptedCheckpoint`（描述非空），不得静默跳过。
- ac-checkpoint-creates-directory: 父目录不存在时 `append` 创建目录并写入；`reset()` 后文件不存在，重复 `reset()` 幂等成功。
- ac-recovery-running-paused: 由 `.running`/`.paused` 的 checkpoint 恢复均得 `.paused`，随后 `resume()` 合法并可到 `.running`；恢复不修改 `completedDistance`/`elapsed`/`splits`。
- ac-recovery-terminal-and-ready: `.finished` 恢复后为 `.finished`，`resume()`/`start()`/`pause()` 均抛错且状态不变；`.ready` 恢复后为 `.ready`，`start()` 可进入 `.running`。
- ac-restart-keeps-completed-splits: 含 ≥2 个已完成分段的 checkpoint 经全新 store 实例（模拟新进程）`loadLatest()` 并恢复后，`splits` 数量与逐项 `index/distance/duration`、`completedDistance` 与写入值完全相等。
- ac-runcore-layer-only: 新增代码只落 `ios/RunCore/Sources/PurePaceRunCore/`、`ios/RunCore/Sources/PurePaceGpxTool/` 与 `ios/RunCore/Tests/PurePaceRunCoreTests/`；`Sources/**` 的 `import` 仍仅 `Foundation`，不出现平台符号、`shared/fixtures`/夹具令牌与根 `VERSION` 字面值。
- ac-no-frozen-contract-break: `RunSessionState`/`RunDistance`/`RunPace`/`RunSample`/`RunSplit`/`Announcement*`/`AudioSessionSettings`/`RunCoreError` 的既有公开字段、初始化签名与既有用例语义不变；不为既有类型新增 `Codable`（`RunCheckpoint` 自行编码原始字段）；不新增 `AnnouncementTrigger` case、不放宽 `AnnouncementCommand` 校验。
- ac-swift-test-green: 仓库根 `swift test --package-path ios/RunCore` 退出码 0、失败数 0 且新用例真实执行；`bash scripts/check-ios-run-core.sh`、`bash scripts/check-baseline.sh` 全 `[PASS]`；`.munk/code-gates.json` 既有门（含 `lint-ios-run-core`/`build-ios-run-core`/`test-ios-run-core`/`check-gpx-export`）id 与 command 不变。
- ac-announcement-exactly-once-per-km: 连续 tick 覆盖第 1..N 个整公里时，每个 `splitIndex` 恰好产生 1 条 `trigger == .kilometerCompleted` 命令；全程命令序列中任何 `splitIndex` 都不重复出现，且序号严格递增。
- ac-announcement-duplicate-tick-debounced: 用完全相同的 `RunMetricsUpdate`（含非空 `newlyCompletedSplits`）连续 tick 两次，第二次返回空数组；重复 10 次仍只有首次那批命令，`completedKilometers` 不变时不再产出。
- ac-announcement-paused-suppressed: 状态 `.paused` 时 tick 恒返回空数组（即使携带 `newlyCompletedSplits`）；`.ready` 同样恒空。
- ac-announcement-finished-stops: 进入 `.finished` 时最多产出 1 条 `trigger == .finished` 命令（`splitIndex == 已完成公里数`、`elapsed == metrics.elapsed`），已完成公里数为 0 则不产出；此后任意 tick 恒空且不再出现 `.kilometerCompleted`。
- ac-announcement-resume-catch-up-once: `paused → running` 后首次 tick 对「已完成但未播报」的公里最多产出 1 条 `.resumedAfterPause`（`splitIndex` 为未播报的最大公里序号）；同一恢复期再次 tick 返回空；第二次恢复若无新未播公里亦返回空；不得逐条补播（总数 ≤ 1）。
- ac-announcement-command-fields: 所有产出命令均满足 `splitIndex >= 1`、`elapsed` 有限非负、`distance.meters == splitIndex * 1000 ± 1e-9`、`pace` 与该分段 `RunSplit.pace` 一致、`elapsed` 单调不减；未满 1 公里时全程无命令。
- ac-audiosession-settings-values: 默认公告配置断言 `category == .playback`、`mode == .spokenAudio`、`options == Set([.duckOthers, .mixWithOthers])`（恰好两项）、`deactivationOptions == Set([.notifyOthersOnDeactivation])`（恰好一项）。
- ac-audiosession-deactivate-option: `deactivate()` 返回动作携带 `.notifyOthersOnDeactivation`（动作值断言）；`.active` 停用后状态 `.inactive`，`.inactive` 再次停用返回 `.none` 且状态不变。
- ac-audiosession-interruption-lifecycle: `.active` 收到 `interruptionBegan` → `.interrupted` 且不产生激活动作；`ended(shouldResume: true)` → `.active` 且动作等于按默认公告配置重新激活；`ended(shouldResume: false)` → `.inactive` 且动作 `.none`；重复 `began` 幂等且不重复激活；非 `.interrupted` 时 `ended` 返回 `.none` 且状态不变。
- ac-audiosession-activation-idempotent: `.inactive → activate()` 产出 1 次激活动作且状态 `.active`；`.active` 再次 `activate()` 返回 `.none`，状态仍 `.active`。
- ac-runcore-purity-preserved: `ios/RunCore/Sources/**` 仍只 `import Foundation`，不出现 `AVFoundation|AVAudioSession|AVSpeechSynthesizer|CoreLocation|UIKit|SwiftUI|Timer` 等平台符号，不新增 `class`/`actor`/全局可变状态/`@unchecked`，新增公开类型显式 `Sendable`，包依赖仍为空。
- ac-announcement-audio-existing-unchanged: `RunSessionState`/`RunMetrics`/`RunSplit`/`RunMetricsEngine` 的既有公开签名、枚举 `allCases` 顺序与 rawValue、5 条合法迁移、阈值常量均不变；既有 RunCore 用例继续通过（因新增 `notifyOthersOnDeactivation` 仅允许把 `AudioCategoryOption.allCases.count` 断言由 4 改为 5 并断言包含关系，不得删除既有用例）。
- ac-first-sample-no-metrics: 首个被接受的 `RunSample` 只建立锚点——`distance == 0`、`elapsed == 0`、`averagePace == nil`、`currentPace == nil`、`splits.isEmpty`；其后第一个有效点才产生非零距离。
- ac-haversine-constant: 距离函数使用常量地球半径 `6_371_000.0`（单测直接断言该常量值）；对 4 个合成坐标点（纬 31.2304→31.2358、经 121.4737→121.4773，逐点 +0.0018/+0.0012）累加得 `691.16 m ± 0.05 m`，与 `shared/fixtures/README.md` 的 `derived_distance_m: 691.2` 口径一致。
- ac-distance-error-le-1pct: 对 5:00/km 与 7:00/km 两条合成 1 Hz 流（各 ≥ 600 点、恒定航向），引擎累计距离相对误差 `≤ 1.0%`（与同流独立 Haversine 逐段累加值比较）。
- ac-average-pace-error-le-2s: 上述两条恒定配速流，`averagePace.secondsPerKilometer` 相对真值误差 `≤ 2.0 s/km`。
- ac-current-pace-error-le-2s: 恒定配速流中，滑动窗口预热完成（窗口内有效距离达到最小阈值）之后每个采样点 `currentPace` 误差 `≤ 2.0 s/km`；预热期返回 `nil` 而非不可靠值。
- ac-split-boundary-within-1-sample: 分段序号从 1 连续递增；第 n 段完成点与「累计距离首次 ≥ n×1000 m」的理论最近采样点相差 `≤ 1` 个采样点；每段 `RunSplit.distance == 1000.0 m`（差 < 1e-9）、`duration > 0` 为该段活跃时长差、`pace` 非 `nil`。
- ac-split-cumulative-consistency: 任意快照 `splits.count` 等于已跨过整公里计数，且 `Double(splits.count) * 1000 <= distance.meters + 1e-9`；`splits.count` 单调不减，已发出的分段不被后续采样改写或重复发出。
- ac-duplicate-point-zero-delta: 与上一点经纬度完全相同（时间更晚）的样本产生 0 m 增量，不改变 `splits`、不新增整公里计数；活跃时长按正常计时推进。
- ac-time-regression-ignored: `timestamp <= 上一个已接受采样点` 的样本整条丢弃——距离、活跃时长、分段、整公里计数全部与丢弃前一致（无负增量、不回退）。
- ac-pause-excludes-time-and-distance: `pause(at:)` 期间 `elapsed` 冻结、`currentPace == nil`；暂停区间采样点（含坐标位移）不累计距离与活跃时长；`resume(at:)` 后恢复累计，暂停空档不计入 `elapsed`，跨越暂停的相邻两点之间不产生位移。
- ac-idempotent-anchors: 重复 `start`/`pause`/`resume`/`finish` 调用（含未 `start` 直接 `ingest`）不崩溃、不产生负时长或非有限值；早于当前账本时间的非法锚点被忽略而非反向计时。
- ac-gpx-roundtrip-real-file: `Tests/` 内 GPX round-trip 用例用 `NSTemporaryDirectory()` 真实写 `.gpx` 再由 `GPXCodec.read` 读回，断言点数与每点 `latitude/longitude/altitude/timestamp/heartRate/cadence` 与输入全等，且用例结束删除临时文件（仓库无残留）。
- ac-gpx-namespaces-and-extensions: `encode` 结果含 `version="1.1"`、`xmlns="http://www.topografix.com/GPX/1/1"`、`xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`，且 `hr`/`cad` 位于 `gpxtpx:TrackPointExtension` 之下（字符串或解析结构断言均可）。
- ac-gpx-optional-fields: `altitude == nil` 的点输出无 `<ele>`；`heartRate == nil` 且 `cadence == nil` 的点无 `gpxtpx:hr`/`gpxtpx:cad`；该输出仍能被 `decode` 读回且字段与输入一致。
- ac-gpx-decode-rejects-invalid: 「无 `trkseg/trkpt`」「默认命名空间非 GPX 1.1」「`lat="91"`」「`time` 非 ISO 8601」四类输入各抛对应 `GPXCodecError` case（不 crash）；`read(from:)` 对不存在路径抛 `ioFailure`。
- ac-gpx-tool-cli: `swift build --package-path ios/RunCore --product PurePaceGpxTool` 退 0；`--help` 退 0 且含「用法」；`--definitely-invalid` 与缺 `--output` 各退 2；`--input /nonexistent/x.gpx --output <tmp>` 退 3 且 stderr 含 `error:`。
- ac-check-gpx-export-pass: `bash scripts/check-gpx-export.sh` 退 0 且逐条打印 `[PASS]`；`xmllint --noout` 对工具输出返回 0，四个 `trkpt` 的 `lat/lon/ele/time/hr/cad` 与夹具逐点一致。
- ac-check-gpx-export-no-skip: 脚本对 `xmllint`/`python3`/`swift` 缺失各走 `fail` 分支并非零退出（存在 `command -v` 判定与失败输出，无 `skip`/`exit 0` 兜底）。
- ac-check-gpx-export-hygiene: shebang `#!/usr/bin/env bash`、含 `set -euo pipefail` 与 `BASH_SOURCE`；`bash -n` 通过；`--help` 退 0 且含「用法」；未知参数退 2；文件可执行。
- ac-gate-check-gpx-export: `.munk/code-gates.json` 原有 19 个 `id` 与 `command` 全部保留，新增 `check-gpx-export` 且 command 为 `bash scripts/check-gpx-export.sh`；全部 command 不含 `&&`/`||`/`|`/`;`/`>`/`<`；`bash scripts/check-baseline.sh` 仍全 PASS。
- ac-run-core-gate-allows-tool: `bash scripts/check-ios-run-core.sh` 与 `--self-test` 均退 0；`Package.swift` 的 `PurePaceGpxTool` 不再被判违规，self-test 中「注入非 `PurePaceGpxTool` 的 executable target → 失败」反例被真实执行。
- ac-gpx-no-ui-export-entry: `ios/` 下不出现 `ShareLink`、`fileExporter`、`UIDocumentPicker`、`UIActivityViewController`、`UIActivityItemProvider`；`git status --porcelain` 对 `ios/PurePace/**`、`ios/project.yml`、`ios/PurePace.xcodeproj`、`shared/` 为空。
- ac-no-platform-or-ui-change: 未新增/修改 `ios/project.yml`、`ios/PurePace.xcodeproj`、`ios/PurePace/**`、`shared/**`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`、`scripts/version.sh` 与既有门禁 command。
- ac-gates-green: 仓库根 `bash scripts/check-ios-run-core.sh`、`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore` 全部退出码 0 且无失败用例；`.munk/code-gates.json` 19 个既有 `id`/command 不变。
- ac-evidence-wording: 交付结论只写「配置与调度契约通过」；音乐/duck、TTS 实听、锁屏后台定位一律 `pending: 待人现场`，不得出现「已验证」「实听通过」「真机通过」。

## 非目标

- 不在本域实现真实发声/音频路由：`AVSpeechSynthesizer`/TTS 播放、`AVAudioSession` 真实激活与读回、音量与 duck 实测归波 2 App target 适配子项；`AnnouncementScheduler`/`AudioSessionCoordinator` 只到动作值与纯逻辑契约；不做跨进程播报状态持久化（`checkpoint` 不新增「已播公里」），不把中断与播报队列耦合。
- 不做 GPX 导入 UI/导入流程接线、App target 音频适配器、CoreLocation 接入、模拟器 Harness 与 `verify-ios-sim-runtime.sh`；不跑 `xcrun simctl` / `xcodebuild`。度量引擎只做计时/距离账本（锚点幂等，不做状态辩论），checkpoint 只存盘与会话恢复（不做距离重算、不产生新分段），跨进程 terminate→relaunch 编排归波 2。
- 不写采样流 JSONL 解析器、不在 RunCore 内读夹具文件、不做精度过滤/首点漂移剔除（适配器侧职责）；GPX 能力只覆盖「与夹具同构的轨迹导出/回读 + CLI 校验」，不做批量转换、压缩/加密容器或后台导出。
- 不新增导出页/导出按钮/`ShareLink`/`fileExporter`/`UIDocumentPicker`/分享上传入口；不把 `PurePaceRunCore` 接进 App target（本地包接入 XcodeGen 属后续子项）；可执行 target 唯一放行 `PurePaceGpxTool`，不新增其他 executable。
- 不做 XcodeGen 接入（本地包进 `.xcodeproj` 留给后续子项，届时需放宽 `check-ios-shell.sh` 仅对本地包）。
- 不改动 `check-ios-core.sh` / `check-ios-scripts.sh` / `check-ios-shell.sh` / `check-shared.sh` / `check-baseline.sh` 的既有断言语义；`scripts/test-ios.sh` 只追加，不重排/不删除既有分支。
- 不写 `tech.md`、不改 `AGENTS.md`/`README.md`/`VERSION`、不碰 `shared/`、`android/`、CI workflow、Host 托管文件。
- 不做真机、签名、推送、CI run；不写「CI 通过」「真机已验证」类结论；真机项（后台锁屏连续定位、音乐不打断与 duck 恢复）仍为 `pending: 待人现场`。

## 实现约束

- 宿主环境 Swift 6.2 / Xcode 26.3 / macOS arm64；`swift test` 走 macOS destination，故 `platforms` 必须同时含 `.macOS(.v14)` 与 `.iOS(.v17)`。
- Swift 6 语言模式（严格并发）：契约类型全为 `struct`/`enum` 值类型并显式 `Sendable`；不引入 `actor`、`class`、全局可变状态、`@unchecked`。
- 包名与模块名统一 `PurePaceRunCore`（目录名 `RunCore`）；阶段 3 的 App/Harness 直接 `import PurePaceRunCore`。
- 夹具红线：RunCore 代码不得出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌；夹具路径只能由 `scripts/` 以 CLI 参数传入（`check-shared.sh` 扫描整个 `ios/` 树）。
- 门禁命令必须为可直接执行的单一 argv；结构断言一律由 `scripts/` 下 bash 脚本承载（`set -euo pipefail`、幂等、`--help`、以仓库根为路径基准、`pass`/`fail` 计数与「N 项断言，M 项失败」输出风格）。
- `--self-test` 把 `ios/RunCore` 复制到 `${TMPDIR:-/tmp}` 临时目录注入违规，复用同一批断言（断言函数以包路径为参数），结束清理；不得在仓库内留临时文件。
- 版本禁写死：包内与自检脚本均不出现根 `VERSION` 当前字面值；测试样例使用与仓库版本无关的合成数值。
- 度量引擎输入口唯一：平台适配器与 JSONL 适配器都只把数据转成 `RunSample` 后喂入同一 `ingest`，不为两套数据源各开接口；时间基准是 `RunSample.timestamp` 差值，不引入时区/格式化。
- 阈值不得放宽：Coding 可按测试微调常量命名与实现，但验收阈值（1% 距离、2.0 s/km 配速、≤1 采样点分段边界）不得放松；分段尾差只体现在 `distance` 与 `currentPace`，不生成 `RunSplit`。
- 测试数据合成：坐标流在测试内用固定步长公式生成，时间统一 `Date(timeIntervalSince1970: n)` 构造；不读磁盘、不引用夹具文件、不使用 `Date()` 现时。
- 注意 `Timer` 是结构红线禁用子串：新增类型/常量命名不得包含该词。
- 构建产物：根 `.gitignore` 的 `.build/`、`.swiftpm/` 已覆盖嵌套路径，不改忽略规则；若 `git status --porcelain` 仍出现产物，从包落点修正。
- 状态机红线：`idle` 等同既有 `ready`，不新增/重命名枚举 case（`allCases` 顺序与 rawValue 已锁定）；合法迁移矩阵恰为 5 条，其余一律 `invalidStateTransition` 且状态不变；语义化入口复用同一校验，不另开旁路。
- checkpoint 红线：文件即真源，`RunCheckpointStore` 是唯一落盘点，外面不得再包内存缓存层；`FileHandle` 追加 + 每行 `\n`，只用 `Foundation`（`FileManager`/`Data`/`FileHandle`/`JSONEncoder`/`JSONDecoder`/`URL`），不引入 `OutputStream`/SQLite/`UserDefaults`；尾行丢弃、非尾行抛错、IO 不可读不得伪装成空结果。
- 恢复语义红线：`.running`/`.paused` 一律恢复为 `.paused`，禁止进程重启后静默冒充 running；`.ready`/`.finished` 原样恢复；恢复不改写 checkpoint 数据。
- 测试隔离：临时目录用 `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`（或 `NSTemporaryDirectory()`）的独立子目录，每用例独立并 `defer`/`tearDown` 清理；仍用 XCTest（禁 `import Testing`），测试数值全部合成，不出现夹具令牌与根 `VERSION` 字面值。
- 调度器契约：内部 `lastAnnouncedSplitIndex`（或等价有序状态）负责去抖与幂等，禁止依赖调用方去重，禁止用时间间隔判定（无时钟源、不用 `Date()`）；时间统一取 `metrics.elapsed`；分段边界只认 `newlyCompletedSplits`，不复刻分段判定，`distance`/`pace` 取 `RunSplit`。
- 音频契约：`AudioSessionCoordinator` 不 `import AVFoundation`，只返回 `AudioSessionAction` 值（激活配置/停用选项/`.none`）；`notifyOthersOnDeactivation` 以 `AudioCategoryOption` 新 case 表示，既有 case rawValue 不改；两条路（新 case vs 独立枚举）只取其一。
- GpxTool 红线：`check_foundation_only`/`check_no_platform_symbols` 扫描整个 `Sources`（含 `PurePaceGpxTool`），工具同样只能 `import Foundation`；`check_no_fixture_tokens` 覆盖 `Tests/`，夹具路径仅由 `check-gpx-export.sh` 以 CLI 传入。
- `scripts/check-ios-run-core.sh` 只做三处最小改动（放行 `PurePaceGpxTool`、期望门禁表加 `check-gpx-export`、self-test 加 executable 反例），不得放宽零依赖/仅 Foundation/无平台符号/无夹具令牌/无 XcodeGen 产物等既有断言。
- 证据口径：只报 `swift build` / `swift test` 真实输出摘要与用例数、`check-ios-run-core.sh`、`check-gpx-export.sh` 的 PASS 计数；不得写「已验证」「实听通过」「真机通过」，真机项统一 `pending: 待人现场`。

## 最近交付证明

- workItemId: wi_ws_e21a5bd66cd74c34（2026-11-07，pass，`announcement-audio-contract`；checkpoint `cp-tts-audio-contract` 关闭，`cp-stage2-exit` 仅取代码层证据）
- 交付：新增 `AnnouncementScheduler.swift`（`tick(_:state:)`：公里一次且仅一次、重复 tick 去抖、`ready`/`paused` 抑制、`finished` 单条收尾、恢复最多补播 1 条）与 `AudioSessionCoordinator.swift`（激活幂等、停用携带 `.notifyOthersOnDeactivation`、interruption 状态机）；`AudioSessionSettings` 追加 `notifyOthersOnDeactivation` case 与 `defaultAnnouncement`（`.playback`/`.spokenAudio`/激活 `{duckOthers, mixWithOthers}`/停用 `{notifyOthersOnDeactivation}`）；新增两个测试文件，仅把 `AudioCategoryOption.allCases.count` 由 4 改 5。配置与调度契约通过；实听与锁屏后台连续定位 `pending: 待人现场`。
- 验证：`code_gates` 全绿——`lint-ios-run-core` PASS、`build-ios-run-core` / `test-ios-run-core` 真实无失败；未改 `.munk/code-gates.json`（19 门不变）、`scripts/**`、`ios/PurePace/**` / `project.yml` / `.xcodeproj` / `shared/` / `android/` / CI / `VERSION`。
