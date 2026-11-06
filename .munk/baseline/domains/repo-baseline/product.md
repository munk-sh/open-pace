# Domain: repo-baseline

仓库协作底座：版本单一真源、脚本入口、协作文档、官方 skill 安装与门禁定义。不承载任何跑步业务实现，也不创建 iOS/Android 应用工程。

## 范围

- 根 `VERSION` 为仓库唯一版本真源；`scripts/version.sh` 是读取版本的唯一入口（`README.md`、`scripts/*.sh` 不得写死版本字面值）。
- `scripts/check-baseline.sh` 以可执行结构断言覆盖本域验收（VERSION 格式、无硬编码版本、`AGENTS.md` 四节、skill 路由与磁盘双向一致、iOS+Android skill 存在），同时充当 `code-gates` 的 `test` 门。
- 薄 `README.md`（定位、冻结技术栈、构建/测试入口、版本说明、指向 `AGENTS.md`）与仓库根薄 `AGENTS.md`（技术栈与核心库 / 目录约定 / 测试金字塔 / `.agents/skills` 路由表）。
- `.agents/skills/` 仓库内本地安装的官方 skill（iOS/SwiftUI 与 Android 各至少一个），与 `AGENTS.md` 路由表双向一一对应。
- 初始 `.munk/code-gates.json`：仅含真实可执行的 shell 语法 `lint` 与执行 `scripts/check-baseline.sh` 的 `test`；iOS/Android build/test 门由各自骨架子项追加。

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
- ac-no-business-code: 新增文件仅限 `VERSION`、`README.md`、`AGENTS.md`、`.agents/skills/**`、`scripts/version.sh`、`scripts/check-baseline.sh`、`.munk/code-gates.json`；不出现任何跑步业务实现、占位以外的样例/种子数据或 `ios/`、`android/` 应用工程。

## 非目标

- 不创建 iOS 应用工程（`ios/project.yml`、`.xcodeproj`、SwiftUI 空壳）与 `ios/Core` SwiftPM 包。
- 不创建 Android 工程、Gradle wrapper、Compose 占位页。
- 不创建 `shared/` 夹具与 `schema.sql`、`.github/workflows/*`，也不创建 `scripts/build-*.sh` / `test-*.sh`。
- 不做任何业务功能（跑步页、计时、播报、历史、导出）、不做视觉设计、不申请真实定位权限。
- 不做真机签名 / TestFlight / 分发凭据；不新建或修改 git remote；不声称任何 CI 执行或通过。
- 不做版本自增/发布流水线、不写多语言框架、不引入任何跨端框架。

## 实现约束

- 冻结技术栈不得改选：iOS SwiftUI + XcodeGen（iOS 17.0 / Swift 6.2 / Xcode 26.3，仅系统框架，禁止第三方运行时依赖，禁止手写 `project.pbxproj`）；Android Gradle wrapper + Jetpack Compose（minSdk 26 / compileSdk 36 / JDK 21，applicationId 暂定 `com.chaxiu.purepace` 且只在一处 gradle property 定义）；Shared 只放 GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql` 等数据契约。禁止 RN / Flutter / CMP。
- 版本口径：`VERSION` 初始 `0.1.0` 一次定死；后续 iOS `MARKETING_VERSION`、Android `versionName`、`scripts/*.sh` 一律从 `VERSION` 派生。
- skill 安装口径：只用 `npx skills find` / `npx skills add <owner/repo@skill>` 装到仓库内 `.agents/skills/`，禁止 `-g` / `--global`，禁止以 `git clone`、`curl | sh` 为主路径；装不上如实写明并让断言反映真实结果，不得放宽为「有任意 skill 即可」。
- 文档口径：`AGENTS.md` 保持薄，只写事实与约定；`scripts/test-ios.sh` / `test-android.sh` 只能标注为「由 iOS/Android 骨架项补齐」的目标入口，不得声称已存在。
- 门禁口径：`code-gates.json` 按 `.munk/code-gates.example.json` 结构生成且不改 example；禁止占位/空转门（`echo`、`true`）。
- 红线：不修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）；不自建远端；不写「CI 通过 / 真机已验证」等不实表述；不嵌套第二个 `.git`。

## 最近交付证明

- workItemId: wi_ws_6035fb0cde33a0a3（2026-11-07，pass）
- 交付：`VERSION` = 0.1.0、`scripts/version.sh`、`scripts/check-baseline.sh`、薄 `README.md` / `AGENTS.md`（四节 + skill 路由表）、`.agents/skills/{swiftui-pro,android-cli}` 仓库内本地安装、`.munk/code-gates.json`（`lint` 两门 shell 语法检查 + `test` 真实执行结构断言）。
- 验证：`code_gates` 全部通过；`scripts/check-baseline.sh` 退出码 0 且改坏断言可非零退出；README 与 `scripts/` 无版本字面值。
