# 随包交付的人工测试说明（manual-test-guide）

## 范围

新增一份随包交付的简体中文人工测试说明 `docs/distribution/manual-test-guide.md`，让拿到包的人在无人陪同的情况下独立跑完一轮并按要求回报；状态口径必须诚实，逐项区分「机器已验：<真实测试名>」与 `pending: 待人现场`。

说明需覆盖六块内容：

1. **安装与获取**
   - Android：走 `docs/distribution/android.md` 的出包脚本与产物目录 `${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/`（APK + `manifest.json` + `checksums.txt`），给 `shasum -a 256 -c checksums.txt`（Linux 回退 `sha256sum -c`）与 `adb install -r` 步骤；版本号只以占位符 `<versionName>-<versionCode>` 出现，不写版本字面值。
   - iOS：走 `docs/release/testflight-runbook.md` 的 TestFlight 内部测试路径；上传状态写「凭据就位后由分发任务执行，人安装以 TestFlight 实际可见为准」，不得写「已发布 / 已分发 / 可下载」。
2. **核心一轮路径**（每步写清「点哪里 / 看什么 / 期望结果」）：开跑 → 后台或锁屏继续记轨迹（距离、配速仍在走）→ 每公里语音播报 → 暂停/继续 → 结束保存 → 详情页看轨迹与分段 → GPX 导出/分享。仓库事实：iOS 具备完整跑步链路；Android 端目前只有独立同意门与占位主界面（`android/app/src/main/java/dev/purepace/PurePaceApp.kt` 的 `HomeScreen` 仅一个占位记录态文案，无定位、无语音、无 GPX），因此核心一轮路径明确限定为 iOS，并写清 Android 当前不适用，不得让人去 Android 上找不存在的功能。
3. **音频项**（单列一节，含任务给定的三条原文口径）：每公里播报时音乐**不被打断 / 不切歌**、播完**音量恢复**。
4. **同意门**（iOS 与 Android 各一节）：首启出现同意屏、不同意则开跑被拦并给原因、同意后可开跑、关于页可读政策全文、可撤回且撤回后回到未同意；政策链接统一写 `https://munk.sh/privacy`（含 PurePace 专项小节）。
5. **回报格式**：每条给「通过 / 缺陷（现象 + 复现步骤 + 期望）」；附设备型号、系统版本、音频来源（Apple Music 曲名或「无外部音源」）；隐私相关不要求人上传轨迹文件。
6. **汇总表**：一行一项，列「项 / 说明 / 状态」；状态只允许两种写法。

另做两处顺带修改：

- `docs/release/stage4-prereqs.md` 六项前置表第 4 行（隐私政策 URL 行）改为：`https://munk.sh/privacy` 已上线并含 PurePace 专项小节，ASC App 信息直接填该 URL，人无需操作。
- `README.md` 文档索引加一行指向本说明；并入既有段（`## 跑步链路验收自动化` 的「用途 / 入口」表，与「真机手测」行同段），不新开 `##` 段。

本项不新增验证接缝，`docs/verification-matrix.md` 的任何行都不改。

## 验收

状态口径与语义断言（Coding 需转成 `code_gates` 里的静态断言；均为可 grep / 可执行的确定性判据）：

- ac-guide-file-and-sections: `docs/distribution/manual-test-guide.md` 存在、非空、简体中文，且含六块内容对应的标题/段落：安装与获取、核心一轮路径、音频、同意门（iOS）、同意门（Android）、回报格式，以及汇总表；六块齐全，缺任一判红。
- ac-no-version-literal: 说明全文不出现根 `VERSION` 的字面值（断言方式：`grep -F -- "$(bash scripts/version.sh)" docs/distribution/manual-test-guide.md` 零命中）；版本只以 `VERSION` 与 `<versionName>-<versionCode>` 占位符出现。
- ac-no-false-release-claims: 说明全文不含「已发布 / 已分发 / 可下载 / 已上架 / 真机已验证」这几个肯定式或虚假结论；iOS 段必须出现「凭据就位后由分发任务执行，人安装以 TestFlight 实际可见为准」原句。
- ac-android-install: 说明的 Android 段必须引用 `docs/distribution/android.md`，逐字给出产物目录 `${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/`、三类产物名（APK、`manifest.json`、`checksums.txt`）、`shasum -a 256 -c checksums.txt`（含 `sha256sum -c` 回退）与 `adb install -r` 步骤。
- ac-ios-testflight-entry: 说明的 iOS 段必须引用 `docs/release/testflight-runbook.md`，说明本仓不出本地 IPA、构建由分发任务在凭据就位后上传 TestFlight，并以 TestFlight 实际可见作为人安装的唯一判据。
- ac-core-path-steps: 核心一轮路径按七步顺序给出且每步都写明「点哪里 / 看什么 / 期望结果」：开跑、后台或锁屏继续记轨迹、每公里语音播报、暂停/继续、结束保存、详情页轨迹与分段、GPX 导出/分享；同段必须明示该路径适用于 iOS，Android 端当前只有同意门与占位主界面、核心跑步链路不适用（不得把不可执行的步骤派给 Android）。
- ac-audio-three-clauses: 音频节逐字包含三条口径「音乐不被打断」「不切歌」「播完音量恢复」，且这三条的状态只能写 `pending: 待人现场`；必须写入免责句「模拟器无外部音源时读数只作环境事实，不能据此判音乐不打断」，并写明人现场需放 `com.apple.Music` 才算成立。
- ac-audio-machine-rows-honest: 音频节的机器层读数只允许标「机器已验：<真实测试名>」，且不得把「音乐不打断 / 不切歌 / 播完音量恢复」任何一条标成机器已验；「机器已验」引用的测试名必须在仓库测试源码中真实存在（断言方式：每个名字能在 `ios/PurePaceTests`、`ios/PurePaceUITests`、`ios/RunCore/Tests` 或 `android/app/src/test` 的 `func test`/`fun ` 定义中命中）。
- ac-consent-ios: iOS 同意门节覆盖五条：首启出现独立同意屏；点「不同意」后开跑入口被拦并显示原因；同意后可开跑；设置页「关于」可读随包政策全文；可撤回且撤回后回到未同意（含杀进程重启后的状态持久化）；政策链接写 `https://munk.sh/privacy`（含 PurePace 专项小节）。
- ac-consent-android: Android 同意门节覆盖同样五条（首启同意屏、不同意被拦+原因、同意后可开跑、关于页政策全文、可撤回并回到未同意）；政策链接写 `https://munk.sh/privacy`（含 PurePace 专项小节）；不得声称 Android 已完成核心跑步链路。
- ac-report-format: 回报格式节要求每条给「通过」或「缺陷（现象 + 复现步骤 + 期望）」，并要求附设备型号、系统版本、音频来源（Apple Music 曲名或「无外部音源」）；明确隐私相关不要求人上传轨迹文件。
- ac-summary-table: 汇总表为一行一项、三列「项 / 说明 / 状态」；每个状态单元格只允许「机器已验：<测试名>」或 `pending: 待人现场` 两种形式；全表「真机已验证」零命中；每个「机器已验：」后面的测试名真实存在（同 ac-audio-machine-rows-honest 的断言方式）；纯人工项（真实锁屏/后台续记、每公里播报是否听清、音乐不打断/不切歌/音量恢复、真机同意门观感）一律 `pending: 待人现场`。
- ac-stage4-row4: `docs/release/stage4-prereqs.md` 六项前置表第 4 行（隐私政策 URL）写明 `https://munk.sh/privacy` 已上线并含 PurePace 专项小节、ASC App 信息直接填该 URL、人无需操作；该行状态不再写 `pending: 人`；同时修正文末「本次没有 `ready` 项」一类与新状态互斥的表述，保证同一文档内无自相矛盾。
- ac-readme-index-row: `README.md` 的「用途 / 入口」表新增一行指向 `docs/distribution/manual-test-guide.md`（相对链接可点），且不新开 `##` 标题（`grep -c '^## ' README.md` 前后不变），README 内不出现版本字面值。
- ac-static-gates-green: 改动后 `bash scripts/check-baseline.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/check-privacy-policy.sh` 均退出 0；不接受删断言、放宽断言或 `|| true` 绕过。

## 非目标

- 不改任何产品代码（iOS / Android / shared 均不改），不改 `VERSION`、`CHANGELOG.md`、`docs/verification-matrix.md`（本项不新增接缝）。
- 不改 `docs/distribution/android.md`、`docs/release/testflight-runbook.md`、`docs/device-manual-acceptance.md`、`docs/privacy/privacy-policy-zh-Hans.md`（政策真源）与包内政策副本；只引用它们。
- 不新增/修改脚本、CI workflow、code-gates 条目；不生成安装包、不上传 TestFlight、不碰任何凭据。
- 不声明任何未经实测为绿的东西：不写「真机已验证」，不把模拟器读数当音乐不打断的证据，不把 Android 占位记录态描述成完整跑步链路。
- 不做 drive-by 文案润色或文档结构重构；不顺带改其它段落。

## 实现约束

- 文件落点：新增 `docs/distribution/manual-test-guide.md`；改 `docs/release/stage4-prereqs.md` 第 4 行（及相关结论句）；改 `README.md` 既有「用途 / 入口」表加一行。除这三个文件外不落其它改动。
- 版本口径：Android 产物目录与 APK 文件名只写 `<versionName>-<versionCode>` 占位符；任何地方不写 `VERSION` 的字面值。
- README 现状（已核对）：`## 跑步链路验收自动化` 段的「用途 / 入口」表已有「真机手测」行指向 `docs/device-manual-acceptance.md`；新行并入该表即可，不新开段。README「当前状态」段与版本表首行由 `check-baseline.sh` 严格断言，动 README 时不要碰这两处。
- 已核对的真实测试名（供「机器已验」行选用，均在仓库内、且在被权威腿执行）：
  - iOS 跑步链路（模拟器 UI 腿 `RunFlowUITests`）：`testRunPauseResumeFinishAndHistory`（开跑 / 暂停继续 / 结束保存 / 历史 / 详情分段行数）、`testRunProducesTelemetryAcrossKilometerBoundary`（跨 1 km、遥测含 `duckOthers=true` 与「第 1 公里」）、`testStartFinishExportGPXArtifact`（详情 → 导出 GPX → 系统分享面板 → 回详情）。
  - 锁屏续记（模拟器注入 protected-data 与 fake 采样源，非真实锁屏）：`testLockRunningContinuesWithMonotonicSamples`（`ios/PurePaceTests/RunSessionLockTests.swift`）。
  - 每公里播报调度：`testEachKilometerAnnouncedExactlyOnceInOrder`（`ios/RunCore/Tests/PurePaceRunCoreTests/AnnouncementSchedulerTests.swift`）。
  - duck 会话：`testEndAnnouncementRevokesDuckWhenActivationDucked`（`ios/PurePaceTests/AudioSessionAdapterTests.swift`）。
  - 音源环境事实（模拟器可跑，明确 `simulatorNotApplicable`，只作环境事实）：`testDefaultStrategyAndBundleDeclarations`、`testRunnerPlaysAndNoneIsSilent`（`ios/PurePaceUITests/MusicSourceSelfCheckUITests.swift`，已进 `scripts/test-ios.sh` 的 `ui_call`）。
  - iOS 同意门：`testTrajectoryConsentGateThreeStates`（`ios/PurePaceUITests/RunFlowUITests.swift`，覆盖未同意拦截+原因、同意后启用、关于页政策全文、撤回后回未同意、冷启动持久化）。
  - Android 同意门（Robolectric/Compose，本地 JVM 腿）：`firstLaunchShowsConsentGateAsRoot`、`unattendedStartAttemptStaysBlockedWithReason`、`agreeGrantsAndEnablesStart`、`declineStaysUnattended`、`withdrawReturnsUnattended`（`android/app/src/test/java/dev/purepace/ConsentGateScreenTest.kt`）。
- 音频节写法：机器读数只允许落在「音源与环境声明 / 播报调度去重 / duck 撤销配置」这几类环境事实上，并紧邻免责句；三条人耳结论固定 `pending: 待人现场`。
- 隐私链接事实：`https://munk.sh/privacy` 本次实取为 200（跳转 `https://www.munk.sh/privacy`），页面含 PurePace 专项小节；stage4 第 4 行按任务给定原句写入。隐私政策真源已在行内写同一链接（含 PurePace 专项小节），不要改真源。
- 状态词表：全文只用「机器已验：<测试名>」与 `pending: 待人现场` 两种状态写法；禁「真机已验证 / 已发布 / 已分发 / 可下载」。
- 预算：纯文档改动，≤8M token / ≤90 分钟；`check-baseline.sh` 变更前实测 29 项断言全绿（VERSION=0.1.0），改动后必须复跑保持绿。
