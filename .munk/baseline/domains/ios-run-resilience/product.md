# Domain: ios-run-resilience

跑步会话的「系统接缝韧性」子域：把后台定位会话策略、锁屏（protected-data）区间语义与进程重启恢复做成**可判红断言**，只补断言与 additive 接口，不新增产品行为。接缝分层：锁屏与应用级恢复在 App 层（`RunSessionViewModel` 及其注入的 `NotificationCenter`/`now`），纯逻辑恢复入口与去重计数在 `ios/RunCore`。同一子域维护仓内唯一验证矩阵表 `docs/verification-matrix.md`。

## 范围

- `ios/PurePace/Location/RunLocationSource.swift`：`endUpdating()` 补 `pausesLocationUpdatesAutomatically = false`，与既有 `allowsBackgroundLocationUpdates` 复位成对。
- `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift`：additive `public private(set) var duplicateSampleCount`，仅在「running 下等时/倒退样本整条丢弃」分支 +1。
- `ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift`：additive `init(restoring:checkpointStore:archiveStore:announcementsEnabled:)`（状态恢复为 `paused`、还原 `announcedSplitIndex`、以 `lastSample` 回填归档单调守卫锚点、按「锚点时间 − 活跃时长」派生 `startedAt` 下界）+ `duplicateSampleCount` 只读转发。
- `ios/PurePace/Run/RunSessionViewModel.swift`：注入 `NotificationCenter` + `restoringCheckpoint`；生产注册两条 protected-data 通知（`RunProtectedDataObservation`，`deinit` 移除 token）映射为 `isProtectedDataLocked`/`protectedDataUnavailableSince`；发布 `duplicateSampleCount`、`didRestoreFromCheckpoint`；新增 `makeRestored(...) throws` 应用级恢复入口。
- 测试落点：`ios/PurePaceTests/RunSessionLockTests.swift`、`RunSessionRestoreTests.swift`、`RunLocationSourceTests.swift`（补强）；`ios/RunCore/Tests/PurePaceRunCoreTests/OrchestratorRestoreTests.swift`、`RunSampleDedupTests.swift`、`DocsVerificationMatrixTests.swift`。
- `docs/verification-matrix.md`：纯 Markdown 表格单一真源，覆盖 10 条接缝；B/C 归属的 6 行已按 main 上真实符号回填，终态为 9 行实测 + 1 行显式缺口（Dynamic Type），不再有 `pending: 待对应 item 回填`。
- `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`：结构守护同步放宽为「10 条接缝逐条存在」+ 计数断言（pending 0 / 缺口 1 / 实测 9），不再要求旧 6 项标 pending。

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

### D. 冻结约束与验证矩阵

- ac-verification-matrix: `docs/verification-matrix.md` 为纯 Markdown 表格（无正文段落），表头逐字 `| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |`，数据行恰 10 条、每行 6 列且单元格非空；`pending: 待对应 item 回填` 出现 0 次；10 条接缝逐条存在（后台定位 / 锁屏 / 重启 / Info.plist / TTS / duck / GPX / 竖屏 / Dynamic Type / 设计 token），其中「Dynamic Type」为唯一缺口行（「现状」含 `缺口：本波未做（预算取舍）`，「断言名」「反例」两列均为 `none（缺口）`），其余 9 行为实测行。
- ac-matrix-rows-real-names: 6 条回填行（TTS / duck / GPX / 竖屏 / 设计 token）的「断言名」「反例」列只写 main 上真实存在的测试/门禁标识，禁编造；TTS 含 `testEachKilometerAnnouncedExactlyOnceInOrder`/`testResumeCatchUpEmitsAtMostOne`/`testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates` 与反例 `testResumeCatchUpDoesNotReplayEachMissingKilometer`；duck 含 `testEndAnnouncementRevokesDuckWhenActivationDucked`/`testEndAnnouncementSeparatesDeactivationFromDuckRevocation`/`testApplyingDefaultConfigurationReadsBackFromRealSession` 与反例 `testDuckRevokedDiffersFromSessionDeactivatedWhenActivationSkipsDuck`；GPX 含 `fixture-fields-match`/`red-proof-missing-ele`/`red-proof-namespace`/`testExportRoundTripPreservesEveryPoint`；竖屏含 `ac-portrait-orientation-lock`；设计 token 含 `testPolicyThresholds`/`ac-design-tokens`。
- ac-matrix-status-column-measured: 「现状」列写实测口径与阈值来源而非结论词——GPX 行出现 `1e-6`、`0.11 m/格`、`恰为 4`、`不设数量容差`；竖屏行写出 `UISupportedInterfaceOrientations=UIInterfaceOrientationPortrait` 与 `TARGETED_DEVICE_FAMILY=1` 并注明源码 `project.yml` 与构建产物 `Info.plist` 双向实测；设计 token 行出现 `80 = 2.5 × Spacing.xl`、`16 = Spacing.md`、`2026-11-11`（先定后测）。
- ac-matrix-guard-counts: `DocsVerificationMatrixTests` 保留「表头逐字 / 恰 10 条接缝 / 6 列 / 非空单元格」结构断言与仓库根 `VERSION` 定位，并断言 `pending == 0`、`缺口 == 1`、`实测 == 9`；缺口行以 `缺口` / `none（缺口）` 识别且必须落在 Dynamic Type。
- ac-matrix-scope-frozen: 本项 `git diff --name-only` 仅含 `docs/verification-matrix.md` 与 `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`；前 4 行（A 归属）内容不变。
- ac-freeze-identifiers: `scripts/check-ios-shell.sh` 可及 identifier 冻结清单仍 33 项，零新增/改名/删除；`git diff` 无 `accessibilityIdentifier(...)` 改动。
- ac-freeze-gates: `.munk/code-gates.json` 仍 22 个 gate，不删不增且全退 0；新增矩阵表不得让任何既有 gate 变红。
- ac-no-ui-or-asset-diff: 不改 `RunView`/`History/*`/`Settings/*`/`Design/*`/`Localizable.xcstrings`/截图/`shared/`；`git diff --stat` 只含本项 session/location/RunCore 源码、测试与 `docs/verification-matrix.md`。
- ac-no-new-business-semantics: 不新增用户可见文案/identifier；不改 GPX/音频/状态迁移表/度量公式/checkpoint 格式版本与归档契约；锁屏不得引入「自动 pause」「自动 resume」「补样本回放」。
- ac-no-device-claims: 不新增真机流程、XCUITest 设备用例或设备脚本；digest、矩阵表与代码注释不得出现「真机已验证」类结论，真机项保持 `pending: 待人现场`。

## 非目标

- 不改任何 UI、设计 token、排版、截图、可及 identifier 与用户可见文案；不改 GPX 导出、音频播报、归档格式、checkpoint JSONL 字段或 `formatVersion`。
- 不新增真机场、XCUITest 设备用例、设备脚本或 CI 重腿；真机锁屏/后台定位恒为 `pending: 待人现场`。
- 不定义「重启后结束会话」的归档 `startedAt` 新语义、不改 `RunRecord`/`RunArchiveStore` 契约；恢复入口**不接生产启动流程**（`ContentView`/App 启动不自动恢复），故重启后归档只含重启后样本、`startedAt` 为下界，均为已知缺口。
- 不重写既有 110+ RunCore 用例、既有 ViewModel/Location 用例或 `scripts/**` 门禁；不新增 gate。
- 矩阵回填不改 `ios/PurePace/**` 生产代码（含 `RunLayoutBalancePolicy`/`RunView`/`DesignTokens`）、不改 `.github/workflows/ios.yml` 与 `.munk/code-gates.json`、不新增门禁、不改 `docs/` 下其他文件；不补 Dynamic Type 实现或动态字号断言（预算取舍，矩阵如实记为缺口，禁虚标实测）。
- 不做性能优化、定位精度策略调整、后台任务/续跑调度（`BGTaskScheduler`）；不维护第二张矩阵表。

## 实现约束

- **additive 优先级**：`RunSessionOrchestrator.init(checkpointStore:archiveStore:announcementsEnabled:)`、`RunSessionMachine`、`RunMetricsEngine` 既有 public 契约与语义不变；恢复入口失败必须抛错或可观测，不得静默零度量恢复。
- **唯一摄入路径**：样本仍经 `RunSessionViewModel.ingest` → `RunSessionOrchestrator.ingest` → `RunMetricsEngine.ingest`；锁屏通知只写可观测状态，不触发 pause/resume/finish、不停定位、不补投样本；去重计数不改变既有 drop 语义与度量公式。
- **RunCore 边界**：`ios/RunCore` 只 `import Foundation`，源码/测试不得出现 `CoreLocation|UIKit|SwiftUI|AVFoundation|URLSession|Timer` 字样（含注释）、夹具令牌与根 `VERSION` 字面值；恢复语义不得引入第三方依赖。
- **时间与测试纪律**：时间一律由注入时钟/样本时间戳提供，测试禁用 `Date()` 现时与真实通知投递时序；临时目录 + `defer` 清理；XCTest（禁 `import Testing`）；真实落盘断言必须用新 store 实例从磁盘读回。
- **阈值先定后测**：所有数值阈值（含 `maximumSampleGapSeconds`）必须在首次跑相关测试前写入代码与注释并说明推导依据，禁止看红后调阈值或反向拟合。
- **反例纪律**：反例与正例同 commit、可独立判红、不改生产代码、不手工改阈值；反例测试是长期资产，不是一次性脚本。
- **矩阵回填纪律**：断言名/反例名逐条取自 main 已交付代码与 `scripts/**` 门禁的真实标识，禁编造、禁把「计划中的测试」写成实测；证据路径必须指向仓库内真实文件（TTS：`AnnouncementSchedulerTests`/`AnnouncementSpeakerTests`；duck：`AudioSessionAdapterTests`/`AnnouncementSpeakerTests`；GPX：`RunGPXExporterTests`/`GPXCodecTests`/`scripts/check-gpx-export.sh`；竖屏：`ios/project.yml`/`scripts/check-ios-shell.sh`；设计 token：`RunLayoutBalancePolicy`/`LocalizationPolicyTests`/`DesignTokensTests`/`scripts/check-ios-shell.sh`）。缺口行只许写 `none（缺口）`，不得以 `pending` 充当缺口。

## 最近交付证明

- workItemId: wi_intake_3c33f34dc2d5a6b8（2026-11-11，pass，验证矩阵 B/C 6 行回填 + 守护测试放宽）
- 交付：`docs/verification-matrix.md` 由「4 实测 + 6 pending」收敛为「9 实测 + 1 显式缺口」——TTS / duck / GPX / 竖屏+iPhone-only / 设计 token+hero 间距 5 行按 main 上真实测试与门禁标识填全，断言名与反例零编造；「现状」列改写实测口径与阈值来源（GPX 1e-6 ≈ 0.11 m/格、trkpt 恰 4 不设数量容差；竖屏 `project.yml` 与构建产物 `Info.plist` 双向实测；阈值 80 = 2.5 × Spacing.xl、16 = Spacing.md，2026-11-11 先定后测）。Dynamic Type 如实记为唯一缺口（`none（缺口）`，不补实现）。`DocsVerificationMatrixTests` 由 `measuredSeams(4)/pendingSeams(6)` 改为 10 接缝逐条存在 + 计数断言（pending 0 / 缺口 1 / 实测 9），保留表头逐字、6 列非空、`repoRoot()`/`VERSION` 定位。
- 验证：`code_gates` 22 门 attempt 001 全绿（含 `test-ios-run-core` 的 `swift test`、`lint-ios-shell`）；本项未改生产代码、`ios/project.yml`、`.munk/code-gates.json` 与其他文档，缺口永久对下游可见。
