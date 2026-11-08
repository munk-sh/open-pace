# Domain: repo-baseline

仓库协作底座：版本单一真源、脚本入口（含 iOS 构建/测试/脚本契约）、协作文档、官方 skill 安装与门禁定义。不承载任何跑步业务实现，也不创建 iOS/Android 应用工程。

## 范围

- 根 `VERSION` 为仓库唯一版本真源；`scripts/version.sh` 是读取版本的唯一入口（`README.md`、`scripts/*.sh` 不得写死版本字面值）。
- `scripts/check-baseline.sh` 以可执行结构断言覆盖本域验收（VERSION 格式、无硬编码版本、`AGENTS.md` 四节、skill 路由与磁盘双向一致、iOS+Android skill 存在），同时充当 `code-gates` 的 `test` 门。
- 薄 `README.md`（定位、冻结技术栈、构建/测试入口、版本说明、指向 `AGENTS.md`）与仓库根薄 `AGENTS.md`（技术栈与核心库 / 目录约定 / 测试金字塔 / `.agents/skills` 路由表）。
- `.agents/skills/` 仓库内本地安装的官方 skill（iOS/SwiftUI 与 Android 各至少一个），与 `AGENTS.md` 路由表双向一一对应。
- `scripts/version.sh`：无参保持单行版本输出；新增 `--tools` 追加根 `VERSION` 与 Xcode / Swift / JDK / Gradle 摘要，工具缺失显式标注「未就绪」，不报错、不伪造版本。
- `scripts/build-ios.sh` / `scripts/test-ios.sh`：按 `ios/PurePace.xcodeproj`（或 `ios/project.yml` + 本机 `xcodegen`）可用性自动分支。工程可用走 `xcodebuild build|test -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16'`（派生数据落 `.build/ios`）；不可用输出 `blocked:` 原因并降级真实执行 `swift build|test --package-path ios/Core`，以该命令退出码为准。
- `scripts/check-ios-scripts.sh`：上述三脚本的静态契约断言（`bash -n`、`set -euo pipefail`、`--help` 退出 0、未知参数退出 2、无版本字面值、无伪造成功行、含 xcodebuild/destination 契约字面量）。
- `.munk/code-gates.json`：真实可执行门 `lint` / `lint-baseline` / `lint-ios-core` / `lint-ios-scripts` / `build-ios-core` / `build-ios` / `test-ios-core` / `test-ios` / `test`；`test` 仍为 `bash scripts/check-baseline.sh`。Android build/test 门由 Android 骨架子项追加；`check-shell-expansion` 与 `verify-ios-sim-runtime`（模拟器三链路编排，编排口径见 `ios-shell` 域）为 append-only 追加，既有门 id/command 逐字不变。
- `scripts/check-shell-expansion.sh` + `check-shell-expansion` 门：变量展开卫生静态门，扫描 `scripts/**/*.sh`、`android/**` 的 shell 文件（含无扩展名 `android/gradlew`）与 `.github/workflows/*.yml|*.yaml` 的非注释行，禁止裸 `$var` 紧跟非 ASCII 字节；本域持有该门的范围/豁免/退出码契约，跨域脚本（Android、shared、CI 侧）只做 `${var}` 包裹，不改入口语义与退出码。

## 验收

- ac-version-file-single-source: 仓库根 `VERSION` 单行匹配 `^[0-9]+\.[0-9]+\.[0-9]+$`，初始 `0.1.0`，无 `v` 前缀、无 BOM、无空行。
- ac-version-script-reads-file: `bash scripts/version.sh` 退出码 0，stdout 去换行等于 `VERSION` 内容；修改 `VERSION` 后输出随之变化（证明未缓存、未硬编码）。
- ac-no-hardcoded-version: `README.md` 与 `scripts/*.sh` 不出现 `VERSION` 的字面值；`scripts/version.sh` 的版本来源只有读取 `VERSION` 文件一条路径。
- ac-agents-four-sections: `AGENTS.md` 含「技术栈」「目录约定」「测试金字塔」「skill 路由」四节标题且各节正文非空。
- ac-test-pyramid-doc: 测试金字塔节写明 L1 落点（`ios/Core/Tests` 的 `swift test`、`android/app/src/test` 的 JVM JUnit）与 L2 落点（`ios/PurePaceUITests` 的 XCUITest、Android Robolectric 或 Compose UI test），并给出单跑（`swift test --filter` / `xcodebuild test -only-testing:` / `./gradlew testDebugUnitTest --tests`）与全跑入口。
- ac-skill-routing-matches-disk: 路由表条目均真实存在于磁盘且含非空 `SKILL.md`，磁盘 skill 目录也都在表中出现（双向一一对应，无悬空条目）。
- ac-skills-ios-android: `.agents/skills/` 至少各有一个 iOS/SwiftUI 与 Android 对应 skill，`SKILL.md` 非空，不得以无关 skill 凑数。
- ac-skills-not-global: 安装只落仓库内 `.agents/skills/`，未用 `-g` / `--global`，未写 `~/.agents` 或全局目录。
- ac-code-gates-test-real: `code-gates.json` 含 `lint` 与 `test` 门，command 均为单一 argv（无 `&&`/`||`/`|`/`;`/重定向）；`test` 真实执行 `scripts/check-baseline.sh`，本机退出码 0，且人为改坏断言后能非零退出。
- ac-no-business-code: 新增文件仅限 `VERSION`、`README.md`、`AGENTS.md`、`.agents/skills/**`、`scripts/*.sh`、`.munk/code-gates.json`；不出现任何跑步业务实现、占位以外的样例/种子数据或 `ios/`、`android/` 应用工程。
- ac-version-bare-unchanged: `bash scripts/version.sh` 退出 0 且 stdout 去换行等于根 `VERSION` 内容；`bash scripts/version.sh --help` 退出 0。
- ac-version-tools-report: `bash scripts/version.sh --tools` 退出 0，输出同时含根 `VERSION` 值、Xcode 版本（与 `xcodebuild -version` 首行数字一致）、Swift 版本（与 `swift --version` 的 `Apple Swift version x.y.z` 一致）、JDK 行与 Gradle 行；工具缺失时该行显式标注未就绪（无 `android/gradlew` 时 Gradle 行标注未就绪），任一行缺失即失败。
- ac-version-tools-idempotent: 连续两次 `bash scripts/version.sh --tools` 输出逐字节相同（不含时间戳、随机数、与路径相关的变量）。
- ac-ios-scripts-help: `bash scripts/build-ios.sh --help`、`bash scripts/test-ios.sh --help`、`bash scripts/check-ios-scripts.sh --help` 均退出 0，stdout 含「用法」；三者对未知参数均退出 2。
- ac-ios-scripts-bash-strict: 三个 iOS 脚本 `bash -n` 退出 0，shebang 为 `#!/usr/bin/env bash`，正文含 `set -euo pipefail`。
- ac-build-ios-xcodebuild-path: `scripts/build-ios.sh` 源码含 `xcodebuild build`、`-scheme`、iPhone 16 destination（引号形式可等价，允许显式 `OS=18.6` 或 UDID 以消除 latest 歧义），分支判定基于 `ios/PurePace.xcodeproj` 是否存在；分支 A 成功时日志含 `BUILD SUCCEEDED` 与存在的 `*.app` 路径。
- ac-build-ios-blocked-fallback: 无 `ios/PurePace.xcodeproj` 且无 `xcodegen` 时 `bash scripts/build-ios.sh` 退出 0，输出含 `blocked:` 并指明缺失原因（含 `xcodegen`），同时含降级 `swift build --package-path ios/Core` 的真实执行标记与 `Build complete`；输出中不出现 `BUILD SUCCEEDED`。
- ac-test-ios-blocked-fallback: 同环境下 `bash scripts/test-ios.sh` 退出 0，输出含 `blocked:` 标注与真实 `swift test --package-path ios/Core` 结果，匹配 `Executed [0-9]+ tests?` 且失败数为 0、执行用例数 ≥ 1。
- ac-test-ios-xcodebuild-path: `scripts/test-ios.sh` 源码含 `xcodebuild test`、`-scheme` 与同一 iPhone 16 destination（同样允许显式 `OS` / UDID）；无 `ios/PurePace.xcodeproj` 时不调用 xcodebuild。
- ac-ios-scripts-idempotent: 连续两次执行 `build-ios.sh` 与 `test-ios.sh` 均退出 0；执行后 `git status --porcelain` 不出现新增未忽略产物（xcodebuild 派生数据与 Swift 构建产物均落在忽略路径）。
- ac-check-ios-scripts-detects-drift: 人为改动可检测点（删除某脚本 `--help` 分支，或把 destination 改成非法机型）后 `bash scripts/check-ios-scripts.sh` 非零退出并指出具体失败项；恢复后退出 0。
- ac-code-gates-ios-scripts: `.munk/code-gates.json` 合法 JSON 且 `version=1`，含 `lint-ios-scripts` / `build-ios` / `test-ios` 三门，command 均为单一 argv（无 `&&`、`||`、`|`、`;`、重定向、反引号、`echo`、`true`）；既有六条门 id 与 command 语义不变，`test` 门仍为 `bash scripts/check-baseline.sh`。
- ac-code-gates-all-green: 本机逐条执行 `.munk/code-gates.json` 全部门（含新增三门）均退出 0，且 `bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-no-version-literal: 新增/修改的 `scripts/*.sh` 与 `README.md` 均不出现根 `VERSION` 当前字面值；版本一律经 `scripts/version.sh` 取得。
- ac-no-fake-evidence: 脚本、门禁与 README 输出/文案不出现「CI 通过」「真机已验证」；工程缺失时不得输出 `BUILD SUCCEEDED` 或伪造的 XCTest 通过行。
- ac-scan-zero-hits: 对上述扫描范围的非注释行，`$标识符` 紧跟非 ASCII 字节的展开命中数为 0；`grep` 与门脚本两种口径结果一致。
- ac-shell-expansion-wrap-only: 全部命中改为 `${var}` 形式且变量名/语义不变（纯加花括号，除 workflow 该行允许的必要引号修正）；`android/gradlew` 逐字节未改，其注释内命中仍存在并被豁免。
- ac-gate-registered: `.munk/code-gates.json` 含 `id` 为 `check-shell-expansion`、`cwd` 为 `.`、`command` 恰为 `bash scripts/check-shell-expansion.sh` 的门；JSON 可解析且 `version=1`、门 id 唯一、门集合只增不减。
- ac-prior-gates-unchanged: 既有门的 `id` 与 `command` 逐字未变；新增门一律 append-only，不删除、不重排、不改写（`description` 可追加说明）。
- ac-gate-clean-run: `bash scripts/check-shell-expansion.sh` 在真实仓库退出 0 并逐条 `[PASS]`。
- ac-gate-self-test-positive: 内置自检构造含 `${var}中文` 的样本，判定为通过（不误报）。
- ac-gate-self-test-negative: 内置自检构造含 `$var中文` 的样本，判定为命中并使门非零退出（证明断言非恒真）。
- ac-gate-comment-exempt: 内置自检构造 `# $var中文` 注释行样本，判定为豁免（不命中）。
- ac-gate-help-and-args: `--help` 退出 0 且输出含「用法」；未知参数退出 2 且不执行扫描。
- ac-gate-no-bypass: 门脚本不新增 `set -e` 之外的静默放行分支；扫描器（python3/perl）均缺失时显式 fail 并非零退出，不用 `true`/空转冒充通过。
- ac-workflow-expansion-only: `.github/workflows/android.yml` 的卫生改动仅限 echo 行的变量包裹（必要引号亦仅此一行），`bash scripts/check-android-workflow.sh` 仍退出 0。
- ac-regression-green: 既有 `check-*` 结构门（baseline / android / android-workflow / ios-core / ios-scripts / ios-shell / ios-workflow / ios-run-core）全部退出 0。
- ac-script-contract-preserved: 被修脚本的 `--help` 退出 0 且含「用法」、未知参数退出 2、`blocked:` 降级与退出码语义不变。

## 非目标

- 不创建 iOS 应用工程（`ios/project.yml`、`.xcodeproj`、SwiftUI 空壳）与 `ios/Core` SwiftPM 包。
- 不创建 Android 工程、Gradle wrapper、Compose 占位页。
- 不创建 `shared/` 夹具与 `schema.sql`，也不创建 Android 脚本 `scripts/build-android.sh` / `test-android.sh`；iOS workflow 已由 `ci` 域落地，不在本域扩展。
- 不创建 `ios/project.yml`、`ios/PurePace.xcodeproj`、`project.pbxproj`、`ios/PurePace/` App 源码与 XCTest/XCUITest target；不安装 `xcodegen`。iOS 构建/测试脚本只按工程存在性分支，不代建工程。
- 不做任何业务功能（跑步页、计时、播报、历史、导出）、不做视觉设计、不申请真实定位权限。
- 不做真机签名 / TestFlight / 分发凭据；不新建或修改 git remote；不声称任何 CI 执行或通过。
- 不做版本自增/发布流水线、不写多语言框架、不引入任何跨端框架。

## 实现约束

- 冻结技术栈不得改选：iOS SwiftUI + XcodeGen（iOS 17.0 / Swift 6.2 / Xcode 26.3，仅系统框架，禁止第三方运行时依赖，禁止手写 `project.pbxproj`）；Android Gradle wrapper + Jetpack Compose（minSdk 26 / compileSdk 36 / JDK 21，applicationId 暂定 `com.chaxiu.purepace` 且只在一处 gradle property 定义）；Shared 只放 GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql` 等数据契约。禁止 RN / Flutter / CMP。
- 版本口径：`VERSION` 初始 `0.1.0` 一次定死；后续 iOS `MARKETING_VERSION`、Android `versionName`、`scripts/*.sh` 一律从 `VERSION` 派生。
- skill 安装口径：只用 `npx skills find` / `npx skills add <owner/repo@skill>` 装到仓库内 `.agents/skills/`，禁止 `-g` / `--global`，禁止以 `git clone`、`curl | sh` 为主路径；装不上如实写明并让断言反映真实结果，不得放宽为「有任意 skill 即可」。
- 文档口径：`AGENTS.md` 保持薄，只写事实与约定；`scripts/test-android.sh` 仍只能标注为「由 Android 骨架项补齐」的目标入口，不得声称已存在；iOS 三脚本状态按真实执行结果描述（含 `blocked:` 降级说明）。
- 门禁口径：`code-gates.json` 按 `.munk/code-gates.example.json` 结构生成且不改 example；禁止占位/空转门（`echo`、`true`）；门 command 必须单一 argv，多步断言放进 `scripts/*.sh`。
- iOS 脚本口径：退出码 0 = 成功或显式降级成功（输出必含 `blocked:` 原因）、1 = 工程存在但真实构建/测试失败、2 = 参数非法；降级不得吞掉 `swift build` / `swift test` 的非零退出码；分支只由 `ios/PurePace.xcodeproj` 存在性（或 `project.yml` + xcodegen 可生成）判定；scheme 固定 `PurePace`，destination 钉住 iPhone 16，需带 `OS=18.6`（或等价 UDID）以免 `latest` 解析到无 iPhone 16 的运行时；脚本以 `BASH_SOURCE` 推导仓库根，不依赖调用者 cwd。
- 证据口径：回执只报真实命令 stdout 摘要（门 id → 退出码 → 关键行）与 `swift test` 的 `Executed N tests` 数字；blocked 项逐条列出原因；严禁以本地绿替代远端 CI run。
- 红线：不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）；不自建远端；不写「CI 通过 / 真机已验证」等不实表述；不嵌套第二个 `.git`。
- 展开卫生口径：非 ASCII 判定用字节级比较（`LC_ALL=C`，字节 ≥ 0x80），不依赖当前 locale 的字符分类；扫描器只用 python3 或 perl（不假定 GNU `grep -P` 可用），二者都缺失即 fail。注释行（行首允许前导空白 `#`）整行豁免，`android/gradlew` 属 Gradle wrapper 生成物且命中在注释，**禁止编辑**。
- 门自身会被自己扫描：`check-shell-expansion.sh` 源码不得出现裸 `$var` + 非 ASCII 的字面组合（正则用 `[^ -~]` 一类 ASCII 取反类表达）；自检样本必须落在 `mktemp -d` 临时目录，不在仓库内落地 `.sh` 夹具。
- 新脚本仍受 `check-baseline.sh` 约束：不得写死根 `VERSION` 字面值，遵循 `#!/usr/bin/env bash` + `set -euo pipefail` + `--help`/未知参数退出 2 的既有脚本契约。

## 最近交付证明

- workItemId: wi_ws_8ca5ddccad72148d（2026-11-08，pass）
- 交付：`.munk/code-gates.json` append-only 追加第 22 个门 `verify-ios-sim-runtime`（`cwd=.`，command `bash scripts/verify-ios-sim-runtime.sh`，单一 argv）；既有 21 个门 id/command 逐字未变；本域仅更新门清单记录，编排口径与 AC 落 `ios-shell` 域。
- 验证：`code_gates` 22 门全绿（attempt 001，含 `lint-baseline`、`test`=`check-baseline.sh`）；`bash scripts/check-shell-expansion.sh` 退出 0（新脚本非注释行零裸 `$var` + 非 ASCII 命中），`scripts/verify-ios-sim-runtime.sh` 不写根 `VERSION` 字面值。
- 风险标注：`.github/workflows/*` 本轮未改、CI 未在远端复跑，不得声称 CI 已通过；模拟器三链路证据为本机 iPhone 16 / iOS 18.6 实测。
