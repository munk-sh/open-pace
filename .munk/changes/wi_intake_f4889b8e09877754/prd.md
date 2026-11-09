# 阶段 2 机器自证补齐：跑次授权/音频遥测（additive，模拟器可回归）

## 范围

在既有跑步链路（Run → 结束归档 → History → RunDetail → GPX 导出）之上，为「机器自证」补齐两块可机器断言的证据，不重写任何业务算法：

1. **跑次授权/定位遥测**：每条新跑次文件 `Documents/Runs/<stem>.json` 内嵌 additive `telemetry` 对象（授权状态、精度授权、后台更新开关、系统自动暂停开关），并为 `samples[]` 每个采样点补 `source`（`device` ｜ `simulated`）。
2. **音频播报自证**：每公里播报在 `telemetry.announcements[]` 留下可断言证据——播报时刻的 `AVAudioSession` category/mode/options（须含 `duckOthers`）、`isOtherAudioPlaying`、`secondaryAudioShouldBeSilencedHint`、`AVSpeechSynthesizer` 起止回调与播报文本、播报结束后 duck 撤销/会话恢复的调用记录。
3. 以上由 **单测 + 模拟器 XCUITest** 钉住，并挂进既有 code_gates（`test-ios`、`verify-ios-ui-e2e`、脚本 lint 门）真实执行；**不新增门 id、不改既有门 command**。

本项只做 additive 遥测与最小探针，生产业务行为（计时/距离/配速/分段/GPX 编码/导出文件名/导出结果）零变化。真机项（锁屏后台连续采样、duck 实际听感）一律保持 `pending: 待人现场`。

## 验收

- ac-tel-fields: 新跑次 JSON（`Documents/Runs/*.json`）顶层含 `telemetry` 对象，且含 `authorizationStatus{name,rawValue}`、`accuracyAuthorization{name,rawValue}`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically`；`samples[]` 每个元素含 `source` 且取值 ∈ {`device`,`simulated`}。断言落点：`ios/PurePaceTests/RunTelemetryTests.swift`（真实临时目录落盘后按原始 JSON 回读）+ `scripts/verify-ios-ui-e2e.sh` 的容器 JSON 断言。
- ac-tel-source-device: 真实 `RunLocationSource` 路径下写入的 `samples[].source == "device"`；`-uiTestLocation` 确定性源路径下 `samples[].source == "simulated"`。断言落点：`RunTelemetryTests` 用注入桩证明 device 分支；`verify-ios-ui-e2e.sh` 对 `-uiTestLocation` 跑出的容器 JSON 断言全部为 `simulated`。
- ac-tel-backcompat: 旧格式跑次夹具（无 `telemetry`、`samples[]` 无 `source`）仍能被 `RunArchiveStore.list()` 正常解码，History 列表、`RunDetailContent` 详情映射、`RunGPXExporter` 导出均不回归；含新增未知键的新格式记录同样可被 `RunRecord` 解码，既有字段数值逐字段不变。断言落点：`RunTelemetryTests` + `RunDetailContentTests` / `RunExportStateTests` 既有用例回归。
- ac-tel-always: 模拟器执行 `xcrun simctl privacy <udid> grant location-always com.chaxiu.purepace` 后，App 侧系统授权探针读回 `authorizedAlways`，写入 JSON 的 `telemetry.authorizationStatus.name == "authorizedAlways"` 且 `rawValue == 3`（`CLAuthorizationStatus` 原始值），与系统授权一致；若不一致，用例失败并输出实际值（如实记录缺口，不回退为通过）。断言落点：`RunTelemetryTests`（探针注入桩断言映射）+ `RunFlowUITests.testRunProducesTelemetryAcrossKilometerBoundary`（真实 `simctl` 预置下断言 `run.telemetry` 摘要中的名称与 rawValue）。
- ac-tel-capability: 跑步进行态 `allowsBackgroundLocationUpdates == true`、`stop()`/结束/失权后 `false`；`pausesLocationUpdatesAutomatically == false`；`CLLocationManager` 与其 delegate 由强引用持有。**既有单测已覆盖，复用不重写**：`ios/PurePaceTests/RunLocationSourceTests.swift` 的 `testBackgroundUpdatesEnabledWhileRunningAndResetAfterStop` 与 `testSystemManagerRetainsLocationManagerAndDelegate`；回执须注明复用来源。新增仅补充：`telemetry` 中的后台开关取「跑步进行态快照」（真实源为 true/false；确定性模拟源如实记录 false/false 并注明原因）。
- ac-audio-duck-contract: 播报时下发 `AVAudioSession` `category == .playback`、`mode == .spokenAudio`、`options` 含 `.duckOthers`；播报结束（`didFinish` 或 `didCancel`）后恰好一次 `setActive(false, [.notifyOthersOnDeactivation])`（duck 撤销/会话恢复）；`AVSpeechSynthesizer` 的起始与结束回调都被调用，播报文本写入遥测并被断言。断言落点：`ios/PurePaceTests/AnnouncementSpeakerTests.swift`（`AudioSessionSpy` + `SpeechSynthesizerSpy`）+ `RunTelemetryTests` 从 JSON 回读断言。
- ac-audio-telemetry: `telemetry.announcements[]` 每条记录含 `splitIndex`、`text`、`startedAt`、`finishedAt`/`cancelled`、`category`、`mode`、`categoryOptions`（含 `duckOthers` 标志）、`isOtherAudioPlaying`、`secondaryAudioShouldBeSilencedHint`、`sessionActivated`、`sessionDeactivated`/`duckRevoked`；断言其**「已记录」**（键存在且类型正确），**不断言** `isOtherAudioPlaying` 与 `secondaryAudioShouldBeSilencedHint` 的具体数值变化（模拟器无并发音频源，数值变化只在真机 30 秒实听判）。断言落点：`RunTelemetryTests` + `AnnouncementSpeakerTests`。
- ac-audio-ui-e2e: 模拟器 XCUITest `RunFlowUITests.testRunProducesTelemetryAcrossKilometerBoundary` 以 `-uiTestLocation`（+ DEBUG 快速里程参数）驱动「开始 → 跨 1 km 边界 → 结束」，结束后 `run.saved` 出现，并通过 DEBUG 门控的 `run.telemetry` 无障碍摘要断言：至少 1 条播报遥测含 `duckOthers` 与含「第 1 公里」的文本、并含 `authorizationStatus` 与两个音频环境布尔字段；digest/回执标注「定位源=确定性，仅触发边界」。断言落点：`ios/PurePaceUITests/RunFlowUITests.swift`。
- ac-no-semantic-change: 距离、活跃时长、当前/平均配速、分段、GPX 编码、导出文件名与导出行为与改动前逐字段一致；本次只允许新增 `telemetry` 顶层键与 `samples[].source` 键，不修改任何既有键值；未被本次跑次注入的旧记录文件不被改写。断言落点：`test-ios-core` / `test-ios-run-core` / `RunExportStateTests` / `check-gpx-export` 既有门回归全绿。
- ac-gates-green: 既有 code_gates 全量绿，至少含 `test-ios`（新单测 + 新 UI 用例真实执行）、`verify-ios-ui-e2e`、`lint`、`lint-ios-shell`、`lint-ios-scripts`、`lint-ios-run-core`、`build-ios`；`.munk/code-gates.json` 门 id 集合与 command 均不变（不新增、不放宽）。
- ac-evidence-honesty: 交付回执/文档只写「模拟器链路通过」「代码层断言通过」；不出现任何真机验收、阶段整体通过、授权升级已完成的断言；真机项统一列为 `pending: 待人现场`。

## 非目标

- **不连真机、不产出真机证据**：锁屏/后台连续采样 `(a1)` 与 duck 实际听感 `(b)` 一律 `pending: 待人现场`；不对 `isOtherAudioPlaying` / `secondaryAudioShouldBeSilencedHint` 的真机数值变化做机器断言。
- 不改 `ios/RunCore/**`（运行域纯逻辑、`RunRecord`/`RunSample` 编码、`RunArchiveStore`、`RunGPXExporter` 零改动）；不改计时/距离/配速/分段算法；不改 GPX 编码与导出文件名规则。
- 不改 `ios/project.yml` 签名与版本主干、`VERSION`；不改 `.github/workflows` 触发条件与步骤语义；不推 tag、不动 Release。
- 不新增第三方运行时依赖；不新增 code-gates 门 id；不新建数据库；不改跑次 json 文件名规则；不新增 sidecar（遥测只走内嵌一种落点）。
- 不改 README 已定的「人手清单只剩两件」。
- 不做 Android / `shared/` / 视觉主题 / 遥测展示页；History 与 RunDetail 不新增遥测 UI（`run.telemetry` 仅 DEBUG 测试摘要）。
- 不在 Release 构建引入任何测试/遥测写入分支。

## 实现约束

### 遥测落点（已定，唯一）

- **写进既有跑次 json 的内嵌 additive 字段**（不用 sidecar，两种不并存）：在已由 `RunArchiveStore.save` 落盘的 `Documents/Runs/<stem>.json` 上，用 `JSONSerialization` 读出顶层对象 → 仅新增顶层 `telemetry` 键、并为 `samples[]` 每个对象新增 `source` 键 → 原子写回（临时文件 + `replaceItem`）。除这两个新增点外不改任何既有键值，旧记录文件不触碰。
- 新增 `ios/PurePace/Run/RunTelemetry.swift`：`RunTelemetry` 及子结构的 `Codable` 契约 + `RunTelemetryWriter`（定位目标文件按解码出的 `RunRecord.id` 匹配，不复制文件名规则）。
- `telemetry` 结构固定：`authorizationStatus{name,rawValue}`、`accuracyAuthorization{name,rawValue}`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically`、`announcements[]`（字段见 ac-audio-telemetry）。
- 名称映射：授权名字面量 `notDetermined|restricted|denied|authorizedAlways|authorizedWhenInUse`；精度 `full|reduced`；`authorizedAlways.rawValue == 3`、`authorizedWhenInUse.rawValue == 4`、`full.rawValue == 0`、`reduced.rawValue == 1`。音频 options 用 `duckOthers|mixWithOthers|interruptSpokenAudioAndMixWithOthers|allowBluetoothA2DP|notifyOthersOnDeactivation` 字面量。

### 文件锚点（逐文件；禁止整目录改写）

- `ios/PurePace/Run/RunTelemetry.swift`（新增）：遥测 Codable 模型、从会话上下文构建、`RunTelemetryWriter` additive 注入（原子替换，只加 `telemetry` 与 `samples[].source`）。
- `ios/PurePace/Run/RunStorage.swift`：新增 `archiveDirectory(fileManager:)`（`Documents/Runs/`）与 DEBUG-only `resetArchiveIfRequested(_:)`（仅 `-uiTestResetArchive` 时清空 `Documents/Runs`、`Exports`，用于 UI 用例隔离；Release 不编译）。
- `ios/PurePace/Run/RunSessionViewModel.swift`：持有 `AnnouncementTelemetryRecorder` 与 `SystemAuthorizationProbing`；在 `locationSource(_:didProduce:)` 记录 `(timestamp → source)`；`start()` 后抓「跑步进行态」后台开关快照；`finish()` 成功后构建 `RunTelemetry` 并调用 writer 注入，同时缓存 `telemetrySummary`（DEBUG UI 摘要）。
- `ios/PurePace/Run/RunView.swift`：仅当 ViewModel 暴露 `telemetrySummary`（DEBUG + `-uiTestLocation`）时渲染带 `accessibilityIdentifier("run.telemetry")` 的文本，供 XCUITest 断言；Release 不出现。
- `ios/PurePace/Location/RunLocationSource.swift`：`RunLocationProviding` 增加只读 `sampleSource`、`allowsBackgroundLocationUpdates`、`pausesLocationUpdatesAutomatically`；`RunLocationSource` 返回 `.device` 与 manager 实际值。
- `ios/PurePace/Location/RunTestLocationSource.swift`：返回 `sampleSource == .simulated`、后台开关如实 `false/false`；新增 DEBUG 快速里程模式（由 `-uiTestLocationFast` 开启，仅该测试源生效，不改变既有 `-uiTestLocation` 默认节奏）。
- `ios/PurePace/Location/SystemAuthorizationProbe.swift`（新增）：`SystemAuthorizationProbing` 协议 + 生产实现读取 `CLLocationManager().authorizationStatus` 与 `accuracyAuthorization`；`CoreLocation` 仅在本文件与既有 `Location/`、`Harness/` 作用域内。
- `ios/PurePace/Audio/AudioSessionAdapter.swift`：`AudioSessionControlling` 增加只读 `isOtherAudioPlaying`、`secondaryAudioShouldBeSilencedHint`；`AVAudioSessionController` 直读真实 `AVAudioSession`；`beginAnnouncement()/endAnnouncement()` 返回是否真实执行了平台调用（供 `sessionActivated/sessionDeactivated` 记录）。
- `ios/PurePace/Audio/AnnouncementSpeaker.swift`：`SpeechSynthesizing` 增加起始回调（生产 `AVSpeechSynthesizing` 用 `speechSynthesizer(_:didStart:)` 触发）；`SpeechAnnouncementSpeaker` 接受可选 `AnnouncementTelemetryRecording`，在播报开始/结束记录 category/mode/options/两个布尔/文本/起止时间/duck 撤销。
- `ios/PurePace/Audio/AnnouncementTelemetry.swift`（新增）：`AnnouncementTelemetryRecording` 协议 + `AnnouncementTelemetryRecorder`（线程安全的进程内累积，结束时导出为 `announcements[]`）。
- `ios/PurePace/ContentView.swift`：构造 ViewModel 时注入 recorder/probe 与 DEBUG launch-arg（`-uiTestLocationFast`、`-uiTestResetArchive`、`-uiTestLocation` 判定沿用既有 `#if DEBUG`）。
- `ios/PurePaceTests/RunTelemetryTests.swift`（新增）：ac-tel-fields / ac-tel-source-device / ac-tel-backcompat / ac-tel-always（探针桩）/ ac-audio-telemetry（JSON 回读）。
- `ios/PurePaceTests/AnnouncementSpeakerTests.swift`：沿用/扩展 spy，覆盖起止回调、duckOthers、结束 `[.notifyOthersOnDeactivation]`、文本与遥测记录；同步更新 `SpeechSynthesizerSpy` 到新契约。
- `ios/PurePaceTests/RunSessionViewModelTests.swift`：同步更新 `FakeLocationSource` 到 `RunLocationProviding` 新要求；补 finish 后遥测注入断言。
- `ios/PurePaceUITests/RunFlowUITests.swift`：新增 `testRunProducesTelemetryAcrossKilometerBoundary`；既有 run-flow 用例开头使用 `-uiTestResetArchive` 保证容器隔离。
- `scripts/verify-ios-ui-e2e.sh`：扩展内嵌 `python3` 容器断言：`telemetry` 四类字段存在、`samples[].source` 全为 `simulated`、`authorizationStatus.rawValue == 3`（预置 `location-always` 时）；不新增门 id。
- `scripts/test-ios.sh`：模拟器隐私阶段在既有 `location` 授权之外补 `simctl privacy grant location-always`（失败则按既有隐私阶段失败语义处理），使 ac-tel-always 的 `authorizedAlways` 可机器成立；不改门 command。
- `scripts/check-ios-shell.sh`：把新增源码/测试文件登记进 `live_sources` / `unit_tests` / `ui_tests` 清单，`run.telemetry` 纳入 UI 标识断言；保持 `--self-test` 退出 0。

### 探针与注入（最小，不大改）

- 音频探针走最小协议 `AudioSessionControlling` 扩展 + `AnnouncementTelemetryRecording`；生产实现直读 `AVAudioSession`，测试用 spy，不引入 `Speech` 等新框架（import 允许表不变）。
- 授权探针独立于采样源（`SystemAuthorizationProbing`），使 `-uiTestLocation` 下采样可为 `simulated` 而授权仍反映系统真实值；这是 ac-tel-always 与 ac-tel-fields 能同时成立的关键。
- 所有新增测试分支用 `#if DEBUG` 或 launch-arg 门控；Release 不编译 `RunTestLocationSource` 及其快速模式、`run.telemetry` 摘要、归档 reset。

### 门禁与证据口径

- 不新增 `.munk/code-gates.json` 门 id、不改既有 `command`；新用例随 `test-ios`（`-only-testing:PurePaceTests` 与 `-only-testing:PurePaceUITests`）与 `verify-ios-ui-e2e` 既有门执行。
- 同机并发：优先 `-only-testing:PurePaceTests`；若撞 `RunFlowUITests` 抢占导致伪失败，按仓库 AGENTS.md 判为环境抢占，清理后串行重跑一次，不放宽断言。
- 回执必须写明：每个 `ac-*` 的断言落点（文件/用例名/断言项）、一次模拟器实跑输出摘要（`** TEST SUCCEEDED **` 与用例数）、脱敏遥测 JSON 样例片段（不含 secret）、仍为 `pending: 待人现场` 的项清单。
- 证据口径：只写「模拟器链路通过」「代码层断言通过」；不写任何真机验收或阶段整体通过的结论。
