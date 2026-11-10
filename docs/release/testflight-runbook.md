# TestFlight 分发 Runbook

面向人工执行的 iOS 归档 / 导出 / 上传流程。仓库只提供可复现的归档脚本与静态门；
App 记录由一次性授权操作创建（见 `docs/release/stage4-prereqs.md`），上传构建、邀请测试者、提交审核仍是人的写操作，
不在 CI 与仓库脚本内。

## 前置

- 一台已登录 Apple Developer 账号、装有 Xcode 的 Mac，且 Xcode 命令行工具可用：`xcodebuild -version` 能输出版本。
- App Store Connect 中存在 `sh.munk.purepace` 对应的 App 记录：该记录由公司负责人授权的一次性操作创建
  （见 `docs/release/stage4-prereqs.md`），仓库脚本不创建。执行本流程前先用只读方式确认：
  - 当前 bundle id 为 `sh.munk.purepace`，由 `ios/project.yml` 的 `PUREPACE_BUNDLE_ID` 单点定义；
    换 id 后需由人在 App Store Connect 新建或更新对应 App 记录，否则 TestFlight 无对应构建。此前构建记录里的旧
    bundle id 属历史事实，保持原样。
  - `xcrun altool --list-apps`（本机已有 App Store Connect 凭据时）逐条核对 bundle id；或
  - 在 App Store Connect 网页 / ASC API 只读查询该 bundle id 的 App 记录是否存在。
  - 若不存在，先按 `docs/release/stage4-prereqs.md` 的 ASC App 记录一行处理（由人在 App Store Connect 创建，
    或由持有建记录权限的凭据执行一次授权操作），回读校验通过后再继续本流程。
- 三件凭据均由环境变量提供，值是人的本机路径/ID，不得写进仓库、日志或 shell history：
  - `ASC_KEY_PATH`：App Store Connect API 私钥 `.p8` 的绝对路径，必须位于仓库之外（例如 `~/keys/AuthKey_$ASC_KEY_ID.p8`）。
  - `ASC_KEY_ID`：API Key ID。
  - `ASC_ISSUER_ID`：API Issuer ID。
  - 示例（仅占位，真实值由人临时 export）：
    ```bash
    export ASC_KEY_PATH="$HOME/keys/AuthKey_$ASC_KEY_ID.p8"
    export ASC_KEY_ID="<你的 Key ID>"
    export ASC_ISSUER_ID="<你的 Issuer ID>"
    # 自检：只判断存在性，不打印值
    test -f "$ASC_KEY_PATH"
    test -n "$ASC_KEY_ID"
    test -n "$ASC_ISSUER_ID"
    ```
- 人在场要求：归档与导出需要 Xcode 自动签名访问钥匙串与 Apple 服务，必须由人在本机会话中执行，
  不可交给无人值守 CI；`.p8`、Issuer ID、Key ID 只留在本机环境中。
- 可选：`BUILD_NUMBER` 指定 `CURRENT_PROJECT_VERSION`，缺省 1；`OUT_DIR` 覆盖产物目录，
  缺省为 `${TMPDIR:-/tmp}/purepace-dist/<version>-<build>`，始终在仓库之外。

## 执行步骤

1. 在仓库根确认工作区干净、记录当前 commit（证据用）：
   ```bash
   git rev-parse HEAD
   ```
2. 设置 `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID`（见前置），确认路径在仓库外。
3. 先做一次脱敏预演，确认命令与版本接线无误（不要求凭据、不触网）：
   ```bash
   DRY_RUN=1 bash scripts/archive-ios.sh
   ```
4. 真实归档与导出（生成 archive、`.app`、`.app.dSYM`、两个 zip 与 `checksums.txt`）：
   ```bash
   bash scripts/archive-ios.sh
   ```
   脚本读取 `scripts/version.sh` 作为 `MARKETING_VERSION`、`BUILD_NUMBER` 作为
   `CURRENT_PROJECT_VERSION`，以 xcodebuild 命令行覆盖，不修改 `ios/project.yml`。
5. 静态门自查（与 CI 同层）：
   ```bash
   bash scripts/check-ios-release.sh
   ```
6. 由人在 Xcode Organizer 或 Transporter 中把导出产物上传到 App Store Connect，
   在 TestFlight 页面等待处理完成后分发。本仓库脚本不执行上传。
7. 记录证据并归档（见下节），随后清除本机临时凭据环境变量：
   ```bash
   unset ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
   ```

## 证据归档清单

把以下内容记入本次分发记录（可放在 `docs/evidence/` 或团队发布记录中，且不含任何凭据值）：

- 归档与导出产物：`PurePace.app.zip`、`PurePace.app`、`PurePace.app.dSYM`（以及 `PurePace.app.dSYM.zip`）的路径。
- 每个 zip 的 `sha256`：脚本会打印并写入 `OUT_DIR/checksums.txt`；缺失 `shasum` 时回退 `sha256sum`。
- 工具链版本：`xcodebuild -version` 输出。
- 代码版本：`git rev-parse HEAD` 得到的 commit。
- 版本号与 build 号：`bash scripts/version.sh` 与本次使用的 `BUILD_NUMBER`。
- 静态门结果：`bash scripts/check-ios-release.sh` 的退出码与末行摘要。

## 反范围

- 不 push tag、不创建 GitHub Release、不在 CI 中触发分发。
- 不在仓库内写 `.p8`、`.env` 或任何凭据文件；不把 Key ID / Issuer ID / 私钥内容写入仓库、日志、截图或本 Runbook。
- 不上传构建、不提交 App 审核、不发送 TestFlight 邀请（这些是人的写操作）。
- App 记录只由公司负责人授权的一次性操作创建（见 `docs/release/stage4-prereqs.md`）；仓库脚本不复用该授权、不创建记录。
- 不修改 `ios/project.yml` 的签名设置、版本主干或 bundle id；不手写 `project.pbxproj`。
- 不引入任何第三方分发框架或运行时依赖；分发只依赖 Xcode 自带命令。
