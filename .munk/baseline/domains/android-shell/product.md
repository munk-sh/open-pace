# Domain: android-shell

PurePace Android 空壳工程域：以入库的 Gradle wrapper 驱动 `android/` 单一 App module，承载单 Activity + Jetpack Compose 占位首屏与 JVM/Robolectric 测试，全部随 `testDebugUnitTest` 执行、零模拟器。只做骨架与验证路径，不含任何跑步业务实现、视觉设计与第三方运行时依赖。

## 范围

- `android/gradlew` / `gradlew.bat` / `gradle/wrapper/gradle-wrapper.jar` / `gradle-wrapper.properties`：wrapper 入库并固定 Gradle 版本，不依赖系统 gradle；`scripts/build-android.sh` / `scripts/test-android.sh` 以 `bash android/gradlew -p android <task>` 形态调用；`scripts/version.sh --tools` 的 Gradle 版本只离线读取 `gradle-wrapper.properties` 的 `distributionUrl`，不调用 gradlew。
- `android/settings.gradle.kts`、`android/build.gradle.kts`、`android/app/build.gradle.kts`、`android/gradle.properties`：minSdk 26 / compileSdk 36 / targetSdk 36 / JDK 21；`applicationId` 与 `namespace` 取自 `gradle.properties` 的单一 property；`versionName` 在配置期读仓库根 `VERSION`。
- `android/app/src/main/`：单 `ComponentActivity` + `setContent`，一个 stateless `@Composable` 占位屏（`PurePace` 名称 + 一句 tagline + Run/History/Log/Settings 四个 Tab 占位标签），无 ViewModel/Repository/DI/导航图，可留 `TODO(V1.1)` 指向后续阶段。
- `android/app/src/test/`：≥1 个纯 JVM 单测（文案契约）+ ≥1 个 Robolectric 驱动的 Compose UI 测试（`createComposeRule`，`testOptions.unitTests.isIncludeAndroidResources = true`），两者同被 `testDebugUnitTest` 收集，不引入 `connectedAndroidTest`。
- 依赖口径：运行时仅 AndroidX/Jetpack Compose（BOM 统一版本）+ `activity-compose`；测试依赖（JUnit / Robolectric / `ui-test-junit4`）只在 test 配置出现；无 RN / Flutter / Compose Multiplatform。
- `.gitignore`：覆盖 `android/.gradle/`、`android/build/`、`android/app/build/`、`android/local.properties`、`.kotlin/`；`local.properties` 不入库。
- `scripts/build-android.sh` / `scripts/test-android.sh` / `scripts/check-android.sh`：Android 统一入口。构建脚本真实跑 `assembleDebug` 并校验打印非空 APK 路径；测试脚本真实跑 `testDebugUnitTest`，按测试类区分纯 JVM 与 Robolectric/Compose 两类并各自计数；两处 `gradlew` 调用统一收敛到 `gradle_with_retry`（仅网络/下载类失败最多重试 3 次即最多 4 次尝试，非网络失败立即原样退出，输出 `tee` 实时打印不吞）；结构脚本逐条断言脚本契约、有界重试形态与 stub 反例、applicationId 单点、SDK/JDK、版本派生、wrapper 固定、无业务实现、无跨端框架与门禁完整性，并含内置反例自检。
- 门禁：`.munk/code-gates.json` 中 `lint-android` → `bash scripts/check-android.sh`；`build-android` / `test-android` 保留原 id，改经统一脚本路由（同一 gradle task + 产物/用例断言，强度不降），单一 argv、cwd 为仓库根；既有非 Android 门 id 与 command 逐字节不变。

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
- ac-build-android-apk: 干净状态（`android/app/build` 不存在）下 `bash scripts/build-android.sh` 退出 0，stdout 含真实 APK 路径，且 `android/app/build/outputs/apk/debug/` 下 ≥1 个非空 `*.apk`。
- ac-build-android-idempotent: 连续两次运行 `bash scripts/build-android.sh` 均退出 0，且两次打印的 APK 路径一致。
- ac-build-android-fails-loudly: 构建失败或产物缺失时脚本退出非零并输出 `error:`/失败原因；脚本内不伪造 `BUILD SUCCESSFUL` 类成功行。
- ac-test-android-real-suite: `bash scripts/test-android.sh` 退出 0，真实执行 `testDebugUnitTest`（不含 `connectedAndroidTest`、不需要模拟器/真机），stdout 含累计用例数与 failures/errors 统计，failures 与 errors 均为 0 且累计 tests ≥ 2。
- ac-test-android-breakdown: 脚本输出纯 JVM 单测与 Robolectric/Compose UI 测试两类各自用例数，两类均 ≥1；任一类为 0 或存在失败用例即非零退出（不得因「总数够」放过）。
- ac-test-android-fresh-results: 只以本次运行产生的测试结果为准（运行前清理或校验结果文件新于本次启动）；`android/app/build` 不存在时直接运行仍通过；预置伪造旧结果 XML 不影响判定。
- ac-android-gradle-bounded-retry: `scripts/build-android.sh` 与 `scripts/test-android.sh` 无函数体外的裸 `bash android/gradlew` 调用（各恰好 1 处、位于同一 `gradle_with_retry` 函数体内），`assembleDebug` / `testDebugUnitTest` 均经该函数；尝试上限 4（1 次 + 最多 3 次重试），仅当上一轮失败命中网络/下载特征（`Could not download` / `Could not resolve` / `Read timed out` / `Connect timed out` / `Connection refused` / `UnknownHostException` / `SSLException` / `HTTP 5xx` / `network is unreachable`）才重试。
- ac-android-retry-non-network-fails-fast: stub `gradlew` 输出普通编译/测试失败（不含网络特征）时，脚本只尝试 1 次并原样非零退出。
- ac-android-retry-exhausted-exitcode: stub 每次均以网络特征非零退出时尝试次数恰为 4 次后非零退出；`build-android.sh` 退出码与 stub 退出码一致，`test-android.sh` 以 1 结束并打印 `testDebugUnitTest 失败`。
- ac-android-retry-success-path: stub 第 2 次尝试成功时，重试后脚本继续走原有成功路径（`build-android.sh` 校验 APK 产物；`test-android.sh` 校验 test-results XML 与用例计数），入口语义与既有断言不变。
- ac-check-android-static-guards: `scripts/check-android.sh` 含上述静态断言与 `mktemp` 沙箱 stub 反例自检（非网络只试 1 次、网络失败恰 4 次、退出码语义、删除重试函数的违规样本必须 FAIL），离线、可重复、不污染仓库。
- ac-script-help-and-strict: 三个脚本 `bash -n` 通过、首行为 `#!/usr/bin/env bash`、正文含 `set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根（任意 cwd 一致）；`--help` 退出 0 且输出含「用法」；未知参数退出 2。
- ac-check-android-application-id: `com.chaxiu.purepace` 在 `android/`（排除 `build/`、`.gradle/`）仅出现 1 次且位于 `android/gradle.properties` 单一 property；出现第 2 处即 FAIL。
- ac-check-android-sdk-jdk: 断言 `compileSdk = 36`、`minSdk = 26`、Java/Kotlin 编译目标 21，且 `android/` 无写死 JDK 绝对路径、`local.properties` 未入库；不符即 FAIL。
- ac-check-android-version: 断言 `versionName` 由仓库根 `VERSION` 派生（配置期读取、不缓存），`android/` 提交内容不出现 `cat VERSION` 字面值；不符即 FAIL。
- ac-check-android-wrapper: 断言 `gradle-wrapper.jar` 为非空 jar、`distributionUrl` 指向固定版本（不含 `latest`/`+`/`SNAPSHOT`）；不符即 FAIL。
- ac-check-android-no-business: 断言 `AndroidManifest.xml` 无定位/后台位置/前台服务/录音等业务权限，`src/main` 无计时器、GPS/GPX/TCX 解析、音频/TTS、历史或导出实现，依赖无 RN / Flutter / CMP；不符即 FAIL。
- ac-check-android-gates-integrity: 断言 `.munk/code-gates.json` 可解析、id 唯一、无空转命令（`echo`/`true`/空串），存在 `lint-android` / `build-android` / `test-android` 且分别指向三个新脚本，既有非 Android 门 id 与 command 未变；不符即 FAIL。
- ac-check-android-negative-path: `scripts/check-android.sh` 含内置反例自检（沙箱最小样本或等价 `--root` 机制），至少能对「applicationId 出现两处」「compileSdk 不等于 36」两类注入反例输出 FAIL 并非零退出。
- ac-code-gates-single-argv: 新增/更新的 Android 门 `command` 为单一 argv（不含 `&&`、`|`、`;`、重定向），`cwd` 为 `.`；`build-android` / `test-android` 仍分别只做一次 `assembleDebug` 与一次 `testDebugUnitTest`，不串接。
- ac-existing-gates-unchanged: `.munk/code-gates.json` 中既有非 Android 门块零改动（id 与 command 逐字节一致）；`test` 门仍为 `bash scripts/check-baseline.sh`。
- ac-baseline-and-ios-still-green: `bash scripts/check-baseline.sh` 与 `bash scripts/check-ios-scripts.sh` 仍退出 0（版本单一真源、无版本字面值、AGENTS.md 四节与 skill 路由、iOS 脚本契约均未破坏）。
- ac-scope-no-app-change: 改动只落在三个 `scripts/*-android.sh`、`.munk/code-gates.json`、`README.md`；`ios/**`、`android/**`、`shared/**` 无改动；跑过脚本后 `git status --porcelain` 不含构建残留。

## 非目标

- 不做任何跑步业务功能：跑步页逻辑、计时器、GPS 定位、播报/TTS、节拍器、历史列表、热量记录、导出、地图。
- 不做视觉设计/主题体系/多语言框架；Tab 内为空占位，不实现真实导航与页面切换逻辑。
- 不改 `android/` 工程本身：Gradle/AGP/依赖版本、首屏 Compose、既有测试用例数一律不动；脚本暴露真实工程缺陷时按 `blocked:` 记录实测命令与原始错误回报，不顺手改工程。
- 不改 `scripts/version.sh` 的对外契约（无参、`--help`、未知参数退出码与输出格式/行序不变）；`--tools` 的 Gradle 行已改为离线解析 wrapper properties（不调用 gradlew），版本来源仍由本域 wrapper 固定，不因探测或重试改动放宽任何本机断言。
- 不引入 Android Lint / detekt / ktlint / konsist 等新工具链：`lint-android` 是结构断言门，不是 Gradle `lintDebug`。
- 不做模拟器/真机安装、`connectedAndroidTest`、签名、Release/AAB；不做性能优化。
- 不创建/修改 `.github/workflows/android.yml`，不做 Android CI 真实 run id 回执。
- 不创建 `shared/` 夹具、`schema.sql`、字符串资源包。
- 不引入 RN / Flutter / CMP 等跨端框架，不引入第三方运行时依赖（AndroidX/Jetpack 官方库与仅测试用的 JUnit/Robolectric 除外）。
- 不动 iOS 侧文件，不改写既有基线门禁断言，不改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- 环境事实：JDK 21（`JAVA_HOME` 指向 zulu-21，构建必须显式走 21；缺 `JAVA_HOME` 时回退 `java_home -v 21` 探测，不得赌默认 `java`）、`ANDROID_HOME=ANDROID_SDK_ROOT` 指向本机 SDK 且已装 `platforms/android-36` 与 `build-tools/36.0.0`；系统 gradle 仅可用于生成一次 wrapper，构建一律走 `android/gradlew`。绝对路径不得写进脚本或 `local.properties`，缺失时 fail fast 并打印可操作提示。
- 脚本形态：`#!/usr/bin/env bash` + `set -euo pipefail` + `usage()` + `case "${1:-}"`（`-h|--help` → 0，未知参数/参数过多 → 2）+ `script_dir`/`repo_root` 由 `BASH_SOURCE` 推导后 `cd "$repo_root"`；`check-android.sh` 输出沿用 `[PASS] ac-xxx` / `[FAIL] ac-xxx: 原因` + `N 项断言，M 项失败` 风格。脚本与 README 不得出现根 `VERSION` 字面值（`check-baseline.sh` / `check-ios-scripts.sh` 会扫描）。
- wrapper 版本与 AGP / Compose BOM 版本按本机已验证组合固定，升级需同时改 wrapper 属性与插件版本并重跑 `assembleDebug` / `testDebugUnitTest`。
- `applicationId` 唯一真源是 `android/gradle.properties` 的单个 property，`namespace` 由同一 property 派生，不得复写字面值；包名与版本号不得写进 README、脚本或源码常量。
- 版本派生：`versionName` 每次配置期读 `rootProject.file("../VERSION")`，不缓存、不落字面值；格式由 `scripts/version.sh` 保证为 `x.y.z`。
- 网络受限时按 `blocked:` 记录实际失败命令与原始错误，禁止离线 mock/stub、伪造 wrapper jar、或把测试降级为不跑；Robolectric 首次运行需联网下载属正常，不得因此改写测试方案。
- 测试结果判定：结果文件为 `android/app/build/test-results/testDebugUnitTest/*.xml`，累加 `tests=` / `failures=` / `errors=` 属性；含 `RobolectricTestRunner` / `createComposeRule` / `createAndroidComposeRule` 的测试类记为 Robolectric/Compose 类，其余为纯 JVM 类，再与 XML `classname` 对齐计数。具体用例数不写死，只校验「两类各 ≥1 且零失败」。首次 Robolectric 运行需联网下载依赖属正常，网络被拦时按 `blocked:` 记录，禁止离线 mock/stub 或跳测。
- 门禁形态：`command` 保持单一 argv，`assembleDebug` 与 `testDebugUnitTest` 不得用 `&&` 串接成一条门；`build-android` / `test-android` 经统一脚本路由（同一 gradle task + 额外断言，属增强不属放宽），不得借机统一重写既有 iOS 门；构建/测试产物由忽略规则覆盖，不入库。
- 重试口径：重试函数名可被静态识别（`gradle_with_retry`），函数体内保留唯一单次 `bash android/gradlew -p android <task>` 调用；输出经 `tee` 落到 `mktemp` 临时日志并实时打印，失败输出不得被吞；重试间隔保持短且有界（如固定 1s），不把 `test-android.sh` 在 CI 上拖到超时；不改 wrapper 自身 `retries` / `networkTimeout` 属性，不引入 `curl`/`jq`/`python` 等外部依赖上生产路径。
- 证据口径：只报真实命令输出摘要与用例数，不写「CI 通过」「真机已验证」；本地门通过不替代远端 run。

## 最近交付证明

- workItemId: wi_ws_829cd75d36d5bb39（2026-11-08，pass）
- 交付：`scripts/build-android.sh` / `scripts/test-android.sh` 各自新增 `gradle_with_retry`，`assembleDebug` 与 `testDebugUnitTest` 均经其调用（函数体内唯一裸 `bash android/gradlew -p android <task>`）：仅网络/下载类失败重试，最多 4 次尝试、间隔 1s，非网络失败 1 次即原样透传退出码，`tee` 实时打印；`scripts/check-android.sh` 新增静态断言（唯一调用点在函数内、上限 4、网络特征清单）与 `mktemp` 沙箱 stub 反例（非网络 1 次、网络恰 4 次、退出码透传、删除函数必 FAIL）。
- 验证：`code_gates` 22 门全绿；`lint-android`/`check-android.sh` 全断言 PASS；`build-android` 产 APK 与 `test-android` 用例计数路径语义未变（仅新增重试包裹）。
- 风险标注：远端 `ios`/`android` workflow 的本次 headSha run 需推送后取真实 run id 与 conclusion 才能宣称绿，本地结果不作远端证据；`android/**` 零改动。
