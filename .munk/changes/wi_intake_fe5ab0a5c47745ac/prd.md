# 修核心闭环真机零可用：计时与定位解耦、结束必有数据 + 根因说明

## 范围

真机现象（人工实测，唯一现场事实）：授权定位后点开始，计时停在 00:00；结束后没有任何数据。必须修到主链路在真机成立，并让该失败模式在无真机条件下可复现。

已由只读勘察确认的现状（可直接采信，自行复核后方动刀）：

- `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift` 的 `activeElapsed` 完全由 sample 时间戳累加（约 :92-101 / :159-161），`start/pause/resume/finish` 只挪锚点，`finish` 不为墙钟补账 → 零条 accepted fix 就必然 00:00 / 0m / 空记录。
- `ios/PurePace/Location/RunLocationSource.swift` 精度过滤 ≤50m（约 :207-209），CL 失败无 `didFailWithError`、无 `locationServicesEnabled` 检查，全程静默。
- `RunSessionOrchestrator.swift` 的 finish（约 :185-215）把 `metrics.elapsed` 写进 `RunRecord.activeDuration`；`RunRecord.swift:52-60` 允许空 samples（不崩但页面空）。
- 现有测试全走合成定位源（`-uiTestLocation` 每秒一条 fix），单测的 elapsed 也由 sample 驱动 → 所以门全绿而真机零可用。

要做的事：

1. 计时真源改为单调时钟（`ContinuousClock` / `ProcessInfo.systemUptime` 经可注入 protocol），暂停区间不计入；`finish` 按时钟结算 `activeDuration`。App/View 层只做 1s 刷新（如 `TimelineView(.periodic)` 或等价 ticker），不得再以 location 回调作为推进来源。
2. 定位健壮性：保留 best 精度与 `distanceFilter=none`；补 `didFailWithError`、`locationServicesEnabled=false`、授权被拒/受限的上报路径（可展示状态，不静默）；加有界降级——自 `startUpdatingLocation` 起 N 秒内无 ≤50m fix 时接受当前可得的最佳 fix 并标记其 accuracy（N 与放宽阈值先写进代码注释并说明推导，先定后测）。首个 fix 到达前状态明确为「等待定位」。
3. 运行态 UI：ticker 驱动的时间照常走；0 采样/无首 fix 时显示「等待定位」内联提示（沿用既有 inline 胶囊形态，不新增版式、不改令牌）。
4. 结束与保存：无论 samples 是否为空都写 `RunRecord`；结束页明确给「时长 / 采样点数 / 距离」，无定位时距离位写「未获取到定位，距离为空」；详情页与导出入口不空白、不崩溃；空 samples 的 GPX 导出给明确提示且不产生损坏文件。
5. 根因说明（必交，新增 `docs/root-cause-core-loop-device.md`）：逐条写清为什么单测 + 模拟器 UI + 四条 CI 全绿而真机零可用，每条附代码位置与对应的无真机可复现断言名；禁止以「真机环境差异」收尾。
6. `docs/verification-matrix.md` 更新对应接缝行；`docs/distribution/manual-test-guide.md` 增量更新复测段（只写点哪里、看什么、异常回报什么，不含任何命令）。

## 验收

- ac-clock-tick: 注入「已授权但零 location 回调」的场景，start 后推进注入时钟 5s，`activeDuration` ≥ 4.5s 且 UI 文案不再是 00:00；断言不依赖真实 sleep。
- ac-clock-pause: pause 期间注入时钟推进不增加 `activeDuration`，resume 后继续累计；前后台切换不重置。
- ac-finish-empty: samples 为空时 finish 产出的记录含 `activeDuration>0`、`sampleCount==0`、距离为空语义；结束页与详情页有对应文案、不空白、不崩溃。
- ac-finish-normal: 有 samples 时结束页显示 距离/时长/配速/采样点数，详情页地图与分段与记录一致。
- ac-location-fallback: 注入「仅一条 65m 精度 fix」场景，不再永久 0 且无提示，而是按降级口径产出距离或以明确精度状态呈现（护栏不得放宽到接受任意精度）。
- ac-location-error: 注入 `didFailWithError` 与 `locationServicesEnabled=false`，状态可展示、计时不回退。
- ac-gpx-empty: 空 samples 导出返回明确失败/空轨迹提示，不产生损坏文件。
- ac-root-cause-doc: `docs/root-cause-core-loop-device.md` 存在，逐条含代码位置 + 断言名，无「真机环境差异」式结论。
- ac-matrix-row: `docs/verification-matrix.md` 相关行已更新且结构不变量测试仍绿。
- ac-guide-update: 人工复测说明增量段无命令行、逐项标「机器已验 / pending: 待人现场」，无「真机已验证」字样。

## 非目标

- 不改 UI 设计 / 版式 / 令牌 / 配色，不新增功能面（不做新页面、新设置项、社交或订阅）。
- 不上 TestFlight、不推 tag、不建 GitHub Release、不执行任何上传，不动 `VERSION` 与 release notes。
- 不新增真机自动化 / 设备场基建；agent 不做真机验收。
- Android 不改功能面，只保证同一主链路不回退。
- 不降低、不删除、不 `continue-on-error` 任何既有门禁腿与阈值。

## 实现约束

- 依赖方向保持 View → ViewModel → Orchestrator → RunCore；计时真源在 RunCore，App 层不得自建第二套计时真源。
- 时间源必须可注入（protocol），默认实现用单调时钟；测试用注入时钟推进，禁止 sleep 真实时间与采样抖动断言。
- 先定后测：精度降级超时 / 放宽阈值在测量前写进代码注释并说明推导，禁止看到红了再调阈值。
- 每条新断言同 commit 附「构造错误输入 → 必须红」的反例，且不依赖改生产代码才红；断言不得同源别名自证、不得因缺席而绿。
- identifier 是契约：既有集合只增不改；新增 a11y label 用中文且与可见文字语义一致。
- 用户可见文案走 String Catalog 单一来源，禁裸英文字面量与中英混排。
- commit 按面拆分：code（源码/测试/脚本）、fold（基线/文档/证据）、prd 不得同一个 commit。

## 本单执行约束（不 fold）

- 预算 ≤8M token / ≤90 分钟墙钟；到点即停手交未闭合回执（已做 / 未做 / 已过门 / 未闭合点），不续命、不重跑已绿门、不弱化断言。
- 只改 `ios/`、`shared/`（若确需夹具）与 `docs/` 必要文件；目录外零写入，不动托管文件。
- 交付前本地跑快腿（lint / static / 结构契约 / `swift build|test` / 单测）；改到受管视图或 identifier 时显式跑 `scripts/check-ios-shell.sh --self-test` 并全绿。
- iOS 权威腿结论以同 commit `ios.yml` run 为准，本地只作旁证；回执只写实际跑到范围，未跑齐写「未跑齐」并给依据。
- 不产出「请人跑命令」类 assist 卡；人只做真机复测。未验项写 `pending: 待人现场`，禁写「真机已验证」。
- 证据（截图/日志/断言源）绑 commit 与 sha256；每个数字标口径。

## 公司补充裁决（与上文同等效力，2026-11-18）

### 设备取证结论（已跑，直接采信）

- `xcrun devicectl device info apps`（18:38 local；设备 40383DE2…A148 / iPhone 12 Pro Max）显示设备上**当前没有任何 PurePace**（`sh.munk.purepace` 与旧 `com.chaxiu.purepace` 均不在列）。
- 上一轮安装的是 `ebcb3d8`（VERSION 0.1.0 / build 1）开发签名直装（`devicectl install`，10:14Z，任务 `trun_a79a41e0bbef692b`）。即：人工看到的「计时不动、结束无数据」是**包内缺陷**；bundle id 历史上换过一次，本轮为全新 notDetermined 起点。

### 追加硬要求（缺一不算交付）

1. **系统权限弹窗必须真实触发**：`CLAuthorizationStatus == .notDetermined` 且用户点「开始」时必须调用 `requestWhenInUseAuthorization()`；App 内「行踪轨迹敏感个人信息」同意按钮只是告知同意，不得替代/短路，也不得排在系统请求之前把请求吞掉。交付需给出明确顺序与代码位置。
2. **两段式授权**：取得 WhenInUse 后、跑步进行中调用 `requestAlwaysAuthorization()`（Apple 规则：必须先有 WhenInUse 且 App 在使用中）；`UIBackgroundModes` 含 `location` 且 `allowsBackgroundLocationUpdates=true` 二者缺一不可；未拿到 Always 时 UI 必须写明「仅前台记录」，不得假装后台在采。
3. **denied / restricted 必须有出口**：不得进入记录态；给原因文案 + 「去系统设置」按钮（`UIApplication.openSettingsURLString`）；App 回前台（`scenePhase == .active`）自动复检授权并刷新状态。
4. **诊断区（设置页新增，不改既有版式与令牌）**：版本号 + 构建 sha 前 8 位（构建期写入 Info.plist，如 `PurePaceBuildSHA`，不得运行时读 git）+ `CLAuthorizationStatus` + `accuracyAuthorization` + 本次会话已采样本数 + 最近样本时间 + `allowsBackgroundLocationUpdates` + **raw 回调数 / 被精度过滤丢弃数**；一键复制/导出文本。诊断数据走单一 `RunDiagnostics` snapshot，不新建第二个计时真源。
5. **采样过滤可归因**：`accuracyThresholdMeters = 50` 室内可能全滤掉；诊断区必须同时显示 raw 与 dropped 计数；阈值/降级窗口仍按「先定后测」写进注释。
6. **断言**（每条同 commit 附「构造错误输入必红」反例）：spy 断言「notDetermined 点开始 → `requestWhenInUseAuthorization` 恰 1 次」；「WhenInUse 且 running → `requestAlwaysAuthorization` 恰 1 次」；「denied → 不进记录态且有设置引导」；「background 声明缺一 → 断言红」。
7. **plist 读回证据**：从**同一 commit** 的 Release 归档产物（`xcodebuild archive` 的 `.app/Info.plist`，不导出不上传、不当作分发候选）读回 `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` / `UIBackgroundModes`，读回值写入交付证据并注明归档路径与 commit；**禁用 11-10 那次旧读回**。

### 实施顺序

A 时钟改单调时钟 + 结束必给数据 → B 权限链路 → C 诊断区 + plist 读回 → D 根因文档/验证矩阵/复测说明 → 门与自检。A 段不得留半套（禁止一台机器两个计时真源）。

### 预算与纪律

12M token / 90 分钟墙钟，到点即停手交未闭合回执；预算上调仅本项、由公司补充裁决触发。commit 按 code / fold / prd 分面；不碰 `VERSION`、release notes、workflows 既有腿；不产出 assist 卡、不写真机已验证；`pending: 待人现场` 照写。

### 明确不进

不改 UI 版式与设计令牌、不加功能面（诊断区除外且按上面口径最小化）、不上 TestFlight / 不建 Release / 不推 tag。
