# AGENTS.md

PurePace 仓库协作基线（薄）。只写事实与约定，教程式长文不进本文件。

## 技术栈与核心库（冻结）

| 层 | 选择 | 约束 |
|---|---|---|
| iOS | SwiftUI + XCTest/XCUITest | Xcode 26.3 / Swift 6.2 / deployment target iOS 17.0；**仅系统框架，禁止第三方运行时依赖** |
| iOS 工程生成 | XcodeGen | 唯一真源是 `ios/project.yml`；`.xcodeproj` 由 XcodeGen 生成后入库，**禁止手写 `project.pbxproj`** |
| iOS 可测核心 | SwiftPM package `ios/Core` | 只放不依赖模拟器的纯逻辑/基础设施，承载 L1 测试；也是 xcodegen 缺失时的退路（`swift build` / `swift test`） |
| Android | Gradle wrapper + Jetpack Compose | wrapper 固定版本，不依赖系统 gradle；minSdk 26 / compileSdk 36 / JDK 21；applicationId 暂定 `com.chaxiu.purepace`，只在一处 gradle property 定义 |
| Android 测试 | JUnit JVM 单测 + Robolectric 或 Compose UI test | 优先无需启动模拟器、CI 友好的方案 |
| Shared | GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql` | 只放数据契约与静态样例，不放业务逻辑 |
| 版本 | 根 `VERSION` 单一真源 + `scripts/version.sh` 读取入口 | README、脚本、工程配置一律不得写死版本号 |

禁止 RN / Flutter / CMP 等跨端框架。

## 目录约定

- `ios/project.yml`：XcodeGen 唯一真源；`ios/PurePace.xcodeproj` 为生成产物（由 iOS 骨架子项落地）。
- `ios/PurePace/`：App 源码（占位页，不含业务实现）；`ios/PurePaceTests/`：XCTest 单测 target；`ios/PurePaceUITests/`：XCUITest target。
- `ios/Core/`：SwiftPM package（`Package.swift` + `Sources/` + `Tests/`），L1 纯逻辑测试与 `swift test` 落点。
- `android/`：Gradle wrapper + `app/` module + Compose 占位页；`android/app/src/test/` 放 JVM JUnit 单测。
- `shared/`：`fixtures/`（GPX/TCX）、`strings/`、`schema.sql`、`fixtures/README.md`；不写解析业务代码。
- `scripts/`：bash 脚本，统一 `set -euo pipefail`、幂等、支持 `--help`、路径以仓库根为基准。
- `.agents/skills/`：官方 skill 本地安装目录（仓库内，禁止 `-g`）；路由表见下节。
- `.munk/code-gates.json`：门禁定义，`command` 为单一 argv；根 `VERSION` 与 `README.md` 为版本真源与入口说明。
- 分层红线：平台代码不引用另一平台代码；`shared/` 只承载数据契约/夹具；UI 占位页不得依赖内置样例数据；示例数据只许进 XCTest fixture 与 `shared/fixtures`。

## 测试金字塔

**L1 纯逻辑单测**（无外部 IO、最快、覆盖 happy path / 边界 / 错误路径）

- iOS：`ios/Core/Tests`，用 `swift test` 跑（该层不依赖模拟器）。
- Android：`android/app/src/test`，JVM JUnit 单测，用 `./gradlew testDebugUnitTest` 跑。

**L2 契约与进程内集成测试**（模拟器/设备内 UI 与集成）

- iOS：`ios/PurePaceUITests` 的 XCUITest，在模拟器 destination 上跑。
- Android：Robolectric 或 Compose UI test，放在能被 `testDebugUnitTest` 或 CI 取到的位置。

**单跑（只跑一个用例/一个 target）**

```bash
# iOS 纯逻辑单跑
swift test --filter CoreTests.SomeTest/testCase
# 或在 ios/ 工程内单跑某个测试 target / 用例
xcodebuild test -only-testing:PurePaceTests/SomeTests/testCase -scheme PurePace -destination "platform=iOS Simulator,name=iPhone 16"
# Android 单跑某个测试类/方法
./gradlew testDebugUnitTest --tests "com.chaxiu.purepace.SomeTest"
```

**全跑**

```bash
# 脚本入口（iOS/Android 骨架子项补齐后可用；当前尚未存在）
bash scripts/test-ios.sh
bash scripts/test-android.sh
# 仅本仓协作基线结构断言（现在即可运行）
bash scripts/check-baseline.sh
```

真机不做 agent 验收：锁屏定位、音频实听、定位授权等真机项一律 `pending: 待人现场`，交付后由人按 `docs/device-manual-acceptance.md` 手测；agent 与 CI 只跑 L1 单测与模拟器 UI 腿。

**CI 定位约定**：CI 的 UI 测试禁止依赖隐藏式 simulator 定位投递；UI 测试用 launch-arg 门控（`-uiTestLocation`，仅 DEBUG）的确定性测试源，真实 CoreLocation 覆盖放 `scripts/verify-ios-sim-runtime.sh`（模拟器）。

## 测试稳定性约定（iOS UI 腿）

- **禁止墙钟依赖断言**：断言期望不得由「跑了多久」决定（tick 数 / 墙钟累计）。会随运行时长漂移的内容（距离、分段行数、布局平衡）必须用 canonical 启动输入锁定，例如 `-uiTestLocation` / `-uiTestLocationTargetMeters`；同一用例在慢机器上不得改变期望值。
- **导航/重启后必须状态判据**：`tap` 前先等状态（Tab 栏存在 → 目标按钮 `exists && isHittable`），`tap` 后以目标页根/关键元素出现作为页面就绪判据；禁止固定 `sleep` / `Thread.sleep`。tap 被吞或页面未就绪时允许按状态重试 ≤2 次，单次 timeout 与断言强度不变；失败路径必须把可及树/截图与持久化探针写入 xcresult，用于区分「点击被吞 / 页面未就绪」与「数据未持久化」。
- **单次 xcodebuild ≤600s 分段约定**：`IOS_XCODEBUILD_TIMEOUT=600` 是单次调用硬上界。`scripts/test-ios.sh` 的 UI 腿按目标拆成两段 `xcodebuild test-without-building`（RunFlow 6 条 / 取证+AX5+音频 7 条），每段仍 ≤600s。**拆分≠放宽**：阈值、用例数、断言强度、重试策略与 `-only-testing` 覆盖范围都不得减少，禁止 `continue-on-error`、禁止删腿、禁止提高 timeout。

## Skill 路由（`.agents/skills/<name>`）

官方 skill 以 `npx skills add <owner/repo@skill>` 安装到仓库内 `.agents/skills/`（禁止 `-g` / `--global`）。路由表与磁盘内容必须双向一致；新增或删除 skill 时同步更新本表。

| 平台 | skill | 用途 |
|---|---|---|
| iOS | `.agents/skills/swiftui-pro` | SwiftUI 布局、状态、性能与 API 使用规范（`twostraws/swiftui-agent-skill@swiftui-pro`） |
| Android | `.agents/skills/android-cli` | Android 构建/测试与工程工具链（Gradle、SDK、模拟器）操作口径（`android/skills@android-cli`） |

修改本仓库前先读取对应平台的 skill；跨平台或通用改动同时参考两者。
