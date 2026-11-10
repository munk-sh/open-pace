# PurePace V1 范围建议（MVP 切片 + 反范围）

前提：平台建议 **iOS only（SwiftUI 原生）**，Android 留到 V1.1（见 `docs/evidence/mobile-stack-spike.md`）。
产品定位一句话：**不是为了刷数据的跑步 App，而是一个"没人打扰你"的跑步计时器 + 热量记录本**——无账号、无广告、无社交、数据在你手里。

V1 的成功标准只有一条：**一个人在真实户外跑 5 km，全程不掏手机，跑完看到准确的轨迹/配速，并在 App 里用条码记下两样食物。** 其他都是加法。

---

## 1. 切片（每片都可独立验收）

### S0 · 骨架（可运行空壳）
- SwiftUI App + Tab（Run / History / Log / Settings）
- SQLite 建库（`run` / `run_point` / `food_log` / `food_cache`）+ 迁移位
- 导出目录：`Documents/exports/`
- 验收：模拟器启动、建库、写入一条假 run 并读出
- 依赖：无（先不接定位）

### S1 · 跑步核心（前台）
- `CLLocationManager`（`activityType = .fitness`，1 Hz，`distanceFilter = 3 m`）
- 计时：`elapsed` vs `moving`（自动暂停阈值 0.5 m/s 持续 5 s）
- 实时指标：距离、当前配速、平均配速、分圈（1 km 自动圈）
- 轨迹折线（MapKit 不做自定义瓦片）
- 每 5 s checkpoint 落盘（为 §7 风险 3 兜底）
- 验收：`xcrun simctl location start --speed=3.0` 注入 3 km 轨迹，距离误差 < 3%，配速曲线单调合理

### S2 · 后台与音频（产品的灵魂，也是最大风险）
- `UIBackgroundModes`：`location` + `audio`
- 锁屏/切后台连续记录；App 被用户杀掉后的恢复提示
- `AVAudioSession(.playback, .spokenAudio, [.duckOthers, .mixWithOthers])`
- `AVSpeechSynthesizer`：每公里播报（距离 + 配速 + 用时），可关
- 播报结束后 `setActive(false, .notifyOthersOnDeactivation)` 恢复别人的音乐
- 验收（边听 Spotify 边跑 1 km，音乐只降不暂停、播报后恢复；锁屏 30 min 仍连续记录）：真机不做 agent 验收，交付后由人手测

### S3 · 节拍（cadence metronome）
- `AVAudioEngine` + `AVAudioPlayerNode.scheduleBuffer(at:)` 采样级排程
- BPM 60–220（步频目标），可开关、可跟随当前步频（`CMPedometer`/CoreMotion 可选）
- 播报期间节拍不抖（暂停-续接策略）
- 验收（180 BPM 连续 3 min 主观无漂移；与 Spotify 同时播放互不打断，需有线耳机）：真机不做 agent 验收，交付后由人手测

### S4 · 条码热量（V1 的差异点）
- `AVCaptureMetadataOutput`（EAN-13/EAN-8/UPC-A）扫码 → OFF v2 查询
- 展示：名称/品牌/每 100 g 热量 → 用户输入份量 → `food_log`
- 手输条码 + 手输名称/热量（**P0，不是兜底彩蛋**）
- `food_cache` 30 天；断网/未命中 → 立即降级，不出现无限 loading
- OFF 署名（Settings 页 + 关于页）
- 验收：真机扫 3 个真实包装；模拟器用"手输条码"走通全链路

### S5 · 历史与导出（数据所有权的兑现）
- 历史列表 + 单次详情（轨迹、分圈、图表用 Swift Charts）
- GPX 1.1 导出（`XMLParser` 自写）+ 从 Files 导入 GPX
- 分享 sheet（系统 `ShareLink`，不做社交 SDK）
- 验收：导出 → 用第三方（Strava/Garmin Connect 网页）手动导入成功

### S6 · 发布准备
- 隐私标签、隐私政策页、审核备注（后台定位 + 后台音频用途说明）
- 1 次真机 QA 全量回归（清单见 spike §3.4）
- TestFlight 内测（≥ 3 人 × 3 次跑步）

依赖关系：`S0 → S1 → S2 → (S3 ∥ S4) → S5 → S6`。S2 若卡住，S3/S4 可并行推进，但**不许绕过 S2 发布**。

---

## 2. 反范围（V1 明确不做，写进 handoff 以防蔓延）

| 不做 | 为什么 |
|---|---|
| 账号、云同步、多设备 | 与"数据归你"定位冲突；SQLite 单文件已够用 |
| 社交 feed、排行榜、好友、挑战 | 无广告=无增长引擎，社交是纯成本 |
| 订阅墙 / 广告 / 付费解锁 | 产品名就是 Ad-Free；一旦加就是自毁定位 |
| Apple Watch 独立 App | 工作量 ≈ 再造一个产品；V1.1 再评估 |
| Android 首发 | 双平台会把 §7 风险放大 2 倍（见 spike §2） |
| FIT 编解码 / Strava OAuth 直传 | FIT 许可未确认；Strava single-player 限流 + 提审成本；GPX/TCX 手动导入已够 |
| 训练计划、教练建议、AI 分析、心率区间处方 | 需要运动科学背书，且是"另一种产品" |
| OFF 全量离线库 / 营养分析 / 餐食推荐 | 数百 MB + 许可 share-alike 复杂度；条码查询已兑现承诺 |
| 离线地图瓦片 / 自定义地图样式 | MapKit 默认即可；瓦片授权是坑 |
| BLE 心率带 / 功率计 | V1.1；V1 只做系统 HealthKit 只读（可选） |
| 多语言 | 先英文（商店文案）+ 中文（若目标市场需要），不做 i18n 框架 |

---

## 3. 仍需公司/人确认的三件事（阻塞实现，不阻塞调研）

1. **真机**：至少 1 台 iPhone（iOS 18+）。S2/S3/S4 的真机项不做 agent 验收，交付后由人按 `docs/device-manual-acceptance.md` 手测；设备可后到位，不阻塞开工。
2. **平台决策**：确认"iOS 首发、Android 后置"是否可接受；若不可接受，需按 spike §2 改选 Expo 并重估周期。
3. **分发凭据**：ASC API Key + App 记录 + 隐私政策 URL + OFF 联系邮箱（清单见 spike §6）。

---

## 4. 给下一层的执行提示

- 第一个 work item 不要写业务代码，先写 **S2 的音频技术原型**（TTS + 节拍 + duck 三者共存），这是唯一"做错了要推翻架构"的部分。
- 所有距离/配速算法必须可注入轨迹单测（`simctl location` 轨迹作为 fixture），否则后期无法防回归。
- 每个切片结束都产出一个可安装的 dev build，避免"最后一次集成"。
