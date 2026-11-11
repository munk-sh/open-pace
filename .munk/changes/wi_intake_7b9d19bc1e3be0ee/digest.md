# B 项（wi_intake_7b9d19bc1e3be0ee）Digest

基线：`main 51cd153e`（本 worktree HEAD）。收口原因：父级在 18:12Z 起将本 stage 标记 unresponsive/no_output_backlog，按公司口径立即交回执，不再开新任务、不重派子 worker。

## 本次未见闭项

### 已做（事实）

- 已读 `.munk/changes/wi_intake_7b9d19bc1e3be0ee/prd.md`（72 行，18 条 ac-* + 实现约束）与 `.munk/baseline/INDEX.md`（仅索引，未展开各 domain 正文）。
- 已读并核对既有资产（只读，零改动）：
  - `ios/RunCore/Sources/PurePaceRunCore/TrackGeometry.swift`（192 行）：`simplificationEpsilonMeters = 3.0`、`maxSegmentGapSeconds = 60`、`segments/simplify/renderSegments/boundingBox/cameraBox(for:paddingRatio:)` 均已在 main，阈值常量未改。
  - `ios/RunCore/Sources/PurePaceRunCore/RunArchiveStore.swift`（357 行）：`RunRecordSummary`、`listSummaries()`、`record(withID:)` 已在 main。
  - `ios/PurePace/Run/RunSessionOrchestrator.swift:96-124`：`finishedSnapshot` / `savedRecord` / `acceptedSamples` 只读公开面已在 main；`RunSessionViewModel.acceptedSamples` 可直接复用，无需复制 samples。
  - `ios/PurePace/History/HistoryView.swift`（223 行）现状：`load()` 仍调 `archiveStore.list()`（第 191 行），`ForEach(state.records)`，`navigationDestination` 就地取 `RunRecord` 传 `RunDetailView(record:exporter:)`。
  - `ios/PurePace/History/HistoryViewState.swift`（86 行）现状：`outcome: HistoryLoadOutcome` 持 `[RunRecord]`。
  - `ios/PurePace/History/RunDetailView.swift`（251 行）现状：直接吃 `RunRecord`，无轨迹块。
  - `ios/PurePace/Run/RunView.swift`（541 行）现状：三态共用 distanceHero / metricsPanel / hintLayer / 主操作；无轨迹块、无分段明细块。
  - `scripts/check-ios-shell.sh`（2485 行）现状映射：框架校验函数名为 `validate_app_imports()`（112–148，`MapKit` 在 143 行通用禁止），门为 `ac-app-targets-and-frameworks`（1818–1833）；`managed_files`（802–806）只 find `Run`/`History`/`Settings`/`Design -maxdepth 1`/`ContentView`；`validate_localization` 视图清单在 371 起；`ac-live-run-ui` 在 1872–1953（含 `archiveStore.list()` 与 `RunDetailView(record:` 硬断言）；自检 `import MapKit` 反例在 1167–1169；`ios/project.yml` 为 `sources: - path: PurePace`，新增 `Track/` 无需改工程。
  - `docs/verification-matrix.md`：17 行（表头 2 行 + 15 条接缝），最后 5 条归属 `wi_intake_e7e73d829e61fa7a`。
  - `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`：`expectedSeamCount = 15`，`baseSeams`(10) + `workItemSeams`(5)。
- 结论：本项所需的上游资产（A 项 TrackGeometry / 归档轻量索引 / 交互 plan）确实已在 main，PRD 的「已有资产」段落与仓库一致，无需先补 A 代码。

### 未做（本项验收全部 18 条 ac-* 均未落地）

- 未新增 `ios/PurePace/Track/TrackMapView.swift`（唯一地图壳、`Map` + `MapPolyline`、accent 4pt + accentSoft 光晕、相机一次定位 + `trackMap.cameraFit` DEBUG 日志、空/单点空态）。
- 未在 `RunView.state == .finished` 分支接线轨迹预览卡与分段明细块（ac-finished-summary-blocks / no-split-fallback / detail-parity）。
- 未给 `ios/PurePace/Design/DesignTokens.swift` 增 `Stroke.track = 4`（及派生 halo 宽度）与其加法断言。
- 未改 `ios/PurePace/History/HistoryView.swift` / `HistoryViewState.swift` 走 `listSummaries()` + `record(withID:)` 懒解码（ac-history-summary-only）；未保留/改造 DEBUG 注入路径。
- 未改 `ios/PurePace/History/RunDetailView.swift` 接受 id + store（或等价懒加载）并嵌入同一 `TrackMapView`。
- 未新增 `L10n` 键与 `ios/PurePace/Resources/Localizable.xcstrings` 条目（`run.mapEmpty` / `runDetail.mapEmpty` / `run.finished.splits.empty` 等）。
- 未补 `ios/RunCore/Tests/PurePaceRunCoreTests/TrackGeometryTests.swift` 的空/单点、60s 精确边界、边界经度/跨 180°、`simplify(epsilonMeters: 8)` 反例。
- 未改 `scripts/check-ios-shell.sh`：MapKit 精确放行（仅 `ios/PurePace/Track/TrackMapView.swift`）及 `--self-test` 正反例、`managed_files` 增 `ios/PurePace/Track`、`validate_localization` 视图清单增 `Track/TrackMapView.swift`、`ac-live-run-ui` 段改 `listSummaries()` + `record(withID:)`。
- 未追加 `docs/verification-matrix.md` 4 行（地图壳 / RDP 抽稀 / >60s 断线 / list 轻量索引），未把 `DocsVerificationMatrixTests.expectedSeamCount` 从 15 改 19（该测试若不同步修改会直接红，故两者必须同 commit）。
- 未新增 `.munk/changes/wi_intake_1d3cee7d621efc36/digest.md`（A 项事实回填，ac-a-digest-backfill 未闭合）；已确认该目录当前只有 `prd.md`，无 digest.md。
- 未产出 `docs/evidence/track-map/{empty,single,multi}.png` 三张证据与抽稀/相机/list 索引实测证据。

### 已过门（实跑记录，原样结论）

- 未跑任何门：本会话没有执行 `bash scripts/check-ios-shell.sh`、`swift test --package-path ios/RunCore`、`bash scripts/check-ios-run-core.sh`、`bash scripts/test-ios.sh --unit-only`、`bash scripts/check-gpx-export.sh`。
- `.munk/code-gates.json` 已存在（未新增/未删除门、未改阈值，符合 B 的「不新增门」约束），但本次未执行其中任何 gate。

### 未闭合点（交给下一位执行者）

- 全部 18 条 ac-* 未实现：`ac-map-single-shell`、`ac-map-empty-single`、`ac-map-camera-once`、`ac-map-polyline-cached`、`ac-rdp-epsilon-3m`、`ac-rdp-render-only`、`ac-break-60s`、`ac-single-and-boundary-longitude`、`ac-finished-summary-blocks`、`ac-finished-no-split-fallback`、`ac-finished-save-discard`、`ac-finished-detail-parity`、`ac-history-summary-only`、`ac-history-identifier-add-only`、`ac-store-format-frozen`、`ac-a-digest-backfill`、`ac-matrix-4-rows`、`ac-gates-and-evidence`。
- 已知硬耦合（下一位必须先做）：`docs/verification-matrix.md` 加 4 行与 `DocsVerificationMatrixTests.expectedSeamCount` 15→19 必须同 commit；`scripts/check-ios-shell.sh` 的 `ac-live-run-ui` 段改 `listSummaries()` 前，`HistoryView` 必须先改成 summary 消费，否则该门必红。
- 已知偏差（如实标注，本项不修）：`EvidenceCaptureUITests/testEvidenceAx5Layout` 的顺序依赖仍存在。
- 真机项：一律 `pending: 待人现场`。
- 本 worktree 无代码改动待提交；唯一新增文件为本 digest（及 Host 写入的 `prd.md`）。
