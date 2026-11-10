---
verdict: 3
window: trun_fa2b41fa85283565
release_candidate: 2c7c4f3
scope: 定性 + 确定性复现 + 最小修法建议（未改生产语义）
---

# 定性：`sessionDeactivated` / `duckRevoked` 恒 false 的唯一归因

## 0. 结论（唯一）

**verdict: 3 — 停用调用抛出被吞（错误未落盘）。**

`AnnouncementTelemetryRecorder.recordFinished` 本身没有写错派生值（排除①）；
观测窗口内三条播报都没有中断事件，且 TTS 时长完整、`cancelled=false`、`finishedAt` 均存在，
与「状态机已非 active 且被中断提前结束」的特征不符（排除②）；
`AudioSessionCoordinator.deactivate()` 先执行 `state = .inactive`、再返回 `.deactivate` 动作，
`AudioSessionAdapter.endAnnouncement()` 随后执行 `setActive(false, ...)` 时抛出，
`SpeechAnnouncementSpeaker.speak` 的 `onFinish` catch 丢弃错误并写 `sessionDeactivated = false`，
同时协调器已是 `.inactive`，所以下一次播报仍会重新激活并记录 `sessionActivated = true`。
该机制同时解释三条播报的完整字段指纹（③自洽）。

具体抛出的 `AVAudioSession` 错误码当前**没有落盘**：`AnnouncementSpeaker.swift:130-135` 的
`catch` 只把局部变量置 false，错误对象被丢弃，遥测契约也没有错误字段。这是本项要指出的
第二重缺陷（可观测性缺口），不改变上述唯一归因。

## 1. 字段写入链路与分支条件表

### 1.1 写入方（文件 + 函数 + 行号）

| 字段 | 写入方 | 取值来源 | 写 false 的条件 | 写 true 的条件 |
|---|---|---|---|---|
| `sessionActivated` | `ios/PurePace/Audio/AnnouncementSpeaker.swift` `speak`（`recordStarted` 调用 119-124 行；局部赋值 109-114 行）；落盘 `AnnouncementTelemetry.swift` `recordStarted` 39-64 行 | `try audioSession.beginAnnouncement()` 的返回值 | `beginAnnouncement()` 返回 `false`（协调器非 `.inactive`、动作 `.none`），或激活调用抛错（catch 只保留 false） | `beginAnnouncement()` 返回 `true`（协调器从 `.inactive -> .active`，`setActive(true)` 真实下发）；见 `AudioSessionAdapter.swift:136-142`、`AudioSessionCoordinator.swift:39-43` |
| `sessionDeactivated` | `AnnouncementSpeaker.swift` `onFinish` 闭包（130-142 行）；落盘 `AnnouncementTelemetry.swift` `recordFinished` 88-135 行 | `try audioSession.endAnnouncement()` 的返回值 | ① `endAnnouncement()` 返回 false：`deactivate()` 的动作是 `.none`（`AudioSessionCoordinator.swift:47-51` 的 `guard state == .active` 不成立）；② `setActive(false, ...)` 抛出后被 `AnnouncementSpeaker.swift:130-135` catch 吞掉并强制写 false | `endAnnouncement()` 返回 true：`AudioSessionAdapter.swift:147-152` 的 `performed = action != .none`，且 `perform` 的 `.deactivate` 分支（216-230 行）成功执行一次 `setActive(false, [.notifyOthersOnDeactivation])` |
| `duckRevoked` | `AnnouncementSpeaker.swift` 136-142 行；落盘 `AnnouncementTelemetry.swift` `recordFinished` 132-133 行 | `duckRevoked: sessionDeactivated`（同源派生，不是独立读取） | 与 `sessionDeactivated` 完全相同 | 与 `sessionDeactivated` 完全相同 |
| `isOtherAudioPlaying` | `AudioSessionAdapter.swift` `announcementContext` 124-133 行（129 行读取）；`AnnouncementSpeaker.swift:117` 调用；`recordStarted` 39-64 行落盘 | `controller.isOtherAudioPlaying` 实时只读属性 | 平台读回 false | 平台读回 true |
| `secondaryAudioShouldBeSilencedHint` | 同上（130 行读取） | `controller.secondaryAudioShouldBeSilencedHint` 实时只读属性 | 平台读回 false | 平台读回 true |

### 1.2 关键分支语义

- `AudioSessionCoordinator.deactivate()`（`ios/RunCore/Sources/PurePaceRunCore/AudioSessionCoordinator.swift:47-51`）：
  `guard state == .active else { return .none }` → 状态先置 `.inactive`，再返回 `.deactivate(options:)`。
  因此「状态已变」与「平台调用是否成功」解耦：`setActive(false)` 抛错后状态仍停在 `.inactive`。
- `AudioSessionAdapter.endAnnouncement()`（`ios/PurePace/Audio/AudioSessionAdapter.swift:147-152`）：
  `performed` 由协调器**动作**决定，而不是由平台调用**结果**决定；`try perform(action)` 抛错时
  整个方法抛出，调用方拿不到 `performed`。
- `SpeechAnnouncementSpeaker.speak` 的 `onFinish`（`ios/PurePace/Audio/AnnouncementSpeaker.swift:126-143`）：
  `sessionDeactivated = try self.audioSession.endAnnouncement()`（132 行），随后
  `duckRevoked: sessionDeactivated`（141 行）；
  130-135 行 `catch { sessionDeactivated = false }`，错误被丢弃；136-142 行把该 false 同时写入
  `sessionDeactivated` 与 `duckRevoked`，`finishedAt`/`cancelled` 仍按回调如实写入。
- `AnnouncementTelemetryRecorder.recordFinished`（`ios/PurePace/Audio/AnnouncementTelemetry.swift:88-135`）：
  按 `splitIndex + finishedAt == nil` 定位条目（143-151 行），只覆写传入的
  `sessionDeactivated`/`duckRevoked`；没有硬编码、没有从旧快照取值。

## 2. 证据读数（window `trun_fa2b41fa85283565`，候选 2c7c4f3）

证据文件：
`artifacts/evidence/window-2c7c4f3/evidence/container-runs-B/20261110T024456Z-04AB2F11-3785-49F8-A266-BE92CD3C7CDD.json`
与 `artifacts/evidence/window-2c7c4f3/evidence/analysis-B.txt`。

| splitIndex | startedAt (UTC) | finishedAt (UTC) | 实算时长 | sessionActivated | sessionDeactivated | duckRevoked | cancelled |
|---|---|---|---|---|---|---|---|
| 1 | 02:45:47.670764 (`1794278747.670764`) | 02:45:52.161462 (`1794278752.1614618`) | 4.4906979s | true | false | false | false |
| 2 | 02:46:37.513539 (`1794278797.5135388`) | 02:46:41.661635 (`1794278801.661635`) | 4.1480961s | true | false | false | false |
| 3 | 02:47:28.515088 (`1794278848.515088`) | 02:47:32.973935 (`1794278852.9739351`) | 4.4588470s | true | false | false | false |

（PRD 中第三条写作 4.47s，按 JSON 时间戳实算为 4.4588470s，本表以 JSON 实算值为准。）

其他实测字段：

- 三条均为 `category="playback"`、`mode="spokenAudio"`、
  `categoryOptions=["duckOthers","mixWithOthers"]`、
  `isOtherAudioPlaying=true`、`secondaryAudioShouldBeSilencedHint=true`。
- `analysis-B.txt:10`：`audio source: env-blocked — com.apple.MobileMusic not installed`;
  `preflight-result.json` 的 `result="env-blocked"`（`checkedAt=2026-11-10T02:44:30Z`）。
- `analysis-B.txt:11`：`duck revocation anomaly: sessionDeactivated=false & duckRevoked=false for all 3 announcements (no setActive(false) performed)`。
- `container-runs-B/...json` 的 `telemetry.events` 只有
  `didEnterBackground @ 2026-11-10T02:45:29Z` 与 `willEnterForeground @ 2026-11-10T02:45:32Z`；
  两次事件早于第一条播报开始（02:45:47.670764Z）15 秒以上，三条播报期间没有任何中断事件。

## 3. 指纹矩阵（逐格预测 vs 观测）

| 观测维度 | 机制① 遥测派生字段写错 | 机制② 回调时序致状态机已非 active | 机制③ 停用调用抛出被吞 | 实测 |
|---|---|---|---|---|
| 三条均 `sessionActivated=true` | 预测 true：起始激活路径独立于派生字段写错 | 预测 true：每条播报都要从 `.inactive` 重新激活 | 预测 true：失败停用已先把状态转 `.inactive`，下一条重新激活 | true / true / true |
| `sessionDeactivated`、`duckRevoked` 同源 false | 预测 false：写错点应在 `recordFinished` | 预测 false：`deactivate()` 在 `.interrupted` 返回 `.none` | 预测 false：`setActive(false)` 抛出，catch 强制 false | false / false（两条目同值） |
| didFinish 是否发生（`finishedAt != nil`） | 预测存在（写错不影响回调） | 预测只在被中断并恢复/取消后发生，时长应缩短或 `cancelled=true` | 预测正常发生，时长完整 | 三条均存在，`cancelled=false` |
| 真机播报时长未被截断 | 预测完整（4.49 / 4.15 / 4.46s 量级） | 预测被截断：中断开始即应结束或暂停，无法得到完整 4s+ 朗读 | 预测完整：停用失败发生在朗读结束之后 | 4.4906979 / 4.1480961 / 4.4588470s，均为完整时长 |
| 播报期间是否有中断事件 | 与中断无关 | 必须每条播报窗口内都有 `began`，且在下一条前以 `shouldResume=false` 结束 | 无需中断事件 | 三条播报窗口内 0 条中断事件；仅有播报前 15s+ 的 background/foreground |
| 平台停用调用 | 预测存在且成功：仅遥测写错时真实 `setActive(false)` 已撤销 duck | 预测不调用 `setActive(false)` | 预测调用已发起但抛出（调用未成功完成） | 分析结论 `no setActive(false) performed`，与「duck 未撤销」一致 |
| 下一条播报能否再次 `sessionActivated=true` | 预测 true（起始路径独立） | 预测 true（`shouldResume=false` 后回 `.inactive`） | 预测 true（失败停用已先把状态转 `.inactive`） | true（三条全部） |
| 与证据是否自洽 | 否：证据无成功停用调用；且 `recordFinished` 直接赋值、真分支测试固定 true | 否：需要三次未观测到的中断，且与完整时长/未取消矛盾 | 是：唯一不需要额外未观测事件的机制 | 判定③ |

补充：`isOtherAudioPlaying` / `secondaryAudioShouldBeSilencedHint` 是**播报开始时**读取的只读环境快照
（`announcementContext` 在 `beginAnnouncement` 之后、`synthesizer.speak` 之前调用），与**播报结束时**
由 `endAnnouncement()` 结果派生的 `sessionDeactivated`/`duckRevoked` 不是同一类字段。新测试
`testAnnouncementContextPassesThroughInjectedAudioEnvironmentBooleans` 注入 true/true 与 false/false
两组相反值，证明这两个字段每次调用都实时透传，既未写死也未复用旧快照；因此它们不是本次矛盾的写入方。

## 4. 被排除机制的证伪依据

### ① 遥测派生字段写错 — 证伪

- 代码：`recordFinished` 直接把调用方传入值写入两个字段（`AnnouncementTelemetry.swift:88-135`），
  `duckRevoked: sessionDeactivated`（`AnnouncementSpeaker.swift:141`）是显式同源派生。
- 测试：`AnnouncementSpeakerTests.testActiveSessionDeactivationWritesTrueDerivationsAndSinglePlatformCall`
  （`ios/PurePaceTests/AnnouncementSpeakerTests.swift:219`）在协调器保持 `.active` 时断言
  `sessionDeactivated=true`、`duckRevoked=true`，且平台序列恰为 `[true, false]`，证明 true 分支真实存在。
- 既有回归：`testTelemetryRecordsDuckContractStartFinishAndDeactivation`
  （同文件 163 行）同样固定该真分支。

### ② 回调时序致状态机已非 active — 证伪

- 测试：`AnnouncementSpeakerTests.testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates`
  （`ios/PurePaceTests/AnnouncementSpeakerTests.swift:258`）证明②的完整签名是：
  `began → .interrupted → didFinish 时 endAnnouncement() 返回 .none → 无 setActive(false) → false/false`；
  并且该分支要求中断发生在播报窗口内。
- 证据：三条播报窗口（02:45:47.670764–02:45:52.161462、02:46:37.513539–02:46:41.661635、
  02:47:28.515088–02:47:32.973935 UTC）内没有任何中断事件；唯一的 lifecycle pair
  （02:45:29Z / 02:45:32Z）早于第一条播报 15 秒以上。
- 证据：三条播报均完整走完 `startedAt -> finishedAt`，时长 4.4907 / 4.1481 / 4.4588 秒，
  `cancelled=false`。②要求播报被系统中断并放弃恢复（`shouldResume=false`），无法同时得到
  未截断时长、`didFinish` 非取消回调与零中断事件三项观测。

### ③ 停用调用抛出被吞 — 复现

- 测试：`AnnouncementSpeakerTests.testThrownDeactivationProducesObservedFalseFingerprintAndNextActivation`
  （`ios/PurePaceTests/AnnouncementSpeakerTests.swift:304`）用 `AudioSessionSpy.deactivationError`
  让 `setActive(false)` 抛出，断言：
  停用调用已发起（`deactivations.count == 1`）、协调器状态已为 `.inactive`、
  `sessionDeactivated=false`、`duckRevoked=false`、`sessionActivated=true`、
  `finishedAt != nil`、`cancelled=false`；再播下一条时 `activations.count == 2` 且
  `sessionActivated=true`，完整复现真机字段指纹。

## 5. 最小修法建议（仅建议，本项未改生产代码）

判定：**产品缺陷**——`setActive(false)` 失败后 duck 没有真正撤销，且错误被吞导致遥测失去原因；
**需另派写项，本项未修**。

### 5.1 最小改动点

1. `ios/PurePace/Audio/AnnouncementSpeaker.swift` `speak` 的 `onFinish`（130-135 行）：
   `catch` 不再只赋 false，至少记录错误（`os_log`/诊断日志）并保留 `sessionDeactivated=false`
   的真实语义；不改回调签名与 JSON 字段。
2. `ios/PurePace/Audio/AudioSessionAdapter.swift` `endAnnouncement()`（147-152 行）：
   对 `.deactivate` 动作失败做一次有界重试（仅对可重试的 `AVAudioSession` 错误），
   重试仍失败时把协调器状态恢复为 `.active`（可通过 `AudioSessionCoordinator` 增加一个
   纯状态回滚方法实现），使下一次结束路径仍有机会撤销 duck。
3. 若 Owner 接受遥测契约扩展，再另派项新增错误码/结束状态字段；本项按非目标不改契约。

### 5.2 为何是最小

- 仅触及「停用结束路径 + 错误处理」，不碰 `AudioSessionSettings`、`.duckOthers`/`.mixWithOthers`
  配置、播报文案、调度、定位与持久化。
- 正常成功路径的下发序列仍是一次 `setActive(false, [.notifyOthersOnDeactivation])`；
  重试只在异常路径发生。

### 5.3 影响面

- 现有调用序列：正常路径不变；异常路径多一次停用尝试。
- 遥测 JSON：字段集合与含义不变（本项不改契约）；成功后 `sessionDeactivated=true`，
  失败仍如实为 false，但错误原因可在日志中定位。
- 旧记录解码：无字段增删，`RunTelemetryAnnouncement` Codable 解码不变。
- 既有测试：`AnnouncementSpeakerTests`、`AudioSessionAdapterTests` 的既有断言无需删除或放宽。

## 6. 复现测试与实跑

新增/扩展文件：`ios/PurePaceTests/AnnouncementSpeakerTests.swift`（仅测试，未改生产代码）。

新增用例：

- `testActiveSessionDeactivationWritesTrueDerivationsAndSinglePlatformCall`（219 行）→ ac-repro-true-branch
- `testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates`（258 行）→ ac-repro-false-branch-interruption
- `testThrownDeactivationProducesObservedFalseFingerprintAndNextActivation`（304 行）→ ac-repro-false-branch-throw
- `testAnnouncementContextPassesThroughInjectedAudioEnvironmentBooleans`（344 行）→ ac-derived-fields-provenance

单跑命令与结果：

```bash
xcodebuild test -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:PurePaceTests/AnnouncementSpeakerTests
```

结果：`AnnouncementSpeakerTests` 11/11 通过，`** TEST SUCCEEDED **`（2026-11-10 11:10:25Z 本地运行）。

本地门实跑摘要：

```bash
bash scripts/test-ios.sh --unit-only
```

结果：exit 0；`PurePaceTests` 全部 suite passed（含 `AnnouncementSpeakerTests`、`AudioSessionAdapterTests`），
RunCore SwiftPM 123/123 passed；`[timing] boot=0s prep=4s build=9s unit=9s ui=0s runcore=12s total=34s`。

## 7. 边界声明

- 未改 `ios/PurePace/Audio/**`、`ios/RunCore/Sources/**`、`ios/PurePace/Run/RunTelemetry.swift`。
- 未改遥测 JSON 契约、Info.plist、bundle id、签名、`ios/project.yml`、`VERSION`、定位/持久化/GPX 契约。
- 未跑真机窗口、未做人耳验收；设备侧窄场复验由 Owner 另行排。
- 本项未提交生产修法；第 5 节仅为最小修法建议。
