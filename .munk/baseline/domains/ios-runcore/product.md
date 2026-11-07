# Domain: ios-runcore

跑步域纯逻辑包：独立 SwiftPM package `ios/RunCore`（包名/模块名 `PurePaceRunCore`，目录名 `RunCore`）。冻结值类型契约（状态枚举、距离/配速、采样点、分段、播报命令、音频配置镜像、错误类型），并提供不依赖平台的 GPX 1.1 编解码与一个无 UI 的校验 CLI；不含状态机/计算引擎等业务算法，不接平台框架。与 `ios-core`（`PurePaceCore`，基础设施）边界分离，不做合并。

## 范围

- `ios/RunCore/Package.swift`：`// swift-tools-version: 6.0`，`name: "PurePaceRunCore"`，platforms 同时声明 `.iOS(.v17)` 与 `.macOS(.v14)`（macOS host 上可直接 `swift build` / `swift test`），零外部依赖；targets 为 `PurePaceRunCore` + `PurePaceRunCoreTests`，另加唯一可执行 target `PurePaceGpxTool`（product 同名，仅依赖 `PurePaceRunCore`）。
- 布局固定 `ios/RunCore/{Package.swift, Sources/PurePaceRunCore/, Sources/PurePaceGpxTool/, Tests/PurePaceRunCoreTests/}`；不放 `project.yml` / `.xcodeproj` / `project.pbxproj`。
- `Sources/PurePaceRunCore/` 的契约面：`RunSessionState`（`ready/running/paused/finished` 与派生 `isActive`/`isTerminal`，不含迁移逻辑）、`RunDistance`、`RunPace`、`RunSample`、`RunSplit`、`AnnouncementTrigger`/`AnnouncementCommand`、`AudioCategory`/`AudioMode`/`AudioCategoryOption`/`AudioSessionSettings`（纯数据镜像，不 import AVFoundation）、`RunCoreError` — 全 `public`、值语义、显式 `Sendable`、仅 `import Foundation`。
- `Sources/PurePaceRunCore/` 的 GPX 编解码面（仍仅 Foundation）：`GPXTrack`（`name`/`description?`/`createdAt`/`activityType`/`points: [RunSample]`，**复用 `RunSample`** 不另建点类型；空名/空点/相邻点时间戳递减为 `nil`）、`GPXCodecError`（`invalidDocument`/`missingTrack`/`unsupportedNamespace`/`invalidPoint(index:reason:)`/`ioFailure`，`description` 非空且互不相同，**不改** `RunCoreError` case 集合）、`GPXCodec`（`encode`/`decode`/`write`/`read`，`write`/`read` 走真实文件 IO）。
- GPX 1.1 输出契约：默认命名空间 `http://www.topografix.com/GPX/1/1` 与 `gpxtpx` 扩展命名空间 `.../TrackPointExtension/v1`；`metadata/name`、可选 `metadata/desc`、`metadata/time`（首点时间）；`trk/name`、`trk/type`、`trk/trkseg/trkpt[@lat,@lon]`，子元素顺序固定 `ele?/time/extensions?`；`hr`/`cad` 仅在存在时写入 `gpxtpx:TrackPointExtension`；UTC 秒级 ISO 8601 以 `Z` 结尾、坐标 ≥ 6 位小数、同一输入输出确定。
- GPX 1.1 回读契约：`XMLParser` 开启 `shouldProcessNamespaces`，精确匹配上述两个命名空间；命名空间不符、缺 `trk/trkseg`、`trkpt` 缺 `lat/lon` 或越界、`time` 不可解析一律抛 `GPXCodecError`，不返回部分结果。
- `Sources/PurePaceGpxTool/main.swift`：无 UI 的校验用 CLI，`--input <path>` 读、`--output <path>` 写；参数缺失或未知退 2，解析/IO 失败退 3 并 stderr 打 `error:`，成功退 0，`--help` 退 0；源码不含任何夹具路径字面量。
- `scripts/check-gpx-export.sh`：结构沿用 `check-ios-core.sh`（`set -euo pipefail`、`BASH_SOURCE` 推根、pass/fail 计数 +「N 项断言，M 项失败」、`--help`、未知参数退 2）；`mktemp -d` + `trap` 真实跑工具，`xmllint --noout` + `python3` 逐字段比对 `shared/fixtures/sample-run.gpx`（`trkpt` 恰 4 个；坐标/海拔 `abs(delta) <= 1e-6`；时间按同一瞬间；`hr`/`cad` 整数相等）。
- 门禁：`.munk/code-gates.json` 保留既有 19 个 `id`/`command`，新增 `check-gpx-export`（`bash scripts/check-gpx-export.sh`，单一 argv）；`scripts/check-ios-run-core.sh` 恰好放行一个 `PurePaceGpxTool` executable target（帮助文本同步、`check_gates` 期望表加入 `check-gpx-export`、self-test 增加「第二个/改名 executable target 必须失败」反例）；`scripts/test-ios.sh` 保留既有 RunCore 入口。

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

## 非目标

- 不实现会话状态机迁移、距离/配速/分段计算引擎、播报调度与去重、AudioSession 协调器与读回、GPX 导入 UI、checkpoint 持久化与恢复；GPX 编解码本身已交付，但只做编解码与 CLI 校验，不预埋算法或采集入口。
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
- 构建产物：根 `.gitignore` 的 `.build/`、`.swiftpm/` 已覆盖嵌套路径，不改忽略规则；若 `git status --porcelain` 仍出现产物，从包落点修正。
- `check_foundation_only` 与 `check_no_platform_symbols` 扫描整个 `ios/RunCore/Sources`（含 `PurePaceGpxTool`），故工具同样只能 `import Foundation`；`XMLParser`/`ISO8601DateFormatter`/`Data` 均在 Foundation 内可用。
- `check_no_fixture_tokens` 扫描整个 `ios/RunCore`（含 `Tests/`），单测只用合成坐标；夹具路径仅由 `scripts/check-gpx-export.sh` 以 CLI 参数传入。
- `check_no_version_literal` 扫描 `ios/RunCore` 与 `scripts/*.sh`：不得出现根 `VERSION` 当前字面值；`description`/creator 文案与测试数值不得写死版本号。
- `scripts/check-ios-run-core.sh` 只做三处最小改动（放行 `PurePaceGpxTool`、期望门禁表加 `check-gpx-export`、self-test 加 executable 反例），不得放宽零依赖/仅 Foundation/无平台符号/无夹具令牌/无 XcodeGen 产物等既有断言；`copy_package` 须让 self-test 副本也覆盖 `Sources/PurePaceGpxTool`。
- 临时文件：单测用 `NSTemporaryDirectory()` 子目录并 `defer`/`tearDown` 清理；脚本 `mktemp -d` + `trap 'rm -rf' EXIT`；仓库内不得残留 `.gpx` 或其它产物。
- 证据口径：只报 `swift test --package-path ios/RunCore`、`bash scripts/check-gpx-export.sh`、`bash scripts/check-ios-run-core.sh [--self-test]` 的真实输出与 PASS 计数；不写「真机已验证」「CI 通过」，真机项仍为 `pending: 待人现场`。

## 最近交付证明

- workItemId: wi_ws_08dba7faf5f52d9f（2026-11-07，pass）
- 交付：新增 `GPXTrack`/`GPXCodecError`/`GPXCodec`（GPX 1.1 encode/decode + 真实文件 write/read，命名空间严格校验、可选 `ele`/`hr`/`cad`、UTC 秒级时间）；`Package.swift` 增唯一可执行 target `PurePaceGpxTool`（`--input/--output/--help`，退出码 0/2/3）；新增 `scripts/check-gpx-export.sh`（`mktemp` + `trap`、真实跑工具、`xmllint --noout` + `python3` 与 `shared/fixtures/sample-run.gpx` 逐字段比对、依赖缺失一律 fail）；`.munk/code-gates.json` 新增 `check-gpx-export`（既有 19 门原样保留）；`scripts/check-ios-run-core.sh` 最小放宽至恰好放行该 executable 并加 self-test 反例。
- 验证：`code_gates` 全部通过（真实 `swift test --package-path ios/RunCore`、`bash scripts/check-gpx-export.sh`、`bash scripts/check-ios-run-core.sh --self-test`）；未新增 UI/导出入口，未改 `ios/PurePace/**`、`ios/project.yml`、`.xcodeproj`、`shared/`、`android/`、CI、`VERSION`；真机项仍 `pending: 待人现场`。
