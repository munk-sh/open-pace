# Domain: ios-track-render

轨迹渲染子域：把「存 WGS-84 原始采样 → 渲染期派生 polyline」这段只读派生逻辑收口在 `ios/RunCore`（`PurePaceRunCore`，只 `import Foundation`），再由 App 内唯一地图壳 `ios/PurePace/Track/TrackMapView.swift` 消费，供跑步结束态与历史详情页的地图卡使用。存储与渲染分离：本域只读 `RunSample`，从不回写归档，GPX 导出语义不受影响。当前纯几何层（断线分段 / RDP 抽稀 / 包围盒与相机框 / 坐标合法性过滤）与 MapKit 壳均已落地并接线到结束态与详情页。

## 范围

- `ios/RunCore/Sources/PurePaceRunCore/TrackGeometry.swift`：常量 `simplificationEpsilonMeters = 3.0`、`maxSegmentGapSeconds = 60`、`minimumCameraPadding = 0.08` / `maximumCameraPadding = 0.12`；值类型 `TrackCoordinate`（含 `isValidWGS84`：纬度 ±90、经度 ±180，`180.0001` 非法）、`TrackBoundingBox`、`validSamples(from:)`（保序过滤非法坐标）；派生函数 `segments(from:)`、`simplify(_:epsilonMeters:)`、`renderSegments(from:)`、`boundingBox(of:)`、`cameraBox(for:paddingRatio:)`。
- 局部米制投影固定为 `x = lon * 111320 * cos(lat0)`、`y = lat * 111320`（`lat0` 取该段首点纬度）；RDP 用点到线段垂距的迭代栈实现，不做递归、不引入浮点工具。
- 测试：`ios/RunCore/Tests/PurePaceRunCoreTests/TrackGeometryTests.swift`（分段边界含 60s 精确边界 / 坐标保真 / 空输入 / 单点 / 抽稀误差与 ε 反例 / 短段不抽 / padding 边界 / 包围盒扩张 / 空轨迹 nil / 跨 180° 经线 / 渲染不写回归档）。
- 消费面：结束态轨迹预览卡与历史详情页地图卡共用同一 `TrackMapView`（`Map(position:)` + 多段 `MapPolyline(...).stroke`，不子类化 renderer），是全 App 唯一 `import MapKit` 文件；主轨迹 `DesignTokens.Colors.accent` / `Stroke.track`(4pt)，光晕 `accentSoft` / `Stroke.trackHalo`(=track×2)；相机 padding 固定 `cameraPaddingRatio = 0.10`；`onMapCameraChange` 只打日志不回写 state；空轨迹 / 无有效坐标 / 单点给 zh-Hans 空态文案 + 图标。

## 验收

- ac-map-break-segments: 按采样时间切段——相邻间隔 59s 不断、61s 断、跨 3 段夹具输出 3 段；切段只产出坐标，不改写任何采样。落点 `TrackGeometryTests.testSegmentSplitAtSixtySecondsBoundary` / `testSegmentsPreserveOriginalCoordinates` / `testEmptySamplesProduceNoSegments`。
- ac-map-rdp-render-only: RDP ε=3m 在局部米制投影下执行，固定夹具上每点最大偏差 < 3m；抽稀只作用于渲染输入，归档 `samples` 与 GPX 全量点不受影响（`check-gpx-export` 仍绿）。落点 `testSimplificationKeepsEveryPointWithinThreeMeters` / `testSimplificationLeavesShortSegmentsUntouched`。
- ac-map-camera-fit: `cameraBox(for:paddingRatio:)` 的 padding 只接受 0.08…0.12（7% / 13% 返回 nil，fail-closed），每条边各扩 `span * padding` 即 span 增量 = `2 * padding`；极小轨迹给最小可视跨度 0.0002 避免相机缩到 0；空轨迹返回 nil。落点 `testCameraPaddingAcceptsEightToTwelvePercentOnly` / `testCameraBoxExpandsByPaddingOnEverySide` / `testCameraBoxNilForEmptyTrack`。
- ac-render-segments-pipeline: `renderSegments(from:)` 先按 >60s 断线再逐段抽稀，且丢弃抽稀后少于 2 点的段（单点段不上图）。
- ac-track-render-no-storage-write: `TrackGeometry` 入参只读、无 `mutating`、无文件 IO、无 `import` 平台框架；`RunRecord`/`RunArchiveStore`/`RunGPXExporter` 契约零改动，`formatVersion` 不变，不新增字段。
- ac-map-single-shell: `ios/PurePace/Track/TrackMapView.swift` 是 App 内唯一地图壳，也是唯一允许 `import MapKit` 的文件（`validate_app_imports` 精确放行该路径，其它目录含 `Harness` / `History` 仍判红；`HealthKit`/`CoreMotion`/`UserNotifications`/`URLSession` 禁止不变）；只有 `RunView` 的 `state == .finished` 分支与 `RunDetailView` 引用它，ready/running/paused 无地图视图。反例：记录态插地图、MapKit 越界到其它目录，必须判红。
- ac-map-empty-state: 空 samples / 无有效坐标 / 单点轨迹三种输入均不构造 `Map`/`MapPolyline`，渲染 zh-Hans 空态（图标 + 标题 + 说明 + 稳定 identifier：结束态 `run.mapEmpty` / `run.mapEmpty.single`，详情页 `runDetail.mapEmpty` / `runDetail.mapEmpty.single`）；单点与空轨迹文案可区分。落点 `TrackMapView.init`（`TrackKind.empty/singlePoint/track` 三态判定）+ `check-ios-shell` 空态断言。反例：删文案/图标、单点仍出 polyline，必须判红。
- ac-map-polyline-cached: `MapPolyline` 在 `init` 中按 `TrackGeometry.renderSegments` 一次性构造并由 `@State` 持有，`body` 内只做 `ForEach` 绘制；`body` 因父视图刷新重算时不重建（静态断言构造点在 `body` 外）。polyline 数量等于渲染段数，光晕与主轨迹共用同一组段。反例：把构造移进 `body` 必须判红。
- ac-map-camera-once: 相机只由 `TrackGeometry.cameraBox(for:paddingRatio: TrackMapView.cameraPaddingRatio = 0.10)` 计算一次并存入 `@State`；`onMapCameraChange` 闭包内零 state 赋值（静态断言：该闭包体内不得出现 `cameraPosition =`）；DEBUG 日志 `trackMap.cameraFit` 由 `didLogCameraFit` 守卫，同一轨迹身份恰 1 行，含包围盒四至、padding 与段数。反例：padding 改 0.07/0.13、闭包回写 `cameraPosition` 必须判红。
- ac-track-coordinate-validity: `TrackCoordinate.isValidWGS84` 拒绝纬度 >90 / 经度 >180（`180.0001` 非法）且 `validSamples(from:)` 保序过滤；经度 ±180 与跨 180° 经线夹具不丢点、不重排、不产生非法坐标；RDP / 相机纯函数在这些输入上不崩，明确不做跨线最短路径优化。落点 `testTrackCoordinateValidityBoundaries` / 跨线夹具用例。反例：接受 `180.0001`、跨线夹具丢点，必须判红。
- ac-default-epsilon-3m: `simplificationEpsilonMeters == 3.0` 且不得改；固定夹具上默认 `simplify` 每点最大偏差 <3m 且点数减少；同 commit 反例用显式 `simplify(points, epsilonMeters: 8)` 证明偏差 >3m（默认阈值改 8 时默认用例即判红）。落点 `testDefaultEpsilonStaysThreeMeters`。
- ac-detail-map-parity: 结束态与历史详情页共用同一 `TrackMapView` 与同一 `RunRecord.samples` 数据源（结束态取只读快照，详情页取 `record(withID:)` 解码结果），两处段数/点数一致；详情页无轨迹走 `runDetail.mapEmpty` 空态。反例：两处各写一套地图壳、详情页不带 samples 仍出图，必须判红。


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
- 证据口径：L1 证据只报 `swift test` 用例数与断言结论；可视化证据须是模拟器截图落盘或可摘录的 DEBUG 日志，未采到就写 `pending: 待人现场`，不得以「已接线」代替图示证据。

## 最近交付证明

- workItemId: wi_intake_7b9d19bc1e3be0ee（2026-11-12，pass）
- 交付：新增 `ios/PurePace/Track/TrackMapView.swift`（唯一 `import MapKit`；`init` 内 `validSamples` → `renderSegments` → `MapPolyline` 一次性构造并由 `@State` 持有；`cameraBox` padding 固定 0.10 一次定位；`onMapCameraChange` 只打日志；空/单点走 zh-Hans 空态，不构造 `Map`）；`RunView` 只在 `state == .finished` 挂轨迹预览卡，`RunDetailView` 加 `mapSection` 共用同一壳；`TrackGeometry` 只做加法（`isValidWGS84` / `validSamples`），ε=3m 与 60s 常量未改。
- 判定与断言：`TrackGeometryTests` 新增 7 例（60s 精确边界、61s 断 2 段、单点 1 段/渲染 0 段、空输入 0 段且相机 nil、坐标合法性、跨 180° 不丢点不重排、`epsilonMeters: 8` 偏差 >3m 反例、渲染不写回归档）；`swift test --package-path ios/RunCore` 173 例 0 失败；`check-ios-shell.sh` 29 项断言 0 失败（MapKit 允许表正反例、地图壳绘制/相机/仅 finished 静态断言）；`code_gates` 22 门全绿（attempt 001）。
- 边界（未闭合）：三张证据 PNG（`docs/evidence/track-map/{empty,single,multi}.png`）未产出，`trackMap.cameraFit` 运行时「次数 = 1」与列表量化耗时未采集，均在验证矩阵里标「本项实测」但缺截图/日志回执，记 `pending: 待人现场`。

