# iOS SwiftPM 可测核心（L1 测试与 xcodegen 退路）

## Scope

在空仓（当前只有协作基线：`VERSION` / `AGENTS.md` / `README.md` / `scripts/version.sh` / `scripts/check-baseline.sh` / `.munk/code-gates.json`）中新增一个独立的 SwiftPM package，作为不依赖模拟器的 L1 测试入口，以及 xcodegen 缺失时 Owner 指定退路：

1. `ios/Core/Package.swift`：包名 `PurePaceCore`，`swift-tools-version: 6.0`，platforms 声明 iOS 17.0 与 macOS 14（保证在 macOS host 上可直接 `swift build` / `swift test`，不需要模拟器），**零外部 package 依赖**。
2. `ios/Core/Sources/PurePaceCore/`：只放非业务的基础设施纯逻辑——版本与构建元数据：
   - `SemanticVersion`：严格 `x.y.z` 解析（拒绝缺段/多段/非数字/前导零/带前缀或后缀）、`Comparable` 逐段比较、渲染回原字符串。
   - `BuildMetadata`：产品显示名 + `SemanticVersion`，初始化时校验非空显示名与合法版本，字段只读。
   - 不引入任何定位/计时/音频/GPX/TCX/网络/持久化逻辑。
3. `ios/Core/Tests/PurePaceCoreTests/`：XCTest 测试目标，覆盖解析 happy path、边界与错误路径，至少 1 个可执行用例。
4. `.munk/code-gates.json` 追加两条真实门：`build-ios-core`（`swift build --package-path ios/Core`）与 `test-ios-core`（`swift test --package-path ios/Core`）；既有 `lint` / `lint-baseline` / `test` 三门保持原样（`test` 仍执行 `scripts/check-baseline.sh`）。
5. 构建/测试产物不入库：`.build/`、`.swiftpm/` 纳入忽略规则。

本项是「波 1」中 iOS 空壳（`ios/project.yml` + XcodeGen 生成工程 + XCTest/XCUITest + `scripts/build-ios.sh` / `test-ios.sh`）的前置：为下游提供可独立验证的纯逻辑层，不与下游争抢 `project.yml`、`.xcodeproj` 或同名脚本。

当前环境事实（已实测）：`swift --version` = Apple Swift 6.2.4、`xcodebuild -version` = Xcode 26.3；`xcodegen` **未安装**，因此本项交付的 `swift test` 就是本轮 iOS 退路证据，不得手写 `project.pbxproj`。

## Acceptance Criteria

- ac-core-package-builds: 在仓库根执行 `swift build --package-path ios/Core` 退出码 0，且不请求任何网络包解析（无 `.package(url:)` 依赖）。
- ac-core-tests-pass: 在仓库根执行 `swift test --package-path ios/Core` 退出码 0，输出中实际执行用例数 ≥ 1 且失败数 = 0。
- ac-l1-no-simulator: 上述两条命令不包含 `xcodebuild`、`-destination`、模拟器 UDID 或 `-sdk iphonesimulator`，未启动模拟器即可通过。
- ac-no-thirdparty-deps: `swift package dump-package --package-path ios/Core` 输出的 `dependencies` 为空数组；`Package.swift` 中无 `url:` / `path:` 形式的 package 依赖，`Sources/` 只 import 系统框架（`Foundation` 及 Swift 标准库）。
- ac-no-business-implementation: `ios/Core/Sources/**` 不含 `CoreLocation` / `CLLocationManager` / `AVFoundation` / `AVAudioSession` / `CoreMotion` / `MapKit` / `HealthKit` / `Timer` / `GPX` / `TCX` / `URLSession` 等业务或平台能力的实现与 import；无持久化、无 UI、无网络代码。
- ac-no-version-literal: `ios/Core/**` 任何文件都不出现当前根 `VERSION` 的字面值（版本必须由调用方传入或在构建期注入，不得在包里写死）。
- ac-semver-strict-parse: `SemanticVersion(parsing:)` 对 `"1.2.3"`、`"0.0.0"`、`"10.20.30"` 返回非 nil 且分段取值正确；对 `"1.2"`、`"1.2.3.4"`、`"v1.2.3"`、`"1.2.3-rc1"`、`"01.2.3"`、`"1.2.3 "`、`""`、`"a.b.c"`、`"1.-2.3"` 返回 nil。
- ac-semver-compare-and-render: 逐段比较语义正确（如 `1.2.3 < 1.2.10`、`1.10.0 > 1.9.9`、相等版本比较结果为相等）；`description` 输出与解析输入一致的 `x.y.z` 形式，可用于往返。
- ac-build-metadata-validation: `BuildMetadata` 用空/纯空白显示名或非法版本字符串初始化时失败（返回 nil 或抛错，二选一且测试锁定）；用合法输入初始化后显示名与版本字段与输入一致且不可变。
- ac-code-gates-ios-core: `.munk/code-gates.json` 含 `build-ios-core` 与 `test-ios-core` 两条门，command 为单一 argv（无 `&&` / `|` / `;` / 重定向 / `echo` / `true`），分别真实执行 `swift build` 与 `swift test`；既有 `test` 门仍执行 `scripts/check-baseline.sh`，且 `bash scripts/check-baseline.sh` 在本项改动后仍全部 PASS。
- ac-no-xcodegen-artifacts: 本项不新增 `ios/project.yml`、`ios/PurePace.xcodeproj`、`project.pbxproj`、`ios/PurePace/` 或 `scripts/build-ios.sh` / `scripts/test-ios.sh`（这些属于下游 iOS 空壳项）。
- ac-build-artifacts-ignored: `git status --porcelain` 在 `swift build` / `swift test` 之后不出现 `ios/Core/.build/`、`ios/Core/.swiftpm/` 等派生产物（由仓库根 `.gitignore` 或 `ios/Core/.gitignore` 覆盖）。

## Non-Goals

- 不创建 XcodeGen 工程真源 `ios/project.yml`、`.xcodeproj` 或任何 `project.pbxproj`；不安装 xcodegen。
- 不创建 App target、占位页、Tab 结构、XCTest/XCUITest 的 app 侧 target，不写 `scripts/build-ios.sh` / `scripts/test-ios.sh`。
- 不实现任何跑步业务：定位、计时、音频/TTS、GPX/TCX 解析、schema/持久化、导出、地图、历史。
- 不安装第三方 Swift 包，不引入 SwiftLint 等工具链依赖，不改 `VERSION` / `README.md` / `AGENTS.md` / `scripts/version.sh` / `scripts/check-baseline.sh` 的既有断言语义。
- 不做视觉设计、不做真机/签名、不推远端、不碰 CI workflow（属下游项）。
- 不新增 `.munk/code-gates.json` 之外的 Host 托管文件。

## Implementation Constraints

- 已确认的宿主环境：Swift 6.2.4 / Xcode 26.3 / macOS arm64；`swift test` 走 macOS 目标，因此 `Package.swift` 的 `platforms` 必须同时包含 `.macOS(.v14)` 与 `.iOS(.v17)`，否则 host 侧无法编译测试。
- 使用 `swift-tools-version: 6.0`，语言模式为 Swift 6（严格并发）：对外类型应为值类型并显式 `Sendable` / `Equatable`，避免在纯逻辑层引入 actor 或全局可变状态。
- 布局固定为 `ios/Core/{Package.swift, Sources/PurePaceCore/, Tests/PurePaceCoreTests/}`；测试用 `XCTest`，不得使用 Swift Testing（与 AGENTS.md 声明的 XCTest 测试金字塔一致）。
- 门禁命令必须是可直接执行的单一 argv；若需要结构断言（如零依赖、无业务符号），用 `scripts/` 下新增 bash 脚本承载（`set -euo pipefail`、幂等、支持 `--help`、以后仓根为路径基准），由门以 `bash scripts/<name>.sh` 调用，禁止在 command 中拼接管道。
- 版本号禁止写死：包内不出现 `VERSION` 当前字面值；测试中的版本样例使用与仓库版本无关的合成值。
- 依赖关系：本项是 `wi_ws_ce605c342b221168`（iOS 空壳）与 `wi_ws_83a62c6534df30c6` 的前置；下游可直接以 `PurePaceCore` 作为纯逻辑依赖，但本项不预埋任何业务 API。
- 回执证据口径：报告 `swift build` / `swift test` 的真实输出摘要与用例数，不写「CI 已通过」「真机已验证」；本地门通过不得替代远端 run（远端由波 1 Delivery 建立）。
