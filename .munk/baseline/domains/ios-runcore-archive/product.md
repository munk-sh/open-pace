# Domain: ios-runcore-archive

`ios/RunCore`（模块 `PurePaceRunCore`）内的跑次归档与 GPX 文件导出层：跑次值类型 `RunRecord`、按「一次跑次一文件」落盘的 `RunArchiveStore`、由归档采样写真实 `.gpx` 的 `RunGPXExporter`。纯逻辑 + `Foundation` 真实文件 IO，不接 UI/平台框架/网络；与 `ios-runcore` 同包并复用其值类型，但只新增文件、不动阶段 2 契约。

## 范围

- 全部新增于 `Sources/PurePaceRunCore/`：`RunRecord.swift`、`RunArchiveStore.swift`、`RunGPXExporter.swift`；测试新增 `Tests/PurePaceRunCoreTests/{RunRecordTests,RunArchiveStoreTests,RunGPXExporterTests}.swift`。不改既有源文件、既有测试、`Package.swift`。
- `RunRecord`：`public struct RunRecord: Equatable, Sendable, Codable`，字段 `formatVersion`（唯一合法 1）/`id: UUID`/`startedAt`/`endedAt`/`distance: RunDistance`/`activeDuration: TimeInterval`/`splits: [RunSplit]`/`samples: [RunSample]`；采样全量落盘，不设上限、不降采样。
- `RunRecord.init?` 复用既有 `RunDistance`/`RunSplit` 语义与 `RunCheckpoint.hasContiguousSplitIndices`；`Codable` 手写、只编码原始标量，未知版本/字段越界在解码时抛错（供 store 跳过）。
- `RunArchiveStore`（`Sendable`，持有 `directoryURL`）：`save(_:)` 自动建目录、原子写（同目录临时文件 → 重命名替换目标）、失败清理临时文件并返回最终 `URL`；`list()` 按 `startedAt` 降序，等值按 `id.uuidString` 升序（重复调用次序一致）。文件即真源，不内置内存缓存层。
- 归档读取：`FileManager` + `Data(contentsOf:)` + `JSONDecoder`；单文件解码/校验失败静默跳过，目录级 IO 失败才抛错；缺失目录视为空且不隐式创建；子目录、`.tmp` 与非 `.json` 扩展名条目不参与 `list()` 与计数。
- 文件名契约：`<startedAt 的 UTC 紧凑时间 yyyyMMdd'T'HHmmss'Z'（en_US_POSIX）>-<id.uuidString>.json`；导出同 stem + `.gpx`；目标已存在追加 `-2`、`-3`… 递增后缀，绝不覆盖；排序仍以记录内容 `startedAt` 为准。
- `RunGPXExporter`（`Sendable`，持有 `directoryURL`）：`export(_:)` 由归档采样构建 `GPXTrack(name: 含 startedAt 的确定性非空名, createdAt: record.startedAt, activityType: "running", points: record.samples)`，走 `GPXCodec.write` 落盘并返回 `URL`；采样为空抛 `RunArchiveError.emptySamples` 且不落文件；不重造编码器、不改 GPX 输出格式。
- `RunArchiveError`（`Error, Equatable, Sendable, CustomStringConvertible`）：`invalidRecord(String)`/`emptySamples`/`ioFailure(String)`，描述非空且互异；沿用 `GPXCodecError`/`RunCoreError` 分离模式，不改既有 case 与 `description`。

## 验收

- ac-record-roundtrip: 保存一条记录后，用新建的 store 实例读回，`startedAt`/`endedAt`/`distance`/`activeDuration`/`splits`/`samples`（含 `altitude`/`heartRate`/`cadence`）逐字段相等，且磁盘上恰好多出 1 个 `.json` 文件。
- ac-archive-one-file-per-run: 同一目录连续保存两条记录（含 `startedAt` 相同、`id` 不同的情形）→ 目录内 2 个互不覆盖的记录文件，`list()` 返回 2 条且都能完整解码。
- ac-archive-list-desc: 以乱序 `startedAt` 写入 3 条记录 → `list()` 按 `startedAt` 倒序返回；`startedAt` 相等时按 `id` 的 `uuidString` 升序固定次序（重复调用结果一致）。
- ac-archive-corrupt-skip: 目录中混入非 JSON 文本文件、`formatVersion` 未知的 JSON、缺必需字段的 JSON、字段越界（如 `endedAt < startedAt`、分段索引不连续）的 JSON → `list()` 不抛错，静默跳过这 4 个条目，仍返回其余全部有效记录。
- ac-archive-missing-dir-empty: 归档目录不存在时 `list()` 返回空数组且不抛错、不隐式创建目录。
- ac-archive-atomic-write: 保存成功后归档目录内除最终 `.json` 记录文件外不留任何临时/半成品文件；保存失败（目标归档路径被同名普通文件占用导致无法建目录）时抛错且不留下新文件或残留临时文件。
- ac-archive-ignore-foreign-entries: 目录内的子目录、`.tmp` 文件与非 `.json` 扩展名文件不参与 `list()` 与计数。
- ac-record-validation: 构造 `RunRecord` 时，`formatVersion != 1`、`endedAt < startedAt`、`activeDuration` 非有限或为负、距离为负、分段索引不从 1 起连续、采样时间戳递减或坐标越界 → 构造失败返回 `nil`（不产生半合法值）。
- ac-export-gpx-roundtrip: `RunGPXExporter` 对含 N 个采样的记录导出 → 目录内出现非空 `.gpx` 文件；`GPXCodec.read` 回读得到点数 == N，逐点 `latitude`/`longitude`/`altitude`/`timestamp`/`heartRate`/`cadence` 与记录采样完全相等，track `name` 非空且 `activityType == "running"`，点的先后顺序与记录一致。
- ac-export-filename-no-overwrite: 导出文件名同时含记录 `startedAt` 的 UTC 时间标识与记录 `id`；对同一记录向同一目录导出两次 → 得到 2 个不同文件且都能回读出相同的采样序列（既有文件不被覆盖）。
- ac-export-empty-samples-fails: 对采样点为空数组的合法记录导出 → 抛出可区分的错误，且目标目录不产生任何 `.gpx` 文件。
- ac-existing-contracts-intact: 阶段 2 的既有源文件与既有测试文件不被修改（`git diff` 中 `ios/RunCore` 只出现新增文件），`RunCoreError`/`GPXCodecError` 既有 case 与描述不变，既有 87 例测试全部仍通过。
- ac-gates-green: `bash scripts/check-ios-run-core.sh`、`swift build --package-path ios/RunCore`、`swift test --package-path ios/RunCore` 三者均退出 0；`swift test` 失败 0 例、执行数 ≥ 既有基线且新增用例覆盖上述全部 ac-*。

## 非目标

- 不写会话编排器（组合 `RunSessionMachine`/`RunMetricsEngine`/`AnnouncementScheduler`/`RunCheckpointStore`）、不做「结束只归档一次」的幂等策略——本域只提供 store/export 原语。
- 不做历史列表/详情 UI、系统分享面板、`ShareLink`/`fileExporter`/`UIDocumentPicker`；不把 `PurePaceRunCore` 接进 App target 或 `project.yml`。
- 不接 CoreLocation/AVFoundation/SwiftUI/UIKit/URLSession/Timer 等平台符号；不广播、不作为后台任务运行。
- 不改阶段 2 契约：`RunSessionState`/`RunCheckpoint`/`RunCheckpointStore` JSONL 语义、`RunMetricsEngine` 阈值、`AnnouncementScheduler` 规则、`AudioSession*` 契约、`GPXCodec` 输出格式一律不动。
- 不读/不引用 `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 等夹具令牌；测试数据一律合成。
- 不新增 executable target、不改 `Package.swift`、不改 `.munk/code-gates.json` 与 `scripts/**`、不碰 `android/`、`shared/`、CI workflow、`VERSION`、`AGENTS.md` 与 Host 托管文件。
- 不做导出降采样、压缩/加密容器、批量转换、导入 UI、删除/编辑记录、迁移既有 JSONL checkpoint 为记录文件。
- 不做真机/模拟器运行、签名、CI run；不写「真机已验证」类结论。

## 实现约束

- 分层：新增代码只落 `Sources/PurePaceRunCore/` 与 `Tests/PurePaceRunCoreTests/`；`Sources` 只 `import Foundation`，不得出现 `CoreLocation|AVFoundation|AVAudioSession|SwiftUI|UIKit|URLSession|CoreData|SQLite|SwiftData|Timer` 字样（含注释与命名），不得出现夹具令牌与根 `VERSION` 字面值。
- Swift 6 严格并发：只用 `struct`/`enum` + 显式 `Sendable`，不引入 `actor`/`class`/全局可变状态/`@unchecked`；store 不内置内存缓存层（文件即真源）。
- 错误分离：归档/导出失败用新增 `RunArchiveError`，`RunCoreError`/`GPXCodecError` 的既有 case 与 `description` 不变。
- 测试纪律：XCTest（禁 `import Testing`）；临时目录用 `FileManager.default.temporaryDirectory` + `UUID()` 子目录并 `defer` 清理；时间统一 `Date(timeIntervalSince1970: n)` 合成，坐标用固定步长公式生成，不读夹具、不用 `Date()` 现时；损坏条目用真实写盘文件（非内存桩）构造。
- 导出契约：采样为空先拦（`emptySamples`）再建目录，避免留下空目录/空文件；写出复用 `GPXCodec.write` 的内部原子写。
- 证据口径：只报 `swift build`/`swift test` 真实输出摘要与用例数、`check-ios-run-core.sh` PASS 计数；不写「已验证」「真机通过」。

## 最近交付证明

- workItemId: wi_ws_d61334ffe87c8e14（2026-11-08，pass，跑次归档 + GPX 导出原语；只取代码层证据）
- 交付：新增 `RunRecord`（手写 `Codable`，`init?` 校验版本/时间序/时长/距离/分段索引连续/采样时间非递减）、`RunArchiveStore`（一次跑次一文件、临时文件 + 重命名原子写、命名 `<UTC 紧凑时间>-<uuid>.json`、`list()` 倒序 + 同刻 `uuidString` 升序、损坏条目静默跳过、缺失目录返回空）、`RunGPXExporter`（复用 `GPXTrack`/`GPXCodec.write`，`activityType == "running"`，同名追加 `-2`/`-3` 不覆盖，空采样抛 `RunArchiveError.emptySamples`）；错误新增 `RunArchiveError`，既有 `RunCoreError`/`GPXCodecError` 未动。
- 验证：`code_gates` 22 门全绿——`lint-ios-run-core` 11 项断言 0 失败、`build-ios-run-core` PASS、`test-ios-run-core` 110 例 0 失败（既有 87 + 新增 23：`RunRecordTests` 10、`RunArchiveStoreTests` 10、`RunGPXExporterTests` 3）；`ios/RunCore` 只出现新增文件，未改 `scripts/**`、`.munk/code-gates.json`、`project.yml`、`shared/`、`android/`、CI、`VERSION`。App 侧「结束只归档一次」编排、历史列表/详情 UI 与系统分享仍 `pending`（归后续 Wave 2 子项）。
