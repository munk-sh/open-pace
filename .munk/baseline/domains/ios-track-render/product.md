# Domain: ios-track-render

轨迹渲染子域：把「存 WGS-84 原始采样 → 渲染期派生 polyline」这段只读派生逻辑收口在 `ios/RunCore`（`PurePaceRunCore`，只 `import Foundation`），供跑步结束态与历史详情页的地图卡使用。存储与渲染分离：本域只读 `RunSample`，从不回写归档，GPX 导出语义不受影响。当前已落地纯几何层（断线分段 / RDP 抽稀 / 包围盒与相机框），MapKit 视图壳 `TrackMapView` 仍 `pending`。

## 范围

- `ios/RunCore/Sources/PurePaceRunCore/TrackGeometry.swift`（新增）：常量 `simplificationEpsilonMeters = 3.0`、`maxSegmentGapSeconds = 60`、`minimumCameraPadding = 0.08` / `maximumCameraPadding = 0.12`；值类型 `TrackCoordinate`、`TrackBoundingBox`；派生函数 `segments(from:)`、`simplify(_:epsilonMeters:)`、`renderSegments(from:)`、`boundingBox(of:)`、`cameraBox(for:paddingRatio:)`。
- 局部米制投影固定为 `x = lon * 111320 * cos(lat0)`、`y = lat * 111320`（`lat0` 取该段首点纬度）；RDP 用点到线段垂距的迭代栈实现，不做递归、不引入浮点工具。
- 测试：`ios/RunCore/Tests/PurePaceRunCoreTests/TrackGeometryTests.swift`（分段边界 / 坐标保真 / 空输入 / 抽稀误差 / 短段不抽 / padding 边界 / 包围盒扩张 / 空轨迹 nil）。
- 消费面（尚未接线）：结束态轨迹预览卡与历史详情页地图卡共用同一 `TrackMapView` 壳（`Map(position:)` + `MapPolyline(...).stroke`，必要时退 `MKPolyline`，不子类化 renderer），只 `import MapKit`；相机按包围盒一次定位、padding 8–12%；`onMapCameraChange` 内不回写 state；空轨迹给 zh-Hans 空态文案 + 图标。

## 验收

- ac-map-break-segments: 按采样时间切段——相邻间隔 59s 不断、61s 断、跨 3 段夹具输出 3 段；切段只产出坐标，不改写任何采样。落点 `TrackGeometryTests.testSegmentSplitAtSixtySecondsBoundary` / `testSegmentsPreserveOriginalCoordinates` / `testEmptySamplesProduceNoSegments`。
- ac-map-rdp-render-only: RDP ε=3m 在局部米制投影下执行，固定夹具上每点最大偏差 < 3m；抽稀只作用于渲染输入，归档 `samples` 与 GPX 全量点不受影响（`check-gpx-export` 仍绿）。落点 `testSimplificationKeepsEveryPointWithinThreeMeters` / `testSimplificationLeavesShortSegmentsUntouched`。
- ac-map-camera-fit: `cameraBox(for:paddingRatio:)` 的 padding 只接受 0.08…0.12（7% / 13% 返回 nil，fail-closed），每条边各扩 `span * padding` 即 span 增量 = `2 * padding`；极小轨迹给最小可视跨度 0.0002 避免相机缩到 0；空轨迹返回 nil。落点 `testCameraPaddingAcceptsEightToTwelvePercentOnly` / `testCameraBoxExpandsByPaddingOnEverySide` / `testCameraBoxNilForEmptyTrack`。
- ac-render-segments-pipeline: `renderSegments(from:)` 先按 >60s 断线再逐段抽稀，且丢弃抽稀后少于 2 点的段（单点段不上图）。
- ac-track-render-no-storage-write: `TrackGeometry` 入参只读、无 `mutating`、无文件 IO、无 `import` 平台框架；`RunRecord`/`RunArchiveStore`/`RunGPXExporter` 契约零改动，`formatVersion` 不变，不新增字段。
- ac-map-empty-state（pending）: 轨迹为空或定位失败时地图区域必须渲染 zh-Hans 空态文案 + 图标，不留空白地图；反例=删文案/图标必须红。待 `TrackMapView` 落地时补断言与反例。
- ac-map-polyline-cached（pending）: `TrackPolyline` 在 `body` 外构造并由 `@State`（或等价）持有缓存，构造点不在 `body` 内；坐标/相机逻辑收敛在 `TrackMapView` 单文件，视图外不散落。待 `TrackMapView` 落地时补静态门断言。
- ac-detail-map-parity（pending）: 历史详情页与结束态共用同一 `TrackMapView`、渲染同一 `RunRecord.samples`。待消费面接线时补断言。

## 非目标

- 不做跑步中实时地图、不做双 SDK / 高德 / 审图号 / 地图许可采购。
- 不改归档格式、不升 `formatVersion`、不为派生 polyline 落盘（预算紧就用进程内缓存）；不迁 SwiftData。
- 不做平滑/降噪改写归档数据（平滑 = 伪造证据，GPX 必须与屏幕同源）。
- 不引入第三方地图/UI 框架，不子类化 `MKPolylineRenderer`。
- 不在 `ios/RunCore` 里接 MapKit/CoreLocation/SwiftUI/UIKit（纯 Foundation，L1 可 `swift test`）。
- 不做真机定位验收、不排人手步骤、不写「真机已验证」。

## 实现约束

- 分层：几何与相机纯逻辑只落 `Sources/PurePaceRunCore/`；`TrackMapView` 只做 MapKit 接线，保留将来换双 SDK 的抽象缝。
- 阈值先定后测：ε=3m、60s、8–12% 写进代码常量（`TrackGeometry` 静态 let），禁止红了再调阈值。
- 投影：`cos(lat0)` 按段取首点纬度，避免跨纬度段的系统性拉伸；RDP 用栈避免长轨迹递归爆栈。
- 相机：fail-closed —— padding 越界或空点集返回 `nil`，由视图层决定空态，不在几何层兜底给默认区域。
- 测试纪律：XCTest（禁 `import Testing`），坐标用固定步长公式合成，不读 `shared/fixtures`、不用 `Date()` 现时。
- 证据口径：只报 `swift test` 用例数与断言结论，不把「轨迹已上图」写进证据（地图壳未落地前不宣称可视化完成）。

## 最近交付证明

- workItemId: wi_intake_1d3cee7d621efc36（2026-11-11，pass，纯几何层）
- 交付：新增 `TrackGeometry`（`segments` 按 >60s 断线、`simplify` 迭代 RDP ε=3m、`renderSegments` 分段 + 抽稀 + 丢单点段、`boundingBox`、`cameraBox` padding 0.08–0.12 fail-closed、局部米制投影）与 8 例 `TrackGeometryTests`；未接 MapKit、未改归档与 GPX 契约。
- 实测：`test-ios-run-core` 165 例 0 失败（含 `TrackGeometryTests` 8 例）；`code_gates` 22 门全绿（attempt 001）。
- 边界（未闭合）：`TrackMapView` 地图壳、空态文案与图标、polyline 缓存静态门、结束态/详情页接线与截图证据均 `pending`，本域当前只有 L1 几何断言，无可视化证据。
