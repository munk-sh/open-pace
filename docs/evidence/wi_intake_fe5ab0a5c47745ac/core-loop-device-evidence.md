# 核心闭环真机零可用修复 · 本项证据（wi_intake_fe5ab0a5c47745ac）

> 口径：本文件所有数字均来自本机实跑，命令与日志路径可复核。未跑齐的腿在末节如实列出。

## 1. 构建期 plist 读回（同 commit 包产物，不导出、不上传、非分发候选）

- commit: `f57f562ab8c7a8ee6e0e517a1aaf15a3a20f376e`（code 面最后一条；含 SHA 注入脚本路径转义修复）
- 归档命令：`xcodebuild archive -project ios/PurePace.xcodeproj -scheme PurePace -configuration Release -destination 'generic/platform=iOS' -archivePath .build/archive3/PurePace.xcarchive -derivedDataPath .build/archive-dd3 CODE_SIGNING_ALLOWED=NO`（`** ARCHIVE SUCCEEDED **`）
- 读回对象：`.build/archive3/PurePace.xcarchive/Products/Applications/PurePace.app/Info.plist`（sha256 `78e023b3a787dd5ef7b78144a56e7cf7f0681c825bf5613b1327da80c0b234c2`）
- 读回原值（`plutil -extract <key> raw`）：
  - `NSLocationWhenInUseUsageDescription` = `PurePace 在跑步过程中使用定位来记录路线、距离与配速。`
  - `NSLocationAlwaysAndWhenInUseUsageDescription` = `PurePace 需要「始终允许」定位权限，以便在锁屏或切到后台时继续记录跑步路线与配速。`
  - `UIBackgroundModes` = `["location","audio"]`
  - `PurePaceBuildSHA` = `f57f562a`（构建期写入，运行时读 plist，不读 git）
  - `CFBundleIdentifier` = `sh.munk.purepace`；`CFBundleShortVersionString` = `0.1.0`；`CFBundleVersion` = `1`
- 上次 `ad123a2` 归档读回 `PurePaceBuildSHA` 缺失：脚本里 `git -C \"${SRCROOT}/..\"` 的 `\"` 在 `"..."` 内成为字面量引号，git 路径被打断后静默跳过；改为不转义后重新归档，`f57f562a` 读回成功。

## 2. 诊断区两读数（raw 回调数 / 精度过滤丢弃数）

`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift::testDiagnosticsSnapshotReportsVersionSHAAndCallbackCounters` 以 `rawCallbackCount: 12 / filteredCallbackCount: 12` 构造快照，断言文案含 `原始回调: 12` 与 `精度过滤丢弃: 12`；另断言 sha 仅展示前 8 位、缺 sha 写「未注入」、未拿 Always 写「仅前台」。该用例实跑通过（见下节 293/0）。

## 3. 计时解耦断言红绿记录

绿（本机 `swift test --package-path ios/RunCore`，Executed **177 tests, 0 failures**）：`testElapsedTicksWithClockAndZeroLocationSamples` / `testPauseFreezesElapsedAndResumeContinues` / `testFinishWithoutAnySampleArchivesClockDrivenDuration` / `testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance`。

红（反例证明，不改仓库：把包复制到 `/tmp/pp-runcore-red`，仅把 `liveActiveElapsed` 改回「忽略注入时钟、只取已结算账本」的旧行为，再跑同一组用例）：
- `testElapsedTicksWithClockAndZeroLocationSamples` 红：`("0.0") is less than ("4.5")`、`("0.0") is not equal to ("5.0")`
- `testPauseFreezesElapsedAndResumeContinues` 红：`("0.0") is not equal to ("3.0")`、`("3.0") is not equal to ("5.0")`
- `testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance` 与 `testFinishWithoutAnySampleArchivesClockDrivenDuration` 在该变异下仍绿（前者本就断言冻结时钟下 elapsed 必须为 0，是守门反例；后者断言空样本 finish 仍产记录）。删除 `/tmp` 副本后仓库零改动。

## 4. 本机快腿实跑（全部 exit 0）

| 命令 | 结果 |
|---|---|
| `bash scripts/check-baseline.sh` | 29 项断言 0 失败 |
| `bash scripts/check-ios-core.sh` | 8 项断言 0 失败 |
| `bash scripts/check-ios-run-core.sh` | 11 项断言 0 失败 |
| `bash scripts/check-ios-scripts.sh` | 38 项断言 0 失败 |
| `bash scripts/check-ios-shell.sh` | 33 项断言 0 失败 |
| `bash scripts/check-ios-shell.sh --self-test` | 102 项断言 0 失败 |
| `bash scripts/check-ios-release.sh` / `check-ios-workflow.sh` | exit 0 |
| `bash scripts/check-shared.sh` / `check-gpx-export.sh` / `check-shell-expansion.sh` | exit 0 |
| `bash scripts/check-android.sh` / `check-android-workflow.sh` | exit 0（仅静态结构断言） |
| `swift build --package-path ios/Core` | exit 0 |
| `swift build --package-path ios/RunCore` | exit 0 |
| `swift test --package-path ios/Core` | Executed 20 tests, 0 failures |
| `swift test --package-path ios/RunCore` | Executed 177 tests, 0 failures |
| `bash scripts/test-ios.sh --unit-only` | PurePaceTests **Executed 293 tests, 0 failures**；`** TEST EXECUTE SUCCEEDED **`（日志 `.build/logs/xcodebuild-unit.log` / `/tmp/test-ios-unit.log`） |

修复过程中曾红的三项（最小修后转绿）：`check-ios-shell.sh --self-test` 红于「新增 identifier 缺少可读 accessibilityLabel」与冻结计数（49/50 → 56/57），补 `.accessibilityLabel(Text(L10n.*))` 后绿；红于 `import UIKit` 非允许 import，改用 SwiftUI 已暴露的 `UIPasteboard` 后绿；`DocsVerificationMatrixTests` 因新增接缝行缺失而需同步常量。

## 5. 未闭合点（如实交付）

- **ac-location-error 未闭合**：`ios/PurePace/Location/RunLocationSource.swift` 的 `CLLocationManagerDelegate` 仅实现 `locationManagerDidChangeAuthorization` 与 `didUpdateLocations`，**无 `didFailWithError`、无 `locationServicesEnabled` 前置检查**，也无对应断言；本机 grep 在 `ios/` 源码与测试中零命中。按收口令未扩面补齐，留待后续小项。
- `run.waitingLocation` 胶囊与 `scenePhase == .active` 复检：实现存在（`RunView.swift` / `RunSessionViewModel.swift`），但无自动化断言，标 `pending: 待人现场`（复测步骤见 `docs/distribution/manual-test-guide.md` 第 8 节）。
- **未跑齐**：真实 UI 腿（`scripts/test-ios.sh` 全量含 4 段 XCUITest）与 Android `build`/`test` 实跑未执行（预算到点；本项零 Android 功能改动）；iOS 权威腿结论仍以同 commit `ios.yml` run 为准，本地仅旁证。
- 真机行为未验：所有真机相关项一律 `pending: 待人现场`，本文件不含任何「真机已验证」结论。
