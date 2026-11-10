# V1 阶段 4 前置：ASC App 记录（PLA 自检优先）+ 分发前置清单落盘

## 范围

前置事实（Intake 已核，均只判存在/可用性，未读取任何凭据内容）：

- 凭据就位：`$ASC_KEY_PATH` 指向的 `.p8` 存在（仓外绝对路径）；`~/.munk-release/secrets.env` 存在且含 `ASC_ISSUER_ID`（只 `grep -c` 计数）。
- 工具链：`/opt/homebrew/bin/fastlane` 已安装；`xcrun altool` 26.10.1 可用；`openssl` 3.6.4、`python3` + `cryptography` 46 可用（三者任一即可手工签 JWT 做只读 GET）。
- 基线冲突已裁决：`ios-release` 域历史非目标写有「不执行任何 App Store Connect 写操作 / 不引入 fastlane」。本项是公司负责人显式授权的**唯一一次性例外**：只允许创建 App 记录；上传、审核、证书/描述文件创建仍禁止（见「非目标」）。

**A. ASC 只读自检（先做，PLA 门控优先）**

1. 从环境变量取凭据：`ASC_KEY_PATH`（key 文件绝对路径，仓外）、`ASC_KEY_ID`、`ASC_ISSUER_ID`（来自 `~/.munk-release/secrets.env`，只在本机 shell 内 source，不进仓库、不进日志、不进回执）。值一律不打印、不回显；命令回显只用 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID` 占位符。
2. 只读 GET（`https://api.appstoreconnect.apple.com`，JWT ES256，`aud=appstoreconnect-v1`）：
   - `GET /v1/bundleIds?filter[identifier]=sh.munk.purepace`
   - `GET /v1/certificates?limit=5`
3. 把结论落证据：`docs/evidence/stage4-prereqs/asc-selfcheck.json`（+ 可选同名 `.md` 摘要），只含 endpoint、HTTP 状态码、ASC `errors[].code` / `title` / `detail` 原文、返回资源 `id` / `attributes.identifier|name|expirationDate` 这类非敏感字段。禁止写入 Authorization 头、JWT（`eyJ…`）、私钥内容、Issuer UUID、Key ID 实值。

**B. 按自检结果分叉（互斥）**

- 403 且 `errors[].code` 为 `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`：**立即停止**，不执行 `fastlane produce`、不执行 `sigh`，不重试、不换端点试错。清单里 PLA 项 = `blocked: PLA`，ASC App 记录 / 证书与 profile 项 = `pending: 人`；回执引用该错误原文。
- 200（bundleIds 可读）：先判重——若 `filter[identifier]=sh.munk.purepace` 已返回记录，只记录其 `id`/`name`，**不重复创建**；为空则用 `fastlane produce` 建记录，参数固定：
  - bundle id `sh.munk.purepace`、`--platform ios`、`--sku purepace-ios`、`--language zh-Hans`、App 名 `PurePace`（公开名核重前的暂用名）
  - 一次性 API Key JSON 落在仓外临时目录（`mktemp -d`，`chmod 600`），用完 `rm -rf`；仓库内不落 `fastlane/Fastfile`、`Gemfile`、`fastlane/Appfile` 等任何文件
  - 建完立即用**只读** `GET /v1/apps?filter[bundleId]=sh.munk.purepace` 回读校验 `id` / `attributes.name` / `bundleId` / `sku` / `primaryLocale`，并把结果写进清单与证据
  - 若报权限/会话卡（钥匙串授权、协议待签、App Store Connect 用户权限），**不绕过**：如实记 `pending: 人` 并保留错误原文
- 隐私政策 URL `https://munk.sh/privacy` 与支持邮箱 `support@munk.sh` 属 App 信息/版本本地化字段，`produce` 通常不写这些字段：能写就写，写不了就在清单里标 `pending: 人`（证据指向已建记录的 `id`），不得为了填这两个字段去动其它写端点。

**C. 阶段 4 前置清单落盘**

新增 `docs/release/stage4-prereqs.md`，逐项三列：状态（`ready` / `pending: 人` / `blocked: PLA`）、证据路径、责任人。至少含 6 项：

1. ASC App 记录（本项产出，证据 = `docs/evidence/stage4-prereqs/asc-selfcheck.json` 与回读 JSON）
2. Apple Distribution 证书 + App Store profile（本项不创建；现状取证只读 `GET /v1/certificates` / `GET /v1/profiles`）
3. PLA 接受（Program License Agreement，仅人可接受）
4. 隐私政策 URL `https://munk.sh/privacy`（munk.sh 官网承载，不在本仓自建）
5. Android upload keystore（本项不生成，标 `pending: 人`）
6. 公开名核重（暂用 PurePace，App Store 名称唯一性由人核）

并同步 `docs/release/testflight-runbook.md` 的「前置 / 反范围」措辞：把「本仓库不创建记录」改为「App 记录由一次性授权操作创建（见 `docs/release/stage4-prereqs.md`）；上传/邀请/审核仍是人的写操作」，仍保留 `check-ios-release.sh` 断言所需的占位符与段落。

## 验收

- ac-checklist-file: `docs/release/stage4-prereqs.md` 存在且非空；6 项必备条目（ASC App 记录 / Apple Distribution 证书与 App Store profile / PLA 接受 / 隐私政策 URL / Android upload keystore / 公开名核重）逐条命中；每条含状态与证据路径与责任人三要素；状态取值只允许 `ready` / `pending: 人` / `blocked: PLA`；文件内 `TBD`、`PLACEHOLDER`、`<占位>` 零命中。
- ac-asc-readonly-first: 证据 JSON 含 `GET /v1/bundleIds` 与 `GET /v1/certificates` 两条记录的 HTTP 状态码；在 produce 决策前对 ASC 的写请求计数为 0（证据含 `writeRequestsBeforeProduce: 0` 或等价字段）。
- ac-pla-fail-closed: 若自检返回 403 且错误码含 `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`，则证据中 `produceInvoked: false`、ASC 侧 `/v1/apps?filter[bundleId]=sh.munk.purepace` 回读为空，清单 PLA 项为 `blocked: PLA`、ASC App 记录项为 `pending: 人`，回执逐字引用该错误 `title`/`detail`。
- ac-app-record-created: 若自检 200 且原无记录，则只读回读 `GET /v1/apps?filter[bundleId]=sh.munk.purepace` 恰好返回 1 条；`id` 非空；`attributes.bundleId == sh.munk.purepace`、`sku == purepace-ios`、`primaryLocale == zh-Hans`、`attributes.name == PurePace`；清单与证据落有该 `id`/`name`/`bundleId`。
- ac-app-record-idempotent: 若自检 200 且记录已存在，则不发生第二次 create（证据 `produceInvoked: false`），回读 `id` 与既有记录一致，清单 ASC App 记录项为 `ready`。
- ac-record-only-side-effects: 与自检前快照对比，`GET /v1/certificates` 与 `GET /v1/profiles` 的条目数与 `id` 集合无新增；无 `/v1/builds` 上传、无 `/v1/appStoreVersions` 提交审核、无 TestFlight 邀请；仓库内无 `git tag` 新增、无 `git push`、无远端设置改动。
- ac-privacy-policy-field-honest: 清单隐私政策项写 `https://munk.sh/privacy` 且注明「munk.sh 官网承载、不在本仓自建」；若该字段未随创建写入 ASC，状态为 `pending: 人`（不得写成 `ready`），证据路径指向已建 App 记录 `id`。
- ac-evidence-redacted: `docs/evidence/stage4-prereqs/**` 内 `eyJ`（JWT 前缀）、`BEGIN PRIVATE KEY`、Issuer UUID 实值、Key ID 实值、`Authorization` 头、用户主目录绝对路径（`/(Users|home)/` 形态）零命中。
- ac-no-secret-in-repo: `git grep -nE 'AuthKey_[A-Z0-9]{10}|BEGIN PRIVATE KEY' -- . ':!*.png'` 零命中（含本条 prd 自身）；`git grep -nE '/(Users|home)/[A-Za-z0-9._-]' -- docs scripts README.md` 零命中；工作区无新增 `.p8` / `.env` / `secrets.*`（`git status --porcelain` 不含此类路径）。
- ac-protected-paths-zero-diff: 相对基线 `d6f46d9`，`git diff --stat` 在 `ios/`、`shared/`、`android/`、`.github/workflows/`、`.munk/code-gates.json` 上为空（业务源码、CI 语义、门禁拓扑零改动）。
- ac-gates-green: `.munk/code-gates.json` 现有 22 门全部本地真实执行退出 0（含 `lint` / `lint-baseline` / `lint-ios-*` / `lint-android*` / `build-*` / `test-*` / `test` / `check-*`），不得 skip、不得 `continue-on-error`、不得临时改门。
- ac-new-script-contract: 若新增 `scripts/*.sh`，则 `bash -n` 退出 0、shebang 为 `#!/usr/bin/env bash`、含 `set -euo pipefail`、`--help` 退出 0 且输出含「用法」、未知参数退出 2；且不含 `… | grep -q` 形态（pipe-free：用 `grep -q <<<"$var"` 或显式捕获 `$?`），文件内无凭据字面量。
- ac-runbook-consistent: `bash scripts/check-ios-release.sh` 退出 0（runbook 段落/占位符断言仍满足）；runbook 与清单中 `fastlane` 只作为「本机一次性 CLI」表述，仓库内无 `fastlane/Fastfile`、`Gemfile`、`fastlane/Appfile`；runbook 反范围明确「不上传构建、不提交审核、不邀请测试者」。
- ac-no-upload-or-archive: 本次不执行 `scripts/archive-ios.sh`、不跑 `xcodebuild archive`、不跑 `xcrun altool --upload-*` / Transporter；仓库与证据内 `--upload-package`、`--upload-app` 零命中。

## 非目标

- 不发布、不上传构建、不提交 App 审核、不发送 TestFlight 邀请、不 push tag、不建 GitHub Release、不动远端仓库设置。
- 不创建 Apple Distribution 证书、不创建/修改 App Store provisioning profile（只做只读盘点）。
- 不接受 PLA、不代签任何协议、不提升 ASC 用户权限、不绕过钥匙串/权限弹窗。
- 不改 `ios/`、`shared/`、`android/` 任何业务源码；不改 `ios/project.yml` 与 `project.pbxproj`。
- 不改 `.github/workflows/*` 语义（如确需 CI 改动，另立小项）。
- 不把 fastlane 变成仓库依赖：不新增 `Fastfile` / `Gemfile` / `Appfile`，不改 CI，不新增 gate。
- 不在仓内自建隐私政策页面；不为 Android 生成 upload keystore；不核重公开名（只登记待办与暂用名）。
- 不重写 `.munk/baseline/**`：本项只是平台侧一次授权例外，域基线由 Delivery fold 时按事实更新。

## 实现约束

- 凭据纪律：只从环境变量读；`source ~/.munk-release/secrets.env` 只在本机 shell 会话内，禁止 `set -x`，禁止 `echo`/`printf` 变量值，禁止把命令连同真实参数写进任何仓内文件或证据。仓内一律 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID`。
- 门禁拓扑冻结：`scripts/check-ios-release.sh` 硬断言 `.munk/code-gates.json` 门数为 22（第 359 行），因此**不要新增/删除 gate**；若确需接线，必须同时改 `check-ios-release.sh` 的门数断言与 `check-ios-scripts.sh` 的「保持 22 门」/`-ne 22` 断言——本项不建议这么做，静态保证靠清单文档 + 现有门。
- 脚本默认零新增：只读自检用一次性命令（`curl` + openssl/python3 签 JWT，或 `xcrun altool --list-apps`）即可，不必新建脚本；如确要落 `scripts/asc-selfcheck.sh`，必须满足 ac-new-script-contract，且不得把新增脚本接进门禁。
- 门禁口径：任何 shell 判定禁止 `上游 | grep -q`（pipefail 下会误判），改用 `grep -q <<<"$var"` 或显式捕获退出码。
- 一次性 API Key JSON 与 JWT 只在仓外临时目录（`mktemp -d`，`chmod 600`），脚本退出前 `rm -rf`；证据只留非敏感字段。
- 若 `fastlane produce` 需要 App Store Connect 用户角色/团队参数，用既有 `DEVELOPMENT_TEAM=3X4J53U6RY` 上下文，不新增账号、不改团队设置。
- 证据目录约定：`docs/evidence/stage4-prereqs/asc-selfcheck.json`（必选）、`.../asc-app-record.json`（仅 200 分叉产生）、`.../summary.md`（可选，一屏结论）。路径写成相对仓库根。
- 已有事实：`docs/release/testflight-runbook.md` 现存「本仓库不创建记录」表述与本项授权冲突，需按 C 节改写但不得触发 `check-ios-release.sh` 断言（禁 `set -x`、禁用户主目录绝对路径、禁 `fastlane` 字样、保留 `$ASC_KEY_PATH`/`$ASC_KEY_ID`/`$ASC_ISSUER_ID`/`xcrun altool --list-apps`/`xcodebuild -version`/`sha256`/`commit`/`.env` 与四个段落）。
- 预算：≤10M token、≤90 分钟自开工起；超时或 PLA 阻塞即停手交回执（写已达成项、未闭合项定性、证据路径），不做长期重试。
