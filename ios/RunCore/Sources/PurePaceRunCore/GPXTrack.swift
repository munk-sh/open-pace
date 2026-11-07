import Foundation

/// 可写入 GPX 1.1 的单条轨迹。只校验基本契约，不承载编解码逻辑。
public struct GPXTrack: Equatable, Sendable {
    public let name: String
    public let description: String?
    public let createdAt: Date
    public let activityType: String
    public let points: [RunSample]

    public init?(
        name: String,
        description: String? = nil,
        createdAt: Date,
        activityType: String,
        points: [RunSample]
    ) {
        guard !name.isEmpty else {
            return nil
        }
        guard !points.isEmpty else {
            return nil
        }
        for index in 1..<points.count {
            guard points[index].timestamp >= points[index - 1].timestamp else {
                return nil
            }
        }
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.activityType = activityType
        self.points = points
    }
}
