import MapKit
import PurePaceRunCore
import SwiftUI

/// App 内唯一地图壳：跑步结束态与跑次详情页共用，记录态一律不渲染。
///
/// 几何全部委托 `TrackGeometry`（>60s 断线 + RDP ε=3m 渲染抽稀），本视图只做缓存与绘制：
/// polyline 与相机在 `init` 中一次性构造并由 `@State` 持有，父视图刷新不会重建；
/// 空轨迹 / 无有效坐标 / 单点轨迹一律不构造 `Map`，走明确中文空态。
struct TrackMapView: View {
    /// 相机 padding：固定 10%，落在 `TrackGeometry` 允许的 8%–12% 区间内，越界由纯函数 fail-closed。
    static let cameraPaddingRatio: Double = 0.10

    let samples: [RunSample]
    /// 空态稳定 identifier（如 `run.mapEmpty` / `runDetail.mapEmpty`）。
    let emptyIdentifier: String
    /// 单点轨迹 identifier；调用方显式传入，保证与空态文案可区分。
    let singlePointIdentifier: String

    @State private var haloSegments: [MapPolyline]
    @State private var trackSegments: [MapPolyline]
    @State private var cameraPosition: MapCameraPosition
    @State private var trackKind: TrackKind
    @State private var cameraFitLog: String?
    @State private var didLogCameraFit = false

    private enum TrackKind: Equatable {
        case empty
        case singlePoint
        case track
    }

    init(samples: [RunSample], emptyIdentifier: String, singlePointIdentifier: String) {
        self.samples = samples
        self.emptyIdentifier = emptyIdentifier
        self.singlePointIdentifier = singlePointIdentifier

        let validSamples = TrackGeometry.validSamples(from: samples)
        let segments = TrackGeometry.renderSegments(from: validSamples)
        let coordinates = validSamples.map {
            TrackCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let cameraBox = TrackGeometry.cameraBox(
            for: coordinates,
            paddingRatio: TrackMapView.cameraPaddingRatio
        )

        let kind: TrackKind
        if segments.isEmpty {
            kind = validSamples.count == 1 ? .singlePoint : .empty
        } else if let cameraBox {
            kind = .track
            _ = cameraBox
        } else {
            kind = .empty
        }

        let lines = segments.map { segment in
            MapPolyline(coordinates: segment.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            })
        }
        let visibleLines = kind == .track ? lines : []

        _haloSegments = State(initialValue: visibleLines)
        _trackSegments = State(initialValue: visibleLines)
        _trackKind = State(initialValue: kind)

        if kind == .track, let cameraBox {
            _cameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: cameraBox.centerLatitude,
                        longitude: cameraBox.centerLongitude
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: cameraBox.latitudeSpan,
                        longitudeDelta: cameraBox.longitudeSpan
                    )
                )
            ))
            _cameraFitLog = State(initialValue: String(
                format: "trackMap.cameraFit minLat=%.6f maxLat=%.6f minLon=%.6f maxLon=%.6f padding=%.2f segments=%d",
                cameraBox.minimumLatitude,
                cameraBox.maximumLatitude,
                cameraBox.minimumLongitude,
                cameraBox.maximumLongitude,
                TrackMapView.cameraPaddingRatio,
                segments.count
            ))
        } else {
            _cameraPosition = State(initialValue: .automatic)
            _cameraFitLog = State(initialValue: nil)
        }
    }

    var body: some View {
        Group {
            switch trackKind {
            case .track:
                map
            case .singlePoint:
                emptyState(
                    symbol: "location.circle",
                    title: L10n.runMapSingleTitle,
                    message: L10n.runMapSingleBody,
                    identifier: singlePointIdentifier
                )
            case .empty:
                emptyState(
                    symbol: "map",
                    title: L10n.runMapEmptyTitle,
                    message: L10n.runMapEmptyBody,
                    identifier: emptyIdentifier
                )
            }
        }
        .onAppear { logCameraFitOnce() }
    }

    /// 地图本体：光晕在下、accent 主轨迹在上；相机由 `cameraPosition` 一次定位后不再回写。
    /// 轨迹预览是装饰性缩略：MapKit 内部注释 / 瓦片会自带可及元素（如 "Section N" 等系统文案），
    /// 一律从可及树隐藏，只由外层容器暴露一个 zh-Hans label 的整体元素。
    private var map: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(haloSegments.indices, id: \.self) { index in
                    haloSegments[index]
                        .stroke(DesignTokens.Colors.accentSoft, lineWidth: DesignTokens.Stroke.trackHalo)
                }
                ForEach(trackSegments.indices, id: \.self) { index in
                    trackSegments[index]
                        .stroke(DesignTokens.Colors.accent, lineWidth: DesignTokens.Stroke.track)
                }
            }
            .onMapCameraChange { _ in logCameraChange() }
            // 轨迹缩略不承载周边 POI：关掉注记点，既减少视觉噪声，也避免 MapKit
            // 把系统注记（VKPointFeature / "Section N"）注入可及树污染 zh-Hans 文案门禁。
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("run.mapPreview")
        .accessibilityLabel(Text(L10n.runMapPreviewLabel))
    }

    /// 空态卡：图标 + 标题 + 说明，占据与地图一致的位置，不留白地图。
    private func emptyState(
        symbol: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        identifier: String
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.primaryValue)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.primary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(Text(title))
            Text(message)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.sm)
        .background(
            DesignTokens.Colors.surface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separator, lineWidth: DesignTokens.Stroke.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(title))
    }

    /// 同一轨迹身份只打一次相机定位日志（DEBUG），供回执摘录次数。
    private func logCameraFitOnce() {
#if DEBUG
        guard !didLogCameraFit, let cameraFitLog else { return }
        didLogCameraFit = true
        print(cameraFitLog)
#endif
    }

    /// 相机变化只留日志，绝不写回 `cameraPosition` 或任何 state（静态断言守此约束）。
    private func logCameraChange() {
#if DEBUG
        print("trackMap.cameraChange observed")
#endif
    }
}
