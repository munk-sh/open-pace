# Domain: ci

PurePace 远端持续集成域：以 `.github/workflows/ios.yml` 为唯一 iOS 远端门，`macos-latest` 单 job 按 `install` → `lint` → `test` → `build` 顺序全量复用 `scripts/` 既有本地命令，不放行 SwiftPM 降级分支；workflow 的语法与结构由本机 `scripts/check-ios-workflow.sh` 回归。不含 Android workflow、真机签名、分发与任何仓库设置类变更。

## 范围

- `.github/workflows/ios.yml`：`name: ios`，`on.push`（不限分支/标签，推任意分支即触发）与 `workflow_dispatch`，`permissions.contents: read`；单 job `runs-on: macos-latest`，承载 `checkout` → `install` → `drift` → `lint` → `test` → `build` 六步（`drift` 为自 `wi_intake_af1e1082643399d9` 起的构建前置校验，不计入 install/lint/test/build 顺序锚点）。
- `drift` 步：`rm -rf` 生成目录后由 `xcodegen generate --spec ios/project.yml --project ios` 重建、`git ls-files` 断言无 tracked `project.pbxproj`、`PurePace` shared scheme 非空且 `xcodebuild -list` 可见；仅允许 `xcodegen` 与 `xcodebuild -list`，不得引入第二套 `xcodebuild build/test`，不得靠 ignored 文件的 `git diff` 充当断言。
- `install` 步负责 runner 侧前置且幂等：`xcodegen` 缺失时经 `brew install xcodegen` 安装；`iOS 18.6` 运行时缺失时经 `xcodebuild -downloadPlatform iOS -buildVersion 18.6` 下载（失败用 `sudo` 重试）并轮询就绪；`iPhone 16` 设备缺失时用 `xcrun simctl create` 按固定 device type + 18.6 runtime 创建并轮询就绪。
- `lint` 步逐条调用既有本地门：`scripts/check-baseline.sh`、`check-ios-core.sh`、`check-ios-scripts.sh`、`check-ios-shell.sh`（各自独立命令行，不合并成一个 `&&` 长串，不新增空转 `echo`/`true` 门）。
- `test` / `build` 步分别执行 `bash scripts/test-ios.sh` / `bash scripts/build-ios.sh` 并透传输出；捕获到 `blocked:` 一律 `exit 1`，其余按脚本退出码透传。
- `scripts/check-ios-workflow.sh`：本机 workflow 结构断言（bash、`set -euo pipefail`、支持 `--help`、幂等、以仓库根为路径基准），用本机已有 `ruby -ryaml` / `python3` 解析 YAML，并自测「改错 `runs-on` / 删除 `test` 步骤 / 去掉 `push` 触发 / 去掉 blocked 失败口径」四种破坏必须被拒绝；自 `wi_intake_af1e1082643399d9` 起追加 `drift` 步骤结构与「非空转」断言及对应负向自测。
- 门禁：`.munk/code-gates.json` 新增 `lint-ios-workflow`（`command` 为单一 argv，指向上述脚本）；既有 10 条门 id 与 command 语义不变。

## 验收

- ac-workflow-exists-and-parses: `.github/workflows/ios.yml` 存在，YAML 可被本机已有解释器解析且含 `name` / `on` / `jobs` 顶层键；不引入 actionlint 等新工具依赖。
- ac-workflow-push-trigger: `on` 含 `push`，未用 `tags` 或分支白名单把「推分支」排除在触发之外（首次推任意分支即触发）；不得只挂 `pull_request`。
- ac-workflow-macos-latest: job 的 `runs-on` 为 `macos-latest`，且只有一个 job 承载 install/lint/test/build。
- ac-workflow-step-order: job steps 中 `install`、`lint`、`test`、`build` 按此顺序出现，每步 `run` 非空。
- ac-install-provisions-xcodegen-and-simulator: `install` 步在后继步骤之前完成「`xcodegen` 可用」与「`platform=iOS Simulator,name=iPhone 16,OS=18.6` 可解析」且幂等；缺设备用 `xcrun simctl create` 建同名设备，缺 iOS 18.6 运行时则下载，或改走 scripts 显式支持的 destination 注入口（UDID / OS）指向 runner 上真实可用的 iPhone 16 与运行时。
- ac-lint-step-reuses-local-gates: `lint` 步调用 `check-baseline.sh` / `check-ios-core.sh` / `check-ios-scripts.sh` / `check-ios-shell.sh` 的真实断言，各自独立命令行。
- ac-test-build-reuse-scripts: `test` 步执行 `bash scripts/test-ios.sh`，`build` 步执行 `bash scripts/build-ios.sh`；workflow 内不出现绕过脚本的第二套 `xcodebuild test` / `xcodebuild build` 调用。
- ac-ci-fails-on-blocked-degradation: 脚本输出 `blocked:` 时对应 workflow 步骤以非零退出码失败，CI 变绿必然意味着 xcodebuild 真跑了 iOS 测试与构建。
- ac-workflow-structural-gate: `scripts/check-ios-workflow.sh` 覆盖 YAML 解析与上述结构断言，并在 `.munk/code-gates.json` 注册为单一 argv 的 lint 门；本机执行退出 0，人为破坏 workflow（改错 `runs-on`、删除 `test` 步骤、去掉 `push` 触发）后非零退出并指出具体失败项，恢复后退出 0。
- ac-ci-drift-step-present: `.github/workflows/ios.yml` 存在 `drift` 步骤（位于 `install` 之后），其 `run` 非空且执行 `xcodegen generate`（spec 指向 `ios/project.yml`），并在同一步骤内包含三项断言：生成成功、`git ls-files` 过滤 `project.pbxproj` 为空、`PurePace` shared scheme 存在且 `xcodebuild -list` 可见；任一条不满足时以非零退出。
- ac-ci-drift-not-vacuous: drift 校验不依赖对 ignored 文件的 `git diff`；`check-ios-workflow.sh` 对「删除 drift 步骤 / 去掉索引断言 / 去掉 scheme 断言 / drift 改用 `git diff`」均判失败，并用桩 `xcodegen` / `xcodebuild` / `git` 实跑 drift 体，证明 tracked pbxproj 非空、scheme 缺失、scheme 未被列出三种篡改都会真实失败（断言非恒真）。
- ac-workflow-structure-kept: `check-ios-workflow.sh` 既有 install/lint/test/build 顺序（忽略额外步骤）、`blocked:` 失败口径、test 硬超时与有界重试断言保持通过；workflow 内除 drift 步的 `xcodebuild -list` 外不出现第二套 `xcodebuild build` / `xcodebuild test`，drift 步骤不得插入根 `VERSION` 字面值或「CI 通过」类措辞。
- ac-existing-gates-unchanged-green: `.munk/code-gates.json` 既有 10 条门 id 与 command 语义不变（`test` 仍为 `bash scripts/check-baseline.sh`）；`build-ios.sh` / `test-ios.sh` 仍走 xcodebuild 分支，`check-ios-scripts.sh` 的 iPhone 16 destination 断言未被放宽。
- ac-no-version-literal: 新增/修改的 workflow 与 `scripts/*.sh` 不出现根 `VERSION` 当前字面值，版本只经 `scripts/version.sh` 取得。
- ac-runner-simulator-mismatch-not-silent: 无论下载 iOS 18.6 还是注入 runner 实际可用 destination，scripts 源码中 `iPhone 16` 与显式 `OS=`/`id=` 的 destination 契约字面量仍在，本机默认行为不变；不得为适配 runner 删除机型或 OS 断言。
- ac-branch-only-push: Delivery 只经 Host 工具推本分支触发 Actions；不推 tag、不建 Release、不改 origin URL、不新增 remote、不向远端 seed 任何内容（`git tag -l` 无新增、`git remote -v` 与推送前一致）。
- ac-real-green-run-id: run 产出后证据必须是真实 run：`conclusion=success` 且带数字 run id 与 workflow 名，来源为 `gh run list --repo munk-sh/open-pace --workflow ios.yml` / `gh run view <id>` 或 Host CI 通道原始输出摘要。
- ac-pending-honest: run 尚未产出（排队/未触发）时，交付摘要逐字记录 `pending: 待 remote 验证`，不得写成「CI 绿」/`blocked`，不得用本地门结果替代远端 run。
- ac-ci-red-blocks-delivery: run 为 `failure`/`cancelled` 时本项不交付，摘要附失败 run id 与失败步骤日志摘要；修复后重新推送取新绿色 run，不沿用旧 run。
- ac-empty-remote-escalation: 若 Delivery 因「远端无默认分支 / 空仓」报错，把错误原文整段写入摘要并回报 Owner，不改用其他 git 工具反复重试。
- ac-no-fake-ci-wording: 摘要、脚本与文档不出现「CI 通过」「CI 已通过」「真机已验证」等未经 run id 支撑的措辞。

## 非目标

- 不新增 `.github/workflows/android.yml`，不做 Android / `shared/` 任何改动。
- 不改动 iOS 业务/UI 源码、`ios/project.yml` 内容与 `ios/PurePace.xcodeproj` 的生成内容（唯一授权：`drift` 步骤按 spec 重建工程并校验；工程生成物不入库见 `ios-shell` 域）。
- 不引入第三方运行时依赖，不引入 actionlint / fastlane / 覆盖率 / 构建产物上传 / 依赖缓存等附加设施。
- 不设置分支保护、required checks、secrets、environment 或任何仓库设置类变更；不推 tag、不建 Release、不新建 remote、不改 remote URL、不 seed 远端。
- 不用 CI 替代或放宽本地门；不在 workflow 内重写一套构建/测试命令。
- 不做真机签名、TestFlight、分发；不做视觉设计与业务功能。

## 实现约束

- 环境事实（2026-11-07）：`origin` = `https://github.com/munk-sh/open-pace.git`，远端已有 `refs/heads/main`（非空仓）；`gh` 可用；本机 `xcodegen` 在 `/opt/homebrew/bin/xcodegen`。
- destination 锚点不可动：`build-ios.sh` / `test-ios.sh` 固定 `platform=iOS Simulator,name=iPhone 16,OS=18.6`；`check-ios-scripts.sh` 用正则断言 `name=iPhone 16` + 可选 `,OS=x` / `,id=UDID`。优先不改脚本，由 `install` 步在 runner 上备齐 iPhone 16 与 iOS 18.6；仅当 18.6 确实拿不到，才可给脚本加「默认值不变、环境变量注入 destination」的注入口，且保持正则与本机默认行为不变。
- `lint-ios-shell` 依赖 xcodegen 从 `ios/project.yml` 复核工程，因此 CI `install` 步必须装 xcodegen，否则 `lint` 直接红。
- Workflow 内不得出现根 `VERSION` 字面值；需要版本时调用 `bash scripts/version.sh`。
- YAML 校验口径：本机无 actionlint，用 `ruby -ryaml`（`/usr/bin/ruby`）或 `python3`；Psych 遵循 YAML 1.1 会把裸 `on` 解析为布尔 `true`，断言脚本按原文/AST 处理 `on` 键，避免误判「缺 on」。
- 门禁口径：`command` 必须是单一 argv（无 `&&`、`|`、`;`、重定向、反引号），多步逻辑封装进 `scripts/check-ios-workflow.sh`；新增门不得替换或放宽既有门。
- 推送口径：一次分支推送即触发 workflow；推送后按 `gh run list` 轮询取 run id，取不到即记 `pending: 待 remote 验证`，不为等 run 反复推空提交。
- 证据口径：只报真实命令输出摘要、run id 与 conclusion；CI 红按失败处理，不以本地绿替代远端 run。
- shell 可移植性（远端实测教训）：macOS runner 的 bash 3.2 在部分 locale（本机复现为 `LANG=zh_CN.UTF-8`）下，`$var` 紧跟全角字符（如 `（` `，` `）`）会把多字节字节并入变量名，报 `unbound variable`。本仓脚本里的参数展开一律写 `${var}`；本地 UTF-8 默认 locale 不报错，只有远端 run 才会暴露，新增脚本须按此写。

## 最近交付证明

- workItemId: wi_intake_af1e1082643399d9（2026-11-10，pass）
- 交付：`ios.yml` 在 `install` 之后新增 `drift` 步骤——按 `ios/project.yml` 重建工程、`git ls-files` 断言无 tracked `project.pbxproj`、`PurePace` shared scheme 非空且 `xcodebuild -list` 可见，三条断言任一失败即非零退出；`scripts/check-ios-workflow.sh` 追加 drift 结构断言与「非空转」断言，并新增四种破坏自测 + 桩 `xcodegen`/`xcodebuild`/`git` 的正向实跑与三种篡改必须失败的自测。
- 验证：`code_gates` 22 门全绿（含 `lint-ios-workflow`）；既有 install/lint/test/build 顺序、`blocked:` 失败口径、test 硬超时与有界重试断言均保持通过。远端 run 结论仍待 Owner 经 guard 观测并记录 run id（`pending: 待 remote 验证`，不以本地绿替代）。
