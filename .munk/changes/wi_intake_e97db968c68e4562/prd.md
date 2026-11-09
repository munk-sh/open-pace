# 设备取证套件跟随 sh.munk.purepace + 从 main tip 出最终 Release 候选包

## 范围

前置事实（Intake 已核）：worktree 源自 main tip `667e1bcf`（产品标识已迁到 `sh.munk.purepace`，`ios/project.yml` 的 `PUREPACE_BUNDLE_ID: sh.munk.purepace`，pbxproj 由 xcodegen 生成且同值）。`git grep -n 'com\.chaxiu\.purepace' -- ios scripts docs` 当前命中 6 条：`docs/evidence/stage3-e2e/report.json`（2，历史证据）、`scripts/verify-ios-device-flow.sh`（2，usage 说明 + 默认值）、`docs/device-assertion-matrix.md`（2，(a) 档与批次 A1 说明）。`ios/PurePaceUITests/DeviceFlowUITests.swift` 内无旧 bundle id 字面量（只有 `com.apple.*`），无需改动。

**A. 设备取证套件跟随新 bundle id（零新建基建）**
1. `scripts/verify-ios-device-flow.sh`：第 43 行 usage 说明与第 58 行 `bundle_id="${PUREPACE_BUNDLE_ID:-com.chaxiu.purepace}"` 的默认值改 `sh.munk.purepace`；保留 env 覆盖语义（`PUREPACE_BUNDLE_ID` 优先）。不改脚本其它任何逻辑、断言、等待、退出码。
2. `docs/device-assertion-matrix.md`：`## 构建身份与档位` 段 (a) 与批次 A1 说明里的 bundle id 改 `sh.munk.purepace`；三档标注（Debug 可断言 / Release 候选包可断言 / 只能人耳）与 A1/A2/B 三表结构不动；(b) 段历史候选 sha256 `7258…` / commit `8db1a167` 属历史记录，保持原样不改写。
3. `docs/evidence/**`、`artifacts/**` 一律不动。

**B. 出最终 Release 候选包（真机窗口用，非 TestFlight 发布包）**
1. 从本 worktree（=`667e1bcf` 树）`xcodegen generate --spec project.yml`（在 `ios/` 内，禁手改 pbxproj，生成后 `ios/PurePace.xcodeproj` 应零 diff）。
2. `xcodebuild -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates`，派生数据落仓内 `.build/`（不进 git）。
3. 打包冻结后的 `.app` 为 zip，落 `<productDir>/artifacts/candidates/PurePace-Release-0.1.0-<UTC时间戳>.zip`，`<productDir>` = `/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059`（仓外，与既有候选同目录）。
4. 记录 `<productDir>/artifacts/candidates/Release-candidate-667e1bc.txt`，字段与顺序沿用 `Release-candidate-8db1a16.txt`：builtAt / commit / buildConfig / signingIdentity / provisioningProfile / scheme+target / zipPath / zipSha256 / zipBytes / execName / execSha256 / execBytes / infoPlist dump 行 / codesign / 验收键口径 / iosCI / note。
5. 实算并记录：zip sha256 与字节数、主可执行文件 sha256 与字节数、构建配置、签名身份、provisioning profile、commit sha；plist 一律从**解压后 `.app/Info.plist` 本体**读回（不得抄 `project.yml`）。

## 验收

- ac-legacy-id-grep-exempt-only: `git grep -n 'com\.chaxiu\.purepace' -- ios scripts docs` 命中仅 `docs/evidence/**`（当前 2 条于 `docs/evidence/stage3-e2e/report.json`）；`scripts/` 与 `docs/` 的非 `docs/evidence/` 路径零命中。
- ac-device-script-default-id: `scripts/verify-ios-device-flow.sh` 内 `sh.munk.purepace` 出现 ≥ 2 处（usage 说明 + 默认值），且 `bundle_id="${PUREPACE_BUNDLE_ID:-sh.munk.purepace}"` 精确命中 1 处（env 覆盖能力保留）；`bash -n scripts/verify-ios-device-flow.sh` 退出 0。
- ac-device-script-not-weakened: 该脚本 `continue-on-error` 零命中、`set -euo pipefail` 仍在、`--phase` 三值（audit|audio|background）与 `pending: 待人现场` 文案仍在；`git diff 667e1bc -- scripts/verify-ios-device-flow.sh` 只改 bundle id 相关 2 行。
- ac-matrix-bundle-id-updated: `docs/device-assertion-matrix.md` 中 `com.chaxiu.purepace` 零命中，`## 构建身份与档位` 段 (a) 与批次 A1 说明写 `sh.munk.purepace`；三档标签与 `## 批次 A1` / `## 批次 A2` / `## 批次 B` 三个标题仍在（批次数量不变）。
- ac-matrix-structure-intact: matrix 的 (b) 历史候选行仍为 `zip sha256 \`7258…\`` 与 `commit \`8db1a167\``（历史不改写），且 `pending: 待人现场` 表述仍在（真机项不写成通过）。
- ac-no-evidence-rewrite: `git diff 667e1bc -- docs/evidence artifacts shared ios/PurePace ios/Core ios/RunCore android .github` 为空（历史证据、业务源码、共享契约、CI workflow 零改动）。
- ac-gates-green: `code_gates` 全部 22 门本地真实执行为退出 0（含 lint* / build-ios-core / build-ios-run-core / build-ios / test-ios-core / test-ios-run-core / test-ios / build-android / test-android / test / check-*），不得 skip、不得 continue-on-error。
- ac-candidate-zip-hash: `<productDir>/artifacts/candidates/PurePace-Release-0.1.0-<UTC>.zip` 存在且 `zipBytes > 0`；记录中 `zipBytes` == `stat -f%z <zip>`，`zipSha256` == `shasum -a 256 <zip>` 实算值（64 位小写十六进制）。
- ac-candidate-exec-hash: 从 zip 解压得到的 `.app/PurePace` 可执行文件 `stat -f%z` / `shasum -a 256` 与记录中 `execBytes` / `execSha256` 完全一致，且 `execSha256` 为 64 位十六进制非占位。
- ac-candidate-plist-readback: 从 zip 解压的 `.app/Info.plist` 读回并写入记录：`CFBundleIdentifier=sh.munk.purepace`（精确相等）、`UIBackgroundModes` 实际数组同时含 `location` 与 `audio`、`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0`；记录文本对应行可直接 grep 出 `CFBundleIdentifier=sh.munk.purepace` 与 `UIBackgroundModes=["location","audio"]`（顺序可变，须含两项）。
- ac-candidate-identity: 记录含 `buildConfig` 为 Release 且 `.app` 内 `PurePace.debug.dylib` 不存在（debugDylibCount=0）；`signingIdentity` 含 `Apple Development` 与 `Team 3X4J53U6RY`；`provisioningProfile` 非空；`commit` 与 `git rev-parse HEAD` 前 7 位 `667e1bc` 一致（完整 sha 一并记录）。
- ac-candidate-record-format: `Release-candidate-667e1bc.txt` 每项一行、含「验收键: **zip sha256 + 设备安装后 bundle Info.plist 实际数组**；exec sha 只作辅助记录」口径行；不含 `TBD` / `<sha256>` / `PLACEHOLDER` 等占位，且 `zipSha256` 不等于旧包 `7258d2e3…`（不得抄旧包）。
- ac-no-external-side-effects: `git tag --points-at HEAD` 无新增 tag、无 `git push`；`git diff 667e1bc -- ios/project.yml .github/workflows` 为空（签名配置不进 project.yml 主干、workflow 不改）；记录中真机三项仍为 `pending: 待人现场`。

## 非目标

- 不改任何业务源码（CoreLocation / AudioSession / 持久化 / UI / 状态机一律不动），不加 `#if DEBUG` 之外的运行期分支。
- 不改 `.github/workflows/*`；不把签名/Team 配置写进 `ios/project.yml` 主干；不手改 `project.pbxproj`。
- 不推 tag、不建 GitHub Release、不做 TestFlight / App Store Connect 上传（对外副作用不在本项）。
- 不排人、不起真机场、不约窗、不提 assist；真机三档验收仍记 `pending: 待人现场`。
- 不新建任何设备取证基建（第二条脚本 / 第二套 driver / 新 report 格式）；不重写 `docs/evidence/**` 与 `artifacts/**` 历史证据。
- 不弱化任何断言、不删用例、不把设备套件改成 `continue-on-error`；matrix 的 (b) 历史候选 sha/commit 不改写。
- 重 UI E2E（`verify-ios-ui-e2e.sh` / `verify-ios-sim-runtime.sh` 真跑）不进本地阻断集合，最多作旁证，不作为本项通过条件。

## 实现约束

- 工具链已核：Xcode 26.3（17C529）、xcodegen 2.46.0、签名身份 `Apple Development: Tao Zhu (H47755VBGF)`、`DEVELOPMENT_TEAM=3X4J53U6RY`（另有 Developer ID 与另一开发证书，构建命令里显式指定 team 即可）。
- 版本 0.1.0(1) 来自根 `VERSION` + `ios/Config/Version.xcconfig`（由 `scripts/sync-ios-version.sh` 生成，勿手改）；如需先同步再 `xcodegen generate`。
- 记录格式对齐 `Release-candidate-8db1a16.txt`（字段顺序与 `验收键` 行口径逐字沿用），只换成本次实算值与 `sh.munk.purepace`。
- 解压校验用仓外临时目录（如 `${TMPDIR:-/tmp}/purepace-candidate-667e1bc/`）或 `.build/`，不得把解压产物落进 tracked 路径污染 `git status`。
- 候选 zip 落在 `<productDir>/artifacts/candidates/`（仓外，与既有 5 个候选包同目录）；仓库内 `artifacts/` 只存既有 device-audit 证据，不新增。
- 预算：≤12M token、≤90 分钟自开工起；超时即停手交回执（写明已达成项与缺口），不靠长会话反复补绿。
- 真机驱动脚本的 env 覆盖保持原语义：`PUREPACE_BUNDLE_ID` / `PUREPACE_DEVICE_UDID` / `--device` 均不受本次改动影响。
