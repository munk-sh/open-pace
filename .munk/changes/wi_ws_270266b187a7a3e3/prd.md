# 跨进程恢复契约补齐（最后采样点、已播序号、引擎恢复入口）

## 范围

在 `ios/RunCore`（模块 `PurePaceRunCore`）内把「杀进程后继续同一次跑步」的纯逻辑契约补齐，仍不接平台框架、不接 UI、不写 Harness：

1. `RunCheckpoint` 增加两个可选字段并保持旧格式可解码：最后采样点（纬度/经度/时间戳，供恢复时间与位置锚点）与已播公里序号（供播报去重）。
2. `RunMetricsEngine` 增加从 checkpoint 恢复的入口：还原累计距离、活跃时长、已完成分段、分段计时基准与最后采样锚点；恢复语义与 `RunSessionMachine(restoring:)` 一致（`running`/`paused` → 暂停态，必须显式 resume 才继续累计）。
3. 引擎暴露「最后被接受的采样点」，使上层能凭 `metrics` + 该采样点 + 调度器的已播序号构造下一条 checkpoint。
4. `AnnouncementScheduler` 增加从已播公里序号恢复的入口，重启后同序号公里不再重复播报，新公里仍恰好播报一次。

只做契约与单测；落盘时机、CoreLocation 适配、terminate→relaunch 编排归波 2 后续子项。

## 验收

- ac-checkpoint-last-sample-roundtrip: 携带最后采样点（纬度/经度/时间戳）的 `RunCheckpoint` 经 JSON 编码→解码后三字段数值相等；经 `RunCheckpointStore.append` → `loadLatest` 落盘往返后同样相等。
- ac-checkpoint-announced-index-roundtrip: 携带已播公里序号的 checkpoint 编码/解码与 store 落盘往返后序号不变。
- ac-checkpoint-legacy-decode: 不含「最后采样点」与「已播公里序号」两个键的旧格式 JSON 行可正常解码，两字段均为 `nil`，其余字段（版本、状态、距离、时长、分段、记录时间）不变；`RunCheckpointStore.loadAll` 读取新旧行混合的文件时两行都计入有效记录。
- ac-checkpoint-new-field-validation: 最后采样点坐标越界、时间戳为 `distantPast`/`distantFuture`、或已播序号为负数、或已播序号大于 `splits.count` 时 checkpoints 构造返回 `nil`（非法值无法入库）。
- ac-checkpoint-ready-no-sample: `state == .ready` 的 checkpoint 不得携带最后采样点（构造返回 `nil`），避免恢复出「已开始」的伪锚点。
- ac-engine-restore-ledger: 从 `distance=2500m`、`elapsed=900s`、`splits` 序号 1..2 的 checkpoint 恢复后，`metrics.distance == 2500`、`elapsed == 900`、`splits` 序号 1..2、`completedKilometers == 2`，平均配速等于 `elapsed / (distance/1000)`。
- ac-engine-restore-paused-state: 从 `state == .running` 或 `state == .paused` 的 checkpoint 恢复的引擎处于暂停态：未 `resume` 前 `ingest` 不改变 `distance` / `elapsed` / `splits`；`resume(at:)` 后恢复累计。
- ac-engine-restore-continues-splits: 恢复后 resume 并继续喂点跨过 3 km，新完成分段从序号 3 开始，不重复产出 1/2；第 3 段 `duration` ≈ 恢复后累计 `elapsed` − 恢复的 `splits` 时长之和（±1e-6 s），累计距离 ≈ 恢复值 + 恢复后新增位移。
- ac-engine-restore-anchor: 从携带最后采样点的 checkpoint 恢复后，喂入 `timestamp` 等于该采样点时间戳的样本被丢弃（`distance`/`elapsed`/`splits` 不变）；喂入更晚时间、相同坐标的样本只增加 `elapsed`（等于时间差），`distance` 不变。
- ac-engine-restore-no-sample-anchor: 从无最后采样点（旧格式）的 checkpoint 恢复后，首个被接受的样本只建立锚点：`distance`/`elapsed` 不增加；其后样本才累计位移。
- ac-engine-restore-finished: 从 `state == .finished` 的 checkpoint 恢复的引擎已结束：后续 `ingest` / `finish` 不改变 `metrics`。
- ac-engine-exposes-last-sample: 运行中的引擎暴露的最后被接受采样点坐标与时间戳等于最后一次 `ingest` 的样本；未接受任何样本或从无最后采样点的 checkpoint 恢复时为 `nil`；从含最后采样点的 checkpoint 恢复后等于该值。
- ac-scheduler-restore-no-repeat: 以已播序号 2 恢复的 `AnnouncementScheduler`，首次 `tick(state: .running, newlyCompletedSplits: [1, 2])` 返回空数组；随后 `tick` 携带新完成分段 3 恰好返回 1 条 `splitIndex == 3` 的 `.kilometerCompleted` 命令，重复同一 `tick` 再返回空。
- ac-scheduler-restore-default: 未给已播序号（`nil` 或 0）恢复的调度器与全新调度器行为一致：只有分段 1 的首次 `tick` 仍返回 1 条命令。
- ac-swift-test-green: `swift test --package-path ios/RunCore` 全部通过；既有 34 个用例的断言语义不变（只新增用例，不删改既有断言）。
- ac-gates-no-regression: `bash scripts/check-ios-run-core.sh` 与 `swift build --package-path ios/RunCore` 通过；`.munk/code-gates.json` 门禁数量不减少，不新增门。

## 非目标

- 不实现 checkpoint 的写盘时机与快照节流（谁在何时 `append` 归波 2 Harness / 编排子项）；本项只交付可落盘、可恢复的契约。
- 不持久化 `finished` 收尾播报状态；重启后 `.finished` 会话是否重发收尾命令由上层决定，不在本项保证范围内（本项只保证公里播报不重复）。
- 不改 `RunCheckpointStore` 的既有语义：文件即真源、JSONL 一行一条、尾行损坏静默丢弃、非尾行抛 `corruptedCheckpoint`；不引入内存缓存、多进程锁或格式压缩。
- 不改状态机合法迁移矩阵、播报 exactly-once / 去抖 / `paused→running` 最多补播 1 条 / `finished` 单条收尾的既有语义。
- 不放宽度量阈值（距离 1%、配速 2 s/km、分段边界 ±1 采样点），不改包平台声明与零第三方依赖。
- 不新增平台框架引用（CoreLocation/AVFoundation/SwiftUI/UIKit 等）、不接 App target / Harness、不跑 `simctl` / `xcodebuild`、不写 `verify-ios-sim-runtime.sh`。
- 不改 `scripts/**`、`.munk/code-gates.json` 门禁数量、`.github/workflows/*`、`ios/Core`、`ios/PurePace`、`ios/project.yml`、`shared/**`、`android/**`、`VERSION`、`README.md`、`AGENTS.md`。
- 不写 `tech.md`；本项不产出任何真机或「已验证」类结论，真机项继续 `pending: 待人现场`。

## 实现约束

- 落点：`ios/RunCore/Sources/PurePaceRunCore/{RunCheckpoint.swift, RunMetricsEngine.swift, AnnouncementScheduler.swift}` 与 `ios/RunCore/Tests/PurePaceRunCoreTests/`（可新增测试文件）；不新建 executable target。
- 向后兼容硬要求：新字段一律可选、构造参数带默认 `nil`、手写 `Codable` 用 `decodeIfPresent` 解码，缺键与 `null` 都必须解出 `nil`；已写出的旧 JSONL 不得因本项改动变成「非尾行损坏」。
- 恢复语义与 `RunSessionMachine(restoring:)` 对齐：`running`/`paused` 一律恢复为暂停态（禁止重启后静默冒充 running），`finished` 恢复为已结束，`ready` 恢复为未开始；恢复本身不改写 checkpoint 数据。
- 分段计时基准不新增 checkpoint 字段：恢复时由 `splits` 的 `duration` 累加还原「上一分段完成时的活跃时长」。
- 既有工程红线照旧：仅 `import Foundation`、零第三方依赖、`struct` + 显式 `Sendable`、无 `class`/`actor`/锁/全局可变状态；命名不得包含 `Timer` 子串；测试用 XCTest、时间用 `Date(timeIntervalSince1970:)` 合成、临时目录用 `UUID()` 子目录并清理。
- 本项显式覆盖基线 `ios-runcore` 中「checkpoint 不新增已播公里」的旧非目标；基线文档已约 32.6 KB（接近体积上限），落基线时新增条目需精简或替换旧条目。
- 自检命令（Coding 结束前必跑）：`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore`、`bash scripts/check-ios-run-core.sh`；证据只报真实输出摘要与用例数，不写「已验证」。
