# PurePace Release candidate 2c7c4f3（历史候选，仅记录构建身份，非 TestFlight 发布包）

本文件是产品数据目录记录
`products/codebase_19e8ad47434ff059/artifacts/candidates/Release-candidate-2c7c4f3.txt`
的仓内同值摘要。zip 本体不入 git，只在仓外 candidates 目录保留；此处不放大二进制。

## 核心事实（与 txt 逐字同值）

| 字段 | 取值 |
| --- | --- |
| commit | `2c7c4f36dfdc09acfb37a3888f206512b42e7eb2`（origin/main tip，短 sha `2c7c4f3`） |
| zipSha256 | `e08fda6bbbcb68ecbb26e019e4c1219f938e932883b5e7fb11d65375b1a86f5a` |
| zipBytes | `428138` |
| execName | `PurePace` |
| execSha256 | `8ccaf131cccd615c5cc2acf10e697482e10627853fdd524a77eed5921099092f` |
| execBytes | `1565104` |
| UIBackgroundModes | `["location","audio"]` |

zip 路径（仓外）：`products/codebase_19e8ad47434ff059/artifacts/candidates/PurePace-Release-0.1.0-20261110T014651Z.zip`

## 构建与产物断言

- `builtAt`: 2026-11-10T01:46Z（local 2026-11-10 09:46 CST）
- 工程：`xcodegen generate --spec project.yml` 生成（未手改 pbxproj），`ios/project.yml` 零签名/team 改动。
- 构建：`xcodebuild -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates`，派生数据 `.build/release-candidate-2c7c4f3`。
- 签名：`Authority=Apple Development: Tao Zhu (H47755VBGF)`，`TeamIdentifier=3X4J53U6RY`，`Provisioning Profile: iOS Team Provisioning Profile: * (189a9987-fed0-4221-a4c4-efbd849fe6ea)`。
- 产物 `PurePace.app/Info.plist`（解压后读回）：`CFBundleIdentifier=sh.munk.purepace`、`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0`、`UIBackgroundModes=["location","audio"]`。
- `find PurePace.app -name 'PurePace.debug.dylib' | wc -l` = `0`（`debugDylibCount=0`）。
- 二进制含 `-releaseDeterministicLocation` 字符串；无该 flag 时仍走真实 CoreLocation，默认关的负例断言
  `PurePaceTests.ReleaseDeterministicLocationSourceTests.testDefaultSelectionReturnsInjectedRealSourceWithoutBuildingDeterministicSource` 已在本地单测腿执行通过。

## 双 sha（真实计算，非编造）

- zip：`shasum -a 256` + `stat -f%z` 实跑；
- 主二进制：解包 zip 后对 `PurePace.app/PurePace` 实跑 `shasum -a 256` + `stat -f%z`，与构建产物本体一致。

## 本地阻断门（全部退出码 0）

| 门 | 结果 |
| --- | --- |
| `bash -n scripts/version.sh` / `bash -n scripts/check-baseline.sh` | 0 |
| `scripts/check-baseline.sh` | 11 项断言 0 失败 |
| `scripts/check-ios-core.sh` | 8 项断言 0 失败 |
| `scripts/check-ios-scripts.sh` | 25 项断言 0 失败 |
| `scripts/check-ios-release.sh` | 17 项断言 0 失败 |
| `scripts/check-ios-shell.sh` | 20 项断言 0 失败 |
| `scripts/check-ios-workflow.sh` | 结构门通过（含负向自检） |
| `scripts/check-ios-run-core.sh` | 11 项断言 0 失败 |
| `scripts/check-shared.sh` | 13 项断言 0 失败 |
| `scripts/check-shell-expansion.sh` | 7 项断言 0 失败 |
| `scripts/version.sh` | `0.1.0` |
| `swift build --package-path ios/Core` | Build complete |
| `swift test --package-path ios/Core` | 9 tests，0 failures |
| `swift build --package-path ios/RunCore` | Build complete |
| `swift test --package-path ios/RunCore` | 123 tests，0 failures |
| `scripts/test-ios.sh --unit-only` | 0（PurePaceTests 99 tests 0 failures） |

## 边界与状态

- `iosCI`: 2c7c4f3 ios run [42737709123](https://github.com/munk-sh/open-pace/actions/runs/42737709123) `in_progress` 待出结论（headSha 与记录 commit 一致）；重 UI E2E 权威在该同 commit run。
- 严格零业务源码改动：相对 tip 仅新增 `docs/release/candidates/Release-candidate-2c7c4f3.md`（以及流水线元数据）。
- 未 push tag、未建/改 GitHub Release、未上传 TestFlight、未建 ASC 记录。
- 未写真机已验证：真机三项仍 `pending: 待人现场`；真机窗口开工前须从设备已安装 bundle 读回 `Info.plist`，确认 `UIBackgroundModes` 实际含 `location` 与 `audio`（不得只核构建产物）。
