# Android 构建/测试脚本与门禁扩展

> 只覆盖 WorkSet 波 2 的 `key: android-scripts` 子项。WorkSet 叙事以 `.munk/work-set/overview.md` 为准，此处不复制；`android/` 骨架与 `scripts/` 现状以 `predecessors/wi_ws_b36d34c91bf1915a`、`predecessors/wi_ws_6035fb0cde33a0a3` 为已落地事实。

## 范围

在**已落地的 Android 骨架**上补齐统一脚本入口与门禁，不改工程本身：

1. `scripts/build-android.sh`：以 `android/gradlew -p android assembleDebug` 真实构建，成功时校验并打印非空 APK 产物路径（`android/app/build/outputs/apk/debug/*.apk`）；构建失败或无产物时非零退出，不输出伪造成功行。
2. `scripts/test-android.sh`：以 `android/gradlew -p android testDebugUnitTest` 真实跑测试，解析 `android/app/build/test-results/testDebugUnitTest/*.xml` 统计用例总数与 failures/errors，并按测试类区分「纯 JVM 单测」与「Robolectric / Compose UI 测试」，两类各 ≥1 才算通过；旧结果不得计入。
3. `scripts/check-android.sh`：Android 结构断言脚本（相当于 iOS 侧的 `check-ios-scripts.sh` + 工程结构断言），覆盖脚本自身契约、applicationId 单点、minSdk/compileSdk/JDK、版本派生、wrapper 固定、无业务实现、无跨端框架、code-gates 完整性；逐条 `[PASS]/[FAIL]` 并打印汇总，任一失败非零退出。
4. `.munk/code-gates.json`：新增 `lint-android`（→ `bash scripts/check-android.sh`）；把 `build-android` / `test-android` 改为经新脚本路由（id 保留、执行同一 gradle task、强度不降）；**既有 iOS / 基线门 id 与 command 逐字节不变**。
5. `README.md`：Android 构建/测试行由「由 Android 骨架子项补齐」改为已就绪，补 `check-android` 行并更新门清单描述；仍受「无版本字面值、无已发布措辞」约束。

## 验收

- ac-build-android-apk: 干净状态（`android/app/build` 不存在）下 `bash scripts/build-android.sh` 退出 0，stdout 含真实 APK 路径，且 `android/app/build/outputs/apk/debug/` 下 ≥1 个非空 `*.apk`。
- ac-build-android-idempotent: 连续两次运行 `bash scripts/build-android.sh` 均退出 0，且两次打印的 APK 路径一致（可重复执行，无累积副作用）。
- ac-build-android-fails-loudly: 当构建失败或产物缺失时脚本退出非零并输出 `error:`/失败原因；脚本内不存在伪造 `BUILD SUCCESSFUL` 类成功行（不自造 gradle 输出）。
- ac-test-android-real-suite: `bash scripts/test-android.sh` 退出 0，真实执行 `testDebugUnitTest`（不含 `connectedAndroidTest`、不需要模拟器/真机），stdout 含累计用例数与 failures/errors 统计，且 failures 与 errors 均为 0、累计 tests ≥ 2。
- ac-test-android-breakdown: 脚本输出纯 JVM 单测与 Robolectric/Compose UI 测试两类各自用例数，两类均 ≥1；若任一类为 0 或存在失败用例，脚本退出非零（不得因「总数够」而放过）。
- ac-test-android-fresh-results: 脚本只以本次运行产生的测试结果为准（运行前清理或校验结果文件修改时间晚于本次启动）；在 `android/app/build` 不存在时直接运行仍能通过；预置一份伪造的旧结果 XML 不影响判定。
- ac-script-help-and-strict: 三个脚本 `bash -n` 通过、首行为 `#!/usr/bin/env bash`、正文含 `set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根（任意 cwd 下一致）；`--help` 退出 0 且输出含「用法」；未知参数退出 2。
- ac-check-android-application-id: `scripts/check-android.sh` 断言字面值 `com.chaxiu.purepace` 在 `android/`（排除 `build/`、`.gradle/`）仅出现 1 次且位于 `android/gradle.properties` 的单一 property；出现第 2 处即 FAIL。
- ac-check-android-sdk-jdk: 断言 `compileSdk = 36`、`minSdk = 26`、Java/Kotlin 编译目标为 21，且 `android/` 无写死的 JDK 绝对路径、`local.properties` 未入库；任一不符即 FAIL。
- ac-check-android-version: 断言 `versionName` 由仓库根 `VERSION` 派生（配置期读取，不缓存），且 `android/` 提交内容中不出现 `cat VERSION` 的字面值；不符即 FAIL。
- ac-check-android-wrapper: 断言 `android/gradle/wrapper/gradle-wrapper.jar` 为非空 jar、`distributionUrl` 指向固定版本（不含 `latest`/`+`/`SNAPSHOT`）；不符即 FAIL。
- ac-check-android-no-business: 断言 `AndroidManifest.xml` 无定位/后台位置/前台服务/录音等业务权限，`src/main` 无计时器、GPS/GPX/TCX 解析、音频/TTS、历史或导出实现，依赖声明无 RN / Flutter / Compose Multiplatform；不符即 FAIL。
- ac-check-android-gates-integrity: `scripts/check-android.sh` 断言 `.munk/code-gates.json` 可解析、id 唯一、无空转命令（`echo`/`true`/空串）、存在 `lint-android` / `build-android` / `test-android` 且三条命令分别指向三个新脚本，且既有非 Android 门（`lint`、`lint-baseline`、`lint-ios-*`、`build-ios*`、`test-ios*`、`test`、`check-shared`）的 id 与 command 与子项开始前一致；不符即 FAIL。
- ac-check-android-negative-path: `scripts/check-android.sh` 含内置反例自检（沙箱复制最小样本或等价 `--root` 机制），至少能对「applicationId 出现两处」「compileSdk 不等于 36」两类注入反例输出 FAIL 并以非零退出；证明断言不是恒真。
- ac-code-gates-single-argv: 新增/更新的 Android 门 `command` 为单一 argv（不含 `&&`、`|`、`;`、重定向），`cwd` 为 `.`；`build-android` / `test-android` 仍分别只做一次 `assembleDebug` 与一次 `testDebugUnitTest`（不串接）。
- ac-existing-gates-unchanged: `git diff` 显示 `.munk/code-gates.json` 中既有非 Android 门块零改动（id 与 command 逐字节一致）；`test` 门仍为 `bash scripts/check-baseline.sh`。
- ac-baseline-and-ios-still-green: `bash scripts/check-baseline.sh` 与 `bash scripts/check-ios-scripts.sh` 仍退出 0（未破坏版本单一真源、无版本字面值、AGENTS.md 四节与 skill 路由、iOS 脚本契约）。
- ac-scope-no-app-change: 本子项改动只落在 `scripts/build-android.sh`、`scripts/test-android.sh`、`scripts/check-android.sh`、`.munk/code-gates.json`、`README.md`（及 `.munk/changes/**`）；`ios/**`、`android/**`、`shared/**` 无改动；运行脚本后 `git status --porcelain` 不含构建残留。

## 非目标

- 不改 `android/` 工程：Gradle/AGP/依赖版本、首屏 Compose、既有测试用例数一律不动；若脚本暴露真实工程缺陷，按 `blocked:` 记录实测命令与原始错误回报，不在本项顺手改工程。
- 不改 `scripts/version.sh` 契约与 `--tools` 输出格式（`android/gradlew --version` 探测形态不能为脚本让步）。
- 不新增 `.github/workflows/android.yml`、不推远端、不取 CI run id（波 2 后续子项负责）。
- 不做模拟器/真机安装、`connectedAndroidTest`、签名、Release/AAB。
- 不引入 Android Lint / detekt / ktlint / konsist 等新工具链：`lint-android` 是结构断言门，不是 Gradle `lintDebug` 任务。
- 不改 `ios/**`、`shared/**`、`.munk/baseline/**` 既有断言，不改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。
- 不新增业务代码、示例/种子数据、视觉设计或多语言框架；不引入任何第三方运行时依赖。

## 实现约束

**已加载 skill**：`.agents/skills/android-cli`（`AGENTS.md` 路由表内 Android 官方 skill，本地已安装）。仓库已有 `AGENTS.md` + `VERSION` + `scripts/`，本项**不需要** repo-bootstrap，也不创建新的协作基线文件。

**本机环境实测（Intake 2026-11-07 在本 worktree 已验证）**
- `JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home`，默认 `java -version` 即 21.0.1；`/usr/libexec/java_home -V` 同时有 17/11/8，因此脚本不得靠「默认 java」赌版本，需显式校验 21（缺 `JAVA_HOME` 时可回退 `java_home -v 21` 探测）。
- `ANDROID_HOME=ANDROID_SDK_ROOT=/Users/zhutao/Library/Android/sdk`，已装 `platforms/android-36`（另 36.1/37.0）与 `build-tools/36.0.0`。
- `bash android/gradlew -p android --version` 实测输出 Gradle 8.14.3、Launcher JVM 21.0.1，wrapper 可用且不依赖系统 gradle。
- 可用工具：`node` v24.4.1、`jq`、`python3` 均存在（`node` 为 `scripts/check-baseline.sh` 已用的 JSON 校验方式）；脚本不得硬依赖 CI 未保证的 `jq`，优先纯 bash/grep 解析，或用 `node` + grep 回退。
- 禁止把上述绝对路径写进脚本或 `local.properties`；路径缺失时 fail fast 并打印可操作提示。

**脚本形态（对齐 `build-ios.sh` / `test-ios.sh` / `check-ios-scripts.sh`）**
- `#!/usr/bin/env bash` + `set -euo pipefail` + `usage()` + `case "${1:-}"`（`-h|--help` → 0，未知参数 → 2，多于一个参数 → 2）+ `script_dir`/`repo_root` 由 `BASH_SOURCE` 推导后 `cd "$repo_root"`。
- `check-android.sh` 输出格式沿用既有风格：`pass`/`fail` 计数、逐条 `[PASS] ac-xxx` / `[FAIL] ac-xxx: 原因`、末尾 `N 项断言，M 项失败`。
- 新脚本与 README 不得出现根 `VERSION` 的字面值（`check-baseline.sh` 的 `ac-no-hardcoded-version` 与 `check-ios-scripts.sh` 的 `ac-no-version-literal` 都会扫 `scripts/*.sh`）。
- 只写 `android/app/build`（已被 `.gitignore` 覆盖），不改版本文件、不写 `local.properties`。

**门禁路由口径**
- 现状：`android-shell` 域此前让 `build-android` / `test-android` 直连 `bash android/gradlew -p android <task>`。本项保留这两个 id，改为指向 `bash scripts/build-android.sh` / `bash scripts/test-android.sh`（同一 gradle task + 额外产物/用例断言，属增强不属放宽）；新增 `lint-android` → `bash scripts/check-android.sh`，cwd 为 `.`。
- 该路由变更须在交付摘要中明写，并在 Delivery 折叠 `.munk/baseline/domains/android-shell/product.md` 时同步更新其「门禁」行，避免基线与事实冲突。
- 既有非 Android 门（含 `test` → `bash scripts/check-baseline.sh`）零改动，禁止借机「统一风格」重写 iOS 门。

**测试结果判定细节**
- 结果文件：`android/app/build/test-results/testDebugUnitTest/*.xml`；用 `tests=` / `failures=` / `errors=` 属性累加。
- 两类区分：以测试源码中「含 `RobolectricTestRunner` / `createComposeRule` / `createAndroidComposeRule`」的类为 Robolectric/Compose 类，其余测试类为纯 JVM 类；再与 XML 的 `classname` 对应计数。当前基线为 3 例纯 JVM（`PlaceholderCopyTest`）+ 1 例 Robolectric（`PurePacePlaceholderScreenTest`），脚本不得把该具体数字写死，只校验「两类各 ≥1 且无失败」。
- 首次 Robolectric 运行需联网下载依赖属正常；网络被拦时按 `blocked:` 记录实际命令与原始错误，禁止离线 mock/stub、跳过测试或改写测试方案。
