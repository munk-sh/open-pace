# iOS 分发基线工具链（TestFlight 归档 / 导出脚本 + 静态门 + Runbook）

## 范围

在现有仓库内补齐「可复现、可静态校验」的 iOS 分发基线，只交付脚本、静态门与文档：

1. 新增 `scripts/archive-ios.sh`：`xcodegen generate` → `xcodebuild archive`（`-destination 'generic/platform=iOS'`）→ `xcodebuild -exportArchive`（`ExportOptions` 为 `method=app-store-connect`、`teamID=3X4J53U6RY`、`uploadSymbols=false`、`signingStyle=automatic`）。凭据只从环境变量 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` 读取，传给 xcodebuild 时使用 `-authenticationKeyPath` / `-authenticationKeyID` / `-authenticationKeyIssuerID` 与 `-allowProvisioningUpdates`；缺任一变量立即非零退出且只打印缺失变量名。支持 `DRY_RUN=1`：不要求凭据、不执行 `xcodegen` / `xcodebuild`、不触网，只回显脱敏命令并以 0 退出。产物全部落在仓外（默认 `$TMPDIR/purepace-dist/<version>-<build>`，可用 `OUT_DIR` 覆盖），结束时打印 zip / app / dSYM 路径与 sha256。
2. 版本与 build 号复用现有入口：`MARKETING_VERSION` 来自 `scripts/version.sh`（并可先跑 `scripts/sync-ios-version.sh`），`CURRENT_PROJECT_VERSION` 取 `BUILD_NUMBER`（缺省 1），两者都以 xcodebuild 命令行覆盖，不改 `ios/project.yml` 的签名与版本主干。
3. 新增 `scripts/check-ios-release.sh` 静态门，并接入 `.munk/code-gates.json`（与 `check-ios-scripts.sh` 同层），门数从 23 变为 24，既有全量门保持绿。
4. 新增 `docs/release/testflight-runbook.md`：前置检查、执行步骤、证据归档清单、反范围。

## 验收

- ac-archive-script-contract: `scripts/archive-ios.sh` 存在，`bash -n` 通过，shebang 为 `#!/usr/bin/env bash`，含 `set -euo pipefail`，`--help` 退出 0 且输出含「用法」，未知参数退出 2。
- ac-dry-run-runs-without-credentials: 在 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` 全部未设置且 `DRY_RUN=1` 时执行 `scripts/archive-ios.sh` 退出 0，回显包含 `xcodegen generate`、`xcodebuild archive`、`-exportArchive`、`-destination 'generic/platform=iOS'`，且不实际执行 `xcodegen` / `xcodebuild`、不发起任何网络调用。
- ac-dry-run-output-redacted: 在设置伪凭据（如 `ASC_KEY_PATH=/tmp/FAKE-KEY.p8`、`ASC_KEY_ID=FAKEKEYID`、`ASC_ISSUER_ID=FAKE-ISSUER-UUID`）且 `DRY_RUN=1` 时，输出出现 `-authenticationKeyPath` / `-authenticationKeyID` / `-authenticationKeyIssuerID` 参数名，但不出现 `FAKEKEYID`、`FAKE-ISSUER-UUID`、`FAKE-KEY.p8` 这些值（以 `$ASC_*` 占位符代替）。
- ac-missing-env-fails-closed: 非 `DRY_RUN` 下缺少任一凭据变量时脚本立即非零退出，输出只包含缺失变量名；已设置变量的值（例如 `ASC_KEY_ID=SECRETID`）不得出现在任何输出中。
- ac-no-secret-literals-or-xtrace: `scripts/archive-ios.sh` 与 `docs/release/testflight-runbook.md` 不含 `set -x`、不含真实 `.p8` 绝对路径（`/Users/`、`/home/`）、不含真实 Key ID / Issuer ID / 密钥字面量；脚本内所有凭据引用均为变量。
- ac-export-options-content: 生成的 `ExportOptions.plist` 内容实际包含 `app-store-connect`、teamID `3X4J53U6RY`、`signingStyle` 的 `automatic`、`uploadSymbols` 为 `false`；导出命令同时含 `-exportArchive` 与 `-exportOptionsPlist`。
- ac-version-and-build-wiring: 归档脚本通过 `scripts/version.sh` 取得 `MARKETING_VERSION`，通过 `BUILD_NUMBER`（缺省 1）取得 `CURRENT_PROJECT_VERSION`，并以 xcodebuild 命令行参数覆盖；`ios/project.yml` 未被修改。
- ac-artifacts-outside-repo-and-checksums: 脚本默认输出目录为 `${TMPDIR}/purepace-dist/<version>-<build>` 且支持 `OUT_DIR` 覆盖，归档/导出过程中不向仓库内写产物；结束逻辑包含 `.app`、`.app.dSYM` 的复制、zip 打包、`sha256`（`shasum -a 256`，缺失时回退 `sha256sum`）以及将 zip/app/dSYM 路径与 sha256 打印到 stdout。
- ac-release-gate-wired: `.munk/code-gates.json` 新增 `lint-ios-release` 门且 `command` 为 `bash scripts/check-ios-release.sh`，全部门数为 24；`scripts/check-ios-scripts.sh` 的门数断言同步为 24 且该门仍通过。
- ac-release-gate-self-tests: `scripts/check-ios-release.sh` 自身包含负向自检——缺 env 时归档脚本非零退出且无值泄露、`DRY_RUN=1` 输出脱敏——并在失败时非零退出、全部通过时退出 0。
- ac-runbook-complete: `docs/release/testflight-runbook.md` 含前置（ASC App 记录存在性检查命令、三件凭据的绝对路径与环境变量说明、人在场要求）、执行步骤、证据归档清单（zip/app/dSYM 的 sha256、`xcodebuild -version`、commit）、反范围（不 push tag、不建 Release、不在仓内写 `.p8` / `.env`），命令示例一律使用 `$ASC_KEY_PATH` 等占位符。
- ac-no-network-or-workflow-changes: 本次不执行任何 App Store Connect 上传/记录创建；`.github/workflows/*` 的触发条件与内容不变；不引入 fastlane 依赖。

## 非目标

- 不执行任何 App Store Connect 网络调用、上传、App 记录/构建记录创建。
- 不安装或引入 fastlane 及任何第三方运行时/构建依赖。
- 不修改 `ios/project.yml` 的签名设置、版本主干或 bundle id；不手写 `project.pbxproj`。
- 不在仓库或日志中写入 `.p8`、issuer、Key ID 或任何 secret；不提交 `.env`。
- 不做 tag、GitHub Release、TestFlight 邀请/分发操作，不改 `.github/workflows/*` 触发条件。
- 不重构既有 `build-ios.sh` / `test-ios.sh` / `check-ios-scripts.sh` 的非必要逻辑（仅更新门数断言与本项要求的接入）。

## 实现约束

已约定的锚点与做法（不是正式技术方案，Architect 不介入）：

- 版本：`MARKETING_VERSION="$(bash scripts/version.sh)"`；可先执行 `bash scripts/sync-ios-version.sh`。`CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}"`。只以 CLI 覆盖，不写 `project.yml` / `Version.xcconfig` 的 build 号。
- 工程生成：在 `ios/` 内执行 `xcodegen generate --spec project.yml`（`project.yml` 是唯一真源）。
- 归档命令（参数顺序可按实现调整）：`xcodebuild archive -project ios/PurePace.xcodeproj -scheme PurePace -destination 'generic/platform=iOS' -archivePath "$OUT_DIR/PurePace.xcarchive" -derivedDataPath "$OUT_DIR/DerivedData" MARKETING_VERSION="$marketing_version" CURRENT_PROJECT_VERSION="$build_number" CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"`。注意 `project.yml` 基线里 `CODE_SIGNING_ALLOWED: NO`，归档时必须用 CLI 覆盖为 `YES`，不得改 `project.yml`。
- 导出：`ExportOptions.plist` 由脚本生成到 `$OUT_DIR`（仓外），键含 `method=app-store-connect`、`teamID=3X4J53U6RY`、`signingStyle=automatic`、`uploadSymbols=false`；导出命令 `xcodebuild -exportArchive -archivePath "$OUT_DIR/PurePace.xcarchive" -exportPath "$OUT_DIR/export" -exportOptionsPlist "$OUT_DIR/ExportOptions.plist"`，并同样带三个认证参数与 `-allowProvisioningUpdates`。
- `DRY_RUN=1`：跳过凭据必填校验；仍创建 `OUT_DIR` 并生成非敏感 `ExportOptions.plist`（供静态门断言真实生成内容），随后以占位符（字面量 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID`，不展开变量值）回显上述命令，退出 0；不得执行 `xcodegen` / `xcodebuild` / 网络访问。
- 缺失变量提示：仅遍历变量名输出（如 `archive-ios: 缺少环境变量 ASC_ISSUER_ID`），绝不 `printf` 变量值；脚本禁用 `set -x`。
- 产物与校验：`OUT_DIR` 默认 `${TMPDIR:-/tmp}/purepace-dist/<version>-<build>`；归档后复制 `PurePace.app` 与 `PurePace.app.dSYM` 到 `OUT_DIR`，用 `ditto -c -k --keepParent` 打成 zip（app zip 与 dSYM zip），分别计算 sha256 并与导出产物一起打印、写入 `OUT_DIR/checksums.txt`。
- `scripts/check-ios-release.sh`：沿用 `check-ios-scripts.sh` 的结构（`CHECKS`/`FAILURES`、`pass`/`fail`、`--help`、退出码 0/1/2、以 `BASH_SOURCE` 推导仓库根）；用 `mktemp -d` 作 `OUT_DIR` 跑 `DRY_RUN=1` 与缺 env 负向用例，断言导出配置内容、脱敏、门禁接入与门数 24、runbook 必填段落与占位符。
- 门禁接入：`.munk/code-gates.json` 追加 `{"id":"lint-ios-release","cwd":".","command":"bash scripts/check-ios-release.sh"}`（`command` 不得含 shell 分隔符/重定向，符合 `check-baseline.sh` 校验）；同步把 `scripts/check-ios-scripts.sh` 中「保持 23 门」与 `-ne 23` 断言改为 24（仅此两处门数相关文案/判定）。
- README：在「构建与测试入口」表补 `archive-ios.sh` 与 `check-ios-release.sh` 两行，不改其它文案，且不得出现根 `VERSION` 字面值。
- Runbook 命令示例用占位符：`$ASC_KEY_PATH`（`.p8` 绝对路径）、`$ASC_KEY_ID`、`$ASC_ISSUER_ID`；ASC App 记录存在性检查只给出可离线复述的 `xcrun altool --list-apps` / ASC API 只读说明，不在本项执行。
