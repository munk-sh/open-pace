# Domain: ios-runcore

跑步域纯逻辑包：独立 SwiftPM package `ios/RunCore`（模块 `PurePaceRunCore`）。承载值类型契约（状态、距离/配速、采样点与锚点、分段、播报命令、音频配置镜像、错误）、会话状态机、JSONL checkpoint 存储/恢复、距离/配速/分段度量引擎、每公里播报调度与音频会话动作契约、GPX 1.1 编解码与无 UI 校验 CLI；纯逻辑 + `Foundation` 文件 IO，不接 UI/平台框架/网络。与 `ios-core`（`PurePaceCore`）边界分离，不合并。

## 范围

- `ios/RunCore/Package.swift`：`// swift-tools-version: 6.0`、`name: "PurePaceRunCore"`、`.iOS(.v17)` + `.macOS(.v14)`（macOS 上可 `swift build`/`swift test`）、零外部依赖；targets `PurePaceRunCore` + `PurePaceRunCoreTests` + 唯一可执行 `PurePaceGpxTool`。
- 布局固定 `ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Sources/PurePaceGpxTool/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
- `Sources/PurePaceRunCore/` 全 `public`、值语义、显式 `Sendable`、仅 `import Foundation`，无平台框架；契约类型与度量引擎不含 IO，IO 只在 `RunCheckpointStore` 与 `GPXCodec.write/read`：
  - `RunSessionState`（`ready/running/paused/finished`，`String` 原始值）及派生 `isActive`/`isTerminal`；枚举不含迁移逻辑。
  - `RunDistance`（`meters`）、`RunPace`（`secondsPerKilometer`，可由距离+时长派生）。
  - `RunSample`（经纬度/海拔/时间戳/心率/步频）、`RunSampleAnchor`（只含纬度/经度/时间戳，`init?` 拒绝越界坐标与 `distantPast`/`distantFuture`；供 checkpoint 恢复锚点与引擎暴露）、`RunSplit`（`index` + 距离 + 时长，派生 `pace`）。
  - `AnnouncementTrigger`、`AnnouncementCommand`（触发源/分段序号/距离/配速/已用时长）。
  - `AudioCategory` / `AudioMode` / `AudioCategoryOption`（含 `notifyOthersOnDeactivation`，追加在末尾，既有 case rawValue/顺序不变）/ `AudioSessionSettings`：纯数据镜像，**不 import AVFoundation**；`defaultAnnouncement` 冻结公告配置。
  - `RunCoreError`（`Error, Equatable, Sendable`，`CustomStringConvertible`）。
- 播报调度与音频会话契约（纯逻辑，`struct`/`enum` + `mutating`，不用 `Date()` 时钟源）：
  - `AnnouncementScheduler`：唯一输入口 `mutating func tick(_ update: RunMetricsUpdate, state: RunSessionState) -> [AnnouncementCommand]`；`init(announcedSplitIndex: Int = 0)` 支持重启后按已播公里序号恢复（负值按 0，缺省等价全新）；公里边界按 `newlyCompletedSplits` 一次且仅一次播报，内部 `lastAnnouncedSplitIndex` 去抖，`ready`/`paused` 恒空，`finished` 只补 1 条收尾（已完成公里数为 0 则无），`paused→running` 对未播公里最多补播 1 条 `.resumedAfterPause`。
  - `AudioSessionCoordinator` + `AudioSessionState` / `AudioSessionAction`：不 `import AVFoundation`，只产出动作值供波 2 App target 执行；激活幂等、`deactivate()` 携带 `.notifyOthersOnDeactivation`、interruption `began`/`ended(shouldResume:)` 状态机冻结。
- 会话与持久化（同包内，`struct` 全 `Sendable`）：
  - `RunSessionMachine`：`init(state:)`、`canTransition(to:)`、`mutating transition(to:) throws`、语义化 `start()/pause()/resume()/finish()`、`init(restoring:)`；非法迁移抛 `RunCoreError.invalidStateTransition(from:to:)` 且状态不变。
  - `RunCheckpoint`（手写 `Codable`）：`formatVersion`（唯一合法 1）/`state`/`completedDistance`/`elapsed`/`splits`/`recordedAt`，另加可选 `lastSample: RunSampleAnchor?` 与 `announcedSplitIndex: Int?`（构造默认 `nil`，`decodeIfPresent` 解码，缺键与 `null` 均得 `nil`）；`init?` 校验有限非负 `elapsed`、`splits` 索引从 1 连续、时间非 `distantPast`/`distantFuture`、`ready` 时零距离零分段且无 `lastSample`、`announcedSplitIndex` 在 `0...splits.count`。
  - `RunCheckpointStore`（持有 `fileURL: URL`）：JSONL 追加写盘（每行 UTF-8 JSON + `\n`）、`loadAll()`、`loadLatest()`、`reset()`；缺失文件视为空，尾行损坏静默丢弃，非尾行损坏抛 `corruptedCheckpoint`。
- 度量引擎（纯逻辑，全 `Sendable`、无 `class`/`actor`/全局可变状态）：
  - `GeoDistance.swift`：公开 Haversine 纯函数，地球平均半径常量 `6_371_000.0`，`min(1.0, sqrt(h))` 防 `asin` 越界。
  - `RunMetrics.swift`：快照（累计 `RunDistance`、活跃 `elapsed`、`averagePace`/`currentPace`、`splits`、整公里计数）与 `RunMetricsUpdate`（快照 + `newlyCompletedSplits`）。
  - `RunMetricsEngine.swift`：唯一输入口 `ingest(_ sample: RunSample) -> RunMetricsUpdate`、`start(at:)`/`pause(at:)`/`resume(at:)`/`finish(at:)` 四个幂等锚点，以及 `init(restoring: RunCheckpoint)`（还原累计距离、活跃时长、已完成分段、分段计时基准＝`splits` 的 `duration` 之和、最后采样锚点；`running`/`paused` → 暂停态，`finished` → 已结束，`ready` → 未开始）与只读 `lastAcceptedSample: RunSampleAnchor?`；不解析 JSONL、不接 CoreLocation、不含时间格式化。
  - 阈值以命名常量硬编码：分段 `1000.0` m、当前配速窗口 `10.0` s、窗口最小距离 `5.0` m、最小活跃时长 `3.0` s。
- GPX 编解码（仅 Foundation）：`GPXTrack`（`name`/`description?`/`createdAt`/`activityType`/`points: [RunSample]`，复用 `RunSample`；空名/空点/相邻点时间递减为 `nil`）、`GPXCodecError`（`invalidDocument`/`missingTrack`/`unsupportedNamespace`/`invalidPoint(index:reason:)`/`ioFailure`，描述非空且互异，不改 `RunCoreError`）、`GPXCodec`（`encode`/`decode`/`write`/`read`）。
- GPX 1.1 输出：默认命名空间 `http://www.topografix.com/GPX/1/1` 与 `gpxtpx` `.../TrackPointExtension/v1`；`metadata/{name,desc?,time}`、`trk/{name,type,trkseg/trkpt[@lat,@lon]}`，子元素顺序固定 `ele?/time/extensions?`；`hr`/`cad` 仅在存在时写入；UTC 秒级 ISO 8601 以 `Z` 结尾、坐标 ≥ 6 位小数、输出确定。
- GPX 1.1 回读：`XMLParser` 开启 `shouldProcessNamespaces` 并精确匹配两个命名空间；命名空间不符、缺 `trk/trkseg`、`trkpt` 缺 `lat/lon` 或越界、`time` 不可解析一律抛 `GPXCodecError`，不返回部分结果。
- `Sources/PurePaceGpxTool/main.swift`：无 UI 校验 CLI，`--input`/`--output`；参数缺失或未知退 2，解析/IO 失败退 3 并 stderr 打 `error:`，成功退 0，`--help` 退 0；不含夹具路径字面量。
- `scripts/check-gpx-export.sh`：结构沿用 `check-ios-core.sh`（`set -euo pipefail`、`BASH_SOURCE` 推根、pass/fail 计数 +「N 项断言，M 项失败」、`--help`、未知参数退 2）；`mktemp -d` + `trap` 真实跑工具，`xmllint --noout` + `python3` 逐字段比对 `shared/fixtures/sample-run.gpx`。
- 门禁：`.munk/code-gates.json` 保留既有 19 个 `id`/`command`（含 `lint-ios-run-core`、`build-ios-run-core`、`test-ios-run-core`、`check-gpx-export`）；`scripts/check-ios-run-core.sh` 恰好放行一个 `PurePaceGpxTool` executable target；`scripts/test-ios.sh` 保留既有 RunCore 入口。
- 跑次归档与 GPX 文件导出（`RunRecord`/`RunArchiveStore`/`RunGPXExporter`）为本包增量能力，契约与验收见 `ios-runcore-archive` 域。

## 验收

Package / 门禁：
- ac-run-core-package-builds: `swift build --package-path ios/RunCore` 退 0，且不解析外部依赖（无 `.package(url:)`）。
- ac-run-core-tests-pass: `swift test --package-path ios/RunCore` 退 0、失败 0、执行数 ≥ 1，命令不含 `xcodebuild`/`-destination`/UDID。
- ac-run-core-package-shape: `Package.swift` 含 tools 6.0、包名、`.iOS(.v17)`、`.macOS(.v14)`、测试 target、唯一可执行 `PurePaceGpxTool`；三个目录齐备。
- ac-run-core-zero-deps: `swift package dump-package` 的 `dependencies` 为空数组，无 `.package(`/`url:`/`path:` 依赖。
- ac-run-core-foundation-only: `Sources/**`（含可执行 target）仅 `import Foundation`，无 `CoreLocation|CLLocationManager|AVFoundation|AVFAudio|AVAudioSession|CoreMotion|MapKit|HealthKit|SwiftUI|UIKit|UserNotifications|URLSession|CoreData|SQLite|SwiftData|Timer` 符号。
- ac-run-core-no-fixture-tokens: `ios/RunCore/**` 无 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌；`check-shared.sh` 仍 PASS。
- ac-run-core-no-version-literal: `ios/RunCore/**`（排除 `.build`/`.swiftpm`）与 `check-ios-run-core.sh` 均不含根 `VERSION` 字面值。
- ac-run-core-xctest-only: `Tests/` 有 `import XCTest`、无 `import Testing`、≥1 个 `test*`；公开契约类型各有合法/非法断言，并用泛型辅助锁定 `Sendable`。
- ac-run-core-domain-contracts: 单测锁定 `allCases` 顺序与 `isActive`/`isTerminal`；`RunDistance`/`RunPace`/`RunSample`/`RunSplit`/`AnnouncementCommand` 对负值/非有限/越界/零值输入返回 `nil`；`AudioSessionSettings` 选项相等性；`RunCoreError` 各 case 描述非空且互异。
- ac-run-core-gate-script: `bash scripts/check-ios-run-core.sh` 退 0 并逐条 `[PASS]`；`--help` 退 0 含「用法」；未知参数退 2；`bash -n` 通过；可执行。
- ac-run-core-gate-self-test: `--self-test` 退 0，注入 `import UIKit`/`.package(url:)`/版本字面值等违规后真实报失败。
- ac-code-gates-ios-run-core: `.munk/code-gates.json` 既有 19 个 `id`/command 全部保留（含 `lint-ios-run-core`/`build-ios-run-core`/`test-ios-run-core`/`check-gpx-export`），command 为单一 argv、无 shell 分隔符/重定向；`check-baseline.sh` 全 PASS。
- ac-test-ios-runcore-entry: `scripts/test-ios.sh` 含字面量 `swift test --package-path ios/RunCore`，保留 `xcodebuild test`/`-scheme`/`ios/PurePace.xcodeproj`/`swift test --package-path ios/Core`/`blocked:`/iPhone 16 destination；RunCore 失败时退出码非 0，缺失时打 `blocked:` 不伪造成功。
- ac-build-artifacts-ignored: `swift build`/`swift test`/`check-gpx-export` 后 `git status --porcelain` 不出现 `ios/RunCore/.build/`、`ios/RunCore/.swiftpm/`。
- ac-swift-test-green: `swift test --package-path ios/RunCore` 退 0 且失败 0；本项只新增用例（`ResumeContractTests`），既有断言不改；`check-ios-run-core.sh`、`check-baseline.sh` 全 `[PASS]`。
- ac-gates-no-regression: `bash scripts/check-ios-run-core.sh` 与 `swift build --package-path ios/RunCore` 通过；`.munk/code-gates.json` 门禁数量不减少、不新增门。
- ac-gate-check-gpx-export: 原有 19 个 `id`/command 保留，新增 `check-gpx-export` = `bash scripts/check-gpx-export.sh`；全部 command 不含 `&&`/`||`/`|`/`;`/`>`/`<`。
- ac-gates-green: `check-ios-run-core.sh`、`swift build`、`swift test` 全退 0 且无失败用例；19 个既有 `id`/command 不变。

状态机：
- ac-session-legal-matrix: 5 条合法迁移全部成功；`canTransition(to:)` 对 16 种组合与 `transition(to:)` 实际结果逐对一致。
- ac-session-illegal-rejected: 其余 11 种（含全部自迁移、`ready→paused/finished`、`finished→*`）抛 `invalidStateTransition`，`from`/`to` 正确且状态不变。
- ac-session-event-entrypoints: `start()` 仅 `.ready`、`pause()` 仅 `.running`、`resume()` 仅 `.paused`、`finish()` 仅 `.running`/`.paused`；错误状态抛错且状态不变。

Checkpoint：
- ac-checkpoint-real-file: `append` 后磁盘真实存在文件，每次恰一行、以 `\n` 结尾、可独立 UTF-8 JSON 解码；旧行字节前缀不变。
- ac-checkpoint-roundtrip: 新 store 实例 `loadLatest()` 等于最后 append（含 `state`/距离/`elapsed`/`splits`/`recordedAt`）；`loadAll()` 按写入顺序返回全部。
- ac-checkpoint-missing-and-empty: 文件不存在或 0 字节时 `loadLatest()` 为 `nil`、`loadAll()` 为空且不抛错。
- ac-checkpoint-partial-tail-discarded: 末行截断（无结尾换行/JSON 不完整）时不抛错，只返回截断前完整记录。
- ac-checkpoint-corrupt-tail-discarded: 末行合法 JSON 但违约（负距离、非有限 `elapsed`、未知版本、`splits` 断裂）按尾行丢弃，返回前一条。
- ac-checkpoint-middle-corruption-throws: 非末行损坏抛 `corruptedCheckpoint`（描述非空），不静默跳过。
- ac-checkpoint-creates-directory: 父目录不存在时 `append` 创建并写入；`reset()` 后文件不存在，重复 `reset()` 幂等成功。
- ac-checkpoint-last-sample-roundtrip: 带 `lastSample` 的 checkpoint 经 JSON 编码→解码、以及 `append`→`loadLatest` 落盘往返后纬度/经度/时间戳数值相等。
- ac-checkpoint-announced-index-roundtrip: 带 `announcedSplitIndex` 的 checkpoint 编码/解码与落盘往返后序号不变。
- ac-checkpoint-legacy-decode: 缺 `lastSample`/`announcedSplitIndex` 两键的旧 JSON 行可正常解码且两字段为 `nil`，其余字段不变；`loadAll` 对新旧混合文件两行都计入有效记录。
- ac-checkpoint-new-field-validation: `lastSample` 坐标越界、时间为 `distantPast`/`distantFuture`、`announcedSplitIndex` 为负或大于 `splits.count` 时构造返回 `nil`。
- ac-checkpoint-ready-no-sample: `state == .ready` 且携带 `lastSample` 的 checkpoint 构造返回 `nil`。

恢复：
- ac-recovery-running-paused: 由 `.running`/`.paused` 的 checkpoint 恢复均得 `.paused`，随后 `resume()` 合法；恢复不改 `completedDistance`/`elapsed`/`splits`。
- ac-recovery-terminal-and-ready: `.finished` 恢复后 `start()`/`pause()`/`resume()` 均抛错且状态不变；`.ready` 恢复后 `start()` 可进 `.running`。
- ac-restart-keeps-completed-splits: 全新 store 实例 `loadLatest()` 恢复后 `splits` 数量与逐项 `index/distance/duration`、`completedDistance` 与写入值全等。
- ac-engine-restore-ledger: 由 `distance=2500`、`elapsed=900`、`splits` 序号 1..2 的 checkpoint 恢复后 `distance == 2500`、`elapsed == 900`、`splits` 序号 1..2、`completedKilometers == 2`、平均配速 == `elapsed/(distance/1000)`。
- ac-engine-restore-paused-state: 由 `.running`/`.paused` 恢复的引擎未 `resume` 前 `ingest` 不改 `distance`/`elapsed`/`splits`；`resume(at:)` 后恢复累计。
- ac-engine-restore-continues-splits: 恢复后继续跨过 3 km，新分段从序号 3 起、不重复 1/2；第 3 段 `duration` ≈ 恢复后累计 `elapsed` − 恢复的 `splits` 时长之和（±1e-6 s）。
- ac-engine-restore-anchor: 由带 `lastSample` 的 checkpoint 恢复后，`timestamp` 等于锚点的样本被丢弃（账本不变）；更晚同坐标样本只增 `elapsed`（等于时间差），`distance` 不变。
- ac-engine-restore-no-sample-anchor: 由无锚点（旧格式）checkpoint 恢复后，首个被接受样本只建锚点（`distance`/`elapsed` 不增），其后样本才累计位移。
- ac-engine-restore-finished: 由 `.finished` 恢复的引擎已结束，后续 `ingest`/`finish` 不改 `metrics`。
- ac-engine-exposes-last-sample: `lastAcceptedSample` 等于最后一次被接受样本的坐标与时间戳；无样本或旧格式恢复为 `nil`；带锚点恢复后等于该锚点。

度量与播报：
- ac-first-sample-no-metrics: 首个被接受样本只建锚点——`distance == 0`、`elapsed == 0`、`averagePace`/`currentPace` 为 `nil`、`splits` 空；其后才产生非零距离。
- ac-announcement-exactly-once-per-km: 覆盖第 1..N 公里时每个 `splitIndex` 恰 1 条 `.kilometerCompleted`，全程不重复且序号递增。
- ac-announcement-duplicate-tick-debounced: 相同 `RunMetricsUpdate`（含非空 `newlyCompletedSplits`）连续 tick 只首次出命令，重复 10 次仍为空。
- ac-announcement-paused-suppressed: `.paused`/`.ready` 时 tick 恒为空。
- ac-announcement-finished-stops: `.finished` 最多 1 条 `.finished`（`splitIndex` = 已完成公里数、`elapsed` = `metrics.elapsed`），零公里则无；此后恒空。
- ac-announcement-resume-catch-up-once: `paused→running` 首次 tick 对未播公里最多 1 条 `.resumedAfterPause`（未播最大序号）；同恢复期再 tick 为空，总数 ≤ 1。
- ac-announcement-command-fields: 命令均 `splitIndex >= 1`、`elapsed` 有限非负、`distance == splitIndex*1000 ±1e-9`、`pace` 与该分段一致、`elapsed` 单调不减；未满 1 km 无命令。
- ac-scheduler-restore-no-repeat: 以 `announcedSplitIndex = 2` 恢复的调度器首次 `tick(state: .running, ...)` 带 `newlyCompletedSplits [1,2]` 返回空；随后带分段 3 恰返回 1 条 `splitIndex == 3` 的 `.kilometerCompleted`，重复同一 tick 再返回空。
- ac-scheduler-restore-default: 未给已播序号（`nil`/`0`/负数）与全新调度器行为一致：分段 1 首次 tick 仍回 1 条命令。
- ac-audiosession-settings-values: 默认公告 `category == .playback`、`mode == .spokenAudio`、`options == {duckOthers, mixWithOthers}`、`deactivationOptions == {notifyOthersOnDeactivation}`。
- ac-audiosession-deactivate-option: `deactivate()` 动作携带 `.notifyOthersOnDeactivation`；`.active` 停用后 `.inactive`，`.inactive` 再停用返回 `.none`。
- ac-audiosession-interruption-lifecycle: `.active` + `began` → `.interrupted` 且无激活动作；`ended(true)` → `.active` 且动作为默认配置重激活；`ended(false)` → `.inactive` 且 `.none`；重复 `began` 幂等。
- ac-audiosession-activation-idempotent: `.inactive → activate()` 产出 1 次激活动作且 `.active`；`.active` 再 `activate()` 返回 `.none`。
- ac-runcore-purity-preserved: `Sources/**` 仅 `import Foundation`，无平台符号、无 `class`/`actor`/全局可变/`@unchecked`，新公开类型显式 `Sendable`，包依赖为空。
- ac-announcement-audio-existing-unchanged: 既有公开签名、枚举 `allCases` 顺序与 rawValue、5 条合法迁移、阈值常量不变；`AudioCategoryOption.allCases.count` 仅允许 4→5 并断言包含关系。
- ac-haversine-constant: 地球半径常量 `6_371_000.0` 由单测直接断言；4 点合成轨迹累加 `691.16 m ± 0.05 m`，与夹具 `derived_distance_m: 691.2` 口径一致。
- ac-distance-error-le-1pct: 5:00/km 与 7:00/km 合成 1 Hz 流（各 ≥600 点）累计距离相对误差 ≤ 1.0%。
- ac-average-pace-error-le-2s: 上述两流 `averagePace` 相对真值误差 ≤ 2.0 s/km。
- ac-current-pace-error-le-2s: 窗口预热完成后每点 `currentPace` 误差 ≤ 2.0 s/km；预热期返回 `nil`。
- ac-split-boundary-within-1-sample: 分段序号从 1 连续；完成点与「距离首次 ≥ n×1000 m」最近采样点相差 ≤ 1 点；每段 `distance == 1000.0`（<1e-9）、`duration > 0`、`pace` 非 `nil`。
- ac-split-cumulative-consistency: `splits.count` 等于整公里计数、`count*1000 <= distance + 1e-9`，单调不减且不被改写/重复发出。
- ac-duplicate-point-zero-delta: 同坐标更晚样本增 0 m、不改 `splits`，活跃时长照常推进。
- ac-time-regression-ignored: `timestamp <= 上一个已接受采样点` 的样本整条丢弃，账本不变。
- ac-pause-excludes-time-and-distance: 暂停期 `elapsed` 冻结、`currentPace == nil`，暂停采样（含位移）不累计；`resume` 后恢复，暂停空档不计入且跨暂停相邻点无位移。
- ac-idempotent-anchors: 重复 `start`/`pause`/`resume`/`finish`（含未 start 直接 `ingest`）不崩溃、不产生负值；早于账本时间的锚点被忽略。

GPX 与导出：
- ac-gpx-roundtrip-real-file: 用 `NSTemporaryDirectory()` 真实写 `.gpx` 再 `read` 读回，断言点数与每点 `latitude/longitude/altitude/timestamp/heartRate/cadence` 全等，用例结束删除临时文件。
- ac-gpx-namespaces-and-extensions: 输出含 `version="1.1"` 与两个命名空间声明，`hr`/`cad` 位于 `gpxtpx:TrackPointExtension` 之下。
- ac-gpx-optional-fields: `altitude`/`heartRate`/`cadence` 为 `nil` 时不输出对应元素，输出仍可 `decode` 回且字段一致。
- ac-gpx-decode-rejects-invalid: 无 `trkseg/trkpt`、命名空间不符、`lat="91"`、`time` 非 ISO 8601 各抛对应 `GPXCodecError`；`read` 不存在路径抛 `ioFailure`。
- ac-gpx-tool-cli: `swift build --product PurePaceGpxTool` 退 0；`--help` 退 0 含「用法」；未知参数与缺 `--output` 各退 2；不存在输入退 3 且 stderr 含 `error:`。
- ac-check-gpx-export-pass: `bash scripts/check-gpx-export.sh` 退 0 并逐条 `[PASS]`；`xmllint --noout` 退 0，四个 `trkpt` 逐字段与夹具一致。
- ac-check-gpx-export-no-skip: `xmllint`/`python3`/`swift` 缺失各走 fail 并非零退出，无 `skip`/`exit 0` 兜底。
- ac-check-gpx-export-hygiene: shebang、`set -euo pipefail`、`BASH_SOURCE`；`bash -n` 通过；`--help` 退 0 含「用法」；未知参数退 2；可执行。
- ac-run-core-gate-allows-tool: `check-ios-run-core.sh` 与 `--self-test` 退 0；`PurePaceGpxTool` 不再违规；self-test 含「注入非 `PurePaceGpxTool` executable → 失败」反例。
- ac-gpx-no-ui-export-entry: `ios/` 下无 `ShareLink`/`fileExporter`/`UIDocumentPicker`/`UIActivityViewController`/`UIActivityItemProvider`；`git status --porcelain` 对 `ios/PurePace/**`、`project.yml`、`.xcodeproj`、`shared/` 为空。
- ac-runcore-layer-only: 新增代码只落 `Sources/PurePaceRunCore/`、`Sources/PurePaceGpxTool/`、`Tests/PurePaceRunCoreTests/`。
- ac-no-frozen-contract-break: 既有公开字段/初始化签名/用例语义不变；不为既有类型新增 `Codable`；不新增 `AnnouncementTrigger` case、不放宽 `AnnouncementCommand` 校验。
- ac-no-platform-or-ui-change: 未改 `ios/project.yml`/`.xcodeproj`/`ios/PurePace/**`/`shared/**`/`android/**`/`.github/workflows/**`/`VERSION`/`README.md`/`AGENTS.md`/`scripts/version.sh` 与既有门禁 command。
- ac-evidence-wording: 交付结论只写「配置与调度契约通过」；音乐/duck、TTS 实听、锁屏后台定位一律 `pending: 待人现场`，不写「已验证」「实听通过」「真机通过」。

## 非目标

- 不在本域实现真实发声/音频路由：TTS 播放、`AVAudioSession` 真实激活与读回、音量与 duck 实测归波 2 App target；`AnnouncementScheduler`/`AudioSessionCoordinator` 只到动作值与纯逻辑契约；不持久化 `finished` 收尾播报状态（重启后是否重发收尾命令由上层决定，本域只保证公里不重播），checkpoint 写盘时机与快照节流归波 2 Harness/编排。
- 不做 GPX 导入 UI/导入流程接线、App target 音频适配器、CoreLocation 接入、模拟器 Harness 与 `verify-ios-sim-runtime.sh`；不跑 `xcrun simctl`/`xcodebuild`。度量引擎只做计时/距离账本（锚点幂等，不做状态辩论），checkpoint 只做存盘与会话恢复（不做距离重算、不产生新分段），跨进程 terminate→relaunch 编排归波 2。
- 不写采样流 JSONL 解析器、不在 RunCore 内读夹具、不做精度过滤/首点漂移剔除（适配器职责）；GPX 只覆盖「与夹具同构的导出/回读 + CLI 校验」，不做批量转换、压缩/加密容器或后台导出。
- 不新增导出页/按钮/`ShareLink`/`fileExporter`/`UIDocumentPicker`/分享上传入口；不把 `PurePaceRunCore` 接进 App target（本地包接入 XcodeGen 属后续子项）；可执行 target 唯一放行 `PurePaceGpxTool`。
- 不改动 `check-ios-core.sh`/`check-ios-scripts.sh`/`check-ios-shell.sh`/`check-shared.sh`/`check-baseline.sh` 的既有断言语义；`scripts/test-ios.sh` 只追加，不重排/不删除既有分支。
- 不写 `tech.md`、不改 `AGENTS.md`/`README.md`/`VERSION`、不碰 `shared/`、`android/`、CI workflow、Host 托管文件。
- 不做真机、签名、推送、CI run；不写「CI 通过」「真机已验证」类结论；真机项（后台锁屏连续定位、音乐不打断与 duck 恢复）仍为 `pending: 待人现场`。

## 实现约束

- 宿主 Swift 6.2 / Xcode 26.3 / macOS arm64；`swift test` 走 macOS destination，`platforms` 必须同时含 `.macOS(.v14)` 与 `.iOS(.v17)`。
- Swift 6 严格并发：契约类型全为 `struct`/`enum` 值类型并显式 `Sendable`；不引入 `actor`、`class`、全局可变状态、`@unchecked`。
- 包名与模块名统一 `PurePaceRunCore`（目录 `RunCore`）；App/Harness 直接 `import PurePaceRunCore`。
- 夹具红线：RunCore 代码不出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌；夹具路径只能由 `scripts/` 以 CLI 参数传入（`check-shared.sh` 扫描整个 `ios/` 树）。
- 门禁命令为可直接执行的单一 argv；结构断言由 `scripts/*.sh` 承载（`set -euo pipefail`、幂等、`--help`、以仓库根为基准、pass/fail 计数 +「N 项断言，M 项失败」）。
- `--self-test` 把 `ios/RunCore` 复制到 `${TMPDIR:-/tmp}` 注入违规并复用同一批断言，结束清理，仓库不留临时文件。
- 版本禁写死：包内与自检脚本不出现根 `VERSION` 当前字面值；测试样例用与仓库版本无关的合成数值。
- 度量引擎输入口唯一：平台适配器与 JSONL 适配器都只把数据转成 `RunSample` 后喂同一 `ingest`；时间基准是 `RunSample.timestamp` 差值，不引入时区/格式化。
- 阈值不得放宽：验收阈值（1% 距离、2.0 s/km 配速、≤1 采样点分段边界）不得放松；分段尾差只体现在 `distance` 与 `currentPace`，不生成 `RunSplit`。
- 测试数据合成：坐标流用固定步长公式生成，时间统一 `Date(timeIntervalSince1970: n)`；不读磁盘、不引用夹具、不用 `Date()` 现时。
- `Timer` 是结构红线禁用子串：新增类型/常量命名不得包含该词。
- 构建产物：根 `.gitignore` 的 `.build/`、`.swiftpm/` 已覆盖嵌套路径，不改忽略规则。
- 状态机红线：不新增/重命名 case（`allCases` 顺序与 rawValue 锁定）；合法迁移恰 5 条，其余一律 `invalidStateTransition` 且状态不变。
- checkpoint 红线：文件即真源，`RunCheckpointStore` 是唯一落盘点，外面不得再包内存缓存层；`FileHandle` 追加 + 每行 `\n`，只用 `Foundation`；尾行丢弃、非尾行抛错、IO 不可读不得伪装成空结果。
- checkpoint 扩展红线：新字段一律可选、构造默认 `nil`、`decodeIfPresent` 解码（缺键与 `null` 均得 `nil`）；已写出的旧 JSONL 不得变成「非尾行损坏」；分段计时基准不新增字段，由 `splits` 的 `duration` 累加还原；`RunSampleAnchor` 复用坐标/时间校验，不引入平台类型。
- 恢复语义红线：`.running`/`.paused` 一律恢复为 `.paused`，禁止重启后静默冒充 running；`.ready`/`.finished` 原样恢复；恢复不改写 checkpoint 数据。
- 测试隔离：临时目录用 `FileManager.default.temporaryDirectory` + `UUID()` 子目录（或 `NSTemporaryDirectory()`），每用例独立并 `defer`/`tearDown` 清理；仍用 XCTest（禁 `import Testing`）。
- 调度器契约：内部 `lastAnnouncedSplitIndex` 负责去抖与幂等，禁止依赖调用方去重与时间间隔判定；时间取 `metrics.elapsed`；边界只认 `newlyCompletedSplits`，`distance`/`pace` 取 `RunSplit`。
- 音频契约：`AudioSessionCoordinator` 不 `import AVFoundation`，只返回 `AudioSessionAction` 值；`notifyOthersOnDeactivation` 以新 `AudioCategoryOption` case 表示，既有 rawValue 不改。
- GpxTool 红线：`check_foundation_only`/`check_no_platform_symbols` 扫描整个 `Sources`（含工具）；`check_no_fixture_tokens` 覆盖 `Tests/`。
- `scripts/check-ios-run-core.sh` 只做三处最小改动（放行 `PurePaceGpxTool`、门禁表加 `check-gpx-export`、self-test 加 executable 反例），不放宽既有断言。
- 证据口径：只报 `swift build`/`swift test` 真实输出摘要与用例数、脚本 PASS 计数；不写「已验证」「实听通过」「真机通过」，真机项统一 `pending: 待人现场`。

## 最近交付证明

- workItemId: wi_ws_270266b187a7a3e3（2026-11-07，pass，跨进程恢复契约：最后采样点、已播公里序号、引擎恢复入口、调度器恢复入口；只取代码层证据）
- 交付：`RunCheckpoint` 增可选 `lastSample`（新 `RunSampleAnchor`）与 `announcedSplitIndex`，手写 `Codable` 走 `decodeIfPresent`，旧 JSONL 行仍可读、`ready` 带锚点被拒；`RunMetricsEngine(restoring:)` 还原距离/时长/分段/分段计时基准（`splits.duration` 累加）/锚点，`running`/`paused` 落暂停态，新增只读 `lastAcceptedSample`；`AnnouncementScheduler(announcedSplitIndex:)` 重启后同序号不重播。新增 `ResumeContractTests`（18 例）。
- 验证：`code_gates` 全绿——`lint-ios-run-core` PASS、`build-ios-run-core` PASS、`test-ios-run-core` 87 例 0 失败；未改 `scripts/**`、`.munk/code-gates.json`（19 门不变）、`ios/PurePace/**`、`project.yml`、`shared/`、`android/`、CI、`VERSION`。checkpoint 写盘时机与 terminate→relaunch 编排仍 `pending`（归波 2）。
