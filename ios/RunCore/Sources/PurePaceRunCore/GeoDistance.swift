import Foundation

/// 球面大圆距离（Haversine）。纯函数，无状态、无 IO。
public enum GeoDistance: Sendable {
    /// 地球平均半径（米）。与 shared 口径保持一致，写死不可配置。
    public static let earthRadiusMeters: Double = 6_371_000.0

    /// 两组经纬度（度）之间的 Haversine 距离（米）。
    public static func meters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let phi1 = latitude1 * Double.pi / 180.0
        let phi2 = latitude2 * Double.pi / 180.0
        let deltaPhi = (latitude2 - latitude1) * Double.pi / 180.0
        let deltaLambda = (longitude2 - longitude1) * Double.pi / 180.0

        let sinHalfDeltaPhi = sin(deltaPhi / 2.0)
        let sinHalfDeltaLambda = sin(deltaLambda / 2.0)
        let h = sinHalfDeltaPhi * sinHalfDeltaPhi
            + cos(phi1) * cos(phi2) * sinHalfDeltaLambda * sinHalfDeltaLambda
        // min(1.0, ...) 防 asin 定义域越界（对跖点浮点误差）。
        let clamped = min(1.0, sqrt(max(0.0, h)))
        return 2.0 * earthRadiusMeters * asin(clamped)
    }
}
