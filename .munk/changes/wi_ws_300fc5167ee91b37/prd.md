# iOS GitHub Actions workflow 与真实绿色 run

## 范围

在 iOS 空壳工程与 `scripts/` 本地门已就绪的前提下（前序已合入 `ios/project.yml` + `ios/PurePace.xcodeproj`、`scripts/build-ios.sh` / `test-ios.sh`、10 条 code-gates），补上仓库唯一的 iOS 远端门：

- 新增 `.github/workflows/ios.yml`：`macos-latest` 单 job，按 `install` → `lint` → `test` → `build` 顺序四步，全部复用 `scripts/` 既有本地命令（不在 workflow 内另写一套 xcodebuild 逻辑）。
- `install` 步负责 runner 侧前置：安装 `xcodegen`（`lint-ios-shell` 依赖它从 `ios/project.yml` 复核工程），并把 iPhone 16 + iOS 18.6 模拟器准备好（缺失则创建设备 / 下载对应运行时，或经 scripts 支持的显式 destination 注入口替代），保证 `scripts/test-ios.sh` 与 `build-ios.sh` 在 runner 上真走 xcodebuild 分支。
- 新增一个 workflow 结构断言脚本（YAML 解析 + 触发/runner/步骤顺序/命令复用/无降级放行断言）并注册为单一 argv 的 lint 门，使 `.github/workflows/ios.yml` 的语法与结构在本机可回归。
- 由本项 Delivery 经 Host 工具只推分支触发 GitHub Actions（不推 tag、不动 Release、不新建远端或改 remote、不 seed），取真实绿色 run id 作为证据；run 未出前如实记 `pending: 待 remote 验证`。

## 验收标准

### A. 本机可断言（Coding 在 code_gates 中落地）

- ac-workflow-exists-and-parses: `.github/workflows/ios.yml` 存在，YAML 可被解析且含 `name` / `on` / `jobs` 顶层键；解析用本机已有解释器（`ruby -ryaml` 或 `python3`），不引入 actionlint 等新工具依赖。
- ac-workflow-push-trigger: `on` 包含 `push`，且未用 `tags`/分支白名单把「推分支」排除在触发条件之外（首次推任意分支即能触发本 workflow）；不得只挂 `pull_request`。
- ac-workflow-macos-latest: job 的 `runs-on` 为 `macos-latest`，且只有一个 job 承载 install/lint/test/build。
- ac-workflow-step-order: job steps 中 `install`、`lint`、`test`、`build` 四个步骤名按此顺序出现，每步 `run` 非空。
- ac-install-provisions-xcodegen-and-simulator: `install` 步骤在后继步骤之前完成两件事且幂等（重复执行不失败）——(1) `xcodegen` 可用（缺失时经 `brew install xcodegen` 等官方渠道安装）；(2) `platform=iOS Simulator,name=iPhone 16,OS=18.6` 可解析：缺设备时用 `xcrun simctl create` 建立同名设备，缺 iOS 18.6 运行时（如 `xcrun simctl list runtimes` 无 18.6）时下载该运行时，或改走 scripts 显式支持的 destination 注入口（UDID / OS）指向 runner 上真实可用的 iPhone 16 与运行时。
- ac-lint-step-reuses-local-gates: `lint` 步骤调用既有 `scripts/check-baseline.sh`、`scripts/check-ios-core.sh`、`scripts/check-ios-scripts.sh`、`scripts/check-ios-shell.sh` 的真实断言（各自独立命令行，不合并成一个 `&&` 长串），不新增空转 `echo`/`true` 门。
- ac-test-build-reuse-scripts: `test` 步骤执行 `bash scripts/test-ios.sh`，`build` 步骤执行 `bash scripts/build-ios.sh`；workflow 内不出现绕过脚本的第二套 `xcodebuild test` / `xcodebuild build` 调用。
- ac-ci-fails-on-blocked-degradation: 当 `scripts/test-ios.sh` 或 `build-ios.sh` 输出 `blocked:`（工程/工具缺失的 SwiftPM 降级分支）时，对应 workflow 步骤以非零退出码失败（例如执行后对输出做 `blocked:` 断言即 `exit 1`），保证 CI 变绿必然意味着 xcodebuild 真跑了 iOS 测试与构建。
- ac-workflow-structural-gate: 新增 `scripts/check-ios-workflow.sh`（bash、`set -euo pipefail`、支持 `--help`、幂等、路径以仓库根为基准），覆盖 YAML 解析与上述结构断言；并在 `.munk/code-gates.json` 注册为 command 为单一 argv 的 lint 门。本机执行退出 0；人为破坏 workflow（改错 `runs-on`、删除 `test` 步骤、去掉 `push` 触发）后该脚本非零退出并指出具体失败项，恢复后退出 0。
- ac-existing-gates-unchanged-green: `.munk/code-gates.json` 既有 10 条门的 id 与 command 语义不变（`test` 仍为 `bash scripts/check-baseline.sh`），全部在本机退出 0；`bash scripts/build-ios.sh` 与 `bash scripts/test-ios.sh` 仍走 xcodebuild 分支并真实成功，`scripts/check-ios-scripts.sh` 的 iPhone 16 destination 断言未被放宽。
- ac-no-version-literal: 新增/修改的 workflow 与 `scripts/*.sh` 中不出现根 `VERSION` 的当前字面值（沿用既有断言口径，版本只经 `scripts/version.sh` 取得）。
- ac-runner-simulator-mismatch-not-silent: 无论采用下载 iOS 18.6 还是注入 runner 实际可用 destination，scripts 源码中 `iPhone 16` 与显式 `OS=`/`id=` 的 destination 契约字面量仍在，且本机默认行为不变；不得为了适配 runner 把机型或 OS 断言删掉。

### B. 远端证据（Delivery 执行并写入交付摘要）

- ac-branch-only-push: Delivery 只经 Host 工具推送本分支触发 Actions；全程 git 网络操作用 `env -u GIT_EXEC_PATH git ...`；不推 tag、不创建 Release、不改 origin URL、不新增 remote、不向远端预置（seed）任何内容（`git tag -l` 无新增、`git remote -v` 与推送前一致）。
- ac-real-green-run-id: Actions run 产出后，证据必须是真实 run：`conclusion=success` 且带数字 run id 与 workflow 名，来源为 `gh run list --repo munk-sh/open-pace --workflow ios.yml` / `gh run view <id>` 或 Host CI 通道的原始输出摘要。
- ac-pending-honest: run 尚未产出（排队/未触发）时，交付摘要逐字记录 `pending: 待 remote 验证`，不得写成「CI 绿」或 `blocked`，不得用本地门结果替代远端 run。
- ac-ci-red-blocks-delivery: run 为 `failure`/`cancelled` 时本项不交付，摘要附失败 run id 与失败步骤日志摘要；修复后重新推送取新的绿色 run，不得沿用旧 run。
- ac-empty-remote-escalation: 若 Delivery 因「远端无默认分支 / 空仓」报错，把该错误原文整段写入摘要并回报 Owner，不自行改用其他 git 工具反复重试。
- ac-no-fake-ci-wording: 摘要、脚本与文档中不出现「CI 通过」「CI 已通过」「真机已验证」等未经 run id 支撑的措辞。

## 非目标

- 不新增 `.github/workflows/android.yml`（波 2）、不做 Android/shared 任何改动。
- 不改动 iOS 业务/UI 源码、`ios/project.yml`、`ios/PurePace.xcodeproj`（工程仍由 XcodeGen 单一真源生成）、`ios/Core` 源码与其测试。
- 不引入第三方运行时依赖、不引入 actionlint / fastlane / 覆盖率 / 构建产物上传 / 依赖缓存等附加设施。
- 不设置分支保护、required checks、secrets、environment 或任何仓库设置类变更；不推 tag、不建 Release、不新建 remote、不改 remote URL、不 seed 远端。
- 不用 CI 替代或放宽本地门；不在 workflow 内重写一套构建/测试命令。
- 不做真机签名、TestFlight、分发；不做视觉设计与业务功能。

## 实现约束

- 当前仓库事实（Intake 实测，2026-11-07）：`.github/` 不存在；`ios/PurePace.xcodeproj` 与 `ios/project.yml` 已入库；`scripts/` 含 `build-ios.sh` / `test-ios.sh` / `version.sh` / `sync-ios-version.sh` / `check-baseline.sh` / `check-ios-core.sh` / `check-ios-scripts.sh` / `check-ios-shell.sh`；本机 `xcodegen` 已在 `/opt/homebrew/bin/xcodegen`；`gh` 可用且 `gh run list --repo munk-sh/open-pace` 当前无任何 run；`origin` = `https://github.com/munk-sh/open-pace.git`，远端已有 `refs/heads/main`（5e386f3），并非空仓。
- 脚本 destination 锚点（改脚本必须保住）：`scripts/build-ios.sh:59,72` 与 `scripts/test-ios.sh:57,69` 固定 `platform=iOS Simulator,name=iPhone 16,OS=18.6`；`scripts/check-ios-scripts.sh:137-139,160-162` 用正则断言 `name=iPhone 16` + 可选 `,OS=x`/`,id=UDID`。优先方案是**不改脚本**，在 workflow `install` 步把 iPhone 16 与 iOS 18.6 准备好；若 runner 上 18.6 确实拿不到，才允许给脚本加「默认值不变、可用环境变量注入 destination」的注入口，并保持上述正则与本机默认行为不变。
- `lint-ios-shell` 依赖 xcodegen 从 `ios/project.yml` 复核工程（`scripts/check-ios-shell.sh:72-96`），因此 CI `install` 步必须装 xcodegen，否则 lint 会直接红。
- Workflow 内不得出现根 `VERSION` 字面值；需要版本时调用 `bash scripts/version.sh`。
- YAML 校验口径：本机无 actionlint，用 `ruby -ryaml`（`/usr/bin/ruby`）或 `python3` 解析；注意 Psych 遵循 YAML 1.1，会把裸 `on` 解析为布尔 `true`，断言脚本应按原文/AST 处理 `on` 键，避免误判成「缺 on」。
- code-gates 的 `command` 必须是单一 argv（无 `&&`、`|`、`;`、重定向、反引号），多步逻辑封装进 `scripts/check-ios-workflow.sh`；新增门不得替换或放宽既有 10 条门。
- Delivery 只推分支：一次推送即应触发 `.github/workflows/ios.yml`；推送后按 `gh run list --repo munk-sh/open-pace --workflow ios.yml` 轮询取 run id，取不到就记 `pending: 待 remote 验证`，不要为了等 run 反复推空提交。
- 证据口径：只报真实命令输出摘要、run id 与 conclusion；CI 红按失败处理，不得以本地绿替代远端 run。
