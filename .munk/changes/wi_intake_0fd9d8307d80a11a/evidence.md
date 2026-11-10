# 证据回执：ASC app-store-connect 出包通路验证（efeb57d）

状态：**卡在 ASC App 记录写操作（403 角色权限不足），已按口径停止并上报 Owner**；archive / export / .ipa 未产出。
未上传、未打 tag、未改 `ios/project.yml` / `ios/PurePace.xcodeproj`、未改任何脚本与 `code-gates.json`。

## 0. 起点

- worktree HEAD：`efeb57d2983ab9e936fe4b8d8cab5eb669ed6928`（`main` tip），`git status --porcelain` 仅本 change pack 目录为 untracked。
- 本机身份（`security find-identity -v -p codesigning`）：3 条有效身份，均为 Developer ID Application / Apple Development，**Apple Distribution 为 0**（与 Intake 实测一致）。
- 工具链：Xcode 26.3 (17C529) / xcodegen（homebrew）/ fastlane 2.232.2。

## 1. ASC App 记录（唯一写操作）

- 尝试 1（`fastlane produce create`，bundle `sh.munk.purepace`、sku `purepace-ios`、platform `ios`、primary language `zh-Hans`）：
  `exit=1`，原文 `invalid option: --api_key_path` —— 本机 fastlane 版本不支持 ASC API Key 传参，与历史实测一致。
  日志：`.build/asc-export/produce.log`（仓内 gitignored，未提交）。
- 只读回读（`GET /v1/apps` / `GET /v1/bundleIds`，均 HTTP 200）：`count=0`，即 ASC 无该 App 记录、开发者门户无该 Bundle ID。
- 尝试 2（PRD 允许的等价退化：单次 `POST /v1/bundleIds`，payload `identifier=sh.munk.purepace` / `name=PurePace` / `platform=IOS`）：
  **HTTP 403**，`errors[0].code = FORBIDDEN_ERROR`，
  `title = This request is forbidden for security reasons`，
  `detail = You are not allowed to perform this operation.  Please check with one of your Team Admins, or, if you need further assistance, please contact Apple Developer Program Support. https://developer.apple.com/support`
  响应原文：`.build/asc-export/post-bundleids.json`。**未发第二次写请求、未换端点、未重试。**
- 定性：这是 **API Key 角色权限不足**（非 `PLA_NOT_ACCEPTED`，响应未出现该码）。同一把 Key 的只读 GET 正常（200），说明密钥/issuer/JWT 正确，缺的是团队角色（Admin / App Manager 级写权限）。

## 2. 未执行项（因第 1 步 403 即停）

- `xcodegen generate` → `xcodebuild archive -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates DEVELOPMENT_TEAM=3X4J53U6RY`：未执行（Bundle ID 无法写入门户，`-allowProvisioningUpdates` 必然复用同一条被拒通路）。
- `xcodebuild -exportArchive -method=app-store-connect`：未执行。
- `.ipa` 绝对路径 + sha256、archive/export 原始日志、Apple Distribution 身份出现、`embedded.mobileprovision` 解码：均无产物（不解锁角色无法产出，未以自造证书/手工 profile 绕过）。

## 3. 已跑的最小门（ac-minimal-gates-only）

- `id=lint-ios-release` / `bash scripts/check-ios-release.sh` → `exit=0`，17 项断言 0 失败（日志 `.build/asc-export/check-ios-release.log`）。
- 未执行全量 `code_gates`；`git status --porcelain ios/` 为空。

## 4. 脱敏

本文件不含 Issuer ID、Key ID、私钥内容与用户主目录绝对路径；所有凭据只经环境变量传递，全程未 `set -x`、未打印变量值。

## 5. 解除阻塞所需（Owner 决策）

给该 ASC API Key 的团队角色升级到 **Admin**（或至少具备 App Manager + 证书/描述文件写权限），或换一把管理员 Key；之后重跑同一条链即可继续验证 `-allowProvisioningUpdates` 能否自动产出 Apple Distribution 证书与 App Store 描述文件。

## 6. 本项结论

**本项结论：ASC API Key 无写权限（403 FORBIDDEN_ERROR），L1 上传通路待 ASC 角色提升或换 Admin key；未产 .ipa，未上传。**

- 收口方式：外部权限阻塞（非代码缺陷、非签名配置缺陷）。Owner 已确认不再尝试任何门户写操作，也不再跑 archive / export（同一把 Key 的写路径必然同 403）。
- 未改动源码、`ios/project.yml`、`ios/PurePace.xcodeproj`、脚本与 `.munk/code-gates.json`；`git status --porcelain ios/` 为空。
- 复跑条件：Key 具备 Admin（或 App Manager + 证书/描述文件写）权限后，重跑 `POST /v1/bundleIds` → `xcodebuild archive -allowProvisioningUpdates DEVELOPMENT_TEAM=3X4J53U6RY` → `xcodebuild -exportArchive -method=app-store-connect`，按本回执第 2 节未执行项补齐证据即可收口。
