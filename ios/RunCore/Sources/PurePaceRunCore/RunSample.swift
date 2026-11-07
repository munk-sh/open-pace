import Foundation

/// 单个跑步采样点。只做字段合法性校验，不含插值、过滤或计算。
public struct RunSample: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let timestamp: Date
    public let heartRate: Int?
    public let cadence: Int?

    public init?(
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        timestamp: Date,
        heartRate: Int?,
        cadence: Int?
    ) {
        guard latitude.isFinite, latitude >= -90, latitude <= 90 else {
            return nil
        }
        guard longitude.isFinite, longitude >= -180, longitude <= 180 else {
            return nil
        }
        if let altitude {
            guard altitude.isFinite else {
                return nil
            }
        }
        guard timestamp != .distantPast, timestamp != .distantFuture else {
            return nil
        }
        if let heartRate {
            guard heartRate > 0 else {
                return nil
            }
        }
        if let cadence {
            guard cadence > 0 else {
                return nil
            }
        }
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.cadence = cadence
    }
}
