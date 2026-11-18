# Domain: ios-run-resilience

跑步会话的「系统接缝韧性」子域：把**计时真源**、后台定位会话策略与精度降级、系统授权链路、锁屏（protected-data）区间语义、进程重启恢复与**空样本结束语义**做成**可判红断言**。接缝分层：锁屏、应用级恢复、系统授权触发与诊断快照在 App 层（`RunSessionViewModel`、`RunLocationSource`、`RunDiagnostics`，均注入时钟/探针），单调计时真源、度量与恢复入口在 `ios/RunCore`。同一子域维护仓内唯一验证矩阵表 `docs/verification-matrix.md`。

不变量：活跃时长只有一个时间源——`RunMetricsEngine` 注入的 `RunTimeSource`（生产 `ProcessInfo.systemUptime`）；App 层每秒只做一次读数刷新，**不得**再以定位回调推进时长，也不得出现第二套计时。

## 范围

- `ios/PurePace/Location/RunLocationSource.swift`：`endUpdating()` 补 `pausesLocationUpdatesAutomatically = false`，与既有 `allowsBackgroundLocationUpdates` 复位成对。
- `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift`：additive `public private(set) var duplicateSampleCount`，仅在「running 下等时/倒退样本整条丢弃」分支 +1。
- `ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift`：additive `init(restoring:checkpointStore:archiveStore:announcementsEnabled:)`（状态恢复为 `paused`、还原 `announcedSplitIndex`、以 `lastSample` 回填归档单调守卫锚点、按「锚点时间 − 活跃时长」派生 `startedAt` 下界）+ `duplicateSampleCount` 只读转发。
- `ios/PurePace/Run/RunSessionViewModel.swift`：注入 `NotificationCenter` + `restoringCheckpoint`；生产注册两条 protected-data 通知（`RunProtectedDataObservation`，`deinit` 移除 token）映射为 `isProtectedDataLocked`/`protectedDataUnavailableSince`；发布 `duplicateSampleCount`、`didRestoreFromCheckpoint`；新增 `makeRestored(...) throws` 应用级恢复入口。
- `docs/verification-matrix.md`：纯 Markdown 表格单一真源，覆盖全部已声明接缝（含本项新增「单调时钟计时真源」「定位授权链路与诊断」「空样本结束与导出」3 行，均归属本 WI）；无 `pending: 待对应 item 回填` 行、无 `none（缺口）` 行。
- `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`：结构守护按 seams 数组逐条断言「每条接缝恰 1 行」+ pending 0 / 缺口 0 + 归属项 `wi_*`，**不 pin 全局行数**（并发项可各自追加行）；并锁定 Dynamic Type 行的真实符号与证据路径。
- `ios/RunCore/Sources/PurePaceRunCore/RunTimeSource.swift`：`RunTimeSource` 协议（单调 `uptime` 秒）+ 生产实现 `SystemMonotonicTimeSource`；`RunMetricsEngine(clock:)` 与 `RunSessionOrchestrator(timeSource:)` 注入点，`start/resume` 记读数、`pause/finish` 结算、运行态实时读时钟；`ingest(_:)` 只算距离/配速/分段。
- `ios/RunCore/Sources/PurePaceRunCore/RunRecord.swift` / `RunSessionOrchestrator`：additive `sampleCount` / `hasLocationData`（结束页与详情页唯一口径）+ `tick(at:)` 空跑刷新（只出新快照，不改状态、不写 checkpoint）。
- `ios/PurePace/Location/RunLocationSource.swift`：`accuracyThresholdMeters = 50`（正常接受）、`accuracyFallbackWindowSeconds = 15`（降级窗口）、`accuracyFallbackCeilingMeters = 200`（降级上限）三常量均「先定后测」注释；`requestWhenInUseAuthorization()` / `requestAlwaysAuthorization()` 各实例恰一次；`rawCallbackCount` / `filteredCallbackCount` / `lastAcceptedAccuracyMeters` 可归因计数。
- `ios/PurePace/Location/RunLocationSource.swift` 定位失败链路：`RunLocationProviding` / `RunLocationManaging` 各增只读 `locationServicesEnabled`、`lastLocationErrorCode`（协议扩展给默认值，既有 fake 零改动）；`RunLocationManagerHandler.locationManagerDidFail(code:)` 承接 `CLLocationManagerDelegate.didFailWithError`（`CLError` → 原始码，不伪造样本）；`start()` 前置检查系统定位服务关闭时不调 `startUpdatingLocation` 并复位后台标志，正常启动时清空旧错误码；`ios/PurePace/Run/RunLocationReadiness.swift` 的 `resolve(authorization:servicesEnabled:lastErrorCode:)` 把「服务关闭 / 最近失败」并入既有 `.unavailable`（文案键 `run.status.locationUnavailable` + `retry` 出口），`RunSessionViewModel.locationReadiness` 由它派生。
- `ios/PurePace/Run/RunDiagnostics.swift`（新增）与 `SettingsView` 诊断行：单一 `RunDiagnostics` 快照（版本 / 构建期 sha 前 8 位 / 授权 / `accuracyAuthorization` / `locationServicesEnabled` / 已采样本数 / 最近样本时间 / `allowsBackgroundLocationUpdates` / raw 与过滤丢弃计数 / 最近错误 domain + code + 中文描述）+ 一键复制文本。
- `ios/PurePace/Location/RunLocationSource.swift` 搜索与降级结算：`RunLocationErrorInfo`（`CLError` domain / code / 中文描述）与 `lastLocationError`、`restart()`（只 stop → start 数据源，不碰计时与样本）、`fallbackTimer` 到点主动 `flushPendingFallbackIfDue()`（>50m fix 不再等下一个回调才结算）。
- `ios/PurePace/Run/RunLocationReadiness.swift`：`RunLocationSearchState`（`idle` / `searching` / `timedOut(RunLocationSearchFailureReason)`，`timeoutSeconds = 30` 带推导注释）与四类原因（`unauthorized` / `servicesDisabled` / `accuracyFiltered` / `noCallbacks`），全部输入来自既有计数器与授权 / 服务开关。
- `ios/PurePace/Run/RunSessionViewModel.swift`：`timeSource` 注入与 `tick()`；「开始」在 `notDetermined` 时触发系统 WhenInUse 请求，跑步进行中升级 Always，denied/restricted 不进记录态并给「去系统设置」；`recordingStartedAt` + `locationSearchState` / `locationSearchMessage` 派生状态；`retryLocation()` 在 `.unavailable` 或搜索超时时只 `restart()` 定位会话。
- `ios/PurePace/Run/RunView.swift`：运行态 1s ticker 只重读时长；记录态三态提示（搜索中胶囊 / 30s 超时原因 + `run.retryLocation` 按钮 / 已有 fix 不提示），「降级精度」沿用既有 inline 胶囊；结束页新增采样点数，无定位时距离位写「未获取到定位」而非 0.00。
- `ios/PurePace/History/RunDetailContent.swift`、`RunDetailView.swift`、`RunExportState.swift`：详情页采样点数与空样本距离语义；导出新增 `.emptySamples` 分支（明确提示、零新文件）。
- `ios/project.yml`：`postBuildScripts` 在构建期把 commit sha 前 8 位写入已装包 `PurePaceBuildSHA`（运行时绝不读 git）。
- `docs/root-cause-core-loop-device.md`（根因说明，必交）+ `docs/distribution/manual-test-guide.md` 复测增量段。
- `scripts/check-ios-shell.sh`：必需新增 identifier 清单并入 `run.locationSearchTimeout` / `run.retryLocation`（冻结计数 56 → 58，新增放行自检 59），`RunFlowUITests` 用例数下限 7 → 9。
- 测试落点：`ios/RunCore/Tests/PurePaceRunCoreTests/RunClockDecouplingTests.swift`（新增）、`RunMetricsEngineTests.swift`、`OrchestratorRestoreTests.swift`、`ResumeContractTests.swift`、`RunSessionDecisionTests.swift`、`RunSessionOrchestratorTests.swift`、`RunSampleDedupTests.swift`；`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift`（新增）、`RunSessionContractTests.swift`、`RunSessionLockTests.swift`、`RunSessionRestoreTests.swift`、`RunLocationSourceTests.swift`、`RunDetailContentTests.swift`、`RunExportStateTests.swift`。

## 验收

### A. 定位会话与更新策略

- ac-loc-bg-flags-running: `authorizedAlways` 下 `start()` 后注入 manager 的 `allowsBackgroundLocationUpdates == true` 且 `pausesLocationUpdatesAutomatically == false`；`stop()` 后两者均为 `false`（含 `pauses` 复位，不只断 `allows`）。
- ac-loc-bg-flags-counterexample: 同 commit 独立反例，`stop()` 前把两个开关预置为脏值，`stop()` 后必须被复位为 `false`；生产漏赋值/漏复位该反例独立判红，不依赖改生产代码。
- ac-loc-manager-delegate-retained: `RunLocationSource()` 存活期间对 `SystemLocationManager.underlyingManager` 与其 `delegate` 的弱引用读取均非 `nil`，`source.retainedManager === manager`；释放 source 后两个弱引用变 `nil`（证明强引用链真实存在）。
- ac-plist-built-app-readback: 以 `Data` + `PropertyListSerialization` 读**构建产物 App 的 `Info.plist` 本体**（不读 `ios/project.yml`），断言 `UIBackgroundModes` 为字符串数组且同时含 `location` 与 `audio`；同一读取路径对缺任一模式的临时 plist 必须独立判红。
- ac-auth-always-upgrade: `notDetermined` 首次 `start()` 只请求 WhenInUse；`authorizedWhenInUse` 时 `start()` 发起一次 Always 升级且同一实例不重复请求；升级后 `backgroundCapable == true`、降级提示 `nil`。
- ac-auth-wheninuse-degraded: 授权落 `authorizedWhenInUse` 时 `backgroundCapable == false` 且 `backgroundDegradationHint != nil`；同 commit 反例断言「降级态若 capable 为 true 或缺提示即判红」。

### B. 锁屏语义（模拟器层，禁写「真机已验证」）

- ac-lock-running-continues: `running` 下注入 `protectedDataWillBecomeUnavailable`（注入时钟 `tLock`），用 fake location source 以 1 Hz 连续喂 N≥10 个递增采样；每次摄入后 `state == .running`，`metrics.distance` 与 `elapsed` 严格递增，不得发生任何状态迁移。
- ac-lock-sample-cadence: 锁定区间内被接受样本时间戳严格单调递增，相邻样本最大空洞 `<= maximumSampleGapSeconds`（初值 `2.0`）；阈值必须在首次跑测试**之前**写入代码常量与注释（fixture 1.0 s 采样 × 2 倍调度抖动容差），并声明不构成真机采样频率承诺；禁止看红后调阈值。
- ac-lock-dedup-samples: 正常锁屏区间去重计数为 `0`；注入与上一接受样本同时间戳（坐标可不同）的重复样本必须被丢弃——`distance`/`elapsed`/`splits` 不变、计数 `+1`；整段重复序列同样全部丢弃且计数与丢弃条数一致。
- ac-lock-unlock-no-replay-no-reset: 注入 `protectedDataDidBecomeAvailable`（`tUnlock`）后 `state`/`distance`/`elapsed`/`splits` 与解锁前一刻完全相等（不补样本、不增 checkpoint 行、不重置计时）；解锁后下一条样本使 `elapsed` 按样本时间差继续增长，不归零、不按 `tUnlock` 重算。
- ac-lock-handler-observable: ViewModel 对锁屏区间有注入式可测状态（注入 `now` 与 `NotificationCenter`），生产注册两条 protected-data 通知；断言锁定期间为「已锁定」、解锁后复位。
- ac-lock-counterexample-independent: B 每条断言都有同 commit 独立反例（锁屏后状态被误改、重复样本注入、解锁重置计时、锁状态缺失），均不改生产代码即可判红。

### C. 进程重启恢复（必须到应用层）

- ac-restart-restores-metrics: 跑到 ≥2 个完整分段并落盘 checkpoint；丢弃全部内存实例后用**同一文件、全新 `RunCheckpointStore` + 全新 orchestrator + 全新 ViewModel** 构造；恢复后 `state == .paused`，`distance`/`elapsed`/`splits`（index、distance、duration）与最后一条有效 checkpoint 逐项相等且均不为 0。
- ac-restart-last-sample: 恢复后的锚点与 checkpoint `lastSample`（经纬度、时间戳）一致；`resume(at: tR)` 后 `<=` 锚点的样本被拒绝（度量不变），晚于锚点的首条样本只重建位置锚点、不累计距离。
- ac-restart-timer-continues: `resume(at: tR)` 后喂 `tR + Δ` 的样本，`elapsed == 恢复值 + Δ`（容差 1e-6）且严格大于恢复值，`distance` 从恢复值继续累加；覆盖「非归零」与「非重算」。
- ac-restart-bad-tail: checkpoint 文件末尾为不完整 JSON 行时，新进程恢复入口静默丢弃坏尾、以上一条完整有效记录恢复，度量与坏尾前最后一条有效记录相等且不抛错。
- ac-restart-middle-corruption: 非尾行损坏时必须暴露 `RunCoreError.corruptedCheckpoint`（throwing 或 ViewModel `errorMessage`），不得静默构造零度量会话。
- ac-restart-viewmodel-e2e: 至少一条经 `RunSessionViewModel`（非仅 store）的端到端用例：新进程构造后由 fake location source 继续供点，断言 `state`/`metrics` 与旧 checkpoint 连续。
- ac-restart-counterexample-independent: 坏尾、中间损坏、非法锚点等反例各有同 commit 独立用例，独立判红且不改生产代码。

### D. 计时真源与空样本语义

- ac-clock-tick: 注入「已授权但零 location 回调」场景，`start` 后推进注入时钟 5s，`metrics.elapsed` / `RunRecord.activeDuration` ≥ 4.5s（实测 5.0，容差 1e-9），`distance == 0`，结束页文案不再是 00:00；断言不依赖真实 sleep。
- ac-clock-pause: 暂停期间推进注入时钟不增加活跃时长（3.0 → 3.0），`resume` 后再推进 2s 得 5.0；前后台切换不重置。
- ac-clock-single-source: 时钟冻结时喂 3 条严格递增样本，`distance` 增长而 `elapsed` 恒为 0 且 `averagePace == nil`——时长绝不来自采样回调（反例护栏，不改生产代码即可判红）。
- ac-finish-empty: samples 为空时 `finish` 必须产出 `RunRecord`：`activeDuration` 由时钟结算 > 0、`sampleCount == 0`、`hasLocationData == false`、`distance == 0`，且归档目录恰含该记录。
- ac-finish-normal: 有 samples 时结束页显示 距离 / 时长 / 配速 / 采样点数，详情页地图、分段与记录逐项一致。
- ac-gpx-empty: 空 samples 导出走 `RunExportState.Phase.emptySamples` 明确提示，`RunArchiveError.emptySamples` 不产生任何新文件（`testExportEmptySamplesThrowsAndWritesNoFile`）。

### E. 系统授权链路、定位降级与诊断

- ac-permission-request-when-in-use: `notDetermined` 时点「开始」必须真实调用 `requestWhenInUseAuthorization()` 恰 1 次（spy 断言），App 内「行踪轨迹敏感个人信息」告知同意不得替代或短路它。
- ac-permission-request-always: 取得 WhenInUse 且跑步进行中调用 `requestAlwaysAuthorization()` 恰 1 次；未拿到 Always 时 UI 写明「仅前台记录」；`UIBackgroundModes` 含 `location` 与 `allowsBackgroundLocationUpdates=true` 二者缺一即判红。
- ac-permission-denied-blocks-recording: `denied` / `restricted` 不进入记录态，给原因文案 + 「去系统设置」按钮（`UIApplication.openSettingsURLString`），回前台（`scenePhase == .active`）自动复检授权并刷新状态。
- ac-location-fallback: 自 `startUpdatingLocation` 起 15s 内无 ≤50m fix 时，接受窗口内「最佳可得」且 ≤200m 的 fix 并标记其 accuracy（`lastAcceptedAccuracyMeters`）；超过 200m 或窗口未到一律继续等待——护栏不得放宽到接受任意精度。
- ac-loc-degrade: 窗口到点由 `RunLocationSource` 自带的一次性定时器主动结算，**不依赖「必须再来一个回调」**；只来一条 >50m fix 且此后零回调时，15s 到点仍被接受、距离累计并标「精度降级」（`isAccuracyDegraded` + `run.degradedAccuracy`），旧「等下一个回调才结算」的静默丢弃路径已删除（`testSingleImpreciseFixAcceptedAtWindowWithoutAnotherCallback`，反例：窗口前一刻仍为空）。
- ac-location-error: 系统定位失败（`didFailWithError`，覆盖 `.denied` 与 `.locationUnknown`）必须落进状态而不静默：注入失败后 `RunLocationProviding.lastLocationErrorCode` 等于 `CLError` 原始码、`locationReadiness == .unavailable`（文案键 `run.status.locationUnavailable`、`nextAction == .retry`、跑步页 `notice == .locationUnavailable`），计时不回退；重新 `start()` 成功必须清空旧错误码并回到 `.ready`（`testLocationFailureAndServicesOffSetUnavailableAndExposeCopy` / `testRecoveryAfterLocationFailureReturnsReady`）；反例已实测判红：断开 `locationManagerDidFail` → `lastLocationErrorCode` 转发后从 `:281` 起共 9 处断言红，`start()` 恢复时不清旧错误码后 `:346/:347/:348` 红（证据 `docs/evidence/wi_intake_a443ff461a4b5787/logs/mutation-b.log` / `mutation-c.log`）。
- ac-services-disabled: `locationServicesEnabled == false` 时 `start()` 不得调用 `startUpdatingLocation`（计数不变），且 `locationReadiness == .unavailable`、呈现 zh-Hans「定位暂不可用」文案与既有 retry 出口（复用 `run.status.locationUnavailable`，不新增文案键）；反例已实测判红：删整段前置检查（读取 + 回写 + guard）后 `:320/:321` 红；**只删 `guard` 而保留回写时仍 `0 failures`**（`beginUpdating()` 自带 `!isUpdating` 幂等，首轮 `start()` 已置真，故 `:315-319` 调用计数断言不能单独判红），真实判红点是状态/文案断言，不得声称计数断言可单独判红。
- ac-diagnostics: 设置页诊断区只读单一 `RunDiagnostics` 快照：版本 + 构建期写入的 sha 前 8 位（缺失显式写「未注入」）+ `CLAuthorizationStatus` + `accuracyAuthorization` + `locationServicesEnabled` + 已采样本数 + 最近样本时间 + `allowsBackgroundLocationUpdates` + raw 回调数与精度过滤丢弃数 + 最近错误（`RunLocationErrorInfo` 的 domain / code / 中文描述，无错误写「无」）；一键复制文本，中文标签与可见文案语义一致。
- ac-loc-diagnostics: 上述字段全部来自既有单一来源（`BundleInfoProviding`、授权探针、编排器采样序列、`RunLocationSource` 计数器 / 服务开关 / `lastLocationError`），快照自洽且有断言（`testDiagnosticsSnapshotReportsVersionSHAAndCallbackCounters` / `testDiagnosticsSnapshotIsSelfConsistentAndSingleSourced`）；仓内无第二套 raw 回调计数真源。
- ac-loc-searching: 记录态零可用 fix 时先显示「正在搜索定位」（`run.waitingLocation` 胶囊），计时与距离区不空白、不静默；`RunLocationSearchState.resolve(isRunning:hasLocationData:elapsedSinceRecording:authorization:servicesEnabled:rawCallbackCount:filteredCallbackCount:timeout:)` 是唯一派生入口。
- ac-loc-timeout: 记录态 30s 到点按四类可归因原因之一给可读文案（未授权 / 系统定位服务关闭 / 精度长期不足 / 无回调，禁「系统限制」兜底）并挂 `run.locationSearchTimeout` + `run.retryLocation` 重试入口；点重试只 `locationSource.restart()`（stop → start），计时值与已累计距离 / 样本不变（`testLocationSearchStateTimesOutWithAttributableReason` / `testTimeoutRetryRestartsLocationWithoutResettingSession`）。

### F. 冻结约束与验证矩阵

- ac-verification-matrix: `docs/verification-matrix.md` 为纯 Markdown 表格（无正文段落），表头逐字 `| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |`，每条数据行 6 列且单元格非空；`pending: 待对应 item 回填` 与 `none（缺口）` 均出现 0 次；已声明接缝逐条存在且**每条恰 1 行**（后台定位 / 锁屏 / 重启 / Info.plist / TTS / duck / GPX / 竖屏 / Dynamic Type / 设计 token / 隐私政策正文真源 / 轨迹数据单独同意门 / 轨迹敏感信息单独同意门 / 可安装 APK 产物与获取路径 / iOS 权威腿执行 ios/Core / 单调时钟计时真源 / 定位授权链路与诊断 / 空样本结束与导出），不 pin 全局行数，并发项可各自追加。
- ac-matrix-rows-real-names: 回填行的「断言名」「反例」列只写 main 上真实存在的测试/门禁标识，禁编造；TTS 含 `testEachKilometerAnnouncedExactlyOnceInOrder`/`testResumeCatchUpEmitsAtMostOne`/`testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates` 与反例 `testResumeCatchUpDoesNotReplayEachMissingKilometer`；duck 含 `testEndAnnouncementRevokesDuckWhenActivationDucked`/`testEndAnnouncementSeparatesDeactivationFromDuckRevocation`/`testApplyingDefaultConfigurationReadsBackFromRealSession` 与反例 `testDuckRevokedDiffersFromSessionDeactivatedWhenActivationSkipsDuck`；GPX 含 `fixture-fields-match`/`red-proof-missing-ele`/`red-proof-namespace`/`testExportRoundTripPreservesEveryPoint`；竖屏含 `ac-portrait-orientation-lock`；设计 token 含 `testPolicyThresholds`/`ac-design-tokens`。
- ac-matrix-status-column-measured: 「现状」列写实测口径与阈值来源而非结论词——GPX 行出现 `1e-6`、`0.11 m/格`、`恰为 4`、`不设数量容差`；竖屏行写出 `UISupportedInterfaceOrientations=UIInterfaceOrientationPortrait` 与 `TARGETED_DEVICE_FAMILY=1` 并注明源码 `project.yml` 与构建产物 `Info.plist` 双向实测；设计 token 行出现 `80 = 2.5 × Spacing.xl`、`16 = Spacing.md`、`2026-11-11`（先定后测）；计时 / 授权 / 空样本三行写明注入时钟、50m/15s/200m 与「零采样仍结算时长」口径，断言名为真实用例（`testElapsedTicksWithClockAndZeroLocationSamples` 等）。
- ac-matrix-guard-counts: `DocsVerificationMatrixTests` 保留「表头逐字 / 6 列 / 非空单元格」结构断言与仓库根 `VERSION` 定位，断言 `pending == 0`、`缺口 == 0`、每个已声明接缝恰 1 行、归属项为 `wi_*`；Dynamic Type 行按真实符号断言（`testAX5PrimaryActionMeetsMinimumTapTarget` / `testFixed32ptActionHeightCounterexample` / 证据路径 `ios/PurePaceTests/DynamicTypeLayoutTests.swift` 与 `ios/PurePace/Design/PrimaryActionLayoutPolicy.swift`）。
- ac-identifier-freeze-additive: `scripts/check-ios-shell.sh` 的 identifier 集合只增不改：既有 33 项冻结集零改名/删除，累计已增至 9 项新增（`run.sampleCount`/`run.waitingLocation`/`run.degradedAccuracy`/`settings.diagnostics`/`settings.diagnostics.copy`/`runDetail.sampleCount`/`runDetail.exportEmpty`/`run.locationSearchTimeout`/`run.retryLocation`）带中文可读 label，`--self-test` 计数下限 49 → 58 同步（新增放行自检 59）；`RunFlowUITests` 用例数下限同步 7 → 9（新增定位搜索超时/重试与精度降级可见各 1 条），删任一条即判红。
- ac-freeze-gates: `.munk/code-gates.json` 只增不改既有门语义，23 个 gate 全退 0；任何新增接缝不得让既有 gate 变红，也不得删腿、加 `continue-on-error` 或提高 timeout。
- ac-copy-single-source: 新增用户可见文案（正在搜索定位 / 四类搜索超时原因 / 重试定位 / 诊断「定位服务」「最近错误」/ 精度降级 / 距离未获取 / 采样点数 / 详情空样本导出 / 诊断标签）全部经 `L10n` 落 `Resources/Localizable.xcstrings`，零裸中英文混排；`DesignTokens` 色板、字号、间距零新增（搜索/超时提示沿用既有胶囊与 `warning`/`warningSoft` 令牌）。
- ac-no-device-claims: 不新增真机流程、XCUITest 设备用例或设备脚本；digest、矩阵表与代码注释不得出现「真机已验证」类结论，真机项保持 `pending: 待人现场`。

### G. 定位失败断言的变异红证（证据项口径）

- ac-mutation-red: 三种变异各自使 `testLocationFailureAndServicesOffSetUnavailableAndExposeCopy` / `testRecoveryAfterLocationFailureReturnsReady` 红，日志含失败断言原文与 `XCTAssert` 位置——(a) 删整段 `servicesEnabled` 前置检查 → `:320/:321`；(b) 断开 `locationManagerDidFail` → `lastLocationErrorCode` 转发 → `:281` 起 9 处；(c) `start()` 恢复时不清旧错误码 → `:346/:347/:348`；同一 commit 未变异时两用例 `Executed 2 tests, with 0 failures`（`** TEST SUCCEEDED **`）。变异只在仓库外 `/tmp` 副本内做。
- ac-mutation-boundary-honest: 断言敏感度边界如实记录，不把「计划中的判红」写成实测——只删 `guard servicesEnabled` 保留回写时判绿（`beginUpdating()` 的 `!isUpdating` 幂等），该点在矩阵与证据 README「发现」节同口径出现。
- ac-matrix-row: 矩阵「定位失败与服务关闭的两条断言红证」行恰 1 行、6 列非空，归属项为本 WI，证据路径逐条指向仓内真实文件（`docs/evidence/{wi}/logs/*.log`）；原「定位授权链路与诊断」行保留并追加这两条断言名，不再以 pending/缺口充当结论。
- ac-no-prod-change: 相对基线 commit `90bb205` 的改动只含 `docs/`（矩阵 + 证据）与 `.munk/`（change pack），`ios/**`、`VERSION`、CI 工作流、`shared/` 零改动；HEAD 未变，`git status` 仅新增证据目录与 change pack。

## 非目标

- 不改设计 token / 版式 / 截图；用户可见文案只经 `L10n` 增量新增，不改既有键名与语义。
- 不新增真机场、XCUITest 设备用例、设备脚本或 CI 重腿；真机定位授权/锁屏/后台定位恒为 `pending: 待人现场`，agent 不做真机验收。
- 不定义「重启后结束会话」的归档 `startedAt` 新语义、不改归档格式与 `formatVersion`；恢复入口**不接生产启动流程**（`ContentView`/App 启动不自动恢复），故重启后归档只含重启后样本、`startedAt` 为下界，均为已知缺口。
- 不重写既有 RunCore / ViewModel / Location 用例；不删腿、不加 `skip`、不加 `continue-on-error`、不提高 timeout。
- 不改 GPX 编码、文件名规则、音频播报与状态迁移表；锁屏不得引入「自动 pause」「自动 resume」「补样本回放」。
- 不新增诊断展示页、遥测上传或第二个计时真源；诊断数据只读既有单一来源。
- 不做性能优化、后台续跑调度（`BGTaskScheduler`）；不维护第二张矩阵表；不推 tag、不建 Release、不动 `VERSION`。
- 不改 `RunLocationReadiness.resolve` 判定顺序：`denied + 定位服务关闭` 仍压成 `.unavailable` + `retry`（丢 `permissionDenied` 与「去系统设置」出口），属已记账的已知局限，另项再议。

## 实现约束

- **单一时钟真源**：活跃时长只由 `RunMetricsEngine` 注入的 `RunTimeSource` 驱动，`RunSessionOrchestrator(timeSource:)` 与 `RunSessionViewModel(timeSource:)` 串同一实例；App 层 `tick()` 每秒只重读快照，不改状态、不写 checkpoint；`ingest(_:)` 绝不累加时长。
- **additive 优先级**：`RunSessionOrchestrator.init(checkpointStore:archiveStore:announcementsEnabled:)`、`RunSessionMachine` 既有 public 契约与语义不变，新参数带默认值；恢复入口失败必须抛错或可观测，不得静默零度量恢复。
- **唯一摄入路径**：样本仍经 `RunSessionViewModel.ingest` → `RunSessionOrchestrator.ingest` → `RunMetricsEngine.ingest`；锁屏通知只写可观测状态，不触发 pause/resume/finish、不停定位、不补投样本；去重计数不改变既有 drop 语义与度量公式。
- **权限顺序不可短路**：`notDetermined` 时「开始」先触发系统 WhenInUse；取得 WhenInUse 后在跑步进行中升级 Always；App 内告知同意只写本地键，不得替代或排在系统请求之前；`denied`/`restricted` 在状态机层被挡在记录态之外，回前台复检授权。
- **精度可归因**：`RunLocationSource` 的 50m 接受阈值、15s 降级窗口、200m 降级上限三常量在首次跑测试前写入代码注释并说明推导；raw 回调与过滤丢弃分别计数，不合并成一个「采样数」。
- **诊断单一快照**：`RunDiagnostics` 全部字段来自既有来源（`BundleInfoProviding`、授权探针、编排器采样序列、定位源计数器），构建期 sha 由构建期脚本写入 Info.plist，运行时禁读 git；文案中文化留在 `L10n` + 枚举映射，不新建第二套计时或采样账本。
- **RunCore 边界**：`ios/RunCore` 只 `import Foundation`，源码/测试不得出现 `CoreLocation|UIKit|SwiftUI|AVFoundation|URLSession|Timer` 字样（含注释）、夹具令牌与根 `VERSION` 字面值。
- **时间与测试纪律**：时间一律由注入时钟/样本时间戳提供，测试禁用真实 sleep 与墙钟断言；临时目录 + `defer` 清理；XCTest（禁 `import Testing`）；真实落盘断言必须用新 store 实例从磁盘读回。
- **阈值先定后测**：所有数值阈值（含 `maximumSampleGapSeconds`、`accuracyFallbackWindowSeconds`、`accuracyFallbackCeilingMeters`）必须在首次跑相关测试前写入代码与注释并说明推导依据，禁止看红后调阈值或反向拟合。
- **反例纪律**：反例与正例同 commit、可独立判红、不改生产代码、不手工改阈值；反例测试是长期资产，不是一次性脚本。
- **矩阵纪律**：断言名/反例名逐条取自 main 已交付代码与 `scripts/**` 门禁的真实标识，禁编造、禁把「计划中的测试」写成实测；证据路径必须指向仓库内真实文件（TTS：`AnnouncementSchedulerTests`/`AnnouncementSpeakerTests`；duck：`AudioSessionAdapterTests`/`AnnouncementSpeakerTests`；GPX：`RunGPXExporterTests`/`GPXCodecTests`/`scripts/check-gpx-export.sh`；竖屏：`ios/project.yml`/`scripts/check-ios-shell.sh`；设计 token：`RunLayoutBalancePolicy`/`LocalizationPolicyTests`/`DesignTokensTests`/`scripts/check-ios-shell.sh`；计时 / 授权 / 空样本：`RunClockDecouplingTests`/`RunPermissionAndDiagnosticsTests`/`RunDetailContentTests`）。缺口行只许写 `none（缺口）`，不得以 `pending` 充当缺口。

## 最近交付证明

- 最近一次：`wi_intake_9681718e12c7b31c` — 定位搜索三态可归因：`RunLocationSearchState`（30s 窗口 + 四类原因）与 `RunView` 搜索中 / 超时原因 + `run.retryLocation` 出口；`retryLocation()` 改为只 `restart()` 定位会话，计时与已累计样本不动；   `RunLocationSource` 删除「等下一个回调才结算」的静默丢弃路径，改由一次性 `fallbackTimer` 到点结算；诊断快照补 `locationServicesEnabled` 与最近错误 domain / code / 中文描述，仍单一来源。L1 侧新增 `testSingleImpreciseFixAcceptedAtWindowWithoutAnotherCallback`、`testLocationSearchStateTimesOutWithAttributableReason`、`testTimeoutRetryRestartsLocationWithoutResettingSession`、`testDiagnosticsSnapshotIsSelfConsistentAndSingleSourced`、`testLastSampleTimeNeverRegresses`，模拟器 UI 新增超时/重试与降级可见两条。
- 最近一次（文档项）：`wi_intake_500f9d48a49c1315` — 距离恒 0 四分支归因（零回调 / 精度过滤丢弃 / 降级窗口吞掉 / 静置同坐标）+ 三态读数签名 + 读屏协议 + W1 五条断言的 `/tmp` 变异红证（`mutation-1..5` 退出码 65，未变异对照 `Executed 5 tests, with 0 failures`）；docs-only，`ios/**` 与 `scripts/**` 零 diff，契约见同域 `three-state-readings.md`。
- 记账与未闭合：`RunLocationSearchState.resolve` 仍先判授权再判服务，`denied + 服务关闭` 归 `unauthorized`；真机三态 × ≥30s 读数与真机定位授权/锁屏/后台采样恒为 `pending: 待人现场`。
- 前置同域交付：`wi_intake_a443ff461a4b5787` 定位失败链路变异红证；`wi_intake_695f725dbf554509` 定位失败链路落地（`didFailWithError` → `lastLocationErrorCode`、`start()` 服务关闭前置检查、`RunLocationReadiness.resolve` 并入 `.unavailable`）；`wi_intake_fe5ab0a5c47745ac` 核心闭环真机零可用修复。
- 边界：Android 只保证同一主链路不回退，未做对等功能面。
