# V1 最终 Release 候选包：构建 + 出包 + 记录（切点 dac291a）

## 范围

- 在切点 `dac291a22044ed7c69d659361112cee69ec98c6b`（当前 worktree HEAD 与 `origin/main` tip）上，用现有 `ios/project.yml` + xcodegen 生成工程，按 Release 配置 + 开发签名构建 iOS 设备切片产物。
- 只产出一个候选包与一份候选记录，供人按 `docs/device-manual-acceptance.md` 做真机终验；本项不执行真机验收本身。
- 候选包目录沿用既有口径（产品数据目录、仓外、zip 不入 git）：
  `/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/`
- 交付物仅两个新文件：
  - `Release-candidate-dac291a.zip`（根级 `PurePace.app/` 布局）
  - `Release-candidate-dac291a.txt`（候选记录，字段见验收）
- 本项只做「构建 + 出包 + 记录」，不改任何 App 源码 / `ios/project.yml` / `scripts/` / `docs/` / `.github/`。

## 验收

- ac-cutpoint-valid: 构建开始时 worktree `git rev-parse HEAD` 与 `git rev-parse main` / `git ls-remote --heads origin main` 均为 `dac291a22044ed7c69d659361112cee69ec98c6b`；若执行期间 main 前进且新提交触及 `ios/PurePace/**` 或 `ios/project.yml`，立即停手、不产出候选包，并在候选记录/回执中写明「切点已失效」及新旧 sha。
- ac-single-candidate: 候选目录下本 commit 只新增 1 个 `Release-candidate-dac291a.zip` 与 1 个 `Release-candidate-dac291a.txt`；既有候选文件零改动、零删除，不产出第二份候选。
- ac-zip-root-app: zip 顶层唯一目录为 `PurePace.app/`（无 `Payload/`、无 `__MACOSX/`、无其它顶层条目），解包后 `PurePace.app/Info.plist` 与 `PurePace.app/PurePace` 均存在。
- ac-zip-sha-recorded: txt 中 `zipPath` 为绝对路径；`zipSha256` 为 64 位十六进制且等于 `shasum -a 256` 对 zip 实算值；`zipBytes` 等于 `stat -f%z` 实算值。
- ac-exec-sha-recorded: txt 中主可执行文件 `PurePace.app/PurePace` 的 `execSha256` 与 `execBytes` 等于对该文件实算的 sha256 与字节数。
- ac-exec-sha-reproducible: 对同一 zip 二次独立解包重算 exec sha，与首次读数一致；再用独立 `-derivedDataPath` 重跑同一 `xcodebuild` 命令并实算新 `.app` 主二进制 sha：一致时 txt 记「可复现」；不一致时 txt 同时保留两次读数并写明差异来源（第二次构建结果只作对照，不打包、不落候选）。
- ac-plist-fields: 用 `plutil` 读回构建产物 `PurePace.app/Info.plist` 本体（非 UITests runner、非 project.yml 推断）：`UIBackgroundModes` 实际数组同时含 `location` 与 `audio`；`CFBundleIdentifier=sh.munk.purepace`；`CFBundleShortVersionString` 等于根 `VERSION`（`0.1.0`）；`CFBundleVersion=1`；`MinimumOSVersion=17.0`；txt 内保存该实测 dump。
- ac-signing-identity: `codesign -dvvv` 读回签名身份为 `Apple Development: Tao Zhu (H47755VBGF)` 且 `TeamIdentifier=3X4J53U6RY`；`git diff --exit-code -- ios/project.yml` 退出 0（签名配置只在命令行，不写入 project.yml）。
- ac-record-complete: `Release-candidate-dac291a.txt` 含：commit 全 sha、构建配置、签名身份、zip 绝对路径、zip/exec 双 sha 与字节数、上述 plist 字段 dump、构建起止时刻（含时区与总耗时）、`xcodebuild -version` 原文、所用完整命令；缺任一字段即不通过。
- ac-no-source-change: `git diff --stat -- ios android shared scripts docs .github` 为空；相对切点仅 `.munk/changes/wi_intake_13c114074a297bc6/**` 可有改动；`git status --porcelain` 中不出现 `.zip`（候选 zip 不进仓库）。
- ac-no-release-side-effects: 未创建/推送 tag、未 push、未触发 GitHub Release 或任何发布 workflow、未安装到真机、未上传 ASC/TestFlight；txt 与 prd 不出现「已验证 / 已发布」措辞，真机项一律保持 `pending: 待人现场`。
- ac-script-decision-recorded: txt 记录是否使用仓库既有脚本及其完整命令；若未使用 `scripts/archive-ios.sh`，写明原因（该脚本要求 `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID` 并走 `-exportArchive` 的 app-store-connect 口径，与本次「Release 构建 + 开发签名 + 根级 .app zip 候选」口径不一致）。

## 非目标

- 不改 App 源码、`ios/project.yml`、`scripts/`、`docs/`、`.github/`、`shared/`、`android/`、`.munk/code-gates.json`。
- 不打 tag、不 push、不触发 Release、不上传 TestFlight / App Store Connect、不建 ASC 记录。
- 不安装到真机、不做真机验收、不修改 `docs/device-manual-acceptance.md`。
- 不重跑全量 code_gates、不改断言、不降门。
- 不产出第二份候选、不重命名/覆盖/删除历史候选包。
- 不把 zip、dSYM 或任何二进制复制进 git。

## 实现约束

- 切点：`dac291a22044ed7c69d659361112cee69ec98c6b`（短 sha `dac291a`）。构建前与收尾时各核一次主分支 tip；只要新提交触及 `ios/PurePace/**` 或 `ios/project.yml` 即按 ac-cutpoint-valid 停手。
- 工程生成：`ios/PurePace.xcodeproj` 不入库，先 `cd ios && xcodegen generate --spec project.yml`；不得手写 `project.pbxproj`。
- 版本：唯一真源为根 `VERSION`（`0.1.0`），经既有 `scripts/sync-ios-version.sh` 幂等生成 `ios/Config/Version.xcconfig`（当前已为 0.1.0，运行后应无 git 改动）；`CURRENT_PROJECT_VERSION` 取 `project.yml` 基线 `1`。不得在源码/project.yml 写死版本。
- 构建命令（签名仅命令行；`project.yml` 基线为 `CODE_SIGNING_ALLOWED: NO`，靠 CLI 覆盖）：

  ```bash
  cd ios && xcodegen generate --spec project.yml
  xcodebuild -project ios/PurePace.xcodeproj -scheme PurePace \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath .build/release-candidate-dac291a \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY \
    -allowProvisioningUpdates build
  ```

  本机 `security find-identity -v -p codesigning` 已含 `Apple Development: Tao Zhu (H47755VBGF)`。
- 打包：对 `.build/release-candidate-dac291a/Build/Products/Release-iphoneos/PurePace.app` 使用 `ditto -c -k --keepParent PurePace.app <候选目录>/Release-candidate-dac291a.zip`，保证根级 `PurePace.app/` 布局；用 `unzip -Z1` 核验顶层条目。
- 候选目录：`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/`（仓外既有候选目录，历史候选 1e7e653/2c7c4f3/667e1bc/73eb801/7ce3dfe/8db1a16/ccd6037 均在此）。不放到仓库内，避免未跟踪二进制污染工作树。
- 记录口径：字段顺序与措辞对齐既有 `Release-candidate-7ce3dfe.txt`，但只写事实，不写「已验证 / 已发布」；构建起止时刻同时给 UTC 与本地时间；`xcodebuild -version` 取原文（当前 Xcode 26.3 / 17C529）。
- 失败处理：xcodegen / xcodebuild / 打包 / 校验任一步失败即停手，在候选记录或回执中写失败步骤、退出码与错误原文片段，不降级、不换签名、不重试绕过。
- 时间盒：本项总预算 ≤6M token / ≤60 分钟；超时即停手并回执已完成的步骤与现场。
