# Domain: ios-run-telemetry

iOS App 侧「机器自证」遥测子域：在既有跑步链路（Run → 结束归档 → History → RunDetail → GPX 导出）上做 additive 遥测——把跑次授权/定位遥测内嵌进既有跑次 JSON，并为每公里音频播报留下可断言证据。只新增 `telemetry` 顶层键与 `samples[].source` 键，不改任何既有键值、不改 RunCore 任何契约、不改门 id 与门 command。

## 范围

- `ios/PurePace/Run/RunTelemetry.swift`（新增）：`RunTelemetry` 及子结构的 `Codable` 契约 + `RunTelemetryWriter`；写回走 `JSONSerialization` 读顶层对象 → 仅新增 `telemetry` 顶层键与 `samples[]` 每项 `source` 键 → 原子写回（临时文件 + `replaceItem`）；定位目标文件按解码出的 `RunRecord.id` 匹配，不复制文件名规则。
- `telemetry` 结构固定：`authorizationStatus{name,rawValue}`、`accuracyAuthorization{name,rawValue}`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically`、`announcements[]`。
- `ios/PurePace/Run/RunStorage.swift`：新增 `archiveDirectory(fileManager:)` 与 DEBUG-only `resetArchiveIfRequested(_:)`（仅 `-uiTestResetArchive` 清空 `Documents/Runs` 与 `Exports`，Release 不编译）。
- `ios/PurePace/Run/RunSessionViewModel.swift`：持有 `AnnouncementTelemetryRecorder` 与 `SystemAuthorizationProbing`；`locationSource(_:didProduce:)` 记录 `timestamp → source`；`start()` 后抓「跑步进行态」后台开关快照；`finish()` 成功后构建 `RunTelemetry` 并注入，同时缓存 DEBUG `telemetrySummary`。
- `ios/PurePace/Run/RunView.swift`：仅 DEBUG 且 ViewModel 暴露 `telemetrySummary`（`-uiTestLocation`）时渲染 `accessibilityIdentifier("run.telemetry")` 文本；Release 不出现。
- `ios/PurePace/Location/RunLocationSource.swift`：`RunLocationProviding` 增加只读 `sampleSource`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically`；真实源返回 `.device` 与 manager 实际值。
- `ios/PurePace/Location/RunTestLocationSource.swift`：返回 `sampleSource == .simulated`、后台开关如实 `false/false`；新增 DEBUG 快速里程模式（`-uiTestLocationFast`，仅该测试源生效，不改既有 `-uiTestLocation` 默认节奏）。
- `ios/PurePace/Location/SystemAuthorizationProbe.swift`（新增）：`SystemAuthorizationProbing` 协议 + 生产实现读 `CLLocationManager().authorizationStatus` 与 `accuracyAuthorization`。
- `ios/PurePace/Audio/AudioSessionAdapter.swift`：`AudioSessionControlling` 增加只读 `isOtherAudioPlaying`、`secondaryAudioShouldBeSilencedHint`；`beginAnnouncement()/endAnnouncement()` 返回是否真实执行平台调用。
- `ios/PurePace/Audio/AnnouncementSpeaker.swift`：`SpeechSynthesizing` 增加起始回调；`SpeechAnnouncementSpeaker` 接受可选 `AnnouncementTelemetryRecording`，在播报开始/结束记录 category/mode/options/两个布尔/文本/起止时间/duck 撤销。
- `ios/PurePace/Audio/AnnouncementTelemetry.swift`（新增）：`AnnouncementTelemetryRecording` 协议 + 线程安全的进程内 `AnnouncementTelemetryRecorder`。
- `ios/PurePace/ContentView.swift`：构造 ViewModel 时注入 recorder/probe 与 DEBUG launch-arg（`-uiTestLocationFast`、`-uiTestResetArchive`）。
- 测试落点：`ios/PurePaceTests/RunTelemetryTests.swift`（新增）、`AnnouncementSpeakerTests.swift`、`RunSessionViewModelTests.swift`、`AudioSessionAdapterTests.swift`；`ios/PurePaceUITests/RunFlowUITests.swift` 新增 `testRunProducesTelemetryAcrossKilometerBoundary`。
- 脚本：`scripts/verify-ios-ui-e2e.sh` 容器断言扩展；`scripts/test-ios.sh` 模拟器隐私阶段补 `simctl privacy grant location-always`；`scripts/check-ios-shell.sh` 登记新增源码/测试与 `run.telemetry` 标识。不新增门 id、不改既有门 command。
- `ios/PurePace/Run/RunLifecycleTelemetry.swift`（新增）：`RunLifecycleTelemetryRecording` 协议 + 线程安全 `RunLifecycleTelemetryRecorder`（可注入 `NotificationCenter` / `now` / 快照闭包）与 `RunLifecycleSnapshotBox`；观察 `UIApplication` 四条通知，事件名固定 `protectedDataWillBecomeUnavailable` / `protectedDataDidBecomeAvailable` / `didEnterBackground` / `willEnterForeground`（UIKit 无 DidBecomeUnavailable，按其真实 API 记录），`deinit` 移除观察者，只记录不驱动会话与定位。
- `ios/PurePace/Run/RunLaunchArguments.swift`（新增）：纯函数 `autoStartRecordingEnabled(arguments:)`——默认关，裸 flag 或后跟 `1`/`true` 为开，其它值（含 `0`）为关；Release 可编译，不与定位源门控 `-uiTestLocation` 互相读取。
- `telemetry` 增补（additive，不新增 sidecar）：`events[]`（`name`/`at`/`sampleCount`/`distanceMeters`/`elapsedSeconds`，按到达顺序）与 `bundle{}`（`backgroundModes`/`identifier`/`shortVersion`/`buildVersion`，取自**运行中已装包** `Bundle.main.infoDictionary`）；`RunSessionViewModel` 按本跑次自增样本计数生成事件当刻快照，`onAppear` 在 `autoStartRecording && .ready` 时只自动 `start()` 一次。
- 测试落点增补：`ios/PurePaceTests/RunLifecycleTelemetryTests.swift`、`ios/PurePaceTests/RunLaunchArgumentsTests.swift`（新增，登记进 `check-ios-shell.sh` 的 `live_sources` / `unit_tests`）；`RunSessionViewModelTests.swift` 补 autoStart 与生命周期事件不改变会话状态。

## 验收

- ac-tel-fields: 新跑次 JSON（`Documents/Runs/*.json`）顶层含 `telemetry`，且含 `authorizationStatus{name,rawValue}`、`accuracyAuthorization{name,rawValue}`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically`；`samples[]` 每元素含 `source` 且 ∈ {`device`,`simulated`}。落点：`RunTelemetryTests`（真实临时目录落盘后按原始 JSON 回读）+ `verify-ios-ui-e2e.sh` 容器 JSON 断言。
- ac-tel-source-device: 真实 `RunLocationSource` 路径写入的 `samples[].source == "device"`；`-uiTestLocation` 确定性源路径全为 `"simulated"`。落点：`RunTelemetryTests` 注入桩证明 device 分支；`verify-ios-ui-e2e.sh` 断言容器 JSON 全为 `simulated`。
- ac-tel-backcompat: 旧格式跑次夹具（无 `telemetry`、`samples[]` 无 `source`）仍能被 `RunArchiveStore.list()` 解码，History 列表、`RunDetailContent` 详情映射、`RunGPXExporter` 导出不回归；含新增未知键的新格式记录同样可被 `RunRecord` 解码，既有字段数值逐字段不变。落点：`RunTelemetryTests` + `RunDetailContentTests` / `RunExportStateTests` 既有用例回归。
- ac-tel-always: 模拟器 `simctl privacy <udid> grant location-always com.chaxiu.purepace` 后，App 侧系统授权探针读回 `authorizedAlways`，JSON 的 `telemetry.authorizationStatus.name == "authorizedAlways"` 且 `rawValue == 3`；不一致则用例失败并输出实际值（如实记录缺口，不回退为通过）。落点：`RunTelemetryTests`（探针桩断言映射）+ `RunFlowUITests.testRunProducesTelemetryAcrossKilometerBoundary`（真实 `simctl` 预置下断言名称与 rawValue）。
- ac-tel-capability: 跑步进行态 `allowsBackgroundLocationUpdates == true`、`stop()`/结束/失权后 `false`；`pausesLocationUpdatesAutomatically == false`；`CLLocationManager` 与其 delegate 由强引用持有。既有单测复用不重写：`RunLocationSourceTests.testBackgroundUpdatesEnabledWhileRunningAndResetAfterStop` 与 `testSystemManagerRetainsLocationManagerAndDelegate`（回执须注明复用来源）。新增仅补：`telemetry` 后台开关取「跑步进行态快照」（真实源 true/false；确定性模拟源如实记录 false/false 并注明原因）。
- ac-audio-duck-contract: 播报时下发 `AVAudioSession` `category == .playback`、`mode == .spokenAudio`、`options` 含 `.duckOthers`；播报结束（`didFinish` 或 `didCancel`）后恰好一次 `setActive(false, [.notifyOthersOnDeactivation])`；`AVSpeechSynthesizer` 起始与结束回调都被调用，播报文本写入遥测并被断言。落点：`AnnouncementSpeakerTests`（`AudioSessionSpy` + `SpeechSynthesizerSpy`）+ `RunTelemetryTests` 从 JSON 回读。
- ac-audio-telemetry: `telemetry.announcements[]` 每条含 `splitIndex`、`text`、`startedAt`、`finishedAt`/`cancelled`、`category`、`mode`、`categoryOptions`（含 `duckOthers` 标志）、`isOtherAudioPlaying`、`secondaryAudioShouldBeSilencedHint`、`sessionActivated`、`sessionDeactivated`/`duckRevoked`；只断言**已记录**（键存在且类型正确），不断言两个音频环境布尔的具体数值变化（模拟器无并发音频源，数值变化只在真机 30 秒实听判）。落点：`RunTelemetryTests` + `AnnouncementSpeakerTests`。
- ac-audio-ui-e2e: 模拟器 XCUITest `RunFlowUITests.testRunProducesTelemetryAcrossKilometerBoundary` 以 `-uiTestLocation`（+ DEBUG 快速里程参数）驱动「开始 → 跨 1 km 边界 → 结束」，结束后 `run.saved` 出现，并通过 DEBUG 门控的 `run.telemetry` 无障碍摘要断言：至少 1 条播报遥测含 `duckOthers` 与含「第 1 公里」的文本、并含 `authorizationStatus` 与两个音频环境布尔字段；回执标注「定位源=确定性，仅触发边界」。落点：`ios/PurePaceUITests/RunFlowUITests.swift`。
- ac-no-semantic-change: 距离、活跃时长、当前/平均配速、分段、GPX 编码、导出文件名与导出行为与改动前逐字段一致；只允许新增 `telemetry` 顶层键与 `samples[].source` 键，不修改任何既有键值；未被本次跑次注入的旧记录文件不被改写。落点：`test-ios-core` / `test-ios-run-core` / `RunExportStateTests` / `check-gpx-export` 既有门回归全绿。
- ac-gates-green: 既有 code_gates 全量绿，至少含 `test-ios`（新单测 + 新 UI 用例真实执行）、`verify-ios-ui-e2e`、`lint`、`lint-ios-shell`、`lint-ios-scripts`、`lint-ios-run-core`、`build-ios`；`.munk/code-gates.json` 门 id 集合与 command 均不变（不新增、不放宽）。
- ac-evidence-honesty: 交付回执/文档只写「模拟器链路通过」「代码层断言通过」；不出现任何真机验收、阶段整体通过、授权升级已完成的断言；真机项统一列为 `pending: 待人现场`。

### 锁屏/前后台遥测、包自报与 autoStart（`wi_intake_19c87b6c71d028a0` 起）

- ac-telemetry-events-fields: 新跑次 JSON 顶层 `telemetry.events` 为数组，每元素含 `name`（字符串）、`at`（UTC ISO8601 秒级字符串，可被 `ISO8601DateFormatter` 解析）、`sampleCount`（整数）、`distanceMeters`（数值）、`elapsedSeconds`（数值）；类型固定、无占位值。落点：`RunLifecycleTelemetryTests`（真实临时目录落盘后按原始 JSON 回读）。
- ac-telemetry-event-names: 四条通知分别记录为 `protectedDataWillBecomeUnavailable`、`protectedDataDidBecomeAvailable`、`didEnterBackground`、`willEnterForeground`；注入四条通知后 `events` 恰 4 条、名称集合相等、无重复。PRD 原文写的 `protectedDataDidBecomeUnavailable` 在 UIKit 不存在，按系统真实 API（`protectedDataDidBecomeAvailableNotification`）落地并保持同名映射。
- ac-telemetry-event-order-and-time: `events` 顺序与通知到达顺序严格一致；每条 `at` 等于注入时钟在该事件时刻的 UTC ISO8601 字符串，不随时间本地化漂移。
- ac-telemetry-event-snapshot: 每条事件的 `sampleCount`/`distanceMeters`/`elapsedSeconds` 等于**该事件发生当刻**的跑次快照（递增样本数不得写成结束终值）；样本计数是本跑次内自增（`start()` 归零），不复用跨跑次累加的 `sampleSources`。
- ac-telemetry-additive-no-behavior-change: 无事件时 `events == []`，既有 `telemetry` 键与 `samples[].source` 逐字段不变；事件观察器在未开跑/暂停/已结束都只记录，不改变 `RunSessionState`、不触发 `locationSource.start()/stop()`、不改距离/时长/配速/分段/GPX 输出。
- ac-bundle-self-report: `telemetry.bundle` 含 `backgroundModes`（即 `Bundle.main.infoDictionary["UIBackgroundModes"]` 实际数组）、`identifier`、`shortVersion`、`buildVersion`（同一 `infoDictionary` 的三键）；App target 单测断言 `identifier == "sh.munk.purepace"` 且 `backgroundModes` 含 `location` 与 `audio`；注入假字典按同一映射输出，缺键输出空值不伪造。**设备侧唯一来源**，禁止 `#if DEBUG` 包裹。
- ac-autostart-default-off: 无 `-autoStartRecording`（空数组 / 仅其它 launch-arg）时解析为 `false`；代码层单测落在默认模拟器腿（`test-ios --unit-only`）真实执行。
- ac-autostart-on-and-value: `-autoStartRecording 1` 与裸 `-autoStartRecording` 为 `true`；`-autoStartRecording 0` / 非法值为 `false`；解析器编译进 Release（无 `#if DEBUG`，`check-ios-shell.sh` 断言）。
- ac-autostart-wiring: 开启且状态为 `.ready` 时首屏出现触发 `start()` 恰好一次（重复 `onAppear` 不重复开跑）；关闭时 `onAppear` 后仍 `.ready` 且不产生 `RunRecord`。
- ac-autostart-isolation: `-autoStartRecording` 与 `-uiTestLocation` 互不读取——仅前者时定位源仍为 `RunLocationSource`（`sampleSource == .device`），仅后者时不自动开跑；不改变授权请求时机与既有 `telemetry` 字段。
- ac-local-gates-green: `lint` / `lint-ios-shell` / `lint-ios-scripts` / `lint-ios-core` / `lint-ios-run-core` / `lint-ios-release` / `build-ios` / `build-ios-core` / `build-ios-run-core` / `test-ios-core` / `test-ios-run-core` / `test-ios --unit-only` 全绿；`.munk/code-gates.json` 门 id/command 与 `ios/project.yml` 零改动；新增源码与测试按既有口径登记 `scripts/check-ios-shell.sh`，不弱化既有断言。重 UI E2E 不作本地阻断门。

### 播报停用边界定性（`wi_intake_f76b858c0c2376f5`）

- ac-verdict-single-cause: 定性结论唯一落盘于该项 `digest.md` 顶部 `verdict: 1|2|3`（①遥测派生字段写错 / ②回调时序致状态机已非 active / ③停用调用抛出被吞），结论段不得出现「需进一步观察 / 可能 / 猜测 / 待现场判定」等含糊措辞；被排除的两个机制各自附排除依据（测试名或证据读数）。
- ac-writer-branch-mapping: 给出写入方与分支表，至少覆盖 `AnnouncementTelemetryRecorder.recordFinished` 写入 `sessionDeactivated`/`duckRevoked`、取值来自 `SpeechAnnouncementSpeaker.speak` 的 `onFinish`（`sessionDeactivated = try audioSession.endAnnouncement()`、`duckRevoked: sessionDeactivated`）、`AudioSessionAdapter.endAnnouncement` 的 `performed = action != .none`、`AudioSessionCoordinator.deactivate` 的 `guard state == .active`，并写清写 false / 写 true 的条件。
- ac-repro-true-branch: 测试证明播报期间协调器保持 `.active` → didFinish → 恰好一次 `setActive(false, .notifyOthersOnDeactivation)` → `sessionActivated/sessionDeactivated/duckRevoked` 全 true、`finishedAt != nil`、`cancelled=false`。
- ac-repro-false-branch-interruption: 测试证明播报中 `interruption began` → 状态 `.interrupted` → didFinish 时 `deactivate` 返回 `.none`、无 `setActive(false)`、两派生字段 false；且 `interruptionEnded(shouldResume: false)` 后下一次播报重新激活（`sessionActivated=true`）。
- ac-repro-false-branch-throw: 测试证明 `setActive(false)` 从注入控制器抛出 → 异常被 `speak` 的 catch 吞掉 → 两派生字段 false，但协调器状态已先转 `.inactive`，故下一次播报仍 `sessionActivated=true`；该用例须同时出现 `sessionActivated=true` + `sessionDeactivated=false` + `finishedAt != nil` + `cancelled=false` 这一真机指纹。
- ac-fingerprint-discrimination: 指纹矩阵逐格列出三种机制在「三条均 `sessionActivated=true`」「`finishedAt` 均回调且 `cancelled=false`」「播报时长未被截断」上的预测与观测，据此说明为何只有一种自洽；不得只给结论。
- ac-derived-fields-provenance: 说明 `isOtherAudioPlaying`/`secondaryAudioShouldBeSilencedHint` 由 `AudioSessionAdapter.announcementContext` 在 `beginAnnouncement` 之后、`synthesizer.speak` 之前实时读取并经 `recordStarted` 落盘，判定其与 `sessionDeactivated`/`duckRevoked` 非同类问题；测试须以 `true/true` 与 `false/false` 两组相反值证明透传、未写死也未复用旧快照。
- ac-no-production-semantic-change: 不触碰 `ios/PurePace/Audio/**`、`ios/RunCore/Sources/**`、`ios/PurePace/Run/RunTelemetry.swift` 的生产行为；遥测 JSON 字段集合与含义不变；改动仅新增/扩展 `ios/PurePaceTests/**`。
- ac-minimal-fix-proposal: 「最小修法」段给出改动文件与函数、为何最小、对调用序列/遥测契约/旧记录解码的影响面；判定为产品缺陷时明确写「需另派写项，本项未修」，仅遥测语义时明确写「不修真实音频行为」。
- ac-evidence-refs: 引用 `artifacts/evidence/window-2c7c4f3/evidence/container-runs-B/*.json` 与 `analysis-B.txt` 的具体字段值与时间戳，禁止「见证据目录」式空引用。
- ac-gates-green-no-weakening: `.munk/code-gates.json` 门 id 与 command 均不变（不新增、不放宽）；`test-ios`（`--unit-only`）、`test-ios-core`、`test-ios-run-core`、`build-ios`、`lint-ios-*` 全绿；不删既有断言、不加 skip。
- ac-budget-stop: 90 分钟或 10M token 触顶立即停手，回执写明已完成到哪一步（定性 / 复现 / 修法建议）与未完成原因。

## 非目标

- 不连真机、不产出真机证据：锁屏/后台连续采样与 duck 实际听感一律 `pending: 待人现场`；不对 `isOtherAudioPlaying` / `secondaryAudioShouldBeSilencedHint` 的真机数值变化做机器断言。
- 不改 `ios/RunCore/**`（`RunRecord`/`RunSample` 编码、`RunArchiveStore`、`RunGPXExporter` 零改动）；不改计时/距离/配速/分段算法；不改 GPX 编码与导出文件名规则。
- 不改 `ios/project.yml` 签名与版本主干、`VERSION`；不改 `.github/workflows` 触发条件与步骤语义；不推 tag、不动 Release。
- 不新增第三方运行时依赖；不新增 code-gates 门 id；不新建数据库；不改跑次 json 文件名规则；不新增 sidecar（遥测只走内嵌一种落点）。
- 不改 README 已定的「人手清单只剩两件」。
- 不做 Android / `shared/` / 视觉主题 / 遥测展示页；History 与 RunDetail 不新增遥测 UI（`run.telemetry` 仅 DEBUG 测试摘要）。
- 不在 Release 构建引入任何测试/遥测写入分支；但 `-autoStartRecording` 解析与接线属发布态可用能力（非 DEBUG 门控），事件与包自报写入同样在 Release 生效。
- 不新增 sidecar telemetry JSON（只走既有跑次 JSON 内嵌）、不新增遥测展示页/数据库/第三方依赖；不改 Bundle ID `sh.munk.purepace` 与根 `VERSION`。
- 不排真机、不驱动锁屏、不用 `devicectl copy from` 读回设备 Info.plist，也不用 XCUITest `Bundle.main.infoDictionary` 冒充候选包证据；真机窗口由公司另排。

## 实现约束

- 唯一落点：写进既有跑次 json 的内嵌 additive 字段，不用 sidecar、两种不并存；除新增两个键外不改任何既有键值，旧记录文件不触碰。
- 名称映射：授权 `notDetermined|restricted|denied|authorizedAlways|authorizedWhenInUse`；精度 `full|reduced`；`authorizedAlways.rawValue == 3`、`authorizedWhenInUse.rawValue == 4`、`full.rawValue == 0`、`reduced.rawValue == 1`；音频 options 用 `duckOthers|mixWithOthers|interruptSpokenAudioAndMixWithOthers|allowBluetoothA2DP|notifyOthersOnDeactivation` 字面量。
- 探针最小化：音频走 `AudioSessionControlling` 扩展 + `AnnouncementTelemetryRecording`，生产直读 `AVAudioSession`、测试用 spy，不引入 `Speech` 等新框架（import 允许表不变）；授权探针独立于采样源（`SystemAuthorizationProbing`），使 `-uiTestLocation` 下采样可为 `simulated` 而授权仍反映系统真实值。
- 门控：所有新增测试分支用 `#if DEBUG` 或 launch-arg 门控；Release 不编译 `RunTestLocationSource` 及其快速模式、`run.telemetry` 摘要、归档 reset。
- 同机并发：优先 `-only-testing:PurePaceTests`；若撞 `RunFlowUITests` 抢占导致伪失败，按仓库 AGENTS.md 判为环境抢占，清理后串行重跑一次，不放宽断言。
- 证据口径：只报「模拟器链路通过」「代码层断言通过」与真实用例数/门计数；不写「真机已验证」「阶段整体通过」。
- 事件采集接缝：recorder 随 ViewModel 初始化即注册，快照经 `RunLifecycleSnapshotBox` 中转（通知回调线程读、主线程状态变化写）；时刻固定 `ISO8601DateFormatter` + `[.withInternetDateTime]`，事件名映射写死在单一表内，不按通知 `object` 分支。
- 包自报接缝：`BundleInfoProviding` / `SystemBundleInfoProvider` 读运行中 `Bundle.main`，测试注入字典；`bundle` 只在跑次落盘后的 `injectTelemetry(for:)` 写入，与前两次注入同一写回路径。
- autoStart 接线：只在 `onAppear` 且 `state == .ready` 且未触发过时开跑一次（一次性守卫），不改变既有授权请求链路与定位源选择分支；`ContentView` 仅把解析结果作为 ViewModel 参数透传。
- 排期/证据依赖：Release 候选包须在「最新 main 已含 `-uiTestLocation` 收录式门控交付」之后构建一次；依赖未合入时按预检拒出包并报 owner，不得先用旧 main 出包再重出。

## 最近交付证明

- workItemId: wi_intake_f76b858c0c2376f5（2026-11-10，pass，播报停用边界定性；只取代码层与模拟器腿证据）
- 结论：`verdict: 3` — 真机 window `trun_fa2b41fa85283565`（候选 2c7c4f3）三条播报的 `sessionDeactivated`/`duckRevoked` 恒 false 唯一归因为「`AudioSessionCoordinator.deactivate()` 先置 `.inactive` 再返回 `.deactivate` 动作，`setActive(false, ...)` 抛出后被 `SpeechAnnouncementSpeaker.speak` 的 `onFinish` catch 吞掉并强制写 false」，错误对象被丢弃、遥测无错误字段（可观测性缺口）。①遥测派生字段写错与②回调时序致状态机非 active 均被测试与证据证伪（三条播报窗口内零中断事件、时长 4.4907/4.1481/4.4588s 完整、`cancelled=false`）。
- 交付：定性结论与写入方/分支表、指纹矩阵、证据读数、最小修法建议落盘 `.munk/changes/wi_intake_f76b858c0c2376f5/digest.md`；`ios/PurePaceTests/AnnouncementSpeakerTests.swift` 扩展 `AudioSessionSpy.deactivationError` 注入点并新增 4 例（true 分支 / 中断 false 分支 / 抛错 false 分支复现真机指纹 / 两个音频环境布尔双值透传）。未改生产代码与遥测 JSON 契约。
- 实测：`AnnouncementSpeakerTests` 11/11 通过、`** TEST SUCCEEDED **`；`bash scripts/test-ios.sh --unit-only` exit 0（`PurePaceTests` 全 suite + RunCore 123/123）。
- 后续承接：停用失败路径的生产修法已由 `wi_intake_2ba71ae036eedd40` 落地，会话停用语义、失败诊断文件与 A/B/C 验收归 `ios-audio-session` 域（「盲重试一次 + 失败回滚 `.active`」已被公司裁决否决，不在此域复活）；本域遥测契约仍不新增错误码 / 结束状态字段。设备侧窄场复验仍为 `pending: 待人现场`。

