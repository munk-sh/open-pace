# Domain: ios-release

PurePace iOS 分发基线域：只交付「仓外产物、可静态校验、可脱敏预演」的归档/导出脚本、静态门与人执行 Runbook。不执行任何 App Store Connect 写操作，不引入 fastlane 等第三方分发依赖，不改签名主干、`ios/project.yml` 与 `.github/workflows/*`。

## 范围

- `scripts/archive-ios.sh`：`xcodegen generate --spec project.yml`（cwd=`ios/`）→ `xcodebuild archive -destination 'generic/platform=iOS'` → `xcodebuild -exportArchive -exportOptionsPlist`；`ExportOptions.plist` 由脚本生成到 `OUT_DIR`（仓外），含 `method=app-store-connect`、`teamID=3X4J53U6RY`、`signingStyle=automatic`、`uploadSymbols=false`。
- 凭据只从环境变量 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` 读取，映射为 `-authenticationKeyPath` / `-authenticationKeyID` / `-authenticationKeyIssuerID` 并带 `-allowProvisioningUpdates`；缺任一变量立即非零退出且只打印变量名，已设置变量的值不得出现在输出。
- `DRY_RUN=1`：不要求凭据、不执行 `xcodegen` / `xcodebuild`、不触网，仍创建 `OUT_DIR` 与非敏感 `ExportOptions.plist`，以字面量 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID` 回显命令并退出 0。
- 版本与 build 号复用既有入口：`MARKETING_VERSION` 取 `bash scripts/version.sh`（可先 `scripts/sync-ios-version.sh`），`CURRENT_PROJECT_VERSION` 取 `BUILD_NUMBER`（缺省 `1`），两者均以 xcodebuild 命令行覆盖，不改 `ios/project.yml`。
- 产物全部落在仓外：默认 `${TMPDIR:-/tmp}/purepace-dist/<version>-<build>`，`OUT_DIR` 可覆盖；归档后复制 `PurePace.app` 与 `PurePace.app.dSYM`，用 `ditto -c -k --keepParent` 打 zip，计算 sha256（`shasum -a 256`，缺失回退 `sha256sum`）并打印 zip/app/dSYM 路径与 sha256、写入 `OUT_DIR/checksums.txt`。
- `scripts/check-ios-release.sh` 静态门：结构沿用 `check-ios-scripts.sh`（`CHECKS`/`FAILURES`、`--help`、退出码 0/1/2、以 `BASH_SOURCE` 推导仓库根），用 `mktemp -d` 跑 `DRY_RUN=1` 与缺 env 负向用例，断言归档脚本契约、`ExportOptions` 真实内容、脱敏、门禁接入、Runbook 必填段落。
- `.munk/code-gates.json` 追加单一 argv 门 `lint-ios-release`（`command` 恰为 `bash scripts/check-ios-release.sh`），门数由 23 变为 24；`scripts/check-ios-scripts.sh` 的门数断言与帮助文案同步为 24，既有门 id/command 语义不变。
- `docs/release/testflight-runbook.md`：前置（ASC App 记录只读检查、三件凭据的环境变量与仓外 `.p8` 绝对路径、人在场要求）、执行步骤、证据归档清单、反范围。
- `README.md`「构建与测试入口」表新增 `archive-ios.sh` 与 `check-ios-release.sh` 两行，不写根 `VERSION` 字面值。

## 验收

- ac-archive-script-contract: `scripts/archive-ios.sh` 存在，`bash -n` 通过，shebang 为 `#!/usr/bin/env bash`，含 `set -euo pipefail`，`--help` 退出 0 且输出含「用法」，未知参数退出 2。
- ac-dry-run-runs-without-credentials: 三个 `ASC_*` 全未设置且 `DRY_RUN=1` 时退出 0，回显包含 `xcodegen generate`、`xcodebuild archive`、`-exportArchive`、`-destination 'generic/platform=iOS'`，且不实际执行 `xcodegen` / `xcodebuild`、不发起网络调用。
- ac-dry-run-output-redacted: 设置伪凭据（`ASC_KEY_PATH=/tmp/FAKE-KEY.p8`、`ASC_KEY_ID=FAKEKEYID`、`ASC_ISSUER_ID=FAKE-ISSUER-UUID`）且 `DRY_RUN=1` 时，输出出现三个 `-authentication*` 参数名，但不出现 `FAKEKEYID`、`FAKE-ISSUER-UUID`、`FAKE-KEY.p8` 这些值。
- ac-missing-env-fails-closed: 非 `DRY_RUN` 下缺少任一凭据变量时脚本立即非零退出，输出只包含缺失变量名；已设置变量的值（如 `ASC_KEY_ID=SECRETID`）不得出现在任何输出中。
- ac-no-secret-literals-or-xtrace: `scripts/archive-ios.sh` 与 `docs/release/testflight-runbook.md` 不含 `set -x`、不含真实 `.p8` 绝对路径（`/Users/`、`/home/`）、不含真实 Key ID / Issuer ID / 密钥字面量；脚本内凭据引用一律为变量。
- ac-export-options-content: 生成的 `ExportOptions.plist` 实际包含 `app-store-connect`、`3X4J53U6RY`、`automatic`、`uploadSymbols` 为 `false`；导出命令同时含 `-exportArchive` 与 `-exportOptionsPlist`。
- ac-version-and-build-wiring: 归档脚本经 `scripts/version.sh` 取 `MARKETING_VERSION`、经 `BUILD_NUMBER`（缺省 1）取 `CURRENT_PROJECT_VERSION` 并以 xcodebuild 命令行覆盖；`ios/project.yml` 未被修改。
- ac-artifacts-outside-repo-and-checksums: 默认输出目录为 `${TMPDIR}/purepace-dist/<version>-<build>` 且支持 `OUT_DIR` 覆盖，归档/导出不向仓库内写产物；结束逻辑含 `.app` 与 `.app.dSYM` 复制、zip 打包、`shasum -a 256`（缺失回退 `sha256sum`）以及 zip/app/dSYM 路径与 sha256 打印。
- ac-release-gate-wired: `.munk/code-gates.json` 新增 `lint-ios-release` 门且 `command` 为 `bash scripts/check-ios-release.sh`，门数 24（该项交付当时的快照；当前本地拓扑为 22 门，见 `ios-ci-stability`）；`scripts/check-ios-scripts.sh` 的门数断言与本域 `check-ios-release.sh` 断言现同步为 22 且该门仍通过。
- ac-release-gate-self-tests: `scripts/check-ios-release.sh` 含负向自检（缺 env 时归档脚本非零退出且无值泄露、`DRY_RUN=1` 输出脱敏），失败非零退出、全通过退出 0。
- ac-runbook-complete: Runbook 含前置（ASC App 记录存在性检查命令、三件凭据的绝对路径与环境变量说明、人在场要求）、执行步骤、证据归档清单（zip/app/dSYM 的 sha256、`xcodebuild -version`、commit）、反范围（不 push tag、不建 Release、不在仓内写 `.p8` / `.env`），命令示例一律使用 `$ASC_KEY_PATH` 等占位符。
- ac-runbook-current-bundle-id: `docs/release/testflight-runbook.md` 声明的当前 bundle id 为 `sh.munk.purepace`（指向 `ios/project.yml` 的 `PUREPACE_BUNDLE_ID` 单点），并注明换 id 后需人侧在 App Store Connect 新建/更新对应 App 记录；历史构建记录里的旧 bundle id 保持原样不改写。
- ac-no-network-or-workflow-changes: 不执行任何 App Store Connect 上传/记录创建；`.github/workflows/*` 触发条件与内容不变；不引入 fastlane 依赖。
- ac-candidate-evidence-keys: Release 候选证据文件（`artifacts/candidates/Release-candidate-*.txt`）至少含 zip **绝对路径**、zip sha256、exec sha256、构建配置、签名身份、合入 main 的 commit sha 与 `mainTipAtBuild`/`treeSha`，以及**构建产物 Info.plist 的 `UIBackgroundModes` 实际数组 dump**；候选验收键固定为 **zip sha256 + 设备侧运行中已装包自报**（跑次 JSON 的 `telemetry.bundle.backgroundModes` / `identifier` / 版本），exec sha 只作辅助记录，不得单以 exec sha 区分新旧包；记录须注明「设备侧＝运行中已装包自报，非文件拷贝断言」。
- ac-candidate-preflight: 出包前断言当前 `main` 已含前置交付（如 `-uiTestLocation` 收录式门控所在 commit，`git log main --oneline` 可回溯），且构建树源码同时含前置门控与本项变更；任一缺失则不构建、不产出 zip/txt，以 `munk_report_owner` 报出缺失依赖后停手，不得先用旧 main 出包再重出。
- ac-candidate-build-provenance: 候选包从默认分支 tip 的 worktree 产出——`ios/` 内 `xcodegen generate --spec project.yml`（`ios/PurePace.xcodeproj` 零 diff），再 `xcodebuild -configuration Release -destination 'generic/platform=iOS'` 且 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates`；派生数据落 `.build/`（不进 git），zip 与记录落仓外 `<productDir>/artifacts/candidates/`。
- ac-candidate-hashes-real: 记录中 `zipBytes` / `zipSha256` / `execBytes` / `execSha256` 均为对 zip 与 zip 内 `.app/PurePace` 实算值（`stat -f%z` / `shasum -a 256`），`zipSha256` 为 64 位小写十六进制且不等于历史候选包（当前基线 `43be04f3…`，更早 `7258d2e3…` / `81b9f2de…`）；记录不含 `TBD` / `<sha256>` / `PLACEHOLDER` 占位。
- ac-candidate-plist-readback: **构建产物** Info.plist 从解压后 `.app/Info.plist` 本体读回，记录可 grep 出 `CFBundleIdentifier=sh.munk.purepace`、`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0` 与 `UIBackgroundModes=["location","audio"]`（顺序可变，两项必含）；**设备侧**一律改为运行中已装包自报，不再用 `devicectl copy from` 读回 Info.plist（该路径无 bundle 域，exit 64，已裁决降级）。
- ac-candidate-identity: 记录含 `buildConfig` 为 Release 且 `.app` 内无 `PurePace.debug.dylib`；`signingIdentity` 含 `Apple Development` 与 `Team 3X4J53U6RY`，`provisioningProfile` 非空，`commit` 与 `git rev-parse HEAD` 前 7 位一致（完整 sha 一并记录）；记录字段顺序与「验收键」口径行沿用既有 `Release-candidate-*.txt`。
- ac-candidate-no-external-side-effects: 出包过程不 `git push`、不打 tag、不建 GitHub Release、不做 TestFlight / ASC 上传；`ios/project.yml` 与 `.github/workflows/*` 零改动（签名配置只走命令行），记录中真机三项仍为 `pending: 待人现场`。

## 非目标

- 不执行任何 App Store Connect 网络调用、上传、App 记录/构建记录创建；不发送 TestFlight 邀请。
- 不安装或引入 fastlane 及任何第三方运行时/构建依赖。
- 不修改 `ios/project.yml` 的签名设置、版本主干或 bundle id；不手写 `project.pbxproj`。
- 不在仓库或日志中写入 `.p8`、issuer、Key ID 或任何 secret；不提交 `.env`。
- 不做 tag、GitHub Release、分发操作，不改 `.github/workflows/*` 触发条件。
- 不重构既有 `build-ios.sh` / `test-ios.sh` / `check-ios-scripts.sh` 的非必要逻辑（仅门数断言与本项接入）。
- 不做真机签名执行、不替代 `ios-ci-stability` 的测试链路；后者「23 门」为该项交付当时的历史快照。

## 实现约束

- 签名覆盖：`ios/project.yml` 基线为 `CODE_SIGNING_ALLOWED: NO`，归档时必须用 CLI 覆盖 `CODE_SIGNING_ALLOWED=YES` / `CODE_SIGNING_REQUIRED=YES` / `CODE_SIGN_STYLE=Automatic` / `DEVELOPMENT_TEAM=3X4J53U6RY`，不得改 `project.yml`。
- 工程生成：在 `ios/` 内执行 `xcodegen generate --spec project.yml`（`project.yml` 是唯一真源）；导出阶段不再 generate。
- 脱敏口径：`DRY_RUN=1` 回显字面量 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID`（不展开变量值）；失败提示只遍历变量名（如 `archive-ios: 缺少环境变量 ASC_ISSUER_ID`），绝不 `printf` 变量值；禁用 `set -x`。
- 目录创建顺序：`DRY_RUN` 也要先建 `OUT_DIR` 并写 `ExportOptions.plist`，静态门据此断言真实生成内容而非只读源码。
- 门禁口径：新增门 `command` 必须单一 argv（无 `&&`、`|`、`;`、重定向），多步断言封装进 `scripts/check-ios-release.sh`；`scripts/check-ios-scripts.sh` 只改门数相关两处（帮助文案与 `-ne 24` 判定），不改其它断言。
- 脚本契约：`#!/usr/bin/env bash` + `set -euo pipefail` + `--help` 退出 0 含「用法」+ 未知参数退出 2；路径以 `BASH_SOURCE` 推导的仓库根为基准；参数展开一律 `${var}`（macOS bash 3.2 与 `check-shell-expansion.sh` 卫生口径）。
- Runbook 口径：只给可离线复述的 `xcrun altool --list-apps` / ASC API 只读说明，上传与记录创建明确写为人的写操作；不得出现任何真实凭据值或根 `VERSION` 字面值。
- 门数现状：本域落地时为 24 门；`wi_intake_11dc6b68d0c7555d` 起本地门拓扑收敛为 22 门（`test-ios` = `--unit-only`，两条模拟器重腿移出本地阻断，权威覆盖回 CI `ios.yml`），本域 `check-ios-release.sh` 的门数断言随之同步 22；其它域交付证明里出现的门数为当轮快照，不回写。

## 最近交付证明

- workItemId: wi_intake_e97db968c68e4562（2026-11-10，pass）
- 交付：从默认分支 tip `667e1bcf` 的 worktree 出首个「新 bundle id 已入包」的 Release 候选包 `PurePace-Release-0.1.0-20261109T171534Z.zip`（仓外，zipSha256 `81b9f2de…`，407647 B；exec sha256 `2f812d65…`，1490800 B），记录 `Release-candidate-667e1bc.txt` 按既有字段顺序落盘并含「验收键: zip sha256 + 设备安装后 bundle Info.plist 实际数组」口径行。
- 实测：从解压 `.app/Info.plist` 读回 `CFBundleIdentifier=sh.munk.purepace`、`UIBackgroundModes=["location","audio"]`、0.1.0(1)、MinimumOSVersion 17.0；Release 构建无 debug dylib，签名 `Apple Development: Tao Zhu (H47755VBGF)` / Team `3X4J53U6RY`；`ios/PurePace.xcodeproj` 与 `ios/project.yml`、`.github/workflows/*` 零 diff，未 push / 未打 tag / 未上传 ASC。
- 边界：真机侧验收（安装后从设备 bundle 读回 plist 并跑三档）仍为 `pending: 待人现场`；纯 plist 变更可能使 exec sha 与旧包相近，故候选验收键固定为 zip sha256 + 设备安装后 plist 实际数组。
