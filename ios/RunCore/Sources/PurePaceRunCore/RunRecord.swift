import Foundation

/// 一次已完成跑次的归档值类型。字段全部为原始值，可安全序列化为单条 JSON 记录。
public struct RunRecord: Equatable, Sendable, Codable {
    /// 当前唯一的合法格式版本。
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let distance: RunDistance
    public let activeDuration: TimeInterval
    public let splits: [RunSplit]
    /// 全量采样点，按时间戳非递减顺序保存；导出直接复用，不做降采样。
    public let samples: [RunSample]

    /// 构造跑次记录；任一约束不满足返回 `nil`。
    public init?(
        formatVersion: Int = RunRecord.currentFormatVersion,
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        distance: RunDistance,
        activeDuration: TimeInterval,
        splits: [RunSplit],
        samples: [RunSample]
    ) {
        guard formatVersion == RunRecord.currentFormatVersion else {
            return nil
        }
        let startSeconds = startedAt.timeIntervalSince1970
        let endSeconds = endedAt.timeIntervalSince1970
        guard startSeconds.isFinite, endSeconds.isFinite else {
            return nil
        }
        guard startedAt != .distantPast, startedAt != .distantFuture else {
            return nil
        }
        guard endedAt != .distantPast, endedAt != .distantFuture else {
            return nil
        }
        guard endedAt >= startedAt else {
            return nil
        }
        guard activeDuration.isFinite, activeDuration >= 0 else {
            return nil
        }
        guard distance.meters.isFinite, distance.meters >= 0 else {
            return nil
        }
        guard RunCheckpoint.hasContiguousSplitIndices(splits) else {
            return nil
        }
        if samples.count > 1 {
            for index in 1..<samples.count {
                guard samples[index].timestamp >= samples[index - 1].timestamp else {
                    return nil
                }
            }
        }
        self.formatVersion = formatVersion
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distance = distance
        self.activeDuration = activeDuration
        self.splits = splits
        self.samples = samples
    }

    // MARK: - Codable（手写，只编码原始标量）

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case id
        case startedAt
        case endedAt
        case distance
        case activeDuration
        case splits
        case samples
    }

    private struct SplitPayload: Codable {
        let index: Int
        let distance: Double
        let duration: TimeInterval
    }

    private struct SamplePayload: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let timestamp: TimeInterval
        let heartRate: Int?
        let cadence: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == RunRecord.currentFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: container,
                debugDescription: "未知 formatVersion: \(formatVersion)"
            )
        }
        let rawID = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: rawID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "非法 id: \(rawID)"
            )
        }
        let startedAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .startedAt))
        let endedAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .endedAt))
        let meters = try container.decode(Double.self, forKey: .distance)
        guard let distance = RunDistance(meters: meters) else {
            throw DecodingError.dataCorruptedError(
                forKey: .distance,
                in: container,
                debugDescription: "非法距离: \(meters)"
            )
        }
        let activeDuration = try container.decode(TimeInterval.self, forKey: .activeDuration)
        let splitPayloads = try container.decode([SplitPayload].self, forKey: .splits)
        var splits: [RunSplit] = []
        splits.reserveCapacity(splitPayloads.count)
        for payload in splitPayloads {
            guard
                let splitDistance = RunDistance(meters: payload.distance),
                let split = RunSplit(index: payload.index, distance: splitDistance, duration: payload.duration)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .splits,
                    in: container,
                    debugDescription: "非法分段: index \(payload.index)"
                )
            }
            splits.append(split)
        }
        let samplePayloads = try container.decode([SamplePayload].self, forKey: .samples)
        var samples: [RunSample] = []
        samples.reserveCapacity(samplePayloads.count)
        for payload in samplePayloads {
            guard
                let sample = RunSample(
                    latitude: payload.latitude,
                    longitude: payload.longitude,
                    altitude: payload.altitude,
                    timestamp: Date(timeIntervalSince1970: payload.timestamp),
                    heartRate: payload.heartRate,
                    cadence: payload.cadence
                )
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .samples,
                    in: container,
                    debugDescription: "非法采样点"
                )
            }
            samples.append(sample)
        }
        guard let record = RunRecord(
            formatVersion: formatVersion,
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            distance: distance,
            activeDuration: activeDuration,
            splits: splits,
            samples: samples
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .activeDuration,
                in: container,
                debugDescription: "跑次字段不满足契约"
            )
        }
        self = record
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(startedAt.timeIntervalSince1970, forKey: .startedAt)
        try container.encode(endedAt.timeIntervalSince1970, forKey: .endedAt)
        try container.encode(distance.meters, forKey: .distance)
        try container.encode(activeDuration, forKey: .activeDuration)
        let splitPayloads = splits.map { split -> SplitPayload in
            SplitPayload(index: split.index, distance: split.distance.meters, duration: split.duration)
        }
        try container.encode(splitPayloads, forKey: .splits)
        let samplePayloads = samples.map { sample -> SamplePayload in
            SamplePayload(
                latitude: sample.latitude,
                longitude: sample.longitude,
                altitude: sample.altitude,
                timestamp: sample.timestamp.timeIntervalSince1970,
                heartRate: sample.heartRate,
                cadence: sample.cadence
            )
        }
        try container.encode(samplePayloads, forKey: .samples)
    }
}
