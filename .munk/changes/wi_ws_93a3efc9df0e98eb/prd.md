# 会话状态机、中断恢复与 checkpoint 存储

WorkSet 子项 `session-lifecycle-store`（波 1）。前置子项 `run-core-bootstrap` 已在 `ios/RunCore` 冻结领域值类型契约（17 个用例、`lint/build/test-ios-run-core` 三门全绿）。本项在**同一包内**实现会话状态机与真实文件 checkpoint 存储及其恢复语义，全部为纯逻辑 + Foundation 文件 IO，不进入 View、App target 或平台适配层。

## 范围

1. 状态机（`Sources/PurePaceRunCore/` 新增源文件，不改既有类型语义）：
   - 复用既有 `RunSessionState`（`ready/running/paused/finished`）。**`idle` 一律等同现有 `ready`，不新增/重命名枚举 case**（`RunSessionStateTests` 已锁定 `allCases` 顺序与 rawValue）。
   - 新增公开值类型 `RunSessionMachine`（`struct`、`Equatable`、`Sendable`），持有 `state: RunSessionState`，提供：
     - `init(state: RunSessionState = .ready)`；
     - `canTransition(to:) -> Bool`；
     - `mutating func transition(to:) throws`，非法迁移抛 `RunCoreError.invalidStateTransition(from:to:)` 且 `state` 保持不变；
     - 语义化入口 `start()`（ready→running）、`pause()`（running→paused）、`resume()`（paused→running）、`finish()`（running/paused→finished），均复用同一迁移校验。
   - 合法迁移矩阵**恰为 5 条**：`ready→running`、`running→paused`、`running→finished`、`paused→running`、`paused→finished`。其余 11 种组合（含所有自迁移、`ready→paused/finished`、`finished→*`）一律非法。
2. checkpoint 值类型：
   - 新增公开 `RunCheckpoint`（`struct`、`Equatable`、`Sendable`、手写 `Codable`），字段：`formatVersion: Int`（当前唯一合法值 1）、`state: RunSessionState`、`completedDistance: RunDistance`、`elapsed: TimeInterval`、`splits: [RunSplit]`、`recordedAt: Date`。
   - `init?` 校验：`elapsed` 有限且 `>= 0`；`splits` 的 `index` 必须是从 1 开始、步长 1 的连续序列（`1...n`）；`recordedAt` 不得为 `distantPast`/`distantFuture`；任一不满足返回 `nil`。`state == .ready` 时 `completedDistance.meters == 0 && splits.isEmpty` 才合法。
   - 解码侧：`init(from:)` 对未知 `formatVersion`、非有限 `elapsed`、非连续 `splits` 抛错（供 store 归一为 `corruptedCheckpoint`）。
3. checkpoint 存储 `RunCheckpointStore`（`struct`，持有 `fileURL: URL`；仅 `Foundation`）：
   - `init(fileURL: URL)`；
   - `func append(_ checkpoint: RunCheckpoint) throws`：以 JSONL（一行一个 JSON、UTF-8、以 `\n` 结尾）**追加**写真实文件；父目录不存在时创建；每次调用独立打开/关闭文件句柄，返回后磁盘内容可被新实例读到；单次写入不重写历史行。
   - `func loadAll() throws -> [RunCheckpoint]`：按行解析；缺失文件视为空数组返回；
   - `func loadLatest() throws -> RunCheckpoint?`：缺失/空文件返回 `nil`，否则返回最后一条**有效**记录；
   - `func reset() throws`：删除文件（不存在时幂等成功）。
   - 容错规则（必须可区分）：
     - **尾行**（最后一行）不完整/无法解码/字段非法 → 静默丢弃，返回其前一条有效记录（不抛错）；
     - **非尾行**损坏或非法 → 抛 `RunCoreError.corruptedCheckpoint(...)`（不静默跳过中间数据）；
     - 文件存在于磁盘但无法读取（权限/IO 错误）→ 抛 `corruptedCheckpoint` 或底层错误，不得伪装成空结果。
4. 中断恢复：
   - `RunSessionMachine.init(restoring checkpoint: RunCheckpoint)`：`.running`/`.paused` 一律恢复为 `.paused`（中断后必须显式 `resume()` 才能继续计时，禁止进程重启后静默冒充 running）；`.ready`/`.finished` 原样恢复。
   - 恢复后的 `completedDistance` / `elapsed` / `splits` 由 checkpoint 原样保留（本项不做距离重算，也不产生新分段）。

## 验收

- ac-session-legal-matrix: 5 条合法迁移全部成功且落点状态正确；`canTransition(to:)` 对 16 种组合的返回值与 `transition(to:)` 实际成功/抛错完全一致（逐对穷举断言）。
- ac-session-illegal-rejected: 其余 11 种组合（含 `ready→ready`、`running→running`、`paused→paused`、`finished→finished`、`ready→paused`、`ready→finished`、`finished→{ready,running,paused}`、`paused→paused` 等）抛 `RunCoreError.invalidStateTransition`，`error.from`/`error.to` 与实际一致，且抛错后 `machine.state` 与调用前相同。
- ac-session-event-entrypoints: `start()` 仅 `.ready` 成功；`pause()` 仅 `.running` 成功；`resume()` 仅 `.paused` 成功；`finish()` 仅 `.running`/`.paused` 成功；在错误状态下调用均抛错且状态不变。
- ac-checkpoint-real-file: `append` 后磁盘上真实存在 `fileURL`，内容为「每次 append 恰一行、每行以 `\n` 结尾、每行可独立 UTF-8 解码为 JSON」；追加 N 次后文件行数为 N，且旧行内容字节前缀不变（不整文件重写）。
- ac-checkpoint-roundtrip: 用新 `RunCheckpointStore` 实例 `loadLatest()` 得到与最后 append 相等的 `RunCheckpoint`（含 `state`、`completedDistance`、`elapsed`、`splits`、`recordedAt`）；`loadAll()` 按写入顺序返回全部记录。
- ac-checkpoint-missing-and-empty: 文件不存在时 `loadLatest()` 返回 `nil`、`loadAll()` 返回空数组且不抛错；文件存在但为空（0 字节）时同样返回 `nil`/空数组。
- ac-checkpoint-partial-tail-discarded: 文件末行被截断（无结尾换行或 JSON 不完整）时，`loadLatest()` 不抛错并返回截断前的最后一条有效记录；`loadAll()` 同样只返回有效完整记录。
- ac-checkpoint-corrupt-tail-discarded: 末行是合法 JSON 但违反契约（负距离、非有限 `elapsed`、未知 `formatVersion`、`splits` 序号断裂）时，按尾行丢弃处理，返回前一条有效记录且不抛错。
- ac-checkpoint-middle-corruption-throws: 非末行损坏/非法时 `loadLatest()`/`loadAll()` 抛 `RunCoreError.corruptedCheckpoint`（错误描述非空），不得静默跳过该行继续返回后续记录。
- ac-checkpoint-creates-directory: 目标父目录不存在时 `append` 成功创建目录并写入文件；`reset()` 后文件不存在，再次 `reset()` 仍成功（幂等）。
- ac-recovery-running-paused: 由 `state: .running` 与 `state: .paused` 的 checkpoint 构造 `RunSessionMachine(restoring:)` 均得到 `.paused`，随后 `resume()` 合法并可继续到 `.running`；恢复过程不修改 checkpoint 的 `completedDistance`/`elapsed`/`splits`。
- ac-recovery-terminal-and-ready: `.finished` 的 checkpoint 恢复后为 `.finished`，`resume()`/`start()`/`pause()` 均抛错且状态不变；`.ready` 的 checkpoint 恢复后为 `.ready`，`start()` 可进入 `.running`。
- ac-restart-keeps-completed-splits: 写入含 ≥2 个已完成分段的 checkpoint 后，用全新 store 实例（模拟新进程）`loadLatest()` 并恢复，得到的 `splits` 数量、逐项 `index/distance/duration` 与 `completedDistance` 和写入值完全相等（零丢失、零重排）。
- ac-runcore-layer-only: 新增代码只落在 `ios/RunCore/Sources/PurePaceRunCore/` 与 `ios/RunCore/Tests/PurePaceRunCoreTests/`；`Sources/**` 的 `import` 仍仅 `Foundation`，不出现 `SwiftUI/UIKit/CoreLocation/AVFoundation/AVAudioSession/UserNotifications/URLSession/CoreData/SQLite/SwiftData/Timer` 等平台符号，不出现 `shared/fixtures`/`sample-run.gpx`/`sample-run.tcx` 令牌与根 `VERSION` 字面值。
- ac-no-frozen-contract-break: `RunSessionState`/`RunDistance`/`RunPace`/`RunSample`/`RunSplit`/`Announcement*`/`AudioSessionSettings`/`RunCoreError` 的既有公开字段、初始化签名与既有 17 个用例语义不变；不为既有类型新增 `Codable`（`RunCheckpoint` 自行编码原始字段）。
- ac-swift-test-green: 仓库根 `swift test --package-path ios/RunCore` 退出码 0、失败数 0，且新用例真实执行（用例数 > 17）；`bash scripts/check-ios-run-core.sh`、`bash scripts/check-baseline.sh` 仍全部 `[PASS]`；`.munk/code-gates.json` 既有门（含 `lint-ios-run-core`/`build-ios-run-core`/`test-ios-run-core`）id 与 command 不变。
- ac-no-platform-or-ui-change: 未修改 `ios/project.yml`、`ios/PurePace.xcodeproj`、`ios/PurePace/**`、`scripts/**`、`shared/**`、`android/**`、`.github/workflows/**`、`VERSION`、`README.md`、`AGENTS.md`。

## 非目标

- 不实现距离/配速/分段计算引擎、播报调度与去重、AudioSession 协调器与读回、GPX 导出、App target 音频适配器、CoreLocation 接入、模拟器 Harness 与 `verify-ios-sim-runtime.sh`（均为同 WorkSet 其他子项/波次）；本项不做 `xcrun simctl`、不跑 xcodebuild。
- 不新增 UI、页面、ViewModel；不把任何状态机/持久化逻辑放进 `ios/PurePace/**` 或平台适配层。
- 不引入 SQLite/`shared/schema.sql` 依赖、不引入第三方库、不新增可执行 target。
- 不做跨进程真实杀进程验证（由波 2 的 terminate→relaunch 编排承担）；本项只用「同进程内新建 store/machine 实例 + 真实文件」证明重启可继续。
- 不改既有测试的断言语义与既有 17 个用例；不新增/删除 `code-gates.json` 门禁（新用例由既有 `test-ios-run-core` 执行）。
- 不修改 `.github/workflows/*`、不推送、不写「CI 通过」「真机已验证」类结论；阶段 2 两项真机项仍为 `pending: 待人现场`。

## 实现约束

- **前置 skill 事实**：仓库已有 `AGENTS.md` 并路由官方 skill（`.agents/skills/swiftui-pro`、`.agents/skills/android-cli`），App 工程已存在；本项是纯 SwiftPM 逻辑包，无需 `repo-bootstrap` 重新安装 skill、不创建任何新工程骨架，也不适用 `ui-baseline`。
- 复用既有契约：`RunSessionState` 已有 `ready/running/paused/finished`（审查者口中的 `idle` 即 `ready`）；`RunCoreError.invalidStateTransition(from:to:)` 与 `corruptedCheckpoint(_:)` 已存在，直接复用，不新增 error case（如确需新 case 视为破坏冻结契约，走 `corruptedCheckpoint` 描述区分）。
- 文件即真源：`RunCheckpointStore` 是唯一落盘点，外面不得再包内存缓存层；`append` 用 `FileHandle` 追加 + 每行 `\n` 结尾，`loadLatest` 以「按 `\n` 切分 + 逐行解码」实现，尾行规则按上文。只用 `Foundation`（`FileManager`/`Data`/`FileHandle`/`JSONEncoder`/`JSONDecoder`/`URL`），不引入 `OutputStream`、`SQLite`、`UserDefaults`。
- Swift 6 严格并发：新增类型全为 `struct`/`enum` 值语义并显式 `Sendable`；`RunCheckpoint` 的手写 `Codable` 只编码原始标量（`meters`、`duration`、`index`、`state.rawValue`、`recordedAt.timeIntervalSince1970` 或 ISO 8601），避免给冻结类型加 `Codable`。不引入 `actor`、全局可变状态、`@unchecked`。
- 测试用临时目录：`FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`，每个用例独立目录，`defer` 清理；不写仓库、不写固定绝对路径、不依赖 `$TMPDIR` 之外的环境。
- 测试仍用 XCTest（`check-ios-run-core.sh` 禁止 `import Testing`）；测试方法与文件名沿用现有命名风格（如 `SessionMachineTests.swift`、`CheckpointStoreTests.swift`）。
- 门禁沿用：`lint-ios-run-core`（结构断言，源码仍只 `import Foundation`）、`build-ios-run-core`、`test-ios-run-core` 已覆盖本项；`scripts/check-ios-run-core.sh` 的 `--self-test` 无需改动，若新增结构断言须保持「copy 包到临时目录注入违规」的反例自检可用。
- 夹具/版本红线：RunCore 内不得出现 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 与根 `VERSION` 字面值（当前 `0.1.0`），测试数值全部合成。
- 证据口径：只报 `swift test --package-path ios/RunCore` 的真实用例数与失败数、`check-ios-run-core.sh` / `check-baseline.sh` 的 PASS 计数；不写「真机已验证」「CI 通过」。
