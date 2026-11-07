# ios/RunCore SwiftPM 包、领域数据契约与结构门

WorkSet 子项 `run-core-bootstrap`（波 1 第一个子项，本地无 predecessors）。本项只做「包 + 契约 + 门」，不实现任何算法；同波次后续子项在本包之上实现状态机、距离/配速/分段、播报调度、AudioSession 协调、GPX 导出与 checkpoint。

## 范围

1. 新建独立 SwiftPM 包 `ios/RunCore`：
   - `Package.swift`：`// swift-tools-version: 6.0`，`name: "PurePaceRunCore"`，`platforms: [.iOS(.v17), .macOS(.v14)]`，`products: [.library(name: "PurePaceRunCore", targets: ["PurePaceRunCore"])]`，`targets` 仅 `PurePaceRunCore` + `PurePaceRunCoreTests`（testTarget 依赖本模块），零外部依赖。
   - 布局固定：`ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
2. `Sources/PurePaceRunCore/` 只放跑步域公共契约（值类型 / 状态枚举 / 错误类型），全部 `public`、值语义、显式 `Sendable`，仅 `import Foundation`，不含任何算法、循环、平台框架、IO 或持久化。冻结以下公开面：
   - `RunSessionState`：`public enum RunSessionState: String, CaseIterable, Sendable { case ready, running, paused, finished }`；派生只读属性 `isActive`（`running || paused`）、`isTerminal`（`finished`）。本项不含合法/非法迁移逻辑。
   - `RunDistance`：`meters: Double`，`init?(meters:)` 要求 `isFinite && meters >= 0`，否则 `nil`；`Equatable/Hashable/Comparable/Sendable`。
   - `RunPace`：`secondsPerKilometer: Double`，`init?(secondsPerKilometer:)` 要求 `isFinite && > 0`；`init?(distance: RunDistance, duration: TimeInterval)` 在 `distance.meters > 0 && duration.isFinite && duration > 0` 时按 `duration / (meters / 1000)` 派生，否则 `nil`；`Equatable/Hashable/Comparable/Sendable`。
   - `RunSample`：单个采样点，字段 `latitude: Double`、`longitude: Double`、`altitude: Double?`、`timestamp: Date`、`heartRate: Int?`、`cadence: Int?`；`init?` 要求纬 `∈ [-90, 90]`、经 `∈ [-180, 180]`、`altitude` 若存在须 `isFinite`、`timestamp` 非 `distantPast`/`distantFuture`、`heartRate` 若存在须 `> 0`、`cadence` 若存在须 `> 0`，任一不满足即 `nil`；`Equatable/Sendable`。
   - `RunSplit`：公里分段契约，字段 `index: Int`（`>= 1`）、`distance: RunDistance`、`duration: TimeInterval`（`isFinite && > 0`）；`init?` 校验上述约束；派生只读 `pace: RunPace?`（由 `RunPace(distance:duration:)` 派生）；`Equatable/Sendable`。
   - `AnnouncementTrigger`：`public enum AnnouncementTrigger: String, CaseIterable, Sendable { case kilometerCompleted, resumedAfterPause, finished }`。
   - `AnnouncementCommand`：字段 `trigger: AnnouncementTrigger`、`splitIndex: Int`（`>= 1`）、`distance: RunDistance`、`pace: RunPace`、`elapsed: TimeInterval`（`isFinite && >= 0`）；`init?` 校验；`Equatable/Sendable`。本项不产生任何播报命令（生成与去重归后续子项）。
   - `AudioCategory` / `AudioMode` / `AudioCategoryOption`（均为 `String` 原始值枚举，`CaseIterable/Sendable`；option 覆盖 `mixWithOthers` / `duckOthers` / `interruptSpokenAudioAndMixWithOthers` / `allowBluetoothA2DP`）与 `AudioSessionSettings`（字段 `category`、`mode`、`options: Set<AudioCategoryOption>`、`deactivationOptions: Set<AudioCategoryOption>`，成员逐一初始化，`Equatable/Hashable/Sendable`）。这是纯数据镜像契约，**不 import AVFoundation**；默认配置常量与协调器实现归后续子项。
   - `RunCoreError`：`public enum RunCoreError: Error, Equatable, Sendable`，至少含 `invalidDistance(Double)`、`invalidPace(Double)`、`invalidDuration(TimeInterval)`、`invalidSplitIndex(Int)`、`invalidCoordinate(latitude: Double, longitude: Double)`、`invalidSample(String)`、`invalidStateTransition(from: RunSessionState, to: RunSessionState)`、`corruptedCheckpoint(String)`，并提供可读的 `description`（`CustomStringConvertible`）。
   - 不导出上述以外的 `public` 符号；不加可执行 target。
3. `Tests/PurePaceRunCoreTests/`：XCTest（禁用 Swift Testing），覆盖每个类型的合法/非法输入边界、枚举全量 case、错误 `description` 非空，并用编译期泛型辅助（如 `func requireSendable<T: Sendable>(_: T.Type)`）锁定公开契约类型的 `Sendable`。
4. 新增 `scripts/check-ios-run-core.sh`：`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根、幂等、`--help` 退出 0 且含「用法」、未知参数退出 2、无参数在当前树退出 0；支持 `--self-test`。断言项：
   - 包布局、`Package.swift` 声明（tools 6.0 / `PurePaceRunCore` / `.iOS(.v17)` / `.macOS(.v14)` / testTarget）；
   - 零第三方依赖（`Package.swift` 无 `.package(`/`url:`/`path:`，且 `swift package dump-package` 的 `dependencies` 为空数组）；
   - `Sources/` import 白名单仅为 `Foundation`；
   - `Sources/` 不出现平台框架/业务符号：`CoreLocation`、`CLLocationManager`、`AVFoundation`、`AVFAudio`、`AVAudioSession`、`CoreMotion`、`MapKit`、`HealthKit`、`SwiftUI`、`UIKit`、`UserNotifications`、`URLSession`、`CoreData`、`SQLite`、`SwiftData`、`Timer`；
   - `ios/RunCore/**` 不出现夹具令牌 `shared/fixtures` / `sample-run.gpx` / `sample-run.tcx`（该目录被 `check-shared.sh` 的 ios 扫描覆盖）；
   - `ios/RunCore/**` 不出现根 `VERSION` 字面值（排除 `.build` / `.swiftpm`）；
   - 测试为 XCTest 且至少 1 个 `test*` 方法，无 `import Testing`；
   - `ios/RunCore` 内无 XcodeGen 产物；
   - `.munk/code-gates.json` 含 `lint-ios-run-core` / `build-ios-run-core` / `test-ios-run-core` 三门且 command 为预期单一 argv；
   - `scripts/test-ios.sh` 同时含 `xcodebuild test`、`swift test --package-path ios/Core`、`swift test --package-path ios/RunCore`、`blocked:` 四个字面量；
   - `--self-test`：在临时目录复制包并注入违规（如 `import UIKit`、`.package(url:)`、版本字面值），断言同一批断言对这些违规返回失败。
5. `.munk/code-gates.json` 追加三门（command 单一 argv，不含 `&&`/`|`/`;`/重定向）：
   - `lint-ios-run-core` → `bash scripts/check-ios-run-core.sh`
   - `build-ios-run-core` → `swift build --package-path ios/RunCore`
   - `test-ios-run-core` → `swift test --package-path ios/RunCore`
6. `scripts/test-ios.sh` 追加 RunCore 入口：工程可用分支在 `xcodebuild test` 成功后、`exit 0` 前执行 `swift test --package-path ios/RunCore`；降级分支在保留 `blocked:` 说明与 `swift test --package-path ios/Core` 之后（或之前）同样执行 RunCore 的 `swift test`；RunCore 测试非零时脚本非零退出；`ios/RunCore` 缺失时打印 `blocked:` 说明并继续，不伪造成功行。同步更新 `--help` 文本。

## 验收

- ac-run-core-package-builds: 仓库根执行 `swift build --package-path ios/RunCore` 退出码 0，且不解析任何外部依赖（无 `.package(url:)`、无网络包解析）。
- ac-run-core-tests-pass: 仓库根执行 `swift test --package-path ios/RunCore` 退出码 0，实际执行用例数 ≥ 1、失败数 = 0，命令不含 `xcodebuild` / `-destination` / 模拟器 UDID / `-sdk iphonesimulator`。
- ac-run-core-package-shape: `Package.swift` 含 `// swift-tools-version: 6.0`、`name: "PurePaceRunCore"`、`.iOS(.v17)`、`.macOS(.v14)`、`PurePaceRunCoreTests`；存在 `Sources/PurePaceRunCore/` 与 `Tests/PurePaceRunCoreTests/`。
- ac-run-core-zero-deps: `swift package dump-package --package-path ios/RunCore` 的 `dependencies` 为空数组，且 `Package.swift` 无 `.package(` / `url:` / `path:` 依赖声明。
- ac-run-core-foundation-only: `ios/RunCore/Sources/**` 的全部 `import` 仅 `Foundation`；且不出现 `CoreLocation|CLLocationManager|AVFoundation|AVFAudio|AVAudioSession|CoreMotion|MapKit|HealthKit|SwiftUI|UIKit|UserNotifications|URLSession|CoreData|SQLite|SwiftData|Timer` 任一符号。
- ac-run-core-no-fixture-tokens: `ios/RunCore/**` 不出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌（`bash scripts/check-shared.sh` 仍 PASS）。
- ac-run-core-no-version-literal: `ios/RunCore/**`（排除 `.build`/`.swiftpm`）不出现根 `VERSION` 的当前字面值；`scripts/check-ios-run-core.sh` 自身亦不含该字面值（`check-baseline.sh` 的 scripts 扫描仍 PASS）。
- ac-run-core-xctest-only: `Tests/` 至少 1 个 `test*` 方法、`import XCTest` 存在、`import Testing` 不存在；每个公开契约类型均有合法/非法两条以上断言，且公开类型均通过编译期 `Sendable` 约束。
- ac-run-core-domain-contracts: 单测锁定公开面行为——`RunSessionState.allCases` 恰为 `ready/running/paused/finished` 且 `ready.isActive==false`、`running.isActive==true`、`paused.isActive==true`、`finished.isTerminal==true`、`finished.isActive==false`；`RunDistance(meters: -1)`/`.infinity` 为 `nil` 而 `0` 合法；`RunPace(secondsPerKilometer: 0)`/负值/`nan` 为 `nil`，`RunPace(distance:duration:)` 在零距离或零时长时为 `nil`；`RunSample` 对纬度 `91`、经度 `181`、负心率、零步频为 `nil`，对合法点非 `nil` 且字段一致；`RunSplit(index: 0)`/非正时长为 `nil`，合法值 `pace` 非 `nil`；`AnnouncementCommand(splitIndex: 0)`/负 `elapsed` 为 `nil`；`AudioSessionSettings` 的 `options`/`deactivationOptions` 与入参一致且相等性判断正确；`RunCoreError` 每个 case 的 `description` 非空且互不相同。
- ac-run-core-gate-script: `bash scripts/check-ios-run-core.sh` 在当前树退出 0 且逐条打印 `[PASS]`；`--help` 退出 0 且含「用法」；未知参数退出 2；`bash -n scripts/check-ios-run-core.sh` 通过；文件可执行（`chmod +x`）。
- ac-run-core-gate-self-test: `bash scripts/check-ios-run-core.sh --self-test` 退出 0，并在注入 `import UIKit` / `.package(url:)` / 版本字面值等违规后真实报出失败（反例自检，不靠跳过或 `true` 冒充）。
- ac-code-gates-ios-run-core: `.munk/code-gates.json` 原有 16 个 `id` 全部保留且 command 不变，新增 `lint-ios-run-core`/`build-ios-run-core`/`test-ios-run-core` 三门，command 分别为 `bash scripts/check-ios-run-core.sh`、`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore`，无 shell 分隔符/重定向；`bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-test-ios-runcore-entry: `scripts/test-ios.sh` 直接包含字面量 `swift test --package-path ios/RunCore`，同时保留 `xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:` 与 iPhone 16 destination（`bash scripts/check-ios-scripts.sh` 仍 PASS）；`--help` 说明新增 RunCore 分支；`bash -n scripts/test-ios.sh` 通过；RunCore 测试失败时脚本退出码非 0。
- ac-build-artifacts-ignored: `swift build`/`swift test` 之后 `git status --porcelain` 不出现 `ios/RunCore/.build/`、`ios/RunCore/.swiftpm/`（复用根 `.gitignore` 的 `.build/`、`.swiftpm/`，不新增或放宽忽略规则）。
- ac-no-platform-or-ui-change: 未新增/修改 `ios/project.yml`、`ios/PurePace.xcodeproj`、`ios/PurePace/**`、`shared/**`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`、`scripts/version.sh` 与既有 16 门 command。

## 非目标

- 不实现会话状态机迁移、距离/配速/分段计算引擎、播报调度与去重、AudioSession 协调器与读回、GPX 1.1 导出、checkpoint 持久化与恢复——均由同波次后续子项在 `PurePaceRunCore` 之上实现；本项只冻结类型与最小 init 校验，不预埋算法入口。
- 不新增可执行 target（`PurePaceGpxTool` 归后续子项）；不建 App target、不接 CoreLocation/AVFoundation、不建 UI 页面，不改 `ios/project.yml` 与 `.xcodeproj`（XcodeGen 接入本地包留给后续子项，届时需放宽 `check-ios-shell.sh` 仅对本地包）。
- 不改动 `scripts/check-ios-core.sh`、`scripts/check-ios-scripts.sh`、`scripts/check-ios-shell.sh`、`scripts/check-shared.sh`、`scripts/check-baseline.sh` 的既有断言语义；`scripts/test-ios.sh` 只做追加，不重排/不删除既有分支。
- 不写 `tech.md`、不改 `AGENTS.md`/`README.md`/`VERSION`、不碰 `shared/`、`android/`、`.github/workflows/*`、Host 托管文件（`goal.md`/`handoff.md`/`now.md`/`product.json`）。
- 不做真机、签名、推送、CI run；不写「CI 通过」「真机已验证」类结论。

## 实现约束

- **前置 skill 事实**：仓库已有 `AGENTS.md` 且已路由官方 skill（`.agents/skills/swiftui-pro`、`.agents/skills/android-cli`），App 工程亦已存在（阶段 1 交付）。故本项不需要 `repo-bootstrap` 重新装 skill，**不创建任何新工程/项目骨架**；本项是纯 SwiftPM 逻辑包，UI 规范（swiftui-pro）不适用，只需守住 Swift 6 严格并发与值类型约定。
- 环境：Swift 6.2 / Xcode 26.3 / macOS arm64。`swift test` 走 macOS destination，因此 `platforms` 必须同时含 `.macOS(.v14)` 与 `.iOS(.v17)`，否则 host 侧无法编译。
- Swift 6 语言模式（严格并发）：公开契约类型全为 `struct`/`enum` 值类型并显式 `Sendable`；本项不引入 `actor`、`class`、全局可变状态、`@unchecked`。
- 包名与模块名统一 `PurePaceRunCore`（目录名 `RunCore`），阶段 3 App/Harness 直接 `import PurePaceRunCore`；与既有 `ios/Core`（`PurePaceCore`，只放基础设施）保持边界分离，不做合并。
- 夹具红线：本项与后续 RunCore 代码都不得出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌；夹具路径只能由 `scripts/` 以 CLI 参数传入（`check-shared.sh` 会扫描整个 `ios/` 树）。
- 门禁命令必须为可直接执行的单一 argv；需要结构断言时一律由 `scripts/` 下 bash 脚本承载。新增脚本沿用 `check-ios-core.sh` 的 `pass`/`fail` 计数与「N 项断言，M 项失败」输出风格，便于人工核对。
- `--self-test` 实现建议：把 `ios/RunCore` 复制到 `${TMPDIR:-/tmp}` 临时目录，在副本内注入违规，复用同一批断言函数（断言函数以包路径为参数），结束清理临时目录；不得在仓库内留下临时文件或在 self-test 中写仓库。
- 版本禁写死：`ios/RunCore/**` 与 `scripts/check-ios-run-core.sh` 均不得出现根 `VERSION` 当前字面值（`check-baseline.sh` 会扫描 `scripts/*.sh`）；测试样例使用与仓库版本无关的合成数值。
- `scripts/test-ios.sh` 追加时注意 `check-ios-scripts.sh` 的既有字面量断言：`xcodebuild test`、`-scheme`、`ios/PurePace.xcodeproj`、`swift test --package-path ios/Core`、`blocked:`、iPhone 16 destination 必须原样保留；不得出现 `echo ... TEST SUCCEEDED` 之类伪造成功行。
- 构建产物：根 `.gitignore` 的 `.build/`、`.swiftpm/` 已覆盖嵌套路径，本项不修改忽略规则；若 `git status --porcelain` 仍出现产物，从包的落点修正而不是放宽规则。
- 证据口径：本项只报 `swift build`/`swift test` 真实输出摘要与用例数、`check-ios-run-core.sh` 的 PASS 计数；不得写「真机已验证」「CI 通过」。阶段 2 的两项真机项（后台锁屏连续定位、音乐不打断与 duck 恢复）在本项不涉及，仍为 `pending: 待人现场`。
