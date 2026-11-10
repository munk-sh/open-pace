# Domain: ios-audio-verification

`ios-device-verification` 的音频子域：用「UITests target 自带合成音源 + 正负对照」把「他路音频在播 → 播报 duck → 恢复」从「依赖系统 Music / 人耳」变成无人操作、可归因、可重复的机器证据。核心裁决：音源默认 runner 自播（`AVAudioPlayer(.playback)` 循环），`--music-strategy=runner|app|none` 默认 `runner`；`duckRevoked` / `sessionDeactivated` 本域只做结构性观测、不做 pass/fail（`pending-classification: wi_intake_f76b858c0c2376f5`）；本域不改产品音频/播报语义。

## 范围

- **音源资产**：`scripts/gen-ios-test-audio.sh`（python3 标准库 `wave` + `struct` 合成、确定性、幂等、`--force` 才覆盖、`--help`、未知参数退出 2、零网络）与生成的 `ios/PurePaceUITests/Fixtures/runner-music-loop.wav`（短循环、≤200 KB、入库）。
- **UITests target 后台音频声明**：`ios/project.yml` 给 `PurePaceUITests` 配 `info.properties.UIBackgroundModes: [audio]`（生成 `ios/PurePaceUITests/Info.plist`）并把 wav 作为 UITests bundle 资源；pbxproj 一律 `xcodegen generate` 产物，禁手改；App target `ios/PurePace/Info.plist` 保持零 diff。
- **音源策略层**：`ios/PurePaceUITests/MusicSource.swift`（策略解析 + runner `AVAudioPlayer` 播放器 + 证据模型）：`runner|app|none`，默认 `runner`；`app` 用 `--music-bundle-id`（默认常量 `com.apple.Music`）启动第三方/系统 App；`none` 不产生任何音源；非法值回落 `runner` 并在证据里记 `invalidRequested`。
- **参数化**：`scripts/verify-ios-device-flow.sh` 新增 `--music-strategy=runner|app|none`（默认 runner）与 `--music-bundle-id <id>`，经 `TEST_RUNNER_MUSIC_STRATEGY` / `TEST_RUNNER_MUSIC_BUNDLE_ID` 传入测试 runner；`--phase=audio` 顺序跑两遍（runner 正例 + none 负对照），各自独立 result bundle / 证据子目录。
- **设备侧断言（audio 阶段）**：`DeviceFlowUITests.swift` 一用例 `testAudioKilometerBoundaryWithMusic` 观测 a) `isOtherAudioPlaying == true` 且可归因 runner 自播；b) `categoryOptions` 含 `duckOthers`；c) `duckRevoked` 只记录实测值；d) `sessionActivated == true`，`sessionDeactivated` 只记录实测值，并记录 `setActive(false)` 是否发生。
- **模拟器全量可跑**：`ios/PurePaceUITests/MusicSourceSelfCheckUITests.swift`（默认 UI 腿会跑、不被 DeviceFlow 跳过规则排除）在模拟器跑 runner/none 两遍，断言资产、UITests bundle `UIBackgroundModes`、默认策略、`AVAudioPlayer.isPlaying` 正负；模拟器无法观测的 app 侧语义写 `simulatorNotApplicable`。
- **静态门**：`scripts/check-ios-shell.sh` 把 App target `UIBackgroundModes` 断言收敛到 `PurePace` target 段，新增 UITests `UIBackgroundModes == [audio]`、wav 存在且 ≤200 KB、全仓无 `com.apple.MobileMusic`、App plist 仍 `[location,audio]` 的断言与负向自检；`code_gates` 仍 22 门。
- **文档口径**：`docs/device-assertion-matrix.md` 的「他路音频在播取值 / duck 应用与恢复」两行音源改标 runner 自播（无人操作）并补 Release 包机器复核口径；`docs/device-flow-usage.md`、`DeviceFlowUITests.swift` 注释同步改口径。

## 验收

### 音源资产与工程声明

- ac-audio-asset-committed: `ios/PurePaceUITests/Fixtures/runner-music-loop.wav` 存在、字节数 >0 且 ≤204800；`bash scripts/gen-ios-test-audio.sh --force` 重新生成后 sha256 与入库文件一致（可复现），脚本零网络、只依赖 python3 标准库。
- ac-audio-asset-registered: `xcodegen generate --spec ios/project.yml` 连跑两次 pbxproj 一致，且 `PurePaceUITests` target Resources 阶段包含该 wav；pbxproj 为生成产物（无手改痕迹）。
- ac-uitests-background-audio-only: `ios/project.yml` 的 `UIBackgroundModes` 只出现在 `PurePaceUITests` target 且值为 `[audio]`；`PurePace` target 仍为 `[location, audio]`。
- ac-product-plist-readback: 模拟器构建产物 `Debug-iphonesimulator/PurePace.app/Info.plist` 读回 `UIBackgroundModes == [location, audio]`；`ios/PurePace/Info.plist` sha256 与改动前一致（测试侧声明不得混进产品包）。
- ac-uitests-plist-readback: 构建产物 `PurePaceUITests-Runner.app/PlugIns/PurePaceUITests.xctest/Info.plist` 读回 `UIBackgroundModes` 含 `audio`；`MusicSourceSelfCheckUITests` 运行时用 `Bundle(for:).object(forInfoDictionaryKey: "UIBackgroundModes")` 再读回含 `audio`。
- ac-no-legacy-music-id: `git grep -n 'com\.apple\.MobileMusic'` 全仓零命中（代码、脚本、matrix、报告、注释）。
- ac-music-id-constant: 用例/单测断言目标音源 id 常量等于 `com.apple.Music`（常量断言），改动该常量即红；`app` 策略缺省 bundle id 取该常量。

### 参数化与策略

- ac-music-strategy-param: `scripts/verify-ios-device-flow.sh --help` 列出 `--music-strategy=runner|app|none` 与 `--music-bundle-id`；缺省解析为 `runner`；非法值退出 2；取值经 `TEST_RUNNER_MUSIC_STRATEGY` / `TEST_RUNNER_MUSIC_BUNDLE_ID` 传入 runner 并写入证据 JSON 的 `musicStrategy` 字段。
- ac-music-strategy-default-runner: 无参数（或仅 `--phase=audio`）时证据 `musicStrategy == "runner"`；`app` / `none` 分支存在且可显式选择，均非默认。
- ac-strategy-none-semantics: `--music-strategy=none` 时 runner 不创建播放器、`playerStarted == false`、`isPlaying == false`，证据如实记 `strategy=none`。

### 正负对照与归因（裁决 A）

- ac-negative-control: `--phase=audio` 同一条用例跑两遍：(i) runner 播音频、(ii) `--music-strategy=none`；断言 (i) `telemetry.announcements[].isOtherAudioPlaying == true` 且 (ii) 同字段 `== false`；任一侧缺失或不符即失败，两遍都落 runner 播放器状态日志（`isPlaying`、`currentTime`、起播/停止时刻、session active 状态）。
- ac-runner-attribution: runner 正例证据记录 `strategy=runner`、资产名/字节数/sha256、`playerStarted=true`、`isPlayingAtStart=true`、`playbackStartedAt < runStartedAt`、`currentTimeAtFinish > 0`；缺任一项则 `audio-other-audio-attributable` 判失败（不凭单一布尔通过）。
- ac-attribution-fail-closed: 正例 `isOtherAudioPlaying == true` 但 runner 证据缺失/未起播时判失败；负例 `isOtherAudioPlaying != false` 时判失败（不得因策略或字段缺失而空过）。

### 四断言与 not-applicable 口径（裁决 C/E）

- ac-duck-options: 设备 audio 阶段 `telemetry.announcements[].categoryOptions` 含 `duckOthers`，否则失败。
- ac-session-activated: `telemetry.announcements[].sessionActivated == true`，否则失败；同时落 `setActive(true)` 调用是否发生的证据。
- ac-duck-revoked-record-only: `duckRevoked` 只记录实测值（值 + 时间戳 + 结构化观测），本域不写 pass/fail 断言；证据标记 `pending-classification: wi_intake_f76b858c0c2376f5`。
- ac-session-deactivated-record-only: `sessionDeactivated` 只记录实测值（值 + 时间戳）并记录 `setActive(false)` 是否实际发生；本域不写 pass/fail 断言，标记 `pending-classification: wi_intake_f76b858c0c2376f5`。
- ac-not-applicable-never-green: 无音源场景（`strategy=none` 或 runner 未起播）下，`isOtherAudioPlaying` 归因、`duckOthers` 生效、`duckRevoked`、`sessionActivated/sessionDeactivated` 一律记 `not-applicable`（含原因），不得记 pass；任何「前置不成立而空过」按 `not-applicable` 落盘。
- ac-structural-observation: 上述字段的存在性/类型/实测值/时间戳先于任何语义结论落盘到 `announcements-*.json` 与 `audio-result.json`（或 `music-source.json`）。

### 模拟器与真机能力分层

- ac-simulator-selfcheck-green: `bash scripts/test-ios.sh`（全量，UI 腿含 `MusicSourceSelfCheckUITests`）在模拟器退出 0；该用例跑 runner/none 两遍并断言资产存在且 ≤200 KB、UITests bundle `UIBackgroundModes` 含 `audio`、默认策略为 runner、正例 `AVAudioPlayer.isPlaying == true`、负例 `isPlaying == false`。
- ac-simulator-honest-cap: 模拟器附件/产物显式写 `simulatorNotApplicable`（至少含 app 侧 `isOtherAudioPlaying` 归因、`duckOthers` 实际 duck 语义、`duckRevoked`、`sessionDeactivated`），原因写「模拟器音频栈无真实他路音频/duck，真机可跑」；模拟器不得把这些项断言为 true 或记 pass。
- ac-device-only-assertions: 设备 audio 阶段承载 app 侧 a–d 观测；报告逐项写明「模拟器可断言 / 仅真机可断言」，不得伪绿。

### 静态门与文档

- ac-static-gate-audio: `bash scripts/check-ios-shell.sh` 退出 0；新增断言覆盖 UITests `UIBackgroundModes == [audio]`、wav 存在且 ≤200 KB、全仓无 `com.apple.MobileMusic`、App 构建产物 plist `[location,audio]`，且每类至少 1 条负向自检（临时副本违规必报错）。
- ac-static-gate-scope: 原 App target `UIBackgroundModes == [location,audio]` 断言改为按 target 作用域解析，新增 UITests 声明不会让该断言误红或误绿。
- ac-gates-unchanged: `.munk/code-gates.json` 仍为 22 门、id/command 语义不变；`check-ios-scripts.sh` / `check-ios-release.sh` 门数断言不改；不新增门、不新增 timeout、无 `continue-on-error`。
- ac-script-contract: `scripts/gen-ios-test-audio.sh` 含 `set -euo pipefail`、`--help`、未知参数退出 2、二次运行无 diff、零网络；`bash -n` 与 `scripts/check-shell-expansion.sh` 通过。
- ac-matrix-rows-updated: `docs/device-assertion-matrix.md` 的「他路音频在播取值」「duck 应用与恢复」两行音源标为 runner 自播（无人操作），取值路径含 `audio-result.json` / `music-source.json` 的 runner 字段与 `announcements-*.json` 同名字段，并写明 Debug UI-test 构建可断言 / Release 候选包只能人耳。
- ac-matrix-release-review: 矩阵写明 Release 包机器复核口径：`sessionDeactivated` 须与实际 `setActive(false)` 调用成对（桩或日志证明）、`categoryOptions` 须含 `duckOthers`、`duckRevoked` 只判「与是否真发生 duck 一致」而非单看布尔；本域不跑真机。
- ac-docs-no-system-music: `docs/device-flow-usage.md` 与 `DeviceFlowUITests.swift` 注释不再把「起系统 Music」当默认路径，写明策略参数与默认 runner；`com.apple.Music` 只出现在 `app` 策略说明与常量断言中。
- ac-report-honest: 交付回执写明音源策略默认值、`isOtherAudioPlaying` 归因证据形式（含负对照）、模拟器与真机各能断言到哪一项、`duckRevoked` / `sessionDeactivated` 的实测值与 `pending-classification` 状态（不得写 pass/fail 结论）。

### 边界

- ac-no-product-code-diff: `git diff --name-only` 不含 `ios/PurePace/**`（`Info.plist` 含）、`ios/Core/**`、`ios/RunCore/**`、`.munk/code-gates.json`、`.github/workflows/**`；`AnnouncementSpeaker.swift`、`AudioSessionAdapter.swift`、`RunTelemetry.swift`、`RunSessionViewModel.swift` 零 diff。
- ac-no-device-run: 本域不排真机、不装包、不出 Release 候选包、不改 Bundle ID、不动 workflow 600s 预算、不新增 CI 腿；真机能力只交脚本与用例。

## 非目标

- 不修产品 `AudioSession` / `AnnouncementSpeaker` / `CoreLocation` 业务语义；`duckRevoked` / `sessionDeactivated` 的产品缺陷由 `wi_intake_f76b858c0c2376f5` 定性后单独修，本域不写它们的 pass/fail 断言、不降级、不 `continue-on-error`。
- 不依赖系统 Music 或任何第三方音乐 App 作为默认音源；不再向人要订阅/曲库；不网络下载音频资产。
- 不提交大体积二进制（音频 ≤200 KB）；不引入第三方运行时依赖、不新增跨端框架。
- 不做真机排期、候选包构建、Release 发布、CI 拓扑变更；不改 Android 侧。
- 不改既有单测/UI 用例语义（`RunFlowUITests` 的 duckOthers/otherAudioPlaying 断言保持原样）。

## 实现约束

- **可写文件锚点**：`ios/PurePaceUITests/`（`DeviceFlowUITests.swift`、新增 `MusicSource*.swift`、`Info.plist`、`Fixtures/runner-music-loop.wav`）、`ios/project.yml`、`ios/PurePace.xcodeproj/project.pbxproj`（仅生成物）、`scripts/gen-ios-test-audio.sh`（新增）、`scripts/verify-ios-device-flow.sh`、`scripts/check-ios-shell.sh`、`docs/device-assertion-matrix.md`、`docs/device-flow-usage.md`；其余路径禁改。
- **裁决 E 优先**：`duckRevoked` / `sessionDeactivated` 只做结构性观测（字段存在、类型、实测值、时间戳、`setActive(false)` 调用证据）并标 `pending-classification`；`duckOthers`（配置项）与 `sessionActivated` 可断言 true。
- **正负对照落地**：`--phase=audio` 内顺序跑 `runner` 与 `none` 两遍（同用例 `testAudioKilometerBoundaryWithMusic`），各自 `DeviceFlow-audio-runner.xcresult` / `DeviceFlow-audio-none.xcresult` 与证据子目录；对比检查 `audio-negative-control` 要求 true/false 两侧齐备。
- **策略传递**：脚本导出 `TEST_RUNNER_MUSIC_STRATEGY` / `TEST_RUNNER_MUSIC_BUNDLE_ID`（同时导出无前缀同名变量兜底）；用例按 `ProcessInfo.environment` 读取，缺省 `runner`；`app` 分支保留 `XCUIApplication(bundleIdentifier:)` 但非默认，起播失败如实记 false。
- **静态门作用域**：`check-ios-shell.sh` 的 `UIBackgroundModes` awk 解析只取 `PurePace:` target 段；新增 UITests 段断言 + 资产/旧 id 断言 + 负向自检；`INFO_PLIST_SHA256` 常量与 App plist 零 diff 断言保留。
- **构建产物读回**：模拟器 UI 腿后从 `.build/ios/Build/Products/Debug-iphonesimulator` 用 plistlib 读 `.app/Info.plist` 与 `PurePaceUITests-Runner.app/PlugIns/PurePaceUITests.xctest/Info.plist`；XCTest 内再用 `Bundle(for:)` 做运行时读回。
- **资产生成**：wav 用 python3 `wave` + `struct` 合成（2 s / 22050 Hz / 单声道 16-bit ≈ 88 KB），默认仅在缺失时生成，`--force` 才覆盖；打印 sha256 与字节数，超 200 KB 非零退出。
- **口径**：模拟器只证明 runner 侧播放器与 bundle 声明；app 侧 `isOtherAudioPlaying` / duck 语义仅真机可断言，证据写 `simulatorNotApplicable`，不伪绿；`none` 场景一律 `not-applicable`，不记 pass。
- **门禁**：`code_gates` 全绿（22 门不变）；新增脚本须满足 `--help` / 未知参数契约与 shell 展开检查；不写「真机已验证」。

## 最近交付证明

- workItemId: wi_intake_222ccb141ff911f4（2026-11-10，pass）
- 交付：`scripts/gen-ios-test-audio.sh` + `ios/PurePaceUITests/Fixtures/runner-music-loop.wav`（88244 B，python3 标准库确定性合成、`--force` 可复现）；`ios/project.yml` 给 `PurePaceUITests` 配 `info.properties.UIBackgroundModes: [audio]` 并把 wav 登记为测试 bundle 资源（pbxproj 由 xcodegen 生成），App `Info.plist` 零 diff；新增 `MusicSource.swift`（`runner|app|none` 策略解析、默认 runner、`AVAudioPlayer(.playback)` 循环、证据模型，`com.apple.Music` 为 `app` 缺省常量）与 `MusicSourceSelfCheckUITests.swift`（模拟器 runner/none 两遍自证，`simulatorNotApplicable` 显式落盘）；`verify-ios-device-flow.sh` 增 `--music-strategy` / `--music-bundle-id`，`--phase=audio` 跑 runner 正例 + none 负对照两遍并各自归档；`DeviceFlowUITests.swift` 落 a–d 观测（`duckRevoked` / `sessionDeactivated` 仅记录 + `pending-classification`）。
- 实测：`code_gates` 22 门全绿（含 `generated plist 读回` 与 `check-ios-shell.sh` 新增块：UITests `UIBackgroundModes == [audio]`、wav 存在且 ≤200 KB、全仓无 `com.apple.MobileMusic`、App plist `[location,audio]` 断言 + 负向自检；App 断言已按 target 作用域解析，不再被 UITests 声明误红）。诚实边界：门内 `test-ios` 为 `--unit-only`，`MusicSourceSelfCheckUITests` 的模拟器 runner/none 两遍未在本次门禁腿内执行，UI 腿需 `bash scripts/test-ios.sh` 全量另跑。
- 边界：`ios/PurePace/**`（含 `Info.plist`）、`ios/Core/**`、`ios/RunCore/**`、`.munk/code-gates.json`、`.github/workflows/**` 零 diff；`AnnouncementSpeaker.swift` / `AudioSessionAdapter.swift` / `RunTelemetry.swift` / `RunSessionViewModel.swift` 零 diff；真机 audio 阶段实际取值与 `duckRevoked` / `sessionDeactivated` 定性仍为 `pending: 待人现场` + `pending-classification: wi_intake_f76b858c0c2376f5`，本域不宣称「真机已验证」。
