# 每公里播报开关与真实 TTS 接线

## 范围

把波 1 遗留的两处空白补齐，App 侧仍只做接线与展示，不重写任何 RunCore 契约：

1. **Settings 真实偏好**：新增 UserDefaults 支撑的播报偏好存储（默认开启、重启后保持），`SettingsView` 用它渲染「每公里语音播报」开关，删除「本阶段暂无可配置项」与 `settings.empty` 诚实态文案；不放任何示例数值或额外假控件。
2. **真实播报器**：在 `ios/PurePace/Audio/` 新增 TTS 播报器（`AVSpeechSynthesizer` + 既有 `AudioSessionAdapter`）：每条播报命令先按冻结配置激活音频会话、再合成一条语音、语音结束（或取消）后停用会话；失败不崩溃、不干扰会话状态机。
3. **ViewModel 接线**：`RunSessionViewModel` 把 `RunSessionUpdate.announcements` 逐条转给播报器，并把开关状态用 `RunSessionOrchestrator.setAnnouncementsEnabled` 同步到编排器；关闭即时生效、重新开启不补播；暂停与结束时秩序由既有编排器/调度器保证，App 侧不自建公里判定、计时或去抖。
4. **内容与语言**：播报文案为纯函数生成的短句（含已完成公里序号与本次用时/配速），语速与语言沿用系统默认，不新增设置项。
5. **门禁同步**：`scripts/check-ios-shell.sh` 的 Settings 断言从「必须声明无可配置项且禁止 Toggle」改为「必须有真实开关 `settings.announcementToggle`、禁止示例数值与 Stepper/Slider」，并把新增源文件与测试文件纳入清单；`--self-test` 正负反例同步更新并保持通过。
6. **测试同步**：`PurePaceTests` 新增偏好持久化、播报器 speak 次数与激活/停用序列、ViewModel 关断零播报等断言；`PurePaceUITests` 增加 Settings 开关可见 + 重启保持的用例。

## 验收

- ac-toggle-default-on: 从未写入过偏好键的全新 UserDefaults 域构造偏好存储实例，`isEnabled == true`；`SettingsView` 渲染 `Toggle` 且其无障碍标识为 `settings.announcementToggle`，初始值与存储值一致。
- ac-toggle-persists: 将开关置为关闭后，用同一 UserDefaults 域新建存储实例读回为关闭；再置为开启同样读回为开启；写入键固定为单一常量键，不额外写入其它键。
- ac-settings-honest-copy: App 源码中不再出现「暂无可配置项」与 `settings.empty` 标识；Settings 页除该真实播报开关外不含任何示例数值、内置样例或 `Stepper`/`Slider`。
- ac-speaker-one-speak-per-command: 对一条已暴露的 `AnnouncementCommand`（`trigger == .kilometerCompleted`、`splitIndex == 1`），播报器恰好调用一次 `speak`，文案包含该公里序号；重复投递同一条命令不会多出第二条语音。
- ac-speaker-session-sequence: 每条播报的平台调用序列为「激活 → 一次 speak → 语音结束回调 → 停用」：激活阶段 spy 记录 `setCategory(.playback, .spokenAudio, [.duckOthers, .mixWithOthers])` 且随后一次 `setActive(true)`；结束回调后恰好一次 `setActive(false, [.notifyOthersOnDeactivation])`；语音取消（`didCancel`）同样触发停用；无命令时不产生任何音频会话调用。
- ac-announcement-off-zero-speak: 编排器播报关闭时跨整公里摄入采样，ViewModel 侧 `speak` 调用数为 0，且音频会话激活调用数为 0。
- ac-toggle-immediate-no-backfill: 运行中关闭开关后跨下一个整公里，`speak` 数为 0；重新开启开关后不补播被抑制的公里；再跨下一个整公里恰好一次 `speak`（`splitIndex` 为最新公里）。
- ac-pause-finish-silent: 暂停期间摄入采样不触发 `speak`；调用结束动作不触发 `speak`（编排器不对外返回收尾命令），View 层不自行发起播报。
- ac-no-duplicated-run-logic: App 侧不新增公里判定、计时或播报去抖逻辑：`speak` 只由 `RunSessionUpdate.announcements` 驱动（`ios/PurePace/Run` 仍无 `Timer` / `DispatchQueue.asyncAfter` / `CADisplayLink`）；`git diff` 中 `ios/RunCore` 无源码改动。
- ac-audio-scope-preserved: `AVFoundation` 仍只出现在 `ios/PurePace/Audio/`；App import 允许表不变（SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore），不新增 `Speech` 等框架；`check-ios-shell.sh --self-test` 的 AVFoundation 越界反例仍判失败。
- ac-ui-toggle-restart: XCUITest 在 Settings Tab 内断言 `settings.announcementToggle` 存在且可点击；翻转开关后 `terminate()` + `launch()`，再次进入 Settings 断言开关值与翻转后一致（用 `waitForExistence` 等待，不以固定 `sleep` 作判据）。
- ac-shell-gate-updated: `bash scripts/check-ios-shell.sh` 断言 Settings 源码含 `Toggle` 与 `settings.announcementToggle`、不含「暂无可配置项」、不含示例数值与 `Stepper`/`Slider`；新增文件（`Audio/AnnouncementSpeaker.swift`、`Settings/AnnouncementSettingsStore.swift` 及对应测试）进入文件清单；`--self-test` 至少各有一条新增断言的通过与失败反例，全部用例通过。
- ac-gates-preserved: `.munk/code-gates.json` 门 id 与 command（单一 argv）不变、只增不减；`bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 均退出 0，既有 `PurePaceTests` / `RunFlowUITests` 断言不减少。

## 非目标

- 不做播报语速 / 音量 / 语言 / 音色设置 UI，不做 TTS 试听按钮；文案与语音参数沿用系统默认。
- 不做暂停播报、结束播报、整公里合并播报等新调度语义（沿用阶段 2 调度器，App 侧不改规则）。
- 不做后台 / 锁屏播报，不做音频中断恢复后的重播策略、不做音乐 duck 恢复实听验证（`pending: 待人现场`）。
- 不改 `ios/RunCore` 任何源码与契约（状态机、度量、播报调度、AudioSession 配置值、归档、GPX），不改 `ios/Core`。
- 不做历史详情 / GPX 分享 / 端到端证据脚本（后续波次）；不改 Android、`shared/`、`ios/project.yml` 依赖、`.github/workflows/*`。
- 不做真机验证与 TTS 实听结论，不推 tag、不动 Release、不关闭上集 `cp-stage2-exit`。
- 不新增第三方依赖，也不扩展 App import 允许表。

## 实现约束

- **偏好存储**：新增 `ios/PurePace/Settings/AnnouncementSettingsStore.swift`（`@MainActor final class ... : ObservableObject`），构造注入 `UserDefaults`（默认 `.standard`，测试用独立 suite 并自行清理），单一常量键 + 默认值 `true`，`isEnabled` 与 `setEnabled(_:)` 读写同一键；键名在类型内单点定义，禁止散落字面量。
- **设置页**：`ios/PurePace/Settings/SettingsView.swift` 改为接收该存储并渲染 `Toggle("每公里语音播报", isOn: ...)` + `accessibilityIdentifier("settings.announcementToggle")`；保留 NavigationStack 与标题，删除 `settings.empty` 与「暂无可配置项」文案。
- **播报器**：新增 `ios/PurePace/Audio/AnnouncementSpeaker.swift`，内含
  - `protocol AnnouncementSpeaking`（`func speak(_ command: AnnouncementCommand)`，便于测试 spy）；
  - `protocol SpeechSynthesizing`（最小合成接缝：`speak(utterance text: String)` + 语音结束/取消回调注册），生产实现包装 `AVSpeechSynthesizer`；
  - `SpeechAnnouncementSpeaker`：持有 `AudioSessionAdapter`（可注入，测试传 `observesInterruptions: false`）、合成器与文案纯函数；顺序固定 `beginAnnouncement()` → 一次 `speak` → 结束/取消回调中 `endAnnouncement()`；会话调用抛错时吞掉并继续（不打断跑次），也不重复停用。
  - 文案生成放在同文件（或同目录）纯函数，输入 `AnnouncementCommand`，输出形如「已完成第 1 公里，用时 05:30」的短句；只依赖 Foundation，不写进 `RunCore`。
- **ViewModel**：`init` 增加 `announcements: AnnouncementSpeaking` 与 `announcementsEnabled: Bool = true` 参数（默认生产播报器），构造编排器时透传开关；新增 `setAnnouncementsEnabled(_:)` 只转调 `orchestrator.setAnnouncementsEnabled`；`apply(_ update:)` 中按序对 `update.announcements` 调 `speak`；`finish()` 路径不额外播报。
- **装配**：`ios/PurePace/ContentView.swift` 用 `@StateObject` 持有偏好存储，注入 `RunSessionViewModel` 与 `SettingsView`，并用 `.onChange(of: isEnabled)` 调用 `runModel.setAnnouncementsEnabled(_:)`（不引入 Combine，避免扩允许表）。
- **测试**：
  - `ios/PurePaceTests/AnnouncementSettingsStoreTests.swift`：默认开启、关闭/开启持久化、键唯一。
  - `ios/PurePaceTests/AnnouncementSpeakerTests.swift`：复用 `AudioSessionAdapterTests` 的 `AudioSessionSpy` 模式（可复制为独立私有 spy）断言 speak 次数、文案与激活/停用顺序、取消路径、无命令零调用。
  - 扩充 `ios/PurePaceTests/RunSessionViewModelTests.swift`：注入 spy 播报器，覆盖每公里一次、关断零次、重开不补播、暂停/结束静默。
  - 扩充 `ios/PurePaceUITests/RunFlowUITests.swift`：Settings 开关可见 + 翻转 + 重启保持；`toggle.switches` 用 `value as? String` 断言 "1"/"0"。
- **门禁**：`scripts/check-ios-shell.sh` 中 `live_sources` 增加两个新源文件、`unit_tests` 增加两个新测试文件；Settings 段断言改写如 ac-shell-gate-updated；`run_self_test` 补 Settings 断言的正负样例（含「有 Toggle + 正确标识」通过、「无 Toggle」与「含示例数值」失败），保持全部 self-test 通过。
- **口径**：结论只写「配置与调度契约通过」「代码层断言通过」；TTS 实听、音乐 duck 恢复、真机与锁屏连续播报一律 `pending: 待人现场`，不得写「实听通过」或「真机已验证」。
