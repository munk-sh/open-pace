# 阶段 2 断言补齐 A：后台定位策略 + 锁屏/重启状态恢复

## 范围

只在**代码层 + 模拟器单测**补齐三条系统接缝的可判红断言，不新增产品行为：

1. **定位会话与更新策略**：后台更新开关、`CLLocationManager`/delegate 强引用、构建产物 `Info.plist` 本体读回、Always 升级与 WhenInUse 降级两分支。
2. **锁屏语义**：以 `UIApplication.protectedDataWillBecomeUnavailable` / `protectedDataDidBecomeAvailable` 通知注入锁屏区间（注入时钟），用 fake location source 在锁定期间持续喂点，钉住「会话不中断、计时/距离继续、状态不前移、样本不丢不重、去重计数可观测」。
3. **进程重启恢复**：checkpoint 落盘后用全新 store / orchestrator / ViewModel 实例模拟新进程，钉住距离、已完成分段、最后采样点与计时连续性；坏尾丢弃与中间损坏抛错两态各有断言。
4. **验证矩阵**：本项创建仓内唯一单表 `docs/verification-matrix.md`，覆盖本波三条项的全部接缝；本项行按实测填，另两项行按已知信息填并标 `pending: 待对应 item 回填`。

已有基础（本项只补强、不重写）：`ios/PurePaceTests/RunLocationSourceTests.swift` 已覆盖开关、管理器存活、授权分支；`ios/PurePaceTests/BackgroundModesPlistTests.swift` 已读构建产物 plist 本体并带负向自检；`ios/RunCore/Tests/PurePaceRunCoreTests/CheckpointStoreTests.swift` 已覆盖坏尾/中间损坏；`ios/RunCore/Tests/PurePaceRunCoreTests/ResumeContractTests.swift` 已覆盖 engine 层恢复。缺口是：锁屏区间内无会话行为断言与样本去重计数（仅有「通知不改变状态」的负向测试与遥测记录），以及**应用级（orchestrator / ViewModel）没有 restore 路径**，恢复只到 store/engine 重建。

## 验收

### A. 定位会话与更新策略

- ac-loc-bg-flags-running: 授权为 `authorizedAlways` 时 `RunLocationSource.start()` 后，注入 manager 的 `allowsBackgroundLocationUpdates == true` 且 `pausesLocationUpdatesAutomatically == false`；`stop()` 后两者均为 `false`（含 `pauses` 的复位断言，不只断 `allows`）。
- ac-loc-bg-flags-counterexample: 同 commit 提供不依赖修改生产代码的独立反例用例：`stop()` 前把注入 manager 的后台开关预置为「脏」值，`stop()` 后必须被复位为 `false`；`start()` 后 `pauses` 必须为 `false`。生产若漏掉赋值/复位，该反例用例独立判红。
- ac-loc-manager-delegate-retained: `RunLocationSource()` 存活期间，对 `SystemLocationManager.underlyingManager` 和其 `delegate` 建立弱引用读取均为非 `nil`，且 `source.retainedManager === manager`；释放 source 后弱引用 `underlyingManager` 变为 `nil`（证明强引用链真实存在，不是只在断言时临时取到）；`stop()` 后管理器身份不变。
- ac-plist-built-app-readback: 直接以 `Data` + `PropertyListSerialization` 读取**已构建 App 的 `Info.plist` 文件本体**（不读 `ios/project.yml`），断言 `UIBackgroundModes` 为字符串数组且同时包含 `location` 与 `audio`；同一读取路径对缺任一模式的临时 plist 必须独立判红。
- ac-auth-always-upgrade: `notDetermined` 首次 `start()` 只请求 WhenInUse；`authorizedWhenInUse` 时 `start()` 发起一次 Always 升级且同一实例不重复请求；升级到 `authorizedAlways` 后 `backgroundCapable == true`、降级提示为 `nil`。
- ac-auth-wheninuse-degraded: 授权落到 `authorizedWhenInUse` 时 `authorization.backgroundCapable == false` 且 `backgroundDegradationHint != nil`；同 commit 的独立反例用例断言「降级态若 `backgroundCapable == true` 或缺提示则判红」，不依赖改生产代码取证。

### B. 锁屏语义（模拟器层，禁写「真机已验证」）

- ac-lock-running-continues: 已 `start()` 的 ViewModel 处于 `running` 时注入 `protectedDataWillBecomeUnavailable`（带注入时钟 `tLock`），随后用 fake location source 以 1 Hz 连续喂入 N≥10 个时间/坐标递增采样；每次摄入后 `state == .running`，`metrics.distance` 与 `metrics.elapsed` 严格递增，状态不得变为 `paused`/`finished`，也不得发生任何状态迁移。
- ac-lock-sample-cadence: 锁定区间内被接受的样本时间戳严格单调递增，相邻样本最大空洞 `<= maximumSampleGapSeconds`（初值 `2.0`）。阈值必须在**测量/跑测试之前**写进代码常量与注释，注释给出推导依据（fixture 固定 1.0 s 采样间隔 × 2 倍系统调度抖动容差）与「不构成真机采样频率承诺」的声明；digest 记录阈值定于哪个 commit/时间、依据什么，禁止看红后调阈值。
- ac-lock-dedup-samples: 正常锁屏区间内样本时间戳严格单调递增且样本去重计数为 `0`；向 ViewModel 注入与上一接受样本**同一时间戳**（坐标可不同）的重复样本，必须被丢弃：`distance`/`elapsed`/`splits` 不变、去重计数 `+1`；再注入一条完整重复序列（同一时间戳集合）同样全部丢弃、计数与丢弃条数一致。该反例用例与正例同 commit，不依赖修改生产代码即可独立判红。
- ac-lock-unlock-no-replay-no-reset: 在注入时钟 `tUnlock` 投递 `protectedDataDidBecomeAvailable` 后，`state`、`distance`、`elapsed`、`splits` 与解锁前一刻完全相等（解锁事件本身不补样本、不增加 checkpoint 行、不重置计时）；解锁后的下一条样本使 `elapsed` 从解锁前值继续增加 `sample.timestamp - 上一接受样本.timestamp`，不得回到 0 或按 `tUnlock` 重算。
- ac-lock-handler-observable: ViewModel 对锁屏区间有可观测的注入式处理（内部可测的 lock 状态/事件，使用注入的 `now` 与注入 `NotificationCenter`），生产注册两条 protected-data 通知；断言锁定期间该状态为「已锁定」、解锁后复位。
- ac-lock-counterexample-independent: B 每条断言都有同 commit 的独立反例用例（至少：锁屏事件后状态被误改、重复样本注入、解锁时计时被重置、锁状态缺失），均不需修改生产代码即可判红；digest 表逐条给出反例测试名、文件:行与是否判红。

### C. 进程重启恢复（新增，必须到应用层）

- ac-restart-restores-metrics: 先用 ViewModel/orchestrator 跑到至少 2 个完整分段并落盘 checkpoint；丢弃全部内存实例后，用**同一文件、全新 `RunCheckpointStore` + 全新 orchestrator + 全新 ViewModel** 构造；恢复后 `state == .paused`，`metrics.distance` / `metrics.elapsed` / `metrics.splits`（index、distance、duration）与最后一条有效 checkpoint 逐项相等且均不为 0。
- ac-restart-last-sample: 恢复后的最后采样锚点与 checkpoint `lastSample`（经纬度、时间戳）一致；`resume(at: tR)` 后第一条时间戳 `<=` 锚点的样本被拒绝（度量不变），第一条晚于锚点的样本只重建位置锚点、不因重启前坐标跳变而累计距离。
- ac-restart-timer-continues: `resume(at: tR)` 后喂入 `tR + Δ` 的样本，`elapsed == 恢复值 + Δ`（容差 1e-6）且严格大于恢复值，`distance` 从恢复值继续累加；断言「非归零」与「非重算」两个方向。
- ac-restart-bad-tail: checkpoint 文件末尾为不完整 JSON 行（无换行或半行）时，新进程恢复入口静默丢弃坏尾、以上一条完整有效记录恢复；恢复后的度量与坏尾前最后一条有效 checkpoint 相等，且不抛错。
- ac-restart-middle-corruption: 非尾行损坏（中间行非法 JSON/非法字段）时，恢复入口必须暴露 `RunCoreError.corruptedCheckpoint`（throwing 或 ViewModel 可观测 `errorMessage`），不得静默构造一个零度量会话；断言恢复后不会以 0 距离/0 时长「假装成功」。
- ac-restart-viewmodel-e2e: 上述恢复至少有一条经 `RunSessionViewModel`（而非仅 `RunCheckpointStore`）的端到端用例：新进程构造后由 fake location source 继续供点，断言 ViewModel 的 `state`/`metrics` 与旧进程 checkpoint 连续；不允许只用 store 层读回代替。
- ac-restart-counterexample-independent: 坏尾、中间损坏、非法锚点等反例状态各有同 commit 的独立用例，独立判红且不依赖修改生产代码。

### D. 冻结约束与验证矩阵

- ac-verification-matrix: 本项创建 `docs/verification-matrix.md`，文件内容为**纯 Markdown 表格**（无正文段落），表头恰为 `| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |`；覆盖全部 10 条接缝：后台定位会话与更新策略、锁屏 protectedData 锚点、进程重启恢复、TTS 每公里调度与中断恢复、duck 撤销/去激活/categoryOptions、GPX 导出、Info.plist 能力、竖屏+iPhone-only 静态、Dynamic Type、设计 token / hero 间距；本项（A）相关行按实测填断言名、反例、证据路径与判红结果；另两项行按已知信息填现状与证据路径，断言名/反例/证据状态标 `pending: 待对应 item 回填`。
- ac-freeze-identifiers: `bash scripts/check-ios-shell.sh` 中可及 identifier 冻结清单仍为 33 项，实际集合与清单逐项一致（零新增、零改名、零删除）；`git diff` 不出现 `accessibilityIdentifier(...)` / `identifier: "run|runDetail|history|tab|settings.*"` 的改动。
- ac-freeze-gates: `.munk/code-gates.json` 仍为 22 个 gate，既不删也不新增；22 项全部退 0。`scripts/check-ios-run-core.sh` 的结构/边界断言保持通过；新增 `docs/verification-matrix.md` 不得让任何既有 gate 变红。
- ac-no-ui-or-asset-diff: 不改 `ios/PurePace/Run/RunView.swift`、`History/*`、`Settings/*`、`Design/*`、`Localizable.xcstrings`、截图或 `shared/`；`git diff --stat` 只出现本项相关的 session/location/RunCore 源码、测试文件与 `docs/verification-matrix.md`。
- ac-no-new-business-semantics: 不新增用户可见文案/identifier；不改 GPX/音频；不改状态迁移表、距离/配速/分段公式、checkpoint 格式版本与归档契约；锁屏处理不得引入「锁屏自动 pause」「解锁自动 resume」「补样本回放」等新语义。
- ac-no-device-claims: 不新增真机流程、XCUITest 设备用例或设备脚本；digest、`docs/verification-matrix.md` 与代码注释不得出现「后台锁屏连续定位已验证」「真机已验证」；真机项保持 `pending: 待人现场`。

## 非目标

- 不改任何 UI、设计 token、排版、截图、可及 identifier 与用户可见文案。
- 不改 GPX 导出、音频/播报、归档格式、checkpoint JSONL 字段或 `formatVersion`。
- 不新增真机场、XCUITest 设备用例、设备脚本或 CI 重腿；真机锁屏/后台定位仍为 `pending: 待人现场`。
- 不定义「重启后结束会话」的归档 `startedAt` 新语义，不改 `RunRecord`/`RunArchiveStore` 契约；若恢复后 `finish` 需要 `startedAt`，由 Architect 在不改归档契约的前提下明确取舍并加断言，不得静默新增用户可见错误。
- 不重写既有 110+ RunCore 用例、既有 ViewModel/Location 用例或 `scripts/**` 门禁；不新增 gate。
- 不做性能优化、不做定位精度策略调整、不做后台任务/续跑调度（`BGTaskScheduler` 等）。
- 不维护/创建第二张矩阵表；`docs/verification-matrix.md` 是本波唯一真源表。

## 实现约束

- **前置基线**：仓库已有 `AGENTS.md` 并路由官方 skill（iOS `swiftui-pro`、Android `android-cli`），App 已存在，因此本项**不需要** `repo-bootstrap` 重建、不创建新工程、不改 `AGENTS.md`；不做视觉基线。
- **既有锚点（只读核对后按下述约束改）**：
  - `ios/PurePace/Location/RunLocationSource.swift:105-200`：`beginUpdating()`/`endUpdating()` 的后台开关与复位；`RunLocationSource.swift:240-310` 的 `SystemLocationManager` 强引用与 delegate 绑定（`underlyingManager`、`isDelegateAttached`）。
  - `ios/PurePaceTests/RunLocationSourceTests.swift:92-204`：现有开关/强引用/授权分支用例，本项补强而非另起一套；`:206-260` 现有 engine 层重叠投递用例，不得与本项的应用层锁屏用例混淆。
  - `ios/PurePaceTests/BackgroundModesPlistTests.swift:28-60`：已从构建产物 plist 文件本体读回并带负向自检，保持该读取路径。
  - `ios/PurePace/Run/RunSessionViewModel.swift:38-76`（init 与注入 `now`）、`:94-105`（`start()` 抓后台快照）、`:144-150`（`ingest`）、`:198-206`（lifecycle 快照）、`:267-273`（delegate 回调）。
  - `ios/PurePace/Run/RunLifecycleTelemetry.swift:32-45`：四条 `UIApplication` 通知的既有观察者，可作为注入/命名参考，但不得把本次锁屏断言做成仅遥测记录。
  - `ios/RunCore/Sources/PurePaceRunCore/RunSessionOrchestrator.swift:44-59`（仅全新 init）、`:193-206`（checkpoint append）：恢复入口需新增 additive 初始化器/加载路径。
  - `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift:44-72`（`init(restoring:)` 已恢复距离/时长/分段/最后锚点，恢复为 paused）、`RunSessionMachine.swift:23-32`（恢复为 paused）。
  - `ios/RunCore/Sources/PurePaceRunCore/RunCheckpointStore.swift:36-85`（尾行静默丢弃、非尾行抛错、`loadLatest`）。
  - `ios/RunCore/Tests/PurePaceRunCoreTests/CheckpointStoreTests.swift:125-171`（坏尾/中间损坏既有断言）、`ResumeContractTests.swift:288-383`（engine 恢复既有断言）。
  - `scripts/check-ios-shell.sh:468-489`（33 项 identifier 冻结）；`ios/project.yml:47-53`（`UIBackgroundModes: location, audio`，本项只读不读 project.yml 做断言）。
- **分层**：锁屏/应用恢复的接缝放 App 层（`RunSessionViewModel` 及其注入的 `NotificationCenter`/`now`）；纯逻辑恢复入口放 `ios/RunCore`。`RunCore` 保持只 `import Foundation`，不得出现 `CoreLocation|UIKit|SwiftUI|AVFoundation|URLSession|Timer` 字样（含注释），不得引入第三方依赖。
- **恢复 API 必须 additive**：不改变既有 `RunSessionOrchestrator.init(checkpointStore:archiveStore:announcementsEnabled:)`、`RunSessionMachine`、`RunMetricsEngine` 既有 public 契约与语义；新入口的失败语义必须明确（抛错或可观测错误），不得静默零度量恢复。
- **样本去重计数必须 additive**：可在 engine 或 orchestrator/ViewModel 现有唯一摄入路径上新增只读计数（同时间戳/非递增样本被丢弃时 `+1`），不得改变既有 drop 语义、距离/时长/配速/分段公式或 checkpoint 字段。
- **锁屏处理边界**：通知只用于观察与记录锁屏区间，**不得**触发 `pause`/`resume`/`finish`，不得停定位、不得回放/补投样本；样本仍经既有 `RunSessionViewModel.ingest` → `RunSessionOrchestrator.ingest` → `RunMetricsEngine.ingest` 唯一路径累计。时间一律由注入时钟/样本时间戳提供，测试禁止 `Date()` 现时与真实通知投递时序依赖。
- **阈值先定后测**：`maximumSampleGapSeconds` 等所有数值阈值必须在首次跑相关测试前写入代码/注释并说明推导依据（采样间隔 / 系统调度），digest 记录阈值定于何时、依据什么；禁止看到红后调阈值或反向拟合。
- **反例纪律**：每个接缝的反例用例与正例**同 commit** 提交，且能独立判红；取证不依赖临时修改生产代码、不依赖手工改阈值。反例测试本身也是仓库长期资产，不是一次性实验脚本。
- **验证矩阵**：`docs/verification-matrix.md` 为纯表格单一真源，表外不放解释性正文；本项实测行与另两项 `pending: 待对应 item 回填` 行必须可区分。
- **证据口径**：digest 用「接缝 → 断言名 → 文件:行 → 反例是否判红」表格逐条落；数字必须分口径标注（`用例数` 与 `断言数` 分开，xcodebuild `Executed` 与 XCTest 断言数不得混写）；反例证据必须包含实际失败的测试名与失败输出片段。
- **预算**：≤8M token（本项不设分钟硬上限，超预算交半成品）；超限交半成品并在 digest 如实列未完成项，不得虚报完成。
- **门禁**：交付前至少跑 `bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-run-core.sh`、`swift test --package-path ios/RunCore`、`bash scripts/test-ios.sh --unit-only`，并对 `.munk/code-gates.json` 全 22 项负责。
