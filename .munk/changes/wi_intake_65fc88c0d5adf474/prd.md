# 产品 Bundle ID 迁移到 `sh.munk.purepace`

## Scope

一次性把产品标识从 `com.chaxiu.purepace` 迁移到人已定案的 `sh.munk.purepace`，不留旧值；只换标识，不改任何业务行为。

范围内（逐条按 `git grep -n 'com\.chaxiu\.purepace'` 命中处理）：

1. `ios/project.yml`：`PUREPACE_BUNDLE_ID` 改为 `sh.munk.purepace`（App / `PurePaceTests` / `PurePaceUITests` 三 target 的 `PRODUCT_BUNDLE_IDENTIFIER` 均从该变量派生，`$(PUREPACE_BUNDLE_ID)`、`.tests`、`.uitests`）。改完必须 `xcodegen generate` 重生成 `ios/PurePace.xcodeproj`，**禁止手改 pbxproj**（本地 xcodegen 2.46.0 已就绪）。
2. Info.plist：`ios/PurePace/Info.plist` 的 `CFBundleIdentifier` 是 `$(PRODUCT_BUNDLE_IDENTIFIER)` 占位，保持不动；`project.yml` 内无 bundle-id 类 `INFOPLIST_KEY_*`（仅 display name / launch screen / 朝向 / 定位用途说明），保持不动。
3. `scripts/**`：iOS 侧全部硬编码 bundle id 改为 `sh.munk.purepace`——`scripts/test-ios.sh`（安装/启动/容器/`simctl` 选择器）、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh`（含 usage 文案与 report 兜底字段）。
4. `ios/**` 测试代码：`ios/PurePaceUITests/RunFlowUITests.swift` 当前用默认 `XCUIApplication()`（无 bundle id 字面值），无需改；新增读回断言见验收。
5. 文档：`docs/release/testflight-runbook.md` 的「当前 bundle id」表述改为 `sh.munk.purepace`，并注明新 bundle 需在 App Store Connect 新建/更新 App 记录（人侧动作，不在仓库范围）。`README.md` 当前无命中，保持零命中。

**派生范围（本项必带，理由见下）**：Android 应用标识同步为 `sh.munk.purepace`。

- `android/gradle.properties` 单点 `PUREPACE_APPLICATION_ID=sh.munk.purepace`（AGENTS.md 原表述为「暂定 com.chaxiu.purepace」，产品最终标识已定案，Android 标识跟随同一产品标识）。
- `scripts/check-android.sh` 的 `ac-check-android-application-id` 期望字面值（3 处）、沙箱反例注入（1 处）、沙箱夹具测试 XML/包名（4 处）同步更新。
- 理由：验收要求 `scripts/` 下旧值零命中，而 `scripts/check-android.sh` 有 10 处旧值字面值；若保留 Android 旧标识则该验收无法自洽。此改动为 1 行 property + 门断言字面值，业务行为零变化，回退成本 1 行。
- `android/app/src/**` 与 `AndroidManifest.xml` 不动：Kotlin 包名是 `dev.purepace`，manifest 用全限定 `dev.purepace.MainActivity`，`namespace` 随 property 派生，改 applicationId 不影响类解析。

## Acceptance Criteria

- ac-project-yml-single-source: `ios/project.yml` 中 bundle id 字面值仅一处 `PUREPACE_BUNDLE_ID: sh.munk.purepace`；App / Tests / UITests 三 target 的 `PRODUCT_BUNDLE_IDENTIFIER` 分别为 `$(PUREPACE_BUNDLE_ID)`、`$(PUREPACE_BUNDLE_ID).tests`、`$(PUREPACE_BUNDLE_ID).uitests`，无第二个完整 id 字面值。
- ac-pbxproj-generated: `ios/PurePace.xcodeproj/project.pbxproj` 中 `PUREPACE_BUNDLE_ID` 两处为 `sh.munk.purepace`，且该文件 diff 只可能是 `xcodegen generate` 产物；`bash scripts/check-ios-shell.sh` 的「连续两次生成结果一致」断言仍通过。
- ac-bundle-id-readback: `bash scripts/test-ios.sh --unit-only` 中新增/更新的 hosted 单测断言 `Bundle.main.bundleIdentifier == "sh.munk.purepace"`（即构建产物 Info.plist 的 `CFBundleIdentifier` 读回值），失败信息需打印实际值。
- ac-background-modes-readback: 同一读回单测断言 `Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]` 的数组同时包含 `location` 与 `audio`（既有 `testInfoPlistBackgroundModesContainsLocation` 保留 location 断言并补 audio，或新增对称用例）。
- ac-signing-unchanged: `ios/project.yml` 仍含 `CODE_SIGNING_ALLOWED: NO`；本次 diff 中不出现 `DEVELOPMENT_TEAM`、`PROVISIONING_PROFILE`、证书/签名身份相关新增行。
- ac-ios-scripts-new-id: `scripts/test-ios.sh`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh` 中所有 bundle id 字面值为 `sh.munk.purepace`，且各脚本 `--help` 退出 0、`bash -n` 通过。
- ac-android-appid-aligned: `android/gradle.properties` 含唯一 `PUREPACE_APPLICATION_ID=sh.munk.purepace`；`bash scripts/check-android.sh` 的 `ac-check-android-application-id` 及正负反例自检通过；`bash scripts/build-android.sh` 与 `bash scripts/test-android.sh` 通过。
- ac-no-business-code-change: `ios/PurePace/**` 与 `android/app/src/**` 源码 diff 为空；唯一 Swift 源码改动在 `ios/PurePaceTests/RunLocationSourceTests.swift`（新增/扩展读回断言）。
- ac-legacy-id-grep-zero: `git grep -n 'com\.chaxiu\.purepace' -- ios scripts README.md docs` 在豁免清单外零命中；豁免清单：`scripts/verify-ios-device-flow.sh`、`docs/device-assertion-matrix.md`（用户冻结的 device 取证套件）、`docs/evidence/**`（历史证据）。
- ac-gates-green: 本地 `code_gates` 全绿（lint / static / shell / swift build|test / PurePaceTests 单测 / Android build+test），IO 门真实执行、不跳过；重 UI E2E 不在本地阻断，交 `.github/workflows/ios.yml`。

## Non-Goals

- 不改签名与分发配置：不写 `DEVELOPMENT_TEAM` / 证书 / provisioning profile，不改 `CODE_SIGNING_ALLOWED: NO`。
- 不创建/变更 App Store Connect 记录、不安装到真机；仅文档提示「新 bundle 需新建/更新记录」。
- 不改 `.github/workflows/**`（ios.yml / android.yml 均不动）。
- 不改 device 取证套件：`ios/PurePaceUITests/DeviceFlowUITests.swift`、`scripts/verify-ios-device-flow.sh`、`docs/device-assertion-matrix.md`、`docs/device-flow-usage.md`、`iOS/PurePaceUITests/Info.plist`、`runner-audio.m4a`（该套件按用户要求冻结；如与 main 现状不符见「事实校正」）。
- 不 merge / rebase / cherry-pick 任何分支；本 worktree 只从 main 拉出。
- 不改历史证据：`docs/evidence/**`、`artifacts/**` 内记录的当时构建/包 Info.plist 保持原样，不改写历史事实。
- 不改 `.munk/**`（baseline 文档、历史 changes 的 prd.md 中旧值命中）。
- 不做业务逻辑调整：定位、音频、持久化、UI 文案、GPX 导出等行为零变化；不做顺手的重构与格式化。
- 不新增 gate 层级、不改测试金字塔分工；只在既有门脚本内更新期望字面值。

## Implementation Constraints

- 单一真源：iOS 只改 `ios/project.yml` 的 `PUREPACE_BUNDLE_ID` 后 `xcodegen generate`；Android 只改 `android/gradle.properties` 的 `PUREPACE_APPLICATION_ID`。
- 子 target id 必须继续由变量派生（`.tests` / `.uitests`），不得写死 `sh.munk.purepace.tests`。
- 读回断言落点：`ios/PurePaceTests/RunLocationSourceTests.swift`（同文件已有 `Bundle.main` 读回 `UIBackgroundModes` 的先例，hosted 单测下 `Bundle.main` 即 App 产物）；新增用例命名建议 `testInfoPlistBundleIdentifierIsFinalProductId`，并在既有背景模式用例中补 `audio` 断言。
- `scripts/check-android.sh` 只改字面值（期望值 + 沙箱反例 + 夹具包名/XML 名），不改断言结构、不改 `--self-test` 逻辑。
- 版本继续只来自根 `VERSION`；本次不触碰版本号与 `MARKETING_VERSION`。
- 提交前自检顺序：`xcodegen generate` → `git diff -- ios/PurePace.xcodeproj` 只应出现 bundle id 两行 → 逐门跑 `code_gates` → `git grep -n 'com\.chaxiu\.purepace' -- ios scripts README.md docs` 取前后命中数。
- 历史证据类文档如需提示，仅在 `docs/release/testflight-runbook.md` 加一行「历史记录，当前值为 sh.munk.purepace」，不得改旧构建记录。
- 预算纪律：≤10M token、≤90 分钟；超时即停手出回执，不做长会话自查补绿。

## 事实校正（Intake 核实，供人确认）

1. device 取证套件几个文件并非只在 wip：`docs/device-assertion-matrix.md`（2 处旧值）与 `scripts/verify-ios-device-flow.sh`（2 处旧值）**已存在于 main**，`ios/PurePaceUITests/DeviceFlowUITests.swift` 亦已入库（已由 `a4274b4` 在 ios.yml 默认 UI 腿排除）。本项按「不动」处理并列入 grep 豁免；若希望它们同步新 bundle id，请另开 WorkItem（它们不在本地权威门内，不改不会让 CI 变红）。
2. `README.md` 当前对旧 bundle id 零命中，因此「README 限改」为保持零命中，无实际改写。
3. 新 bundle id 落地后，App Store Connect 里旧 `com.chaxiu.purepace` 记录不再对应当前构建，需人侧新建/更新记录后才谈 TestFlight；仓库内只在 runbook 提示，不代做。

## 风险

- Android `applicationId` 同步改名会让已安装的旧包与新包成为两个应用（设备上会有两份），且需对应新的 Play Console 记录；若人侧不希望现在动 Android，可只回退 `android/gradle.properties` 一行并同时把 `scripts/check-android.sh` 的期望值改回。
- 测试断言依赖 hosted 单测宿主 `Bundle.main` 指向 App 产物（既有 `UIBackgroundModes` 用例已证明该前提成立）；若执行器改为非 hosted 会让读回断言失真，届时改为读 `xcodebuild -showBuildSettings` 或产物 plist 兜底。
