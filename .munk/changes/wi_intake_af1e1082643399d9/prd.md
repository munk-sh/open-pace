# iOS 工程真源收敛到 XcodeGen 并加 CI drift 校验

## 范围

把 iOS 工程的唯一真源收敛为 `ios/project.yml`（XcodeGen），仓库不再入库 `project.pbxproj`：

- 取消跟踪 `ios/PurePace.xcodeproj/project.pbxproj`（`git rm --cached`），并由 `.gitignore` 忽略生成物；生成后在本地 `git status` 必须干净。忽略范围可自定为整个 `ios/PurePace.xcodeproj/`，或仅 `project.pbxproj`。
- 确认 shared scheme 由 XcodeGen 从 `ios/project.yml` 生成：`xcodegen generate` 后存在 `ios/PurePace.xcodeproj/xcshareddata/xcschemes/PurePace.xcscheme`，且 `xcodebuild -list` 能看到 `PurePace` scheme。scheme 可继续入库，也可随生成物不入库；若仍入库，必须在交付 digest 说明理由。
- 在 `.github/workflows/ios.yml` 增加 drift 校验步骤：从 `ios/project.yml` 生成工程、断言生成成功、断言 tracked `project.pbxproj` 为空（`git ls-files` 过滤 `project.pbxproj`）、断言关键 scheme 存在；任一条失败即非零退出。
- 修掉仍假定 `project.pbxproj` 已入库的脚本/门断言（至少 `scripts/check-ios-shell.sh` 的 pbxproj 路径与额外 pbxproj 检查、`scripts/check-ios-scripts.sh` 的分支判定），保持或加强断言，不得删除、不得降级。
- 更新受影响的 workflow 结构断言（`scripts/check-ios-workflow.sh`），使新增 drift 步骤被真实校验且有负向自测，避免 CI 校验空转。

## 验收

- ac-no-tracked-pbxproj: `git ls-files` 中匹配 `project.pbxproj` 的条目为空（含 `ios/PurePace.xcodeproj/project.pbxproj` 也已不在索引）。
- ac-generated-artifacts-ignored: `git check-ignore -v ios/PurePace.xcodeproj/project.pbxproj` 退出 0（`.gitignore` 规则命中）；`.gitignore` 明确的忽略项包含该生成物（整目录或 `project.pbxproj`）。
- ac-status-clean-after-generate: 执行 `xcodegen generate --spec ios/project.yml --project ios` 后，`git status --porcelain` 输出为空（无 modified/untracked 生成物）。
- ac-scheme-generated-shared: `xcodegen generate` 后 `ios/PurePace.xcodeproj/xcshareddata/xcschemes/PurePace.xcscheme` 存在且非空；`xcodebuild -list -project ios/PurePace.xcodeproj` 输出包含 `PurePace` scheme。
- ac-regen-from-spec-passes-unit-leg: `rm -rf ios/PurePace.xcodeproj` 后，由 `ios/project.yml` 重新生成工程成功（退出 0），随后 `bash scripts/test-ios.sh --unit-only` 单测腿通过（真实 `xcodebuild test` 单测，而非走 `blocked:` 降级）。
- ac-ci-drift-step-present: `.github/workflows/ios.yml` 存在 drift 校验步骤，其 `run` 非空且执行 `xcodegen generate`（spec 指向 `ios/project.yml`），并在同一步骤内包含三项断言：生成成功、`git ls-files` 过滤 `project.pbxproj` 为空、关键 scheme（`PurePace`）存在；任一条不满足时脚本以非零退出。
- ac-ci-drift-not-vacuous: drift 校验不依赖对 ignored 文件的 `git diff`；且该步骤有可复现的负向自测（篡改 tracked pbxproj 集合或删除 scheme 时校验失败），证明断言非恒真。
- ac-workflow-structure-kept: `bash scripts/check-ios-workflow.sh` 退出 0，既有 install/lint/test/build 顺序、blocked 失败口径、test 硬超时与有界重试断言保持通过；workflow 内不出现第二套 `xcodebuild build` / `xcodebuild test` 调用（drift 步骤仅允许 `xcodegen` 与 `xcodebuild -list`）。
- ac-shell-gate-consistent: `bash scripts/check-ios-shell.sh` 退出 0；其 pbxproj 相关断言改为「生成后 pbxproj 确实存在 + `git ls-files` 无 tracked pbxproj + 额外/游离 pbxproj 仍判失败」，不再要求 pbxproj 入库。
- ac-scripts-gate-consistent: `bash scripts/check-ios-scripts.sh` 退出 0；其脚本分支判定与实际一致（工程缺失时由 spec + xcodegen 生成/降级口径），既有字面量与顺序锚点断言未被删除或放宽。
- ac-code-gates-22-green: `.munk/code-gates.json` 仍为 22 门（不新增门腿），在本地按环境要求刷新后 22 门全绿。
- ac-ci-run-green-observed-by-owner: push 后新的 `ios` workflow run 结论为 success，由 Owner 经 guard 观测并记录 run id；run 内不轮询等待。

## 非目标

- 不改 App 业务/UI/测试源码与断言语义（`ios/PurePace/**`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**` 的行为语义不变）。
- 不迁移到 Tuist / Swift Testing，不改依赖模型或 `ios/Core` / `ios/RunCore`。
- 不新增 code-gates 门腿；CI 中新增的是构建前置校验步骤，属本项授权范围。
- 不改 `.github/workflows/android.yml` 与 Android / `shared/` 内容。
- 不改 destination 锚点（iPhone 16 / iOS 18.6），不放宽任何既有门禁断言。
- 不生成交付候选包（本项不出候选包），不做真机 / TestFlight / 分发。
- 不手工编辑 `project.pbxproj` 或任何 `.xcodeproj` 生成内容。

## 实现约束

- `ios/project.yml` 是唯一 spec；`minimumXcodeGenVersion` 保持 `2.46.0`，工程一律由 `xcodegen generate` 生成。XcodeGen 默认把 scheme 写入 `xcshareddata/xcschemes`（shared scheme），本项以生成结果与该默认行为为准。
- 忽略方案二选一，交付 digest 需写明选择：A) 忽略整个 `ios/PurePace.xcodeproj/` 并取消跟踪其下全部生成物（pbxproj / workspace / scheme），可最稳保证 `git status` 干净；B) 仅忽略 `project.pbxproj` 并保留 tracked scheme/workspace，须证明重生成后 `git status` 干净。无论哪种，pbxproj 一律不得入库。
- CI drift 校验必须是真实断言而非 `git diff` ignored 文件：用 `git ls-files` 的索引事实 + 生成退出码 + scheme 文件/`xcodebuild -list` 事实。`scripts/check-ios-workflow.sh` 现有断言禁止 workflow 内出现第二套 `xcodebuild test/build`，drift 步骤只能用 `xcodegen` 与 `xcodebuild -list`；也不得插入根 `VERSION` 字面值或「CI 通过」类措辞。
- `scripts/check-ios-workflow.sh` 的步骤顺序断言只认 install/lint/test/build 且忽略额外步骤；新增 drift 步骤不得重排或删除既有步骤，且每个步骤 `run` 非空。建议在同一脚本内新增 `ac-ci-drift-*` 结构与负向自测断言（加强而非替换）。
- `scripts/check-ios-shell.sh` 现有行为：先 `xcodegen generate` 两次比对 checksum，并要求生成后 pbxproj 存在、含本地包引用、无远程包；同时用 `find . -name project.pbxproj -not -path "./ios/PurePace.xcodeproj/project.pbxproj"` 判「额外 pbxproj」。修改时保留生成/可重复性断言，新增「`git ls-files` 无 tracked pbxproj」，并把游离 pbxproj 判定改为排除 ignored 生成物；不得让 generate 产生的本地文件触发伪红。
- `scripts/check-ios-scripts.sh` 对 `build-ios.sh` / `test-ios.sh` 断言字面量 `ios/PurePace.xcodeproj` 与 `xcodegen generate`、`blocked:`；若脚本分支文案/判定调整，同步更新断言与 `--help` 文案，保持或加强，不得删除。脚本新增参数展开一律写 `${var}`（macOS runner bash 3.2 + 中文 locale 会把全角标点并入变量名）。
- 本地跑 code_gates 前必须先 `xcodegen generate --spec ios/project.yml --project ios`，并重跑 build-for-testing 刷新 `.build/ios`；否则 `ac-built-plist-readback` 会因陈旧产物伪红（2026-11-10 已两次踩到，属环境伪红，不得改产品代码来掩盖）。
- 交付 digest 必须写明：scheme 是否入库及理由（若入库）；drift 校验为何不空转（索引事实 + 生成成功 + scheme 存在，且负向自测能证伪）；`git ls-files` 无 pbxproj 的实际输出摘要；`rm -rf ios/PurePace.xcodeproj` 后重新生成并跑通单测腿的真实命令与结果。
- 预算上限 ≤8M token / ≤90 分钟；超时立即停手并回执，不轮询远端 run。
