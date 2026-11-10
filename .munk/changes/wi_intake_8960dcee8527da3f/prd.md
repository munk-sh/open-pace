# PurePace 0.1.0 一次性 Release 候选出包（7ce3dfe，真机验收用，非 TestFlight）

## Scope

从 main tip `7ce3dfef6e179c6d62857efb8b1c411ccf4a38b8` 干净 worktree 拉出，只做四件事：

1. **Release 构建**：`xcodegen generate --spec ios/project.yml` → `xcodebuild -configuration Release -destination 'generic/platform=iOS'` 签名（签名参数仅命令行）。
2. **双 sha256**：zip 与 `.app` 主二进制各跑 `shasum -a 256` + `stat -f%z`，真实计算。
3. **模拟器干净安装启动冒烟**：iPhone 16 UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`，`simctl erase` → install → launch，留截图 + 首屏元素树 + 进程存活证据。
4. **候选 txt（全字段）+ 仓内 md 摘要**：`Release-candidate-7ce3dfe.txt` 落 `artifacts/candidates/`（与 `Release-candidate-2c7c4f3.txt` 同目录同字段），仓内另提交 `docs/release/candidates/Release-candidate-7ce3dfe.md`（不含 zip）。

时间盒 ≤45 分钟、≤8M token；超时即停手并出部分回执。同一 sha 只建一次。

### 路径口径（消歧，避免歧义）

`artifacts/candidates/` 指**产品数据目录**（仓外，zip 本体不入 git，沿用 2c7c4f3 先例）：

- zip：`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/PurePace-Release-0.1.0-<UTC>.zip`
- txt：`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/Release-candidate-7ce3dfe.txt`
- md 摘要（入库）：`<worktree>/docs/release/candidates/Release-candidate-7ce3dfe.md`

txt 中 `zipPath` 必须写上述**绝对路径**。

## Acceptance Criteria

- ac-tip-verified: 开工先跑 `git ls-remote --heads origin main` 并记录结果；若结果不等于 `7ce3dfef6e179c6d62857efb8b1c411ccf4a38b8`，须在回执与 txt 写明新 tip 与差异且不构建旧 commit；当前已核 = 基线，无差异
- ac-project-generated: `xcodegen generate --spec ios/project.yml` 退出码 0，构建所用 `.xcodeproj` 由该命令生成；全程无手改 `project.pbxproj`（`git status --porcelain ios/` 为空）
- ac-release-build-ok: 指定 xcodebuild Release 命令退出码 0，产出 `Build/Products/Release-iphoneos/PurePace.app` 且目录非空
- ac-no-debug-dylib: 构建/解包后的 `PurePace.app` 内 `find PurePace.app -name 'PurePace.debug.dylib' | wc -l` 输出 `0`（debugDylibCount=0）
- ac-plist-bundle-id: 从 zip 解包后读 `.app/Info.plist`，`CFBundleIdentifier` == `sh.munk.purepace`
- ac-plist-version: 同一 plist 中 `CFBundleShortVersionString` == `0.1.0` 且 `CFBundleVersion` == `1`
- ac-plist-minos: 同一 plist 中 `MinimumOSVersion` == `17.0`
- ac-plist-background-modes: 同一 plist 中 `UIBackgroundModes` 为**实际数组**（PlistBuddy `Print` 输出定义数组），元素按序 == `["location", "audio"]`；必须针对 `PurePace.app` 本体，不得用 UITests runner 的 audio-only plist 代替
- ac-strings-location-flag: 对 `.app` 主二进制跑 `strings`，命中 `-releaseDeterministicLocation`
- ac-strings-autostart-flag: 对 `.app` 主二进制跑 `strings`，命中 `-autoStartRecording`
- ac-codesign-authority: `codesign -d --verbose=4 PurePace.app` 输出中 `Authority` 含 `Apple Development: Tao Zhu (H47755VBGF)`
- ac-codesign-team: 同一输出中 `TeamIdentifier=3X4J53U6RY`
- ac-signing-not-in-spec: `git diff --exit-code ios/project.yml` 退出码 0（签名/team 未写入 project.yml；其 `CODE_SIGNING_ALLOWED: NO` 原样保留，由命令行覆盖）
- ac-zip-created: 候选 zip 存在于上述绝对路径，命名为 `PurePace-Release-0.1.0-<UTC>.zip`（UTC 形如 `20261110T014651Z`），`zipBytes` > 0
- ac-zip-sha: `zipSha256` 由 `shasum -a 256` 实测、64 位小写十六进制，且与 txt 记录逐字一致
- ac-exec-sha: 解包 zip 后对 `PurePace.app/PurePace` 实测 `execSha256`（64 位）+ `execBytes`，与构建产物本体及 txt 记录三者一致
- ac-smoke-erase-install-launch: 在 UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD` 上 `simctl erase` → `boot` → `install` → `launch` 命令全部退出码 0，`launch` 输出 bundle id `sh.munk.purepace`；全程不使用真机
- ac-smoke-process-alive: launch 后进程仍存活（`simctl launch` 后再取进程/`launchctl list` 命中 `sh.munk.purepace`），证明非启动即崩溃
- ac-smoke-evidence: 冒烟留存三类证据文件（截图 png + 首屏元素树 dump + 进程存活输出），路径写入 txt 冒烟结果行与 md 摘要
- ac-txt-complete: `Release-candidate-7ce3dfe.txt` 存在且字段与 `Release-candidate-2c7c4f3.txt` 同级齐全：zipPath（绝对）、zipSha256、zipBytes、execName、execSha256、execBytes、buildConfig、signingIdentity、provisioningProfile、commit、plist 数组 dump（UIBackgroundModes）、冒烟结果、`iosCI` 待出结论一行；缺任一字段即不通过
- ac-txt-obsolete-declaration: txt 内含明示声明「旧包 2c7c4f3 / 1e7e653 / 667e1bc 全部作废不得复用」
- ac-md-summary: `<worktree>/docs/release/candidates/Release-candidate-7ce3dfe.md` 存在，与 txt 同值摘要，且 **zip 二进制不入 git**（`git status --porcelain` 中无 `.zip`）
- ac-single-build-per-sha: 对 commit `7ce3dfef…` 只产出一次候选；`artifacts/candidates/` 下该 commit 只有 1 个 zip + 1 个 txt（重跑须先声明并作废旧包）
- ac-no-source-change: 相对 tip 的改动仅限 `.munk/changes/wi_intake_8960dcee8527da3f/**` 与 `docs/release/candidates/Release-candidate-7ce3dfe.md`；`git diff --stat` 对 `ios/`、`scripts/`、`shared/`、`android/` 为空
- ac-no-tag-no-push-no-testflight: 未打 tag、未 push tag、未建/改 GitHub Release、未上传 TestFlight、未建 ASC 记录、未真机装包；`git tag` 无新增
- ac-no-full-gates-rerun: 不执行全量 code_gates（不批量跑 `scripts/check-*.sh`、不重跑 UI E2E）；若出包过程确需单项结构断言，须在 txt `note` 注明单项名称与原因
- ac-time-box: 自开工至回执 wall clock ≤45 分钟；触及上限即停手出部分回执（列已完成项 + 未完成原因），不继续消耗
- ac-receipt-fields: 回执必须含：zip sha256、exec sha256、commit、zip 绝对路径、四项必核结果（debugDylibCount / plist dump / strings 两 flag / codesign authority+team）、冒烟结果

## Non-Goals

- 不重跑全量 code_gates / 不跑 UI E2E / 不打 tag / 不 push / 不建 GitHub Release
- 不碰 TestFlight、App Store Connect、ASC 记录
- 不真机装包、不做设备侧验收（设备留给验收窗口）
- 不改任何源码、脚本、`project.yml`、`.munk/code-gates.json`
- 禁止手改 `project.pbxproj`
- 不做 UI/逻辑调整、不做顺手优化、不扩大改动半径

## Implementation Constraints

### 已核实的环境与事实（开工即用，不必重复大范围勘探）

- **main tip 已核对**：`7ce3dfef6e179c6d62857efb8b1c411ccf4a38b8` == 基线，无前进、无需记录差异。
- 工具链：`xcodegen 2.46.0`（`/opt/homebrew/bin/xcodegen`）、`Xcode 26.3 (17C529)`、`/usr/bin/xcodebuild`。
- 模拟器：`iPhone 16 (B3F00298-E08A-41E0-876E-6E8A75C730FD)` 当前 **Booted**。
- 仓库状态干净（`git status --short` 为空），根 `VERSION` = `0.1.0`。

### 关键约束

- **`ios/project.yml` 第 33 行 base 已含 `CODE_SIGNING_ALLOWED: NO`**。命令行 `CODE_SIGNING_ALLOWED=YES` 优先级高于工程设置，这是出包能签名的前提；**严禁**为了让签名生效去改 `project.yml`。签名/team/profile 一律只出现在 xcodebuild 命令行。
- `PUREPACE_BUNDLE_ID: sh.munk.purepace`（`project.yml:34`）→ 目标 `CFBundleIdentifier`。
- `UIBackgroundModes` 在 `project.yml:48-50` 是 **App target** 的 `["location","audio"]`；`project.yml:91-92` 另有一份 **UTests runner** 的 audio-only。plist 核验必须打 `PurePace.app` 本体，别错拿 runner。
- 两个 launch-arg 常量确认在源码内：`ios/PurePace/Location/ReleaseDeterministicLocationSource.swift:13`（`-releaseDeterministicLocation`）、`ios/PurePace/Run/RunLaunchArguments.swift:5`（`-autoStartRecording`）。`strings` 命不中说明二进制被裁剪或产物拿错，必须停下排查而不是改 AC。
- 版本真源：根 `VERSION` → `scripts/sync-ios-version.sh` → `ios/Config/Version.xcconfig`（`project.yml` 的 configFiles 引用）。不要在 project.yml 或源码写版本字面值。
- 参考基线（字段模板，逐字对齐）：`products/codebase_19e8ad47434ff059/artifacts/candidates/Release-candidate-2c7c4f3.txt` 与仓内 `docs/release/candidates/Release-candidate-2c7c4f3.md`。
- 派生数据建议 `-derivedDataPath .build/release-candidate-7ce3dfe`（已在 `.gitignore` 的 `.build/` 内）。
- 冒烟证据建议落 `.build/release-candidate-7ce3dfe/smoke/`（同样不入 git），路径写进 txt。
- `iosCI` 行写「7ce3dfe ios run 待出结论」并把 run 链接留空/待补；不得编造 run id 或结论。
