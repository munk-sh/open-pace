# Domain: android-shell

PurePace Android 空壳工程域：以入库的 Gradle wrapper 驱动 `android/` 单一 App module，承载单 Activity + Jetpack Compose 占位首屏与 JVM/Robolectric 测试，全部随 `testDebugUnitTest` 执行、零模拟器。只做骨架与验证路径，不含任何跑步业务实现、视觉设计与第三方运行时依赖。

## 范围

- `android/gradlew` / `gradlew.bat` / `gradle/wrapper/gradle-wrapper.jar` / `gradle-wrapper.properties`：wrapper 入库并固定 Gradle 版本，不依赖系统 gradle；必须支持 `bash android/gradlew -p android <task>` 调用形态（`scripts/version.sh --tools` 按此形态探测，脚本契约不可为工程让步）。
- `android/settings.gradle.kts`、`android/build.gradle.kts`、`android/app/build.gradle.kts`、`android/gradle.properties`：minSdk 26 / compileSdk 36 / targetSdk 36 / JDK 21；`applicationId` 与 `namespace` 取自 `gradle.properties` 的单一 property；`versionName` 在配置期读仓库根 `VERSION`。
- `android/app/src/main/`：单 `ComponentActivity` + `setContent`，一个 stateless `@Composable` 占位屏（`PurePace` 名称 + 一句 tagline + Run/History/Log/Settings 四个 Tab 占位标签），无 ViewModel/Repository/DI/导航图，可留 `TODO(V1.1)` 指向后续阶段。
- `android/app/src/test/`：≥1 个纯 JVM 单测（文案契约）+ ≥1 个 Robolectric 驱动的 Compose UI 测试（`createComposeRule`，`testOptions.unitTests.isIncludeAndroidResources = true`），两者同被 `testDebugUnitTest` 收集，不引入 `connectedAndroidTest`。
- 依赖口径：运行时仅 AndroidX/Jetpack Compose（BOM 统一版本）+ `activity-compose`；测试依赖（JUnit / Robolectric / `ui-test-junit4`）只在 test 配置出现；无 RN / Flutter / Compose Multiplatform。
- `.gitignore`：覆盖 `android/.gradle/`、`android/build/`、`android/app/build/`、`android/local.properties`、`.kotlin/`；`local.properties` 不入库。
- 门禁：`.munk/code-gates.json` 追加 `build-android`（`bash android/gradlew -p android assembleDebug`）与 `test-android`（`bash android/gradlew -p android testDebugUnitTest`），单一 argv、cwd 为仓库根；既有门 id 与 command 不变。

## 验收

- ac-wrapper-pinned-and-committed: `android/gradlew` 存在且可执行，`gradle/wrapper/gradle-wrapper.jar` 为非空真实 jar，`distributionUrl` 指向固定版本（非 `latest`/`+`/`SNAPSHOT`）；`bash android/gradlew -p android --version` 退出码 0 且输出 Gradle 版本等于 `distributionUrl` 中的版本。
- ac-assemble-debug-apk: `bash android/gradlew -p android assembleDebug` 退出码 0，且 `android/app/build/outputs/apk/debug/` 下存在 ≥1 个非空 `*.apk`。
- ac-unit-tests-under-testdebugunittest: `bash android/gradlew -p android testDebugUnitTest` 退出码 0；`android/app/build/test-results/testDebugUnitTest/*.xml` 累计 `tests` ≥ 2、`failures` 与 `errors` 均为 0，且至少 1 例来自纯 JVM 单测类、至少 1 例来自 Robolectric/Compose UI 测试类（XML `classname` 可区分）。
- ac-tests-no-emulator: 验收链路只用 `testDebugUnitTest`，不需要 `connectedAndroidTest`、模拟器或真机；仓库无 `connectedAndroidTest` 相关必跑配置。
- ac-min-sdk-26: 合并 manifest（`android/app/build/intermediates/merged_manifest/debug/**/AndroidManifest.xml` 或等价产物）`minSdkVersion` 为 26，且 `output-metadata.json` 的 minSdk 口径为 26。
- ac-compile-sdk-36: `android/app/build.gradle.kts`（或统一版本目录）声明 `compileSdk = 36`，构建在本机已装 android-36 platform 上真实完成，非注释/被覆盖的声明。
- ac-jdk-21: 声明 Java 21 编译目标（`compileOptions` + Kotlin `jvmToolchain(21)`），构建在 JDK 21 下成功；不出现写死的 JDK 绝对路径，`local.properties` 不提交且不含 `org.gradle.java.home`。
- ac-application-id-single-source: 字面值 `com.chaxiu.purepace` 在 `android/`（排除 `build/`、`.gradle/`）只出现 1 次，位于 `android/gradle.properties` 单一 property；`app/build.gradle.kts` 通过该 property 取值赋给 `applicationId`/`namespace`，不重复写字面值。
- ac-version-name-from-version: `assembleDebug` 产物读到的 `versionName` 等于 `cat VERSION`；把根 `VERSION` 改成另一合法 `x.y.z` 后重跑 `assembleDebug`，`versionName` 随之变化；`android/` 源码与配置不出现该字面值。
- ac-first-screen-placeholder-only: Compose 首屏可被断言到 `PurePace` 文案、≥1 句非空 tagline、Run/History/Log/Settings 4 个 Tab 占位标签；界面无列表项、示例跑步记录、示例热量数据或「演示/示例」数据源。
- ac-no-business-logic: `src/main/AndroidManifest.xml` 不声明定位/后台位置/前台服务/录音等业务权限；`src/main` 无计时器、GPS/GPX/TCX 解析、音频/TTS、历史或导出实现（可留 TODO 注释）。
- ac-no-cross-platform-framework: 依赖声明无 React Native / Flutter / Compose Multiplatform（`org.jetbrains.compose`）；运行时依赖仅 AndroidX/Jetpack Compose 与其官方库，测试依赖只在 test 配置。
- ac-build-artifacts-ignored: 跑过 `assembleDebug` 与 `testDebugUnitTest` 后 `git status --porcelain` 不含 `android/app/build/`、`android/.gradle/`、`local.properties` 或其它构建残留。
- ac-baseline-gates-untouched: `bash scripts/check-baseline.sh` 仍退出 0（VERSION 单一真源、README/scripts 无版本字面值、AGENTS.md 四节与 skill 路由双向一致）；`.munk/code-gates.json` 原有门 id 全部保留且 command 未被弱化。
- ac-android-scripts-deferred: 本域不新增 `scripts/build-android.sh` / `scripts/test-android.sh`，不改 `scripts/version.sh` 的既有契约与 `--tools` 探测形态（由后续 Android 脚本子项负责）。

## 非目标

- 不做任何跑步业务功能：跑步页逻辑、计时器、GPS 定位、播报/TTS、节拍器、历史列表、热量记录、导出、地图。
- 不做视觉设计/主题体系/多语言框架；Tab 内为空占位，不实现真实导航与页面切换逻辑。
- 不创建 Android 构建/测试 shell 脚本（`scripts/build-android.sh` / `scripts/test-android.sh`），不改动 `scripts/version.sh`。
- 不创建/修改 `.github/workflows/android.yml`，不做 Android CI 真实 run id 回执。
- 不创建 `shared/` 夹具、`schema.sql`、字符串资源包。
- 不做真机/模拟器安装验证、不做签名配置、不做 Release/AAB、不做性能优化。
- 不引入 RN / Flutter / CMP 等跨端框架，不引入第三方运行时依赖（AndroidX/Jetpack 官方库与仅测试用的 JUnit/Robolectric 除外）。
- 不动 iOS 侧文件，不改写既有基线门禁断言，不改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- 环境事实：JDK 21（`JAVA_HOME` 指向 zulu-21，构建必须显式走 21）、`ANDROID_HOME=ANDROID_SDK_ROOT` 指向本机 SDK 且已装 `platforms/android-36` 与 `build-tools/36.0.0`；系统 gradle 仅可用于生成一次 wrapper，构建一律走 `android/gradlew`。
- wrapper 版本与 AGP / Compose BOM 版本按本机已验证组合固定，升级需同时改 wrapper 属性与插件版本并重跑 `assembleDebug` / `testDebugUnitTest`。
- `applicationId` 唯一真源是 `android/gradle.properties` 的单个 property，`namespace` 由同一 property 派生，不得复写字面值；包名与版本号不得写进 README、脚本或源码常量。
- 版本派生：`versionName` 每次配置期读 `rootProject.file("../VERSION")`，不缓存、不落字面值；格式由 `scripts/version.sh` 保证为 `x.y.z`。
- 网络受限时按 `blocked:` 记录实际失败命令与原始错误，禁止离线 mock/stub、伪造 wrapper jar、或把测试降级为不跑；Robolectric 首次运行需联网下载属正常，不得因此改写测试方案。
- 门禁形态：`command` 保持单一 argv，`assembleDebug` 与 `testDebugUnitTest` 不得用 `&&` 串接成一条门；构建/测试产物由忽略规则覆盖，不入库。
- 证据口径：只报真实命令输出摘要与用例数，不写「CI 通过」「真机已验证」；本地门通过不替代远端 run。

## 最近交付证明

- workItemId: wi_ws_b36d34c91bf1915a（2026-11-07，pass）
- 交付：`android/` 全套骨架——入库 Gradle wrapper（固定 Gradle 8.14.3）、`settings.gradle.kts` / `build.gradle.kts` / `app/build.gradle.kts` / `gradle.properties`（compileSdk 36、minSdk 26、JDK 21、`PUREPACE_APPLICATION_ID` 单一真源、`versionName` 读根 `VERSION`）、单 Activity Compose 占位首屏（`PurePace` + tagline + 四 Tab）、纯 JVM 单测与 Robolectric Compose UI 测试各一组；`.gitignore` 覆盖 Android 构建残留；`.munk/code-gates.json` 新增 `build-android` / `test-android`。
- 验证：`bash android/gradlew -p android assembleDebug` 产出 `app-debug.apk`（`versionName=0.1.0`、minSdk 26）；`testDebugUnitTest` 4 例全绿（`PlaceholderCopyTest` 3 例 + `PurePacePlaceholderScreenTest` 1 例，零 failures/errors，无模拟器）；`bash scripts/check-baseline.sh` 与既有 iOS 门保持绿。
