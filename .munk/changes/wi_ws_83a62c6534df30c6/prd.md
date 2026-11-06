# iOS 构建/测试脚本与初始 code-gates

## 范围

在既有协作基线上补齐 iOS 本地执行入口与门禁（当前仓库只有 `VERSION` / `AGENTS.md` / `README.md` / `scripts/version.sh` / `scripts/check-baseline.sh` / `scripts/check-ios-core.sh` / `ios/Core`）：

1. `scripts/version.sh` 扩展：保留无参行为（单行输出 `VERSION` 内容），新增 `--tools` 开关，在无参契约之外输出根 `VERSION` 与 Xcode / Swift / JDK / Gradle 版本摘要；工具缺失时该行显式标注「未就绪/未安装」，不报错、不伪造版本。
2. 新增 `scripts/build-ios.sh`：bash、`set -euo pipefail`、幂等、支持 `--help`；路径以脚本自身位置推导仓库根。
   - 分支 A（工程可用）：存在 `ios/PurePace.xcodeproj`（或 `ios/project.yml` + 本机有 `xcodegen` 可生成）时执行 `xcodebuild build -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16'`，派生数据写入已忽略的 `.build/ios`，日志输出 `BUILD SUCCEEDED` 与最终 `.app` 路径。
   - 分支 B（工程不可用）：输出 `blocked: 缺 xcodegen` / 缺 `ios/PurePace.xcodeproj` 的明确原因，降级真实执行 `swift build --package-path ios/Core`，并以该命令退出码为准；分支 B 绝不输出 `BUILD SUCCEEDED`。
3. 新增 `scripts/test-ios.sh`：同样的分支结构。工程可用时 `xcodebuild test -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16'` 真跑 XCTest/XCUITest；工程不可用时降级 `swift test --package-path ios/Core`，输出 `blocked:` 标注并保留真实执行用例数与失败数。
4. 新增 `scripts/check-ios-scripts.sh`（lint 门执行体，单一 argv 落点）：对上述脚本做静态断言——`bash -n` 通过、含 `set -euo pipefail`、`--help` 退出 0、未知参数退出 2、不含根 `VERSION` 字面值、不含伪造成功行、含 xcodebuild/destination 契约字面量。
5. `.munk/code-gates.json` 追加三条真实门：`lint-ios-scripts`（`bash scripts/check-ios-scripts.sh`）、`build-ios`（`bash scripts/build-ios.sh`）、`test-ios`（`bash scripts/test-ios.sh`）；既有 `lint` / `lint-baseline` / `lint-ios-core` / `build-ios-core` / `test-ios-core` / `test` 保持原样，`test` 仍执行 `scripts/check-baseline.sh`。
6. `README.md` scripts 表中 `build-ios.sh` / `test-ios.sh` 两行状态从「由 iOS 骨架子项补齐」改为实际状态（可用 + 无工程时降级/blocked 说明），并补 `version.sh --tools` 一行；不改 README 其余结构。

本项不依赖 iOS App 空壳工程存在：以文件存在性自动切换分支，空壳工程落地后无需改代码或改门禁即走 `xcodebuild`。

## Acceptance Criteria

- ac-version-bare-unchanged: `bash scripts/version.sh` 退出 0 且 stdout 去换行等于根 `VERSION` 内容；`bash scripts/version.sh --help` 退出 0。
- ac-version-tools-report: `bash scripts/version.sh --tools` 退出 0，输出同时包含根 `VERSION` 值、Xcode 版本（与 `xcodebuild -version` 首行数字一致）、Swift 版本（与 `swift --version` 中的 `Apple Swift version x.y.z` 一致）、JDK 行（本机为 openjdk 21，取 `java -version` 摘要）、Gradle 行（当前无 `android/gradlew` 时显式标注未就绪）；任一行缺失即判定失败。
- ac-version-tools-idempotent: 连续两次 `bash scripts/version.sh --tools` 输出逐字节相同（不含时间戳、随机数、路径无关变量）。
- ac-ios-scripts-help: `bash scripts/build-ios.sh --help`、`bash scripts/test-ios.sh --help`、`bash scripts/check-ios-scripts.sh --help` 均退出 0，stdout 含「用法」；三者对未知参数均退出 2。
- ac-ios-scripts-bash-strict: 三个脚本 `bash -n` 退出 0，shebang 为 `#!/usr/bin/env bash`，正文含 `set -euo pipefail`。
- ac-build-ios-xcodebuild-path: `scripts/build-ios.sh` 源码含 `xcodebuild build`、`-scheme`、`-destination 'platform=iOS Simulator,name=iPhone 16'`（引号形式可等价），且分支判定基于 `ios/PurePace.xcodeproj` 是否存在；分支 A 成功时日志含 `BUILD SUCCEEDED` 与存在的 `*.app` 路径。
- ac-build-ios-blocked-fallback: 当前仓库（无 `ios/PurePace.xcodeproj`、无 xcodegen）执行 `bash scripts/build-ios.sh` 退出 0，输出含 `blocked:` 且指明缺失原因（含 `xcodegen`），同时日志含降级 `swift build --package-path ios/Core` 的真实执行标记与 `Build complete`；输出中不出现 `BUILD SUCCEEDED`。
- ac-test-ios-blocked-fallback: 当前仓库执行 `bash scripts/test-ios.sh` 退出 0，输出含 `blocked:` 标注，且含真实 `swift test --package-path ios/Core` 的结果，匹配 `Executed [0-9]+ tests?` 且失败数为 0、执行用例数 ≥ 1。
- ac-test-ios-xcodebuild-path: `scripts/test-ios.sh` 源码含 `xcodebuild test`、`-scheme`、同一 iPhone 16 destination 字面量；不存在 `ios/PurePace.xcodeproj` 时不调用 xcodebuild（由降级分支的退出码与输出共同断言）。
- ac-ios-scripts-idempotent: 连续两次执行 `bash scripts/build-ios.sh` 与 `bash scripts/test-ios.sh` 均退出 0；执行后 `git status --porcelain` 不出现新增未忽略产物（xcodebuild 派生数据与 Swift 构建产物均落在忽略路径）。
- ac-check-ios-scripts-detects-drift: 人为改动可检测点（删除某脚本的 `--help` 分支、或把 build 分支的 destination 改成非法机型）后 `bash scripts/check-ios-scripts.sh` 非零退出并在输出中指出具体失败项；恢复后退出 0。
- ac-code-gates-ios-scripts: `.munk/code-gates.json` 为合法 JSON 且 `version=1`，含 `lint-ios-scripts` / `build-ios` / `test-ios` 三条门，command 均为单一 argv（无 `&&`、`||`、`|`、`;`、重定向、反引号、`echo`、`true`）；既有六条门 id 与 command 语义不变，`test` 门仍为 `bash scripts/check-baseline.sh`。
- ac-code-gates-all-green: 在本机逐条执行 `.munk/code-gates.json` 全部门（含新增三门）均退出 0，且 `bash scripts/check-baseline.sh` 仍全部 PASS（含无版本字面值、`test` 门指向基线脚本两项断言）。
- ac-no-version-literal: 新增/修改的 `scripts/*.sh` 与 `README.md` 均不出现根 `VERSION` 的当前字面值；版本一律经 `scripts/version.sh` 取得。
- ac-no-fake-evidence: 脚本、门禁与 README 输出/文案不出现「CI 通过」「真机已验证」；工程缺失时不得输出 `BUILD SUCCEEDED` 或伪造的 XCTest 通过行。

## 非目标

- 不创建 `ios/project.yml`、`ios/PurePace.xcodeproj`、`project.pbxproj`、`ios/PurePace/` App 源码、XCTest/XCUITest target——属 iOS 空壳项；不安装 `xcodegen`。
- 不写 `.github/workflows/*`、不推远端、不建分支、不声称任何 CI run 状态（CI 门由波 1 Delivery 建立）。
- 不新增/修改 Android 脚本（`build-android.sh` / `test-android.sh`）、`shared/`、`ios/Core` 源码与测试。
- 不改 `VERSION` 值、`AGENTS.md` 结构、`scripts/check-baseline.sh` 既有断言语义、`scripts/check-ios-core.sh`、`ios/Core/Package.swift`。
- 不引入 SwiftLint / swift-format / 第三方依赖；不引入模拟器启动守护、覆盖率、报告上传等附加设施。
- 不做视觉设计、真机签名、TestFlight、业务功能。

## Implementation Constraints

- 本机实测环境（2026-11-07）：Xcode 26.3（17C529）、Swift 6.2.4、openjdk 21.0.1（Zulu）、`xcodegen` **未安装**、模拟器 `iPhone 16` 可用且 iOS 18.6 runtime 存在、仓库无 `android/` 目录。因此 `Gradle` 行与 `xcodebuild` 分支持续处于 blocked/降级态，属预期事实，不得改成 fabricated 值。
- `scripts/version.sh` 无参输出被 `scripts/check-baseline.sh` 严格比对（等于 `VERSION`，且沙箱改值后必须随之变化），因此工具链信息只能用新增 flag（`--tools`）承载；同时 `version.sh` 不得出现 `git describe`、`git rev-parse`、`MARKETING_VERSION`、`versionName`、`CURRENT_PROJECT_VERSION` 字样（既有断言会失败）。
- 门禁 command 必须是单一 argv：需要多步断言时新增 `scripts/*.sh` 承载（`set -euo pipefail`、幂等、`--help`、仓库根为路径基准），门以 `bash scripts/<name>.sh` 调用，禁止在 command 内拼接分隔符。
- `test` 门语义锁定：必须仍是 `bash scripts/check-baseline.sh`（基线结构断言），iOS 测试门用独立 id `test-ios`，不得替换或放宽既有门。
- xcodebuild 派生数据必须落在 `.build/ios`（仓库 `.gitignore` 已覆盖 `.build/`）；scheme 固定 `PurePace`，destination 固定 `platform=iOS Simulator,name=iPhone 16`（与 WorkSet §5 验收一致）；缺 scheme/工程时走降级分支，不得静默成功。
- 退出码语义统一：0 = 成功或显式降级成功（输出必含 `blocked:` 前缀原因）；1 = 工程存在但真实构建/测试失败；2 = 参数非法。降级不得吞掉真实失败（`swift build` / `swift test` 非零必须透传）。
- 脚本以 `BASH_SOURCE` 推导仓库根（对齐 `version.sh` 现有写法），保证任意 cwd 下行为一致；不得依赖调用者 cwd。
- 空壳工程落地后的衔接契约：脚本仅以 `ios/PurePace.xcodeproj` 存在性（及 `project.yml` + xcodegen 可生成）判定分支；后续 iOS 空壳项落地后不得修改脚本或门禁定义即可自动走 `xcodebuild`。
- 证据口径：回执只报真实命令 stdout 摘要（门 id → 退出码 → 关键行）与 `swift test` 的 `Executed N tests` 数字；blocked 项逐条列出原因；严禁以本地绿替代远端 CI run。
