# Domain: ios-shell

PurePace iOS 空壳工程域：以 XcodeGen 规格 `ios/project.yml` 为唯一真源生成 `ios/PurePace.xcodeproj`，承载 App 占位页、XCTest/XCUITest 两个测试 target 与真实 `xcodebuild` 构建/测试脚本。只做骨架与验证路径，不含任何跑步业务实现、视觉设计与第三方运行时依赖。

## 范围

- `ios/project.yml`：XcodeGen 规格，声明 App target `PurePace`、单元测试 target `PurePaceTests`、UI 测试 target `PurePaceUITests` 与共享 scheme `PurePace`；deployment target iOS 17.0、`SWIFT_VERSION = 6.2`、零 SwiftPM/第三方依赖、模拟器构建 `CODE_SIGNING_ALLOWED=NO`。
- `ios/PurePace.xcodeproj`：由 `xcodegen generate` 生成的产物入库，**禁止手写 `project.pbxproj`**。
- `ios/Config/Version.xcconfig`：由 `scripts/sync-ios-version.sh` 从根 `VERSION` 派生 `MARKETING_VERSION`；`project.yml` 以 `configFiles` 引用，版本不在规格或源码中写死。
- `ios/PurePace/`：SwiftUI 占位页（App 名 `PurePace` + 一句 tagline + Run/History/Log/Settings 四个空 Tab），无业务逻辑、无内置样例数据、无网络请求。
- `ios/PurePaceTests/`：XCTest 用例，对占位页文案/结构做断言；`ios/PurePaceUITests/`：XCUITest 用例，启动 App 后断言 `PurePace` 文案与四个 Tab 可访问。
- `scripts/build-ios.sh`、`scripts/test-ios.sh`：先由根 `VERSION` 同步 `Config/Version.xcconfig`，工程缺失且有 xcodegen 时从 spec 生成，再对 iPhone 16 / iOS 18.6 执行真实 `xcodebuild build` / `xcodebuild test`（无签名）；工程不可用时输出 `blocked:` 并降级真实 `swift build|test --package-path ios/Core`，绝不伪造成功行。`scripts/check-ios-shell.sh` 承载本域结构断言，`scripts/check-ios-scripts.sh` 承载脚本契约断言。
- 门禁：`.munk/code-gates.json` 新增 `lint-ios-shell` / `build-ios` / `test-ios`（均为单一 argv，指向上述脚本）；既有 `lint` / `lint-baseline` / `lint-ios-core` / `build-ios-core` / `test-ios-core` / `test` 语义不变。

## 验收

- ac-xcodegen-single-source: `ios/project.yml` 存在且 `xcodegen generate --spec ios/project.yml` 成功；生成后 `ios/PurePace.xcodeproj/project.pbxproj` 入库，再次执行同一命令后 `git status --porcelain ios/PurePace.xcodeproj` 为空（工程是生成产物而非手写）。
- ac-no-handwritten-pbxproj: `project.pbxproj` 仅存在于 `ios/PurePace.xcodeproj/` 且可由 `project.yml` 再生成；不存在第二份工程或「有工程却无 `project.yml`」的孤立工程。
- ac-build-settings: `xcodebuild -showBuildSettings -scheme PurePace`（iPhone 16 / iOS 18.6 destination）输出 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`、`SWIFT_VERSION = 6.2`，且 `MARKETING_VERSION` 等于根 `VERSION` 内容。
- ac-build-app: `xcodebuild build`（`-scheme PurePace`、同 destination、`CODE_SIGNING_ALLOWED=NO`）返回 0 并在构建目录产出 `PurePace.app`。
- ac-app-targets-and-frameworks: 工程含 `PurePace` / `PurePaceTests` / `PurePaceUITests` 三个 target，App target 无 SwiftPM 或第三方依赖声明，App 源码 import 仅限系统框架（无 `CoreLocation` / `AVFoundation` / `HealthKit` / `MapKit` 等业务框架）。
- ac-placeholder-ui: App 首屏源码含 `PurePace` 文案、一句 tagline 与 Run/History/Log/Settings 四个 `TabView` 占位，无业务逻辑、无内置样例/种子数据、无网络请求。
- ac-xctest-pass: `xcodebuild test -only-testing:PurePaceTests` 在 iPhone 16 (iOS 18.6) 模拟器通过，执行用例数 ≥ 1。
- ac-xcuitest-pass: `xcodebuild test -only-testing:PurePaceUITests` 在同一模拟器通过，用例真实启动 App 并断言 `PurePace` 静态文本与四个 Tab 存在。
- ac-scripts-and-gates: `bash scripts/build-ios.sh --help` 与 `bash scripts/test-ios.sh --help` 退出码 0 且打印说明；两脚本真实执行构建/测试（非 `echo` / `true` 空转）；`.munk/code-gates.json` 中 iOS 门全部单一 argv 且本机全绿，既有门语义未放宽。

## 非目标

- 不做任何跑步业务实现：定位、计时、音频/TTS/节拍、地图、历史列表、导出、相机扫码、GPX/TCX 解析与持久化。
- 不做视觉设计、设计 token、多语言框架、账号/云/社交，不引入跨端框架。
- 不做真机签名、provision profile、TestFlight 与分发凭据；只做模拟器构建与测试。
- 不做 Android 骨架、`shared/` 夹具与 schema、CI workflow 与远端 run 验证。
- 不重构既有 `ios/Core` 包、不向其新增业务 API；不改写 `scripts/check-baseline.sh` / `scripts/check-ios-core.sh` 既有断言；不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- 环境事实：Xcode 26.3 / Swift 6.2，iOS 18.6 运行时与 iPhone 16 模拟器已安装（destination 以 UDID 固定），构建与测试统一 `CODE_SIGNING_ALLOWED=NO`。
- XcodeGen 为构建期工具，已由 Owner 批准一次安装（`brew install xcodegen` 或等价官方二进制）；本域不允许手写 pbxproj 绕过工具缺失，也不允许在无 xcodegen 时伪造工程入库。
- bundle id 统一 `com.chaxiu.purepace`（与 Android applicationId 口径一致），只在 `project.yml` 一处定义，测试 target 以其为前缀派生。
- 版本派生：`MARKETING_VERSION` 只能来自根 `VERSION`（经 `scripts/sync-ios-version.sh` → `ios/Config/Version.xcconfig`），`project.yml`、源码与脚本均不得写死当前版本字面值；`CURRENT_PROJECT_VERSION` 用常量构建号。
- 依赖/分层：App target 可选择以本地路径依赖 `ios/Core`（不复制源码），但不得向其添加业务 API；`ios/PurePace/` 不放样例数据，示例数据只允许出现在测试代码中。
- 门禁形态：`command` 保持单一 argv，多步流程封装进 `scripts/` 下 bash 脚本（`set -euo pipefail`、幂等、支持 `--help`、以仓库根为路径基准）；构建/测试产物由忽略规则覆盖，不入库。
- destination 钉住 iPhone 16 且必须带 `OS=18.6`（或等价 UDID）：只写 `name=iPhone 16` 会被解析成 `latest` 运行时（本机为 iOS 26.3.1，无 iPhone 16 机型）而构建失败；工程缺失时脚本走 `blocked:` + SwiftPM 降级分支，不得让门禁因此失败。
- 门禁共存：本域 `lint-ios-shell` 与脚本契约门 `lint-ios-scripts` 必须同时通过；后者对 destination 的断言按「iPhone 16 + 可选 OS/UDID」校验，不得放宽为任意机型。
- 证据口径：只报真实命令输出摘要与用例数，不写「CI 通过」「真机已验证」；本地门通过不替代远端 run。

## 最近交付证明

- workItemId: wi_ws_ce605c342b221168（2026-11-07，pass）
- 交付：`ios/project.yml`（三 target + 共享 scheme，iOS 17.0 / Swift 6.2 / 零依赖 / 不签名）、由 XcodeGen 生成入库的 `ios/PurePace.xcodeproj`、`ios/Config/Version.xcconfig` 版本派生链路、SwiftUI 四 Tab 占位页与 XCTest/XCUITest 用例；`scripts/sync-ios-version.sh`、`build-ios.sh`、`test-ios.sh`、`check-ios-shell.sh`；`.munk/code-gates.json` 新增 `lint-ios-shell` 门，与既有 `lint-ios-scripts` / `build-ios` / `test-ios` 合并为共存门集合。
- 验证：本机 xcodegen 2.46.0 可用，主路径达成——`xcodegen generate` 重复执行工程零 diff、`xcodebuild build` 产出 `PurePace.app`（BUILD SUCCEEDED）、`xcodebuild test` 在 iPhone 16 / iOS 18.6 上 `PurePaceTests` 4 例与 `PurePaceUITests` 1 例全部通过（TEST SUCCEEDED）、`scripts/check-ios-shell.sh` 7 项断言 0 失败、`scripts/check-ios-scripts.sh` 11 项断言 0 失败（destination 断言按实际需要允许显式 `OS=18.6`，避免 `latest` 解析到无 iPhone 16 的运行时）。
