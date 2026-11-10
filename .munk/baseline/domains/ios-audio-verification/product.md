# Domain: ios-audio-verification

`ios-device-verification` 的音频子域：把「他路音频在播 → 播报 duck → 恢复」从「依赖系统 Music / 人耳」变成可归因、可重复的机器证据。V1 门已从「Debug 构建 + `-uiTestLocation`」升级为「最终 Release 候选包 + `-releaseDeterministicLocation km-crossing` + 固定三遍 `app`→`runner`→`none`」，一条 `device-run --phase=audio` 出全证据。核心裁决：`runner` 遍用 UITests target 自带合成音源（`AVAudioPlayer(.playback)` 循环），`app` 遍驱动系统 Music 并落曲目元数据，`none` 遍做负对照；`duckRevoked` / `sessionDeactivated` 只做结构性观测、不做 pass/fail（`pending-classification: wi_intake_f76b858c0c2376f5`）；本域不改产品音频/播报语义。

## 范围

- **音源资产**：`scripts/gen-ios-test-audio.sh`（python3 标准库 `wave` + `struct` 合成、确定性、幂等、`--force` 才覆盖、`--help`、未知参数退出 2、零网络）与生成的 `ios/PurePaceUITests/Fixtures/runner-music-loop.wav`（短循环、≤200 KB、入库）。
- **UITests target 后台音频声明**：`ios/project.yml` 给 `PurePaceUITests` 配 `info.properties.UIBackgroundModes: [audio]`（生成 `ios/PurePaceUITests/Info.plist`）并把 wav 作为 UITests bundle 资源；pbxproj 一律 `xcodegen generate` 产物，禁手改；App target `ios/PurePace/Info.plist` 保持零 diff。
- **音源策略层**：`ios/PurePaceUITests/MusicSource.swift`（策略解析 + runner `AVAudioPlayer` 播放器 + 证据模型）：`runner|app|none`，默认 `runner`；`app` 用 `--music-bundle-id`（默认常量 `com.apple.Music`）启动第三方/系统 App；`none` 不产生任何音源；非法值回落 `runner` 并在证据里记 `invalidRequested`。
- **参数化与构建配置**：`scripts/verify-ios-device-flow.sh` 支持 `--music-strategy=runner|app|none` 与 `--music-bundle-id <id>`（`--music-strategy` 只对 `background` 生效），新增 `--configuration Debug|Release`（audio 缺省 `Release`，其余 phase 缺省保持 `Release`）；`--phase=audio` 固定三遍 `app` → `runner` → `none`，各自独立 result bundle / 证据子目录 / `music-source.json`；Release 用 `-releaseDeterministicLocation km-crossing`（20 m/s 确定性源），Debug 仍用 `-uiTestLocation`，默认用户路径与 `ios/PurePace/**` 零改动。
- **候选包绑定**：audio 被驱动 App 必须来自 `--candidate`（或 `artifacts/candidates/PurePace-Release-*.zip` 唯一命中）解包的 `Payload/*.app`，经 build-for-testing 后替换产物或 `UITargetAppPath` 绑定；证据落 candidate zip sha256、候选 exec sha256、实际驱动 `.app` 路径与 exec sha256，两者一致才算候选包已验证；缺包/多义/结构不兼容在跑用例前 fail-closed。
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

### Release 候选包与构建配置

- ac-audio-default-release: `--phase=audio` 不带 `--configuration` 时 meta / report / 分析 JSON 的 `configuration` 均为 `Release`；`--configuration=Debug|Release` 合法，其余取值退出 2；`--phase=audit` 与 `--phase=background` 的默认配置不被本项改变。
- ac-audio-release-launch-args: Release 音频用例实际启动参数含 `-releaseDeterministicLocation`（值 `km-crossing`）且不含 `-uiTestLocation`；Debug 显式构建时仍用 `-uiTestLocation`；用例把实际 `launchArguments` 写入 `audio-result.json`，分析侧对 Release 缺该参数判 FAIL。
- ac-audio-no-debug-substitute: 显式 `--configuration=Debug` 的 audio 证据在 meta / report 标 `evidenceGrade=debug` 且注明「不可计入 V1 Release 门」；默认路径与 `device-run --phase=audio` 只接受 Release，不存在 Debug 或自产 Release 构建顶替候选包。
- ac-audio-candidate-bound: audio 证据记录 `candidatePath`、candidate zip sha256、候选 `.app` exec sha256（64 位 hex）与证据目录路径，并记录实际被驱动 App 的 `.app` 路径与 exec sha256；二者须一致，否则 FAIL（不得只记 zip sha 就宣称候选包已验证）。
- ac-audio-candidate-missing-fail-closed: 无 `--candidate` 且 `artifacts/candidates/PurePace-Release-*.zip` 缺失或多义时，audio 在任何用例启动前非 0 退出并写明原因。

### 参数化与策略

- ac-music-strategy-param: `scripts/verify-ios-device-flow.sh --help` 列出 `--music-strategy=runner|app|none` 与 `--music-bundle-id`；缺省解析为 `runner`；非法值退出 2；取值经 `TEST_RUNNER_MUSIC_STRATEGY` / `TEST_RUNNER_MUSIC_BUNDLE_ID` 传入 runner 并写入证据 JSON 的 `musicStrategy` 字段。
- ac-music-strategy-scope: `--music-strategy` 只对 `--phase=background` 生效；`--phase=audio` 显式传入时按固定三遍执行并在 meta 记 `musicStrategyIgnored`（不静默吞参数）。
- ac-strategy-none-semantics: `--music-strategy=none` 时 runner 不创建播放器、`playerStarted == false`、`isPlaying == false`，证据如实记 `strategy=none`。

### 正负对照与归因（裁决 A）

- ac-audio-triple-pass: 一次 `--phase=audio` 固定产出 `audio-app` / `audio-runner` / `audio-none` 三个独立证据子目录、result bundle、run JSON 与 `music-source.json`；三遍 `configuration` 同为 `Release`。
- ac-audio-app-track-metadata: `app` 遍驱动系统 Music（bundle id `com.apple.Music`）读到正在播放的本地曲目：证据含非空 `nowPlayingTitle`、可解析时长（`durationText` 匹配 `\d{1,2}:\d{2}` 或 `durationSeconds > 0`）、`isLocalFile ∈ {true,false,unknown}` 且带 `localFileBasis`，并附可及树 / 截图原始证据；读不到元数据判 FAIL（不得写空 `unknown` 空过）。
- ac-audio-none-negative: `none` 遍 `announcements[].isOtherAudioPlaying == false`，播报前快照时间戳与实际取样时刻成对；无音源场景只记 `not-applicable`，不因缺席判 pass。
- ac-runner-attribution: `runner` 遍 `announcements[].isOtherAudioPlaying == true` 且自播可归因证据齐全：`strategy=runner`、资产名/字节数/sha256、`playerStarted=true`、`isPlayingAtStart=true`、`playbackStartedAt < runStartedAt`、`currentTimeAtFinish > 0`；缺任一项则 `audio-other-audio-attributable` 判失败（不凭单一布尔通过）。
- ac-attribution-fail-closed: 正例 `isOtherAudioPlaying == true` 但 runner / app 归因证据缺失或未起播时判失败；负例 `isOtherAudioPlaying != false` 时判失败（不得因策略或字段缺失而空过）。

### 四断言与 not-applicable 口径（裁决 C/E）

- ac-duck-options: 设备 audio 阶段 `telemetry.announcements[].categoryOptions` 含 `duckOthers`，否则失败。
- ac-session-activated: `telemetry.announcements[].sessionActivated == true`，否则失败；同时落 `setActive(true)` 调用是否发生的证据。
- ac-duck-revoked-record-only: `duckRevoked` 只记录实测值（值 + 时间戳 + 结构化观测），本域不写 pass/fail 断言；证据标记 `pending-classification: wi_intake_f76b858c0c2376f5`。
- ac-session-deactivated-record-only: `sessionDeactivated` 只记录实测值（值 + 时间戳）并记录 `setActive(false)` 是否实际发生；本域不写 pass/fail 断言，标记 `pending-classification: wi_intake_f76b858c0c2376f5`。
- ac-audio-duck-pair: 每个 pass 的 `duckRevoked` / `sessionDeactivated` / `categoryOptions` 取自**同一条** `telemetry.announcements[]` 条目，并同时落该条目 `splitIndex`、`text`、`startedAt`、`finishedAt`、`sessionActivated`；三字段不得跨条目或跨 pass 拼接（`duckRevoked` / `sessionDeactivated` 只记实测布尔 + 时间戳 + `pending-classification: wi_intake_f76b858c0c2376f5`，不写 pass/fail）。
- ac-audio-km-trigger: `app` 与 `runner` 遍该条目 `splitIndex == 1` 且 `text` 含「第 1 公里」；Release 确定性源节奏下 `activeDuration` 落在 35–90s 窗口（`km-crossing` 为 20 m/s），证据注明节奏来源。
- ac-audio-announcements-structure: 每个 pass 的 `announcements-*.json` 与 `audio-result.json` 同时落播报条目、duck 应用/撤销上下文与 `music-source.json`；结构观测先于语义结论。
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

### 可运行性与诚实边界

- ac-one-command: 候选包存在、真机可达、系统 Music 已有本地曲目时，`bash scripts/device-run.sh --phase=audio`（或带 `--candidate <zip>`）一条命令跑完 audio 腿并 0 退出；证据目录同时含 Release 配置、曲目元数据、runner 正例、none 负对照、duck 三字段、候选 zip/exec sha256 与证据路径。
- ac-structural-fail-honest: 若「Release 候选包 + XCUITest runner」结构性不可行（自产 App 顶掉候选包且无法通过产品路径替换 / xctestrun 绑定），立即停止并写清失败项、已试路径与替代方案，不得用 Debug 或自产 Release 构建证据顶替，不得宣称候选包已验证。
- ac-gates-scope: 只跑受影响门（`lint` / `lint-ios-scripts` / `lint-ios-shell` / `lint-ios-release` / `check-shell-expansion` / `test-ios --unit-only` + `bash -n`），不重跑全量模拟器 UI 或真机门；不改 `.munk/code-gates.json`、不新增 CI 阻断腿。
- ac-no-app-source-diff: `git diff --name-only` 不含 `ios/PurePace/**`、`ios/Core/**`、`ios/RunCore/**`、`ios/project.yml`、`ios/PurePace.xcodeproj/project.pbxproj`、`.github/workflows/**`；`AudioSessionAdapter` / `AnnouncementSpeaker` / `RunTelemetry` / `RunSessionViewModel` 零 diff。

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

- **可写文件锚点**：`ios/PurePaceUITests/`（`DeviceFlowUITests.swift`、`MusicSource.swift`、`Info.plist`、`Fixtures/runner-music-loop.wav`）、`ios/project.yml`、`ios/PurePace.xcodeproj/project.pbxproj`（仅生成物）、`scripts/gen-ios-test-audio.sh`、`scripts/verify-ios-device-flow.sh`、`scripts/device-run.sh`、`scripts/check-ios-scripts.sh`、`scripts/check-ios-shell.sh`、`docs/device-assertion-matrix.md`、`docs/device-flow-usage.md`、`docs/device-scripts.md`；其余路径禁改。
- **裁决 E 优先**：`duckRevoked` / `sessionDeactivated` 只做结构性观测（字段存在、类型、实测值、时间戳、`setActive(false)` 调用证据）并标 `pending-classification`；`duckOthers`（配置项）与 `sessionActivated` 可断言 true。
- **三遍落地**：`--phase=audio` 固定 `app` → `runner` → `none`（同用例 `testAudioKilometerBoundaryWithMusic`），各自 result bundle 与证据子目录；`app`/`runner` 的 duck 三字段与 km 触发须取自同一条 `announcements[]` 条目。
- **候选包绑定**：build-for-testing 后用候选 `Payload/*.app` 替换产物（或 xctestrun `UITargetAppPath` 绑定），通过判据是「实际驱动 App exec sha256 == 候选 exec sha256」；bundle id / executable / 签名 / 架构不一致时替换前 fail-closed，不回退 Debug。
- **策略传递**：脚本导出 `TEST_RUNNER_MUSIC_STRATEGY` / `TEST_RUNNER_MUSIC_BUNDLE_ID`（同时导出无前缀同名变量兜底）；用例按 `ProcessInfo.environment` 读取；`--music-strategy` 只对 `background` 生效，audio 三遍固定并记 `musicStrategyIgnored`。
- **静态门作用域**：`check-ios-shell.sh` 的 `UIBackgroundModes` awk 解析只取 `PurePace:` target 段；新增 UITests 段断言 + 资产/旧 id 断言 + 负向自检；`INFO_PLIST_SHA256` 常量与 App plist 零 diff 断言保留。
- **构建产物读回**：模拟器 UI 腿后从 `.build/ios/Build/Products/Debug-iphonesimulator` 用 plistlib 读 `.app/Info.plist` 与 `PurePaceUITests-Runner.app/PlugIns/PurePaceUITests.xctest/Info.plist`；XCTest 内再用 `Bundle(for:)` 做运行时读回。
- **资产生成**：wav 用 python3 `wave` + `struct` 合成（2 s / 22050 Hz / 单声道 16-bit ≈ 88 KB），默认仅在缺失时生成，`--force` 才覆盖；打印 sha256 与字节数，超 200 KB 非零退出。
- **口径**：模拟器只证明 runner 侧播放器与 bundle 声明；app 侧 `isOtherAudioPlaying` / duck 语义仅真机可断言，证据写 `simulatorNotApplicable`，不伪绿；`none` 场景一律 `not-applicable`，不记 pass；Release 候选包证据与 Debug 证据分级（`evidenceGrade`）不得混用。
- **门禁**：`code_gates` 全绿（22 门不变）；`check-ios-scripts.sh` 增加 audio 契约断言（Release 默认 / launch-arg / 三遍 / 非法 configuration 退出 2 / 缺候选包 fail-closed）；不写「真机已验证」。

## 最近交付证明

- workItemId: wi_intake_a22d527eed9de808（2026-11-10，pass）
- 交付：`verify-ios-device-flow.sh` audio 分支默认 `Release` 并新增 `--configuration Debug|Release`；Release 用例注入 `-releaseDeterministicLocation km-crossing`（Debug 仍 `-uiTestLocation`）并把实际 `launchArguments` 落 `audio-result.json`；`--phase=audio` 固定 `app`→`runner`→`none` 三遍，`app` 遍驱动系统 Music 并落 `nowPlayingTitle` / 时长 / `isLocalFile`+`localFileBasis` / 可及树与截图；候选包绑定用候选 `Payload/*.app` 替换并校验实际驱动 exec sha256 与候选一致，缺包/多义/结构不兼容在跑用例前 fail-closed；duck 三字段与播报上下文取自同一条 `announcements[]`（`splitIndex`/`text`/时间戳成对）；km 窗口改 35–90s。
- 交付（续）：`device-run.sh` 新增 `audio` phase（`tcc` 之后、`record` 之前，10 step），`phase_audio` 只调 `verify-ios-device-flow.sh --phase=audio --configuration=Release` 并把证据收进 `artifacts/device-run/<candidateKey>/audio/` + `audio-step.json` 必备产物清单，缺项非 0；`check-ios-scripts.sh` 硬断言升到 10 step 并新增 audio 契约块；`docs/device-scripts.md`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md` 同步口径。
- 实测与边界：`code_gates` 22 门全绿；真实真机 audio 腿未在本次执行（无设备场、无候选包），`app` 曲目元数据与 `duckRevoked` / `sessionDeactivated` 实测值仍为 `pending: 待人现场` + `pending-classification: wi_intake_f76b858c0c2376f5`；`ios/PurePace/**`、`ios/Core/**`、`ios/RunCore/**`、`ios/project.yml`、`project.pbxproj`、`.github/workflows/**` 零 diff；不宣称「候选包已验证 / 真机已验证」。
