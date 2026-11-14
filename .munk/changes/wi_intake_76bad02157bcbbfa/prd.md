# Android 轨迹敏感信息单独同意门 + 可安装 APK 产物与获取路径

## 范围

### A. 同意门（Compose，与 iOS 同语义）

- 首次启动（无同意记录）以独立同意屏为根视图，不得先落到占位主界面再弹提示。
- 同意屏标题与正文必须写明四件事：轨迹属敏感个人信息、数据只存在本机、可以拒绝、可随时撤回。文案逐条可断言（关键条目字符串命中）。
- 主按钮为「同意」，次操作为「不同意」；两者不可互换主次、不可只留其一。
- 未同意态下不允许开始记录，并给出可读原因（原因文案来自资源）；同意后开跑入口恢复可用。
- 「关于」入口可看政策全文（随包资源，不联网），并可在此撤回同意；撤回后回到未同意态（重启后仍为未同意）。
- 同意状态持久化在设备本地（框架能力即可，例如 SharedPreferences 包裹在可注入的接口后，纯逻辑可做 JVM 单测）。

### B. 文案与视觉

- 同意门/关于页/政策页全部文案进 `android/app/src/main/res/values/strings.xml`（zh-Hans），新增 Kotlin 源码零裸中文字面量。
- 新增 testTag / contentDescription 只增不改：既有占位页的 tag/语义与既有测试断言不得被改写。
- 只用现有 `MaterialTheme` 与既有排版档位；不新增色值档/主题文件/第三方依赖（Compose BOM、material3、activity-compose 之外不加 implementation 依赖，不加新插件）。

### C. 政策正文单一真源

- 真源是 `docs/privacy/privacy-policy-zh-Hans.md`（由并行 iOS 项首建）。Android 侧只做「同步到资源」，不得另写第二份不同正文。
- 当前分支该文件尚不存在：Coding 开工时若仍缺失，**允许且仅允许**创建这一份正文一次（内容覆盖四类关键条目 + 数据删除/联系方式），并在交付回执中显式说明「本项首建了真源文件」；若已存在则逐字沿用、不得改写正文措辞。任何情况下仓内只允许存在这一份政策正文。

### D. 打包与分发（不建 GitHub Release）

- 新增 `scripts/package-android.sh`：`assembleDebug` → 复制 APK 到 `${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/` → 写 `manifest.json` 与 `checksums.txt`，stdout 输出产物绝对路径 + sha256（机器可解析行）。
- 仓外路径硬约束：默认根为 `${TMPDIR:-/tmp}`，允许 `PUREPACE_DIST_ROOT` 覆盖以便反例测试；任何解析结果落在仓库内必须判红拒绝。
- 幂等：同一 commit 连续两次打包输出相同 sha256 与相同目录；重复执行不产生重复目录、不静默覆盖成不同产物。

### E. 门与反例

- `scripts/check-android.sh` 增加契约断言（产物非空、sha256 与文件一致、路径在仓外、幂等、脚本无硬编码凭据、门/工作流接线），每条配「构造错误输入 → 必须红」反例，且反例只用沙箱副本/stub/环境变量构造，不改生产代码。
- 同意门与政策条目断言：未同意不可开始、撤回后不可开始、正文含关键条目、资源正文与真源一致；反例通过喂错状态/削词构造即红，不依赖改生产代码。
- `.munk/code-gates.json` 增加 `package-android` 门（单一 argv：`bash scripts/package-android.sh`）；`.github/workflows/android.yml` 增加 `package` 步骤（复用脚本，`blocked:` 显式 exit 1，禁止 gradlew 直连），并同步 `scripts/check-android-workflow.sh` 的步骤顺序/复用断言与反例。

### F. 文档

- `docs/verification-matrix.md` 只更新/新增本项相关行（接缝、现状、断言名、反例、证据路径、归属项）。
- Android 安装与自测入口写到 `docs/device-manual-acceptance.md` 或 `docs/distribution/` 下；最终面向人的人工测试说明由后续 doc 项统一成稿，本项只给可执行入口（adb 安装命令不含版本字面量、含 sha256 校验与同意门手测步骤）。

## 验收

### 同意门

- ac-consent-first-launch-gate: 无同意记录时启动，同意屏为根视图（`consent.root` 存在），占位主界面的开跑入口不存在或不可点击；同意屏正文（资源解析后）同时含「敏感个人信息」「只存在本机」「可以拒绝」「可随时撤回」四条关键条目。
- ac-consent-blocked-before-agree: 未同意态尝试开始记录，记录态不进入（状态仍为 unattended），且界面出现非空原因文案节点（`consent.blockedReason`），原因来自资源而非空串。
- ac-consent-agree-enables-record: 点击主按钮「同意」后状态变 granted、同意屏消失、开跑入口可点击；持久化后重建界面（新 store 实例）仍为 granted。
- ac-consent-decline-stays-unattended: 点击次操作「不同意」后状态仍 unattended、不写入 granted，界面停留在未同意态并显示原因；重建后仍 unattended。
- ac-consent-withdraw-returns-unattended: 关于页点「撤回同意」并确认后状态回到 unattended，开跑入口再次不可用并出现原因；重建后仍 unattended。
- ac-consent-primary-secondary-order: 「同意」为主按钮、「不同意」为次操作（主/次语义由按钮样式或语义角色断言），二者同时存在且语义不同。
- ac-consent-tests-red-without-prod-change: 同意相关单测内含自证反例（给判定函数喂 granted 态断言「必须拦截」应失败、喂 unattended 态断言「必须放行」应失败、正文断言去掉任一关键条目应失败），全部通过改测试输入取红，不需要改生产代码。
- ac-consent-copy-from-strings: 新增/改动的同意门、关于页 Kotlin 源码不含中文裸字面量（CJK 正则零命中），且这些文件的用户可见 `text =` / `contentDescription =` 一律由 `stringResource(...)` 或资源数组提供；沙箱注入中文裸字面量后该断言必须红。

### 政策

- ac-policy-single-source-sync: 资源中的政策正文逐段等于 `docs/privacy/privacy-policy-zh-Hans.md` 正文（忽略空白/换行差异），沙箱改真源任一段或改资源任一段，断言必须红；仓内不存在第二份政策正文文件。
- ac-policy-bundled-no-network: 政策全文从随包资源渲染，政策页渲染路径不申请网络权限、不新增 INTERNET 权限（Manifest 权限集合与改动前一致）。

### 打包

- ac-package-path-and-layout: `bash scripts/package-android.sh` 产物目录为 `${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/`，内含 debug APK、`manifest.json`、`checksums.txt`；目录绝对路径不在仓库根之下，APK 非空（>0 字节且 `unzip -l` 可读）。
- ac-package-manifest-fields: `manifest.json` 恰含 applicationId（`sh.munk.purepace`）、version（等于根 `VERSION` 内容）、versionCode（整数，与 gradle 配置一致）、commit（HEAD 全 sha）、sha256（与 APK 实测一致）、minSdk 26、targetSdk 36、buildTime（ISO-8601 UTC）；字段集合不得缺失或多出未约定项。
- ac-package-checksums-match: `checksums.txt` 中 APK 的 sha256 与 `shasum -a 256` 实测一致，且 `scripts/package-android.sh` 打印的 `APK=` 绝对路径与 `SHA256=` 行可直接对照；沙箱篡改 checksums.txt 后断言必须红。
- ac-package-idempotent-same-commit: 同一 commit 连续两次执行打包，APK sha256 相同、目录相同、不新增目录；sha256 不同或出现第二个目录必须红（若底层 debug 构建非字节可复现，须在回执中给出差异根因与实测两次 sha，不得放宽断言或隐藏）。
- ac-package-no-hardcoded-credentials: 脚本及打包路径无 `storePassword`/`keyPassword`/`signingConfig` 明文凭据（正则零命中），仅 debug 签名；沙箱注入 `--ks-pass=...` 类明文后断言必须红。
- ac-package-red-proofs: `check-android.sh` 沙箱反例实测取红并点名对应 ac：空 APK → ac-package-path-and-layout；篡改 checksums → ac-package-checksums-match；`PUREPACE_DIST_ROOT` 指向仓库内 → ac-package-path-and-layout（路径在仓外）；注入明文口令 → ac-package-no-hardcoded-credentials；第二次打包产物 sha 变化 → ac-package-idempotent-same-commit。

### 门与接线

- ac-gates-package-wired: `.munk/code-gates.json` 含且仅含一个新的 `package-android` 门，`command` 为单一 argv `bash scripts/package-android.sh`；既有门 id 与 command 零改动（含非 Android 门）；沙箱删除该校验后断言必须红。
- ac-android-workflow-package-step: `android.yml` 的 `package` 步骤位于 `build` 之后，run 内只经 `bash scripts/package-android.sh`（无 `gradlew` 直连），且 `blocked:` 分支显式 `exit 1`；`check-android-workflow.sh` 的步骤顺序/复用断言同步纳入 package，并附「删掉 package 步骤 → 必须红」反例。
- ac-android-local-green: 本机 `bash scripts/check-android.sh`、`bash scripts/build-android.sh`、`bash scripts/test-android.sh`、`bash scripts/package-android.sh` 全部 exit 0，且 `test-android.sh` 报告的 JVM 与 Robolectric/Compose 两类用例均 ≥1（新增用例计入，不写死条数）。
- ac-android-ci-green: 同一 commit 的 `.github/workflows/android.yml` 全绿（install/lint/test/build/package 五步），回执附 run 标识与各步结论；未跑通不得写成通过。

### 文档

- ac-docs-matrix-rows: `docs/verification-matrix.md` 含同意门与打包两条新行，断言名与代码中的实际断言名一致、反例列写明构造输入、证据路径指向真实脚本/日志、归属项为本 workItemId。
- ac-docs-install-entry: `docs/device-manual-acceptance.md`（或 `docs/distribution/android.md`）含 Android 安装与自测入口：产物路径按 `<versionName>-<versionCode>` 占位描述、`adb install -r` 命令、sha256 校验命令、同意门手测顺序（首启拦截 → 同意 → 撤回 → 不再拦截消失），且不含版本号字面值。

## 非目标

- 不做 release 签名、不上架、不建 GitHub Release、不做 Play/应用商店材料、不上传 CI artifact。
- 不改 `applicationId`（仍由 `android/gradle.properties` 单点定义 `sh.munk.purepace`）、不改 `VERSION` 数值、不改 `versionCode` 语义（仍为 1 且不引入自动递增）。
- 不引入第三方插件、新运行时依赖、新设计 token/色值档/主题文件、Android Lint/detekt/ktlint 等新工具链。
- 不改 `ios/` 任何文件；不建第二份政策正文；不顺手重构既有占位页文案（`PlaceholderCopy` 保持现状）。
- 不做真实记录/定位/TTS/历史等业务功能，同意门的「开始记录」仍以占位入口承载语义，不实现跑步逻辑。

## 实现约束

- 环境事实：`JAVA_HOME` 指向 zulu-21、`ANDROID_HOME=ANDROID_SDK_ROOT=$HOME/Library/Android/sdk`（含 platforms/android-36、build-tools/36.0.0）；构建一律走 `android/gradlew`，不写死绝对路径、不写 `local.properties`。
- 脚本形态沿用既有约定：`#!/usr/bin/env bash` + `set -euo pipefail` + `usage()`（`-h|--help` → 0，未知参数 → 2）+ `BASH_SOURCE` 推导 `repo_root`；复用 `build-android.sh` 的 JDK/SDK 前置校验与 `gradle_with_retry`（网络类失败 1+3 次、其余 1 次），不新增外部依赖（不引入 jq/python，manifest.json 用 printf 生成、sha256 用 `shasum -a 256`，按平台回退 `sha256sum`）。
- 脚本/README/文档不得出现根 `VERSION` 字面值（`check-baseline.sh`/`check-ios-scripts.sh` 会扫描）；`versionName`/`versionCode` 从 gradle 产物或配置期派生，不抄字面量。
- Gradle 汇总行沿用 `sed -E 's/actionable tasks:/actionable steps:/'` 改写，规避 Host turbo 缓存启发式；产物目录（`android/app/build/`、`${TMPDIR}/purepace-dist/`）不得入库。
- 幂等的落地口径：打包前清空目标目录、固定 zip/构建输入（不写随机 buildTime 进 APK），`manifest.json` 的 buildTime 允许两次不同（它不进 APK、不进 sha256 断言），但 APK sha256 必须相同；若 AGP debug 构建实测非字节可复现，先尝试不改变构建语义的确定性手段（如固定 `SOURCE_DATE_EPOCH`/禁用不必要的时间戳写入），仍不可复现则如实回执红因，不得改为「只比大小」。
- 同意状态与政策正文的取值口径：判定函数（如 `consentGateVerdict(state)`）与文案 key 常量集中在单文件，测试可喂任意状态；Compose 测试用 Robolectric + `createComposeRule`（已在依赖内），纯逻辑状态机用 JVM JUnit。
- 资源正文同步：政策 md 正文 → `strings.xml`（建议 `string-array` 逐段），`check-android.sh` 用与 Coding 同一规范化规则（去首尾空白、合并空行）比对，避免「肉眼一致但断言不可判」。
- 既有断言维护：`check-android.sh` 的 `ac-check-android-gates-integrity` 目前写死「Android 三门」，新增 `package-android` 后必须改为「四个门 + 其余门零改动」并保留反例；`check-android-workflow.sh` 的 `expected` 步骤数组需加入 `package`，并保持 `ac-test-build-reuse-scripts`（禁止 `gradlew` 直连）不变。
- 提交按面拆分（code / fold / prd），回执写实际命令、产物路径与 sha256、门红绿原文；未跑齐的腿如实记录，不写「CI 通过」除非拿到同 commit run 证据。
