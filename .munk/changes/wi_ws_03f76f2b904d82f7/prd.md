# App target AudioSession 适配器与模拟器读回契约

## 范围

把已交付的 `ios/RunCore`（SwiftPM 包 `PurePaceRunCore`）以**本地 path package** 接入 iOS 工程，并在 App target 落地一层薄 AVAudioSession 适配器，让波 1 的纯逻辑音频契约第一次接到真实平台框架；不发声、不铺 UI：

1. `ios/project.yml`：新增本地包声明 `PurePaceRunCore: path: RunCore`（相对 spec 目录），`PurePace` 与 `PurePaceTests` 两个 target 显式依赖该包；`xcodegen generate` 重新生成 `ios/PurePace.xcodeproj` 并入库。
2. App target 新增音频适配器（`ios/PurePace/Audio/AudioSessionAdapter.swift` 及同目录必要文件）：
   - 把 `AudioSessionSettings.defaultAnnouncement` 落到真实 `AVAudioSession`：category `.playback`、mode `.spokenAudio`、激活选项 `[.duckOthers, .mixWithOthers]`；
   - 播报开始 → 激活；播报结束 → `setActive(false, options: .notifyOthersOnDeactivation)`（选项来源为 `AudioSessionSettings.deactivationOptions`，不写死字符串）；
   - 监听 `AVAudioSession.interruptionNotification`，把 `.began` / `.ended`（含 `AVAudioSessionInterruptionOptionShouldResume`）映射为 `AudioSessionCoordinator` 的 `interruptionBegan()` / `interruptionEnded(shouldResume:)`，并执行返回的 `AudioSessionAction`。
   - 平台调用必须抽到可注入的协议后面（真实实现包装 `AVAudioSession.sharedInstance()`，测试用 spy 实现），以便在模拟器里断言「下发了什么调用」而不依赖真实音频路由与真实来电。
3. `ios/PurePaceTests/`：新增模拟器 XCTest —— 用真实会话读回 category / mode / categoryOptions；用 spy 断言 deactivate 选项与中断恢复动作序列。
4. `scripts/check-ios-shell.sh`：只放宽「本地 path package + App 音频适配器 import」两处，继续禁止远程/第三方依赖与首屏业务逻辑。
5. 基线文档同步（`ios-shell` 域为主体；`ios-runcore` 域本项**不改**，RunCore 源码零改动）。

对齐检查点：`cp-tts-audio-contract`（本项补齐模拟器/App 侧证据）、`cp-stage2-exit`（本项**不关闭**；真机项仍待现场）。

## 验收

- ac-local-package-wired: `ios/project.yml` 以 `path` 形式声明 `PurePaceRunCore` 并指向 `RunCore`，`PurePace` 与 `PurePaceTests` 均显式依赖它；`xcodegen generate --spec ios/project.yml` 成功，且连续两次生成后 `git status --porcelain ios/PurePace.xcodeproj` 为空（工程是可重复生成的产物）；生成的 `project.pbxproj` 含本地包引用，且不含任何 `url:` / `https://` / 远程 package 引用。
- ac-package-resolution-offline: 在已生成工程上执行 `xcodebuild -resolvePackageDependencies -project ios/PurePace.xcodeproj -scheme PurePace` 返回 0，且解析结果只来自仓库内 `ios/RunCore`（无 `Package.resolved` 中的远程 `location`）。
- ac-shell-gate-local-package-only: `bash scripts/check-ios-shell.sh` 退出码 0；脚本对 `project.yml` 中非本地包（含 `url:`、`https://`、`.package(url`）判定失败，且该负向判定可被真实执行（`--self-test` 或等价反例注入，不允许只写注释）。
- ac-app-imports-scoped: App 源码允许 `SwiftUI` / `Foundation` / `AVFoundation` / `PurePaceRunCore` 四种 import，其余（`CoreLocation` / `HealthKit` / `MapKit` / `CoreMotion` / `UserNotifications` / `URLSession` 等）仍判失败；`AVFoundation` 只允许出现在 `ios/PurePace/Audio/` 下的适配器文件中，首屏/占位页文件仍不得出现业务框架与网络请求。
- ac-simulator-readback-configured: 在 iPhone 16 / iOS 18.6 模拟器上 `xcodebuild test -only-testing:PurePaceTests` 通过，其中一条用例经适配器应用默认配置后，从 `AVAudioSession.sharedInstance()` 读回 `category == .playback`、`mode == .spokenAudio`、`categoryOptions` 同时包含 `.duckOthers` 与 `.mixWithOthers`；用例不得使用 `XCTSkip`/`throw XCTSkip` 或条件跳过，读回不符即失败。
- ac-deactivate-options-spy: spy 记录到播报结束时下发 **恰好一次** `setActive(false, options:)`，其 options 恰为 `[.notifyOthersOnDeactivation]`（集合相等，不多不少）；重复结束调用不再重复下发 deactivate。
- ac-interruption-mapping: 向适配器投递真实 `AVAudioSession.interruptionNotification` 的 began userInfo 后，spy 观察到进入 `.interrupted` 且不产生激活调用；随后投递 ended + `AVAudioSessionInterruptionOptionShouldResume` 的 userInfo，spy 观察到按 `.playback/.spokenAudio/[.duckOthers,.mixWithOthers]` 重新 setCategory + setActive(true)；投递不带 `ShouldResume` 的 ended 则回到 `.inactive` 且无激活调用。
- ac-activation-idempotent-on-device-path: 连续两次「播报开始」只下发 1 次 setActive(true)（复用 `AudioSessionCoordinator` 幂等语义，不在 App 侧另建状态机）。
- ac-first-screen-untouched: 首屏仍是 `PurePace` + tagline + Run/History/Log/Settings 四个空 `TabView` 页；App 源码不含 `AVSpeechSynthesizer`、无新增页面/路由，`check-ios-shell.sh` 的占位页断言通过。
- ac-runcore-unchanged: `ios/RunCore/**` 本项零改动（`git diff --stat` 无该路径），`bash scripts/check-ios-run-core.sh` 与 `swift test --package-path ios/RunCore` 仍全绿；RunCore 仍只 `import Foundation`。
- ac-gates-green: `bash scripts/build-ios.sh`、`bash scripts/test-ios.sh`、`bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-baseline.sh` 全部退出码 0；`.munk/code-gates.json` 门数量不减少（允许新增 `lint-ios-shell` 之外的 App 音频专测门，但不得删除或放宽既有门）。
- ac-evidence-wording: 交付结论只写「配置与调度契约通过」（模拟器）与真实用例数；「音乐不打断与 duck 恢复」「TTS 实听」「锁屏后台连续定位」一律记 `pending: 待人现场`，全文不得出现「实听通过」「真机已验证」「音乐不打断已验证」。

## 非目标

- 不实现真实语音播报（不引入 `AVSpeechSynthesizer` / TTS 引擎 / 音频文件 / 节拍器），不调音量与音频路由（蓝牙/AirPods 切换不在本项）。
- 不铺任何 UI：不新增跑步页、播报开关、设置页，不改首屏布局与文案，不接 `RunSessionMachine` / `RunMetricsEngine` 的装配或启动流程。
- 不改 `ios/RunCore/**` 的公开签名、枚举 rawValue、状态机与算法；不新增播报/中断耦合语义（中断期是否丢命令仍不定义）。
- 不新增远程/第三方 SwiftPM 依赖（本地 path package 是唯一放宽项），不引入跨端框架。
- 不做真机、签名、TestFlight、CI 触发与远端 run 验证；不修改 `.github/workflows/*` 的触发条件、权限与构建语义。
- 不做 Android 侧任何改动；不改 `scripts/build-ios.sh` / `scripts/test-ios.sh` 的入口语义与降级分支契约。
- 不用 `XCTSkip` 或降级断言换取绿灯；模拟器读不回就如实失败并上报，不写「已验证」。
- 不把 `ios/Core`（PurePaceCore）与 `ios/RunCore` 合并，不向 `ios/Core` 加业务 API。

## 实现约束

- **XcodeGen 接入**：`ios/project.yml` 顶层新增 `packages: PurePaceRunCore: { path: RunCore }`（相对 spec 目录），target 侧 `dependencies: [{ package: PurePaceRunCore, product: PurePaceRunCore }]`；`PurePaceTests` 必须**显式**依赖该包（不依赖从 App target 传递 import，Swift 6 下显式更稳）。生成命令沿用 `xcodegen generate --spec ios/project.yml`，产物 `ios/PurePace.xcodeproj` 入库，禁止手写 pbxproj。
- **适配器落点**：`ios/PurePace/Audio/AudioSessionAdapter.swift`（可加同目录小文件），不进首屏文件；`PurePaceApp.swift` / `ContentView.swift` / `PlaceholderScreen.swift` / `PlaceholderCopy.swift` 保持无业务引用（本项不接线到 App 生命周期，避免把「未播报」写成已实现）。
- **可测接缝**：定义最小协议，例如 `AudioSessionControlling { var category/mode/categoryOptions 读回; func setCategory(_:mode:options:) throws; func setActive(_:options:) throws }`，真实实现包装 `AVAudioSession.sharedInstance()`，spy 实现记录 `(方法, 参数)` 序列；适配器只依赖协议 + `AudioSessionCoordinator`，动作经注入的 sink 暴露给测试。不要用全局单例或静态可变状态（Swift 6.2 严格并发 + `Sendable`）。
- **选项映射**：`AudioCategoryOption` → `AVAudioSession.CategoryOptions` 必须用显式 `switch` 全量映射（`AudioCategoryOption.allCases` 每个 case 都要有分支，缺一即编译错误），不得用 rawValue 字符串拼接或 `OptionSet` 位运算猜；`deactivationOptions` 同理。
- **中断来源**：适配器内部 `NotificationCenter` 观察 `AVAudioSession.interruptionNotification`；测试可直接构造 `Notification(name:object:userInfo:)` 并带上 `AVAudioSessionInterruptionTypeKey` / `AVAudioSessionInterruptionOptionKey` 正确类型值投递给适配器的处理入口，**不需要**真实来电或真实音频路由。
- **模拟器读回风险**：模拟器无真实音频路由时 `setCategory`/`setActive` 可能行为受限。要求：先真实调用再真实读回；若本机模拟器确实无法读回，如实失败并 `munk_report_owner`，禁止改成 `XCTSkip`、禁止只断言纯逻辑镜像、禁止把读回断言降级为注释。测试之间需复位（`setActive(false)` + 默认 category）避免顺序耦合。
- **`check-ios-shell.sh` 改动边界**（只放宽两处，其余断言不动）：
  1. 包断言：由「出现 `packages:` 即失败」改为「只允许 `path:` 本地条目且路径限于 `RunCore`；出现 `url:` / `https://` / `.package(url` 仍失败」；
  2. import 断言：allowlist 增加 `AVFoundation`、`PurePaceRunCore`，并新增「`AVFoundation` 仅允许出现在 `ios/PurePace/Audio/*.swift`」；
  3. 首屏业务断言：把 `grep ... ios/PurePace/*.swift` 的非递归 glob 换成**显式文件清单**（`PurePaceApp.swift`/`ContentView.swift`/`PlaceholderCopy.swift`/`PlaceholderScreen.swift`），保持 `URLSession|CoreLocation|AVFoundation|HealthKit` 在该清单内仍判失败 —— 明确写出这是收紧而非靠 glob 漏掉子目录。
  脚本保持 `set -euo pipefail`、`--help`、两次生成零 diff 的既有语义。
- **脚本契约**：不改 `scripts/test-ios.sh` / `build-ios.sh` 的 `xcodebuild test|build`、`-scheme PurePace`、`iPhone 16` destination 字面量与降级分支（`check-ios-scripts.sh` 会断言）；纯 `PurePaceTests` 增量随既有 `test-ios` 门真实执行，不新增冗余门（若新增，只能加不减）。
- **基线文档**：更新 `.munk/baseline/domains/ios-shell/product.md`（依赖口径改为「唯一允许的依赖是本地 path package `PurePaceRunCore`；`AVFoundation` 仅限音频适配器文件」），并同步其 `ac-app-targets-and-frameworks` 表述；**不要**改 `ios-runcore` 域文档（RunCore 源码零改动，且该文件已 32.6KB 接近体积上限）。最近交付证明写真实命令摘要与用例数。
- **证据口径**：只报真实 `xcodebuild test` / `swift test` 用例数与 `check-*.sh` PASS 计数；结论措辞限「配置与调度契约通过」；真机项 `pending: 待人现场`。
