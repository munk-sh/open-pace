# Android Gradle + Jetpack Compose 空壳工程

> 本文件只覆盖 WorkSet 波 2 的 `key: android-skeleton` 子项。WorkSet 级叙事以 `.munk/work-set/overview.md` 为准，此处不复制；父级 PRD、`manifest.json` 与 `predecessors/wi_ws_6035fb0cde33a0a3` 为已落地事实。

## 范围

从零建立 `android/` 侧的**纯骨架**，让 Android 与已落地的 iOS 骨架对齐，可构建、可测试、可过门禁，不含任何跑步业务实现：

1. **Gradle wrapper**：`android/gradlew` + `android/gradlew.bat` + `gradle/wrapper/gradle-wrapper.jar` + `gradle/wrapper/gradle-wrapper.properties`，**固定一个 Gradle 版本并入库**，不依赖系统 gradle 9.6.1。wrapper 必须支持 `android/gradlew -p android <task>` 调用形态（`scripts/version.sh --tools` 已按此形态探测，不得改动该脚本去迁就工程）。
2. **工程配置**：`android/settings.gradle.kts`、`android/build.gradle.kts`、`android/app/build.gradle.kts`、`android/gradle.properties`、version catalog（可选，如需则 `gradle/libs.versions.toml`）。minSdk 26 / compileSdk 36 / JDK 21；applicationId 暂定 `com.chaxiu.purepace`；versionName 从仓库根 `VERSION` 读取。
3. **Compose 首屏占位**：单 Activity + `setContent`，界面只显示 `PurePace` 名称、一句 tagline、Tab 占位结构（Run / History / Log / Settings）。无视觉设计、无导航实现、无样例数据。
4. **测试**：`android/app/src/test/` 下 ≥1 个纯 JVM 单测 + ≥1 个 Robolectric 或 Compose UI test，二者都由 `testDebugUnitTest` 执行，**不启动模拟器/真机**。
5. **构建产物与卫生**：`assembleDebug` 产出 `android/app/build/outputs/apk/debug/*.apk`；`.gitignore` 覆盖 `android/.gradle/`、`android/app/build/`、`android/local.properties`、`android/build/` 等构建残留。
6. **门禁（本项范围内允许追加）**：可在 `.munk/code-gates.json` 追加本项真实可执行的 `build-android` / `test-android` 门（单一 argv），不得删除、放宽或改写既有门。

## 验收

- ac-wrapper-pinned-and-committed: `android/gradlew` 存在且可执行，`android/gradle/wrapper/gradle-wrapper.jar` 为非空真实 jar，`gradle-wrapper.properties` 的 `distributionUrl` 指向一个固定版本（非 `latest`/`+`/`SNAPSHOT`）；`bash android/gradlew -p android --version` 退出码 0 且输出的 Gradle 版本等于 `distributionUrl` 中的版本（证明不依赖系统 gradle）。
- ac-assemble-debug-apk: `bash android/gradlew -p android assembleDebug` 退出码 0，且 `android/app/build/outputs/apk/debug/` 下存在 ≥1 个非空 `*.apk`。
- ac-unit-tests-under-testdebugunittest: `bash android/gradlew -p android testDebugUnitTest` 退出码 0；`android/app/build/test-results/testDebugUnitTest/*.xml` 中累计 `tests` ≥ 2、`failures` 与 `errors` 均为 0，且至少 1 个来自纯 JVM 单测类、至少 1 个来自 Robolectric/Compose UI 测试类（XML `classname` 可区分）。
- ac-tests-no-emulator: 验收链路只使用 `testDebugUnitTest`，不需要 `connectedAndroidTest`、模拟器或真机；仓库无 `connectedAndroidTest` 相关必跑配置。
- ac-min-sdk-26: 构建产物的 `android/app/build/intermediates/merged_manifest/debug/**/AndroidManifest.xml`（或等价的合并 manifest）中 `minSdkVersion` 为 26，且 `android/app/build/outputs/apk/debug/output-metadata.json` 的 `minSdkVersion` 为 26。
- ac-compile-sdk-36: `android/app/build.gradle.kts`（或统一版本目录）声明 `compileSdk = 36`，构建在本机已安装的 android-36 platform 上真实完成（不是被注释/覆盖的声明）。
- ac-jdk-21: `android/app/build.gradle.kts` 声明 Java 21 编译目标（`compileOptions` + Kotlin `jvmTarget`/`jvmToolchain(21)`），构建在 JDK 21 下成功；工程中不出现写死的 JDK 绝对路径（`local.properties` 不提交、不含 `org.gradle.java.home`）。
- ac-application-id-single-source: 字面值 `com.chaxiu.purepace` 在 `android/`（排除 `build/`、`.gradle/`）中只出现 1 次，位于 `android/gradle.properties` 的单一 property；`app/build.gradle.kts` 通过该 property 取值赋给 `applicationId`，不重复写字面值。
- ac-version-name-from-version: `assembleDebug` 后从 APK/合并产物读到的 `versionName` 等于 `cat VERSION`；把根 `VERSION` 改成另一合法 `x.y.z` 后重跑 `assembleDebug`，`versionName` 随之变化；`android/` 源码与配置中不出现 `VERSION` 的字面值。
- ac-first-screen-placeholder-only: Compose 首屏可被测试断言到 `PurePace` 文案、至少 1 句非空 tagline、以及 Run / History / Log / Settings 这 4 个 Tab 占位标签；界面不含任何列表项、示例跑步记录、示例热量数据或“演示/示例”数据源。
- ac-no-business-logic: `android/app/src/main/AndroidManifest.xml` 不声明定位/后台位置/前台服务/录音等业务权限；`src/main` 下无计时器、GPS/GPX/TCX 解析、音频/TTS、历史或导出实现（可留 TODO 注释，不得有实现代码）。
- ac-no-cross-platform-framework: `android/` 的依赖声明中无 React Native、Flutter、Compose Multiplatform（`org.jetbrains.compose`）依赖；运行时依赖仅为 AndroidX/Jetpack Compose 与其官方依赖，测试依赖（JUnit / Robolectric 等）只出现在 test 配置。
- ac-build-artifacts-ignored: 完成一次 `assembleDebug` 与 `testDebugUnitTest` 后 `git status --porcelain` 不含 `android/app/build/`、`android/.gradle/`、`local.properties` 或其它构建残留；`android/local.properties` 已入库时视为失败。
- ac-baseline-gates-untouched: `bash scripts/check-baseline.sh` 仍退出 0（既有断言未被放宽：VERSION 单一真源、README/scripts 无版本字面值、AGENTS.md 四节与 skill 路由双向一致）；`.munk/code-gates.json` 原有门 id 全部保留且 command 未弱化为空转。

## 非目标

- 不做任何跑步业务功能：跑步页逻辑、计时器、GPS 定位、播报/TTS、节拍器、历史列表、热量记录、导出、地图。
- 不做视觉设计/主题体系/多语言框架；Tab 内为空占位，不实现真实导航与页面切换逻辑（可留 TODO 指向阶段 2/3）。
- 不创建 `scripts/build-android.sh` / `scripts/test-android.sh`（Android 脚本子项负责）；不改动 `scripts/version.sh` 的既有契约与 `--tools` 探测形态。
- 不创建/修改 `.github/workflows/android.yml`，不做 Android CI 真实 run id 回执（波 2 后续子项负责）。
- 不创建 `shared/` 夹具、`schema.sql`、字符串资源包。
- 不做真机/模拟器安装验证、不做签名配置、不做 Release/AAB、不做性能优化。
- 不引入 RN / Flutter / CMP 等跨端框架，不引入第三方运行时依赖（AndroidX/Jetpack 官方库与仅测试用的 JUnit/Robolectric 除外）。
- 不动 iOS 侧文件，不改 `.munk/baseline/**`，不改 Host 托管文件。

## 实现约束

**已加载 skill**：`.agents/skills/android-cli`（`AGENTS.md` 路由表中 Android 平台官方 skill，仓库内已安装）。仓库已是 Munk 基线（`AGENTS.md` + `VERSION` + `scripts/` 齐全），本项**不需要** repo-bootstrap，也**不创建应用工程以外的任何协作基线文件**。

**本机环境实测（Intake 在 2026-11-07 本 worktree 内已验证，Coding 可直接复用）**
- JDK 21 可用：`JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home`，`/usr/libexec/java_home -V` 同时列出 21/17/11/8，构建必须显式走 21。
- Android SDK 可用：`ANDROID_HOME=ANDROID_SDK_ROOT=/Users/zhutao/Library/Android/sdk`，已装 `platforms/android-36`（另有 36.1/37.0）与 `build-tools/36.0.0`；`cmdline-tools/17.0` 存在。
- 系统 gradle 9.6.1 在 `/opt/homebrew/bin/gradle`：**只允许用它生成一次 wrapper**，构建不得依赖它。
- `~/.gradle` 已有缓存可加速：AGP `8.13.0 / 8.8.0 / 9.0.1`、`androidx.compose:compose-bom:2026.03.01`、Gradle 发行版 `8.10.2 / 8.14.3 / 9.1.0`。Robolectric **未缓存**，首次运行需要联网下载（属正常，不要因此改写测试方案）。
- 网络：`https://repo.maven.apache.org/maven2/` 返回 200，`https://dl.google.com/dl/android/maven2/`（目录路径 404 属正常，域名可达）、`https://services.gradle.org/distributions/` 返回 200。
- 若拉 Gradle 发行版或依赖被网络拦截：按 `blocked:` 记录**实际失败命令 + 原始错误**回报，**禁止**改成离线 mock/stub、禁止伪造 wrapper jar、禁止把测试降级为不跑。核验命令示例：`bash android/gradlew -p android assembleDebug --info`、`bash android/gradlew -p android testDebugUnitTest --stacktrace`。

**版本与标识口径（继承 `repo-bootstrap` 已冻结事实，不得散落写号）**
- `versionName` 只能由 Gradle 在配置期读取仓库根 `VERSION` 派生（如 `rootProject.file("../VERSION").readText().trim()`），**每次构建都读，不缓存、不写进任何提交文件的字面值**；`VERSION` 格式由 `scripts/version.sh` 保证为 `x.y.z`。
- `applicationId` 唯一真源是 `android/gradle.properties` 的单个 property（建议 `PUREPACE_APPLICATION_ID=com.chaxiu.purepace`），`app/build.gradle.kts` 用 `providers.gradleProperty(...)` 读取；`namespace` 可另设但不得复写同一字面值（可用同一 property 派生）。
- 版本号/包名均不得写进 README、脚本或源码常量。

**构建与测试口径**
- 测试优先 CI 友好、零模拟器：JVM 单测放 `android/app/src/test/java/**`；UI 测试用 Robolectric 驱动 Compose（`testOptions.unitTests.isIncludeAndroidResources = true` + `createComposeRule`），同样落 `src/test`，被 `testDebugUnitTest` 收集。若 Robolectric 路线在本机确不可用，允许退到「Robolectric 风格 Compose 测试」之外的最小方案，但必须真跑并通过且仍是 `testDebugUnitTest`；不得用 `connectedAndroidTest` 顶替。
- `local.properties` 不入库（SDK 路径由 `ANDROID_HOME`/`ANDROID_SDK_ROOT` 提供）；`.gitignore` 追加 `android/.gradle/`、`android/build/`、`android/app/build/`、`android/local.properties`、`.kotlin/`。
- 保持既有基线绿：不改 `scripts/check-baseline.sh` 的断言（尤其 `ac-no-hardcoded-version` 会扫 `README.md` 与 `scripts/*.sh`），不动 `ios/**`。
- 门禁：如追加 Android 门，id 用 `build-android` / `test-android`，command 为单一 argv（例：`bash android/gradlew -p android assembleDebug`），cwd 为仓库根；不要把 `assembleDebug` 与 `testDebugUnitTest` 用 `&&` 串接。
- 首屏实现保持最小：`MainActivity` + 一个 stateless `@Composable` 占位屏即可，不引入 ViewModel/Repository/DI/导航图；可留 `// TODO(V1.1)` 注释指向后续阶段落点。
