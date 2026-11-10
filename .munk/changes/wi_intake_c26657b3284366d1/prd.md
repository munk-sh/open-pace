# PurePace 唯一最终 Release 候选包（main tip 2c7c4f3）

## Scope

从 `origin/main` 真实 tip（Intake 实测 `2c7c4f36dfdc09acfb37a3888f206512b42e7eb2` = `2c7c4f3 munk delivery: merge wi_intake_abacaa757ba3bd09`）出**唯一** Release 候选包并留下可核验记录。本项只做「出包 + 记账」，**零业务源码改动**。

产出三件物：
1. 可装机 Release `.zip`（`PurePace.app` 压缩，不入 git）；
2. 产品数据目录候选记录 txt：`products/codebase_19e8ad47434ff059/artifacts/candidates/Release-candidate-<tip短sha>.txt`（字段照既有 `Release-candidate-8db1a16.txt`）；
3. 仓内同内容摘要：`docs/release/candidates/Release-candidate-<tip短sha>.md`（纯文本，不放大二进制），使证据在仓内可查、并给本分支一个可交付提交。

同时跑本地阻断门并留下命令与输出摘要。

## Acceptance Criteria

- ac-tip-recorded: 记录中 `commit:` 取的值为 `git fetch origin && git rev-parse origin/main` 的真实输出，且同时写出短 sha（`2c7c4f3`）；若实际 tip 与 Intake 实测不同，以实取值为准并据此命名文件名，不得沿用 2c7c4f3。
- ac-bundle-id: 从**构建产物** `PurePace.app/Info.plist` 读回 `CFBundleIdentifier` 等于 `sh.munk.purepace`；若为 `com.chaxiu.purepace` 则停手回执、不改源码。
- ac-uibackgroundmodes: 构建产物 `Info.plist` 的 `UIBackgroundModes` 实际数组**同时包含** `location` 与 `audio` 两项。
- ac-plist-version: 构建产物 `Info.plist` 读回 `CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0`，与记录里 scheme/target 行一致。
- ac-no-debug-dylib: 构建产物 `.app` 内不存在 `PurePace.debug.dylib`（`find … -name 'PurePace.debug.dylib' | wc -l` 输出 0），且记录中写明 `debugDylibCount=0`。
- ac-signing: `codesign -dv` 摘要显示 `TeamIdentifier=3X4J53U6RY` 且 Authority 为 `Apple Development: Tao Zhu (H47755VBGF)`；签名参数只出现在命令行，`git diff` 中 `ios/project.yml` 无任何签名/team 变更。
- ac-zip-sha: 记录中 `zipSha256` 与 `zipBytes` 与对产出的 zip 实跑 `shasum -a 256` 及字节数逐字一致（含 64 位十六进制与整数字节）。
- ac-exec-sha: 记录中 `execName=PurePace`、`execSha256`、`execBytes` 与解包后主二进制 `PurePace.app/PurePace` 的实算 `shasum -a 256` 及字节数逐字一致。
- ac-record-parity: 产品数据目录 txt 与仓内 `docs/release/candidates/*.md` 的 commit / zipSha256 / zipBytes / execSha256 / execBytes / UIBackgroundModes 数组六项取值完全相同（md 为同一事实的摘要，不得出现两套数字）。
- ac-record-fields: txt 含 `builtAt` / `commit` / `buildConfig` / `signingIdentity` / `provisioningProfile` / `scheme-target`（bundle id、version、MinimumOSVersion）/ `zipPath` / `zipSha256` / `zipBytes` / `execName` / `execSha256` / `execBytes` / `infoPlist` 读回 / `codesign` 摘要 / `验收键` / `iosCI` / `note` 全部非空字段；`验收键` 行明确写 zip sha256 + 设备侧已装包自报，exec sha 为辅助。
- ac-launch-arg-gating: Release 二进制中存在字符串 `-releaseDeterministicLocation`（`strings`/`nm` 或 `scripts/check-ios-shell.sh` 结构断言为旁证），且记录/回执写明「无该 flag 时仍走真实 CoreLocation」的代码层断言落在 `ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift`（含默认关的负例）。
- ac-gates-green: 本地阻断门全部退出码 0：lint 系列（`check-baseline` / `check-ios-core` / `check-ios-scripts` / `check-ios-release` / `check-ios-shell` / `check-ios-workflow` / `check-ios-run-core` / `check-shared` / `check-shell-expansion` / `version.sh`、`bash -n`）、`swift build|test --package-path ios/Core`、`swift build|test --package-path ios/RunCore`、`bash scripts/test-ios.sh --unit-only`（`PurePaceTests` 单测腿）；每条命令与结果摘要进回执。重 UI E2E 不在本地阻断集合。
- ac-ci-recorded: 记录 `iosCI:` 行给出与同一 commit 绑定的 `.github/workflows/ios.yml` run 标识或明确「待出结论」状态，不得留空、不得写成已绿而未核。
- ac-zip-outside-git: 产出的 zip 位于产品数据目录（仓库外），`git ls-files` 中不含该 zip 路径；`docs/release/candidates/` 只提交 md 文本。
- ac-no-source-diff: 相对 tip 的改动文件集合只含 `docs/release/candidates/**`（以及 `.munk/changes/{workItemId}/prd.md` 等流水线元数据），`ios/`、`shared/`、`android/`、`ios/project.yml`、`.github/workflows/**`、`.munk/code-gates.json`、`.munk/baseline/**` 零改动。

## Non-Goals

- 不改任何业务源码（`ios/`、`shared/`、`android/`），不改 `ios/project.yml`、CI workflow、门禁断言、`.munk/baseline/**` 文本。构建失败且需改码时立即停手上报 Owner（本项无改码授权）。
- 不 push tag、不建/改 GitHub Release、不上传 TestFlight、不建 ASC 记录、不重试 `produce` / `sigh`（PLA 未接受必 403）。
- 不写「真机已验证」；不排真机窗口、不驱动锁屏（窗口由公司约）。
- 不在本地长跑重 UI E2E（`verify-ios-ui-e2e` / `verify-ios-sim-runtime`）；权威在 `ios.yml` 同 commit run。
- 不动 bundle id 之外的标识、不加第三方依赖、不调整版本号真源（`VERSION` 保持 0.1.0）。
- 不为「反正要出包」顺手修文档、改脚本或扩 scope。

## Implementation Constraints

**已核实的事实锚点（Intake 阶段实查，非推测）**
- `git rev-parse origin/main` = `2c7c4f36dfdc09acfb37a3888f206512b42e7eb2`（短 sha `2c7c4f3`），worktree HEAD 与之相同、工作区干净。
- `ios/project.yml:34` `PUREPACE_BUNDLE_ID: sh.munk.purepace`（迁移已生效于真源）。
- `ios/project.yml:45-50` base Info.plist 承载 `UIBackgroundModes: [location, audio]`。
- `VERSION` = `0.1.0`；`ios/project.yml` `CURRENT_PROJECT_VERSION: "1"`、`IPHONEOS_DEPLOYMENT_TARGET: "17.0"`。
- `-releaseDeterministicLocation` 定义于 `ios/PurePace/Location/ReleaseDeterministicLocationSource.swift:13`，注入判定在 `RunLocationSourceSelection`，默认关断言在 `ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift`。
- `xcodegen` = `/opt/homebrew/bin/xcodegen`，`xcodebuild` = `/usr/bin/xcodebuild` 均在 PATH。
- 既有记录格式基准：`products/codebase_19e8ad47434ff059/artifacts/candidates/Release-candidate-8db1a16.txt`（该目录已存在，另有 ccd6037 / 1e7e653 / 73eb801 / 667e1bc 四条历史记录）。

**用户已定的操作口径（照做，不重议）**
1. 从 tip 建工作分支（不改源码）；`xcodegen generate --spec ios/project.yml` 生成工程，**禁止手改 pbxproj**。
2. 构建：`xcodebuild -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates`；签名身份应为 `Apple Development: Tao Zhu (H47755VBGF)` / Team `3X4J53U6RY`；签名参数仅在命令行临时给，**不得写进 project.yml**。
3. 断言从**构建产物** `.app/Info.plist` 读回（不得只核源 plist）。
4. 双 sha 全部真算：zip 本体 `shasum -a 256` + 字节数；解包后主二进制 `PurePace` 的 sha256 + 字节数。**禁止编造**。
5. 记录字段照 `Release-candidate-8db1a16.txt` 排版；zip 与 txt 同放 candidates 目录，zip 不入 git。
6. 仓内摘要落到 `docs/release/candidates/Release-candidate-<tip短sha>.md`（该目录当前不存在，需新建）。

**失败处置**：签名 / provisioning 失败 → 原文回执停手（凭据或承载层问题），**不得**把签名配置写进 project.yml 绕过；需要改业务源码才能修 → 立即停手上报 Owner。
