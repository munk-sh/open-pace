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

## 非目标

- 不连真机、不产出真机证据：锁屏/后台连续采样与 duck 实际听感一律 `pending: 待人现场`；不对 `isOtherAudioPlaying` / `secondaryAudioShouldBeSilencedHint` 的真机数值变化做机器断言。
- 不改 `ios/RunCore/**`（`RunRecord`/`RunSample` 编码、`RunArchiveStore`、`RunGPXExporter` 零改动）；不改计时/距离/配速/分段算法；不改 GPX 编码与导出文件名规则。
- 不改 `ios/project.yml` 签名与版本主干、`VERSION`；不改 `.github/workflows` 触发条件与步骤语义；不推 tag、不动 Release。
- 不新增第三方运行时依赖；不新增 code-gates 门 id；不新建数据库；不改跑次 json 文件名规则；不新增 sidecar（遥测只走内嵌一种落点）。
- 不改 README 已定的「人手清单只剩两件」。
- 不做 Android / `shared/` / 视觉主题 / 遥测展示页；History 与 RunDetail 不新增遥测 UI（`run.telemetry` 仅 DEBUG 测试摘要）。
- 不在 Release 构建引入任何测试/遥测写入分支。

## 实现约束

- 唯一落点：写进既有跑次 json 的内嵌 additive 字段，不用 sidecar、两种不并存；除新增两个键外不改任何既有键值，旧记录文件不触碰。
- 名称映射：授权 `notDetermined|restricted|denied|authorizedAlways|authorizedWhenInUse`；精度 `full|reduced`；`authorizedAlways.rawValue == 3`、`authorizedWhenInUse.rawValue == 4`、`full.rawValue == 0`、`reduced.rawValue == 1`；音频 options 用 `duckOthers|mixWithOthers|interruptSpokenAudioAndMixWithOthers|allowBluetoothA2DP|notifyOthersOnDeactivation` 字面量。
- 探针最小化：音频走 `AudioSessionControlling` 扩展 + `AnnouncementTelemetryRecording`，生产直读 `AVAudioSession`、测试用 spy，不引入 `Speech` 等新框架（import 允许表不变）；授权探针独立于采样源（`SystemAuthorizationProbing`），使 `-uiTestLocation` 下采样可为 `simulated` 而授权仍反映系统真实值。
- 门控：所有新增测试分支用 `#if DEBUG` 或 launch-arg 门控；Release 不编译 `RunTestLocationSource` 及其快速模式、`run.telemetry` 摘要、归档 reset。
- 同机并发：优先 `-only-testing:PurePaceTests`；若撞 `RunFlowUITests` 抢占导致伪失败，按仓库 AGENTS.md 判为环境抢占，清理后串行重跑一次，不放宽断言。
- 证据口径：只报「模拟器链路通过」「代码层断言通过」与真实用例数/门计数；不写「真机已验证」「阶段整体通过」。

## 最近交付证明

- workItemId: wi_intake_f4889b8e09877754（2026-11-09，pass，跑次授权/音频遥测 additive 自证；只取模拟器 + 代码层证据）
- 交付：新增 `RunTelemetry`/`RunTelemetryWriter`（`JSONSerialization` additive 注入 `telemetry` 与 `samples[].source`，按 `RunRecord.id` 定位、原子替换）、`SystemAuthorizationProbe`、`AnnouncementTelemetryRecorder`；`RunLocationProviding` 补 `sampleSource`/后台开关只读、`RunTestLocationSource` 补 `-uiTestLocationFast` 快速里程；`AudioSessionControlling` 补两个音频环境布尔、`SpeechAnnouncementSpeaker` 记录播报起止与 duck 撤销；`RunSessionViewModel` 在 `finish` 后注入遥测并缓存 DEBUG `telemetrySummary`，`RunView` 渲染 `run.telemetry`；`RunStorage` 新增 DEBUG `-uiTestResetArchive` 归档隔离。
- 门禁与测试同步：`verify-ios-ui-e2e.sh` 容器断言补 telemetry 四类字段/`samples[].source` 全 `simulated`/`authorizationStatus rawValue == 3`（并改 `build-for-testing` + `test-without-building` + 后台重申 `location-always` 以免 TCC 绑定新容器）；`test-ios.sh` 补 `grant location-always`；`check-ios-shell.sh` 纳入 4 个新增文件与 `run.telemetry` 标识，UI 用例数期望 2 → 3。
- 实测：`code_gates` 24 门全绿（attempt 003，含 `lint-ios-shell` / `lint-ios-scripts` / `build-ios` / `test-ios` / `verify-ios-ui-e2e` / `test-ios-run-core` / `test-ios-core`）；`test-ios` 单元 123 例 0 失败（含 `RunTelemetryTests` 7 例、`AnnouncementSpeakerTests` 新增 3 例、`AudioSessionAdapterTests` 2 例）+ UI 3 例通过（含 `testRunProducesTelemetryAcrossKilometerBoundary`），均 `** TEST SUCCEEDED **`；`verify-ios-ui-e2e` 容器内断言通过：Runs 恰 1 条、`telemetry.authorizationStatus = authorizedAlways/3`、`sampleSources = ["simulated"]`、GPX `xmllint` 合法。
- 口径：模拟器与代码层契约通过；真机锁屏后台连续采样、duck 实际听感仍为 `pending: 待人现场`（未做真机验收）。
