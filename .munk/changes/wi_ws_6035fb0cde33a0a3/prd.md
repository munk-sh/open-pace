# 仓库协作基线、版本单一真源与官方 skill 安装

> 本文件只覆盖 WorkSet 波 1 的第 1 个子项（`key: repo-bootstrap`）。WorkSet 级叙事以 `.munk/work-set/overview.md` 为准，此处不复制。

## 范围

把当前**空仓**初始化成后续 iOS/Android 骨架项可以直接落地的协作底座，交付物限定为以下 6 类：

1. **根 `VERSION` 单一真源**：单行、无 `v` 前缀、初始值 `0.1.0`。仓库内任何地方需要版本号时只能读取它。
2. **`scripts/version.sh`**：读取 `VERSION` 并输出（`set -euo pipefail`、幂等、支持 `--help`、路径以仓库根为基准）；是 README 与后续所有构建/测试脚本取版本的唯一入口。
3. **`scripts/check-baseline.sh`**：可执行的结构断言脚本，逐条校验本项验收（VERSION 格式、无硬编码版本、AGENTS.md 四节、skill 路由与磁盘一致、iOS+Android skill 存在）。它同时是本项 `code-gates` 的 `test` 门，必须真实断言并非零退出。
4. **薄 `README.md`**：项目一句话定位 + 冻结技术栈 + 构建/测试入口（指向 `scripts/`）+ 版本说明（引用 `VERSION`，不写死数字）+ 指向 `AGENTS.md`。
5. **薄 `AGENTS.md`（仓库根）**：四节 —— 技术栈与核心库 / 目录约定 / 测试金字塔 / `.agents/skills/<name>` 路由表。
6. **`.agents/skills/` 官方 skill**：用 `npx skills find` / `npx skills add` 安装 iOS/SwiftUI 与 Android 各至少一个真实对应 skill（仓库内本地安装，禁止 `-g` / `--global`），并在 `AGENTS.md` 路由表中登记。
7. **初始 `.munk/code-gates.json`**：至少含真实可执行的 `lint` 与 `test` 门；`test` 门必须真跑 `scripts/check-baseline.sh`。

## 验收标准

- ac-version-file-single-source: 仓库根存在 `VERSION`，内容为单行且匹配 `^[0-9]+\.[0-9]+\.[0-9]+$`（初始 `0.1.0`，无 `v` 前缀、无 BOM、无空行）。
- ac-version-script-reads-file: `bash scripts/version.sh` 退出码 0，stdout 去掉换行后等于 `VERSION` 内容；修改 `VERSION` 后重跑，输出随之改变（证明未缓存/未硬编码）。
- ac-no-hardcoded-version: `README.md` 与 `scripts/*.sh` 中不出现 `VERSION` 的字面值；`scripts/version.sh` 的版本来源只有 `VERSION` 文件读取这一条路径。
- ac-agents-four-sections: `AGENTS.md` 含「技术栈」「目录约定」「测试金字塔」「skill 路由」四节标题且各节正文非空。
- ac-test-pyramid-doc: `AGENTS.md` 测试金字塔节写明 L1 纯逻辑单测落点（`ios/Core/Tests` 的 `swift test`、`android/app/src/test` 的 JVM JUnit）与 L2 设备/模拟器内集成测试落点（`ios/PurePaceUITests` 的 XCUITest、Android Robolectric 或 Compose UI test），并给出单跑（`swift test --filter` / `xcodebuild test -only-testing:` / `./gradlew testDebugUnitTest --tests`）与全跑入口。
- ac-skill-routing-matches-disk: `AGENTS.md` 路由表列出的每个 `.agents/skills/<name>` 条目在磁盘上真实存在且含非空 `SKILL.md`，磁盘上的每个 skill 目录也在表中出现（双向一一对应，无悬空条目）。
- ac-skills-ios-android: `.agents/skills/` 下至少有 1 个 iOS/SwiftUI 对应 skill 与 1 个 Android 对应 skill，各自 `SKILL.md` 非空；不得用与本技术栈无关的 skill 凑数。
- ac-skills-not-global: 安装结果只落在仓库内 `.agents/skills/`；未使用 `-g` / `--global`，未向 `~/.agents` 或全局目录写入（可用安装日志或目录对比证明）。
- ac-code-gates-test-real: `.munk/code-gates.json` 含 `lint` 与 `test` 门，command 均为单一 argv（无 `&&`/`||`/`|`/`;`/重定向）；`test` 门真实执行 `scripts/check-baseline.sh`，本机跑通退出码 0，且脚本人为改坏断言后能非零退出。
- ac-no-business-code: 本项新增文件仅限 `VERSION`、`README.md`、`AGENTS.md`、`.agents/skills/**`、`scripts/version.sh`、`scripts/check-baseline.sh`、`.munk/code-gates.json`；仓库中不出现任何跑步业务实现、首屏占位以外的样例/种子数据或 `ios/`、`android/` 应用工程。

## 非目标

- 不创建 iOS 应用工程（`ios/project.yml`、`PurePace.xcodeproj`、SwiftUI 空壳）与 `ios/Core` SwiftPM 包 —— 属 `wi_ws_f96786f27aa224bd`。
- 不创建 Android 工程、Gradle wrapper、Compose 占位页 —— 属后续波次。
- 不创建 `shared/` 夹具与 `schema.sql`、不创建 `.github/workflows/*`、不创建 `scripts/build-ios.sh` / `test-ios.sh` / `build-android.sh` / `test-android.sh`。
- 不做任何业务功能（跑步页、计时、播报、历史、导出）、不做视觉设计、不申请真实定位权限。
- 不做真机签名 / TestFlight / 分发凭据；不新建或修改 git remote；不声称任何 CI 执行或通过。
- 不做版本自增/发布流水线、不写多语言框架、不引入任何跨端框架。

## 实现约束

**前置 skill（已加载，必须遵循）**：`repo-bootstrap`（`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/opencode/.opencode/skills/repo-bootstrap`）。本项即该 skill 的 Step 1 + 最小 Step 2，Step 2 的「创建应用工程」明确跳过（空仓无应用，但应用工程由后续子项创建，本项只交付协作基线）。

**冻结技术栈（上游已定，不得自行改选）**
- iOS：SwiftUI + XcodeGen，deployment target iOS 17.0，Swift 6.2 / Xcode 26.3，**仅系统框架，禁止第三方运行时依赖**；工程文件只能由 XcodeGen 从 `ios/project.yml` 生成，禁止手写 `project.pbxproj`（本项不创建工程，仅写入约定）。
- Android：Gradle wrapper（固定版本，不依赖系统 gradle）+ Jetpack Compose，minSdk 26 / compileSdk 36 / JDK 21；applicationId 暂定 `com.chaxiu.purepace`，只在一处 gradle property 定义。
- Shared：GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql`；只放数据契约，不放业务逻辑。
- 禁止 RN / Flutter / CMP 等跨端框架。

**版本口径**
- `VERSION` = `0.1.0`（本项一次定死；阶段 1 内不得再散落改号）。
- 后续 iOS 的 `MARKETING_VERSION`、Android 的 `versionName`、`scripts/*.sh` 一律从 `VERSION` 派生（`scripts/version.sh` 是取用入口）；本项只需保证 README 与 `scripts/` 无字面值。

**skill 安装口径**
- 只用 `npx skills find <query>` / `npx skills add <owner/repo@skill>`，**禁止 `-g` / `--global`**，禁止 `git clone`、`curl | sh` 作为主路径。
- Intake 已实测可用锚点（Coding 可直接用，也可用 `find` 重新确认）：
  - iOS/SwiftUI：`twostraws/swiftui-agent-skill@swiftui-pro`（备选 `avdlee/swiftui-agent-skill@swiftui-expert-skill`）。
  - Android：`android/skills@android-cli`（备选 `android/skills@migrate-xml-views-to-jetpack-compose`）。
- 若某层确实装不上（网络/仓库不存在），在提交摘要中如实写明「未安装 + 原因 + 已尝试的命令」，**不得拿无关 skill 凑数**；此时 `check-baseline.sh` 对应断言需如实反映实际结果，不得放宽为「有任意 skill 即可」。

**文档口径**
- `AGENTS.md` 保持薄：只写事实与约定，不复制 Munk Host 的 `AGENTS.md`，不写教程长文。
- 测试金字塔中 `scripts/test-ios.sh` / `test-android.sh` 属后续子项产物，文档可写其为目标入口，但必须标注「由 iOS/Android 骨架项补齐」，不得声称已存在。

**门禁口径**
- `.munk/code-gates.json` 按 `.munk/code-gates.example.json` 结构生成（不改 example）。本项只落 `lint`（shell 语法检查）与 `test`（`bash scripts/check-baseline.sh`）两门；iOS/Android 的 build/test 门由各自子项追加，**不得写占位/空转门**（禁 `echo`、`true`）。

**红线**
- 不得修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。
- 不得自建远端、不得写「CI 通过 / CI 绿 / 真机已验证」等不实表述。
- 不得嵌套第二个 `.git`。
