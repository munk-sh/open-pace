# PurePace Release candidate 7ce3dfe（历史候选，仅记录构建身份，非 TestFlight 发布包）

本文件是产品数据目录记录
`products/codebase_19e8ad47434ff059/artifacts/candidates/Release-candidate-7ce3dfe.txt`
的仓内同值摘要。zip 本体不入 git，只在仓外 candidates 目录保留；此处不放大二进制。

## 核心事实（与 txt 逐字同值）

| 字段 | 取值 |
| --- | --- |
| commit | `7ce3dfef6e179c6d62857efb8b1c411ccf4a38b8`（origin/main tip 实取，短 sha `7ce3dfe`） |
| zipSha256 | `a000b0e19c2ee4b5c7f8e067abd9f4c25f95b43569c45b29160c73e38c736897` |
| zipBytes | `441544` |
| execName | `PurePace` |
| execSha256 | `d494746936c99043557ae3ba82fe2c94a3bb84c9beb0412e242dda182ef7139d` |
| execBytes | `1619696` |
| UIBackgroundModes | `["location","audio"]` |

zip 路径（仓外）：
`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/PurePace-Release-0.1.0-20261110T054214Z.zip`

## tip 与构建

- tip：`git ls-remote --heads origin main` = `7ce3dfef6e179c6d62857efb8b1c411ccf4a38b8`，与基线一致（无前进、无差异）。
- `builtAt`：2026-11-10T05:42Z（local 2026-11-10 13:42 CST）。
- 工程：`xcodegen generate --spec ios/project.yml`（退出码 0）生成；`git status --porcelain ios/` 为空（未手改 pbxproj），`git diff --exit-code ios/project.yml` 退出码 0。
- 构建：`xcodebuild -project ios/PurePace.xcodeproj -scheme PurePace -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates`（退出码 0），派生数据 `.build/release-candidate-7ce3dfe`；签名参数仅命令行。
- 签名：`Authority=Apple Development: Tao Zhu (H47755VBGF)`，`TeamIdentifier=3X4J53U6RY`，`Provisioning Profile: iOS Team Provisioning Profile: * (189a9987-fed0-4221-a4c4-efbd849fe6ea)`。

## 四项必核（全部通过）

| 核项 | 结果 |
| --- | --- |
| `debugDylibCount` | `0`（构建产物与 zip 解包各实测） |
| plist | `CFBundleIdentifier=sh.munk.purepace`、`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0`、`UIBackgroundModes` 实际数组 `Array { location audio }` = `["location","audio"]`（打 `PurePace.app` 本体，非 UITests runner） |
| 二进制 strings | `-releaseDeterministicLocation` 命中、`-autoStartRecording` 命中（各 1 次） |
| codesign | `Authority=Apple Development: Tao Zhu (H47755VBGF)`、`TeamIdentifier=3X4J53U6RY` |

## 双 sha（真实计算，非编造）

- zip：`shasum -a 256` + `stat -f%z` 实跑得 `a000b0e1…` / `441544`。
- 主二进制：解包 zip 后对 `PurePace.app/PurePace` 实跑得 `d4947469…` / `1619696`，与构建产物本体逐字一致。

## 模拟器干净安装启动冒烟（PASS）

- 设备 `iPhone 16` UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`；`simctl shutdown/erase/boot/bootstatus/install/launch` 全部退出码 0，`launch` 输出 `sh.munk.purepace: 27423`。
- 进程存活：`launchctl list` 命中 `27423  0  UIKitApplication:sh.munk.purepace[8913][rb-legacy]`，元素树 dump 后复核仍存活。
- 证据目录 `.build/release-candidate-7ce3dfe/smoke/`：`03-first-screen.png`（截图 1179x2556）、`05-element-tree.txt`（首屏元素树 dump，根 `UIWindow` 393x852，含 Run/History/Settings）、`04-process-alive.txt`（launchctl list + ps）、`00-timeline.txt` / `01-install.txt` / `02-launch.txt`、`02a-device-slice-launch-denied.txt`。
- 口径：设备切片（`LC_BUILD_VERSION platform 2`、`CFBundleSupportedPlatforms=iPhoneOS`）在 `dyld_sim` 下无法启动，冒烟改用同一 commit / 同一 `project.yml` / 同一 Release 配置的模拟器切片构建（`-destination 'generic/platform=iOS Simulator'`，`CODE_SIGNING_ALLOWED=NO`）完成；未改源码或脚本。zip 内设备切片由四项必核全部核验。

## 边界与状态

- `iosCI`: 7ce3dfe ios run 待出结论（run 链接待补，不编造 run id）。
- 作废声明：旧包 `2c7c4f3` / `1e7e653` / `667e1bc` 全部作废不得复用。
- 未重跑全量 code_gates、未打 tag、未 push、未建/改 GitHub Release、未上传 TestFlight、未建 ASC 记录、未真机装包。
- 相对 tip 的仓内改动仅 `.munk/changes/wi_intake_8960dcee8527da3f/**` 与本文件；zip 二进制不入 git。
- 真机窗口开工前须从设备已安装 bundle 读回 `Info.plist`，确认 `UIBackgroundModes` 实际含 `location` 与 `audio`（不得只核构建产物）。
