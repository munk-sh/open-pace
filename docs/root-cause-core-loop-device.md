# 核心闭环真机零可用：根因与无设备可复现断言

本文件解释同一个矛盾事实：**真机上授权定位后点「开始」，计时停在 00:00；结束后没有任何数据**，
而单测、模拟器 UI 测试与四条 CI 腿全部绿。全部代码位置与行号以本 worktree 现状为准（可用
`grep -n` 复核）；全部数字都标口径。

本文件不声明「真机已验证」。真机上发生了什么只有人工现场描述一条事实来源；下面的每条根因都用
**不接真机的断言**覆盖，断言在无模拟器、无设备时即可红/绿。

---

## 1. 现象与结论摘要

| # | 现象（人工现场事实） | 根因 | 现有断言（无设备可复现） |
|---|---|---|---|
| A | 计时停在 `00:00`，结束后时长为 0 | 活跃时长寄生在「被接受的定位采样时间戳」上；零条 fix 就没有任何时间增量 | `testElapsedTicksWithClockAndZeroLocationSamples`、`testPauseFreezesElapsedAndResumeContinues`、`testFinishWithoutAnySampleArchivesClockDrivenDuration`、反例 `testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance` |
| B | 室内/楼下一直 0 距离且界面无任何提示 | 精度过滤阈值下方是**静默丢弃**：既不加计数也不降级，定位失败也没有上报出口 | `testSingleImpreciseFixIsAcceptedOnlyAfterFallbackWindowAndMarked` |
| C | 点了「开始」没弹系统定位弹窗；授权后状态不刷新 | `start()` 未在 `notDetermined` 时真实拉起系统请求；无 `scenePhase == .active` 复检；denied 无出口 | `testStartRequestsWhenInUseExactlyOnceWhenNotDetermined`、`testRunningWithWhenInUseUpgradesToAlwaysExactlyOnce`、`testDeniedNeverEntersRecordingStateAndExposesSettingsRecovery`、`testBackgroundLocationModeAndRuntimeFlagCannotDisagree` |
| D | 上面这些缺陷在 CI 里永远看不见 | 测试输入把「每秒都有一条 fix」写进了夹具，真机「一条 fix 都没有」这条路径从来没有被走过 | 反例 `testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance`（时钟冻结 + 采样推进 → 时长必须仍为 0，若有人把计时搬回采样回调，该用例立刻红） |
| E | 结束后「没有任何数据」这一点本身没有诚实呈现 | 结束页/详情页/导出在空样本下要么空白、要么给 0 值，导出可能产出空/损坏文件 | `testMapsRecordFieldsWithoutRecompute`、`testEmptySamplesFailsWithoutNewFile`、`testEmptySplitsExposeHonestEmptyState`、`testDiagnosticsSnapshotReportsVersionSHAAndCallbackCounters` |

口径：上表「现象」列只来自本项 PRD 记录的唯一现场事实（`.munk/changes/wi_intake_fe5ab0a5c47745ac/prd.md:5`）与设备取证结论（同文件 :67-68：设备上包为 `ebcb3d8` 开发签名直装、bundle id 历史变更，故本轮是全新 `notDetermined` 起点）。

---

## 2. 根因 A：计时真源寄生在定位样本上

**旧行为**：`RunMetricsEngine` 的活跃时长完全由「被接受的 sample 时间戳」累加，
`start` / `pause` / `resume` / `finish` 只挪锚点、从不按墙钟结算。于是：

- 零条 accepted fix → 账本里没有任何一次累加 → `elapsed == 0` → UI 恒定 `00:00`；
- `finish` 只把锚点挪到结束时刻，也不补账 → 结束时 `activeDuration == 0`、`distance == 0`；
- `RunRecord` 允许空 `samples`（`ios/RunCore/Sources/PurePaceRunCore/RunRecord.swift:61` 只在 `samples.count > 1` 时校验时间戳单调；`:52` 只校验 `activeDuration` 有限且非负），所以此时**不崩、只是全空**——这正好对上「结束后没有任何数据」。

**现状修复**（本 worktree）：

- `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift:26` — 引擎持有注入的 `clock: RunTimeSource`，`init(clock:)` 在 `:50`，恢复态构造在 `:58-60`；
- `:36` `activeElapsed` 改成**只由 pause/finish 结算**的账本（注释原文「只由 pause/finish 写入」），`:38` `runningSince` 是单调时钟起点；
- `:117-149` `start/pause/resume/finish` 全部改为「读时钟、settle、挪锚点」，`finish`（`:143-149`）先 `settleElapsed()` 再封存；
- `:290-294` `liveActiveElapsed` = 已结算账本 + 当前运行段时钟差（`max(0, …)` 防时钟回拨导致读数回退）；
- `:297-304` `settleElapsed()` 用「now > runningSince」判定，重复调用不重复累加；
- `ios/RunCore/Sources/PurePaceRunCore/RunTimeSource.swift:8-11` 定义唯一时间源协议（`uptime: TimeInterval`，契约写明「采样回调不参与计时」），`:14-19` 生产实现 `SystemMonotonicTimeSource` 直接读 `ProcessInfo.processInfo.systemUptime`（单调、含休眠、不受墙钟跳变影响）；
- App 层只有 1s 刷新，不建第二套真源：`ios/PurePace/Run/RunView.swift:122-131`（`.task(id: viewModel.state)`，`Task.sleep(for: .seconds(1))` 后调 `viewModel.tick()`）、`ios/PurePace/Run/RunSessionViewModel.swift:241-247`（`tick()` 只 `apply(orchestrator.tick(at: now()))`）；
- 编排层透传同一时间源：`ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift:38`/`:53`/`:58`/`:60`，`tick(at:)` 在 `:190`。

**断言**（`ios/RunCore/Tests/PurePaceRunCoreTests/RunClockDecouplingTests.swift`）：

| 断言 | 位置 | 覆盖的口径 |
|---|---|---|
| `testElapsedTicksWithClockAndZeroLocationSamples` | :60 | 5s 注入时钟推进后 `elapsed == 5.0`（±1e-9，:68）且 `≥ 4.5`（:67，对应 ac-clock-tick 阈值）；距离必须 0（:69） |
| `testPauseFreezesElapsedAndResumeContinues` | :74 | pause 期间推进 10s 不增加（:83-84），resume 后 2s 得 5.0（:86-88） |
| `testFinishWithoutAnySampleArchivesClockDrivenDuration` | :93 | 零采样结束仍产出记录并归档（:100-106），`activeDuration == 5.0`（:108），`sampleCount == 0`（:110），`hasLocationData == false`（:112） |
| `testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance`（反例） | :117 | 三条严格递增样本把距离推起来（:127），但时钟冻结时 `elapsed` 必须恒为 0（:128）——把计时搬回采样回调即红 |

断言不 sleep 真实时间：`TestRunClock` 由注入时钟推进（同目录 `TestRunClock.swift`），符合「断言不依赖真实 sleep」的要求。

---

## 3. 根因 B：定位精度过滤静默（≤50m）+ 无失败上报 / 无降级

**旧行为**：`RunLocationSource` 只接受 `horizontalAccuracy <= 50m` 的 fix，超阈值整条丢弃且**不留任何痕迹**；
`CLLocationManagerDelegate` 侧只有 `didUpdateLocations`，没有 `didFailWithError`，也没有
`CLLocationManager.locationServicesEnabled()` 前置检查。合成三点后果：

1. 室内/高楼遮挡下全是 65–120m 的 fix → 一条都不接受 → 距离 0 且界面上没有任何原因；
2. 系统定位服务关闭/出错时，调用方完全不知道——既不显示状态，也不停止等待；
3. 没有计数，事后无法归因「是没回调还是被过滤」。

**现状修复**（`ios/PurePace/Location/RunLocationSource.swift`）：

- `:129` `static let accuracyThresholdMeters: Double = 50.0`（口径：代码常量，注释标明 `kCLLocationAccuracyBest` 开阔路面典型误差上界）；
- `:135` `static let accuracyFallbackWindowSeconds: TimeInterval = 15.0`（口径：代码常量；`:133-134` 注释写明推导——室内/高楼常见 65–120m，15s 覆盖「出电梯/出门」的短暂遮挡且不让用户长时间看 0 距离，属「先定后测」）；
- `:137` `static let accuracyFallbackCeilingMeters: Double = 200.0`（护栏上限：超过 200m 已是蜂窝/基站级粗定位，宁可不接受也不伪造轨迹）；
- `:180-184` 可归因计数与精度快照：`rawCallbackCount`（原始回调含被丢弃）/ `filteredCallbackCount`（被精度过滤丢弃）/ `lastAcceptedAccuracyMeters`；
- `:261-294` `deliver(_:)`：先 `rawCallbackCount += payloads.count`；精度为负直接计入丢弃；`<= 50m` 立即接受并清空待降级最佳 fix；超阈值则计入丢弃、保留窗口内「最佳可得」，窗口到点且不超过 200m 才接受；
- `:296-317` `accept(_:)`：造样本前先记下该 fix 的真实精度，再下发 delegate；
- `:186-192` 运行期后台开关与自动暂停开关快照经 `RunLocationProviding` 暴露；
- `:59-89` `protocol RunLocationProviding`：`:71` `requestWhenInUseAuthorization()`、`:73` `requestAlwaysAuthorization()`、`:75` `rawCallbackCount`、`:77` `filteredCallbackCount`、`:79` `lastAcceptedAccuracyMeters`；`:82-89` 给出测试桩零值默认实现，避免每个 fake 重复样板。

**断言**：`testSingleImpreciseFixIsAcceptedOnlyAfterFallbackWindowAndMarked`
（`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:217`）

- 一条 65m 精度 fix（:231）在窗口内**不得**被接受（:235），同时 `rawCallbackCount == 1`、`filteredCallbackCount == 1`（:236-237）——「护栏不得放宽到接受任意精度」与「过滤必须可归因」同时成立；
- 注入时钟推进 `accuracyFallbackWindowSeconds` 后再来同一条 fix（:239-240），必须接受 1 条（:242）且 `lastAcceptedAccuracyMeters == 65`（:243，降级 fix 必须标记真实精度）。

口径说明：65m 与 15s 都是测试与代码常量的对照值，不是实测统计量。

> **已知缺口（不在本文件内假装已闭合）**：`didFailWithError` 与 `locationServicesEnabled` 在本 worktree
> **仍不存在**——`grep -rn "didFailWithError\|locationServicesEnabled" ios/PurePace ios/PurePaceTests ios/RunCore`
> 零命中（`ios/PurePace/Location/RunLocationSource.swift:402-424` 只实现了
> `locationManagerDidChangeAuthorization` 与 `didUpdateLocations` 两个回调）。
> 因而 PRD 的 ac-location-error（注入 `didFailWithError` 与 `locationServicesEnabled=false`）**当前没有断言覆盖**，
> 也不应在此文件写成「已验」。该缺口需由源码补 seam + 断言后另行回填。

---

## 4. 根因 C：系统授权链路未真实触发 / 无出口

**旧行为**：`notDetermined` 时点「开始」没有调用 `requestWhenInUseAuthorization()`，App 内「行踪轨迹敏感个人信息」
告知同意被当成实际授权；授权变化后没有回前台复检；`denied` / `restricted` 既没有原因文案也没有
「去系统设置」出口，于是用户看到的是一个永远走不动、也说不清为什么的界面。

**现状修复**：

- `ios/PurePace/Run/RunSessionViewModel.swift:181-215` `start()`：先以系统探针真值覆盖本地状态（:184-187）；
  `:189-192` `denied/restricted` **不进入记录态**，只做定位源收敛后返回；
  `:193-197` `notDetermined` 时点「开始」必须真实拉起系统请求（`didRequestWhenInUseAuthorization` 保证每实例一次）；
  倒计时期间即启动定位源（:212-214）。
- `:400-406` `refreshAuthorization()`：回前台复检探针并重新应用定位源，且**不重置会话计时**；
- `:381-383` `locationSettingsURL` = `UIApplication.openSettingsURLString`，被拒态的唯一恢复出口；
- `:408-416` `requestAlwaysAuthorizationIfNeeded()`：仅在 `state == .running && authorization == .authorizedWhenInUse && !didRequestAlwaysAuthorization` 时请求，每会话恰一次；
- `:576-592` delegate：记录态下授权落到 WhenInUse 立即升级 Always（:589-591）；
- `ios/PurePace/Run/RunLocationReadiness.swift:9`/`:11` 定义 `awaitingAuthorization` / `permissionDenied`，
  `:27-29` `denied → permissionDenied`，`:36-37` `permissionDenied → .openSettings`（`nextAction` 枚举另见 `:17-18`）；
- `ios/PurePace/Location/RunLocationSource.swift:194-207` `start()` 按系统状态分派：`notDetermined → requestWhenInUseAuthorization()`、`authorizedWhenInUse → requestAlwaysAuthorization()`、`restricted/denied/authorizedAlways` 不请求；
  `:210-221` 两个请求各自用布尔守卫保证「每数据源实例恰一次」；
- 后台声明与运行期开关缺一不可：`:241-249` `beginUpdating()` 置 `allowsBackgroundLocationUpdates = true`，`:251-258` `endUpdating()` 复位。

**断言**（`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift`）：

| 断言 | 位置 | 判据 |
|---|---|---|
| `testStartRequestsWhenInUseExactlyOnceWhenNotDetermined` | :106 | 连点两次 `start()` 后 `whenInUseRequestCount == 1`（:116），且未拿到 WhenInUse 前 `alwaysRequestCount == 0`（:117） |
| `testRunningWithWhenInUseUpgradesToAlwaysExactlyOnce` | :122 | 进入 `running` 后 `alwaysRequestCount == 1`（:135） |
| `testDeniedNeverEntersRecordingStateAndExposesSettingsRecovery` | :140 | denied 下 `state == .ready`（:154）、连倒计时都不开始（:155）、`locationReadiness == .permissionDenied`（:156）、`nextAction == .openSettings`（:157）、`whenInUseRequestCount == 0`（:158）、`locationSettingsURL != nil`（:159）；反例：授权恢复后同一条 `start` 路径能正常开始（:162-165） |
| `testBackgroundLocationModeAndRuntimeFlagCannotDisagree` | :170 | `Info.plist` 的 `UIBackgroundModes` 含 `location`（:172-175），且已授权时运行期 `allowsBackgroundLocationUpdates == true`（:181-184）——声明与行为缺一即红 |

---

## 5. 根因 D：测试输入制造盲区

**旧行为**：两条机器腿的输入把真机故障路径结构性排除掉了。

1. **模拟器 UI 腿**：所有 UI 用例都带 `-uiTestLocation` 启动参数（`ios/PurePaceUITests/RunFlowUITests.swift:29`、`:373`、`:423`、`:615`、`:738`、`:1648`；`ios/PurePaceUITests/EvidenceCaptureUITests.swift:87`/`:127`/`:135`/`:144`/`:165`/`:179`）。
   该源是 DEBUG 门控的确定性源，`ios/PurePace/Location/RunTestLocationSource.swift:20` `defaultInterval = 1.0`，
   `:96` 用 `Timer.scheduledTimer(withTimeInterval: interval, repeats: true)` **每秒投一条 fix**。
   即：UI 腿从来没有「一条 fix 都没有」的场景，首条 fix 在起跑后 1s 内必定到达。
2. **L1 单测**：旧引擎的 `elapsed` 由样本时间戳累加，样本的时间戳又是夹具给的 → 只要夹具给样本，
   时长就有值；夹具不给样本，则「时长必须为 0」被写成了「设计如此」，不会被判红。
3. **CI 装配**：UI 腿每个分段前还会主动重申模拟器授权
   （`scripts/test-ios.sh:606-614`，`simctl privacy grant location` + `location-always`），
   于是授权链路的真实分支（弹窗、拒绝、回前台复检）在模拟器上被系统命令旁路。

**反例如何把「冻结时钟」照红**：`testFrozenClockKeepsElapsedAtZeroWhileSamplesAdvance`
（`ios/RunCore/Tests/PurePaceRunCoreTests/RunClockDecouplingTests.swift:117`）注入一个**永不前进**的时钟，
但照常喂三条严格递增样本：距离必须 > 0（:127），活跃时长必须仍为 0（:128），平均配速必须为 nil（:129）。
只要有人把计时改回「采样时间戳累加」，:128 立刻红——这条断言在没有设备、没有模拟器时同样成立，
即「真机零可用」的失败模式被搬进了 `swift test`。

---

## 6. 根因 E：结束 / 详情 / 导出对空样本不诚实

**旧行为**：空样本时结束页的距离位显示 `0.00`（假装有轨迹）、详情页地图与分段区空白、
导出入口在空轨迹上仍尝试产出文件。用户看到的是「没有任何数据」且拿不到解释。

**现状修复**：

- `ios/PurePace/Run/RunView.swift:302-320` 结束/运行态距离位：有定位才显示数值与单位（:303-312），
  否则显示 `L10n.runDistanceUnavailable`（:313-319，注释「不显示 0.00 假装有轨迹」），保留同一 `run.distance` identifier；
- `:491-500` 「等待定位」内联胶囊：`viewModel.isWaitingForLocation` 为真时显示 `L10n.runWaitingLocation`，identifier `run.waitingLocation`，**不阻断计时**（注释 :491 原文）；
- `:361-370` 采样点数行：`run.sampleCount` 显示 `viewModel.sampleCount`；
- `ios/PurePace/Run/RunSessionViewModel.swift:452-455` `isWaitingForLocation = state == .running && !orchestrator.hasLocationData`，`:441-444` `hasLocationData`；
- `ios/PurePace/History/RunDetailContent.swift:24-27` 详情距离位：`!record.hasLocationData` 时用 `L10n.runDistanceUnavailable`；`:29` 采样点数照常输出；`:43-49` 分段摘要与 `hasSplits` 供空分段态判定；
- `ios/PurePace/History/RunExportState.swift:10-11` 新增 `.emptySamples` 明确态；`:23-35` `export` 捕获 `RunArchiveError.emptySamples` 直接落该态（不产生文件），其余错误落 `.failed`；`:37-45` `isLandedGPXFile` 要求扩展名 `.gpx`、文件存在且字节数 > 0，否则判 `.failed`——不允许「假成功」；
- 诊断快照：`ios/PurePace/Run/RunSessionViewModel.swift:385-397` `diagnosticsSnapshot()` 单一快照，含版本/构建 sha、授权、`accuracyAuthorization`、样本数、最近样本时间、后台开关、raw/被过滤计数；`ios/PurePace/Run/RunDiagnostics.swift:10` 结构体、`:37` sha 只取前 8 位、`:48-53` 文本渲染、`:72`/`:84` 两种诊断文本；设置页渲染与一键复制见 `ios/PurePace/Settings/SettingsView.swift:58-76`（`settings.diagnostics` / `settings.diagnostics.copy`）。

**断言**：

| 断言 | 位置 | 判据 |
|---|---|---|
| `testEmptySamplesFailsWithoutNewFile` | `ios/PurePaceTests/RunExportStateTests.swift:96` | 空样本导出时导出器必须抛错（:101），UI 相位落到 `.emptySamples`（:104），且导出目录不新增任何 `.gpx`（:105）——失败必须显式，不得产出损坏/空文件 |
| `testEmptySplitsExposeHonestEmptyState` | `ios/PurePaceTests/RunDetailContentTests.swift:75` | 空分段记录的详情映射：`hasSplits == false`（:79）、`splits` 为空（:80）、摘要给出 `分段 · 0`（:81）——空分段区有明确计数文案，不空白 |
| `testMapsRecordFieldsWithoutRecompute` | `ios/PurePaceTests/RunDetailContentTests.swift:39` | 空 samples 记录（`hasLocationData == false`，:44）的距离位必须等于 `L10n.runDistanceUnavailable` 且文案为「未获取到定位，距离为空」（:45-46），不显示 `0.00` |
| `testDiagnosticsSnapshotReportsVersionSHAAndCallbackCounters` | `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:252` | 版本串 `0.1.0 (1)`（:268）、sha 只展示前 8 位且不泄漏完整值（:269-270）、`原始回调: 12` / `精度过滤丢弃: 12`（:271-272，口径：用例构造值）、未拿到 Always 写「仅前台」（:273）、缺 sha 写「未注入」（:285） |

---

## 7. 门禁为什么全绿（逐条）

| 腿 | 为什么对真机失效 | 代码位置 / 断言名 |
|---|---|---|
| **L1 单测（`swift test` RunCore/Core）** | 断言跑的是**注入时钟 + 显式夹具**。旧引擎的问题不是「算错」，而是「真机没有输入可算」；没有一条用例构造「时钟在走、fix 一条都不来」，所以旧实现永远绿。现在由 `testElapsedTicksWithClockAndZeroLocationSamples`（`RunClockDecouplingTests.swift:60`）显式构造零 fix 场景承担该路径。 | `ios/RunCore/Tests/PurePaceRunCoreTests/RunClockDecouplingTests.swift:60`、`scripts/test-ios.sh:686-704` |
| **模拟器 UI 腿（`RunFlowUITests` 等）** | 每条用例都带 `-uiTestLocation`，该源 `defaultInterval = 1.0` 每秒投一条 fix → 「首条 fix 永不到达」「室内全被 50m 过滤」这两条真机主路径在 UI 腿里不可能出现。 | `ios/PurePaceUITests/RunFlowUITests.swift:29`、`ios/PurePace/Location/RunTestLocationSource.swift:20`、`:96` |
| **CI 分段 1：runflow** | 同上（1Hz 合成源），且分段前 `simctl privacy grant location` 已把授权设为已允许 → 系统弹窗与 `notDetermined` 分支从未被走到。 | `scripts/test-ios.sh:658`（目标列表）、`:606-614`（授权重申） |
| **CI 分段 2：evidence / AX5 / 音频自检** | 同样带 `-uiTestLocation`；这腿断言的是取证截图、可及树、音频会话配置，与定位可用性正交 → 定位全静默时依然全绿。 | `scripts/test-ios.sh:661-664`、`ios/PurePaceUITests/EvidenceCaptureUITests.swift:87` |
| **CI 分段 3：截图浅色** | 截图用例只断言关键元素存在与版式，输入仍是 1Hz 合成源；距离被 `-uiTestLocationTargetMeters` 锁到 canonical 值（如 1.2km → 1 条分段），与真实定位质量无关。 | `scripts/test-ios.sh:670-671`、`ios/PurePaceUITests/RunFlowUITests.swift:607`、`:669` |
| **CI 分段 4：截图深色** | 与分段 3 同构，仅外观切换（`simctl ui … appearance dark`），对定位链路零覆盖。 | `scripts/test-ios.sh:673-681` |

补充口径：四段拆分来自「单次 `xcodebuild` ≤600s」约定，阈值/用例数/断言强度不变（`scripts/test-ios.sh:585-590`、`:149-153`）。
所以「四条 CI 腿全绿」只证明**合成输入下主链路自洽**，不证明真机路径可用——这是输入设计问题，不是环境差异问题。

---

## 8. 判定纪律

1. **禁止**以「真机环境差异」「CoreLocation 在模拟器上不真实」这类结论收尾。CoreLocation 在真机上的行为差异不是解释：
   本次故障的三条主因（计时真源、静默过滤、授权未触发）都是**包内代码可判定**的缺陷，与设备型号、系统版本无关。
2. **每个缺陷必须给出无真机可复现的输入**，且该输入构造的是「错误输入 → 必须红」的反例，不依赖改生产代码才红：

   | 缺陷 | 无真机复现输入 | 判红方式 |
   |---|---|---|
   | 时长寄生采样 | 注入**冻结时钟** + 三条递增样本（`RunClockDecouplingTests.swift:117-130`） | 若时长来自采样时间戳 → `elapsed != 0` → :128 红 |
   | 零 fix 无时长 | 注入时钟推进 5s + **零 location 回调**（`:60-70`、`:93-113`） | 若仍只累加样本时间戳 → `elapsed == 0` → :67-68 / :107-108 红 |
   | 精度静默过滤 | 单条 **65m** fix + 窗口前/后各一次投递（`RunPermissionAndDiagnosticsTests.swift:217-244`） | 窗口内接受 → :235 红；窗口后不接受 → :242 红；计数不对 → :236-237 红 |
   | 授权未触发 | `notDetermined` 连点两次开始（`RunPermissionAndDiagnosticsTests.swift:106-118`） | 不请求或请求两次 → :116 红 |
   | 空样本导出 | 空 samples 记录直接导出（`RunExportStateTests.swift:96`） | 生成文件或落到 `.exported` → 红 |
   | 空样本呈现 | 空 samples 记录的详情映射（`RunDetailContentTests.swift:39`、`:75`） | 距离显示 `0.00` → :45-46 红；空分段无计数文案 → :79-81 红 |

3. 上述断言全部在 `swift test` / 单测目标内运行，**不需要模拟器、不需要设备**；因此「这条只能真机测」在本项范围内不成立。
4. 未验项照写 `pending: 待人现场`（例：真机后台续采、锁屏计时、系统弹窗文案与观感），不得写「真机已验证」。
5. 已知未闭合项：ac-location-error（`didFailWithError` / `locationServicesEnabled` 上报路径）在源码中仍缺席
   （见第 3 节缺口说明），**不列为已闭合**。
