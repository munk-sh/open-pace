# Domain: ios-runcore

跑步域纯逻辑包：独立 SwiftPM package `ios/RunCore`（包名/模块名 `PurePaceRunCore`，目录名 `RunCore`）。冻结值类型契约（状态枚举、距离/配速、采样点、分段、播报命令、音频配置镜像、错误类型），并在同包内承载会话状态机与真实文件 checkpoint 存储/恢复语义；仍属纯逻辑 + `Foundation` 文件 IO，不含距离/配速计算引擎与平台适配；与 `ios-core`（`PurePaceCore`，基础设施）边界分离，不做合并。

## 范围

- `ios/RunCore/Package.swift`：`// swift-tools-version: 6.0`，`name: "PurePaceRunCore"`，platforms 同时声明 `.iOS(.v17)` 与 `.macOS(.v14)`（macOS host 上可直接 `swift build` / `swift test`），零外部依赖，targets 仅 `PurePaceRunCore` + `PurePaceRunCoreTests`。
- 布局固定 `ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
- `Sources/PurePaceRunCore/` 全部 `public`、值语义、显式 `Sendable`，仅 `import Foundation`，无平台框架；契约类型不含计算算法，IO 只出现在 `RunCheckpointStore`：
  - `RunSessionState`（`ready/running/paused/finished`，`String` 原始值）及派生只读 `isActive`、`isTerminal`；枚举本身不含迁移逻辑。
  - `RunDistance`（`meters`）、`RunPace`（`secondsPerKilometer`，并可由距离+时长派生）。
  - `RunSample`（经纬度/海拔/时间戳/心率/步频）、`RunSplit`（`index` + 距离 + 时长，派生 `pace`）。
  - `AnnouncementTrigger`、`AnnouncementCommand`（触发源 / 分段序号 / 距离 / 配速 / 已用时长）。
  - `AudioCategory` / `AudioMode` / `AudioCategoryOption` 与 `AudioSessionSettings`：纯数据镜像，**不 import AVFoundation**。
  - `RunCoreError`（`Error, Equatable, Sendable`，`CustomStringConvertible`）。
  - `RunSessionMachine`（`struct`，持有 `state: RunSessionState`）：`init(state:)`、`canTransition(to:)`、`mutating transition(to:) throws`、语义化 `start()/pause()/resume()/finish()`，以及 `init(restoring:)`；非法迁移抛 `RunCoreError.invalidStateTransition(from:to:)` 且状态不变。
  - `RunCheckpoint`（`struct`，手写 `Codable`）：`formatVersion`（唯一合法 1）/`state`/`completedDistance`/`elapsed`/`splits`/`recordedAt`，`init?` 校验有限非负 `elapsed`、`splits` 索引从 1 连续、时间非 `distantPast`/`distantFuture`、`ready` 时零距离零分段。
  - `RunCheckpointStore`（`struct`，持有 `fileURL: URL`）：JSONL 追加写盘（每行 UTF-8 JSON + `\n`）、`loadAll()`、`loadLatest()`、`reset()`；缺失文件视为空，尾行损坏静默丢弃，非尾行损坏抛 `corruptedCheckpoint`。
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
- ac-runcore-layer-only: 新增代码只落 `ios/RunCore/Sources/PurePaceRunCore/` 与 `ios/RunCore/Tests/PurePaceRunCoreTests/`；`Sources/**` 的 `import` 仍仅 `Foundation`，不出现平台符号、`shared/fixtures`/夹具令牌与根 `VERSION` 字面值。
- ac-no-frozen-contract-break: `RunSessionState`/`RunDistance`/`RunPace`/`RunSample`/`RunSplit`/`Announcement*`/`AudioSessionSettings`/`RunCoreError` 的既有公开字段、初始化签名与既有 17 个用例语义不变；不为既有类型新增 `Codable`（`RunCheckpoint` 自行编码原始字段）。
- ac-swift-test-green: 仓库根 `swift test --package-path ios/RunCore` 退出码 0、失败数 0 且新用例真实执行（用例数 > 17）；`bash scripts/check-ios-run-core.sh`、`bash scripts/check-baseline.sh` 全 `[PASS]`；`.munk/code-gates.json` 既有门（含 `lint-ios-run-core`/`build-ios-run-core`/`test-ios-run-core`）id 与 command 不变。
- ac-no-platform-or-ui-change: 未修改 `ios/project.yml`、`ios/PurePace.xcodeproj`、`ios/PurePace/**`、`scripts/**`、`shared/**`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`。

## 非目标

- 不实现距离/配速/分段计算引擎、播报调度与去重、AudioSession 协调器与读回、GPX 1.1 导出、App target 音频适配器、CoreLocation 接入、模拟器 Harness 与 `verify-ios-sim-runtime.sh`；不跑 `xcrun simctl` / `xcodebuild`。checkpoint 只存盘与会话恢复，不做距离重算、不产生新分段、不做跨进程 terminate→relaunch 编排（波 2 承担）。
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
- 构建产物：根 `.gitignore` 的 `.build/`、`.swiftpm/` 已覆盖嵌套路径，不改忽略规则；若 `git status --porcelain` 仍出现产物，从包落点修正。
- 证据口径：只报 `swift build` / `swift test` 真实输出摘要与用例数、`check-ios-run-core.sh` 的 PASS 计数。
- 状态机红线：`idle` 等同既有 `ready`，不新增/重命名枚举 case（`allCases` 顺序与 rawValue 已锁定）；合法迁移矩阵恰为 5 条，其余一律 `invalidStateTransition` 且状态不变；语义化入口复用同一校验，不另开旁路。
- checkpoint 红线：文件即真源，`RunCheckpointStore` 是唯一落盘点，外面不得再包内存缓存层；`FileHandle` 追加 + 每行 `\n`，只用 `Foundation`（`FileManager`/`Data`/`FileHandle`/`JSONEncoder`/`JSONDecoder`/`URL`），不引入 `OutputStream`/SQLite/`UserDefaults`；尾行丢弃、非尾行抛错、IO 不可读不得伪装成空结果。
- 恢复语义红线：`.running`/`.paused` 一律恢复为 `.paused`，禁止进程重启后静默冒充 running；`.ready`/`.finished` 原样恢复；恢复不改写 checkpoint 数据。
- 测试隔离：临时目录用 `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`，每用例独立目录并 `defer` 清理；仍用 XCTest（禁 `import Testing`），测试数值全部合成，不出现夹具令牌与根 `VERSION` 字面值。

## 最近交付证明

- workItemId: wi_ws_93a3efc9df0e98eb（2026-11-07，pass）
- 交付：同包新增 `RunSessionMachine`（5 条合法迁移矩阵、语义化入口、`init(restoring:)` 恢复语义）、`RunCheckpoint`（手写 `Codable` + `init?` 契约校验）与 `RunCheckpointStore`（JSONL 真实文件追加、`loadAll`/`loadLatest`/`reset`、尾行丢弃 / 非尾行抛 `corruptedCheckpoint`）；测试新增 `SessionMachineTests`（8）与 `CheckpointStoreTests`（9），RunCore 用例总数由 17 升至 34。
- 验证：`code_gates` 19 门全绿（真实 `swift build` / `swift test`、`check-ios-run-core.sh`、`check-baseline.sh`）；未改 `Package.swift`、`project.yml`、`.xcodeproj`、`scripts/`、`shared/`、`android/`、CI 与 `VERSION`；未新增 error case，既有契约语义不变。
