# Domain: distribution-manual-guide

## 范围

- 承载随包交付的简体中文人工测试说明 `docs/distribution/manual-test-guide.md`：拿到安装包的人在无人陪同下独立跑完一轮并按固定格式回报。
- 六块必备内容：①安装与获取（Android 出包产物 + sha256 + `adb install -r`；iOS 走 TestFlight 内部测试路径）②核心一轮路径（七步，仅 iOS）③音频三条人耳结论 ④iOS 同意门 ⑤Android 同意门 ⑥回报格式 + 汇总表。
- 状态口径双值制：只允许 `机器已验：<真实测试名>` 与 `pending: 待人现场`；机器已验引用的测试名必须在仓库测试源码（`ios/PurePaceTests`、`ios/PurePaceUITests`、`ios/RunCore/Tests`、`android/app/src/test`）真实存在。
- 顺带口径：`docs/release/stage4-prereqs.md` 六项前置表第 4 行（隐私政策 URL）为 `ready`，与文末结论句同口径；`README.md`「跑步链路验收自动化」段「用途 / 入口」表新增一行指向本说明，不新开 `##` 段。
- 纯文档域：不改产品代码、脚本、CI workflow 与 `docs/verification-matrix.md`（本项不新增验证接缝）；真机与音频项永远 `pending: 待人现场`。
- 定稿口径：手册里「机器已验」行与 Android 获取节必须写实测值（产物目录名 / sha256 / 音频三字段读数）+ 证据相对路径，取证落 `docs/evidence/<workItemId>/`；实测值只抄产物与日志，不由人推断。

## 验收

- ac-guide-file-and-sections：`docs/distribution/manual-test-guide.md` 存在、非空、简体中文，六块内容（安装与获取 / 核心一轮路径 / 音频 / 同意门（iOS）/ 同意门（Android）/ 回报格式 + 汇总表）齐全，缺任一判红。
- ac-no-version-literal：说明全文不出现根 `VERSION` 的字面值（`grep -F -- "$(bash scripts/version.sh)"` 零命中）；版本只以 `VERSION` 与 `<versionName>-<versionCode>` 占位符出现。
- ac-no-false-release-claims：全文不含「已发布 / 已分发 / 可下载 / 已上架 / 真机已验证」；iOS 段必须出现「凭据就位后由分发任务执行，人安装以 TestFlight 实际可见为准」原句。
- ac-android-install：Android 段引用 `docs/distribution/android.md`，逐字给出产物目录 `${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/`、三类产物（APK / `manifest.json` / `checksums.txt`）、`shasum -a 256 -c checksums.txt`（含 `sha256sum -c` 回退）与 `adb install -r`。
- ac-ios-testflight-entry：iOS 段引用 `docs/release/testflight-runbook.md`，说明本仓不出本地 IPA、构建凭据就位后由分发任务上传，人安装以 TestFlight 实际可见为唯一判据。
- ac-core-path-steps：七步按序且每步写明「点哪里 / 看什么 / 期望结果」：开跑、后台或锁屏续记、每公里播报、暂停/继续、结束保存、详情轨迹与分段、GPX 导出/分享；同段明示仅适用于 iOS，Android 当前只有同意门与占位主界面、核心链路不适用。
- ac-audio-three-clauses：音频节逐字含「音乐不被打断」「不切歌」「播完音量恢复」，三条状态只能是 `pending: 待人现场`；含免责句「模拟器无外部音源时读数只作环境事实，不能据此判音乐不打断」，并写明人现场需放 `com.apple.Music`。
- ac-audio-machine-rows-honest：音频节机器层读数只标「机器已验：<真实测试名>」，不得把三条人耳结论任一标成机器已验，且所列测试名在仓库测试源码中真实存在。
- ac-consent-ios：iOS 同意门五条（首启独立同意屏 / 不同意被拦并给原因 / 同意后可开跑 / 关于页可读随包政策全文 / 可撤回并回到未同意含冷启动持久化）；政策链接 `https://munk.sh/privacy`（含 PurePace 专项小节）。
- ac-consent-android：Android 同意门同样五条 + 同一政策链接；不得声称 Android 已完成核心跑步链路。
- ac-report-format：每条给「通过」或「缺陷（现象 + 复现步骤 + 期望）」；附设备型号 / 系统版本 / 音频来源（Apple Music 曲名或「无外部音源」）；隐私相关不要求上传轨迹文件。
- ac-summary-table：汇总表一行一项、三列「项 / 说明 / 状态」；状态单元格只允许「机器已验：<测试名>」或 `pending: 待人现场`；「真机已验证」零命中；纯人工项（真实锁屏/后台续记、播报听感、音乐三条、真机同意门观感）一律 `pending: 待人现场`。
- ac-stage4-row4：`docs/release/stage4-prereqs.md` 第 4 行为 `ready`：`https://munk.sh/privacy` 已上线并含 PurePace 专项小节、ASC App 信息直接填该 URL、人无需操作；文末结论句与表格同口径（仅第 4 行 `ready`，其余五项 `pending: 人`，无 `blocked: PLA`），同文档无自相矛盾。
- ac-readme-index-row：`README.md`「用途 / 入口」表新增一行指向本说明（相对链接可点），`grep -c '^## ' README.md` 前后不变，README 内不出现版本字面值。
- ac-guide-measured-rows-with-evidence：第 3 节机器层事实表与第 7 节汇总表的既有「机器已验」行均写出实测值，并附 `docs/evidence/<workItemId>/<file>` 形态的证据相对路径；状态列仍只允许「机器已验：<真实测试名>」与 `pending: 待人现场`。
- ac-guide-android-measured-artifact：1.1 节写明本次真实产物目录名（`<versionName>-<versionCode>` 实值）、APK 仓外绝对路径、sha256 实值，以及 `shasum -a 256 -c checksums.txt` 的自校验命令与 `OK` 输出；同段注明该表只是实测抄录，版本仍由根 `VERSION` 与 `android/app/build.gradle.kts` 单点派生。
- ac-guide-audio-measured-readings：音频节机器层行补实测读数——播报期真实 `AVAudioSession` 读回 `categoryOptions` 含 `duckOthers`、播报结束 `sessionDeactivated=true` / `duckRevoked=true`、激活未带 `duckOthers` 时 `sessionDeactivated=true` 且 `duckRevoked=false`（两字段非别名）、`isOtherAudioPlaying=false` / `secondaryAudioShouldBeSilencedHint=false`；同段保留「模拟器无外部音源时读数只作环境事实」免责句。
- ac-evidence-pack-traceable：每次定稿在 `docs/evidence/<workItemId>/` 留 `README.md` + 打包日志 / 产物清单与校验、音频两腿日志、环境读数、手册零发布口径自检、门禁日志；每个数字都能在同目录文件找到对应行，绑定 commit 全 sha，目录内不含 `.ipa` 与任何上传 / 分发 / 上架口径。
- ac-static-gates-green：`bash scripts/check-baseline.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/check-privacy-policy.sh` 均退出 0；不接受删断言、放宽断言或 `|| true` 绕过。

## 非目标

- 不改任何产品代码（iOS / Android / shared），不改 `VERSION`、`CHANGELOG.md`、`docs/verification-matrix.md`。
- 不改 `docs/distribution/android.md`、`docs/release/testflight-runbook.md`、`docs/device-manual-acceptance.md`、`docs/privacy/privacy-policy-zh-Hans.md` 与包内政策副本；只引用。
- 不新增/修改脚本、CI workflow、code-gates 条目；不生成安装包、不上传 TestFlight、不碰凭据。
- 不声明未经实测为绿的东西：不写「真机已验证」，不把模拟器读数当音乐不打断证据，不把 Android 占位记录态描述成完整跑步链路。
- 不产 iOS `.ipa`（构建凭据未就位）、不产 release 签名包、不做真实分发；Android 产物只落仓外临时目录，装机由人执行。
- 不做 drive-by 文案润色或文档结构重构；除本说明 + stage4 第 4 行 + README 一行外不落其它改动。

## 实现约束

- 文件落点：新增 `docs/distribution/manual-test-guide.md`；改 `docs/release/stage4-prereqs.md` 第 4 行及相关结论句；改 `README.md` 既有「用途 / 入口」表加一行。
- 版本口径：Android 产物目录与 APK 文件名只写 `<versionName>-<versionCode>` 占位符，任何地方不写 `VERSION` 字面值。
- README 边界：「当前状态」段与版本表首行由 `check-baseline.sh` 严格断言，动 README 时不碰这两处。
- 状态词表：全文只用「机器已验：<测试名>」与 `pending: 待人现场`；禁「真机已验证 / 已发布 / 已分发 / 可下载 / 已上架」。
- 机器已验名单来自权威腿实际执行项：`testRunPauseResumeFinishAndHistory`、`testRunProducesTelemetryAcrossKilometerBoundary`、`testStartFinishExportGPXArtifact`、`testLockRunningContinuesWithMonotonicSamples`、`testEachKilometerAnnouncedExactlyOnceInOrder`、`testEndAnnouncementRevokesDuckWhenActivationDucked`、`testDefaultStrategyAndBundleDeclarations`、`testRunnerPlaysAndNoneIsSilent`、`testTrajectoryConsentGateThreeStates`、`firstLaunchShowsConsentGateAsRoot`、`unattendedStartAttemptStaysBlockedWithReason`、`agreeGrantsAndEnablesStart`、`declineStaysUnattended`、`withdrawReturnsUnattended`。
- 音频节写法：机器读数只落「音源与环境声明 / 播报调度去重 / duck 撤销配置 / 播放探针」四类环境事实，并紧邻免责句；三条人耳结论固定 `pending: 待人现场`。
- 隐私链接事实：`https://munk.sh/privacy` 实取 200（跳转 `https://www.munk.sh/privacy`），含 PurePace 专项小节。
- 证据绑定口径：读数绑定对象写「commit 全 sha + 测试宿主产物」，不写分发渠道；`manifest.json.commit` 必须等于手册引用 commit；目录内每个数字配「测试名 / 命令 / commit / 日志路径」四元定位，禁止手写转写未在日志出现的数值。
- 定稿只读不写：`scripts/package-android.sh`、`android/app/build.gradle.kts`、`.munk/code-gates.json` 与音频测试源码均只读取与实跑，不修改门定义、不新增验证基建脚本。

## 最近交付证明

- workItemId: wi_intake_9dc4d2c5af703568 / at: 2026-11-15T04:20:00+08:00 / status: pass
- 交付：手册按实测定稿——1.1 节写入本次真实产物目录名 `0.1.0-1`、APK 仓外绝对路径、sha256 `8b80c8e2…` 与 `shasum -a 256 -c checksums.txt` 自校验 `OK`；第 3 节机器层事实表由 4 行扩到 8 行（补真实 `AVAudioSession` 读回 `duckOthers`、`duckRevoked=true`、两字段分离、RunCore 默认配置/停用选项、`isOtherAudioPlaying=false`/`secondaryAudioShouldBeSilencedHint=false`）；第 7 节汇总表对应行同步补读数与证据路径；三条人耳结论仍 `pending: 待人现场`。
- 证据：`docs/evidence/wi_intake_9dc4d2c5af703568/` 十件套（README + android-package/checksums/manifest/verify + audio-duck-adapter/runcore + audio-env-readings/telemetry + guide-zero-release-claims + gates），绑定 commit `2873ae21ee05c890980be28a63dda1d7da573bcf`；手册零发布口径 grep 零命中。
- 验证：`code_gates` 23 门全绿（attempt 001，含 build/test/package-android、check-shared、check-baseline）。
- 偏离与未做：iOS `.ipa` 未产出（凭据未就位，人闸未判定），未上传 TestFlight、未推 tag、未建 Release；未改产品代码 / `VERSION` / UI / design tokens / `.github/workflows/` / `.munk/code-gates.json`；装机与真机听感仍待人现场。
