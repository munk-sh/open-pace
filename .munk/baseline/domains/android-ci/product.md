# Domain: android-ci

Android 远端 CI 域：以单个 GitHub Actions workflow 承载 Android 的 install / lint / test / build 远端门，全部复用既有本地脚本，不复制第二套构建或测试命令。本域只做 CI 编排、workflow 结构断言与远端 run 证据口径，不改 `android/` 工程、不改既有脚本契约、不含任何业务实现。

## 范围

- `.github/workflows/android.yml`：`name: android`；触发为 `on.push`（不限分支）与 `workflow_dispatch`；`permissions.contents: read`；单 job `runs-on: ubuntu-latest`（可设 `timeout-minutes` 上限）；步骤固定 `checkout` → `install` → `lint` → `test` → `build`。
- `install` 步负责 runner 前置且幂等：`actions/setup-java@v4`（temurin，`java-version: '21'`）、`android-actions/setup-android@v3` 提供 SDK/`sdkmanager`，再确保 `platforms;android-36` 与 `build-tools;36.0.0` 已装；随后显式校验 `java` 主版本为 21、`ANDROID_HOME` 目录存在、两个 SDK 子目录存在，任一不符即非零退出（不赌 runner 默认值）。
- `lint` 步逐条调用既有本地门：`bash scripts/check-baseline.sh`、`bash scripts/check-android.sh`，各自独立命令行，不合并成长 `&&` 串，不新增空转门、不新增 Gradle `lintDebug` / detekt / ktlint。
- `test` / `build` 步分别执行 `bash scripts/test-android.sh` / `bash scripts/build-android.sh` 并透传输出；捕获到 `blocked:` 一律判失败（显式 `exit 1`），否则以脚本退出码为准。
- `scripts/check-android-workflow.sh`：本机 workflow 结构/语法断言（bash、`set -euo pipefail`、`--help`、幂等、以仓库根为路径基准），用本机已有 `ruby -ryaml`（回退 `python3`）解析 YAML，并内置反例自检（改错 `runs-on`、删除 `test` 步骤、去掉 `push` 触发、去掉 `blocked:` 失败口径时必须拒绝）。
- `.munk/code-gates.json`：新增单一 argv 门 `lint-android-workflow` → `bash scripts/check-android-workflow.sh`，`cwd` 为 `.`；既有门 id 与 command 逐字节不变。
- 远端证据口径：由 Delivery 经 Host 工具只推本分支触发 Actions；run 出后用 `gh run list --repo munk-sh/open-pace --workflow android.yml` / `gh run view <id>`（或 Host CI 通道）取真实 run id 与 conclusion；run 未出前如实记 `pending: 待 remote 验证`。

## 验收

- ac-workflow-exists-and-parses: `.github/workflows/android.yml` 存在，可被本机已有解释器（`ruby -ryaml` 或 `python3`）解析，含 `name` / `on` / `jobs` 顶层键；不引入 actionlint 等新工具依赖。
- ac-workflow-push-trigger: `on` 含 `push` 且未被 `tags` 或分支白名单排除（推任意分支即触发），并含 `workflow_dispatch`；不得只挂 `pull_request`。
- ac-workflow-single-ubuntu-job: 只有一个 job，`runs-on` 为 `ubuntu-latest`，且 `permissions.contents` 为 `read`。
- ac-install-provisions-jdk21-and-sdk: `install` 步显式装载 JDK 21（`actions/setup-java` 的 `java-version: '21'` 或等价显式声明），并确保 `platforms;android-36`、`build-tools;36.0.0` 已安装与 `ANDROID_HOME` 可用；步内存在显式校验（java 主版本 21、SDK 目录存在），不依赖 runner 默认值。
- ac-workflow-step-order: job steps 中 `install`、`lint`、`test`、`build` 按此顺序出现，每步 `run` 非空。
- ac-lint-step-reuses-local-gates: `lint` 步调用 `bash scripts/check-baseline.sh` 与 `bash scripts/check-android.sh`，两者为独立命令行，真实执行既有断言。
- ac-test-build-reuse-scripts: `test` 步执行 `bash scripts/test-android.sh`，`build` 步执行 `bash scripts/build-android.sh`；workflow 内不出现绕过脚本的第二套 `gradlew assembleDebug` / `gradlew testDebugUnitTest` 调用。
- ac-workflow-structural-gate: `bash scripts/check-android-workflow.sh` 退出 0，覆盖 YAML 解析与上述结构断言，并含 ≥3 条内置反例自检（改错 `runs-on`、删 `test` 步、去 `push` 触发时断言 FAIL 且非零退出，恢复后 PASS）；`.munk/code-gates.json` 中 `lint-android-workflow` 的 `command` 为单一 argv、`cwd` 为 `.`。
- ac-existing-gates-unchanged: `.munk/code-gates.json` 既有门（含 `lint-android` / `build-android` / `test-android` / `test`）的 id 与 command 逐字节未变，`bash scripts/check-baseline.sh`、`bash scripts/check-android.sh` 仍退出 0。
- ac-no-version-literal: 新增的 workflow 与 `scripts/check-android-workflow.sh` 不出现根 `VERSION` 当前字面值，版本只经 `scripts/version.sh` 取得。
- ac-scope-no-app-change: 改动只落在 `.github/workflows/android.yml`、`scripts/check-android-workflow.sh`、`.munk/code-gates.json`（及 `.munk/changes/**`）；`ios/**`、`android/**`、`shared/**`、`scripts/build-android.sh`、`scripts/test-android.sh`、`scripts/check-android.sh` 零改动。
- ac-branch-only-push: Delivery 只经 Host 工具推本分支触发 Actions；不推 tag、不建 Release、不改 remote URL、不新增 remote、不向远端 seed（`git tag -l` 无新增、`git remote -v` 与推送前一致）。
- ac-real-green-run-id: run 产出后证据必须是真实 run：`conclusion=success`、带数字 run id 与 workflow 名 `android`，来源为 `gh run list --repo munk-sh/open-pace --workflow android.yml` / `gh run view <id>` 或 Host CI 通道原始输出摘要。
- ac-pending-honest: run 尚未产出（排队/未触发）时，交付摘要逐字记录 `pending: 待 remote 验证`，不得写成「CI 绿」/`blocked`，不得用本地门结果替代远端 run。
- ac-ci-red-blocks-delivery: run 为 `failure`/`cancelled` 时本项不交付，摘要附失败 run id 与失败步骤日志摘要；修复后重新推送取新绿色 run，不沿用旧 run。
- ac-empty-remote-escalation: 若 Delivery 因「远端无默认分支 / 空仓」报错，把错误原文整段写入摘要并回报 Owner，不改用其他 git 工具反复重试。
- ac-no-fake-ci-wording: 摘要、脚本与文档不出现「CI 通过」「CI 已通过」「真机已验证」等未经 run id 支撑的措辞。

## 非目标

- 不改 `android/` 工程：Gradle/AGP/依赖版本、SDK 声明、首屏 Compose、测试用例一律不动；CI 暴露工程缺陷时按 `blocked:` 记录实测命令与原始错误回报，不顺手改工程。
- 不改 `scripts/build-android.sh` / `test-android.sh` / `check-android.sh` 契约，不改 `scripts/version.sh`；不为迎合 runner 放宽任何本机断言。
- 不做 `.github/workflows/ios.yml` 或任何 iOS/`shared/` 改动；不写业务实现。
- 不引入 actionlint / fastlane / 依赖缓存 / 构建产物上传 / 覆盖率等附加设施；不加矩阵构建、多 JDK 或 macOS job。
- 不设置分支保护、required checks、secrets、environment 或任何仓库设置类变更；不推 tag、不建 Release、不改 remote、不 seed。
- 不做模拟器/真机安装、`connectedAndroidTest`、签名、Release/AAB；不做视觉设计与业务功能。
- 不改 `README.md`（本项无 CI 文档需求）。

## 实现约束

- 本机环境事实：`origin` = `https://github.com/munk-sh/open-pace.git`，远端已有默认分支 `main`，本地无 tag；YAML 解析可用 `ruby -ryaml`（Psych 3.1.0），`python3` 无 PyYAML，无 `actionlint`，`gh` 2.97.0 可用。断言脚本按「ruby 优先、python3 回退」实现，两者都不可用即失败并提示，不得静默跳过。
- Psych 遵循 YAML 1.1，会把裸 `on:` 解析成布尔 `true`；断言脚本需按原文或别名键处理，避免误判「缺 on」。
- 本地 `check-android.sh` / `check-baseline.sh` 仅用 bash/sed/awk/grep/find/node/git，Linux runner 可直接运行；`android/gradlew` 已入库且权限 100755。
- `scripts/build-android.sh` / `test-android.sh` 要求 `JAVA_HOME` 指向 JDK 21 且 `ANDROID_HOME`/`ANDROID_SDK_ROOT` 目录存在，缺一即 fail fast；CI 侧须由 `install` 步显式满足。
- workflow 形态：步骤命名固定 `checkout` / `install` / `lint` / `test` / `build`；`lint` 只复用两条本地门；不引入缓存/上传步骤，首次 Robolectric 下载慢属预期，不因超时放宽断言（可设 job `timeout-minutes` 上限但不得跳过测试）。
- 脚本形态对齐既有脚本：`#!/usr/bin/env bash` + `set -euo pipefail` + `usage()` + `BASH_SOURCE` 推导仓库根 + `--help` 退出 0 / 未知参数退出 2 + `[PASS]/[FAIL]` 逐条输出与汇总。
- 门禁口径：`lint-android-workflow` 单一 argv（无 `&&`、`|`、`;`、重定向、反引号），`cwd` 为 `.`；`check-android.sh` 对既有门映射的逐字节断言仍须 PASS。
- 推送与证据：网络 git 操作统一 `env -u GIT_EXEC_PATH git ...`；Delivery 只推本分支 `munk/{workItemId}` 触发 `on.push`，一次推送后轮询 `gh run list`，取不到即记 `pending: 待 remote 验证`，不为等 run 反复推空提交；只报真实命令输出摘要、run id 与 conclusion，不以本地绿替代远端 run。

## 最近交付证明

- workItemId: wi_ws_81dd4c38fb89a06d（2026-11-07，pass）
- 交付：`.github/workflows/android.yml`（`name: android`；`on.push` + `workflow_dispatch`；`permissions.contents: read`；单 job `ubuntu-latest` + `timeout-minutes: 45`；`checkout` → `install`（setup-java temurin 21 + setup-android + `platforms;android-36` / `build-tools;36.0.0` + java 主版本与 `ANDROID_HOME`/SDK 目录显式校验）→ `lint`（独立调用 `check-baseline.sh`、`check-android.sh`）→ `test` / `build`（复用 `test-android.sh` / `build-android.sh`，`blocked:` 判失败））；`scripts/check-android-workflow.sh`（结构断言 + 4 类反例自检，ruby/python3 解析回退）；`.munk/code-gates.json` 新增 `lint-android-workflow`，既有门 id/command 未变。
- 验证：code_gates 全绿（含新增 `lint-android-workflow`、`check-baseline.sh`、`check-android.sh`）；`android/**`、`ios/**`、`shared/**` 与三个既有 Android 脚本零改动；本域不承载远端 run 状态 —— 本分支首次推送后由 Actions 触发的真实 run 状态记 `pending: 待 remote 验证`，未取得 run id 前不声称 CI 结果。
