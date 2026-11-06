# iOS SwiftUI 空壳工程（XcodeGen + XCTest + XCUITest）

## 范围

在 `ios/` 下从零建立 PurePace iOS 空壳工程，工程文件唯一真源为 `ios/project.yml`（XcodeGen），App/测试源码目录与 xcodebuild 脚本齐备：

- `ios/project.yml`：XcodeGen 规格，声明 App target `PurePace`、XCTest target `PurePaceTests`、XCUITest target `PurePaceUITests`、共享 scheme `PurePace`；deployment target iOS 17.0、Swift 6.2 语言模式、仅系统框架、无第三方包依赖、模拟器构建不签名。
- `ios/PurePace/`：SwiftUI 占位页，仅含 App 名 `PurePace`、一句 tagline、空 Tab 结构（Run / History / Log / Settings 四个占位 Tab），不做视觉设计、不做业务实现、不内置样例数据。
- `ios/PurePaceTests/`：≥1 个 XCTest 用例（对占位页的纯逻辑内容如 Tab 标题/文案做断言）。
- `ios/PurePaceUITests/`：≥1 个 XCUITest 用例，启动 App 后断言 `PurePace` 文案可见且四个 Tab 可访问。
- `ios/PurePace.xcodeproj`：由 `xcodegen generate` 生成后入库；**禁止手写 `project.pbxproj`**，禁止提交 GUI 生成未整理的工程。
- `scripts/build-ios.sh`、`scripts/test-ios.sh`：bash、`set -euo pipefail`、幂等、支持 `--help`、路径以仓库根为基准；被 `.munk/code-gates.json` 新增的 iOS 门真实调用。
- `.munk/code-gates.json`：新增 iOS 侧 lint / build / test 门（单一 argv，禁止 `&&`/`|`/`;`/重定向），既有 `lint` / `lint-baseline` / `lint-ios-core` / `build-ios-core` / `test-ios-core` / `test` 语义不得放宽或删除。

分支口径（本项已实测的现状）：`xcodegen` 当前不在 PATH（`xcodegen not found`），Xcode 26.3 与 iPhone 16 / iOS 18.6 模拟器齐备（UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`），`brew` 可用。因此分别给出主路径与退路的可断言验收。

## 验收标准

### A. 主路径（一次安装尝试后 xcodegen 可用）

- ac-xcodegen-single-source: `ios/project.yml` 存在且 `xcodegen generate --spec ios/project.yml` 成功；生成后 `ios/PurePace.xcodeproj/project.pbxproj` 入库，再次执行同一命令后 `git status --porcelain ios/PurePace.xcodeproj` 为空（工程为生成产物，非手写）。
- ac-no-handwritten-pbxproj: 仓库中 `project.pbxproj` 仅存在于 `ios/PurePace.xcodeproj/` 且可由 `project.yml` 再生成；不存在被手工改写的孤立工程文件（如 `ios/PurePace.xcodeproj` 之外的第二份工程、或缺失 `project.yml` 却有工程）。
- ac-build-settings: `xcodebuild -showBuildSettings -scheme PurePace -destination "platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD"` 输出中 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`、`SWIFT_VERSION = 6.2`，且 `MARKETING_VERSION` 等于根 `VERSION` 文件内容（不得另写死版本号）。
- ac-build-app: `xcodebuild build`（`-scheme PurePace`、同上 destination、`CODE_SIGNING_ALLOWED=NO`）返回 0 并产出 `PurePace.app`（构建目录内可定位到 `.app` 包）。
- ac-app-targets-and-frameworks: 工程含三个 target `PurePace` / `PurePaceTests` / `PurePaceUITests`，App target 无 SwiftPM/第三方依赖声明；App 源码 import 仅限系统框架（无 `CoreLocation` / `AVFoundation` / `HealthKit` / `MapKit` 等业务相关框架）。
- ac-placeholder-ui: App 首屏源码含 `PurePace` 文案、一句 tagline 与 Run/History/Log/Settings 四个 Tab 占位（`TabView`），无业务逻辑、无内置样例/种子数据、无网络请求。
- ac-xctest-pass: `xcodebuild test -only-testing:PurePaceTests` 在 iPhone 16 (iOS 18.6) 模拟器上通过，执行用例数 ≥ 1。
- ac-xcuitest-pass: `xcodebuild test -only-testing:PurePaceUITests` 在同一模拟器上通过，用例实际启动 App 并断言 `PurePace` 静态文本与四个 Tab 存在。
- ac-scripts-and-gates: `bash scripts/build-ios.sh --help` 与 `bash scripts/test-ios.sh --help` 退出码 0 且打印说明；两者真实执行构建/测试（非 `echo`/`true` 空转）；`.munk/code-gates.json` 中 iOS 门全部为单一 argv 且在本机全绿，既有门保持原语义。

### B. 退路（一次安装尝试后 xcodegen 仍不可用）

- ac-blocked-recorded: 交付摘要中如实写入 `blocked: 缺 xcodegen`，并记录实际尝试的命令与其失败输出摘要；不得声称 iOS 工程已构建或 CI 通过。
- ac-no-fake-project: 退路下不得出现手写/占位的 `ios/PurePace.xcodeproj`（含 pbxproj）；`ios/project.yml`、`ios/PurePace/`、`ios/PurePaceTests/`、`ios/PurePaceUITests/` 源码可先落盘，工程生成与 xcodebuild 门延后。
- ac-core-fallback-green: `swift test --package-path ios/Core` 通过（真实输出含测试数与通过），作为本项唯一可执行的 iOS 验证证据。
- ac-gates-not-weakened: 退路下 `.munk/code-gates.json` 仍全绿，且不得用 `echo` / `true` / 注释掉的命令冒充 iOS 构建或测试门；`scripts/check-baseline.sh` 既有断言不得放宽。

## 非目标

- 不做 Android 骨架、`shared/` 夹具与 schema、`.github/workflows/*`、CI run 验证（属后续波次 / 其他子项）。
- 不做任何跑步业务实现：定位、计时、音频/TTS/节拍、地图、历史列表、导出、相机扫码。
- 不做视觉设计、设计 token、多语言框架、账号/云/社交、跨端框架。
- 不做真机签名、TestFlight、分发凭据；只做模拟器构建与测试。
- 不重构既有 `ios/Core` 包、不新增其业务 API、不改写 `scripts/check-baseline.sh` / `scripts/check-ios-core.sh` 的既有断言。
- 不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- 当前仓库事实（Intake 已实测）：`xcodegen` 不在 PATH；`xcodebuild` 为 Xcode 26.3 (17C529)；iOS 18.6 运行时与 iPhone 16 模拟器已安装；`brew` 位于 `/opt/homebrew/bin/brew`；`ios/` 下目前仅有 `Core`，无 `project.yml` / `PurePace/` / 脚本。
- xcodegen 安装：Owner 已批一次安装。按「探测 → `brew install xcodegen`（或等价官方二进制）→ 复核 `xcodegen --version`」一次尝试，单个波次内不得反复折腾；失败即切 B 退路并记 `blocked: 缺 xcodegen`。不得手写 pbxproj 绕过。
- 工程规格落点：`ios/project.yml` 为唯一真源；bundle id 统一 `com.chaxiu.purepace`（与 Android applicationId 口径一致），只在此处定义一次。
- 版本派生：`MARKETING_VERSION` 必须来自根 `VERSION`（生成期读取，如 XcodeGen 的环境变量替换 + 脚本导出），禁止在 `project.yml` 或源码里写死当前版本字面值；`CURRENT_PROJECT_VERSION` 用常量构建号即可。
- 目标设备/命令口径：destination 固定 iPhone 16 / iOS 18.6（UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`）；构建与测试统一 `CODE_SIGNING_ALLOWED=NO`，无真机、无 provision profile。
- 门禁形态：新增 iOS 结构断言（如 `scripts/check-ios-shell.sh`）+ 真实 `xcodebuild` 门；`lint` 侧在无 swiftlint 的前提下可用 `bash -n` 与结构断言承载，但必须真实执行、退出码可信；code-gates 的 `command` 仍是单一 argv，需要多步时封装进脚本。
- 依赖/分层：App target 可选依赖本地包 `ios/Core`（若依赖则用本地路径引用，不复制源码），但不得向其添加业务 API；`ios/PurePace/` 不放样例数据，示例数据只允许出现在测试代码中。
- 证据口径：只报真实命令输出摘要与用例数；xcodegen 缺失时写 `blocked: 缺 xcodegen`，禁止写「已构建」「CI 通过」「真机已验证」。
