# TestFlight 分发 Runbook

主路径全部由仓库脚本完成：归档与导出 → 脚本上传 App Store Connect → 脚本把内部测试者加入
TestFlight 内部组。人的动作只剩一次性录入凭据（见 `docs/human-gate-distribution.md`）；
Xcode Organizer / Transporter 仅作 fallback，不再是主路径。

## 前置

- 一台装有 Xcode 的 Mac，且 Xcode 命令行工具可用：`xcodebuild -version` 能输出版本。
- App Store Connect 中存在 `sh.munk.purepace` 对应的 App 记录：该记录由公司负责人授权的一次性操作创建
  （见 `docs/release/stage4-prereqs.md`），仓库脚本不创建。执行本流程前先用只读方式确认：
  - 当前 bundle id 为 `sh.munk.purepace`，由 `ios/project.yml` 的 `PUREPACE_BUNDLE_ID` 单点定义；
    换 id 后需由人在 App Store Connect 新建或更新对应 App 记录，否则 TestFlight 无对应构建。此前构建记录里的旧
    bundle id 属历史事实，保持原样。
  - `xcrun altool --list-apps`（本机已有 App Store Connect 凭据时）逐条核对 bundle id；或
  - 在 App Store Connect 网页 / ASC API 只读查询该 bundle id 的 App 记录是否存在。
  - 若不存在，先按 `docs/release/stage4-prereqs.md` 的 ASC App 记录一行处理（由人在 App Store Connect 创建，
    或由持有建记录权限的凭据执行一次授权操作），回读校验通过后再继续本流程。
- 凭据只需人一次性录入，逐条步骤与安全边界见 `docs/human-gate-distribution.md`。脚本只从以下环境变量读取，
  值是人的本机路径/ID，不得写进仓库、日志或 shell history：
  - `ASC_KEY_PATH`：App Store Connect API 私钥 `.p8` 的绝对路径，必须位于仓库之外（例如 `~/keys/AuthKey_$ASC_KEY_ID.p8`）。
  - `ASC_KEY_ID`：API Key ID。
  - `ASC_ISSUER_ID`：API Issuer ID。
  - `TESTFLIGHT_TESTER_EMAIL`：要加入内部测试组的测试者邮箱。
  - 示例（仅占位，真实值由人临时 export）：
    ```bash
    export ASC_KEY_PATH="$HOME/keys/AuthKey_$ASC_KEY_ID.p8"
    export ASC_KEY_ID="<你的 Key ID>"
    export ASC_ISSUER_ID="<你的 Issuer ID>"
    export TESTFLIGHT_TESTER_EMAIL="<测试者邮箱>"
    # 自检：只判断存在性，不打印值
    test -f "$ASC_KEY_PATH"
    test -n "$ASC_KEY_ID"
    test -n "$ASC_ISSUER_ID"
    test -n "$TESTFLIGHT_TESTER_EMAIL"
    ```
- 归档与导出使用 Xcode 自动签名；凭据只经环境变量传给脚本，`.p8`、Issuer ID、Key ID 只留在本机环境中。
- 可选：`BUILD_NUMBER` 指定 `CURRENT_PROJECT_VERSION`，缺省 1；`OUT_DIR` 覆盖产物目录，
  缺省为 `${TMPDIR:-/tmp}/purepace-dist/<version>-<build>`，始终在仓库之外。

## 执行步骤

1. 在仓库根确认工作区干净、记录当前 commit（证据用）：
   ```bash
   git rev-parse HEAD
   ```
2. 一次性录入凭据：按 `docs/human-gate-distribution.md` 导出 `ASC_KEY_PATH` / `ASC_KEY_ID` /
   `ASC_ISSUER_ID` / `TESTFLIGHT_TESTER_EMAIL`，确认 `.p8` 在仓库外。
3. 先做脱敏预演，确认命令与版本接线无误（不要求凭据、不触网）：
   ```bash
   DRY_RUN=1 bash scripts/archive-ios.sh
   DRY_RUN=1 bash scripts/upload-ios.sh
   DRY_RUN=1 bash scripts/testflight-tester.sh
   ```
4. 真实归档与导出（生成 archive、`.app`、`.app.dSYM`、两个 zip 与 `checksums.txt`）：
   ```bash
   bash scripts/archive-ios.sh
   ```
   脚本读取 `scripts/version.sh` 作为 `MARKETING_VERSION`、`BUILD_NUMBER` 作为
   `CURRENT_PROJECT_VERSION`，以 xcodebuild 命令行覆盖，不修改 `ios/project.yml`。
5. 脚本上传到 App Store Connect（先用 `xcrun altool --list-apps` 只读核对，再执行上传）：
   ```bash
   bash scripts/upload-ios.sh
   # 需要指定非默认产物时：bash scripts/upload-ios.sh --ipa "<ipa 路径>"
   ```
6. 脚本把内部测试者加入 TestFlight 内部组（只读解析 App 与内部组，必要时创建 betaTester）：
   ```bash
   bash scripts/testflight-tester.sh
   ```
7. 静态门自查（与 CI 同层）：
   ```bash
   bash scripts/check-ios-release.sh
   ```
8. 在 App Store Connect / TestFlight 只读确认构建已处理完成、测试者已在内部组；这一步只是核对结果，不是上传或邀请操作。
9. 记录证据并归档（见下节），随后清除本机临时凭据环境变量：
   ```bash
   unset ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID TESTFLIGHT_TESTER_EMAIL
   ```

## fallback（非主路径）

仅当本机脚本链路异常（例如 `xcrun altool` 不可用）时，才退回 Xcode Organizer 或 Transporter 手工上传，
再由 TestFlight 页面手工分配内部测试者。这是 fallback，不是主路径；恢复后仍应回到脚本上传 + 脚本分配测试者。

## 证据归档清单

把以下内容记入本次分发记录（可放在 `docs/evidence/` 或团队发布记录中，且不含任何凭据值）：

- 归档与导出产物：`PurePace.app.zip`、`PurePace.app`、`PurePace.app.dSYM`（以及 `PurePace.app.dSYM.zip`）的路径。
- 每个 zip 的 `sha256`：脚本会打印并写入 `OUT_DIR/checksums.txt`；缺失 `shasum` 时回退 `sha256sum`。
- 工具链版本：`xcodebuild -version` 输出。
- 代码版本：`git rev-parse HEAD` 得到的 commit。
- 版本号与 build 号：`bash scripts/version.sh` 与本次使用的 `BUILD_NUMBER`。
- 上传结果：`bash scripts/upload-ios.sh` 的 ipa 路径、版本/build 与上传结果行（不含凭据）。
- 内部测试者结果：`bash scripts/testflight-tester.sh` 的测试者邮箱与内部 betaGroup 名称（不含凭据）。
- 静态门结果：`bash scripts/check-ios-release.sh` 的退出码与末行摘要。

## 反范围

- 不 push tag、不创建 GitHub Release、不在 CI 中触发分发。
- 不在仓库内写 `.p8`、`.env` 或任何凭据文件；不把 Key ID / Issuer ID / 私钥内容 / JWT 写入仓库、日志、截图或本 Runbook。
- 上传与测试者分配走脚本主路径；Xcode Organizer / Transporter 只作 fallback。
- 只向 `isInternalGroup=true` 的内部组写测试者关系，不触发 Beta App Review、不向外部组邀请、不提交 App 审核。
- App 记录只由公司负责人授权的一次性操作创建（见 `docs/release/stage4-prereqs.md`）；仓库脚本不复用该授权、不创建记录。
- 不修改 `ios/project.yml` 的签名设置、版本主干或 bundle id；不手写 `project.pbxproj`。
- 不引入任何第三方分发框架或运行时依赖；分发只依赖 Xcode 自带命令与系统 `curl` / `openssl`。
