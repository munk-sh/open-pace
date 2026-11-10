# 阶段 2 断言补齐 B：duck 撤销语义去别名 + TTS 每公里调度/中断恢复 + GPX 夹具断言入 CI

## 范围

三处金字塔缺口一次性收紧，均为「断言真实性」修复，不新增业务能力：

1. **duck 撤销语义去别名**：`AnnouncementSpeaker` 结束播报时 `duckRevoked` 目前逐字取 `sessionDeactivated`（`ios/PurePace/Audio/AnnouncementSpeaker.swift:164`），构造上两条恒等，任何断言都无法单独判红。必须让两条字段各自来自**不同的真实平台调用事实**，并补一条两者取值**会分叉**的用例，使「改回别名写法」必然判红。
2. **TTS 每公里调度/中断恢复**：现有 `AnnouncementSchedulerTests` 与 `AnnouncementSpeakerTests` 已覆盖大部分契约，需逐条确认「能判红的反例」；唯一缺口是播报文本从未被断言，且现文案 `已完成第 N 公里，用时 MM:SS` 不含配速，与设置页既有文案 `settings.announcement.body`（「朗读当前配速与累计时长」）不一致——补齐配速子句并补文本单测。
3. **GPX 夹具断言入 CI**：`scripts/check-gpx-export.sh` 的逐字段比对（fixture → 真实临时文件 → `xmllint --noout` → lat/lon/ele/time/hr/cad）**未出现在** `.github/workflows/ios.yml`，是 CI 覆盖的唯一缺口；同时补一条不依赖 `shared/fixtures` 的 RunCore 内联夹具断言。

## 验收

### A. duck 撤销语义（不新增盲重试、不改语义方向）

- ac-duck-independent-source: `sessionDeactivated` 与 `duckRevoked` 分别由两个互不派生的平台调用事实得出——`sessionDeactivated` = 结束播报时 `setActive(false, …)` 真实下发且未抛错；`duckRevoked` = 本次播报激活时真实下发的 category options 含 `.duckOthers`，且结束调用真实携带 `.notifyOthersOnDeactivation` 并成功。`ios/PurePace/Audio/AnnouncementSpeaker.swift` 内不得再出现「`duckRevoked` 直接等于 `sessionDeactivated`」形式的同源赋值或同一个 Bool 同时喂两个参数。
- ac-duck-alias-breaker: 必须以**至少一条**分叉用例判红别名实现——用自定义 `AudioSessionSettings`（例如 `options: [.mixWithOthers]` 不含 `.duckOthers`、`deactivationOptions: [.notifyOthersOnDeactivation]`）走完整成功路径时：`sessionDeactivated == true`、`duckRevoked == false`；且该用例在把实现改回 `duckRevoked: sessionDeactivated` 后**必须失败**（digest 附失败原文）。
- ac-duck-success-pair: 默认设置成功路径：两字段均为 `true`；平台调用序列恰为一次 `setActive(true)` + 一次 `setActive(false, options: [.notifyOthersOnDeactivation])`（以有序调用序列断言，不写次数常量）；协调器落 `.inactive`；诊断文件不新增记录。
- ac-duck-throw-path: 注入 `setActive(false)` 抛错：协调器 `state` 保持 `.active`（不提交、不回滚、无盲重试）；两字段 `false`；诊断文件新增 1 条 `outcome="failed"` 且 `errorDomain` / `errorCode` 与注入错误一致、`platformCallIssued == true`；随后同一播报器下一次播报**不再**下发 `setActive(true)`，其结束仍真实下发一次停用并落 `sessionDeactivated=true` / `duckRevoked=true`（断言下一次的**有序调用序列**，禁止写「重试次数」或 `deactivations.count == 2` 这类计数断言）。
- ac-duck-interrupted-path: 播报中进入 `.interrupted` 后结束：`deactivate()` 走 guard 返回 `.none`，无平台停用调用；两字段 `false`；诊断文件恰新增 1 条 `outcome="not-applicable"`（`errorDomain == null`、`errorCode == null`、`platformCallIssued == false`）且**不存在** `failed` 记录；中断结束后下一次播报重新激活。
- ac-duck-red-proof: 上述成功 / 抛错 / interrupted 为三条**独立**测试方法（不得合并成一条大断言），三条都能各自判红；连同 ac-duck-alias-breaker 的判红原文一并进 digest（表格：接缝 → 断言名 → 文件:行 → 反例是否判红）。

### B. TTS 每公里调度与中断恢复

- ac-km-exactly-once: 连续 5 个公里边界各产生且仅产生 1 条 `.kilometerCompleted`，`splitIndex` 严格递增 1…5；反例「去掉 `lastAnnouncedSplitIndex` 过滤」必判红。
- ac-tick-debounce: 同一 `RunMetricsUpdate` 连喂 11 次只产出 1 条命令；反例「去掉去抖判断」必判红。
- ac-paused-suppressed: `.ready` / `.paused` 的 tick 一律 0 条命令且 `announcedSplitIndex` 不前进；反例「paused 也走 kilometerCommands」必判红。
- ac-finished-stops: 进入 `.finished` 至多 1 条 `.finished` 收尾命令，此后任意 tick（含携带新 split、再次 finished、转 paused/running）恒 0 条；0 公里时 finished 不产出；反例「移除 `didAnnounceFinish` guard」必判红。
- ac-resume-catchup-once: `paused → running` 首个 tick 对未播公里最多 1 条 `.resumedAfterPause`，多条欠账只补最后一条（`splitIndex` 取最大待播）；反例「逐条重放缺失公里」必判红。
- ac-announcement-text-fields: `AnnouncementText.sentence(for:)` 输出必须同时含距离、用时、配速三段：`splitIndex=1, elapsed=330, pace=300s/km` → 文本含「第 1 公里」「05:30」「5:00 /km」；既有前缀「已完成第 N 公里，用时 MM:SS」逐字保留，仅在句尾追加「，配速 X:YY /km」（配速数字格式与 `RunFormatting.paceText` 同口径）；反例「删掉配速子句」或「elapsed 不再格式化」必判红。
- ac-interruption-suppresses-deactivation: 播报中投递 interruption began → 结束时无 `setActive(false)`、两字段 false、诊断 1 条 `not-applicable`；反例「移除中断状态判断」必判红。
- ac-next-announcement-reactivates: 中断结束（`shouldResume == false`）后下一次播报重新下发 `setActive(true)` 且遥测 `sessionActivated == true`；反例「复用旧激活状态」必判红。
- ac-b-red-proof: 上述 8 条逐条在 digest 落「断言名 → 文件:行 → 反例是否判红」；已存在且已覆盖的用例只做确认，缺的（文本字段）新增，不得删除既有断言。

### C. GPX 夹具断言入 CI

- ac-ci-gpx-leg: `.github/workflows/ios.yml` 的 `lint` 步（当前 110–115 行，4 条独立脚本行）**新增一条独立行** `bash scripts/check-gpx-export.sh`；不得删减 `install` / `drift` / `lint` / `test` / `test-logs` / `build` 任一腿，不得加 `continue-on-error`，不得抬高任何 `timeout-minutes`；`bash scripts/check-ios-workflow.sh` 仍退出 0（其 `ac-lint-step-reuses-local-gates` 允许额外独立行、禁止 `&&` / `;` 合并）。
- ac-ci-gpx-red-capable: 把 `shared/fixtures/sample-run.gpx` 临时改错（删某个 `trkpt` 的 `ele`，或把默认命名空间改成 GPX 1.0）后 `bash scripts/check-gpx-export.sh` 必须非 0 退出并打印失败断言名；`git checkout -- shared/fixtures/sample-run.gpx` 后 `git diff --exit-code shared/fixtures` 为空（夹具内容最终零 diff）。
- ac-runcore-fixture-driven: `ios/RunCore/Tests/PurePaceRunCoreTests/GPXCodecTests.swift` 新增一条内联夹具驱动用例：内联 GPX（4 个 `trkpt`，lat/lon/ele/time/hr/cad 取值与 `shared/fixtures/sample-run.gpx` 同值：`31.2304/121.4737/12.0/08:00:00Z/112/82` …）经 `GPXCodec.decode` 后逐点逐字段断言；RunCore 源码与测试均不得出现 `shared/fixtures` 路径引用。
- ac-runcore-fixture-red: 对同一条内联夹具做两个反例必须判红——(a) 删掉某个 `trkpt` 的 `<ele>` → 该点 `altitude` 变 `nil`，逐字段断言失败；(b) 默认命名空间改成 `http://www.topografix.com/GPX/1/0` → `decode` 抛 `GPXCodecError.unsupportedNamespace`（断言错误分支，不得静默通过）。

### D. 冻结与预算

- ac-freeze-copy-identifier: 33 项可及 identifier 集合零 diff；`ios/PurePace/Resources/Localizable.xcstrings` 与 UI 文案、设计 token（`DesignTokens.swift`）、`docs/evidence` 截图零 diff；本项唯一允许的字符串变更只有播报句尾新增配速子句（ac-announcement-text-fields），UI 可见文案不动。
- ac-android-untouched: `git diff --name-only -- android shared/fixtures .munk/code-gates.json` 为空（夹具只读引用、门定义 22 项不减）。
- ac-gates-green: `.munk/code-gates.json` gates 仍为 22 项且 id 列表零变更，全部退出 0；其中 `test-ios-core` / `test-ios-run-core` / `test-ios --unit-only` / `lint-ios-workflow` / `check-gpx-export` 必须真实执行到新增断言。
- ac-pending-device-audio: 交付文档中音频实听、真机 duck 撤销、锁屏定位等真机项保持 `pending: 待人现场`；不得出现「真机已验证」。

## 非目标

- 不改 duck/中断的语义方向：不新增盲重试、失败不回滚 `.active`、不改 `.notifyOthersOnDeactivation` 的既有选型方向。
- 不新增 gate、不新增真机/设备脚本、不跑真机；不改 Android 任何文件；不改 `shared/fixtures` 夹具内容（只读引用）。
- 不改设计 token、不改截图、不改 33 项 identifier、不改 UI 布局与可见文案（播报句尾配速子句除外）。
- 不改 `.github/workflows/android.yml`；不重构 `AnnouncementScheduler` 的算法结构（只补断言与文本字段）。
- 不处理模拟器无法判定的真实音频路由/实听结论（仍 `pending: 待人现场`）。

## 实现约束

- **duck 接缝锚点**：`ios/PurePace/Audio/AnnouncementSpeaker.swift:132-166`（`onFinish` 派生 + `recordFinished`）、`:164`（当前别名赋值）；`ios/PurePace/Audio/AudioSessionAdapter.swift:126-152`（`beginAnnouncement` / `endAnnouncement` 现返回单个 `Bool`，需能分别暴露「停用调用成功」与「本次确实应用 duck 且停用携带 notify 选项」两个事实，例如返回结果结构体；`perform` 已能看到真实下发的 options）；`AudioSessionSettings`（`ios/RunCore/Sources/PurePaceRunCore/AudioSessionSettings.swift:45-50`）可注入自定义 settings 以构造分叉用例。
- **别名判红证据**：临时把 `duckRevoked` 改回 `sessionDeactivated`，运行 `swift test --package-path ios/RunCore` 不覆盖 App 目标，故判红证据必须来自 app 单测腿：`xcodebuild test -only-testing:PurePaceTests/AnnouncementSpeakerTests`（或 `bash scripts/test-ios.sh --unit-only`）中的 ac-duck-alias-breaker，摘录 `XCTAssert` 失败原文进 digest。
- **TTS 文本锚点**：`ios/PurePace/Audio/AnnouncementSpeaker.swift:63-69`（`AnnouncementText`）；可复用 `ios/PurePace/Run/RunFormatting.swift` 的 `paceText` 口径；新单测放 `ios/PurePaceTests/AnnouncementSpeakerTests.swift`（`@testable import PurePace`），不得为测试改公开性。
- **CI 腿锚点**：`.github/workflows/ios.yml:110-115`（`lint` step，4 条独立行、无 `&&`/`;`）；`scripts/check-ios-workflow.sh:162-173` 必须保持绿；`scripts/check-ios-scripts.sh:441-455` 的 22 门/脚本拓扑断言不得被破坏。
- **禁止的计数断言**：不得新增「重试次数」「`deactivations.count == 2`」「`activations.count == N`」这类魔法计数作为语义证据；用**有序调用序列**（active + options）表达，计数只允许作为「一条命令一次调用」的直接结构断言且必须同时给出序列断言。
- **CI 观测方式**：CI run 结果由 Host guard 观测，不得在会话里 `sleep` 轮询 `gh run view`；无 CI 结果时如实写 `pending: 待人现场` 或 `CI 未观测`，不得自称已通过。
- **预算**：≤ 8M token / ≤ 90 分钟；超限交半成品并逐条列出未完成项。
- **交付 digest 格式**：表格列为「接缝 → 断言名 → 文件:行 → 反例是否判红」，另写明 ios.yml 改了哪条腿、数字口径（断言条数 / 测试方法数 / 门数 = 22）。
