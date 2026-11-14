# PurePace 随包人工测试说明

本说明供拿到安装包的人无人陪同地独立跑完一轮，并按第 6 节格式回报。全文只用两种状态写法：
「机器已验」后接真实测试名，与 `pending: 待人现场`。凡本说明未标机器已验的项，一律以人现场实测为准；
本说明不声明任何未经实测的发布、分发或可获取结论。

## 1. 安装与获取

版本号只以占位符 `<versionName>-<versionCode>` 出现，实际值由根 `VERSION` 与构建配置派生，请以产物目录与
`manifest.json` 的实际值为准。

### 1.1 Android（出包产物目录 + sha256 校验 + adb install -r）

出包脚本、产物结构与同意门的完整说明见 [`docs/distribution/android.md`](./android.md)，此处只给安装三步：

1. 在仓库根出包（需要 JDK 21 与 Android SDK 36）：
   ```bash
   bash scripts/package-android.sh
   ```
   产物目录（仓外）：
   ```text
   ${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/
   ├── purepace-<versionName>-<versionCode>-debug.apk
   ├── manifest.json
   └── checksums.txt
   ```
   三类产物缺一不可：APK、`manifest.json`（applicationId / version / versionCode / commit / sha256 /
   minSdk / targetSdk / buildTime）、`checksums.txt`。
2. 校验 sha256：
   ```bash
   DIST="${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>"
   cd "$DIST"
   shasum -a 256 -c checksums.txt
   # Linux 回退
   sha256sum -c checksums.txt
   ```
   期望结果：每个文件一行 `OK`；任一 `FAILED` 即停止，不要安装。
3. 安装（覆盖同签名旧包）：
   ```bash
   DIST="${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>"
   adb install -r "$DIST/purepace-<versionName>-<versionCode>-debug.apk"
   ```
   期望结果：终端最后一行 `Success`。装机后的首启核对见第 5 节（Android 同意门）。

### 1.2 iOS（TestFlight 内部测试路径）

分发链路、凭据边界与证据归档见 [`docs/release/testflight-runbook.md`](../release/testflight-runbook.md)。
本仓不出本地 IPA 给人侧装：构建（归档与导出）、上传 App Store Connect 与内部测试者分配均由仓库脚本完成，
凭据就位后由分发任务执行，人安装以 TestFlight 实际可见为准。

1. 在 iPhone 上打开 TestFlight，确认 PurePace 的内部测试构建实际可见、可点「安装」。
2. 若列表暂不可见：说明分发任务尚未完成或构建仍在处理，稍后重试；不要改用其它来源的安装包。
3. 装机后首次启动即进入第 4 节的同意门流程。

## 2. 核心一轮路径（仅 iOS）

iOS 具备完整跑步链路（开跑、后台/锁屏续记、每公里播报、暂停继续、结束保存、详情轨迹与分段、GPX 导出分享）。
Android 端当前只有独立同意门与占位主界面，没有定位、语音与 GPX 能力，**核心跑步链路对 Android 不适用**，
请勿在 Android 上查找下列功能；Android 只需按第 5 节核对同意门。

按顺序做以下七步，每步都给出了「点哪里 / 看什么 / 期望结果」。建议先在开阔处等定位就绪再开跑。

| 步骤 | 点哪里 | 看什么 | 期望结果 |
|---|---|---|---|
| 1 开跑 | 底部「跑步」Tab → 主按钮「开始记录跑次」 | 距离、时长、当前配速、平均配速随时间变化 | 进入运行态，主按钮变为「暂停」；距离从 `0.00 km` 起增，时长从 `00:00` 起走 |
| 2 后台或锁屏继续记轨迹 | 运行中按电源键锁屏（或回到主屏幕、切到其它 App），保持 ≥1 分钟，再回到 PurePace | 回到 App 后的距离、时长是否包含锁屏期间 | 距离与时长继续增长、不回退不归零，当前配速恢复显示真实值 |
| 3 每公里语音播报 | 保持运行，跑到 ≥1 公里 | 听扬声器播报 | 播报「第 1 公里」及该公里用时/配速；同一公里只播一次、不重复、不乱序 |
| 4 暂停/继续 | 运行中「暂停」，停留 ≥10 秒后点「继续」 | 暂停期间与恢复后的读数 | 暂停期间距离、时长不再增长，当前配速显示 `--`；点「继续」后读数恢复增长 |
| 5 结束保存 | 点「结束」→ 结束待保存态点「保存」 | 保存反馈与返回后的页面 | 出现「已保存」反馈，回到未开始态（主按钮为「开始记录跑次」），结束按钮消失 |
| 6 详情页轨迹与分段 | 底部「历史」Tab → 点本次记录行 | 详情页的开始/结束时间、总距离、活跃时长、平均配速、轨迹、分段区 | 详情读数与该历史行一致；轨迹有折线；分段行数与摘要条数相等，无分段时显示诚实空态 |
| 7 GPX 导出/分享 | 详情页点「导出 GPX」→ 系统分享面板，选一个目标或关闭面板 | 导出完成态与分享入口 | 出现「已导出」与分享入口，不出现失败态；关闭分享面板后回到详情页 |

说明：第 2 步的「进程内续记」有机器覆盖（见第 7 节），但真实锁屏、系统内存回收与定位授权的组合只能人现场确认，
因此第 2 步的真实锁屏行为仍按第 7 节标 `pending: 待人现场`。

## 3. 音频（每公里播报与音乐）

三条人耳结论，全部只能由人现场播放音乐后判断：

- 音乐不被打断：每公里播报期间，Apple Music 正在播放的歌曲继续播放，没有停播。状态：`pending: 待人现场`
- 不切歌：播报前后仍是同一首歌，没有跳到下一首或其它曲目。状态：`pending: 待人现场`
- 播完音量恢复：播报结束后，音乐音量回到播报前的水平，没有被长期压低。状态：`pending: 待人现场`

以上三条在本说明中一律记 `pending: 待人现场`。人现场需放 `com.apple.Music` 才算成立：测试前先用 Apple Music
播放一首歌并确认正在出声，再开始跑步；未播放任何外部音源时，本项不成立、不要判为通过。

人现场的判定口径：模拟器无外部音源时读数只作环境事实，不能据此判音乐不打断。

机器层读数只覆盖环境事实，不覆盖上面三条人耳结论：

| 机器层事实 | 说明 | 状态 |
|---|---|---|
| 播报调度去重与顺序 | 纯逻辑调度器：每公里恰好播报一次且按公里序 | 机器已验：testEachKilometerAnnouncedExactlyOnceInOrder |
| duck 会话撤销配置 | 播报结束后撤销 ducking 的会话动作 | 机器已验：testEndAnnouncementRevokesDuckWhenActivationDucked |
| 音源与环境声明 | 模拟器上明确 `simulatorNotApplicable`，只作为环境事实 | 机器已验：testDefaultStrategyAndBundleDeclarations |
| 播报期间外部音源播放探针 | 模拟器上仅验证播放动作，不构成音乐不被打断的证据 | 机器已验：testRunnerPlaysAndNoneIsSilent |

## 4. 同意门（iOS）

政策链接统一为 https://munk.sh/privacy（含 PurePace 专项小节）。请逐条核对：

1. 首启独立同意屏：干净安装后首次启动，根视图是独立同意屏（不是跑步页上的弹层），正文说明轨迹与位置数据属于
   敏感个人信息、只存在本机、可以拒绝、可随时撤回。
2. 不同意被拦并给原因：点「不同意」（或未同意时点开跑入口），不进入记录态，并出现「未同意轨迹与位置数据授权，
   暂不能开始记录。」一类原因文案。
3. 同意后可开跑：点「同意」后进入主界面，开跑入口可点击并能正常开始。
4. 关于页可读政策全文：从设置页进入「关于」，随包政策全文由 App 内资源渲染（不联网），正文与
   `docs/privacy/privacy-policy-zh-Hans.md` 一致，并含指向 https://munk.sh/privacy（含 PurePace 专项小节）的说明。
5. 可撤回且回到未同意：在关于页点撤回并确认，回到未同意态，开跑入口再次被拦并显示原因；杀进程重启后仍为未同意；
   同样地，同意后杀进程重启仍应为已同意。

## 5. 同意门（Android）

政策链接统一为 https://munk.sh/privacy（含 PurePace 专项小节）。Android 当前只有独立同意门与占位主界面，
**没有核心跑步链路**（无定位、无语音播报、无 GPX），因此本节只核对同意门，不要求也无法测试跑步功能。
逐条核对顺序与 `docs/distribution/android.md` 第 4 节一致：

1. 首启独立同意屏：干净安装后首次启动，根视图是独立同意屏；正文含「敏感个人信息」「只存在本机」「可以拒绝」
   「可随时撤回」四条。
2. 不同意被拦并给原因：此时点「开始记录」不进入记录态，并出现来自资源的原因文案。
3. 同意后可开跑：点主按钮「同意」后进入主界面，开跑入口可点击；杀进程重启后仍为已同意。
4. 关于页可读政策全文：从主界面进入「关于」，政策全文由随包资源渲染（不联网），正文与
   `docs/privacy/privacy-policy-zh-Hans.md` 一致，完整隐私政策见 https://munk.sh/privacy（含 PurePace 专项小节）。
5. 可撤回且回到未同意：在关于页点「撤回同意」并确认，回到未同意态，开跑入口再次不可用并出现原因；
   杀进程重启后仍为未同意。

主界面上的记录态只是占位文案，看到它进入记录态不等于跑步链路可用。

## 6. 回报格式

每条项按下述格式回报，一条一段：

- 通过：`<项名>：通过`
- 缺陷：`<项名>：缺陷 | 现象：<看到/听到什么> | 复现步骤：<1. … 2. … 3. …> | 期望：<应该是什么>`

每条缺陷必须能按复现步骤重放；只有现象没有复现步骤的条目，按未完成处理。

除逐条结论外，回报开头附三项环境信息：

- 设备型号（例：iPhone 16 Pro / Pixel 8）
- 系统版本（例：iOS 18.6 / Android 15）
- 音频来源：Apple Music 曲名，或明确写「无外部音源」

隐私相关项不要求人上传轨迹文件（`.gpx` / `.tcx`）或截图里的精确位置；描述现象即可，不要附轨迹文件。

## 7. 汇总表

一行一项，状态列只允许两种写法：「机器已验」+ 冒号 + 真实测试名，与 `pending: 待人现场`。

| 项 | 说明 | 状态 |
|---|---|---|
| Android 出包、sha256 校验与安装 | 产物目录与 `checksums.txt` 见 `docs/distribution/android.md`；实际装机由人执行 | pending: 待人现场 |
| iOS TestFlight 内部安装 | 凭据就位后由分发任务执行，人安装以 TestFlight 实际可见为准 | pending: 待人现场 |
| 开跑 / 暂停 / 继续 / 结束保存 / 历史 / 详情分段行数（iOS 模拟器） | 跑步链路 UI 腿 | 机器已验：testRunPauseResumeFinishAndHistory |
| 跨 1 公里遥测与「第 1 公里」播报文案（iOS 模拟器） | 遥测含 `duckOthers=true` | 机器已验：testRunProducesTelemetryAcrossKilometerBoundary |
| 详情 → 导出 GPX → 系统分享面板 → 回详情（iOS 模拟器） | 导出产物由 `scripts/verify-ios-ui-e2e.sh` 断言 | 机器已验：testStartFinishExportGPXArtifact |
| 续记采样单调（进程内 protected-data + fake 采样源） | 非真实锁屏 | 机器已验：testLockRunningContinuesWithMonotonicSamples |
| 每公里播报调度去重与顺序 | 纯逻辑 | 机器已验：testEachKilometerAnnouncedExactlyOnceInOrder |
| 播报结束撤销 duck 会话 | 会话动作层 | 机器已验：testEndAnnouncementRevokesDuckWhenActivationDucked |
| 音源与环境声明 | 模拟器 `simulatorNotApplicable`，只作环境事实 | 机器已验：testDefaultStrategyAndBundleDeclarations |
| 播报期间外部音源播放探针 | 模拟器环境事实，不构成音乐不打断证据 | 机器已验：testRunnerPlaysAndNoneIsSilent |
| iOS 同意门（未同意拦截 + 原因 / 同意 / 关于页政策全文 / 撤回 / 冷启动持久化） | 模拟器 UI 腿 | 机器已验：testTrajectoryConsentGateThreeStates |
| Android 首启同意屏为根视图 | 本地 JVM 腿 | 机器已验：firstLaunchShowsConsentGateAsRoot |
| Android 未同意点击开跑被拦并给原因 | 本地 JVM 腿 | 机器已验：unattendedStartAttemptStaysBlockedWithReason |
| Android 同意后开跑可用 | 本地 JVM 腿 | 机器已验：agreeGrantsAndEnablesStart |
| Android 未同意态保持 | 本地 JVM 腿 | 机器已验：declineStaysUnattended |
| Android 撤回后回到未同意 | 本地 JVM 腿 | 机器已验：withdrawReturnsUnattended |
| 真实锁屏 / 后台续记（真机） | 按电源键锁屏 ≥1 分钟后回 App 看读数 | pending: 待人现场 |
| 每公里播报是否听清、听感是否合适 | 人耳判断 | pending: 待人现场 |
| 音乐不被打断 | 人耳判断，需 Apple Music 正在播放 | pending: 待人现场 |
| 不切歌 | 人耳判断，需 Apple Music 正在播放 | pending: 待人现场 |
| 播完音量恢复 | 人耳判断，需 Apple Music 正在播放 | pending: 待人现场 |
| 真机同意门观感（iOS / Android） | 首启同意屏、拦截原因与关于页阅读体验 | pending: 待人现场 |
| 隐私链接可达性 | https://munk.sh/privacy（含 PurePace 专项小节） | pending: 待人现场 |

汇总表里凡标 `pending: 待人现场` 的项，按第 6 节回报通过或缺陷；标为机器已验的项由仓库自动化腿承载，
人工回报只需确认现场现象与所列测试名不矛盾。
