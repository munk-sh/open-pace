# 交付候选产物与音频机器层读数定稿（commit 2873ae2）

## 范围

在 main `2873ae21ee05c890980be28a63dda1d7da573bcf`（已含 manual-test-guide `21158ffd` 与布局断言去抖 `2873ae2`）上一次性产出两件事，并把手册状态列按实测值定稿：

1. **Android 可安装候选产物**：用仓内既有 `scripts/package-android.sh` 实跑，产物落仓外 `${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/`，记录 APK 绝对路径、sha256（含 `shasum -a 256 -c checksums.txt` 自校验）、versionName/versionCode、commit。
2. **音频机器层读数**（同 commit 绑定）：跑既有 duck 断言套件，把三字段实测值（播报期 `categoryOptions` 含 `duckOthers` / 播报结束 duck 是否撤销 / 去激活与 duck 撤销是否分离）落 evidence；另记 `isOtherAudioPlaying`、`secondaryAudioShouldBeSilencedHint` 实际读数与运行环境，明确标注「模拟器无外部音源，只作环境事实」。
3. **手册定稿**：`docs/distribution/manual-test-guide.md` 汇总表与音频节「机器已验」行补实测值与 evidence 相对路径；Android 获取节补本次真实产物目录名与 sha256；三条人耳结论保持 `pending: 待人现场`。
4. **iOS 归档包本项不产**：凭据未就位（人闸 `assist:32aa20a9` 未判定），不生成裸包冒充 iOS 产物；回执明确写「iOS .ipa 未产出（凭据未就位）」。

不改产品功能、不改 `VERSION`、不改 UI、不推 tag、不做分发、不建 GitHub Release。

## 验收

- ac-android-package-produced: `bash scripts/package-android.sh` 退出码 0，产物目录 `${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/` 内同时存在非空 debug APK、`manifest.json`、`checksums.txt`；APK 绝对路径在仓外（不在本仓工作树内）。
- ac-android-version-derived: 产物 `manifest.json` 的 `version` 等于根 `VERSION` 实测值（`0.1.0`），`versionCode` 等于构建产物实测值（当前 `1`），`commit` 等于 `2873ae21ee05c890980be28a63dda1d7da573bcf` 全 sha；三者均抄自 `manifest.json` 产物而非人手转写，`VERSION` 文件未被修改（`git diff` 不含 `VERSION`）。
- ac-android-checksum-selfcheck: 在产物目录执行 `shasum -a 256 -c checksums.txt` 输出逐文件 `OK` 且退出码 0；`shasum -a 256 <apk>` 实测值等于 `manifest.json.sha256` 等于 evidence 记录的 sha256。
- ac-android-dist-preserved: 产物不改名、不删除、不覆盖既有目录；若同名目录已存在且 commit/sha 不同，脚本按既有幂等契约处理并在回执写清实际落点，不手工搬动。
- ac-android-evidence-bound: `docs/evidence/wi_intake_9dc4d2c5af703568/` 存在，且记录 APK 绝对路径、sha256、versionName/versionCode、commit、运行命令、日志路径；每个数字都能在 evidence 内找到对应日志或产物行。
- ac-audio-duck-options: evidence 记录播报期 `categoryOptions` 实测结论为含 `duckOthers`，并带测试名 / 运行命令 / commit / 日志路径三元以上定位，证据来源为 `AudioSessionAdapterTests` 与 `AudioSessionCoordinatorTests` 实跑通过记录。
- ac-audio-duck-revoked: evidence 记录播报结束 `duckRevoked` 实测值为 `true`（`sessionDeactivated=true` 同结果），带测试名 / 命令 / commit / 日志路径。
- ac-audio-deactivation-separated: evidence 记录去激活与 duck 撤销是两条独立派生事实：激活未带 `duckOthers` 时 `sessionDeactivated=true` 且 `duckRevoked=false`；两字段不互为别名。
- ac-audio-env-readings: evidence 记录 `isOtherAudioPlaying` 与 `secondaryAudioShouldBeSilencedHint` 实际读数（含读数来源探针、测试宿主、运行环境：模拟器无外部音源），并显式标注仅作环境事实；全文不出现「音乐不打断」类结论。
- ac-ios-ipa-not-produced: 本项不产出任何 `.ipa`；回执与 evidence 明确写「iOS .ipa 未产出（凭据未就位）」，音频读数绑定对象写为「commit + 测试宿主产物」，不写「已上传 / 已分发 / 已上架」。
- ac-guide-machine-rows: `docs/distribution/manual-test-guide.md` 第 3 节机器层事实表与第 7 节汇总表中既有「机器已验」行均补上实测值，并给出 evidence 相对路径（形如 `docs/evidence/wi_intake_9dc4d2c5af703568/<file>`）；状态列仍只允许「机器已验：<真实测试名>」与 `pending: 待人现场` 两种写法。
- ac-guide-human-rows-pending: 手册三条人耳结论（音乐不被打断 / 不切歌 / 播完音量恢复）状态保持 `pending: 待人现场`，未被改写为机器已验。
- ac-guide-android-real-artifact: 手册 1.1 Android 获取节写入本次真实产物目录名（`<versionName>-<versionCode>` 实值）与 sha256 实值，并附校验命令；不含任何版本字面值硬编码到构建配置的暗示。
- ac-guide-zero-release-claims: 对 `docs/distribution/manual-test-guide.md` 全文 grep「已发布」「已分发」「可下载」「已上架」「真机已验证」零命中，证据落 evidence。
- ac-gates-green: `bash scripts/check-baseline.sh`、`bash scripts/check-android.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/check-privacy-policy.sh` 四条命令实跑全绿，命令与结果入 evidence。
- ac-commit-split-no-side-effects: 提交按面拆分（产物/证据、手册定稿、prd/change-pack 分属不同提交，不混面）；`git diff` 不含 `VERSION`、不含 `.github/workflows/` 既有腿改动、不新增验证基建脚本、不动 `docs/verification-matrix.md` 行数口径；不推 tag、不改 main。

## 非目标

- 不扩功能面：不改 Swift/Kotlin 业务逻辑、不改 AudioSession 默认策略、不改 UI 与 design tokens。
- 不改 `VERSION` 数值（保持 `0.1.0`），不引入新的版本派生逻辑，不改 `android/app/build.gradle.kts` 的 `versionCode`。
- 不碰 ASC / TestFlight 凭据，不建 GitHub Release，不推 tag，不做真实分发动作。
- 不新增 CI 腿、不新增验证基建脚本、不改 `.munk/code-gates.json` 门定义、不重排 `docs/verification-matrix.md`。
- 不把模拟器读数写成「音乐不打断」，不把单元测试 fake 读数写成真机实测。
- 不生成 iOS `.ipa`、不生成 release 签名包、不产出任何「已可下载 / 已分发给用户」口径。

## 实现约束

**锚点（首次派发已点名，无需 Architect 重扫）**

- 出包入口：`scripts/package-android.sh`（既有，实跑优先不改；stdout 末行形如 `APK=` / `SHA256=` / `DIST_DIR=`）。
- 版本真源：根 `VERSION`（`0.1.0`）；`android/app/build.gradle.kts` 中 `versionName = repoVersion`、`versionCode = 1`（单点定义，本项只读不写）。
- 音频断言：
  - `ios/PurePaceTests/AudioSessionAdapterTests.swift`：`testApplyingDefaultConfigurationReadsBackFromRealSession`、`testEndAnnouncementRevokesDuckWhenActivationDucked`、`testEndAnnouncementSeparatesDeactivationFromDuckRevocation`、`testEndAnnouncementDeactivatesWithNotifyOthersExactlyOnce`。
  - `ios/RunCore/Tests/PurePaceRunCoreTests/AudioSessionCoordinatorTests.swift`：`testDefaultAnnouncementSettingsValues`、`testDeactivateCarriesNotifyOthersOption`。
  - 环境读数探针：`ios/PurePaceUITests/MusicSourceSelfCheckUITests.swift` 的 `testRunnerPlaysAndNoneIsSilent` / `testDefaultStrategyAndBundleDeclarations` 与 `ios/PurePaceUITests/MusicSource.swift` 的 `OtherAudioSnapshot`（`isOtherAudioPlaying` 运行进程快照）。
- 手册落点：`docs/distribution/manual-test-guide.md` 第 1.1 节、第 3 节机器层事实表、第 7 节汇总表。
- 建议运行命令（按现状脚本口径）：
  - `xcodebuild test -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:PurePaceTests/AudioSessionAdapterTests`
  - `swift test --package-path ios/RunCore --filter AudioSessionCoordinatorTests`
  - `xcodebuild test -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:PurePaceUITests/MusicSourceSelfCheckUITests`
- evidence 目录：`docs/evidence/wi_intake_9dc4d2c5af703568/`，至少含 `README.md`（每个数字 + 测试名/命令/commit/日志路径）、`android-package.log`、`android-checksums.txt`、`android-manifest.json`、`android-checksums-verify.log`、`audio-duck-adapter.log`、`audio-duck-runcore.log`、`audio-env-readings.log`、`guide-zero-release-claims.log`、`gates.log`。
- 绑定 commit：`2873ae21ee05c890980be28a63dda1d7da573bcf`；`manifest.json.commit` 必须等于该全 sha。
- 若环境缺失（无 JDK 21 / 无 Android SDK / 模拟器不可用）导致任一腿无法实跑：立刻把红因与卡点写进回执并停手，不得用「跳过该腿」凑绿，不得伪造读数。
