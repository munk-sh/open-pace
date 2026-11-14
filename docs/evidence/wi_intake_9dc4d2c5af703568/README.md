# 交付候选产物与音频机器层读数（wi_intake_9dc4d2c5af703568）

- 本项交付范围绑定 commit：`2873ae21ee05c890980be28a63dda1d7da573bcf`（main，含 manual-test-guide `21158ffd` 与布局断言去抖 `2873ae2`）
- Android 产物验收键：**sha256 + 版本 + APK 字节**（`manifest.json` 里的 commit 字样只是构建时标记，不是验收键）
- `manifest.json` 的 `commit` 语义 = **构建时工作树 commit**：第一轮 `2873ae21ee05c890980be28a63dda1d7da573bcf`，
  盘上第二轮 `48b3e5c82c7988df8bc1a1e0c5cf949006c45602`；两次构建在 `android/ ios/ shared/ scripts/` 路径上零差异
  （依据见第 1.1 节），因此两轮 APK 字节一致（同一 sha256）
- 采集主机：macOS darwin-arm64，Xcode 26.3，JDK 21（Zulu 21.0.1），Android SDK（compileSdk 36）
- 本目录每个数字都能在下表「证据文件」内找到对应行。
- **iOS .ipa 未产出（凭据未就位）**：人闸 `assist:32aa20a9` 未判定，本项不生成裸包冒充 iOS 产物；
  本目录不含任何 `.ipa`，也不含上传 / 分发 / 上架口径。

## 1. Android debug APK 候选产物

| 项 | 实测值 | 证据文件 |
|---|---|---|
| 打包命令 | `bash scripts/package-android.sh`（退出码 0） | `android-package.log` 末 3 行 `APK=` / `SHA256=` / `DIST_DIR=` |
| 产物目录（仓外） | `/private/var/folders/hn/rqf4yrcj4yn53l0vghdcgjcr0000gn/T/purepace-dist/android/0.1.0-1` | `android-package.log` `DIST_DIR=` 行 |
| APK 绝对路径 | `/private/var/folders/hn/rqf4yrcj4yn53l0vghdcgjcr0000gn/T/purepace-dist/android/0.1.0-1/purepace-0.1.0-1-debug.apk`（11 760 611 B，zip magic `PK`） | `android-package.log` `APK=` 行；脚本内 `unzip -l` 校验通过 |
| sha256 | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | `android-manifest.json` `sha256`；`android-checksums.txt`；`android-package.log` `SHA256=` 行 |
| versionName | `0.1.0`（等于根 `VERSION`，`VERSION` 未修改） | `android-manifest.json` `version` |
| versionCode | `1`（构建产物实测值，`android/app/build.gradle.kts` 单点定义，本项只读） | `android-manifest.json` `versionCode` |
| applicationId | `sh.munk.purepace` | `android-manifest.json` `applicationId` |
| commit（构建时工作树，第一轮） | `2873ae21ee05c890980be28a63dda1d7da573bcf` | `android-manifest.json` `commit` |
| minSdk / targetSdk | `26` / `36` | `android-manifest.json` |
| buildTime（第一轮） | `2026-11-14T19:59:46Z` | `android-manifest.json` |
| 自校验 | 在产物目录执行 `shasum -a 256 -c checksums.txt` → `purepace-0.1.0-1-debug.apk: OK`，退出码 0 | `android-checksums-verify.log` |
| 产物保留 | 未改名、未删除、未搬迁；脚本按既有契约写 `<versionName>-<versionCode>` 目录 | `android-package.log` |

三类产物齐备：`purepace-0.1.0-1-debug.apk`（非空）、`manifest.json`、`checksums.txt`；
分发根在仓库外（脚本内置「产物路径落在仓内即拒绝」断言，本次通过）。

### 1.1 两轮构建：同一 sha256、两个构建时 commit

| 轮次 | 构建时工作树 commit（manifest.commit） | buildTime | sha256 | 字节 |
|---|---|---|---|---|
| 第一轮 | `2873ae21ee05c890980be28a63dda1d7da573bcf` | `2026-11-14T19:59:46Z` | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | 与第二轮字节一致 |
| 第二轮（盘上现行产物） | `48b3e5c82c7988df8bc1a1e0c5cf949006c45602` | `2026-11-14T20:17:29Z` | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | 与第一轮字节一致 |

两轮 manifest 快照都在本目录：第一轮 `android-manifest.json`，第二轮 `android-manifest-ondisk-48b3e5c.json`。

「代码路径零差异」的可核验依据（命令原样、输出为空即无代码路径变化）：

```bash
git diff --name-only 2873ae2 707da7f | grep -E '^(android|ios|shared|scripts)/'
# 输出为空，退出码 1
```

同命令未过滤的完整输出（只含 `docs/` 与 `.munk/` 路径，无 `android/ ios/ shared/ scripts/` 前缀）与
本项实跑日志：`docs/evidence/wi_intake_8cf34194e113d153/android-two-build-zero-diff.log`。

## 2. duck 三字段（iOS 单测腿，同 commit）

命令与日志：

```bash
xcodebuild test -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:PurePaceTests/AudioSessionAdapterTests
# Executed 8 tests, with 0 failures；** TEST SUCCEEDED **（audio-duck-adapter.log）

swift test --package-path ios/RunCore --filter AudioSessionCoordinatorTests
# Executed 9 tests, with 0 failures（audio-duck-runcore.log）
```

（`ios/PurePace.xcodeproj` 由 `xcodegen generate --spec ios/project.yml` 按仓库约定生成，未入库。）

| 事实 | 实测值 | 测试名 | 证据 |
|---|---|---|---|
| 播报期 `categoryOptions` 含 `duckOthers` | 真实 `AVAudioSession` 读回 `category=playback`、`mode=spokenAudio`、`categoryOptions ⊇ {duckOthers, mixWithOthers}` | `testApplyingDefaultConfigurationReadsBackFromRealSession` | `audio-duck-adapter.log` 第 9-10 行 |
| 播报结束 duck 撤销 | `sessionDeactivated=true`、`duckRevoked=true`（默认设置下同结果） | `testEndAnnouncementRevokesDuckWhenActivationDucked` | `audio-duck-adapter.log` 第 13-14 行 |
| 去激活与 duck 撤销分离 | 激活未带 `duckOthers` 时 `sessionDeactivated=true` 且 `duckRevoked=false`；两字段不互为别名 | `testEndAnnouncementSeparatesDeactivationFromDuckRevocation` | `audio-duck-adapter.log` 第 15-16 行 |
| 一次结束最多一次平台停用 | `deactivations.count == 1`，选项 `[.notifyOthersOnDeactivation]` | `testEndAnnouncementDeactivatesWithNotifyOthersExactlyOnce` | `audio-duck-adapter.log` 第 11-12 行 |
| 默认配置与停用选项 | `playback` / `spokenAudio` / `[duckOthers, mixWithOthers]`，停用选项 `[notifyOthersOnDeactivation]` | `testDefaultAnnouncementSettingsValues`、`testDeactivateCarriesNotifyOthersOption` | `audio-duck-runcore.log` 第 12-13、16-17 行 |

断言取值出处（源码行）：`ios/PurePaceTests/AudioSessionAdapterTests.swift` 第 68-69 行（`duckOthers` / `mixWithOthers`）、
第 110 行（`sessionDeactivated: true, duckRevoked: false`）、第 123 行（`sessionDeactivated: true, duckRevoked: true`）。

## 3. 环境读数（只作环境事实）

| 字段 | 实测值 | 来源 |
|---|---|---|
| `isOtherAudioPlaying` | `false` | App 进程内 `AVAudioSessionController`（`ios/PurePace/Audio/AudioSessionAdapter.swift`），经 `announcementContext` 落盘到 `telemetry.announcements[]` |
| `secondaryAudioShouldBeSilencedHint` | `false` | 同上 |
| 测试宿主 | `PurePaceUITests/RunFlowUITests/testRunProducesTelemetryAcrossKilometerBoundary`（passed，21.332s） | `audio-env-readings-xcodebuild.log` 第 154 行、第 168 行 `** TEST SUCCEEDED **` |
| 运行环境 | iPhone 16 / iOS 18.6 模拟器，commit `2873ae2`，2026-11-14T20:08:10Z | `audio-env-telemetry.json` |

- 细节与口径声明：`audio-env-readings.log`；遥测摘录：`audio-env-telemetry.json`。
- 模拟器无外部音源，两字段读 `false` 只说明该时刻系统里没有他路音频在播，不构成任何真机听感结论。
- 该 UI 腿需在调用全程按 `scripts/test-ios.sh` 同口径重申 `simctl privacy grant location-always`，
  否则用例自身的定位授权断言（与音频读数无关）会红。

## 4. 门禁实跑（四条）

| 命令 | 退出码 | 证据 |
|---|---|---|
| `bash scripts/check-baseline.sh` | 0 | `gates.log` |
| `bash scripts/check-android.sh` | 0 | `gates.log` |
| `bash scripts/check-ios-release.sh` | 0 | `gates.log` |
| `bash scripts/check-privacy-policy.sh` | 0 | `gates.log` |

## 5. 手册零发布口径自检

`grep -nE '已发布|已分发|可下载|已上架|真机已验证' docs/distribution/manual-test-guide.md` → 零命中（退出码 1）；
人耳三条（音乐不被打断 / 不切歌 / 播完音量恢复）仍为 `pending: 待人现场`。证据：`guide-zero-release-claims.log`。

## 6. 边界

- 未改产品代码（iOS / Android / shared）、未改 `VERSION`、未改 UI 与 design tokens、未改 `.github/workflows/`、未新增验证基建脚本、未推 tag。
- 未生成 iOS `.ipa`、未上传 TestFlight、未碰任何分发凭据；Android 产物只落在仓外临时目录，装机由人执行。
