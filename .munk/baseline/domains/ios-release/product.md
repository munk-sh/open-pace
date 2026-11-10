# Domain: ios-release

PurePace iOS 分发基线域：交付「仓外产物、可静态校验、可脱敏预演」的归档/导出脚本、静态门、人执行 Runbook、「分发前置清单 + 只读 ASC 取证」，以及「Release 候选包出包 + 候选记录」的一次性人工出包口径。App Store Connect 写操作一律收口：默认零写，唯一许可是公司负责人显式授权的一次性「创建 App 记录」，且一旦被拒立即停手（见 `docs/release/stage4-prereqs.md`）。不把 fastlane 等第三方分发工具变成仓库依赖（本机一次性 CLI 不入仓、不进 CI），不改签名主干、`ios/project.yml` 与 `.github/workflows/*`。

## 范围

- `scripts/archive-ios.sh`：`xcodegen generate --spec project.yml`（cwd=`ios/`）→ `xcodebuild archive -destination 'generic/platform=iOS'` → `xcodebuild -exportArchive -exportOptionsPlist`；`ExportOptions.plist` 由脚本生成到 `OUT_DIR`（仓外），含 `method=app-store-connect`、`teamID=3X4J53U6RY`、`signingStyle=automatic`、`uploadSymbols=false`。
- 凭据只从环境变量 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` 读取，映射为 `-authenticationKeyPath` / `-authenticationKeyID` / `-authenticationKeyIssuerID` 并带 `-allowProvisioningUpdates`；缺任一变量立即非零退出且只打印变量名，已设置变量的值不得出现在输出。
- `DRY_RUN=1`：不要求凭据、不执行 `xcodegen` / `xcodebuild`、不触网，仍创建 `OUT_DIR` 与非敏感 `ExportOptions.plist`，以字面量 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID` 回显命令并退出 0。
- 版本与 build 号复用既有入口：`MARKETING_VERSION` 取 `bash scripts/version.sh`（可先 `scripts/sync-ios-version.sh`），`CURRENT_PROJECT_VERSION` 取 `BUILD_NUMBER`（缺省 `1`），两者均以 xcodebuild 命令行覆盖，不改 `ios/project.yml`。
- 产物全部落在仓外：默认 `${TMPDIR:-/tmp}/purepace-dist/<version>-<build>`，`OUT_DIR` 可覆盖；归档后复制 `PurePace.app` 与 `PurePace.app.dSYM`，用 `ditto -c -k --keepParent` 打 zip，计算 sha256（`shasum -a 256`，缺失回退 `sha256sum`）并打印 zip/app/dSYM 路径与 sha256、写入 `OUT_DIR/checksums.txt`。
- `scripts/check-ios-release.sh` 静态门：结构沿用 `check-ios-scripts.sh`（`CHECKS`/`FAILURES`、`--help`、退出码 0/1/2、以 `BASH_SOURCE` 推导仓库根），用 `mktemp -d` 跑 `DRY_RUN=1` 与缺 env 负向用例，断言归档脚本契约、`ExportOptions` 真实内容、脱敏、门禁接入、Runbook 必填段落。
- `.munk/code-gates.json` 接入单一 argv 门 `lint-ios-release`（`command` 恰为 `bash scripts/check-ios-release.sh`）；`scripts/check-ios-scripts.sh` 的门数断言与帮助文案同步，既有门 id/command 语义不变（本地拓扑当前 22 门，见 `ios-ci-stability`）。
- `docs/release/testflight-runbook.md`：前置（ASC App 记录只读检查、三件凭据的环境变量与仓外 `.p8` 绝对路径、人在场要求）、执行步骤、证据归档清单、反范围。
- `README.md`「构建与测试入口」表新增 `archive-ios.sh` 与 `check-ios-release.sh` 两行，不写根 `VERSION` 字面值。
- `docs/release/stage4-prereqs.md`：阶段 4 前置清单，6 项（ASC App 记录 / Apple Distribution 证书与 App Store profile / PLA 接受 / 隐私政策 URL / Android upload keystore / 公开名核重）逐条给出「状态（只允许 `ready` / `pending: 人` / `blocked: PLA`）+ 证据路径 + 责任人」三列，并附一次性授权边界与只读复核命令（凭据一律占位符）。
- `docs/evidence/stage4-prereqs/`：只读自检证据 `asc-selfcheck.json`（+ 仅建记录成功时才有的 `asc-app-record.json`），只记 endpoint、HTTP 状态码、ASC `errors[].code|title|detail` 原文与非敏感资源字段，并含 `writeRequestsBeforeProduce` 与 `produceInvoked` 计数。ASC 自检顺序固定：先只读 `GET /v1/bundleIds?filter[identifier]=sh.munk.purepace` 与 `GET /v1/certificates`，写请求计数必须为 0 才决定是否建记录，建记录后立即只读回读 `GET /v1/apps?filter[bundleId]=sh.munk.purepace` 校验。
- 一次性 Release 候选出包（真机终验前置，本轮实例 `dac291a`）：从默认分支 tip 的**已提交且干净** worktree 起飞，先核切点（`git rev-parse HEAD` / `git rev-parse main` / `git ls-remote --heads origin main` 三者一致）→ `scripts/sync-ios-version.sh`（幂等）→ `ios/` 内 `xcodegen generate --spec project.yml` → `xcodebuild -project ios/PurePace.xcodeproj -scheme PurePace -configuration Release -destination 'generic/platform=iOS' -derivedDataPath <仓内忽略目录>`（`CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates` 只在命令行）→ `ditto -c -k --keepParent` 打成根级 `PurePace.app/` 布局的 zip。
- 候选产物只落仓外产品目录 `<productDir>/artifacts/candidates/`：`Release-candidate-<短sha>.zip` + `Release-candidate-<短sha>.txt`（记录含 commit、构建配置、签名身份、zip/exec 双 sha 与字节数、`PurePace.app/Info.plist` 实测 dump、构建起止时刻含时区与总耗时、`xcodebuild -version` 原文、完整命令与脚本取舍）；zip / dSYM 不入 git，历史候选零改动零删除。真机安装与真机验收不属于本域出包动作，一律 `pending: 待人现场`。

## 验收

- ac-archive-script-contract: `scripts/archive-ios.sh` 存在，`bash -n` 通过，shebang 为 `#!/usr/bin/env bash`，含 `set -euo pipefail`，`--help` 退出 0 且输出含「用法」，未知参数退出 2。
- ac-dry-run-runs-without-credentials: 三个 `ASC_*` 全未设置且 `DRY_RUN=1` 时退出 0，回显包含 `xcodegen generate`、`xcodebuild archive`、`-exportArchive`、`-destination 'generic/platform=iOS'`，且不实际执行 `xcodegen` / `xcodebuild`、不发起网络调用。
- ac-dry-run-output-redacted: 设置伪凭据（`ASC_KEY_PATH=/tmp/FAKE-KEY.p8`、`ASC_KEY_ID=FAKEKEYID`、`ASC_ISSUER_ID=FAKE-ISSUER-UUID`）且 `DRY_RUN=1` 时，输出出现三个 `-authentication*` 参数名，但不出现 `FAKEKEYID`、`FAKE-ISSUER-UUID`、`FAKE-KEY.p8` 这些值。
- ac-missing-env-fails-closed: 非 `DRY_RUN` 下缺少任一凭据变量时脚本立即非零退出，输出只包含缺失变量名；已设置变量的值（如 `ASC_KEY_ID=SECRETID`）不得出现在任何输出中。
- ac-no-secret-literals-or-xtrace: `scripts/archive-ios.sh` 与 `docs/release/testflight-runbook.md` 不含 `set -x`、不含真实 `.p8` 绝对路径（`/Users/`、`/home/`）、不含真实 Key ID / Issuer ID / 密钥字面量；脚本内凭据引用一律为变量。
- ac-export-options-content: 生成的 `ExportOptions.plist` 实际包含 `app-store-connect`、`3X4J53U6RY`、`automatic`、`uploadSymbols` 为 `false`；导出命令同时含 `-exportArchive` 与 `-exportOptionsPlist`。
- ac-version-and-build-wiring: 归档脚本经 `scripts/version.sh` 取 `MARKETING_VERSION`、经 `BUILD_NUMBER`（缺省 1）取 `CURRENT_PROJECT_VERSION` 并以 xcodebuild 命令行覆盖；`ios/project.yml` 未被修改。
- ac-artifacts-outside-repo-and-checksums: 默认输出目录为 `${TMPDIR}/purepace-dist/<version>-<build>` 且支持 `OUT_DIR` 覆盖，归档/导出不向仓库内写产物；结束逻辑含 `.app` 与 `.app.dSYM` 复制、zip 打包、`shasum -a 256`（缺失回退 `sha256sum`）以及 zip/app/dSYM 路径与 sha256 打印。
- ac-release-gate-wired: `.munk/code-gates.json` 含 `lint-ios-release` 门且 `command` 为 `bash scripts/check-ios-release.sh`；`scripts/check-ios-scripts.sh` 与 `check-ios-release.sh` 的门数断言与当前本地拓扑（22 门）一致且该门通过。
- ac-release-gate-self-tests: `scripts/check-ios-release.sh` 含负向自检（缺 env 时归档脚本非零退出且无值泄露、`DRY_RUN=1` 输出脱敏），失败非零退出、全通过退出 0。
- ac-runbook-complete: Runbook 含前置（ASC App 记录存在性检查命令、三件凭据的绝对路径与环境变量说明、人在场要求）、执行步骤、证据归档清单（zip/app/dSYM 的 sha256、`xcodebuild -version`、commit）、反范围（不 push tag、不建 Release、不在仓内写 `.p8` / `.env`），命令示例一律使用 `$ASC_KEY_PATH` 等占位符。
- ac-runbook-current-bundle-id: `docs/release/testflight-runbook.md` 声明的当前 bundle id 为 `sh.munk.purepace`（指向 `ios/project.yml` 的 `PUREPACE_BUNDLE_ID` 单点），并注明换 id 后需人侧在 App Store Connect 新建/更新对应 App 记录；历史构建记录里的旧 bundle id 保持原样不改写。
- ac-no-network-or-workflow-changes: 不执行任何 App Store Connect 上传/记录创建；`.github/workflows/*` 触发条件与内容不变；不引入 fastlane 依赖。
- ac-checklist-file: `docs/release/stage4-prereqs.md` 存在且非空；6 项必备条目（ASC App 记录 / Apple Distribution 证书与 App Store profile / PLA 接受 / 隐私政策 URL / Android upload keystore / 公开名核重）逐条命中；每条含状态、证据路径、责任人三要素；状态取值只允许 `ready` / `pending: 人` / `blocked: PLA`；文件内 `TBD`、`PLACEHOLDER`、`<占位>` 零命中。
- ac-asc-readonly-first: 自检证据含 `GET /v1/bundleIds` 与 `GET /v1/certificates` 两条的 HTTP 状态码，且在 produce 决策前对 ASC 的写请求计数为 0（`writeRequestsBeforeProduce: 0` 或等价字段）。
- ac-asc-app-record-single-write: ASC 建记录至多一次尝试；存在性由 `GET /v1/apps?filter[bundleId]=sh.munk.purepace`（或 `xcrun altool --list-apps`）只读回读判定——`count=1` 时证据含 `id` / `sku=purepace-ios` / `primaryLocale=zh-Hans`；`count=0` 且被拒时证据含该次请求 HTTP 状态码与 `errors[].code` 原文，且不发第二次写请求。
- ac-app-record-created: 若自检 200 且原无记录，只读回读恰返回 1 条，`bundleId == sh.munk.purepace`、`sku == purepace-ios`、`primaryLocale == zh-Hans`、`name == PurePace`，清单与证据落有该 `id` / `name` / `bundleId`。
- ac-app-record-idempotent: 若自检 200 且记录已存在，则不发生第二次 create（`produceInvoked: false`），回读 `id` 与既有记录一致，清单 ASC App 记录项为 `ready`。
- ac-pla-fail-closed: 若自检 403 且错误码含 `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`，则证据 `produceInvoked: false`、`/v1/apps?filter[bundleId]` 回读为空、清单 PLA 项 `blocked: PLA` 且 App 记录项 `pending: 人`，回执逐字引用错误 `title` / `detail`。
- ac-write-refusal-closed: 建记录请求若被非 PLA 的 403 拒绝（API Key 角色/权限不足），同样立即停手：不重试、不换端点、不降级绕过；证据保留错误原文，清单 App 记录项 `pending: 人` 并给出「换有建记录权限的 Key 重跑一次」或「人在 ASC 网页创建后回填 `id`」两条路径。
- ac-record-only-side-effects: 与自检前快照对比，`GET /v1/certificates` 与 `GET /v1/profiles` 的条目数与 `id` 集合无新增；无 `/v1/builds` 上传、无 `/v1/appStoreVersions` 提交审核、无 TestFlight 邀请；仓库内无 `git tag` 新增、无 `git push`、无远端设置改动。
- ac-privacy-policy-field-honest: 清单隐私政策项写 `https://munk.sh/privacy` 且注明「munk.sh 官网承载、不在本仓自建」；该字段未随创建写入 ASC 时状态必须为 `pending: 人`（不得写成 `ready`），证据路径指向已建 App 记录 `id` 或记录缺失事实。
- ac-evidence-redacted: `docs/evidence/stage4-prereqs/**` 内 `eyJ`（JWT 前缀）、`BEGIN PRIVATE KEY`、Issuer UUID 实值、Key ID 实值、`Authorization` 头与用户主目录绝对路径（`/(Users|home)/` 形态）零命中。
- ac-no-secret-in-repo: `git grep -nE 'AuthKey_[A-Z0-9]{10}|BEGIN PRIVATE KEY'` 与 `git grep -nE '/(Users|home)/[A-Za-z0-9._-]' -- docs scripts README.md` 零命中；工作区无新增 `.p8` / `.env` / `secrets.*`。
- ac-archive-signed-release: `<abs>/PurePace.xcarchive` 存在，`Info.plist` 的 `ApplicationProperties.CFBundleIdentifier=sh.munk.purepace`、`ApplicationProperties.SigningIdentity` 已记录，且 `ios/project.yml` 与 `ios/PurePace.xcodeproj` 的 `git status --porcelain` 为空。
- ac-ipa-artifact-hash: 成功路径产出 `<abs>/export/*.ipa`，证据含绝对路径与 `shasum -a 256` 实测 sha256（同命令可复现同值）。
- ac-ipa-appstore-signing: 解开 `.ipa` 后 `Payload/PurePace.app` 的 `codesign -dv` Authority 含 `Apple Distribution`、`TeamIdentifier=3X4J53U6RY`；`embedded.mobileprovision` 解码后 `TeamIdentifier` 含 `3X4J53U6RY`、`ProvisionsAllDevices` 不为 true、`ExpirationDate` 已记录。
- ac-no-upload-asc: 全程无上传动作——日志/回执不含 `--upload-app`、`pilot`、`upload_to_testflight`、`deliver` 的实际调用，未调 ASC `POST /v1/builds`，未建 TestFlight 构建记录。
- ac-asc-logs-persisted: 证据含 archive 与 export 的完整原始日志文件绝对路径（`-authenticationKey*` 值确认为变量传递、未出现在日志）与关键行摘录（签名 / 描述文件 / `Exported` 行）。
- ac-asc-secret-hygiene: 仓内 `git status --porcelain` 不含 `.p8` / `secrets.env` / `*.mobileprovision` / `.ipa` / `.xcarchive`；仓内证据不含 Issuer ID、Key ID、私钥内容或用户主目录绝对路径实值（用 `<abs>` 或占位符）。
- ac-cutpoint-valid: 出包开工与收尾各核一次切点——`git rev-parse HEAD`、`git rev-parse main`、`git ls-remote --heads origin main` 均等于解包时记录的同一全 sha；执行期间若该分支前进且新提交触及 `ios/PurePace/**` 或 `ios/project.yml`，立即停手、不产出候选包，并在候选记录/回执写明「切点已失效」与新旧 sha。
- ac-single-candidate: 候选目录下每个 commit 只新增 1 个 `Release-candidate-<短sha>.zip` 与 1 个 `Release-candidate-<短sha>.txt`；既有候选文件零改动、零删除，不产出第二份候选。
- ac-zip-root-app: `unzip -Z1` 顶层唯一条目为 `PurePace.app/`（无 `Payload/`、无 `__MACOSX/`、无 `._` / `.DS_Store` 或其它顶层条目），解包后 `PurePace.app/Info.plist` 与 `PurePace.app/PurePace` 均存在。
- ac-zip-sha-recorded: 记录中 `zipPath` 为绝对路径；`zipSha256` 为 64 位十六进制且等于 `shasum -a 256` 对 zip 实算值；`zipBytes` 等于 `stat -f%z` 实算值；记录不含 `TBD` / `<sha256>` / `PLACEHOLDER` 占位。
- ac-exec-sha-recorded: 记录中 `PurePace.app/PurePace` 的 `execSha256` 与 `execBytes` 等于对该文件实算的 sha256 与字节数。
- ac-exec-sha-reproducible: 对同一 zip 二次独立解包重算 exec sha 必须与首次读数一致；再用独立 `-derivedDataPath` 重跑同一 `xcodebuild` 命令并实算新 `.app` 主二进制 sha：一致时记「可复现」；不一致时同时保留两次读数并写明差异来源（仅作对照，不打包、不落候选）。exec sha 只作辅助记录，不得单以 exec sha 区分新旧包。
- ac-plist-fields: 用 `plutil` 读回解压后 `PurePace.app/Info.plist` 本体（非 UITests runner、非 `project.yml` 推断）：`UIBackgroundModes` 实际数组同时含 `location` 与 `audio`；`CFBundleIdentifier=sh.munk.purepace`；`CFBundleShortVersionString` 等于根 `VERSION`；`CFBundleVersion` 等于 `project.yml` 基线 build 号；`MinimumOSVersion=17.0`；记录内保存该实测 dump。
- ac-signing-identity: `codesign -dvvv` 读回签名身份为 `Apple Development: Tao Zhu (H47755VBGF)` 且 `TeamIdentifier=3X4J53U6RY`；`git diff --exit-code -- ios/project.yml` 退出 0（签名配置只在命令行，不写入 `project.yml`）；`.app` 内 `PurePace.debug.dylib` 计数为 0。
- ac-record-complete: `Release-candidate-<短sha>.txt` 含 commit 全 sha、构建配置、签名身份、zip 绝对路径、zip/exec 双 sha 与字节数、上述 plist 字段 dump、构建起止时刻（含时区与总耗时）、`xcodebuild -version` 原文、所用完整命令；缺任一字段即不通过。
- ac-no-source-change: `git diff --stat -- ios android shared scripts docs .github` 为空；相对切点仅变更包目录 `.munk/changes/<wi>/**` 可有改动；`git status --porcelain` 中不出现 `.zip`（候选 zip 不进仓库）。
- ac-no-release-side-effects: 未创建/推送 tag、未 push、未触发 GitHub Release 或任何发布 workflow、未安装到真机、未上传 ASC/TestFlight；记录与 PRD 不出现「已验证 / 已发布」措辞，真机项一律保持 `pending: 待人现场`。
- ac-script-decision-recorded: 记录写明是否使用仓库既有脚本及其完整命令；若未使用 `scripts/archive-ios.sh`，须写明原因（该脚本要求 `ASC_*` 三件凭据并走 `-exportArchive` 的 app-store-connect 口径，与「Release 构建 + 开发签名 + 根级 `.app` zip 候选」口径不一致）。
- ac-candidate-smoke-honest: 若记录声明做过模拟器干净安装冒烟，须留三类证据（截图 + 首屏元素树 dump + 进程存活输出）；未做的项写 `pending` / `not-run`，不得写成 PASS，也不得用真机代替。
- ac-new-script-contract: 若新增 `scripts/*.sh`，则 `bash -n` 退出 0、shebang 为 `#!/usr/bin/env bash`、含 `set -euo pipefail`、`--help` 退出 0 且输出含「用法」、未知参数退出 2；且不含 `… | grep -q` 形态（用 `grep -q <<<"$var"` 或显式捕获 `$?`），文件内无凭据字面量。
- ac-runbook-consistent: `bash scripts/check-ios-release.sh` 退出 0（Runbook 段落/占位符断言仍满足）；Runbook 与清单中 `fastlane` 只作为「本机一次性 CLI」表述，仓库内无 `fastlane/Fastfile`、`Gemfile`、`fastlane/Appfile`；反范围明确「不上传构建、不提交审核、不邀请测试者」。
- ac-gates-green: `.munk/code-gates.json` 全部本地门真实执行退出 0，不得 skip、不得 `continue-on-error`、不得临时改门；出包轮只跑出包必需命令（`sync-ios-version` / `xcodegen generate` / `xcodebuild` / `ditto` / `shasum` / `stat` / `plutil` / `codesign`），并在记录 `note` 注明未重跑全量门。

## 非目标

- 默认不执行任何 App Store Connect 写操作；唯一例外是公司负责人显式授权的一次性「建 App 记录」，该授权已被 ASC 403 拒绝并即刻停手（2026-11 事实见 `docs/release/stage4-prereqs.md`），重跑需人换权限后重新授权。不上传构建、不提交审核、不发送 TestFlight 邀请。
- 不把 fastlane 变成仓库依赖：不新增 `Fastfile` / `Gemfile` / `Appfile`，不进 CI、不新增 gate；一次性的本机 CLI 调用不算依赖。
- 不创建或修改 Apple Distribution 证书、App Store provisioning profile（只做只读盘点）。
- 不接受 PLA、不代签协议、不提升 ASC 用户权限、不绕过钥匙串/权限弹窗。
- 不在仓内自建隐私政策页面；不为 Android 生成 upload keystore；不核重公开名（只登记待办与暂用名 `PurePace`）。
- 不修改 `ios/project.yml` 的签名设置、版本主干或 bundle id；不手写 `project.pbxproj`。
- 不在仓库或日志中写入 `.p8`、issuer、Key ID 或任何 secret；不提交 `.env`。
- 不做 tag、GitHub Release、分发操作，不改 `.github/workflows/*` 触发条件；不自动 push、不自动建 PR。
- 出包轮不做任何源码 / 脚本 / `project.yml` / `.munk/code-gates.json` 改动，不顺手优化、不扩大改动半径；不重跑全量 code_gates、不改断言、不降门。
- 不产出第二份候选、不重命名/覆盖/删除历史候选包；不把 zip、dSYM 或任何二进制复制进 git。
- 不安装到真机、不做真机验收、不修改 `docs/device-manual-acceptance.md`；真机项永远 `pending: 待人现场`。
- 不重构既有 `build-ios.sh` / `test-ios.sh` / `check-ios-scripts.sh` 的非必要逻辑（仅门数断言与本项接入）；不替代 `ios-ci-stability` 的测试链路。

## 实现约束

- 签名覆盖：`ios/project.yml` 基线为 `CODE_SIGNING_ALLOWED: NO`，出包时必须用 CLI 覆盖 `CODE_SIGNING_ALLOWED=YES` / `CODE_SIGNING_REQUIRED=YES` / `CODE_SIGN_STYLE=Automatic` / `DEVELOPMENT_TEAM=3X4J53U6RY`，不得改 `project.yml`。
- 工程生成：在 `ios/` 内执行 `xcodegen generate --spec project.yml`（`project.yml` 是唯一真源）；导出阶段不再 generate。
- 脱敏口径：`DRY_RUN=1` 回显字面量 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID`（不展开变量值）；失败提示只遍历变量名，绝不 `printf` 变量值；禁用 `set -x`。
- 目录创建顺序：`DRY_RUN` 也要先建 `OUT_DIR` 并写 `ExportOptions.plist`，静态门据此断言真实生成内容而非只读源码。
- 门禁口径：门 `command` 必须单一 argv（无 `&&`、`|`、`;`、重定向），多步断言封装进 `scripts/check-ios-release.sh`。
- 脚本契约：`#!/usr/bin/env bash` + `set -euo pipefail` + `--help` 退出 0 含「用法」+ 未知参数退出 2；路径以 `BASH_SOURCE` 推导的仓库根为基准；参数展开一律 `${var}`（macOS bash 3.2 与 `check-shell-expansion.sh` 卫生口径）。
- 候选打包：优先 `ditto -c -k --keepParent`（可加 `--norsrc --noextattr --noqtn` 消旁支），保证根级 `PurePace.app/`；派生数据落仓内忽略目录（如 `.build/<candidate>`），不写进 git。
- 复现性口径：`LC_UUID` 每次链接随机、二进制内嵌派生数据路径字符串，故不同 `-derivedDataPath` 必然产出不同 exec sha；记录须保留两次读数与差异来源，不得据此声称「可复现」。
- 时间盒：出包轮 wall clock ≤60 分钟；触顶即停手出部分回执（已完成项 + 未完成原因），不继续消耗。
- 失败即停：xcodegen / xcodebuild / 打包 / 校验任一步失败即停手，在候选记录或回执写失败步骤、退出码与错误原文片段，不降级、不换签名、不重试绕过。
- 凭据纪律（阶段 4 前置）：`source ~/.munk-release/secrets.env` 只在本人 shell 会话内，禁 `set -x`、禁 `echo`/`printf` 变量值；一次性 API Key JSON 与 JWT 只落仓外 `mktemp -d` 临时目录（`chmod 600`）并在退出前删除；仓内一律用占位符。
- 门禁与文档互锁：`scripts/check-ios-release.sh` 硬断言门数与脱敏口径（禁 `set -x`、禁用户主目录绝对路径、禁真实凭据）；改写 Runbook / 清单时不得触发这些断言，也不得为绕断言改门数或改门拓扑。

## 最近交付证明

- workItemId: wi_intake_13c114074a297bc6 / at: 2026-11-11T04:58:00+08:00 / status: pass
- 交付：在切点 `dac291a22044ed7c69d659361112cee69ec98c6b`（`HEAD` = `main` = `origin/main`，开工与收尾各核一次）上出 Release 候选：`scripts/sync-ios-version.sh` 幂等 → `ios/` 内 `xcodegen generate` → `xcodebuild -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/release-candidate-dac291a`（签名仅命令行，`project.yml` 零改动）→ `ditto` 打包。产物只两份，落仓外候选目录：`Release-candidate-dac291a.zip`（535634B，sha256 `15b9043c…3415`，顶层唯一条目 `PurePace.app/`）与 `Release-candidate-dac291a.txt`。
- 实测：exec `7b0a5b72…3165` / 2127088B；二次独立解包一致；独立派生数据路径重跑得 `2f598419…004e7` / 2127424B → 判定「不可复现」，差异源于内嵌派生数据路径字符串（57 处）与随机 `LC_UUID`，两次读数均已保留。plist 本体读回 `CFBundleIdentifier=sh.munk.purepace`、`0.1.0` / build `1`、`MinimumOSVersion=17.0`、`UIBackgroundModes=["location","audio"]`；`codesign` Authority `Apple Development: Tao Zhu (H47755VBGF)` / Team `3X4J53U6RY`，`--verify --deep --strict` 通过，`PurePace.debug.dylib` 计数 0。
- 边界：未用 `scripts/archive-ios.sh`（其 ASC `-exportArchive` 口径与本项不一致，原因已入记录）；未打 tag / 未 push / 未触发 Release / 未上传 ASC / 未装真机；相对切点仅 `.munk/changes/wi_intake_13c114074a297bc6/**` 有改动，`git status --porcelain` 无 `.zip`；真机三项保持 `pending: 待人现场`。code_gates 22 门通过（attempt 001）。
