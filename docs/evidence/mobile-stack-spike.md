# PurePace 选型调研（只读 spike）

日期：2026-11-07 · 执行方式：Owner 本机只读调研（未写产品代码、未安装依赖、未发任何外部内容）
标注约定：每条结论带 `【本机实测】` / `【官方文档引用】` / `【未验证推断】`；推断项必须在真机 QA 阶段证伪。

---

## 0. 结论摘要

**推荐栈：iOS 原生 SwiftUI + CoreLocation/CoreMotion + AVAudioEngine/AVSpeechSynthesizer + AVFoundation(Camera) + SQLite（GRDB 或 raw sqlite3）。V1 只做 iOS，Android 放到 V1.1 再决策。**

三条决定性理由（按权重）：

1. 本产品的四个"硬骨头"（锁屏后台连续定位、duck 其它音频后播报、采样级低延迟节拍、摄像头条码）全部直接落在 Apple 原生框架上；走 RN 只是加了一层桥接，且**每一个都需要 dev build**（Expo Go 跑不了后台定位），Expo 的"免构建快速迭代"优势在本产品上几乎不存在。
2. 仓库目前是空仓（`git log` 只有 `chore: initial empty project`），没有存量代码需要复用，选型成本是单向的、越早定越省钱。
3. 无真机可用的现实约束下，原生方案的失败面更小：模拟器能验证的原生路径最多；RN 方案在模拟器上多一层"JS 桥 + 后台任务"的不可解释失败，排障成本更高。

若公司硬性要求 **V1 同时上 iOS + Android**：改选 Expo SDK 58 + dev build（expo-location / expo-audio / expo-speech / expo-camera / expo-sqlite），接受 §7 的三条风险，并把节拍器降级为"原生模块"（无法纯 JS 实现）。

---

## 1. iOS 后台边界

### 1.1 CoreLocation 后台更新 + 锁屏采样

- 需要 `UIBackgroundModes` 含 `location`，且 `CLLocationManager.allowsBackgroundLocationUpdates = true`，授权必须是「使用 App 期间 + 始终允许」（`Always`）。`【官方文档引用】` <https://developer.apple.com/documentation/corelocation/configuring-your-app-to-use-location-services> · <https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates>
- 锁屏本身**不中断**已开启的后台定位；锁屏后 UI 刷新停止，但更新回调继续（这也是跑步 App 的常规形态）。`【官方文档引用】`（同上，后台定位一节）+ `【未验证推断】`（锁屏 30 min 后系统的节流强度、9 小时长跑的电量曲线，必须真机测）
- 关键边界：**用户在任务切换器里上滑杀掉 App → 后台更新立即停止**，不会自动恢复；被系统因内存压力回收则是另一回事（signficant-change / region monitoring 可被系统重启，普通 continuous updates 不保证）。`【官方文档引用】` Apple 文档 + Expo 官方文档同款表述（"Background location will stop if the user terminates the app"）<https://docs.expo.dev/versions/latest/sdk/location/>
- 精度/频率：`desiredAccuracy`、`distanceFilter`、`pausesLocationUpdatesAutomatically`、`activityType = .fitness` 决定功耗与轨迹质量；默认 1 Hz + `kCLLocationAccuracyBest` 是跑步场景基线。`【未验证推断】`（具体参数需真机 + 真实跑步轨迹标定）
- 本机无法验证的部分：真机 GPS 精度、隧道/高楼漂移、锁屏 1 小时后是否被降频。`【未验证推断】`

### 1.2 AVAudioSession duck + AVSpeechSynthesizer 播报

- 正确姿势：`AVAudioSession` 设为 `.playback`（不是 `.ambient`，`.ambient` 会被静音开关掐掉），`setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])` + `setActive(true)`；播报结束后 `setActive(false, options: .notifyOthersOnDeactivation)` 让别人的音乐恢复音量。`【官方文档引用】` <https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/duckothers> · <https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer>
- `.duckOthers` 是**系统级混音**，别人的音乐不会被暂停，只降音量；这在"跑步时听播客/音乐 + 到点播报配速"场景是唯一可接受的行为。`【官方文档引用】`
- 坑：`AVSpeechSynthesizer` 与节拍器共用同一个 audio session 时，TTS 会打断节拍排程，需要"节拍器常驻 player node + TTS 用独立 session 或播报期间暂停节拍再精确续上"。`【未验证推断】`（这是本项目最大的音频架构风险，必须真机 A/B）
- 静音开关：`.playback` category 在静音开关打开时仍出声（这是与 expo-speech 的关键差异，见 §2）。`【未验证推断】` — 真机验证项。
- 模拟器可以验证 API 调用不崩、能听到声音；**混音效果、duck 幅度、蓝牙耳机/车机切换不可验**。`【本机实测】`（模拟器有音频输出但无法接真耳机评估混音）

### 1.3 节拍器低延迟发声

- 方案：`AVAudioEngine` + `AVAudioPlayerNode.scheduleBuffer(_:at:)` 按 `AVAudioTime(sampleTime:)` 排程，或 `AVAudioSourceNode` 自绘节拍。精度到采样级（44.1 kHz 下亚毫秒），不受 UI 线程/JS 抖动影响。`【官方文档引用】` <https://developer.apple.com/documentation/avfaudio/avaudioengine>
- 后台持续发声：需要 `UIBackgroundModes` 含 `audio` + `.playback` category；锁屏后继续。代价是耗电与"后台常驻音频"审核关注点。`【官方文档引用】`（Audio background mode）+ `【未验证推断】`（审核是否要求可解释的后台音频用途——跑步节拍器属于合理用途，建议 Info.plist/审核备注写清楚）
- 必须避免：`Timer`/`DispatchSourceTimer`/JS `setInterval` 驱动发声。JS 定时器抖动 10–50 ms 在 160–180 BPM（333–375 ms 间隔）下是 3–15% 的节奏误差，跑者能听出来。`【未验证推断】`（抖动量级来自工程常识，未在本机实测；结论方向确定：不可用 JS 定时器）
- 延迟 AWS/蓝牙耳机：AirPods 的 A2DP 往返延迟可达 150–200 ms，节拍器如需"贴脚"，要么用"视觉节拍 + 音频节拍"，要么依赖 iOS 26 的低延迟模式。`【未验证推断】` — 真机验证项。

---

## 2. Expo / RN 可行性矩阵 vs 纯 SwiftUI

版本基线 `【本机实测】`（npm registry `latest` 查询）：

| 包 | 版本 |
|---|---|
| expo | 58.0.23 |
| expo-location | 58.0.20 |
| expo-speech | 58.0.3 |
| expo-audio | 58.0.11 |
| expo-camera | 58.0.14 |
| expo-sqlite | 58.0.15 |
| expo-task-manager | 58.0.13 |
| react-native | 0.88.1 |

| 能力 | Expo 方案 | Expo Go | 关键限制 / 坑 | 原生 SwiftUI |
|---|---|---|---|---|
| 后台连续定位 | `expo-location.startLocationUpdatesAsync` + `TaskManager.defineTask` | ❌ 必须 dev build（官方原文："You must use a development build to use background location since it is not supported in the Expo Go app"） | iOS 需 `isIosBackgroundLocationEnabled`（config plugin 写 `UIBackgroundModes`）；Android 需 `isAndroidBackgroundLocationEnabled` + 前台服务通知（Android 14 强制 `FOREGROUND_SERVICE_LOCATION`）；杀掉 App 即停 | ✅ 直接 `CLLocationManager`，参数/降频策略完全可控 |
| 语音播报 | `expo-speech` | ✅ 官方标注 Included in Expo Go | **iOS 真机静音模式下无声**（官方文档明确）；`useApplicationAudioSession=false` 时系统自建 session，duck 行为不可精细控制 | ✅ `.playback` + `.duckOthers`，静音开关下仍出声 |
| 音频 duck / 背景播放 | `expo-audio` `setAudioModeAsync({ interruptionMode: 'duckOthers' })` | ✅ 标注 Included in Expo Go（但后台播放需 config plugin `enableBackgroundPlayback`） | Android 端 `interruptionMode` 映射为音频焦点语义，与 iOS 行为不完全等价 | ✅ `AVAudioSession` 完全掌控 |
| 低延迟节拍器 | ❌ 无采样级调度 API（`expo-audio` 只有 player/recorder，无 `scheduleBuffer(at:)`） | — | 只能用 JS 定时器 → 节奏抖动；或自写原生模块（=放弃 Expo 的收益） | ✅ `AVAudioEngine` 采样级排程 |
| 条码扫描 | `expo-camera` `CameraView` + `barcodeScannerSettings` + `onBarcodeScanned`；config plugin `barcodeScannerEnabled` | ✅ 标注 Included in Expo Go，但**仅真机**（模拟器无摄像头） | 需相机权限文案（`cameraPermission`）；EAN-13/EAN-8 需显式列入 `barcodeTypes` | ✅ `AVCaptureMetadataOutput`，同样只能真机验 |
| 本地库 | `expo-sqlite` | ✅ | 无 | ✅ 系统 SQLite / GRDB |
| 构建/分发 | EAS Build 或本地 `expo prebuild` + Xcode | — | 本机无 watchman、无 EAS 项目，首条 dev build 需要额外 1–2 天环境搭建 | ✅ 直接 Xcode 26.3 |

**取舍结论**：Expo 的唯一实质收益是"iOS + Android 一套代码"。但本产品所有关键能力都在 Expo Go 之外（后台定位）或模拟器之外（摄像头、静音模式 TTS、混音），dev build 变成**必需**而非可选；此时 RN 只剩下"多一层桥 + 多一层后台生命周期管理"的成本。**V1 选 SwiftUI（iOS only）**。

反方意见（诚实记录）：如果公司把 Android 覆盖率当作首要不变量，则 Expo 是正确的第二选择，风险见 §7；此时不要试图用 RN 做节拍器。

---

## 3. 验证方案：模拟器能验到哪一步

### 3.1 本机实测环境

```
$ xcodebuild -version
Xcode 26.3
Build version 17C529

$ swift --version
Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2)

$ xcrun simctl list runtimes
iOS 17.5 (17.5 - 21F79)  com.apple.CoreSimulator.SimRuntime.iOS-17-5
iOS 18.6 (18.6 - 22G86)  com.apple.CoreSimulator.SimRuntime.iOS-18-6
iOS 26.3 (26.3.1 - 23D8133) com.apple.CoreSimulator.SimRuntime.iOS-26-3

$ node -v && npm -v
v24.4.1 / 11.4.2      # Expo 路线可用
$ pod --version
1.16.2                # CocoaPods 可用
$ which watchman
not found             # RN 路线的已知缺口（非阻塞，但 Metro 会退化轮询）
```

### 3.2 轨迹注入：本机实测成功

```
$ xcrun simctl location B3F00298-E08A-41E0-876E-6E8A75C730FD set 37.3349,-122.0090
（exit 0，无输出）

$ xcrun simctl location B3F00298-E08A-41E0-876E-6E8A75C730FD start --speed=3.0 "37.3349,-122.0090" "37.3360,-122.0080"
Parsed 2 waypoints

$ xcrun simctl location <udid> list
City Run / City Bicycle Ride / Freeway Drive / Apple   # 内置场景
```

- 可用参数：`set <lat,lon>`、`start [--speed=<m/s>] [--distance=m|--interval=s] <w1> <w2> ...`（`-` 从 stdin 读航点）。`【本机实测】`（`xcrun simctl location` usage 输出）
- 由此可以程序化生成 5:00–7:00 /km 的跑步轨迹，**用于验证配速/距离/自动圈逻辑**，精度取决于注入点密度与插值。`【本机实测】`
- **注意**：注入轨迹验证的是"算法与 UI"，不是"GPS 精度"。两者必须分开记分。

### 3.3 Android：本机实测成功

```
$ ~/Library/Android/sdk/emulator/emulator -list-avds
Munk_QA_API_30
Pixel_XL_API_29          # 均为 arm64-v8a 系统镜像

$ adb shell getprop sys.boot_completed   → 1
$ adb emu geo fix -122.0090 37.3349      → OK
$ adb emu geo fix -122.0080 37.3360      → OK
```

`emulator` 不在 PATH（需用全路径 `$HOME/Library/Android/sdk/emulator/emulator`）；`adb` 在 `platform-tools/`。现有 SDK platform 覆盖 29–37，build-tools 到 37.0.0。`【本机实测】`

### 3.4 模拟器可验 / 不可验清单

可验（本轮已证实路径存在，不需要真机）：
- UI 流程、计时器、距离/配速/分段计算（注入轨迹）
- GPX 导入导出、SQLite 读写、数据模型
- OFF 条码查询的网络层（用真实条码字符串直查 API，绕过相机）
- 前后台切换的基本生命周期、TTS/节拍器 API 不崩

**无真机不可验（必须在 TestFlight 前安排 1 次真机 QA，否则不许发版）**：
1. 锁屏后台连续定位 30–60 min：是否持续采样、是否被系统降频/挂起、蓝条提示行为
2. `Always` 授权真实降级路径（用户选 "While Using" 后的行为与引导）
3. 音频混音实听：duck 幅度是否合适、播报结束后他人音乐是否恢复
4. TTS 在静音开关 / 蓝牙耳机 / CarPlay 下的表现
5. 节拍器延迟与节奏稳定性（含 AirPods 延迟）
6. 摄像头条码扫描（模拟器无相机；需 EAN-13 实物包装）
7. 真实 GPS 精度、隧道/高楼漂移、距离误差
8. 功耗与发热（30 min 跑步实测）
9. TestFlight 安装、后台音频审核口径

---

## 4. 数据所有权

- **GPX 1.1**：读写都用 Foundation `XMLParser`，零第三方依赖；需要处理 `trk/trkseg/trkpt`、`ele`、`time`，以及 Garmin `TrackPointExtension`（`gpxtpx:hr`、`gpxtpx:cad`）的命名空间。`【官方文档引用】` <https://www.topografix.com/GPX/1/1/>
- **FIT**：Garmin FIT SDK 可下载（<https://developer.garmin.com/fit/overview/>，另有 Protocol 文档 <https://developer.garmin.com/fit/protocol/>），以 Garmin 自有许可发布，需接受条款、非通用 OSS，且文件/Profile 需随 SDK 版本更新。`【未验证推断】`（许可条款原文未在本轮抓取到，**未确认**是否允许闭源分发 / 是否有署名义务；若 V1 要做 FIT 写入，先由人确认许可）
  → **建议 V1 不做 FIT 编解码**，导出 GPX + TCX（TCX 是 XML，自写 100 行内）即可覆盖 Strava/Garmin Connect 手动导入。
- **Strava**：API 默认 single-player 模式（只允许自己的账号），扩展需提审，默认限流 200 req/15min、2,000/day。`【官方文档引用】` <https://developers.strava.com/docs/getting-started/> · <https://developers.strava.com/docs/rate-limits/>
  → **V1 不做 Strava OAuth 直传**；做"导出 GPX/TCX → 用户在 Strava 手动导入"。这同时符合"数据属于用户"的定位。
- **本地存储 SQLite**：单文件、可直接导出备份（这是"无广告 / 数据归你"的核心卖点，比云同步更有说服力）。表设计建议：`run(id, started_at, ended_at, distance_m, duration_s, avg_pace, source, gpx_path)`、`run_point(run_id, t, lat, lon, ele, hr, cad)`、`food_log(id, logged_at, barcode, name, kcal, source)`、`food_cache(barcode, json, fetched_at)`。`【未验证推断】`（schema 为建议稿，随实现细化）

---

## 5. 食物条码与热量（Open Food Facts）

- 接口实测可用 `【本机实测】`：`GET https://world.openfoodfacts.org/api/v2/product/3017620422003.json?fields=product_name,brands,nutriments,code` → HTTP 200，返回 `energy-kcal_100g: 539`、`carbohydrates_100g` 等，字段命名稳定。
- **限流**：读产品 15 req/min/IP；搜索 10 req/min/IP；超限会临时封 IP；"来自终端用户 App 的请求按用户计"。`【官方文档引用】` <https://openfoodfacts.github.io/openfoodfacts-server/api/>
- **要求**：必须带自定义 `User-Agent`（格式 `AppName/Version (ContactEmail)`），否则可能被判为 bot；官方建议填写 API 使用登记表。`【官方文档引用】`（同上）
- **许可**：数据库 ODbL 1.0，内容 DbCL，图片 CC-BY-SA → 需署名（"Contains data from Open Food Facts, available under the Open Database License"），若再分发数据库需保持同样许可。**只要不打包全库、只做在线查询 + 本地缓存，就不触发 share-alike 分发义务，但署名不可省。**`【官方文档引用】` <https://world.openfoodfacts.org/data>
- **离线缓存 / 降级**：不做全库 dump（数百 MB 级，且 nightly 更新），只缓存"用户扫过的条码"（`food_cache`，带 `fetched_at`，30 天过期）；查询失败 → 立刻降级到"手输名称 + 热量"，绝不让用户卡在加载态。
- **V1 该留还是该砍：留条码，但砍掉"库"的野心。** 理由：条码是产品名里的承诺（"Barcode Calorie Log"），砍了就没差异点；但"离线全库、营养分析、餐食推荐"属于反范围。风险：条码扫描**无真机不可验**（§3.4 第 6 项），且 OFF 的 EAN 覆盖率在非欧美食品上明显偏低 → 手输兜底是 P0 而不是 nice-to-have。

---

## 6. 分发凭据

本机现状 `【本机实测】`：

```
$ security find-identity -v -p codesigning
1) 7DB1C6BD... "Developer ID Application: Tao Zhu (3X4J53U6RY)"
2) E9E9F2D8... "Apple Development: Tao Zhu (H47755VBGF)"
3) 118C3202... "Apple Development: chaxiu1@gmail.com (2W2F7DXG7M)"
3 valid identities found

$ ls ~/.appstoreconnect/private_keys        → 不存在（无 ASC API Key）
$ ls ~/Library/MobileDevice/Provisioning\ Profiles/ → 1 个 .mobileprovision
$ security cms -D -i <该文件> | plutil -extract Name/TeamIdentifier/ProvisionedDevices raw - 
  → Name = "MunkAI-Runner", Team = 3X4J53U6RY, 含 ProvisionedDevices（= Development profile，非 App Store 分发）
$ ls ~/.android/*.keystore                  → 仅 debug.keystore（无 release/upload keystore）
$ ls /Applications | grep -i transporter    → 无（无 Transporter）
```

**结论：当前凭据只够在模拟器/真机调试跑，不够 TestFlight，不够上架。**

需人录入/授权清单（我无法代做）：

| # | 项 | 用途 | 谁做 |
|---|---|---|---|
| 1 | 确认 Team `3X4J53U6RY` 下已开通 App Store Connect 并接受最新协议（含付费应用协议/税务/银行） | TestFlight + 上架前置 | 人（Xcode 登录 + ASC 网页） |
| 2 | 创建 App 记录（Bundle ID 反写域名 + App 名 PurePace），提供最终 Bundle ID | 上传构建 | 人决策 + 创建 |
| 3 | App Store Connect API Key（`.p8` + Key ID + Issuer ID），约定存放路径（建议 `~/.appstoreconnect/private_keys/`） | CI/命令行上传（`altool`/`notarytool`） | 人 |
| 4 | Apple Distribution 证书（可用 `-allowProvisioningUpdates` 自动生成，但需已登录的开发者账号与协议） | 分发签名 | 人登录一次即可 |
| 5 | iOS 真机（至少 1 台 iPhone，iOS 18+，可锁屏可装 TestFlight） | §3.4 全部验证 | 人 |
| 6 | 隐私政策 URL、App 隐私标签（定位/相机/健康类说明）、审核备注（后台定位与后台音频用途） | 提交审核 | 人确认文案，我可起草 |
| 7 | Android：upload keystore（`keytool` 生成，密码由人保管）+ Play Console 账号（一次性 $25） | 仅当决定上 Android | 人 |
| 8 | OFF 的 User-Agent 联系邮箱（`purepace/1.0 (xxx@xxx)`） | 满足 OFF API 规范 | 人给定 |

---

## 7. 风险 Top 3（按"会不会毁掉 V1"排序）

1. **无真机 = 核心承诺不可验收。** 本产品 5 个卖点里 4 个（后台锁屏记录、音乐不被掐断的播报、节拍、扫码）在模拟器上都无法证伪。若真机到位晚于开发完成，等于把集成风险全部压到发布前一周。→ 必须先拿到 1 台 iPhone，再启动实现。
2. **音频架构耦合（TTS × 节拍器 × 他人音乐）。** 三者共用一个 `AVAudioSession`，任何一方抢 session 都会让另外两个失效（播报打断节拍 / 节拍掐掉用户音乐 / duck 不恢复）。这是本项目唯一需要"先做技术原型再定 UI"的部分。
3. **后台定位在真实设备上的降频/杀进程不可预测**（低电量模式、系统策略、用户上滑杀 App、iOS 大版本差异 17.5/18.6/26.3）。缓解：关键时刻持久化 checkpoint（每 5 s 落盘一次 GPS 点），即使被中断也能恢复到最后一个点，并对用户显式提示"App 被关闭"。

次要风险：OFF 覆盖率与限流（可降级手输）、FIT 许可不明（V1 不做）、App Store 对后台音频/后台定位的审核尺度（文案前置准备）。

---

## 8. 本轮未答 / 待确认项

- FIT SDK 许可原文条款（本轮只拿到下载入口，未抓取许可正文）。
- 锁屏后台定位的真实节流曲线、功耗曲线（需真机）。
- 静音开关下原生 `AVSpeechSynthesizer` + `.playback` 是否稳定出声（文档层面是"应该出声"，2016 年有社区报告过不一致行为，需真机）。
- 现有 `.mobileprovision` 已确认是 `MunkAI-Runner`（Team `3X4J53U6RY`，Development 类型，含设备白名单）——不是 App Store 分发 profile，与本产品无关，可忽略。
