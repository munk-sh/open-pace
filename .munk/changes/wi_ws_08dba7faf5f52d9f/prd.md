# GPX 1.1 导出、回读与 shared 夹具逐字段对齐

WorkSet 子项 `gpx-export-contract`（波 1，唯一 predecessor：`run-core-bootstrap`，已 delivered）。本项在既有 `ios/RunCore`（`PurePaceRunCore`）之上补齐 GPX 1.1 的**写入 + 回读**能力，并用「真实临时文件 + 外部 `xmllint` 解析」证明导出结果与 `shared/fixtures/sample-run.gpx` 逐字段一致。**不新增任何 UI 导出入口。**

## 范围

1. **RunCore GPX 编解码（纯逻辑，`import Foundation` 白名单内）**
   - 新增 `ios/RunCore/Sources/PurePaceRunCore/GPXTrack.swift`：`public struct GPXTrack: Equatable, Sendable`，字段 `name: String`、`description: String?`、`createdAt: Date`、`activityType: String`、`points: [RunSample]`；`init?` 在 `name` 为空、`points` 为空、或相邻点 `timestamp` 递减时返回 `nil`。**复用既有 `RunSample`**（已含 latitude/longitude/altitude/timestamp/heartRate/cadence），不新建并行点类型。
   - 新增 `ios/RunCore/Sources/PurePaceRunCore/GPXCodecError.swift`：`public enum GPXCodecError: Error, Equatable, Sendable, CustomStringConvertible`，至少 `invalidDocument(String)`、`missingTrack(String)`、`unsupportedNamespace(String)`、`invalidPoint(index: Int, reason: String)`、`ioFailure(String)`，`description` 非空且互不相同。**不改动** 既有 `RunCoreError` 的 case 集合（避免冲击 `RunCoreErrorTests`）。
   - 新增 `ios/RunCore/Sources/PurePaceRunCore/GPXCodec.swift`：`public enum GPXCodec`，公开面为
     `static func encode(_ track: GPXTrack) throws -> String`、
     `static func decode(_ data: Data) throws -> GPXTrack`、
     `static func write(_ track: GPXTrack, to url: URL) throws`、
     `static func read(from url: URL) throws -> GPXTrack`。
     `write`/`read` 必须走真实文件 IO（`Data.write(to:options:)` / `Data(contentsOf:)`），不得内存态伪造。
   - 输出契约（GPX 1.1）：
     - `<?xml version="1.0" encoding="UTF-8"?>` + `<gpx version="1.1" creator="…" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">`；
     - `metadata/name`、可选 `metadata/desc`、`metadata/time`（首点时间）；
     - `trk/name`、`trk/type`、`trk/trkseg/trkpt[@lat,@lon]`，子元素顺序固定 `ele?/time/extensions?`；
     - `hr`/`cad` 仅在该点存在时写入 `<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>/<gpxtpx:cad>`；`altitude` 为 `nil` 时**不写** `<ele>`；
     - 时间统一 UTC ISO 8601、秒级、以 `Z` 结尾，不受系统时区/locale 影响；坐标至少 6 位小数。
   - 回读契约：`XMLParser` 必须 `shouldProcessNamespaces = true`，精确匹配 GPX 1.1 默认命名空间与 `gpxtpx` 扩展命名空间；命名空间不符、无 `trk/trkseg`、`trkpt` 缺 `lat/lon` 或越界、`time` 不可解析 → 抛 `GPXCodecError`，不得返回部分结果。
2. **无 UI 校验可执行目标** `PurePaceGpxTool`
   - `ios/RunCore/Package.swift` 增加 `products` 中的 `.executable(name: "PurePaceGpxTool", targets: ["PurePaceGpxTool"])` 与 `.executableTarget(name: "PurePaceGpxTool", dependencies: ["PurePaceRunCore"])`。
   - 实现落点 `ios/RunCore/Sources/PurePaceGpxTool/main.swift`：读取 `--input <path>` 的 GPX（`GPXCodec.read`），写 `--output <path>`（`GPXCodec.write`）。参数缺失/未知参数退出 2，解析或 IO 失败退出 3 并向 stderr 打 `error:`，成功退出 0。支持 `--help`（退出 0，含「用法」）。**源码内不含任何夹具路径字面量**，路径只经 CLI 参数传入。
3. **外部校验脚本** `scripts/check-gpx-export.sh`
   - 结构沿用 `scripts/check-ios-core.sh`：`#!/usr/bin/env bash`、`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根、`pass`/`fail` 计数并输出「N 项断言，M 项失败」、`--help` 退出 0、未知参数退出 2。
   - 流程：`mktemp -d` 建临时目录 + `trap` 清理 → `swift build --package-path ios/RunCore --product PurePaceGpxTool` → 以 `shared/fixtures/sample-run.gpx` 为 `--input`、临时目录内 `.gpx` 为 `--output` 真实运行工具 → 输出文件存在且非空 → `xmllint --noout` 通过 → `python3` 逐字段比对。
   - 比对口径：根元素为 GPX 1.1 `gpx`、`@version="1.1"`、`@creator` 非空、默认命名空间与 `gpxtpx` 命名空间精确匹配；`trkpt` 恰好 4 个；逐点 `lat`/`lon`/`ele` 按数值比较（`abs(delta) <= 1e-6`）、`time` 按同一时间瞬间比较、`hr`/`cad` 按整数相等比较。
   - 任何 `xmllint`/`python3`/`swift` 缺失、工具非零退出、字段不一致都必须 `fail` 并非零退出，**禁止 skip 或降级为提示**。
4. **门禁接线**
   - `.munk/code-gates.json` 追加 `check-gpx-export` → `bash scripts/check-gpx-export.sh`（单一 argv，无 `&&`/`|`/`;`/重定向）；现有 19 个 `id` 与 `command` 一律保持原样、不删不减。
   - `scripts/check-ios-run-core.sh` 做**最小放宽 + 收紧**：允许且仅允许一个 `.executableTarget(name: "PurePaceGpxTool"`，其它任何 executable target 仍失败（帮助文本同步）；`check_gates` 的期望表中加入 `check-gpx-export`；`--self-test` 反例增加「注入第二个/改名 executable target 必须失败」。

## 验收

- ac-gpx-roundtrip-real-file: `ios/RunCore/Tests` 中存在 GPX round-trip 用例，用 `NSTemporaryDirectory()` 真实写入 `.gpx` 文件再由 `GPXCodec.read` 读回，断言点数量与每点 `latitude/longitude/altitude/timestamp/heartRate/cadence` 与输入完全相等，且用例结束后临时文件被删除（仓库内无残留）。`swift test --package-path ios/RunCore` 退出 0、失败数 0。
- ac-gpx-namespaces-and-extensions: `GPXCodec.encode` 结果含 `version="1.1"`、`xmlns="http://www.topografix.com/GPX/1/1"`、`xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`，且 `hr`/`cad` 位于 `gpxtpx:TrackPointExtension` 之下（单测断言字符串/解析结构，二者均可）。
- ac-gpx-optional-fields: 输入点 `altitude == nil` 时输出该点无 `<ele>`；`heartRate == nil` 且 `cadence == nil` 时该点无 `gpxtpx:hr`/`gpxtpx:cad`；该输出仍能被 `GPXCodec.decode` 成功读回且字段与输入一致。
- ac-gpx-decode-rejects-invalid: `GPXCodec.decode` 对「无 `trkseg/trkpt`」「默认命名空间非 GPX 1.1」「`lat="91"`」「`time` 非 ISO 8601」四类输入各抛对应 `GPXCodecError`（单测断言 case，不 crash）；`read(from:)` 对不存在路径抛 `ioFailure`。
- ac-gpx-tool-cli: `swift build --package-path ios/RunCore --product PurePaceGpxTool` 退出 0；工具 `--help` 退出 0 且含「用法」；`--definitely-invalid` 退出 2；缺 `--output` 退出 2；`--input /nonexistent/x.gpx --output <tmp>` 退出 3 且 stderr 含 `error:`。
- ac-check-gpx-export-pass: `bash scripts/check-gpx-export.sh` 退出 0，逐条打印 `[PASS]`；其中 `xmllint --noout` 对工具输出返回 0，且四个 `trkpt` 的 `lat/lon/ele/time/hr/cad` 与 `shared/fixtures/sample-run.gpx` 逐点比对全部一致（浮点 `<= 1e-6`，时间按瞬间，`hr`/`cad` 整数）。
- ac-check-gpx-export-no-skip: `scripts/check-gpx-export.sh` 对 `xmllint`、`python3`、`swift` 缺失各走 `fail` 分支并以非零退出（脚本内存在对应 `command -v` 判定与失败输出，无 `skip`/`exit 0` 兜底）。
- ac-check-gpx-export-hygiene: 脚本 shebang 为 `#!/usr/bin/env bash`、含 `set -euo pipefail` 与 `BASH_SOURCE`；`bash -n scripts/check-gpx-export.sh` 通过；`--help` 退出 0 且输出含「用法」；未知参数退出 2；文件可执行。
- ac-gate-check-gpx-export: `.munk/code-gates.json` 保留原有 19 个 `id` 及其 `command`，新增 `check-gpx-export` 且 command 为 `bash scripts/check-gpx-export.sh`，新增/既有 command 均不含 `&&`/`||`/`|`/`;`/`>`/`<`；`bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-run-core-gate-allows-tool: `bash scripts/check-ios-run-core.sh` 退出 0（`Package.swift` 中的 `PurePaceGpxTool` executable target 不再被判违规）；`bash scripts/check-ios-run-core.sh --self-test` 退出 0；self-test 中存在「注入非 `PurePaceGpxTool` 的 executable target → 失败」的反例并被真实执行。
- ac-no-fixture-token-in-ios-runcore: `ios/RunCore/**`（排除 `.build`/`.swiftpm`）不含 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 字面量；`bash scripts/check-shared.sh` 仍 PASS（ios 零夹具引用）。
- ac-no-ui-export-entry: `ios/` 下不出现 `ShareLink`、`fileExporter`、`UIDocumentPicker`、`UIActivityViewController`、`UIActivityItemProvider` 任一符号；未修改 `ios/PurePace/**`、`ios/project.yml`、`ios/PurePace.xcodeproj`（`git status --porcelain` 对这些路径为空）。
- ac-fixture-and-shared-untouched: `shared/` 零改动（`git status --porcelain shared/` 为空），夹具与 `fixtures/README.md` 的期望值未调整。
- ac-runcore-tests-green: `swift test --package-path ios/RunCore` 退出 0，用例数不少于新增前（17）且新增 GPX 用例实际被执行（输出含新增用例名，非 0 tests）。
- ac-no-scope-drift: 未修改 `scripts/test-ios.sh`、`scripts/build-ios.sh`、`scripts/version.sh`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`；未新增任何 UI 页面。
- ac-build-artifacts-clean: 跑完 `build-ios-run-core` / `check-gpx-export` 后 `git status --porcelain` 不出现 `ios/RunCore/.build/`、`ios/RunCore/.swiftpm/`（不新增或放宽 `.gitignore`）。

## 非目标

- 不新增导出页、导出按钮、`ShareLink`、`fileExporter`、`UIDocumentPicker`、分享/上传入口；不把 `PurePaceRunCore` 接进 App target，不改 `ios/project.yml` 与 `.xcodeproj`（本地包接入 XcodeGen 属波 2 子项）。
- 不实现 GPX 导入 UI、CoreLocation 采集接线、历史列表、地图或任何阶段 3 页面。
- 不修改 `shared/`（夹具、README、`schema.sql`）、不新增夹具、不把夹具当真实坐标流。
- 不改既有 19 个门禁的 `id`/`command`，不删除门禁；不改 `scripts/test-ios.sh`、`scripts/build-ios.sh` 的既有分支与入口语义。
- 不做 Android 业务改动、不改 `.github/workflows/**`、不推送、不写「CI 通过」「真机已验证」类结论；真机项仍为 `pending: 待人现场`。
- 不在 `ios/RunCore` 引入第三方依赖、平台框架（CoreLocation/AVFoundation/SwiftUI/UIKit 等）或 `Timer`。

## 实现约束

- **前置 skill 事实**：仓库已有 `AGENTS.md` 并已路由官方 skill（`.agents/skills/swiftui-pro`、`.agents/skills/android-cli`）；App 工程、`ios/Core`、`ios/RunCore` 均已存在，故**跳过** `repo-bootstrap` 与项目创建。本项 key 为 `gpx-export-contract`、无用户界面，故**不触发** `ui-baseline`。
- 环境：Swift 6.2 / Xcode 26.3 / macOS arm64；`xmllint`（`/usr/bin/xmllint`）与 `python3` 已在本机可用（`scripts/check-shared.sh` 已硬依赖二者）。测试走 `swift test --package-path ios/RunCore`（macOS destination），故 `Package.swift` 的 `.macOS(.v14)` 必须保留。
- Swift 6 严格并发：新增类型全部为 `struct`/`enum` 值类型并显式 `Sendable`；不引入 `actor`/`class`/全局可变状态/`@unchecked`。
- `check_foundation_only` 扫描整个 `ios/RunCore/Sources`（含可执行 target），因此 `PurePaceGpxTool` 同样只能 `import Foundation`；`XMLParser`、`ISO8601DateFormatter`、`Data` 均在 Foundation 内，可用；`check_no_platform_symbols` 的黑名单（含 `Timer`）对工具同样生效。
- `check_no_fixture_tokens` 扫描整个 `ios/RunCore`（含 `Tests/`），故单测只能使用合成坐标，不能出现夹具文件名；夹具路径仅由 `scripts/check-gpx-export.sh` 以 CLI 参数传入。
- `check_no_version_literal` 扫描 `ios/RunCore` 与 `scripts/*.sh`：不得出现根 `VERSION` 的当前字面值（`0.1.0`）；测试数值与文案需避开该字符串。`description`/creator 文案不得写死版本号。
- `scripts/check-ios-run-core.sh` 是**既有门禁**：本项只做「恰好放行 `PurePaceGpxTool` executable target」+「期望门禁表加入 `check-gpx-export`」+「self-test 增加 executable 反例」三处最小改动，不得放宽零依赖、仅 Foundation、无平台符号、无夹具令牌、无 XcodeGen 产物等既有断言；`copy_package` 需保证新增的 `Sources/PurePaceGpxTool` 在 self-test 副本内同样被扫描到。
- 临时文件：单测用 `NSTemporaryDirectory()` 子目录并在 `defer`/`tearDown` 清理；脚本用 `mktemp -d` + `trap 'rm -rf'` EXIT；不得在仓库内留下 `.gpx` 或其它产物。
- 输出确定性：同一输入多次 `encode` 结果完全一致（固定元素/属性顺序、UTC 时间、POSIX locale），避免测试抖动。
- 证据口径：只报 `swift test --package-path ios/RunCore`、`bash scripts/check-gpx-export.sh`、`bash scripts/check-ios-run-core.sh [--self-test]` 的真实输出与 PASS 计数；不写「真机已验证」「CI 通过」。
