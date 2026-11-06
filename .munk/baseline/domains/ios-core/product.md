# Domain: ios-core

不依赖模拟器的 iOS 纯逻辑核心：独立 SwiftPM package `ios/Core`（包名 `PurePaceCore`），既是 L1 测试入口，也是 xcodegen 未安装时 Owner 指定的退路。只放非业务基础设施纯逻辑，不承载任何跑步业务实现，也不创建 App target / Xcode 工程。

## 范围

- `ios/Core/Package.swift`：`swift-tools-version: 6.0`，platforms 同时声明 `.iOS(.v17)` 与 `.macOS(.v14)`（保证 macOS host 上可直接 `swift build` / `swift test`），零外部 package 依赖。
- `ios/Core/Sources/PurePaceCore/`：仅版本与构建元数据基础设施。
  - `SemanticVersion`：严格 `x.y.z` 解析、`Comparable` 逐段比较、渲染回原字符串。
  - `BuildMetadata`：产品显示名 + `SemanticVersion`，初始化期校验非空显示名与合法版本，字段只读。
- `ios/Core/Tests/PurePaceCoreTests/`：XCTest 测试目标，覆盖解析 happy path、边界与错误路径。
- 门禁：`.munk/code-gates.json` 的 `build-ios-core`（`swift build --package-path ios/Core`）与 `test-ios-core`（`swift test --package-path ios/Core`）真实执行；结构断言由 `scripts/check-ios-core.sh`（`lint-ios-core` 门）承载。既有 `lint` / `lint-baseline` / `test` 语义不变。
- 构建产物（`.build/`、`.swiftpm/`）由忽略规则覆盖，不入库。

## 验收

- ac-core-package-builds: 仓库根执行 `swift build --package-path ios/Core` 退出码 0，且不触发网络包解析（无 `.package(url:)` 依赖）。
- ac-core-tests-pass: 仓库根执行 `swift test --package-path ios/Core` 退出码 0，实际执行用例数 ≥ 1 且失败数 = 0。
- ac-l1-no-simulator: 上述两条命令不含 `xcodebuild`、`-destination`、模拟器 UDID 或 `-sdk iphonesimulator`，未启动模拟器即可通过。
- ac-no-thirdparty-deps: `swift package dump-package --package-path ios/Core` 的 `dependencies` 为空数组；`Package.swift` 无 `url:` / `path:` 形式依赖；`Sources/` 只 import 系统框架（`Foundation` 与 Swift 标准库）。
- ac-no-business-implementation: `ios/Core/Sources/**` 不含 `CoreLocation` / `CLLocationManager` / `AVFoundation` / `AVAudioSession` / `CoreMotion` / `MapKit` / `HealthKit` / `Timer` / `GPX` / `TCX` / `URLSession` 等业务或平台能力的实现与 import；无持久化、无 UI、无网络代码。
- ac-no-version-literal: `ios/Core/**` 不出现根 `VERSION` 的字面值；版本必须由调用方传入或在构建期注入。
- ac-semver-strict-parse: `SemanticVersion(parsing:)` 对 `"1.2.3"`、`"0.0.0"`、`"10.20.30"` 返回非 nil 且分段取值正确；对 `"1.2"`、`"1.2.3.4"`、`"v1.2.3"`、`"1.2.3-rc1"`、`"01.2.3"`、`"1.2.3 "`、`""`、`"a.b.c"`、`"1.-2.3"` 返回 nil。
- ac-semver-compare-and-render: 逐段比较语义正确（`1.2.3 < 1.2.10`、`1.10.0 > 1.9.9`、相等版本比较为相等）；`description` 输出与解析输入一致的 `x.y.z`，可往返。
- ac-build-metadata-validation: `BuildMetadata` 以空/纯空白显示名或非法版本字符串初始化时失败（返回 nil 或抛错，二选一由测试锁定）；合法输入初始化后字段与输入一致且不可变。
- ac-code-gates-ios-core: `.munk/code-gates.json` 含 `build-ios-core` 与 `test-ios-core`，command 为单一 argv（无 `&&` / `|` / `;` / 重定向 / `echo` / `true`）；既有 `test` 门仍执行 `scripts/check-baseline.sh`，且改动后 `bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-no-xcodegen-artifacts: 不新增 `ios/project.yml`、`ios/PurePace.xcodeproj`、`project.pbxproj`、`ios/PurePace/` 或 `scripts/build-ios.sh` / `scripts/test-ios.sh`。
- ac-build-artifacts-ignored: `swift build` / `swift test` 之后 `git status --porcelain` 不出现 `ios/Core/.build/`、`ios/Core/.swiftpm/` 等派生产物。

## 非目标

- 不创建 XcodeGen 工程真源 `ios/project.yml`、`.xcodeproj` 或任何 `project.pbxproj`；不安装 xcodegen。
- 不创建 App target、占位页、Tab 结构、app 侧 XCTest/XCUITest target，不写 `scripts/build-ios.sh` / `scripts/test-ios.sh`。
- 不实现任何跑步业务：定位、计时、音频/TTS、GPX/TCX 解析、schema/持久化、导出、地图、历史。
- 不安装第三方 Swift 包或 SwiftLint 等工具链依赖；不改 `VERSION` / `README.md` / `AGENTS.md` / `scripts/version.sh` / `scripts/check-baseline.sh` 的既有断言语义。
- 不做视觉设计、不做真机/签名、不推远端、不碰 CI workflow。
- 不新增 `.munk/code-gates.json` 之外的 Host 托管文件。

## 实现约束

- 宿主环境：Swift 6.2.4 / Xcode 26.3 / macOS arm64；`swift test` 走 macOS 目标，故 `platforms` 必须同时含 `.macOS(.v14)` 与 `.iOS(.v17)`，否则 host 侧无法编译测试。
- `swift-tools-version: 6.0`、Swift 6 语言模式（严格并发）：对外类型为值类型并显式 `Sendable` / `Equatable`，纯逻辑层不引入 actor 或全局可变状态。
- 布局固定为 `ios/Core/{Package.swift, Sources/PurePaceCore/, Tests/PurePaceCoreTests/}`；测试用 `XCTest`，禁用 Swift Testing。
- 门禁命令必须是可直接执行的单一 argv；需要结构断言（零依赖、无业务符号等）时用 `scripts/` 下 bash 脚本承载（`set -euo pipefail`、幂等、支持 `--help`、以仓库根为路径基准），由门以 `bash scripts/<name>.sh` 调用，禁止在 command 中拼接管道。
- 版本号禁止写死：包内不出现根 `VERSION` 当前字面值；测试版本样例使用与仓库版本无关的合成值。
- 依赖关系：本域是 iOS 空壳（`ios/project.yml` + `.xcodeproj`）的前置；下游可直接以 `PurePaceCore` 作为纯逻辑依赖，但本域不预埋业务 API。
- 证据口径：只报 `swift build` / `swift test` 的真实输出摘要与用例数，不写「CI 已通过」「真机已验证」；本地门通过不得替代远端 run。

## 最近交付证明

- workItemId: wi_ws_f96786f27aa224bd（2026-11-07，pass）
- 交付：`ios/Core` SwiftPM 包（`Package.swift` iOS 17 + macOS 14、零依赖）、`SemanticVersion` + `BuildMetadata` 两个纯逻辑类型、`PurePaceCoreTests` XCTest 用例；`.gitignore` 覆盖 `.build/` 与 `.swiftpm/`；`scripts/check-ios-core.sh` 结构断言；`.munk/code-gates.json` 新增 `lint-ios-core` / `build-ios-core` / `test-ios-core`，`lint` / `lint-baseline` / `test` 保持原样。
- 验证：`code_gates` 全部通过（含真实 `swift build` / `swift test` 与 `scripts/check-baseline.sh`）；未使用 xcodebuild / 模拟器；未新增 `project.yml` / `.xcodeproj`。
