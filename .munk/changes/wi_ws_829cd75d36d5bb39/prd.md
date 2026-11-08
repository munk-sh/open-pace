# 移除 version.sh 的 Gradle 网络依赖并给 Android gradlew 加有界重试

## Scope

修复远端 CI 真实红：`ios` workflow 的 `lint` 步（`bash scripts/check-ios-scripts.sh`）在 `bash scripts/version.sh --tools` 里调用 `android/gradlew -p android --version`，该调用在干净 runner 上会触发 Gradle 分发包下载；分发服务器 504 时命令输出为空，`Gradle:` 行落成「未就绪」，静态断言失败并带红整个 `ios` run。

本项只改 5 个 shell 脚本，保持所有对外语义：

1. `scripts/version.sh`：`--tools` 的 Gradle 行改为**离线解析** `android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`（如 `.../gradle-8.14.3-all.zip` → `8.14.3`），**彻底不再调用 `android/gradlew`**；不得触网、不得启动 JVM。输出格式、行序、退出码、`--help` 与无参契约保持不变。
2. `scripts/build-android.sh` / `scripts/test-android.sh`：`gradlew` 调用统一收敛到一个**有界重试**函数；仅对下载/网络类失败特征重试，最多 3 次重试（即最多 4 次尝试）；非网络失败立即返回，最终失败原样非零退出；`assembleDebug` / `testDebugUnitTest` 入口语义、输出流式打印、APK 与 test-results 校验逻辑不变。
3. `scripts/check-ios-scripts.sh`：新增静态断言——`scripts/version.sh` 不得出现 `gradlew` 调用，且必须读 `android/gradle/wrapper/gradle-wrapper.properties`；Gradle 行期望值改为从 wrapper properties 推导（与 version.sh 解耦地独立推导，避免同源恒真）。
4. `scripts/check-android.sh`：新增静态断言——`build-android.sh` / `test-android.sh` 的 `gradlew` 调用必须经由有界重试函数，且重试上限与网络失败特征判定存在；沙箱内用 stub `gradlew` 反例验证重试次数上限与退出码语义（离线、无网络）。

`.github/workflows/*` 零改动（触发条件、权限、步骤 JSON 一律不动）。`.munk/code-gates.json` 门 id/command/数量（22 门）零改动。

## Acceptance Criteria

- ac-version-tools-no-gradlew: `scripts/version.sh` 正文（含注释与帮助文本）不含字符串 `gradlew`；`bash scripts/version.sh --tools` 在 `android/gradlew` 不可执行时仍退出 0，并输出 `^Gradle: [0-9]` 行。
- ac-version-tools-offline-parse: 将 `android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl` 改为 `gradle-9.9.9-all.zip` 后，`--tools` 输出 `Gradle: 9.9.9`（证明值来自 wrapper properties 而非网络或缓存）；恢复原值后输出与仓库状态一致。
- ac-version-tools-matches-wrapper: 仓库真实状态下 `--tools` 的 `Gradle:` 行等于 `gradle-wrapper.properties` 中 `distributionUrl` 解析出的 `gradle-<x.y[.z]>-{bin,all}.zip` 版本号（当前为 8.14.3）。
- ac-version-tools-idempotent: 连续两次 `bash scripts/version.sh --tools` 输出逐字节相同（含在 Gradle 分发不可达环境下）。
- ac-version-tools-missing-wrapper-fallback: `android/gradle/wrapper/gradle-wrapper.properties` 缺失或无法解析出版本时，Gradle 行标注「未就绪（…）」，命令仍退出 0，不伪造版本。
- ac-version-bare-unchanged: `bash scripts/version.sh` 仍只输出根 `VERSION` 内容；`--help` 退出 0；未知参数退出 2；`scripts/version.sh` 仍以 `VERSION` 为唯一版本来源（无 `git describe` / `MARKETING_VERSION` / `versionName`）。
- ac-android-gradle-bounded-retry: `scripts/build-android.sh` 与 `scripts/test-android.sh` 中不再存在函数体外的裸 `bash android/gradlew` 调用，两处 `assembleDebug` / `testDebugUnitTest` 均经由同一个有界重试函数；函数最多重试 3 次（尝试上限 4），每次重试仅在前一次失败命中网络/下载类特征（如 `Could not download` / `Could not resolve` / `Read timed out` / `Connect timed out` / `Connection refused` / `UnknownHostException` / `SSLException` / `HTTP 5xx` / `network is unreachable`）时发生。
- ac-android-retry-non-network-fails-fast: stub `gradlew` 输出普通编译/测试失败（不含网络特征）时，脚本只尝试 1 次并原样非零退出。
- ac-android-retry-exhausted-exitcode: stub `gradlew` 每次都以网络失败特征非零退出时，脚本尝试次数恰为 4 次（1 次 + 3 次重试）后非零退出，且 `build-android.sh` 的退出码与 stub 的退出码一致；`test-android.sh` 仍以 1 结束并打印 `testDebugUnitTest 失败`。
- ac-android-retry-success-path: stub `gradlew` 第 2 次尝试成功时，重试后脚本继续走原有成功路径（`build-android.sh` 校验 APK 产物；`test-android.sh` 校验 test-results XML 与用例计数），入口语义与既有断言不变。
- ac-check-scripts-static-guards: `bash scripts/check-ios-scripts.sh` 与 `bash scripts/check-android.sh` 均包含上述静态断言且自身有反例自检（沙箱注入违规样本必须 FAIL），全部通过。
- ac-gates-unchanged: `bash scripts/check-baseline.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-android.sh` 全绿；`.munk/code-gates.json` 仍为 22 门且所有 id 与 command 未变。
- ac-workflows-untouched: 本项 diff 中 `.github/workflows/` 下文件数为 0。
- ac-ci-real-green: 推送后 `ios` 与 `android` workflow 各有**本次 headSha** 触发的真实 run，`conclusion=success`，回执附 run id 与 job/step 摘要；旧 run 或本地结果不得作为证据。若重试后仍红，附失败 run id 与日志摘要并停止，不得伪造绿。

## Non-Goals

- 不改 `.github/workflows/*` 的任何触发条件、权限、步骤与命令。
- 不改 Gradle wrapper：`distributionUrl` 版本、`retries=0`、`networkTimeout` 等属性保持原值（重试在脚本层做，不动 wrapper 自带的 `retries` 属性）。
- 不改 `assembleDebug` / `testDebugUnitTest` 入口语义、`blocked:` 降级语义、退出码约定与产物校验。
- 不新增/删除/重排 code gates，不改门 command。
- 不写 Android 业务代码、不碰 iOS 源码、不改 README/VERSION 口径。
- 不把「脚本重试」扩成通用网络重试框架，不引入外部依赖（`curl`、`jq`、`python` 一律不上生产路径）。

## Implementation Constraints

- 可改文件仅：`scripts/version.sh`、`scripts/build-android.sh`、`scripts/test-android.sh`、`scripts/check-ios-scripts.sh`、`scripts/check-android.sh`。
- `version.sh` 读取路径必须基于脚本自身推导的仓库根（`$repo_root/android/gradle/wrapper/gradle-wrapper.properties`），保证任意 cwd 下结果一致；解析用纯 bash/sed/grep，退出码语义与现版一致（0/1/2）。
- `--tools` 输出保持五行固定格式与顺序：`VERSION:` / `Xcode:` / `Swift:` / `JDK:` / `Gradle:`；Gradle 行缺省文案沿用「未就绪（…）」风格。
- 重试函数命名需可被 `check-android.sh` 静态识别（如 `gradle_with_retry`），函数体内保留单次 `bash android/gradlew -p android <task>` 调用；输出必须实时打印（`tee` 到临时日志），不得静默吞掉失败输出。
- 重试间隔保持短且有界（如 1s / 2s / 4s 或统一有限 sleep），不得让 `test-android.sh` 在 CI 上被拖到超时。
- `set -euo pipefail`、`--help`、未知参数退出 2、`bash -n` 通过等既有脚本卫生约束不变；`scripts/check-shell-expansion.sh` 要求裸变量引用后紧跟非 ASCII 字符必须写成 `${var}`（中文 message 里尤其注意）。
- `check-ios-scripts.sh` 的 Gradle 期望值必须**独立**从 wrapper properties 推导（不调用 `version.sh`），否则断言恒真。
- `check-android.sh` 的 stub 反例必须在 `mktemp` 沙箱内完成，不污染仓库、不触网、可重复执行。
