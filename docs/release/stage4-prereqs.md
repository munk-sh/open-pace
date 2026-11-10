# 阶段 4 前置清单（iOS 分发 / TestFlight）

快照时间：2026-11-10（工作区基线 `d6f46d9`）。凭据只从环境变量 `$ASC_KEY_PATH` / `$ASC_KEY_ID` / `$ASC_ISSUER_ID`
读取，值一律不打印、不落仓；证据只写端点、HTTP 状态码、ASC 错误 `code`/`title`/`detail` 原文与非敏感资源字段。

## 结论

- 只读自检四条端点全部 `200`：`GET /v1/bundleIds`（`filter[identifier]=sh.munk.purepace` 命中 0 条）、
  `GET /v1/certificates`（4 条）、`GET /v1/profiles`（3 条）、`GET /v1/apps?filter[bundleId]=sh.munk.purepace`（0 条）。
  自检阶段对 ASC 的写请求计数为 0（`writeRequestsBeforeProduce: 0`）。
- 本项唯一授权的写操作（只建 App 记录）在第一条写请求即被 ASC 拒绝：`POST /v1/bundleIds` 返回
  `403 FORBIDDEN_ERROR`，原文 `This request is forbidden for security reasons` /
  `You are not allowed to perform this operation.  Please check with one of your Team Admins, or, if you need further
  assistance, please contact Apple Developer Program Support. https://developer.apple.com/support`。
  按纪律立即停手：不重试、不换端点、不降级绕过；ASC 侧零状态变更（证书与描述文件的条目数、`id` 集合与自检前一致）。
- 该 403 是 API Key 角色/权限错误，不是 `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`；因此 PLA 是否已接受无法由本次响应判定。
- App 记录仍未创建：`GET /v1/apps?filter[bundleId]=sh.munk.purepace` 回读 0 条，故聚合状态为 `pending: 人`
  （需 App Manager / Admin 角色的 ASC API Key，或由人在 App Store Connect 网页创建）。

## 六项前置

| # | 条目 | 状态 | 证据路径 | 责任人 |
|---|---|---|---|---|
| 1 | ASC App 记录（bundle id `sh.munk.purepace` / platform ios / sku `purepace-ios` / 主语言 `zh-Hans` / 暂用名 `PurePace`） | `pending: 人` | `docs/evidence/stage4-prereqs/asc-selfcheck.json`（`readOnlySelfCheck` 与 `appRecordReadback`） | 人（ASC App Manager / Admin 角色）：A. 换用有建记录权限的 API Key 重跑一次授权操作；或 B. 在 ASC 网页手工创建该 App 记录后回填 `id` |
| 2 | Apple Distribution 证书与 App Store profile | `pending: 人` | `docs/evidence/stage4-prereqs/asc-selfcheck.json`（`readOnlySelfCheck` 中 `GET /v1/certificates` 与 `GET /v1/profiles`） | 人（Apple Developer Program 账号持有者）：证书侧已有 `IOS_DISTRIBUTION`（`id` `D5W5M4JLRK`，到期 2027-03-12）可复用；但 `GET /v1/profiles` 3 条里没有 `sh.munk.purepace` 的 `IOS_APP_STORE` 描述文件，需人用 Xcode 自动签名或 ASC 网页创建 |
| 3 | PLA 接受（Program License Agreement） | `pending: 人` | `docs/evidence/stage4-prereqs/asc-selfcheck.json`（`authorisedWriteAttempt.steps[][]` 的 403 原文） | 人（ASC 账号持有人 / Account Holder）：协议只能在 App Store Connect 网页由人接受；本次响应未出现 `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`，接受状态未由本项确认 |
| 4 | 隐私政策 URL `https://munk.sh/privacy`（munk.sh 官网承载、不在本仓自建） | `pending: 人` | `docs/evidence/stage4-prereqs/asc-selfcheck.json`（`appRecordReadback.count = 0`：无 App 记录可承载该字段） | 人（公司负责人 + ASC 执行者）：隐私政策页由 munk.sh 官网承载；App 信息/版本本地化字段需在 App 记录存在后由人在 ASC 填写，本项未写入 |
| 5 | Android upload keystore | `pending: 人` | 仓内无 keystore（`git status --porcelain` 不含 `.jks` / `.keystore` / `.env`）；本机仓外既有 `~/.munk-release/android-signing.env` 与 `~/.munk-release/munk-mobile-host-release.keystore` 属其它产品，未登记给 PurePace | 人（Android 发布负责人）：本项不生成；需决定是否为 `com.chaxiu.purepace` 另建 upload keystore 并登记到 Android 发布域 |
| 6 | 公开名核重（暂用 `PurePace`） | `pending: 人` | `docs/evidence/stage4-prereqs/asc-selfcheck.json`（`readOnlySelfCheck` 中 `GET /v1/apps` 仅 1 条既有记录 `Munk AI`，团队内无 `PurePace` 名称占用） | 人（公司负责人）：App Store 名称唯一性需在 ASC 网页核重后定稿；定稿前一律用暂用名 `PurePace`，改动涉品牌与商店文案 |

状态取值只有三种：`ready`（已就绪，无需人）、`pending: 人`（等人执行或等人确认）、`blocked: PLA`（被 Program License Agreement 挡住，只能人接受后重试）。本次没有 `ready` 项与 `blocked: PLA` 项。

## 一次性授权边界（本项做了什么 / 没做什么）

授权范围是公司负责人显式许可的**唯一一次性例外**：只创建 ASC App 记录。

- 已做：只读自检（4 条 `GET`）、一次被拒的建记录写尝试（`POST /v1/bundleIds`）、只读回读校验（`GET /v1/apps`）。
  建记录本应使用本机一次性分发 CLI（`fastlane produce`，只在本机执行、不入仓、不作依赖、不进 CI）；本机该版本
  不支持 App Store Connect API Key（`invalid option: --api_key_path`），故把同一范围的建记录请求直接提交到 ASC REST 端点。
- 未做：未创建/修改任何证书与 provisioning profile；未上传构建（无 `/v1/builds`、无 `xcrun altool --upload-*`、无 Transporter）；
  未创建 App Store 版本或提交审核；未发送 TestFlight 邀请；未打 tag、未 push、未改远端设置；仓内无 `Fastfile` / `Gemfile` / `Appfile`。
- 凭证纪律：`.p8` 只在仓外绝对路径，一次性 API Key JSON 与 JWT 只存在于仓外临时目录（`mktemp -d`，`chmod 600`，用完删除）；证据不含 JWT、私钥、Issuer/Key ID 实值或请求鉴权头。

## 复核方法（凭据只用占位符）

```bash
# 只在当前 shell 会话内加载，不要 set -x，不要打印值
. ~/.munk-release/secrets.env
test -f "$ASC_KEY_PATH" && test -n "$ASC_KEY_ID" && test -n "$ASC_ISSUER_ID"

# 只读：确认 App 记录是否存在（换成有 App Manager / Admin 权限的 Key 后再跑）
xcrun altool --list-apps --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

# 写操作（仅人在场、仅限「建 App 记录」这一范围）：
#   在 ASC 网页创建，或由人用具备建记录权限的 API Key 重跑一次，然后回读校验
```

回读校验口径：`id` 非空、`attributes.bundleId == sh.munk.purepace`、`sku == purepace-ios`、
`primaryLocale == zh-Hans`、`attributes.name == PurePace`；回读结果写回本清单第 1 行的证据列。
