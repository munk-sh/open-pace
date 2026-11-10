# Domain: assertion-red-proof

断言真实性子域：只收紧「断言必须能判红」这一层——iOS 播报 duck 撤销语义去别名、每公里播报文案与调度反例、GPX 夹具逐字段比对进入 CI 腿。不新增业务能力；播报会话语义、遥测契约、GPX 编码契约仍分别归 `ios-audio-session` / `ios-run-telemetry` / `ios-runcore-archive`。

## 范围

- 播报结束派生事实拆源：`ios/PurePace/Audio/AudioSessionAdapter.swift` 新增 `AnnouncementEndResult{sessionDeactivated, duckRevoked}`，`endAnnouncement()` 返回该结构；`duckRevoked` =「本次激活时平台读回 `controller.categoryOptions` 含 `.duckOthers`」且「停用调用真实携带 `.notifyOthersOnDeactivation` 并成功」，`sessionDeactivated` 只来自停用调用真实成功。
- 播报器取值去别名：`ios/PurePace/Audio/AnnouncementSpeaker.swift` 的 `onFinish` 逐字段接收两个事实，`recordFinished` 不再用同一个 Bool 喂两个参数。
- 播报文案补配速：`AnnouncementText.sentence(for:)` 前缀「已完成第 N 公里，用时 MM:SS」逐字保留，句尾追加「，配速 m:ss /km」，数字口径复用 `RunFormatting.paceText`。
- 调度反例强化：`ios/RunCore/Tests/PurePaceRunCoreTests/AnnouncementSchedulerTests.swift` 公里边界用例改为每 tick 喂**累计** `newlyCompletedSplits`（模拟引擎重算重复上报），使「去掉 `lastAnnouncedSplitIndex` 过滤」判红。
- GPX 夹具比对入 CI：`.github/workflows/ios.yml` 的 `lint` 步新增独立一行 `bash scripts/check-gpx-export.sh`，不合并行、不加 `continue-on-error`、不删减既有腿、不抬高 `timeout-minutes`。
- `scripts/check-gpx-export.sh` 增加反例自证（删某个 `trkpt` 的 `<ele>`、默认命名空间改 GPX 1.0 必须判红且定位到被破坏字段）与阈值先定后测（坐标/高程 1e-6、`EXPECTED_POINT_COUNT = 4` 不设数量容差、time 同一瞬间、hr/cad 整数相等）；反例只作用于临时副本，仓库夹具零改动。
- RunCore 自包含夹具：`ios/RunCore/Tests/PurePaceRunCoreTests/GPXCodecTests.swift` 新增内联 4 点夹具逐点逐字段断言（lat/lon/ele/time/hr/cad）与两个反例（缺 `<ele>` → `altitude == nil`；GPX 1.0 命名空间 → `GPXCodecError.unsupportedNamespace`），RunCore 源码与测试均不引用 `shared/fixtures` 路径。
- 测试落点：`ios/PurePaceTests/AnnouncementSpeakerTests.swift`、`ios/PurePaceTests/AudioSessionAdapterTests.swift`、RunCore `AnnouncementSchedulerTests` / `GPXCodecTests`；不新增 gate。

## 验收

### A. duck 撤销语义（不新增盲重试、不改语义方向）

- ac-duck-independent-source: `sessionDeactivated` 与 `duckRevoked` 分别由两个互不派生的平台调用事实得出——前者 = 结束播报时 `setActive(false, …)` 真实下发且未抛错；后者 = 本次激活真实下发的 category options 含 `.duckOthers`，且结束调用真实携带 `.notifyOthersOnDeactivation` 并成功。`AnnouncementSpeaker.swift` 内不得再出现「`duckRevoked` 直接等于 `sessionDeactivated`」的同源赋值或同一个 Bool 同时喂两个参数。
- ac-duck-alias-breaker: 至少一条分叉用例判红别名实现——自定义 `AudioSessionSettings`（`options: [.mixWithOthers]` 不含 `.duckOthers`、`deactivationOptions: [.notifyOthersOnDeactivation]`）走完整成功路径时 `sessionDeactivated == true`、`duckRevoked == false`；把实现改回 `duckRevoked: sessionDeactivated` 后该用例必须失败（digest 附失败原文）。
- ac-duck-success-pair: 默认设置成功路径两字段均 `true`；平台调用序列恰为一次 `setActive(true)` + 一次 `setActive(false, options: [.notifyOthersOnDeactivation])`（以有序调用序列断言，不写次数常量）；协调器落 `.inactive`；诊断文件不新增记录。
- ac-duck-throw-path: 注入 `setActive(false)` 抛错时协调器 `state` 保持 `.active`（不提交、不回滚、无盲重试）；两字段 `false`；诊断文件新增 1 条 `outcome="failed"` 且 `errorDomain` / `errorCode` 与注入错误一致、`platformCallIssued == true`；随后同一播报器下一次播报不再下发 `setActive(true)`，其结束仍真实下发一次停用并落两字段 `true`（断言有序调用序列，禁止「重试次数」「`deactivations.count == 2`」类计数断言）。
- ac-duck-interrupted-path: 播报中进入 `.interrupted` 后结束：`deactivate()` 走 guard 返回 `.none`、无平台停用调用；两字段 `false`；诊断文件恰新增 1 条 `outcome="not-applicable"`（`errorDomain` / `errorCode` 为 null、`platformCallIssued == false`）且不存在 `failed` 记录；中断结束后下一次播报重新激活。
- ac-duck-red-proof: 成功 / 抛错 / interrupted 为三条独立测试方法（不得合并），三条都能各自判红；连同 ac-duck-alias-breaker 的判红原文进 digest（表格：接缝 → 断言名 → 文件:行 → 反例是否判红）。

### B. TTS 每公里调度与中断恢复

- ac-km-exactly-once: 连续 5 个公里边界各产生且仅产生 1 条 `.kilometerCompleted`，`splitIndex` 严格递增 1…5；反例「去掉 `lastAnnouncedSplitIndex` 过滤」必判红。
- ac-tick-debounce: 同一 `RunMetricsUpdate` 连喂 11 次只产出 1 条命令；反例「去掉去抖判断」必判红。
- ac-paused-suppressed: `.ready` / `.paused` 的 tick 一律 0 条命令且 `announcedSplitIndex` 不前进；反例「paused 也走 kilometerCommands」必判红。
- ac-finished-stops: 进入 `.finished` 至多 1 条 `.finished` 收尾命令，此后任意 tick（含新 split、再次 finished、转 paused/running）恒 0 条；0 公里时 finished 不产出；反例「移除 `didAnnounceFinish` guard」必判红。
- ac-resume-catchup-once: `paused → running` 首个 tick 对未播公里最多 1 条 `.resumedAfterPause`，多条欠账只补最后一条（`splitIndex` 取最大待播）；反例「逐条重放缺失公里」必判红。
- ac-announcement-text-fields: `AnnouncementText.sentence(for:)` 同时含距离、用时、配速三段：`splitIndex=1, elapsed=330, pace=300s/km` → 含「第 1 公里」「05:30」「5:00 /km」；前缀逐字保留，仅在句尾追加「，配速 X:YY /km」（格式与 `RunFormatting.paceText` 同口径）；反例「删掉配速子句」或「elapsed 不再格式化」必判红。
- ac-interruption-suppresses-deactivation: 播报中投递 interruption began → 结束时无 `setActive(false)`、两字段 false、诊断 1 条 `not-applicable`；反例「移除中断状态判断」必判红。
- ac-next-announcement-reactivates: 中断结束（`shouldResume == false`）后下一次播报重新下发 `setActive(true)` 且遥测 `sessionActivated == true`；反例「复用旧激活状态」必判红。
- ac-b-red-proof: 上述 8 条逐条落「断言名 → 文件:行 → 反例是否判红」；已覆盖的只做确认，缺的（文本字段）新增，不得删除既有断言。

### C. GPX 夹具断言入 CI

- ac-ci-gpx-leg: `.github/workflows/ios.yml` 的 `lint` 步新增一条独立行 `bash scripts/check-gpx-export.sh`；不得删减 `install` / `drift` / `lint` / `test` / `test-logs` / `build` 任一腿，不得加 `continue-on-error`，不得抬高任何 `timeout-minutes`；`bash scripts/check-ios-workflow.sh` 仍退出 0（允许额外独立行、禁止 `&&` / `;` 合并）。
- ac-ci-gpx-red-capable: 临时改错 `shared/fixtures/sample-run.gpx`（删某 `trkpt` 的 `ele`，或默认命名空间改 GPX 1.0）后 `bash scripts/check-gpx-export.sh` 必须非 0 退出并打印失败断言名；`git checkout -- shared/fixtures/sample-run.gpx` 后 `git diff --exit-code shared/fixtures` 为空。
- ac-runcore-fixture-driven: `GPXCodecTests.swift` 新增内联夹具驱动用例：内联 GPX（4 个 `trkpt`，lat/lon/ele/time/hr/cad 与 `shared/fixtures/sample-run.gpx` 同值）经 `GPXCodec.decode` 后逐点逐字段断言；RunCore 源码与测试不得出现 `shared/fixtures` 路径引用。
- ac-runcore-fixture-red: 同一条内联夹具两个反例必须判红——(a) 删某个 `trkpt` 的 `<ele>` → 该点 `altitude` 变 `nil`，逐字段断言失败；(b) 默认命名空间改 `http://www.topografix.com/GPX/1/0` → `decode` 抛 `GPXCodecError.unsupportedNamespace`（断言错误分支，不得静默通过）。

### D. 冻结与预算

- ac-freeze-copy-identifier: 33 项可及 identifier 集合零 diff；`Localizable.xcstrings`、UI 文案、设计 token（`DesignTokens.swift`）、`docs/evidence` 截图零 diff；本项唯一允许的字符串变更只有播报句尾新增配速子句。
- ac-android-untouched: `git diff --name-only -- android shared/fixtures .munk/code-gates.json` 为空（夹具只读引用、门定义 22 项不减）。
- ac-gates-green: `.munk/code-gates.json` 仍 22 项且 id 列表零变更、全部退出 0；其中 `test-ios-core` / `test-ios-run-core` / `test-ios --unit-only` / `lint-ios-workflow` / `check-gpx-export` 必须真实执行到新增断言。
- ac-pending-device-audio: 音频实听、真机 duck 撤销、锁屏定位等真机项保持 `pending: 待人现场`；不得出现「真机已验证」。

## 非目标

- 不改 duck/中断语义方向：不新增盲重试、失败不回滚 `.active`、不改 `.notifyOthersOnDeactivation` 既有选型。
- 不新增 gate、不新增真机/设备脚本、不跑真机；不改 Android 任何文件；不改 `shared/fixtures` 夹具内容（只读引用）。
- 不改设计 token、不改截图、不改 33 项 identifier、不改 UI 布局与可见文案（播报句尾配速子句除外）。
- 不改 `.github/workflows/android.yml`；不重构 `AnnouncementScheduler` 算法结构（只补断言与文本字段）。
- 不处理模拟器无法判定的真实音频路由/实听结论（仍 `pending: 待人现场`）。

## 实现约束

- duck 接缝：两个事实的观测点必须在 `AudioSessionAdapter`——`duckRevoked` 的激活侧事实取平台读回值（`controller.categoryOptions`，非入参 `settings`），停用侧事实取动作携带的 options；`AnnouncementEndResult` 为唯一返回载体，`endAnnouncement()` 不得退回单个 `Bool`。
- 别名判红证据必须来自 app 单测腿（`xcodebuild test -only-testing:PurePaceTests/AnnouncementSpeakerTests` 或 `bash scripts/test-ios.sh --unit-only`），`swift test --package-path ios/RunCore` 不覆盖 App 目标。
- 文案锚点：`AnnouncementText` 内复用 `RunFormatting.paceText`，不为测试放宽访问级别；新增文本单测放 `AnnouncementSpeakerTests.swift`（`@testable import PurePace`）。
- 禁止的计数断言：不得以「重试次数」「`deactivations.count == N`」「`activations.count == N`」作语义证据；一律用有序调用序列（active + options）表达，计数只可作「一条命令一次调用」的结构断言且必须同时给出序列断言。
- CI 腿锚点：`ios.yml` 的 `lint` 步保持多条独立行、无 `&&` / `;`；`scripts/check-ios-workflow.sh` 与 `scripts/check-ios-scripts.sh`（22 门/脚本拓扑）必须保持绿。
- CI 观测：run 结果由 Host guard 观测，不在会话里 `sleep` 轮询 `gh run view`；无结果时如实写 `pending: 待人现场` / `CI 未观测`，不得自称已通过。
- 证据口径：数字须标口径（断言条数 / 测试方法数 / 门数 = 22）。

## 最近交付证明

- workItemId: wi_intake_f1272798d9a999ef（2026-11-11，pass；只取代码层与模拟器单测腿证据）
- 交付：`AudioSessionAdapter` 新增 `AnnouncementEndResult` 与 `activationDuckedOthers` 平台读回事实，`endAnnouncement()` 返回两独立布尔（`duckRevoked = activationDuckedOthers && options.contains(.notifyOthersOnDeactivation)`）；`AnnouncementSpeaker.onFinish` 分字段取值，别名赋值 `duckRevoked: sessionDeactivated` 已删除；`AnnouncementText.sentence` 句尾追加「，配速 \(RunFormatting.paceText(pace))」；`AnnouncementSchedulerTests` 公里边界改喂累计 `newly`；`ios.yml` 的 `lint` 腿新增 `bash scripts/check-gpx-export.sh` 独立一行；`check-gpx-export.sh` 增反例自证两条（`red-proof-missing-ele` / `red-proof-namespace`）与阈值注释；`GPXCodecTests` 增内联 4 点夹具 + 缺 `<ele>` / GPX 1.0 两个反例。
- 验证：`code_gates` 22 门全绿（attempt 002）——`test-ios` 0 失败（`AnnouncementSpeakerTests` 14 例、`AudioSessionAdapterTests` 8 例）、`test-ios-run-core` 0 失败（`Executed 128 tests`，`GPXCodecTests` 13 例）、`check-gpx-export` 8 条断言全 PASS（含两条反例自证）、`lint-ios-workflow` PASS。
- 偏离 / 有意未做：变更包内未落 `digest.md`，PRD 要求的「接缝 → 断言名 → 文件:行 → 反例是否判红」表格与 ac-duck-alias-breaker 判红失败原文未随交付落盘（改写实现回别名再跑红的临时实验未记录）；CI run 结果未观测，按 `pending: 待人现场`；真机 duck 撤销/音频实听/锁屏定位仍 `pending: 待人现场`。
