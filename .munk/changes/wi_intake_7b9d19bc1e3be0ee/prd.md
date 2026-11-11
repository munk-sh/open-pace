# V1.2 第 B 项：详情/结束态轨迹地图 + 结束态总结感 + 渲染契约钉死

接 `main 51cd153e`。可观测终态：一轮跑完能看到本轮距离/时长/配速 + 自己的路线地图 + 分段明细；历史详情页能回看同一条轨迹；地图渲染契约（抽稀/断线/相机/缓存）有同 commit 可判红断言，原始 samples 与 GPX 导出不受影响。

## 范围

1. **TrackMapView 壳**：新增单一地图壳，输入坐标/采样、输出地图；仅出现在历史详情页与结束态（含待保存与已保存），跑步中/暂停/未开始一律不出图。SwiftUI `Map` + `MapPolyline`（不子类化 renderer），accent 4pt 主轨迹 + accentSoft 光晕；相机按包围盒一次性定位，padding 8–12%；`onMapCameraChange` 不写 state；polyline 在 `body` 外构造并缓存；空轨迹/无有效坐标/单点轨迹给明确中文空态，不留白地图。
2. **渲染抽稀与断线**：复用已在 main 的 `TrackGeometry`；RDP ε=3m **只用于渲染**，归档 `samples` 与 GPX 导出逐字节/逐点不变；相邻采样间隔 >60s 断线分段，多段 polyline 分开绘制；WGS-84 单一存储口径。新增纯函数单测与同 commit 反例：抽稀最大偏差 <3m、断线边界、空/单点输入、边界经度与跨 180° 经线。
3. **结束态总结感**：结束态同屏含 本轮距离/时长/配速 + 轨迹预览卡 + 分段明细；无分段数据给明确替代文案；保存=accent 主操作、丢弃=danger 仅在确认 sheet 内，沿用 A 项的语义重映射口径。
4. **历史列表轻量索引**：复用 main 已有的 `RunArchiveStore.listSummaries()` / `record(withID:)`；`HistoryView` 列表走轻量摘要，详情页再解码完整 `samples`；不迁 SwiftData、不升 `formatVersion`、不改归档格式与命名。
5. **补 A 项 digest**：新增 `.munk/changes/wi_intake_1d3cee7d621efc36/digest.md`，只补事实（commit、改动路径、验证证据、已知偏差），不重写 A 的 `prd.md` 结论。
6. **验证矩阵**：`docs/verification-matrix.md` 增补地图壳 / RDP 抽稀 / >60s 断线 / list 索引四组行；同步把 `DocsVerificationMatrixTests` 的接缝计数做纯加法更新。

## 验收

- ac-map-single-shell: `TrackMapView` 是 App 内唯一地图壳；`ios/PurePace` 下仅 `Track/TrackMapView.swift` 允许 `import MapKit`，且只有 `RunDetailView` 与 `RunView` 的 `state == .finished` 分支引用它；ready/running/paused 分支无地图视图、无实时地图 identifier。实现使用 `Map` + `MapPolyline`，主轨迹 `DesignTokens.Colors.accent` 4pt、光晕 `DesignTokens.Colors.accentSoft`，零裸色值、零第三方地图/UI 框架。反例：在记录态插入地图、删光晕、把主色改成非 accent，必须判红。
- ac-map-empty-single: 空 samples / 无有效坐标（定位失败）/ 单点轨迹三种输入均不构造 `Map`/`MapPolyline`，渲染明确 zh-Hans 空态（文案 + 图标 + 稳定 identifier，如 `run.mapEmpty` / `runDetail.mapEmpty`），不得留白地图；单点与空轨迹的文案可区分。反例：删文案/图标、单点仍出 polyline，必须判红。
- ac-map-camera-once: 相机只由 `TrackGeometry.cameraBox(for:paddingRatio:)` 计算一次，padding 固定落在 8%–12% 内，越界返回 nil；`onMapCameraChange` 闭包内零 state 赋值（静态源码断言）；DEBUG 日志 `trackMap.cameraFit` 对同一轨迹身份恰输出 1 行，含包围盒四至与 padding。反例：padding 0.07/0.13、`onMapCameraChange` 内回写 `cameraPosition`、同一轨迹出 2 次 fit，必须判红。
- ac-map-polyline-cached: `MapPolyline`（或多段数组）在 `body` 外构造并由 `@State`（或等价缓存）持有；静态断言构造点不在 `body` 内；body 因父视图刷新重算时不重建 polyline，且 `MapPolyline` 数量等于 `TrackGeometry.renderSegments` 的段数。反例：把构造移进 `body`，必须判红。
- ac-rdp-epsilon-3m: `TrackGeometry.simplificationEpsilonMeters == 3.0` 且不得改动；固定夹具上 `simplify` 的每点最大偏差 <3m，抽稀后点数小于原始点数；同 commit 反例用公共调用 `simplify(points, epsilonMeters: 8)` 证明最大偏差会 >3m，若默认阈值被改成 8 则默认调用用例判红。
- ac-rdp-render-only: RDP 只作用于渲染输入；`RunRecord.samples` 在渲染前后逐点相等，GPX 导出点数等于原始样本数；`RunGPXExporter.swift` / `RunSample.swift` / `GPXCodec.swift` 无 diff，`bash scripts/check-gpx-export.sh` 保持绿。反例：抽稀结果被写回归档或 GPX 用抽稀点，必须判红。
- ac-break-60s: 相邻时间差 ≤60s 不断线，>60s 断线；61s 输入输出 2 段，跨 3 段夹具输出 3 段；空输入 0 段；单点输入在分段层 1 段、在渲染层过滤为 0 段并走空态；多段 polyline 分开绘制。反例：把 `>` 改成 `>=`（60s 即断）或把 61s 判为不断，必须判红。
- ac-single-and-boundary-longitude: 空/单点输入不崩且输出符合上述契约；经度 ±180 与跨 180° 经线夹具不丢点、不重排、不产生非法坐标，RDP/相机纯函数不崩；明确不做跨线最短路径优化（非目标）。反例：接受 `180.0001`、跨线夹具丢点，必须判红。
- ac-finished-summary-blocks: `state == .finished` 时同屏含 距离 / 时长 / 平均配速 三数值 + 轨迹预览卡（同一 `TrackMapView`）+ 分段明细（每段序号 + 配速），三块各有可断言 identifier 或可及文案；running/paused 不出现这些块。反例：删任一块或把地图放进记录态，必须判红。
- ac-finished-no-split-fallback: 无分段数据时显示明确 zh-Hans 替代文案（如「本轮无分段数据」，走 `L10n`），不得只留空卡；有分段时逐段渲染。反例：删文案只留空卡，必须判红。
- ac-finished-save-discard: 保存为同屏唯一填充主操作（accent 实底、`Radius.control`）；丢弃入口为次操作，`danger` 只在确认 sheet 内出现；确认层外不存在 `run.discard`；沿用 `RunInteractionPlan` 既有语义重映射，既有 plan 单测与阈值不改。反例：把 danger 放到主屏、保存改弱底或丢弃升为主填充，必须判红。
- ac-finished-detail-parity: 结束态与历史详情页共用同一 `TrackMapView`；保存后详情页用同一 `RunRecord.samples` 渲染出与结束态一致的段数/点数；详情页无轨迹记录走空态。反例：两处各写一套地图壳、或详情页不带 samples 仍出图，必须判红。
- ac-history-summary-only: 生产路径 `HistoryView` 只调用 `archiveStore.listSummaries()`，不调用 `list()`；列表行字段全部来自 `RunRecordSummary`；详情页按 id 调用 `record(withID:)` 解码完整 `samples`（DEBUG 注入 fixture 路径除外）；`list()` 既有「坏文件跳过、startedAt 降序 + id 升序」语义不变。反例：超大/畸形 samples 记录仍须成行且列表耗时断言不随 samples 线性增长；若改回 `list()` 该反例判红。
- ac-history-identifier-add-only: 33 项冻结 identifier 零删除、零改名；新增 identifier 仅允许新增，且非空、全局唯一、带 `L10n` 可读 label，总计数单调不减；不新增实时地图 identifier。反例：改名/删除任一冻结 identifier、新增空 label 或重复 id，必须判红。
- ac-store-format-frozen: `formatVersion` 仍为 1；归档文件命名、JSON schema、`samples` 字段语义不变；不迁 SwiftData、不新增 `horizontalAccuracy`、不写迁移。反例：改 `formatVersion`、改归档命名或改 samples 字段，必须判红。
- ac-a-digest-backfill: `.munk/changes/wi_intake_1d3cee7d621efc36/digest.md` 存在且只补事实：至少含 A 的实现 commit `67ff54baa6d6ff8e9487c6d8abf9f15f7d91ae2d`、合并 commit `f907fafa42d333720d1c4b0e6db1461e06d7990a`、A 的改动路径（`DesignTokens.swift` / `ContrastPolicy.swift` / `TrackGeometry.swift` / `RunArchiveStore.swift` / `docs/design/palette-a.md` / `docs/evidence/palette-a-contrast.txt`）、A 的测试与门脚本路径、现场可复核的测试/门禁结论与已知偏差；不改 A 的 `prd.md`。反例：写入新结论、伪造未跑的门禁结果，必须判红。
- ac-matrix-4-rows: `docs/verification-matrix.md` 在既有 15 行之后新增恰 4 行（地图壳 / RDP 抽稀 / >60s 断线 / list 轻量索引）；每行 6 列非空、不含 pending/缺口标记，现状含「本项实测」，归属项为 `wi_intake_7b9d19bc1e3be0ee`；`DocsVerificationMatrixTests` 的接缝计数 15→19 且只做加法，既有 15 行与其断言不变。
- ac-gates-and-evidence: `bash scripts/check-ios-shell.sh` 绿；`swift test --package-path ios/RunCore`、`bash scripts/test-ios.sh --unit-only` 与相关 UI 用例绿；`.munk/code-gates.json` 不新增/不删除门，既有阈值与反例不改；MapKit 允许清单只精确放行 `ios/PurePace/Track/TrackMapView.swift`，其他目录仍判红（门内正反例同 commit）。本项 digest 四栏（结论 / 证据 / 未跑门 / 风险）须给：空态/单段/多段三张证据（路径 + sha256 或 commit）、抽稀前后点数与最大偏差、相机一次性定位日志（次数 = 1）、list 索引口径（数据量 / 耗时）；已知偏差 `EvidenceCaptureUITests/testEvidenceAx5Layout` 的顺序依赖如实标注且本项不修；真机项一律 `pending: 待人现场`。

## 非目标

- 不做跑步中实时地图；不做中国区双 SDK / 高德 / 审图号 / 地图许可。
- 不新增色键、字号档、第三方 UI 框架或第三方地图 SDK；不改 identifier 冻结集。
- 不迁 SwiftData、不改 `formatVersion`、不改归档格式/命名、不加 `horizontalAccuracy`、不写迁移。
- 不做平滑/降噪改写归档数据；GPX 必须与屏幕渲染数据同源。
- 不做分发动作（ASC、ipa、TestFlight、tag、GitHub Release）；不改 `VERSION`。
- 不改 `AGENTS.md` 与产品目录文档；不新增生产 demo/seed 入口。
- 不新增门、不改既有阈值/反例；不跑全量分发相关腿与真机腿。
- 不修 `EvidenceCaptureUITests/testEvidenceAx5Layout` 的全量顺序依赖（C 项取证套件遗留，仅如实标注）。

## 实现约束

**已有资产（A 项 `67ff54b` 已在 main，禁止重复造）**
- `ios/RunCore/Sources/PurePaceRunCore/TrackGeometry.swift`：已含 `simplificationEpsilonMeters = 3.0`、`maxSegmentGapSeconds = 60`、`segments(from:)`、`simplify(_:epsilonMeters:)`、`renderSegments(from:)`、`boundingBox(of:)`、`cameraBox(for:paddingRatio:)`；只在其上补单测/反例与视图接线，阈值常量不改。
- `ios/RunCore/Sources/PurePaceRunCore/RunArchiveStore.swift`：已含 `RunRecordSummary`、`listSummaries()`、`record(withID:)`；A 项已覆盖索引绕过 `samples` 解码。本项只改 `HistoryView`/`HistoryViewState` 的消费方式与详情懒加载。
- `ios/PurePace/Run/RunInteractionPlan.swift`：save=primary/accent、discardRequest=secondary、确认层 confirm=danger 的口径已在 main；本项不得改 emphasis/style/tint 映射与既有单测断言。
- `ios/RunCore/Tests/PurePaceRunCoreTests/TrackGeometryTests.swift` 现有 8 个用例已覆盖 8–12% padding、61s 断线、RDP 3m 等；本项在同一文件补空/单点、60s 精确边界、边界经度与反例，不改既有用例。

**TrackMapView 落点与门禁接线**
- 建议落点 `ios/PurePace/Track/TrackMapView.swift`（`project.yml` 的 `PurePace` 目录自动纳入 sources，禁止手改 `project.pbxproj`）。
- `scripts/check-ios-shell.sh` 的 `validate_frameworks` 当前把 `MapKit` 与 `HealthKit` 等一起全局禁止；需改为：`import MapKit` 只允许出现在 `ios/PurePace/Track/TrackMapView.swift`，其他 App 目录仍判红；`--self-test` 同步补「MapKit 在允许文件通过 / 在 Harness 等其它目录判红」正反例。`HealthKit/CoreMotion/UserNotifications/URLSession` 的禁止不变。
- 新文件需纳入 token 纪律扫描（`validate_design_tokens` 的 `managed_files` 增加 `ios/PurePace/Track`）与本地化裸英文扫描（`validate_localization` 的视图清单增加 `Track/TrackMapView.swift`）；颜色/字号一律 `DesignTokens`，文案一律 `L10n`。
- `scripts/check-ios-shell.sh` 的 `ac-live-run-ui` 段当前硬断言 `HistoryView` 含 `archiveStore.list()`、`RunDetailView(record:`；改为 summary 消费后同步把断言改成 `listSummaries()` + `record(withID:)`（保留 `history.row` / `history.empty` / `RunFormatting.paceText` / 详情 identifier 等既有断言），不得删除该段覆盖。
- 4pt 主轨迹与光晕宽度：优先新增 `DesignTokens.Stroke.track = 4`（及由它派生的 halo 宽度），不新增色键、不改字号档/字重/间距/圆角/既有 `Stroke.hairline = 1`；如新增 token，`DesignTokensTests` 只做加法断言。

**数据来源与视图接线**
- 结束态地图数据：`RunSessionViewModel` 目前未公开结束快照；从 `RunSessionOrchestrator.finishedSnapshot` / `savedRecord` 以只读属性暴露 `samples`（或等价只读快照），不复制/不改写样本。分段明细直接用 `viewModel.metrics.splits`。
- 历史详情：`HistoryViewState` 改为持有 `[RunRecordSummary]`（或等价摘要集合），列表行由 summary 渲染；`NavigationLink` 仍只传 `UUID`，详情页用 `archiveStore.record(withID:)` 解码完整记录。截图注入 `injectedRecords: [RunRecord]?` 的 DEBUG 路径保留，可从注入记录派生 summary / 直接取详情。
- 地图壳建议 API：`TrackMapView(samples: [RunSample], emptyIdentifier: String)` 或等价；内部用 `TrackGeometry.renderSegments` 生成段，空/单点/无效坐标由 `TrackMapView` 统一判定并走空态；详情页与结束态只传 samples，不各自实现几何。
- 新增空态/无分段文案走 `L10n` 键并补 `ios/PurePace/Resources/Localizable.xcstrings`（zh-Hans），不在视图内写裸中文/英文；identifier 只新增不改既有 33 项。
- 相机：`MapCameraPosition` 用 `TrackGeometry.cameraBox(for:paddingRatio: 0.10)` 初始化一次并缓存；`onMapCameraChange` 只做日志/无操作，禁止写回 camera/state；DEBUG 日志统一前缀 `trackMap.cameraFit`，便于回执摘录次数。
- 证据：空态/单段/多段三张截图放 `docs/evidence/track-map/{empty,single,multi}.png`（或等价且回执写明路径）并给 sha256 或绑定 commit；UI 取证继续走既有 DEBUG `-uiTestLocation` / `-screenshotRunFinished` / `-screenshotHistoryDemo` 机制，不新增生产 demo/seed 入口。

**文档与测试结构**
- `docs/verification-matrix.md` 追加 4 行时，`ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift` 需把 `expectedSeamCount` 15→19，并把 4 个新接缝名加入期望集合；既有 15 个接缝名与逐行断言不改，归属项写本项 `wi_intake_7b9d19bc1e3be0ee`。
- A 项 digest 的事实来源：`git show --stat 67ff54b`、A 的 `prd.md`、`docs/design/palette-a.md`、`docs/evidence/palette-a-contrast.txt`、`TrackGeometryTests` / `RunArchiveStoreTests` / `DesignTokensTests` / `ContrastPolicyTests`、`scripts/check-ios-shell.sh`；只记录可复核事实。
- 验证命令以本项实际改动为准：`bash scripts/check-ios-shell.sh`；`swift test --package-path ios/RunCore`；`bash scripts/check-ios-run-core.sh`；`bash scripts/test-ios.sh --unit-only`；相关 `PurePaceUITests` 用例。预算 ≤8M tokens / ≤75 分钟墙钟，到点即停并交四栏回执，写清已绿项与未闭合项，不做长会话自查补绿。
