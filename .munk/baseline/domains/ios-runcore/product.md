# Domain: ios-runcore

跑步域纯逻辑契约包：独立 SwiftPM package `ios/RunCore`（包名/模块名 `PurePaceRunCore`，目录名 `RunCore`）。只冻结值类型契约（状态枚举、距离/配速、采样点、分段、播报命令、音频配置镜像、错误类型），不承载任何算法实现；与 `ios-core`（`PurePaceCore`，基础设施）边界分离，不做合并。

## 范围

- `ios/RunCore/Package.swift`：`// swift-tools-version: 6.0`，`name: "PurePaceRunCore"`，platforms 同时声明 `.iOS(.v17)` 与 `.macOS(.v14)`（macOS host 上可直接 `swift build` / `swift test`），零外部依赖，targets 仅 `PurePaceRunCore` + `PurePaceRunCoreTests`。
- 布局固定 `ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
- `Sources/PurePaceRunCore/` 只放公共契约，全部 `public`、值语义、显式 `Sendable`，仅 `import Foundation`，无算法、循环、平台框架、IO 或持久化：
  - `RunSessionState`（`ready/running/paused/finished`，`String` 原始值）及派生只读 `isActive`、`isTerminal`；不含迁移逻辑。
  - `RunDistance`（`meters`）、`RunPace`（`secondsPerKilometer`，并可由距离+时长派生）。
  - `RunSample`（经纬度/海拔/时间戳/心率/步频）、`RunSplit`（`index` + 距离 + 时长，派生 `pace`）。
  - `AnnouncementTrigger`、`AnnouncementCommand`（触发源 / 分段序号 / 距离 / 配速 / 已用时长）。
  - `AudioCategory` / `AudioMode` / `AudioCategoryOption` 与 `AudioSessionSettings`：纯数据镜像，**不 import AVFoundation**。
  - `RunCoreError`（`Error, Equatable, Sendable`，`CustomStringConvertible`）。
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

## 非目标

- 不实现会话状态机迁移、距离/配速/分段计算引擎、播报调度与去重、AudioSession 协调器与读回、GPX 1.1 导出、checkpoint 持久化与恢复；本域只冻结类型与最小 `init` 校验，不预埋算法入口。
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

## 最近交付证明

- workItemId: wi_ws_4149e2b54d5817d5（2026-11-07，pass）
- 交付：新建 `ios/RunCore` SwiftPM 包（tools 6.0 / `PurePaceRunCore` / iOS 17 + macOS 14 / 零依赖），8 个契约源文件（`RunSessionState`、`RunDistance`、`RunPace`、`RunSample`、`RunSplit`、`Announcement(Trigger|Command)`、`AudioSessionSettings`、`RunCoreError`）；`PurePaceRunCoreTests` 6 个 XCTest 文件共 17 个 `test*` 方法覆盖合法/非法边界、枚举全量 case、错误 `description` 与编译期 `Sendable` 锁定；新增 `scripts/check-ios-run-core.sh`（含 `--self-test` 反例注入）；`.munk/code-gates.json` 新增 `lint-ios-run-core` / `build-ios-run-core` / `test-ios-run-core` 三门，`scripts/test-ios.sh` 追加 RunCore 分支且保留既有字面量。
- 验证：`code_gates` 全部通过（真实 `swift build` / `swift test`、`check-ios-run-core.sh` 与 `scripts/check-baseline.sh`）；未使用 xcodebuild / 模拟器；未新增 `project.yml` / `.xcodeproj`，未触碰 `shared/` / `android/` / CI / `VERSION`。
