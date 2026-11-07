# Domain: ios-runcore

跑步域纯逻辑包：独立 SwiftPM package `ios/RunCore`（包名/模块名 `PurePaceRunCore`，目录名 `RunCore`）。承载两类内容：值类型契约（状态枚举、距离/配速、采样点、分段、播报命令、音频配置镜像、错误类型）与纯逻辑度量引擎（Haversine 距离、累计距离/活跃时长/当前与平均配速、公里分段）；不接 UI、平台框架、文件/网络/JSON。与 `ios-core`（`PurePaceCore`，基础设施）边界分离，不做合并。

## 范围

- `ios/RunCore/Package.swift`：`// swift-tools-version: 6.0`，`name: "PurePaceRunCore"`，platforms 同时声明 `.iOS(.v17)` 与 `.macOS(.v14)`（macOS host 上可直接 `swift build` / `swift test`），零外部依赖，targets 仅 `PurePaceRunCore` + `PurePaceRunCoreTests`。
- 布局固定 `ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
- `Sources/PurePaceRunCore/` 契约文件全部 `public`、值语义、显式 `Sendable`，仅 `import Foundation`，无平台框架、IO 或持久化：
  - `RunSessionState`（`ready/running/paused/finished`，`String` 原始值）及派生只读 `isActive`、`isTerminal`；不含迁移逻辑。
  - `RunDistance`（`meters`）、`RunPace`（`secondsPerKilometer`，并可由距离+时长派生）。
  - `RunSample`（经纬度/海拔/时间戳/心率/步频）、`RunSplit`（`index` + 距离 + 时长，派生 `pace`）。
  - `AnnouncementTrigger`、`AnnouncementCommand`（触发源 / 分段序号 / 距离 / 配速 / 已用时长）。
  - `AudioCategory` / `AudioMode` / `AudioCategoryOption` 与 `AudioSessionSettings`：纯数据镜像，**不 import AVFoundation**。
  - `RunCoreError`（`Error, Equatable, Sendable`，`CustomStringConvertible`）。
- 度量引擎（纯逻辑，同包内 `import Foundation`、全 `Sendable`、无 `class`/`actor`/全局可变状态）：
  - `GeoDistance.swift`：公开 Haversine 纯函数（输入两组经纬度返回米），地球平均半径命名常量 `6_371_000.0`，`min(1.0, sqrt(h))` 防 `asin` 越界。
  - `RunMetrics.swift`：快照值类型（累计 `RunDistance`、活跃 `elapsed`、`averagePace`/`currentPace: RunPace?`、`splits: [RunSplit]`、整公里计数）与 `RunMetricsUpdate`（快照 + `newlyCompletedSplits`）。
  - `RunMetricsEngine.swift`：唯一输入口 `ingest(_ sample: RunSample) -> RunMetricsUpdate`，外加 `start(at:)`/`pause(at:)`/`resume(at:)`/`finish(at:)` 四个幂等锚点；不解析 JSONL、不接 CoreLocation、不含时间格式化。
  - 阈值以命名常量硬编码、不配置化：分段 `1000.0` m、当前配速窗口 `10.0` s 活跃时间、窗口最小有效距离 `5.0` m 且最小活跃时长 `3.0` s。
- 门禁：`.munk/code-gates.json` 新增 `lint-ios-run-core`（`bash scripts/check-ios-run-core.sh`）、`build-ios-run-core`（`swift build --package-path ios/RunCore`）、`test-ios-run-core`（`swift test --package-path ios/RunCore`）；`scripts/test-ios.sh` 追加 RunCore 入口。

## 验收

- ac-run-core-package-builds: 仓库根执行 `swift build --package-path ios/RunCore` 退出码 0，且不解析任何外部依赖（无 `.package(url:)`、无网络包解析）。
- ac-run-core-tests-pass: 仓库根执行 `swift test --package-path ios/RunCore` 退出码 0，实际执行用例数 ≥ 1、失败数 = 0，命令不含 `xcodebuild` / `-destination` / 模拟器 UDID / `-sdk iphonesimulator`。
- ac-run-core-package-shape: `Package.swift` 含 `// swift-tools-version: 6.0`、`name: "PurePaceRunCore"`、`.iOS(.v17)`、`.macOS(.v14)`、`PurePaceRunCoreTests`；存在 `Sources/PurePaceRunCore/` 与 `Tests/PurePaceRunCoreTests/`。
- ac-run-core-zero-deps: `swift package dump-package --package-path ios/RunCore` 的 `dependencies` 为空数组，且 `Package.swift` 无 `.package(` / `url:` / `path:` 依赖声明。
- ac-run-core-foundation-only: `ios/RunCore/Sources/**` 的全部 `import` 仅 `Foundation`；且不出现 `CoreLocation|CLLocationManager|AVFoundation|AVFAudio|AVAudioSession|CoreMotion|MapKit|HealthKit|SwiftUI|UIKit|UserNotifications|URLSession|CoreData|SQLite|SwiftData|Timer` 任一符号。
- ac-run-core-no-fixture-tokens: `ios/RunCore/**` 不出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌（`bash scripts/check-shared.sh` 仍 PASS）。
- ac-run-core-no-version-literal: `ios/RunCore/**`（排除 `.build`/`.swiftpm`）不出现根 `VERSION` 的当前字面值；`scripts/check-ios-run-core.sh` 自身亦不含该字面值。
- ac-run-core-xctest-only: `Tests/` 至少 1 个 `test*` 方法、`import XCTest` 存在、`import Testing` 不存在；每个公开契约类型均有合法/非法两条以上断言，且公开类型均通过编译期 `Sendable` 约束（泛型辅助函数锁定）。
- ac-run-core-domain-contracts: 单测锁定公开面行为——`RunSessionState.allCases` 恰为 `ready/running/paused/finished` 且 `ready.isActive==false`、`running.isActive==true`、`paused.isActive==true`、`finished.isTerminal==true`、`finished.isActive==false`；`RunDistance(meters: -1)`/`.infinity` 为 `nil` 而 `0` 合法；`RunPace(secondsPerKilometer: 0)`/负值/`nan` 为 `nil`，`RunPace(distance:duration:)` 在零距离或零时长时为 `nil`；`RunSample` 对纬度 `91`、经度 `181`、负心率、零步频为 `nil`，对合法点非 `nil` 且字段一致；`RunSplit(index: 0)`/非正时长为 `nil`，合法值 `pace` 非 `nil`；`AnnouncementCommand(splitIndex: 0)`/负 `elapsed` 为 `nil`；`AudioSessionSettings` 的 `options`/`deactivationOptions` 与入参一致且相等性判断正确；`RunCoreError` 每个 case 的 `description` 非空且互不相同。
- ac-run-core-gate-script: `bash scripts/check-ios-run-core.sh` 在当前树退出 0 且逐条打印 `[PASS]`；`--help` 退出 0 且含「用法」；未知参数退出 2；`bash -n` 通过；文件可执行。
- ac-run-core-gate-self-test: `bash scripts/check-ios-run-core.sh --self-test` 退出 0，并在注入 `import UIKit` / `.package(url:)` / 版本字面值等违规后真实报出失败（反例自检，不靠跳过或 `true` 冒充）。
- ac-code-gates-ios-run-core: `.munk/code-gates.json` 原有 16 个 `id` 全部保留且 command 不变，新增 `lint-ios-run-core` / `build-ios-run-core` / `test-ios-run-core`，command 为单一 argv、无 shell 分隔符/重定向；`bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-test-ios-runcore-entry: `scripts/test-ios.sh` 直接包含字面量 `swift test --package-path ios/RunCore`，同时保留 `xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:` 与 iPhone 16 destination；`--help` 说明新增 RunCore 分支；RunCore 测试失败时脚本退出码非 0；`ios/RunCore` 缺失时打印 `blocked:` 并继续，不伪造成功行。
- ac-build-artifacts-ignored: `swift build` / `swift test` 之后 `git status --porcelain` 不出现 `ios/RunCore/.build/`、`ios/RunCore/.swiftpm/`（复用根 `.gitignore`，不新增或放宽忽略规则）。
- ac-no-platform-or-ui-change: 未新增/修改 `ios/project.yml`、`ios/PurePace.xcodeproj`、`ios/PurePace/**`、`shared/**`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`、`scripts/version.sh` 与既有 16 门 command。
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
- ac-pure-foundation-and-no-io: 新增源码仅 `import Foundation`；`bash scripts/check-ios-run-core.sh` 全部 `[PASS]`（无平台框架符号、无夹具令牌、无版本字面值、XCTest only）。
- ac-existing-tests-still-pass: `swift test --package-path ios/RunCore` 退出码 0，既有 17 个用例仍通过，新增用例数 ≥ 8。
- ac-gates-not-reduced: `.munk/code-gates.json` 现有 19 个 `id` 全部保留且 command 不变；`bash scripts/check-baseline.sh` 仍全部 PASS。

## 非目标

- 不实现会话状态机迁移合法性判定（归同波状态机子项；度量引擎只做计时/距离账本，锚点幂等不做状态辩论）、每公里播报调度与去重、AudioSession 协调器与读回、GPX 1.1 导出、checkpoint 持久化与恢复；不写 JSONL 解析器、不读文件、不接 `CLLocationManager`、不做精度过滤/首点漂移剔除（适配器侧职责）。
- 不新增可执行 target（`PurePaceGpxTool` 归后续子项）；不建 App target、不接 CoreLocation/AVFoundation、不建 UI 页面。
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
- 度量引擎输入口唯一：平台适配器与 JSONL 适配器都只把数据转成 `RunSample` 后喂入同一 `ingest`，不为两套数据源各开接口，避免逻辑漂移；时间基准是 `RunSample.timestamp` 差值，不引入时区/格式化。
- 阈值不得放宽：Coding 可按测试微调常量命名与实现，但验收阈值（1% 距离、2.0 s/km 配速、≤1 采样点分段边界）不得放松；分段尾差只体现在 `distance` 与 `currentPace`，不生成 `RunSplit`。
- 测试数据合成：坐标流在测试内用固定步长公式生成，时间统一 `Date(timeIntervalSince1970: n)` 构造；不读磁盘、不引用夹具文件、不使用 `Date()` 现时。
- 注意 `Timer` 是结构红线禁用子串：新增类型/常量命名不得包含该词。
- 构建产物：根 `.gitignore` 的 `.build/`、`.swiftpm/` 已覆盖嵌套路径，不改忽略规则；若 `git status --porcelain` 仍出现产物，从包落点修正。
- 证据口径：只报 `swift build` / `swift test` 真实输出摘要与用例数、`check-ios-run-core.sh` 的 PASS 计数。

## 最近交付证明

- workItemId: wi_ws_acb54fb5fa309301（2026-11-07，pass，`track-metrics-splits`）
- 交付：`ios/RunCore/Sources/PurePaceRunCore/` 新增 `GeoDistance.swift`（Haversine 纯函数 + 半径常量 `6_371_000.0`）、`RunMetrics.swift`（快照与 `RunMetricsUpdate`）、`RunMetricsEngine.swift`（`ingest(_:) -> RunMetricsUpdate` 单一输入口 + `start`/`pause`/`resume`/`finish` 幂等锚点；分段、滑动窗口当前配速、暂停冻结、时间倒退丢弃）；`Tests/PurePaceRunCoreTests/RunMetricsEngineTests.swift` 新增 10 个 XCTest 方法（首点无度量、半径常量与 691.16 m 口径、1% 距离误差、2 s/km 平均与当前配速、分段 ≤1 采样点边界与累计一致性、重复点零增量、时间倒退丢弃、暂停排除、锚点幂等）；`SendableContractTests.swift` 补入新类型。
- 验证：`code_gates` 全部通过——`lint-ios-run-core` 结构扫描 PASS、`build-ios-run-core` / `test-ios-run-core` 真实 `swift build` / `swift test`（既有 17 例 + 新增 10 例全绿）；未改 `.munk/code-gates.json`（19 门保留）、未改 `scripts/`、未触碰 `ios/PurePace/**` / `project.yml` / `.xcodeproj` / `shared/` / `android/` / CI / `VERSION`。
