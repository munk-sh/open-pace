# 单页跑步 UI 与真实 CoreLocation 接入

## 范围

把 `ios/PurePace` 从空壳占位页换成真实跑步闭环（波 1 最小集），App 侧只做接线，不重写 RunCore：

1. **Tab 收敛**：首屏 `TabView` 由 Run / History / Log / Settings 四 Tab 收敛为 Run / History / Settings 三 Tab，移除无业务的 Log；非 Harness 启动路径仍然直落跑步页（0 秒可用，无登录/引导/样例加载）。
2. **真实定位数据源**：新增 `ios/PurePace/Location/`，用 `CLLocationManager`（`.fitness` / `desiredAccuracyBest` / `distanceFilter = none` / 不自动暂停）产出 `RunSample`；`.notDetermined` 时请求「使用期间」授权，授权后自动继续，拒绝时显示诚实等待态且不伪造进度。
3. **会话 ViewModel**：新增 `RunSessionViewModel`（主线程可观测），持有既有 `RunSessionOrchestrator` + `RunCheckpointStore` + `RunArchiveStore`，把 delegate 采样转成 `ingest`，把 `start / pause / resume / finish` 转成编排器动作；距离、时长、平均/当前配速、整公里分段一律读 `orchestrator.metrics` / `acceptedSamples`，App 内不自建计时器或距离公式。
4. **单页跑步 UI**（`ios/PurePace/Run/`）：实时展示距离、活跃时长、当前配速、平均配速、已完成分段数；提供开始 / 暂停 / 恢复 / 结束按钮（按状态互斥可见）；结束后显示「已保存」反馈，且再次触发结束不产生第二条记录。
5. **History / Settings 诚实态**（`ios/PurePace/History/`、`ios/PurePace/Settings/`）：History 读本机 `RunArchiveStore.list()`，无记录时给空态与「去跑一次」入口，有记录时按开始时间倒序展示真实日期 / 距离 / 时长；Settings 明确声明本阶段无可配置项，不放任何可交互假开关或示例数值。
6. **门禁与测试同步**：`scripts/check-ios-shell.sh` 里「占位页内容」断言替换为真实 UI 断言，同时保留 xcodegen 单一真源、无手写 pbxproj、构建设置、import 作用域（CoreLocation 仅 `Harness/` + 新增 `Location/`，AVFoundation 仅 `Audio/`）、定位用途与后台模式声明、Harness 七文件清单与无夹具引用、测试落点、真实构建/测试脚本调用，并保留 `--self-test` 正负反例。
7. **XCUITest 真实链路**：占位 UI 测试替换为真实流程测试，在 iPhone 16 / iOS 18.6 模拟器上以 `xcrun simctl location` 注入真实 CoreLocation 更新，走通 开始 → 数值增长 → 暂停 → 数值冻结 → 恢复 → 继续增长 → 结束 → 已保存 → History 出现 1 条。

## 验收

- ac-tabs-converged: 非 Harness 启动时 Tab 栏恰为 Run / History / Settings 三项，`Log` Tab 不再存在。
- ac-live-metrics-from-orchestrator: 注入 N 条采样后，ViewModel 对外暴露的距离 / 时长 / 平均配速 / 当前配速 / 分段数与同一批采样喂给 `RunSessionOrchestrator` 得到的 `metrics` 逐字段相等；未开始时距离为 0、当前与平均配速均为空。
- ac-pause-zero-growth: 进入暂停后继续摄入时间递增且位移非零的采样，距离与活跃时长均保持不变，当前配速为空。
- ac-resume-continues: 恢复后的首条采样只重建位置锚点、不跨越暂停空档累计位移；其后的采样继续使距离与活跃时长单调增长。
- ac-finish-single-archive: 结束一次跑次后 `RunArchiveStore.list()` 恰返回 1 条且字段来自本次会话；对同一会话重复调用结束（含视图重复点击）不新增记录、`list()` 仍为 1 条。
- ac-saved-feedback: 结束成功后 UI 出现可被无障碍标识定位的「已保存」反馈（`run.saved`）；未结束时该元素不存在。
- ac-history-honest: 归档目录为空时 History 显示空态（`history.empty`）且不渲染任何示例跑次；存在归档时按 `startedAt` 倒序渲染真实日期 / 距离 / 时长，条数与 `RunArchiveStore.list()` 一致。
- ac-settings-honest: Settings 不包含任何可切换控件、示例数值或内置样例，并明确说明本阶段无可配置项。
- ac-no-fake-data: App 源码不含内置坐标序列、fixture 引用或 GPX/TCX 样例文件路径，也不存在以固定步长递增距离或用定时器伪造时长的逻辑（源码中不得出现 `.gpx` / `.tcx` 字面量）；距离与时长只能来自 `ingest` 后的 `metrics`。
- ac-location-scope: `CoreLocation` 只允许出现在 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`；其它目录出现即判失败（`check-ios-shell.sh --self-test` 保留该反例并通过）。App import 允许表仍为 SwiftUI / Foundation / AVFoundation / CoreLocation / PurePaceRunCore，不新增其它系统框架。
- ac-harness-intact: `ios/PurePace/Harness/` 七个文件仍存在且行为不变，`--harness direct|corelocation|resume` 的 launch-arg 路径仍可用；Harness 清单与「无夹具引用」断言保留。
- ac-gates-preserved: `.munk/code-gates.json` 原有 22 个门 id 全部保留（只增不减、command 仍为单一 argv）；`bash scripts/check-ios-shell.sh`、`bash scripts/build-ios.sh`、`bash scripts/test-ios.sh` 全部退出 0。
- ac-ui-flow-e2e: `bash scripts/test-ios.sh` 在 iPhone 16 / iOS 18.6 模拟器真实 `simctl location` 注入下，XCUITest 依次断言：开始时距离与时长从零起、运行时二者发生变化、暂停后 4 秒内距离文本不变且当前配速为空、恢复后距离再次增长、结束后出现 `run.saved`、History 出现且仅出现 1 条记录；全程不存在的样例卡片、不使用固定 `sleep` 作为成功判据。
- ac-auth-tolerated: 定位授权弹窗在「首次未授权」与「已授权」两种初始状态下，UI 测试均能继续到真实数据增长，不因系统弹窗失败。

## 非目标

- 不做历史详情页、分段详情、轨迹摘要与地图（波 2）。
- 不做 GPX 文件导出、系统分享面板，也不在 App 内调用 `RunGPXExporter`（波 2）。
- 不做每公里播报开关、真实 TTS 播放与 AudioSession 接线（波 2）；本项不新增 Settings 持久化偏好。
- 不做 `scripts/verify-ios-ui-e2e.sh` 与新增端到端门禁（波 3）；本项只保证既有 `test-ios` 门绿。
- 不改 `ios/RunCore` 任何源码与契约（状态机、度量、播报、GPX、checkpoint、归档/导出、编排器）；若实测暴露缺陷需另开项或在 digest 中说明理由后最小修正。
- 不改 `ios/Core`，不改 Android、`shared/`、`.github/workflows/*` 触发与权限，不推 tag、不动 Release。
- 不做视觉设计系统 / 自定义 token / 主题；沿用系统语义色、系统控件与 Dynamic Type，不新增 `ui-baseline` 项。
- 不做真机验证、锁屏连续定位、音乐 duck 与 TTS 实听（`pending: 待人现场`）。
- 不关闭、不降级、不重新解释上集 `cp-stage2-exit`。

## 实现约束

- **复用优先**：`RunSessionOrchestrator` / `RunCheckpointStore` / `RunArchiveStore` / `RunRecord` / `RunMetrics` 已是公开契约，直接使用；`project.yml` 已把 `PurePaceRunCore` 接进 App 与测试 target，无需改 `project.yml` 依赖。
- **目录与文件**：新增 `ios/PurePace/Run/`、`ios/PurePace/Location/`、`ios/PurePace/History/`、`ios/PurePace/Settings/`；删除 `PlaceholderScreen.swift`、`PlaceholderCopy.swift`、`ios/PurePaceTests/PlaceholderCopyTests.swift`、`ios/PurePaceUITests/PlaceholderUITests.swift`，替换为真实文件；`check-ios-shell.sh` 的文件清单与 `ac-placeholder-ui` / `ac-tests-present` 断言必须同步改写（不得只是删断言）。
- **视图零逻辑**：`View` 只做绑定与格式化；距离/配速格式化放在纯函数（可在 `PurePaceTests` 直接断言），不写进 `RunCore`。
- **时间来源**：编排器所有动作传 `Date`；UI 显示时长只能随 `ingest` 后的 `metrics.elapsed` 变化，不得用 `Timer` 自增，不得伪造空闲时的时长变化。
- **存储路径**：归档目录与 checkpoint 文件放 App 沙盒（建议 `Documents/Runs/` 与 `Caches/` 下 JSONL），用 `FileManager` 构造 `URL`，路径由 ViewModel 注入以便 `PurePaceTests` 用临时目录断言（生产代码不留硬编码绝对路径）。
- **定位注入（XCUITest 的唯一真实链路）**：`scripts/test-ios.sh` 在 `xcodebuild test` 之前按 `iPhone 16` + `iOS 18.6` 选出并 boot 模拟器，执行 `xcrun simctl location <udid> start --speed=3 --interval=1 <p1> <p2>`（直线航点总长 ≥ 20 km，确保测试期间路线不结束，采样间隔 1 s、速率 3 m/s），测试结束在 `trap` 中 `xcrun simctl location <udid> clear`；设备或 runtime 缺失时脚本显式失败并打印诊断，不得静默跳过 UI 断言。禁止用 `--harness direct --stream` 假流替代定位注入。
- **授权处理**：优先在测试内用 SpringBoard 弹窗或 interruption monitor 点击「使用 App 期间允许」；两种初始状态都要通过，弹窗缺失时测试继续执行而不是失败。
- **无障碍标识（测试契约，必须稳定）**：`run.distance`、`run.elapsed`、`run.currentPace`、`run.averagePace`、`run.splits`、`run.start`、`run.pause`、`run.resume`、`run.finish`、`run.saved`、`history.empty`、`history.row`（多条时以 index 区分）。距离文本含单位并可比较字符串变化，配速空态用固定占位（如 `--`）以便断言。
- **门禁写法**：不新增门；`check-ios-shell.sh` 仍使用 `grep -Fq 'xcodebuild test'` 等真实脚本断言；新增 `Location/` 允许目录时同步扩展 import 允许表并补「其它目录出现 CoreLocation 判失败」反例。
- **统计口径**：本波只跑模拟器 + 代码层，文案只写「模拟器链路通过」「代码层断言通过」，不得出现「真机已验证」「阶段 2/3 已通过」。
