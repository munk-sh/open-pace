# B 项（wi_intake_7b9d19bc1e3be0ee）Digest

基线：`main 51cd153e`。本项在受限续跑窗口内落地，按 commit 分组推进。

## 已做（事实 + commit）

- `22b84ab` 地图壳与 token/文案：
  - 新增 `ios/PurePace/Track/TrackMapView.swift`：App 内唯一 `import MapKit` 文件；`Map` + 多段 `MapPolyline`；主轨迹 `DesignTokens.Colors.accent` / `DesignTokens.Stroke.track`(4pt)，光晕 `accentSoft` / `Stroke.trackHalo`(=4×2)；polyline 与相机在 `init` 中构造并由 `@State` 持有（body 外构造）；相机只经 `TrackGeometry.cameraBox(for:paddingRatio:)`，padding 固定 `cameraPaddingRatio = 0.10`；`onMapCameraChange` 只打日志不写 state；空/无有效坐标/单点走 zh-Hans 空态（图标 + 标题 + 说明，不构造 `Map`）；DEBUG `trackMap.cameraFit` 一次性日志含包围盒四至与 padding。
  - `ios/PurePace/Design/DesignTokens.swift`：新增 `Stroke.track = 4`、`Stroke.trackHalo = track * 2`，不改既有 `hairline = 1`。
  - `ios/PurePace/Design/L10n.swift` + `ios/PurePace/Resources/Localizable.xcstrings`：新增 `run.map.empty.title/body`、`run.map.single.title/body`、`run.map.preview.label`、`run.splits.detail.title`、`run.finished.splits.empty`（zh-Hans，JSON 解析通过，68 条 strings）。
  - `ios/RunCore/Sources/PurePaceRunCore/TrackGeometry.swift`：只做加法——`TrackCoordinate.isValidWGS84`（±90/±180，`180.0001` 非法）与 `validSamples(from:)`（保序过滤），阈值常量未改。
- `fb49e06` 纯逻辑反例 + 验证矩阵：
  - `TrackGeometryTests` 新增 7 个用例：60s 精确边界（`>` 非 `>=`）、61s 断 2 段、单点分段层 1 段/渲染层 0 段、空输入 0 段且相机 nil、坐标合法性边界、跨 180° 夹具不丢点不重排且纯函数不崩、`simplificationEpsilonMeters == 3.0` + `simplify(epsilonMeters: 8)` 偏差 >3m 反例、渲染不写回归档 samples。
  - `docs/verification-matrix.md` 追加恰 4 行（地图壳 / RDP 抽稀 / >60s 断线 / list 轻量索引），6 列非空、含「本项实测」、归属 `wi_intake_7b9d19bc1e3be0ee`。
  - `DocsVerificationMatrixTests`：`expectedSeamCount` 15→19，新增 `trackSeams` 4 条与归属断言（既有 15 条断言未改）。
- `26ec992` 视图接线 + 门禁：
  - `RunView`：`state == .finished` 才插入 `finishedTrackSummary`（同一 `TrackMapView(samples: viewModel.acceptedSamples, emptyIdentifier: "run.mapEmpty", singlePointIdentifier: "run.mapEmpty.single")` + 分段明细）；分段明细逐段「序号 + 配速」，无分段给 `L10n.runFinishedSplitsEmpty`；保存/丢弃语义沿用 `RunInteractionPlan`，未改 emphasis/tint 映射与既有单测。
  - `RunDetailView`：新增 `mapSection`，与结束态共用同一 `TrackMapView`（`runDetail.mapEmpty` / `runDetail.mapEmpty.single`），无轨迹走空态。
  - `HistoryViewState`：`HistoryLoadOutcome.loaded([RunRecordSummary])`、`summaries`；`HistoryView` 列表只调 `archiveStore.listSummaries()`，行内容全部来自 `RunRecordSummary`（新增 `HistoryRowContent(summary:)`，保留 `init(record:)`）；详情按 id `archiveStore.record(withID:)` 懒解码完整 `samples`；DEBUG `injectedRecords` 路径保留（派生 summary / 直接给详情）。
  - `ios/PurePaceTests/HistoryViewStateTests.swift`：loader 与断言改为 summary 口径（10 个用例逻辑不变）。
  - `scripts/check-ios-shell.sh`：`validate_app_imports` 精确放行 `MapKit` 仅 `ios/PurePace/Track/TrackMapView.swift`（其余目录仍红，`HealthKit/CoreMotion/UserNotifications/URLSession` 禁止不变）；`managed_files` 增 `ios/PurePace/Track`；`validate_localization` 视图清单增 `Track/TrackMapView.swift`；`ac-live-run-ui` 改为断言 `listSummaries()` + `record(withID: recordID)` 并对 `archiveStore.list()` 反向判红，新增地图壳绘制/相机/仅 finished 静态断言；`--self-test` 增「MapKit 在唯一壳通过 / 在 Harness 与 History 越界判红」。
- `.munk/changes/wi_intake_1d3cee7d621efc36/digest.md`：A 项事实回填（`67ff54baa6d6ff8e9487c6d8abf9f15f7d91ae2d`、`f907fafa42d333720d1c4b0e6db1461e06d7990a`、改动路径、测试/门路径、现场结论、已知偏差）。

## 未做

- 三张证据 PNG（`docs/evidence/track-map/{empty,single,multi}.png`）未产出：本窗口未跑模拟器截图取证腿（仅完成编译 + 单测腿）。
- 相机 `trackMap.cameraFit` 运行时「次数 = 1」未做真机/模拟器日志摘录；当前只有源码级一次性守卫（`didLogCameraFit`）。
- list 索引的量化耗时（数据量 / 耗时）未采集，仅有结构性单测（`testListSummariesFormsRowEvenWhenSamplesAreHugeOrMalformed` 等）。


## 已过门（实跑，原样结论）

- `swift test --package-path ios/RunCore`：**173 tests, 0 failures**（含 `DocsVerificationMatrixTests` 2 passed、`TrackGeometryTests` 全部 passed）。
- `bash scripts/check-ios-shell.sh`：**29 项断言，0 项失败 / ios shell OK**；`ac-design-tokens` identifier 42（冻结 33 + 新增 9）、demo 入口 0；`ac-built-plist-readback` 因无 `.build/ios` 产物 SKIP（既有行为）。
- `bash scripts/test-ios.sh --unit-only`：**TEST BUILD SUCCEEDED / TEST EXECUTE SUCCEEDED**，含 `HistoryViewStateTests`、`RunDetailContentTests` 全绿，RunCore SwiftPM 173 tests 0 failures；`[timing] build=11s unit=7s runcore=1s total=23s`（TrackMapView 已随 App target 编译通过）。
- 未跑：`bash scripts/check-ios-run-core.sh`、`bash scripts/check-gpx-export.sh`、UI 用例、模拟器截图取证腿。
- `.munk/code-gates.json` 未新增/删除门、未改阈值。

## 未闭合点

- `ac-gates-and-evidence`：三张截图与相机/列表量化证据缺失，需在有模拟器与时间预算的窗口补跑（`-uiTestLocation` / `-screenshotRunFinished` / `-screenshotHistoryDemo`）。
- 真机项：一律 `pending: 待人现场`。
- 已知偏差（如实标注，本项不修）：`EvidenceCaptureUITests/testEvidenceAx5Layout` 的全量顺序依赖。
- 并行门未跑：`check-ios-run-core.sh`、`check-gpx-export.sh`（`RunGPXExporter.swift` / `RunSample.swift` / `GPXCodec.swift` 本项零 diff，RDP 只作用于渲染输入已在单测钉住）。
