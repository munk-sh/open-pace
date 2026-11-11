import Foundation

/// 轨迹渲染的纯逻辑（仅 Foundation，无平台框架依赖），承载 L1 可测的抽稀、断线分段与相机包围盒。
///
/// 存储与渲染分离：入参只读 `RunSample`，从不修改归档 `samples`，因此 GPX 导出语义不受影响。
public enum TrackGeometry {
    /// 渲染抽稀阈值（米）。固定常量，禁止红了再调。
    public static let simplificationEpsilonMeters: Double = 3.0

    /// 采样间隔离散阈值（秒）：严格大于该值才断线，60s 本身不断。
    public static let maxSegmentGapSeconds: TimeInterval = 60

    /// 相机 padding 合法区间（包围盒尺寸的比例）。
    public static let minimumCameraPadding: Double = 0.08
    public static let maximumCameraPadding: Double = 0.12
}

/// 轨迹坐标（WGS-84），由平台视图接线时再转换为屏幕坐标。
public struct TrackCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 轨迹包围盒（经纬度）。
public struct TrackBoundingBox: Equatable, Sendable {
    public let minimumLatitude: Double
    public let maximumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLongitude: Double

    public init(
        minimumLatitude: Double,
        maximumLatitude: Double,
        minimumLongitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.maximumLatitude = maximumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLongitude = maximumLongitude
    }

    public var latitudeSpan: Double { maximumLatitude - minimumLatitude }
    public var longitudeSpan: Double { maximumLongitude - minimumLongitude }
    public var centerLatitude: Double { (minimumLatitude + maximumLatitude) / 2 }
    public var centerLongitude: Double { (minimumLongitude + maximumLongitude) / 2 }
}

public extension TrackGeometry {
    /// 把采样点按时间切段：相邻时间差 > 60s 处分段；不改写任何采样。
    static func segments(from samples: [RunSample]) -> [[TrackCoordinate]] {
        guard !samples.isEmpty else { return [] }
        var result: [[TrackCoordinate]] = []
        var current: [TrackCoordinate] = []
        var previousTimestamp: Date?
        for sample in samples {
            if let previousTimestamp,
               sample.timestamp.timeIntervalSince(previousTimestamp) > maxSegmentGapSeconds {
                result.append(current)
                current = []
            }
            current.append(TrackCoordinate(latitude: sample.latitude, longitude: sample.longitude))
            previousTimestamp = sample.timestamp
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    /// 对单段轨迹做 RDP 抽稀；只作用于渲染输入，epsilon 固定 3m。
    static func simplify(
        _ points: [TrackCoordinate],
        epsilonMeters: Double = simplificationEpsilonMeters
    ) -> [TrackCoordinate] {
        guard points.count > 2, epsilonMeters > 0 else { return points }
        let projected = points.map(project)
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = -1
            var farthestDistance = 0.0
            for index in (start + 1)..<end {
                let distance = perpendicularDistance(projected[index], projected[start], projected[end])
                if distance > farthestDistance {
                    farthestDistance = distance
                    farthest = index
                }
            }
            if farthest > 0, farthestDistance > epsilonMeters {
                keep[farthest] = true
                stack.append((start, farthest))
                stack.append((farthest, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// 渲染用分段：先按 >60s 断线，再对每段独立抽稀。
    static func renderSegments(from samples: [RunSample]) -> [[TrackCoordinate]] {
        segments(from: samples)
            .map { simplify($0) }
            .filter { $0.count >= 2 }
    }

    /// 包围盒；无点返回 nil。
    static func boundingBox(of points: [TrackCoordinate]) -> TrackBoundingBox? {
        guard let first = points.first else { return nil }
        var minimumLatitude = first.latitude
        var maximumLatitude = first.latitude
        var minimumLongitude = first.longitude
        var maximumLongitude = first.longitude
        for point in points.dropFirst() {
            minimumLatitude = min(minimumLatitude, point.latitude)
            maximumLatitude = max(maximumLatitude, point.latitude)
            minimumLongitude = min(minimumLongitude, point.longitude)
            maximumLongitude = max(maximumLongitude, point.longitude)
        }
        return TrackBoundingBox(
            minimumLatitude: minimumLatitude,
            maximumLatitude: maximumLatitude,
            minimumLongitude: minimumLongitude,
            maximumLongitude: maximumLongitude
        )
    }

    /// 相机一次定位的包围盒：padding 必须是 0.08…0.12，越界返回 nil（fail-closed）。
    /// 每条边各扩 `span * padding`，因此 span 增量 = 2 * padding。
    static func cameraBox(
        for points: [TrackCoordinate],
        paddingRatio: Double
    ) -> TrackBoundingBox? {
        guard paddingRatio >= minimumCameraPadding,
              paddingRatio <= maximumCameraPadding,
              let box = boundingBox(of: points)
        else {
            return nil
        }
        // 单点 / 极小轨迹给一个最小可视跨度，避免相机缩到 0。
        let minimumSpan = 0.0002
        let latitudeSpan = max(box.latitudeSpan, minimumSpan)
        let longitudeSpan = max(box.longitudeSpan, minimumSpan)
        let latitudePadding = latitudeSpan * paddingRatio
        let longitudePadding = longitudeSpan * paddingRatio
        return TrackBoundingBox(
            minimumLatitude: box.centerLatitude - latitudeSpan / 2 - latitudePadding,
            maximumLatitude: box.centerLatitude + latitudeSpan / 2 + latitudePadding,
            minimumLongitude: box.centerLongitude - longitudeSpan / 2 - longitudePadding,
            maximumLongitude: box.centerLongitude + longitudeSpan / 2 + longitudePadding
        )
    }

    // MARK: - 局部米制投影

    /// `x = lon * 111320 * cos(lat0)`、`y = lat * 111320`（lat0 取首点纬度）。
    private static func project(_ points: [TrackCoordinate]) -> [(x: Double, y: Double)] {
        let origin = points.first?.latitude ?? 0
        let longitudeScale = 111_320 * cos(origin * .pi / 180)
        return points.map { (x: $0.longitude * longitudeScale, y: $0.latitude * 111_320) }
    }

    private static func project(_ point: TrackCoordinate) -> (x: Double, y: Double) {
        project([point])[0]
    }

    /// 点到线段的垂直距离（米）；线段退化为点时退化为点距。
    private static func perpendicularDistance(
        _ point: (x: Double, y: Double),
        _ start: (x: Double, y: Double),
        _ end: (x: Double, y: Double)
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let projectionX = start.x + t * dx
        let projectionY = start.y + t * dy
        return hypot(point.x - projectionX, point.y - projectionY)
    }
}
