# 计时、距离、当前/平均配速与公里分段

WorkSet 子项 `track-metrics-splits`（波 1，前置 `run-core-bootstrap` 已交付 `ios/RunCore` 包与 8 类契约）。本项只在 `PurePaceRunCore` 内实现坐标/时间流驱动的度量引擎：累计距离（Haversine）、活跃时长、当前/平均配速、每公里分段与累计；不接 UI、不接平台框架、不解析文件。

## 范围

1. 在 `ios/RunCore/Sources/PurePaceRunCore/` 新增纯逻辑度量能力（仅 `import Foundation`，全部 `Sendable`，无 `class`/`actor`/全局可变状态）：
   - **Haversine 距离函数**：公开纯函数，输入两组经纬度返回米；地球平均半径常量写死 `6_371_000.0`（与 `shared/fixtures/README.md` 的 `derived_distance_m: 691.2` / 实测 691.16 m 口径一致）。
   - **度量引擎**：值类型（`struct`），对外唯一输入接口为「单个 `RunSample`」，外加 `start(at:)` / `pause(at:)` / `resume(at:)` / `finish(at:)` 四个时间锚点方法；平台适配器（CoreLocation）与直接 JSONL 流适配器都只负责把各自数据转换成 `RunSample` 后喂入，引擎内部不含时间格式化、文件、网络、JSON 解析。
   - **输出快照**：累计 `RunDistance`、活跃 `elapsed`（`TimeInterval`）、`averagePace: RunPace?`、`currentPace: RunPace?`、已完成分段 `[RunSplit]`、已跨过的整公里计数；单次 `ingest` 返回新增分段列表（供后续「每公里播报调度」子项直接消费）。
   - **阈值硬编码**：滑动窗口、最小有效距离/时长、分段长度等常量在源码内以命名常量写死，不做配置化、不读环境变量。
2. 在 `ios/RunCore/Tests/PurePaceRunCoreTests/` 新增 XCTest 用例（沿用现有 XCTest 风格，禁用 Swift Testing），用合成 1 Hz 流锁定距离/配速/分段阈值与边界行为。
3. 不新增脚本、不新增门禁条目：既有 `lint-ios-run-core` / `build-ios-run-core` / `test-ios-run-core` 三门继续覆盖本项（可回归行为在该 test 门内真实执行）。若 Coding 判断确实需要新增结构断言，只能**追加**门禁，不得删改既有 19 门。

## 验收

- ac-first-sample-no-metrics: 首个被接受的 `RunSample` 只建立锚点——`distance == 0`、`elapsed == 0`、`averagePace == nil`、`currentPace == nil`、`splits.isEmpty`；其后第一个有效点才产生非零距离。
- ac-haversine-constant: 距离函数使用常量地球半径 `6_371_000.0`（单测直接断言该常量值）；对 4 个合成坐标点（纬 31.2304→31.2358、经 121.4737→121.4773，逐点 +0.0018/+0.0012）累加得 `691.16 m ± 0.05 m`，与 `shared/fixtures/README.md` 的 `derived_distance_m: 691.2` 口径一致。
- ac-distance-error-le-1pct: 对 5:00/km 与 7:00/km 两条合成 1 Hz 流（各 ≥ 600 点、恒定航向），引擎累计距离相对误差 `≤ 1.0%`（与同流独立 Haversine 逐段累加值比较）。
- ac-average-pace-error-le-2s: 上述两条恒定配速流，`averagePace.secondsPerKilometer` 相对真值误差 `≤ 2.0 s/km`。
- ac-current-pace-error-le-2s: 恒定配速流中，滑动窗口预热完成后（窗口内有效距离达到最小阈值之后的每个采样点）`currentPace` 误差 `≤ 2.0 s/km`；预热期为 `nil` 而非返回不可靠值。
- ac-split-boundary-within-1-sample: 每公里分段序号从 1 连续递增；第 n 段完成的采样点，与「累计距离首次 ≥ n×1000 m」的理论最近采样点相差 `≤ 1` 个采样点；每段 `RunSplit.distance == 1000.0 m`（差值 < 1e-9）、`duration > 0` 且为该段活跃时长差，`pace` 非 `nil`。
- ac-split-cumulative-consistency: 任意快照满足 `splits.count` 等于已跨过整公里计数，且 `Double(splits.count) * 1000 <= distance.meters + 1e-9`；`splits.count` 单调不减，已发出的分段不被后续采样改写或重复发出。
- ac-duplicate-point-zero-delta: 与上一点经纬度完全相同的样本（时间更晚）产生 0 m 增量，不改变 `splits`，不新增整公里计数；其活跃时长按正常计时推进。
- ac-time-regression-ignored: `timestamp <= 上一个已接受采样点` 的样本被整条丢弃——距离、活跃时长、分段、整公里计数全部与丢弃前完全一致（不产生负增量、不回退）。
- ac-pause-excludes-time-and-distance: `pause(at:)` 期间 `elapsed` 冻结、`currentPace == nil`；暂停区间的采样点（含坐标位移）不累计距离与活跃时长；`resume(at:)` 后恢复累计，暂停空档不计入 `elapsed`，跨越暂停的相邻两点之间不产生位移。
- ac-idempotent-anchors: 重复 `start`/`pause`/`resume`/`finish` 调用（含未 `start` 直接 `ingest`）不崩溃、不产生负时长或非有限值；非法锚点时间（早于当前账本时间）被忽略而非反向计时。
- ac-pure-foundation-and-no-io: 新增源码仅 `import Foundation`；`bash scripts/check-ios-run-core.sh` 全部 `[PASS]`（无平台框架符号、无夹具令牌、无版本字面值、XCTest only）。
- ac-existing-tests-still-pass: `swift test --package-path ios/RunCore` 退出码 0，既有 17 个用例仍通过，新增用例数 ≥ 8（覆盖上述各条边界）。
- ac-gates-not-reduced: `.munk/code-gates.json` 现有 19 个 `id` 全部保留且 command 不变；`bash scripts/check-baseline.sh` 仍全部 PASS。
- ac-no-ui-or-platform-change: 未修改 `ios/PurePace/**`、`ios/project.yml`、`ios/PurePace.xcodeproj`、`shared/**`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`；未接 CoreLocation/AVFoundation，未新增任何 UI 或可执行 target。

## 非目标

- 不实现会话状态机迁移合法性（合法/非法迁移判定归同波状态机子项）；本引擎只做计时/距离账本，`start`/`pause`/`resume`/`finish` 幂等而不做状态辩论。
- 不实现每公里播报调度与去重、AudioSession 协调器、GPX 导出、checkpoint 持久化（分别归后续子项）；本项只保证 `ingest` 返回新增分段供其消费。
- 不写 JSONL 解析器、不读文件、不接 `CLLocationManager`、不做精度过滤/首点漂移剔除策略（适配器侧职责），不写 `scripts/verify-ios-sim-runtime.sh`。
- 不调整既有契约类型的字段与校验语义（`RunSample`/`RunSplit`/`RunPace`/`RunDistance` 保持原样；若确需扩展只能新增类型）。
- 不新增/修改 project.yml 与 `.xcodeproj`，不做 XcodeGen 接入本地包，不改 CI workflow，不写 `tech.md`，不碰 Host 托管文件。
- 不做真机、模拟器、推送与 CI 结论；真机项维持 `pending: 待人现场`。

## 实现约束

- 落点：新增文件放 `ios/RunCore/Sources/PurePaceRunCore/`（建议 `GeoDistance.swift` + `RunMetricsEngine.swift`，可再拆 `RunMetrics.swift` 快照类型），测试放 `ios/RunCore/Tests/PurePaceRunCoreTests/`；模块名仍是 `PurePaceRunCore`，UI/适配器直接 `import PurePaceRunCore`。
- 输入口唯一：`ingest(_ sample: RunSample) -> RunMetricsUpdate`；`RunMetricsUpdate` 至少含当前快照与 `newlyCompletedSplits: [RunSplit]`。不为 JSONL / CoreLocation 各开一套接口，避免两套逻辑漂移。
- 时间基准：以 `RunSample.timestamp`（`Date`）差值计算活跃时长；暂停区间与时间倒退样本不计入；不引入时区/格式化逻辑。
- 硬编码常量（建议值，Coding 可按测试微调但不得放宽验收阈值）：地球半径 `6_371_000.0`；每公里分段 `1000.0` m；当前配速滑动窗口 `10.0` s 活跃时间；窗口最小有效距离 `5.0` m 且最小活跃时长 `3.0` s（不满足则 `currentPace == nil`）。
- 分段口径：`RunSplit.distance` 固定 `1000.0`，`index` 从 1，`duration` 为跨越点活跃时长减去上一跨越点活跃时长；未满整公里的尾巴只体现在 `distance` 与 `currentPace`，不生成 `RunSplit`。
- 精度：距离用 `Double` 双精度，Haversine 需 `min(1.0, sqrt(h))` 防 `asin` 定义域越界；比较断言用容差（距离 1e-6 m、配速 1e-6 s/km），不用字符串格式化。
- 结构红线（`check-ios-run-core.sh` 会真扫）：`Sources/**` 只 `import Foundation`；不得出现 `CoreLocation|CLLocationManager|AVFoundation|AVFAudio|AVAudioSession|CoreMotion|MapKit|HealthKit|SwiftUI|UIKit|UserNotifications|URLSession|CoreData|SQLite|SwiftData|Timer` 任一子串（注意别把类/常量命名成含 `Timer` 的词）；整个 `ios/RunCore/**` 不得出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 令牌或根 `VERSION` 当前字面值。
- 并发：Swift 6 严格并发，全部 `struct`/`enum` 值类型并显式 `Sendable`；不加 `@unchecked`、不加锁、不引入 actor。
- 测试数据：合成坐标流在测试内用固定公式生成（经纬度按每点固定步长推进），不得引用夹具文件、不得读磁盘、不得用当前时间（`Date()`）导致不确定性；时间统一由固定 `Date(timeIntervalSince1970: n)` 构造。
- 夹具红线：本项不接触 `shared/fixtures` 文件；`ac-haversine-constant` 的坐标与期望值只以数值字面量写在测试内（与 README 口径对齐），不写文件路径。
- 门禁：不新增脚本、不改 `.munk/code-gates.json`；确保 `lint-ios-run-core`（结构）、`build-ios-run-core`、`test-ios-run-core` 三门本机绿，`scripts/test-ios.sh` 无需改动即已覆盖 `swift test --package-path ios/RunCore`。
