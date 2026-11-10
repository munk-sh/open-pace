# ASC app-store-connect 出包通路验证（archive → .ipa，不上传）

## 范围

只验通路、不上传：从 `main` tip（Intake 实测 `efeb57d2983ab9e936fe4b8d8cab5eb669ed6928`）的干净 worktree 走完
「ASC App 记录 → Release archive → `-exportArchive`（`method=app-store-connect`）→ `.ipa`」这一条链，
验证在团队凭据当前只有 Developer ID / Apple Development（`security find-identity -v -p codesigning` 实测 3 条，
Apple Distribution 为 0）的前提下，`xcodebuild ... -allowProvisioningUpdates` + ASC 团队级 API Key 能否自动产出
Apple Distribution 证书与 App Store 描述文件。

1. **ASC App 记录（唯一写操作）**：`fastlane produce` 建记录（bundle id `sh.munk.purepace`、platform `ios`、
   sku `purepace-ios`、primary language `zh-Hans`、privacy `https://munk.sh/privacy`、support email `support@munk.sh`）；
   已存在则幂等跳过并记录实测响应。若本机 fastlane 版本不支持 ASC API Key（历史实测 `invalid option: --api_key_path`），
   允许退化为同一范围的单次 `POST /v1/bundleIds`（同一 payload），仍只发一次、不重试。
2. **干净出包**：`xcodegen generate --spec ios/project.yml`（cwd=`ios/`）→
   `xcodebuild archive -project ios/PurePace.xcodeproj -scheme PurePace -configuration Release \
   -destination 'generic/platform=iOS' -archivePath <abs>/PurePace.xcarchive -allowProvisioningUpdates \
   DEVELOPMENT_TEAM=3X4J53U6RY CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic`（签名/team 只走命令行）。
3. **导出**：`xcodebuild -exportArchive -archivePath <abs> -exportPath <abs> -exportOptionsPlist <abs> -allowProvisioningUpdates`，
   `exportOptions` 的 `method` 为 `app-store-connect`；ASC 鉴权只用 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID`
   三个环境变量（`ASC_ISSUER_ID` 从 `~/.munk-release/secrets.env` 以等价 `set -a; . ...; set +a` 方式载入，绝不 echo/打印/落盘/入仓）。
4. **证据**：`.ipa` 绝对路径 + sha256；archive/export 原始日志落盘路径 + 关键行摘录；证书与描述文件清单
   （`security find-identity -v -p codesigning` 输出、export/archive 生成的 profile 文件路径与名称）。
5. **失败即停即报**：卡在证书角色权限或 PLA 时当场 `munk_report_owner`（含 HTTP 状态码与 `errors[].code` 原文），
   不重试、不换端点、不降级；时间盒 ≤60 分钟，到点停手出部分回执。

## 验收

- ac-asc-app-record-single-write: 至多一次 ASC 建记录尝试；记录存在性由 `GET /v1/apps?filter[bundleId]=sh.munk.purepace`（或 `xcrun altool --list-apps`）回读判定，回读 `count=1` 时证据含 `id` / `sku=purepace-ios` / `primaryLocale=zh-Hans`；`count=0` 且被拒时证据含该次请求的 HTTP 状态码与 `errors[].code` 原文，且不再发第二次写请求。
- ac-archive-signed-release: `<abs>/PurePace.xcarchive` 存在，其 `Info.plist` 的 `ApplicationProperties.CFBundleIdentifier=sh.munk.purepace`、`ApplicationProperties.SigningIdentity` 已记录，且 `ios/project.yml` 与 `ios/PurePace.xcodeproj` 的 `git status --porcelain` 为空。
- ac-ipa-artifact-hash: 成功路径产出 `<abs>/export/*.ipa`，证据含其绝对路径与 `shasum -a 256` 实测 sha256（同一条命令可复现同值）。
- ac-ipa-appstore-signing: 解开该 `.ipa` 后 `Payload/PurePace.app` 的 `codesign -dv` Authority 含 `Apple Distribution`、`TeamIdentifier=3X4J53U6RY`；`embedded.mobileprovision` 解码后 `TeamIdentifier` 含 `3X4J53U6RY`、`ProvisionsAllDevices` 不为 true（App Store 类型）、`ExpirationDate` 已记录。
- ac-distribution-identity-appears: 出包后 `security find-identity -v -p codesigning` 输出中出现 `Apple Distribution: ... (3X4J53U6RY)` 条目（或其缺失被记录为失败证据，并已 `munk_report_owner`）。
- ac-no-upload: 全程无上传动作——日志/回执中不含 `--upload-app`、`pilot`、`upload_to_testflight`、`deliver` 的实际调用，且未调用 ASC `POST /v1/builds`；未建 TestFlight 构建记录。
- ac-blocked-reported-immediately: 任一命令返回含 `PLA_NOT_ACCEPTED` 或 403/角色权限不足时，当轮即调用 `munk_report_owner`，其 message 含失败命令、HTTP 状态码、`errors[].code` 原文；不等到窗口结束或 23:00。
- ac-logs-persisted: 证据含 archive 与 export 的完整原始日志文件绝对路径（非敏感，`-authenticationKey*` 值已确认为变量传递而未出现在日志）与关键行摘录（xcodebuild 签名/描述文件/`Exported` 行）。
- ac-no-secret-leak: 仓内 `git status --porcelain` 不含 `.p8` / `secrets.env` / `*.mobileprovision` / `.ipa` / `.xcarchive`；仓内证据文件不含 Issuer ID、Key ID、私钥内容或用户主目录绝对路径实值（路径以 `<abs>` 或占位符表述）。
- ac-minimal-gates-only: 只跑与本项相关的最小门（`bash scripts/check-ios-release.sh`、必要时 `bash scripts/build-ios.sh`），证据记录实际执行的门的 id 与结果；未执行全量 `code_gates`。
- ac-timebox-partial-receipt: 触达 60 分钟上限时产出部分回执，列出已完成项、卡点原文、未完成项，且不再追加探测。

## 非目标

- 不上传：禁 `xcrun altool --upload-app`、`fastlane pilot` / `upload_to_testflight` / `deliver`、Transporter；不建 TestFlight 构建记录、不提交审核、不发测试邀请。
- 不打 tag、不 push tag、不改远端设置、不改 `main` 业务源码。
- 不把签名 / `DEVELOPMENT_TEAM` 写进 `ios/project.yml`，不手改 `project.pbxproj`。
- 不提交任何 secret；不把 `.p8` / `secrets.env` / 产物（`.ipa` / `.xcarchive` / profile）放进仓库。
- 不新增/删除证书与描述文件（除 `-allowProvisioningUpdates` 自动创建这一条），不手工 revoke；不在被拒后换端点试错。
- 不重跑全量 `code_gates`；不动 Android 侧；不做商店文案 / 截图 / 隐私页开发。

## 实现约束

- 复用既有入口：优先 `scripts/archive-ios.sh`（已具备 `xcodegen generate` → archive → `-exportArchive`、`method=app-store-connect`、`teamID=3X4J53U6RY`、`signingStyle=automatic`、三件 `ASC_*` 环境变量映射与 `-allowProvisioningUpdates`、产物落仓外 `OUT_DIR`）；若需逐条对齐本条 spec 的命令行，允许直接执行等价 `xcodebuild`，但不得改写脚本既有契约与其静态门断言。
- 版本：`MARKETING_VERSION` 取 `bash scripts/version.sh`（`scripts/sync-ios-version.sh` 只写 `ios/Config/Version.xcconfig`，不动 `project.yml`），build 号用 `BUILD_NUMBER`（缺省 `1`），均以命令行覆盖。
- 凭据：`ASC_KEY_PATH=/Users/zhutao/.dawnchat-release/keys/AuthKey_6YFFYJFK7U.p8`（绝对路径，仅环境变量传递）；`ASC_KEY_ID=6YFFYJFK7U`；`ASC_ISSUER_ID` 从 `~/.munk-release/secrets.env` 用 `set -a; . ~/.munk-release/secrets.env; set +a` 载入（该文件键名含 `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH`）。禁 `set -x`、禁 `echo`/`printf` 变量值、禁写入任何日志或回执。
- 产物与日志落仓外（建议 `artifacts/asc-export-<短sha>/` 或 `${TMPDIR}` 下的产品数据目录），仓内只放脱敏证据摘要。
- 已知风险（开场先定性、不重复踩）：本机无 Apple Distribution 身份；历史 `POST /v1/bundleIds` 曾返回 `403 FORBIDDEN_ERROR`（API Key 角色不足，非 `PLA_NOT_ACCEPTED`）。若本轮 Key 为 Admin 而仍 403，或出现 `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`，直接 `munk_report_owner`。
- 时间盒：单场 ≤60 分钟；到点即停手写回执（已完成项 + 卡点 + 未完成项），不追加探测。
