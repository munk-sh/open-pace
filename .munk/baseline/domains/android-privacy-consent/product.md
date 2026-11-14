# Domain: android-privacy-consent

Android 轨迹敏感信息单独同意门 + 政策正文单一真源 + 可安装 debug APK 产物域。同意门是 Compose 根视图契约（未同意不得开跑），政策正文以 `docs/privacy/privacy-policy-zh-Hans.md` 为唯一真源并逐段同步进 `strings.xml`，打包脚本只出仓外 debug 产物、不签名不分发。本域不含真实记录/定位/历史业务实现。

## 范围

- 同意门：`android/app/src/main/java/dev/purepace/` 下 `ConsentContract.kt`（判定函数 `evaluateStart` + tag 常量 `CONSENT_ROOT_TAG` / `BLOCKED_REASON_TAG` / `AGREE_TAG` / `DECLINE_TAG` / `WITHDRAW_TAG` / `WITHDRAW_CONFIRM_TAG`）、`ConsentStore.kt`（`interface ConsentStore` + `SharedPreferencesConsentStore` 持久化）、`PurePaceApp.kt`（同意屏 / 主界面 / 关于页 / 政策页）、`MainActivity.kt`（注入 store 并以 `PurePaceApp` 为根）。
- 状态口径：仅 `unattended` 与 `granted` 两态；「不同意」不写 `granted`；撤回回到 `unattended` 且重启后仍成立。
- 文案：`android/app/src/main/res/values/strings.xml`（zh-Hans）承载同意屏四条目（敏感个人信息 / 只存在本机 / 可以拒绝 / 可随时撤回）、主次按钮、拦截原因、关于页与撤回确认；新增/改动 Kotlin 源码零中文裸字面量，用户可见文案一律 `stringResource(...)` 或资源数组。
- 政策：真源 `docs/privacy/privacy-policy-zh-Hans.md`（iOS 隐私项首建，本域逐字沿用、不改写措辞），`string-array privacy_policy_paragraphs` 逐段同步；关于页随包渲染，政策/同意门渲染路径无网络调用、Manifest 不新增 `uses-permission`。
- 打包：`scripts/package-android.sh` → `${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/`，内含 debug APK、`manifest.json`、`checksums.txt`；stdout 输出 `APK=` / `SHA256=` / `DIST_DIR=` 机器可解析行；产物路径解析结果落在仓库内即判红拒绝；该版本目录**已存在时绝不覆盖/删除/改名**，本次自动改用兄弟目录 `<versionName>-<versionCode>-b<N>`（N = 已存在最大序号 + 1，基名算 1），选中目录若已被占（序号竞争）即非零退出。
- 门与接线：`.munk/code-gates.json` 新增单一 argv 门 `package-android`（`bash scripts/package-android.sh`），本地门总数 22 → 23，既有门 id/command 零改动；`.github/workflows/android.yml` 在 `build` 之后新增 `package` 步（run 内只经脚本、`blocked:` 显式 `exit 1`）；`scripts/check-android.sh` / `scripts/check-android-workflow.sh` 同步纳入门接线与步骤顺序/复用断言及反例。
- 文档：`docs/distribution/android.md` 给安装与同意门手测入口（不含版本号字面值）；`docs/verification-matrix.md` 增「轨迹敏感信息单独同意门」「可安装 APK 产物与获取路径」两行；`ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift` 用结构不变量（不 pin 全局行数、每个已声明接缝恰 1 行、归属列须 `wi_`）替代字面量计数。

## 验收

- ac-consent-first-launch-gate: 无同意记录时启动，同意屏为根视图（`consent.root` 存在），占位主界面开跑入口不存在或不可点击；正文（资源解析后）同时含四条目。
- ac-consent-blocked-before-agree: 未同意态尝试开始记录，记录态不进入（仍 `unattended`），界面出现非空原因节点（`consent.blockedReason`）且文案来自资源。
- ac-consent-agree-enables-record: 点主按钮「同意」后状态变 `granted`、同意屏消失、开跑入口可点击；新建 store 实例（模拟重启）仍 `granted`。
- ac-consent-decline-stays-unattended: 点「不同意」后仍 `unattended`、不写 `granted`，停留未同意态并显示原因；重建后仍 `unattended`。
- ac-consent-withdraw-returns-unattended: 关于页「撤回同意」并确认后回到 `unattended`，开跑入口再次不可用并出现原因；重建后仍 `unattended`。
- ac-consent-primary-secondary-order: 「同意」为主按钮、「不同意」为次操作，二者同时存在且语义角色不同。
- ac-consent-tests-red-without-prod-change: 单测内含自证反例（给判定函数喂 `granted` 断言「必须拦截」、喂 `unattended` 断言「必须放行」、正文去掉任一关键条目），全部改测试输入即取红。
- ac-consent-copy-from-strings: 同意门/关于页 Kotlin 源码 CJK 正则零命中，可见文案全部由资源提供；沙箱注入中文裸字面量后断言必红。
- ac-policy-single-source-sync: 资源政策正文逐段等于 `docs/privacy/privacy-policy-zh-Hans.md`（忽略空白差异），沙箱改真源任一段必红；`docs/privacy` 下只允许这一份正文。
- ac-policy-bundled-no-network: 政策全文从随包资源渲染，Manifest 权限集合与改动前一致（无 `uses-permission`），渲染路径无网络 API。
- ac-package-path-and-layout: 产物目录为 `${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/`，含非空 debug APK、`manifest.json`、`checksums.txt`，绝对路径不在仓库根之下。
- ac-package-manifest-fields: `manifest.json` 恰含 applicationId（`sh.munk.purepace`）、version（= 根 `VERSION`）、versionCode（整数，与 gradle 一致）、commit（HEAD 全 sha）、sha256（与 APK 实测一致）、minSdk 26、targetSdk 36、buildTime（ISO-8601 UTC），不多不少。
- ac-package-checksums-match: `checksums.txt` 的 sha256 与实测一致，且与脚本打印的 `APK=` / `SHA256=` 行可直接对照；篡改 checksums 后必红。
- ac-package-existing-dir-sibling: 目标 `<versionName>-<versionCode>/` 已存在时零参数运行退出 0 且既有目录三个文件字节逐字不变（不覆盖 / 不删除 / 不改名），本次落到 `<versionName>-<versionCode>-b<N>`（N = 已存在最大序号 + 1）；再跑一次落到 `-b3`（序号单调，不新开基名目录）；stdout 打印「本次实际输出目录」与 `DIST_DIR=`。
- ac-package-existing-dir-red-proof: 从生产脚本副本中删掉 `# guard-begin: preserve-existing-dist` … `# guard-end: preserve-existing-dist` 区间后，同一「既有目录」现场退出 0 且覆盖掉既有目录 → 证明 ac-package-existing-dir-sibling 的绿由守卫触发；该自检在 `check-android.sh` 内实跑，不靠人工日志。
- ac-package-sha-self-check-scoped: sha256 判据只作用于本次产物目录内——写完 `checksums.txt` 立即 `shasum -a 256 -c` 自校验，与本次 APK 字节不一致即非零退出；**不做跨构建 / 跨环境 sha256 比对**（Android APK 构建实测不可复现），旧「同 commit 跨构建 sha 必须相等」判据取消，并保留「旧判据同场景必红」的对照自检。
- ac-package-no-hardcoded-credentials: 脚本与打包路径零 `storePassword` / `keyPassword` / `signingConfig` 明文，仅 debug 签名；沙箱注入明文口令后必红。
- ac-package-red-proofs: 空 APK / 篡改 checksums / `PUREPACE_DIST_ROOT` 指向仓内 / 注入明文口令 / 既有目录被覆盖（去守卫副本必绿对照组），逐条沙箱反例取红并点名对应 ac。
- ac-gates-package-wired: `.munk/code-gates.json` 含且仅含一个新的 `package-android` 门且 `command` 为单一 argv，既有门（含非 Android 门）零改动；沙箱删除该校验后必红。
- ac-android-workflow-package-step: `android.yml` 的 `package` 步在 `build` 之后，run 内只经 `bash scripts/package-android.sh`（无 `gradlew` 直连），`blocked:` 分支显式 `exit 1`；`check-android-workflow.sh` 的顺序/复用断言同步纳入并附「删掉 package 步 → 必红」反例。
- ac-android-local-green: `check-android.sh` / `build-android.sh` / `test-android.sh` / `package-android.sh` 全部 exit 0，且 JVM 与 Robolectric/Compose 两类用例均 ≥1。
- ac-android-ci-green: 同 commit 的 `android` workflow 全绿时附真实 run id 与各步结论；未取到如实记 `pending: 待远端复核`。
- ac-docs-matrix-rows: `docs/verification-matrix.md` 含同意门与打包两行，断言名与代码中实际断言名一致，反例列写明构造输入，归属项为本 workItemId。
- ac-docs-install-entry: `docs/distribution/android.md` 含产物路径占位描述、`adb install -r`、sha256 校验命令、同意门手测顺序（首启拦截 → 同意 → 撤回 → 不再拦截），且不含版本号字面值。

## 非目标

- 不做 release 签名、不上架、不建 GitHub Release、不做商店材料、不上传 CI artifact。
- 不改 `applicationId`（仍由 `android/gradle.properties` 单点定义 `sh.munk.purepace`）、不改 `VERSION` 数值、不改 `versionCode` 语义（仍为 1、不自动递增）。
- 不引入第三方插件 / 新运行时依赖 / 新设计 token、色值档、主题文件 / Android Lint、detekt、ktlint 等新工具链。
- 不改 `ios/` 业务源码；不建第二份政策正文；不重构既有占位页文案（`PlaceholderCopy` 保持现状）。
- 不实现真实记录 / 定位 / TTS / 历史业务；「开始记录」仍以占位入口承载语义。

## 实现约束

- 环境事实：`JAVA_HOME` 指向 zulu-21，`ANDROID_HOME` = `ANDROID_SDK_ROOT` = `$HOME/Library/Android/sdk`（含 platforms/android-36、build-tools/36.0.0）；构建一律走 `android/gradlew`，不写死绝对路径、不写 `local.properties`。
- 脚本形态沿用既有约定：`#!/usr/bin/env bash` + `set -euo pipefail` + `usage()`（`-h|--help` → 0，未知参数 → 2）+ `BASH_SOURCE` 推导 `repo_root`；复用 `build-android.sh` 的 JDK/SDK 前置校验与 `gradle_with_retry`（网络类失败 1+3 次、其余 1 次）；不引入 jq/python（`manifest.json` 用 printf 生成、sha256 用 `shasum -a 256` 并按平台回退 `sha256sum`）。
- 目录守卫落地：守卫块用注释标记 `# guard-begin: preserve-existing-dist` / `# guard-end: preserve-existing-dist` 包住（标记不参与运行语义，仅供门脚本按区间删除做反例）；守卫内**不得**出现 `rm -rf` 既有目录；`manifest.json` 的 buildTime 不入 APK、允许两次不同；APK 字节判据只在本次目录内自校验，不得因跨环境 sha 差异判红，也不得改成「只比大小」。
- 脚本保留字面量（`check-android.sh` 静态断言依赖）：`PUREPACE_DIST_ROOT`、`purepace-dist/android`、`manifest.json`、`checksums.txt`、`printf 'APK=%s`、`printf 'SHA256=%s`、`shasum -a 256`、「仓库外」。
- 政策同步可比口径：`check-android.sh` 用与 Coding 同一规范化规则（去首尾空白、合并空白、丢标题行）逐段比对；反例用沙箱副本 sed 篡改，并额外 `cmp -s` 断言篡改样本与真源确有差异，避免 sed 未命中导致反例空转。
- 无业务实现断言按源码口径（`--include='*.kt' --include='*.java'`）扫 `src/main`：政策正文是随包资源，其中「导出为 GPX 或 TCX 文件」措辞来自真源逐字沿用（受 ac-policy-single-source-sync 约束），不构成业务实现；Manifest 权限扫描与跨端框架扫描范围不变。
- 脚本/README/文档不得出现根 `VERSION` 字面值；`versionName` / `versionCode` 从 gradle 配置期派生。
- Gradle 汇总行沿用 `sed -E 's/actionable tasks:/actionable steps:/'` 改写以规避 Host turbo 缓存启发式；`android/app/build/` 与 `${TMPDIR}/purepace-dist/` 不入库。
- 远端证据口径：推送后用 `gh run list` / `gh run view` 或 Host CI 通道取真实 run id 与 conclusion；取不到逐字记 `pending: 待远端复核`，禁止编造。

## 最近交付证明

- workItemId: wi_intake_8cf34194e113d153 / at: 2026-11-15T06:00:00+08:00 / status: pass
- 交付：`scripts/package-android.sh` 去掉 `rm -rf` 原地覆盖，改为守卫块 `preserve-existing-dist`——既有版本目录一律不动（不覆盖/删除/改名），本次落 `<versionName>-<versionCode>-b<N>`（N = 已存在最大序号 + 1），并打印「本次实际输出目录」/`DIST_DIR=`；sha256 判据收口到目录内 `shasum -a 256 -c checksums.txt` 自校验，取消跨构建 sha 等值比对（CI 实测两个不同 sha256）。CLI 契约不变：`--help` → 0（含「兄弟目录」/`-b<N>`）、未知参数 → 2、仓内路径仍拒。`scripts/check-android.sh` 新增 `ac-package-existing-dir-sibling` / `-monotonic` / `-red-proof`（去守卫区间必绿对照）/ `ac-package-sha-self-check-scoped`（旧判据必红对照）/ `ac-package-cli-contract-preserved`，断言 30 → 34 项。
- 验证：`check-android.sh` 34 项全绿、`check-baseline.sh` 29 项全绿；`code_gates` 23 门全绿（attempt 002，含 `package-android`）。
- 偏离：原计划「默认拒绝覆盖 + 显式 `--force`」被实现推翻，改为零参数兄弟目录（既有产物零改动、确定性更强、无需开关）；盘上基名目录 `0.1.0-1/` 未改名/删除/搬迁，APK sha256 仍 `8b80c8e2…990e0`；清理/归档策略仍未做。
