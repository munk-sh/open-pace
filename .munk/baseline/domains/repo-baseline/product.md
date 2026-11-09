# Domain: repo-baseline

仓库协作底座：版本单一真源、脚本入口（含 iOS 构建/测试/脚本契约）、协作文档、官方 skill 安装与门禁定义。不承载任何跑步业务实现，也不创建 iOS/Android 应用工程。

## 范围

- 根 `VERSION` 为仓库唯一版本真源；`scripts/version.sh` 是读取版本的唯一入口（`README.md`、`scripts/*.sh` 不得写死版本字面值）。
- `scripts/check-baseline.sh` 以可执行结构断言覆盖本域验收（VERSION 格式、无硬编码版本、`AGENTS.md` 四节、skill 路由与磁盘双向一致、iOS+Android skill 存在），同时充当 `code-gates` 的 `test` 门。
- 薄 `README.md`（定位、冻结技术栈、构建/测试入口、版本说明、指向 `AGENTS.md`）与仓库根薄 `AGENTS.md`（技术栈与核心库 / 目录约定 / 测试金字塔 / `.agents/skills` 路由表）。
- `.agents/skills/` 仓库内本地安装的官方 skill（iOS/SwiftUI 与 Android 各至少一个），与 `AGENTS.md` 路由表双向一一对应。
- `scripts/version.sh`：无参保持单行版本输出；`--tools` 追加根 `VERSION` 与 Xcode / Swift / JDK / Gradle 摘要，工具缺失显式标注「未就绪」，不报错、不伪造版本。Gradle 行**离线解析** `android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`（`gradle-<x.y[.z]>-{bin,all}.zip` → `x.y[.z]`），**不调用 `android/gradlew`、不启动 JVM、不触网**。
- `scripts/build-ios.sh` / `scripts/test-ios.sh`：按 `ios/PurePace.xcodeproj`（或 `ios/project.yml` + 本机 `xcodegen`）可用性自动分支。工程可用走 `xcodebuild build|test -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16'`（派生数据落 `.build/ios`）；不可用输出 `blocked:` 原因并降级真实执行 `swift build|test --package-path ios/Core`，以该命令退出码为准。
- `scripts/check-ios-scripts.sh`：上述三脚本的静态契约断言（`bash -n`、`set -euo pipefail`、`--help` 退出 0、未知参数退出 2、无版本字面值、无伪造成功行、含 xcodebuild/destination 契约字面量）；并断言 `version.sh` 正文不含 `gradlew` 且必读 `gradle-wrapper.properties`，Gradle 期望值**独立**从 wrapper properties 推导（不回写 `version.sh`，避免同源恒真），含沙箱反例自检。
- `.munk/code-gates.json`：真实可执行门 `lint` / `lint-baseline` / `lint-ios-core` / `lint-ios-scripts` / `build-ios-core` / `build-ios` / `test-ios-core` / `test-ios` / `test`；`test` 仍为 `bash scripts/check-baseline.sh`。Android build/test 门由 Android 骨架子项追加，`check-shell-expansion` 为 append-only 追加，既有门 id/command 逐字不变。本地门拓扑现为 22 门且只留快而确定腿：`test-ios` 固定 `bash scripts/test-ios.sh --unit-only`，模拟器重腿 `verify-ios-sim-runtime` / `verify-ios-ui-e2e` 移出本地阻断（脚本保留，权威覆盖 = `.github/workflows/ios.yml` 全量 `test-ios.sh`），此收敛为 Owner 批准的拓扑调整，非门禁放宽。
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
- ac-version-tools-report: `bash scripts/version.sh --tools` 退出 0，输出同时含根 `VERSION` 值、Xcode 版本（与 `xcodebuild -version` 首行数字一致）、Swift 版本（与 `swift --version` 的 `Apple Swift version x.y.z` 一致）、JDK 行与 Gradle 行；Gradle 行取自 wrapper properties 离线解析值（`android/gradlew` 缺失或不可执行不影响），仅当 wrapper properties 缺失/无法解析时该行标注「未就绪（…）」，任一行缺失即失败。
- ac-version-tools-idempotent: 连续两次 `bash scripts/version.sh --tools` 输出逐字节相同（不含时间戳、随机数、与路径相关的变量；含 Gradle 分发不可达环境）。
- ac-version-tools-no-gradlew: `scripts/version.sh` 正文（含注释与帮助文本）不含字面量 `gradlew`；`android/gradlew` 不可执行时 `bash scripts/version.sh --tools` 仍退出 0 且输出匹配 `^Gradle: [0-9]` 的行。
- ac-version-tools-offline-parse: 把 wrapper properties 的 `distributionUrl` 临时改为 `gradle-9.9.9-all.zip` 后 `--tools` 输出 `Gradle: 9.9.9`（证明值来自 wrapper properties 而非网络或缓存）；恢复原值后输出与仓库状态一致。
- ac-version-tools-matches-wrapper: 仓库真实状态下 `--tools` 的 `Gradle:` 行等于 `gradle-wrapper.properties` 中 `distributionUrl` 解析出的 `gradle-<x.y[.z]>-{bin,all}.zip` 版本号（当前 8.14.3）。
- ac-version-tools-missing-wrapper-fallback: `android/gradle/wrapper/gradle-wrapper.properties` 缺失或无法解析出版本时，Gradle 行标注「未就绪（…）」，命令仍退出 0，不伪造版本。
- ac-check-ios-scripts-offline-guard: `bash scripts/check-ios-scripts.sh` 含 `version.sh` 无 `gradlew`、必读 wrapper properties、Gradle 期望值独立推导三条断言，且注入违规样本（如追加一行 gradlew 调用）时输出 FAIL 并非零退出。
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
- ac-gate-registered: `.munk/code-gates.json` 含 `id` 为 `check-shell-expansion`、`cwd` 为 `.`、`command` 恰为 `bash scripts/check-shell-expansion.sh` 的门；JSON 可解析且 `version=1`、门 id 唯一、门集合只增不减（唯一例外：`verify-ios-sim-runtime` / `verify-ios-ui-e2e` 两条模拟器重腿于 `wi_intake_11dc6b68d0c7555d` 移出本地阻断，见 `ios-ci-stability` 域）。
- ac-prior-gates-unchanged: 既有门的 `id` 与 `command` 逐字未变；新增门一律 append-only，不删除、不重排、不改写（`description` 可追加说明）。例外仅限上条的本地重腿移出，且须在 `ios-ci-stability` 域留痕、由 `check-ios-scripts.sh` 的拓扑断言锁死。
- ac-gate-clean-run: `bash scripts/check-shell-expansion.sh` 在真实仓库退出 0 并逐条 `[PASS]`。
- ac-gate-self-test-positive: 内置自检构造含 `${var}中文` 的样本，判定为通过（不误报）。
- ac-gate-self-test-negative: 内置自检构造含 `$var中文` 的样本，判定为命中并使门非零退出（证明断言非恒真）。
- ac-gate-comment-exempt: 内置自检构造 `# $var中文` 注释行样本，判定为豁免（不命中）。
- ac-gate-help-and-args: `--help` 退出 0 且输出含「用法」；未知参数退出 2 且不执行扫描。
- ac-gate-no-bypass: 门脚本不新增 `set -e` 之外的静默放行分支；扫描器（python3/perl）均缺失时显式 fail 并非零退出，不用 `true`/空转冒充通过。
- ac-workflow-expansion-only: `.github/workflows/android.yml` 的卫生改动仅限 echo 行的变量包裹（必要引号亦仅此一行），`bash scripts/check-android-workflow.sh` 仍退出 0。
- ac-regression-green: 既有 `check-*` 结构门（baseline / android / android-workflow / ios-core / ios-scripts / ios-shell / ios-workflow / ios-run-core）全部退出 0。
- ac-script-contract-preserved: 被修脚本的 `--help` 退出 0 且含「用法」、未知参数退出 2、`blocked:` 降级与退出码语义不变。
- ac-ios-scripts-help-green: `bash scripts/check-ios-scripts.sh` exit 0，输出含 `[PASS] ac-ios-scripts-help`，全量 `[FAIL]` 计数为 0（既有 25 项断言、0 项失败）。
- ac-version-tools-still-green: 同一次运行中 `ac-version-tools-no-gradlew`、`ac-version-tools-report`、`ac-version-tools-idempotent` 均 PASS，`VERSION` / `Xcode` / `Swift` / `JDK` / `Gradle`（含「未就绪」降级分支）判定期望值与改前完全一致。
- ac-signpipe-free-20x: 连续执行 `bash scripts/check-ios-scripts.sh` 20 次全部 exit 0，合并 stderr 中 `write error: Broken pipe` / `printf: write error` 出现次数均为 0。
- ac-no-printf-grep-pipe: `grep -n "printf .*| *grep" scripts/check-ios-scripts.sh` 无输出；`printf` 不再作为「消费者可能提前退出」的管道写端。
- ac-fail-path-preserved: 改写后的判定在目标串缺失时仍返回非零（同一判定喂入不含目标串的输入实测 exit 1）；不得用 `|| true`、`set +e`、`continue-on-error` 或删断言换取绿灯。
- ac-strict-mode-kept: 脚本仍为 `#!/usr/bin/env bash` 且正文含 `set -euo pipefail`，`bash -n scripts/check-ios-scripts.sh` 通过。
- ac-diff-scope-lint-gate: 本轮改动仅含 `scripts/check-ios-scripts.sh`；`.munk/code-gates.json` 仍 22 门、`.github/workflows/**`、`ios/` / `android/` / `shared/` 业务源码、`VERSION`、`README.md` 均无改动。
- ac-local-fast-gates-green: 本地 `code_gates` 快腿全绿，至少覆盖 `lint`、`lint-ios-scripts`、`check-shell-expansion`、`lint-ios-workflow`、`test`（`bash scripts/check-baseline.sh`）；重 UI E2E 腿不在本地阻断。
- ac-no-grep-pipe-sites: 7 个脚本（`check-ios-release.sh` / `check-ios-shell.sh` / `check-baseline.sh` / `check-android.sh` / `check-ios-workflow.sh` / `check-android-workflow.sh` / `version.sh`）中，`printf … | grep` 与「`| grep -q/-Fq` 类提前退出消费者」的管道判定点数量为 0（改造前分别为 10/6/5/3/1/1/1 处，含 release `:247` 的文件管道 1 处）；逐文件复核口径为 `grep -nE 'printf[^|]*\|[[:space:]]*grep'` 与 `grep -nE '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*[qF]'`。`||` 并列的直连文件 grep 与 `grep -Ev`（无 `-q`、消费全量输入、原就带 `|| true`）不属判定管道。
- ac-here-string-form: 每个原管道判定点改为 `grep … <<< "$var"` 形式；`check-ios-release.sh:247` 的 `grep -A1 file | grep -Fq` 改为先用 `$(grep -A1 …)` 完整捕获再 here-string 喂 `grep -Fq`（消除首个 grep 的 SIGPIPE 面）。
- ac-error-mode-preserved: 各文件 `set -euo pipefail` 出现次数与改造前一致（release=3、android=3、其余=1）；改造点未新增 `|| true`、未引入 retry、未出现 `set +e`，退出码未被吞。
- ac-output-identical: 同一棵树上逐脚本改造前后各跑一遍，`^\[PASS\]` / `^\[FAIL\]` 行序列与末尾 `N 项断言，M 项失败` 汇总行逐行完全一致，退出码一致（release/shell/baseline/android/ios-workflow/android-workflow 六脚本）。
- ac-twenty-run-stable: 7 个脚本各自连跑 20 次，每次 stdout/stderr 与退出码完全一致（`version.sh` 以「stdout+退出码」为一致口径）。
- ac-version-script: `scripts/version.sh` 改动仅限 `:65` 的管道判定；`bash scripts/version.sh` 裸输出仍等于根 `VERSION`；空值/非 `x.y.z` 错误路径仍以原文案 `exit 1`；连跑 20 次恒同；交付摘要单列处置、影响面与验证方式。
- ac-exec-bits: 交付后 7 个文件 git mode 均为 `100755`；`check-ios-release.sh` 由 `100644` 恢复为 `100755`，其余 6 个保持 `100755` 不变。
- ac-scope-only-7: 代码改动 `git diff --name-only` 仅含上述 7 个文件；`.github/**`、`.munk/code-gates.json`、其他脚本未改动；断言文案与判定语义零改动。

## 非目标

- 不创建 iOS 应用工程（`ios/project.yml`、`.xcodeproj`、SwiftUI 空壳）与 `ios/Core` SwiftPM 包。
- 不创建 Android 工程、Gradle wrapper、Compose 占位页。
- 不创建 `shared/` 夹具与 `schema.sql`，也不创建 Android 脚本 `scripts/build-android.sh` / `test-android.sh`；iOS workflow 已由 `ci` 域落地，不在本域扩展。
- 不创建 `ios/project.yml`、`ios/PurePace.xcodeproj`、`project.pbxproj`、`ios/PurePace/` App 源码与 XCTest/XCUITest target；不安装 `xcodegen`。iOS 构建/测试脚本只按工程存在性分支，不代建工程。
- 不做任何业务功能（跑步页、计时、播报、历史、导出）、不做视觉设计、不申请真实定位权限。
- 不做真机签名 / TestFlight / 分发凭据；不新建或修改 git remote；不声称任何 CI 执行或通过。
- 不做版本自增/发布流水线、不写多语言框架、不引入任何跨端框架。
- 修某个 `check-*.sh` 的判定写法时不做跨脚本 drive-by 扩面：除 PRD 明确列入本次范围的单个文件外，兄弟脚本（`check-baseline.sh` / `check-ios-release.sh` / `check-ios-shell.sh` / `version.sh` 等）即便存在同类模式也不得顺手改写，同类清理需另开工作项。

## 实现约束

- 冻结技术栈不得改选：iOS SwiftUI + XcodeGen（iOS 17.0 / Swift 6.2 / Xcode 26.3，仅系统框架，禁止第三方运行时依赖，禁止手写 `project.pbxproj`）；Android Gradle wrapper + Jetpack Compose（minSdk 26 / compileSdk 36 / JDK 21，applicationId 与 iOS bundle id 同为产品最终标识 `sh.munk.purepace`，只在一处 gradle property / `project.yml` 定义）；Shared 只放 GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql` 等数据契约。禁止 RN / Flutter / CMP。
- 版本口径：`VERSION` 初始 `0.1.0` 一次定死；后续 iOS `MARKETING_VERSION`、Android `versionName`、`scripts/*.sh` 一律从 `VERSION` 派生。
- skill 安装口径：只用 `npx skills find` / `npx skills add <owner/repo@skill>` 装到仓库内 `.agents/skills/`，禁止 `-g` / `--global`，禁止以 `git clone`、`curl | sh` 为主路径；装不上如实写明并让断言反映真实结果，不得放宽为「有任意 skill 即可」。
- 文档口径：`AGENTS.md` 保持薄，只写事实与约定；`scripts/test-android.sh` 仍只能标注为「由 Android 骨架项补齐」的目标入口，不得声称已存在；iOS 三脚本状态按真实执行结果描述（含 `blocked:` 降级说明）。
- 门禁口径：`code-gates.json` 按 `.munk/code-gates.example.json` 结构生成且不改 example；禁止占位/空转门（`echo`、`true`）；门 command 必须单一 argv，多步断言放进 `scripts/*.sh`。
- iOS 脚本口径：退出码 0 = 成功或显式降级成功（输出必含 `blocked:` 原因）、1 = 工程存在但真实构建/测试失败、2 = 参数非法；降级不得吞掉 `swift build` / `swift test` 的非零退出码；分支只由 `ios/PurePace.xcodeproj` 存在性（或 `project.yml` + xcodegen 可生成）判定；scheme 固定 `PurePace`，destination 钉住 iPhone 16，需带 `OS=18.6`（或等价 UDID）以免 `latest` 解析到无 iPhone 16 的运行时；脚本以 `BASH_SOURCE` 推导仓库根，不依赖调用者 cwd。
- 证据口径：回执只报真实命令 stdout 摘要（门 id → 退出码 → 关键行）与 `swift test` 的 `Executed N tests` 数字；blocked 项逐条列出原因；严禁以本地绿替代远端 CI run。
- 红线：不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）；不自建远端；不写「CI 通过 / 真机已验证」等不实表述；不嵌套第二个 `.git`。
- 展开卫生口径：非 ASCII 判定用字节级比较（`LC_ALL=C`，字节 ≥ 0x80），不依赖当前 locale 的字符分类；扫描器只用 python3 或 perl（不假定 GNU `grep -P` 可用），二者都缺失即 fail。注释行（行首允许前导空白 `#`）整行豁免，`android/gradlew` 属 Gradle wrapper 生成物且命中在注释，**禁止编辑**。
- 门自身会被自己扫描：`check-shell-expansion.sh` 源码不得出现裸 `$var` + 非 ASCII 的字面组合（正则用 `[^ -~]` 一类 ASCII 取反类表达）；自检样本必须落在 `mktemp -d` 临时目录，不在仓库内落地 `.sh` 夹具。
- 版本探测口径：`--tools` 的 Gradle 行只读 `<repo_root>/android/gradle/wrapper/gradle-wrapper.properties`（路径以脚本自身推导的仓库根为基准，任意 cwd 一致），解析只用 bash/sed/grep；不启动 JVM、不触网、不依赖 Gradle 缓存与 `android/gradlew`。静态断言不得复用 `version.sh` 的解析逻辑（否则恒真）。
- 新脚本仍受 `check-baseline.sh` 约束：不得写死根 `VERSION` 字面值，遵循 `#!/usr/bin/env bash` + `set -euo pipefail` + `--help`/未知参数退出 2 的既有脚本契约。
- 静态断言判定口径（防 SIGPIPE 伪红）：`check-*` 脚本里「长字符串交给可能提前退出的消费者（`grep -q` / `head -n 1`）」一律不得用 `printf '%s' "$var" | <consumer>`——消费者命中即关闭读端，写端收 SIGPIPE（141），`set -euo pipefail` 下整条管道随机判失败。等价写法：here-string `grep -Fq -- "…" <<<"$var"` 或 bash 内建匹配 `[[ "$out" == *"…"* ]]` / `[[ "$out" =~ … ]]`（bash 3.2 兼容）。`grep -Fxq` 的「整行全等」语义与 `-F`/`-E` 的正则 vs 字面量语义必须逐条保持，不得降级为子串匹配。

## 最近交付证明

- workItemId: wi_intake_588bc60ee11d98cc（2026-11-09，pass）
- 交付：`check-ios-release.sh`（10 处 `printf|grep` + `:247` 的文件管道）、`check-ios-shell.sh`（6 处）、`check-baseline.sh`（5 处）、`check-android.sh`（3 处）、`check-ios-workflow.sh` / `check-android-workflow.sh`（各 1 处）、`version.sh`（`:65` 1 处）统一改为 here-string 判定；`check-ios-release.sh` 可执行位由 `100644` 恢复为 `100755`。断言数量/名称/顺序/期望值/文案与退出码零改动。
- 根因：`set -euo pipefail` 下 `printf | grep -q` 命中后 grep 提前退出，写端收 SIGPIPE(141) 被 pipefail 透传，判定随机反转产生偶发伪红（上一项已单点修 `check-ios-scripts.sh`，本项清剩余 7 个文件）。
- 验证：7 脚本当前树全绿——release 17/0、shell 17/0、baseline 11/0、android 15/0、ios-workflow OK、android-workflow OK，`bash scripts/version.sh` 输出与根 `VERSION` 一致（rc=0）；`grep -nE 'printf[^|]*\|[[:space:]]*grep'` 与 `| grep -q/-Fq` 口径逐文件复核无判定管道残留。
- 边界：`grep -Ev` 全量消费管道（`check-ios-shell.sh:97`，原带 `|| true`）与 `||` 并列的直连文件 grep 非判定点，按零语义改动原则不动。

