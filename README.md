# PurePace

没人打扰你的跑步计时器与热量记录本：无账号、无广告、无社交，数据只留在本机。

当前仓库处于**阶段 1：工程骨架初始化**，只有协作基线（版本真源、目录约定、测试金字塔、skill 路由）与门禁，尚无业务功能实现。

## 冻结技术栈

| 层 | 选择 |
|---|---|
| iOS | SwiftUI + XCTest/XCUITest，Xcode 26.3 / Swift 6.2 / deployment target iOS 17.0，仅系统框架，无第三方运行时依赖 |
| iOS 工程生成 | XcodeGen 从 `ios/project.yml` 生成；禁止手写 `project.pbxproj` |
| iOS 可测核心 | SwiftPM package `ios/Core`（`swift test` 跑 L1 纯逻辑测试） |
| Android | Gradle wrapper + Jetpack Compose，minSdk 26 / compileSdk 36 / JDK 21；applicationId 集中定义在一处 gradle property |
| Android 测试 | JUnit JVM 单测 + Robolectric 或 Compose UI test |
| Shared | GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql`，只放数据契约 |

禁止引入 RN / Flutter / CMP 等跨端框架。技术栈与目录的分层约定、测试金字塔细则见 [`AGENTS.md`](./AGENTS.md)。

## 版本

版本号的唯一真源是仓库根 [`VERSION`](./VERSION) 文件；README、构建脚本与工程配置一律不写死版本号，需要时通过唯一入口读取：

```bash
bash scripts/version.sh
bash scripts/version.sh --tools
```

`--tools` 在版本号之外追加 Xcode / Swift / JDK / Gradle 版本摘要；工具缺失时该行显式标注「未就绪」，不伪造版本。

## 构建与测试入口

所有入口都在 `scripts/` 下，统一 bash 实现（`set -euo pipefail`、幂等、支持 `--help`、路径以仓库根为基准）：

| 用途 | 入口 | 状态 |
|---|---|---|
| 读取版本号 | `bash scripts/version.sh` | 已就绪 |
| 读取版本号与工具链摘要 | `bash scripts/version.sh --tools` | 已就绪（缺失工具显式标注未就绪） |
| 仓库基线结构断言 | `bash scripts/check-baseline.sh` | 已就绪 |
| iOS 脚本契约断言 | `bash scripts/check-ios-scripts.sh` | 已就绪 |
| iOS 分发归档与导出 | `bash scripts/archive-ios.sh` | 已就绪；`DRY_RUN=1` 脱敏预演，产物仓外并输出 sha256 |
| iOS 分发静态门 | `bash scripts/check-ios-release.sh` | 已就绪；校验归档脚本契约、脱敏、门禁接入与 Runbook |
| iOS 构建 | `bash scripts/build-ios.sh` | 已就绪；无 `ios/PurePace.xcodeproj` 时输出 `blocked:` 并降级 `swift build` |
| iOS 测试 | `bash scripts/test-ios.sh` | 已就绪；无 `ios/PurePace.xcodeproj` 时输出 `blocked:` 并降级 `swift test` |
| Android 构建 | `bash scripts/build-android.sh` | 已就绪；真实执行 `assembleDebug` 并校验非空 APK 产物 |
| Android 测试 | `bash scripts/test-android.sh` | 已就绪；真实执行 `testDebugUnitTest`，区分纯 JVM 与 Robolectric/Compose 两类用例各 ≥1 |
| Android 脚本与结构断言 | `bash scripts/check-android.sh` | 已就绪；含 applicationId 单点、SDK/JDK、版本派生、wrapper 与门禁完整性断言 |

门禁定义在 [`.munk/code-gates.json`](./.munk/code-gates.json)：含 `lint` / `lint-baseline` / `lint-ios-core` / `lint-ios-scripts` / `lint-ios-shell` / `lint-android` / `build-ios-core` / `build-ios` / `build-android` / `test-ios-core` / `test-ios` / `test-android` / `test` / `check-shared`；`test` 真实执行 `scripts/check-baseline.sh`，iOS build/test 在工程不可用时显式 `blocked:` 并降级到 `ios/Core` 的 SwiftPM 命令，Android build/test 经统一脚本真实执行 `assembleDebug` / `testDebugUnitTest`。
