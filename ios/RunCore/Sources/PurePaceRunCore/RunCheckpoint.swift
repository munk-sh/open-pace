import Foundation

/// 会话 checkpoint 值类型。字段全部为原始值，可安全写入 JSONL 持久化文件。
public struct RunCheckpoint: Equatable, Sendable, Codable {
    /// 当前唯一的合法格式版本。
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let state: RunSessionState
    public let completedDistance: RunDistance
    public let elapsed: TimeInterval
    public let splits: [RunSplit]
    public let recordedAt: Date

    /// 构造 checkpoint；任一约束不满足返回 `nil`。
    public init?(
        formatVersion: Int = RunCheckpoint.currentFormatVersion,
        state: RunSessionState,
        completedDistance: RunDistance,
        elapsed: TimeInterval,
        splits: [RunSplit],
        recordedAt: Date
    ) {
        guard formatVersion == RunCheckpoint.currentFormatVersion else {
            return nil
        }
        guard elapsed.isFinite, elapsed >= 0 else {
            return nil
        }
        guard recordedAt != Date.distantPast, recordedAt != Date.distantFuture else {
            return nil
        }
        guard RunCheckpoint.hasContiguousSplitIndices(splits) else {
            return nil
        }
        if state == .ready {
            guard completedDistance.meters == 0, splits.isEmpty else {
                return nil
            }
        }
        self.formatVersion = formatVersion
        self.state = state
        self.completedDistance = completedDistance
        self.elapsed = elapsed
        self.splits = splits
        self.recordedAt = recordedAt
    }

    /// 分段序号必须从 1 开始、步长 1 连续。
    public static func hasContiguousSplitIndices(_ splits: [RunSplit]) -> Bool {
        var expected = 1
        for split in splits {
            guard split.index == expected else {
                return false
            }
            expected += 1
        }
        return true
    }

    // MARK: - Codable（手写，只编码原始标量）

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case state
        case completedDistance
        case elapsed
        case splits
        case recordedAt
    }

    private struct SplitPayload: Codable {
        let index: Int
        let distance: Double
        let duration: TimeInterval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == RunCheckpoint.currentFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: container,
                debugDescription: "未知 formatVersion: \(formatVersion)"
            )
        }
        let rawState = try container.decode(String.self, forKey: .state)
        guard let state = RunSessionState(rawValue: rawState) else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "未知 state: \(rawState)"
            )
        }
        let meters = try container.decode(Double.self, forKey: .completedDistance)
        guard let completedDistance = RunDistance(meters: meters) else {
            throw DecodingError.dataCorruptedError(
                forKey: .completedDistance,
                in: container,
                debugDescription: "非法距离: \(meters)"
            )
        }
        let elapsed = try container.decode(TimeInterval.self, forKey: .elapsed)
        let payloads = try container.decode([SplitPayload].self, forKey: .splits)
        var splits: [RunSplit] = []
        splits.reserveCapacity(payloads.count)
        for payload in payloads {
            guard
                let distance = RunDistance(meters: payload.distance),
                let split = RunSplit(index: payload.index, distance: distance, duration: payload.duration)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .splits,
                    in: container,
                    debugDescription: "非法分段: index \(payload.index)"
                )
            }
            splits.append(split)
        }
        let recordedAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .recordedAt))
        guard let checkpoint = RunCheckpoint(
            formatVersion: formatVersion,
            state: state,
            completedDistance: completedDistance,
            elapsed: elapsed,
            splits: splits,
            recordedAt: recordedAt
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .elapsed,
                in: container,
                debugDescription: "checkpoint 字段不满足契约"
            )
        }
        self = checkpoint
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(state.rawValue, forKey: .state)
        try container.encode(completedDistance.meters, forKey: .completedDistance)
        try container.encode(elapsed, forKey: .elapsed)
        let payloads = splits.map { split -> SplitPayload in
            SplitPayload(index: split.index, distance: split.distance.meters, duration: split.duration)
        }
        try container.encode(payloads, forKey: .splits)
        try container.encode(recordedAt.timeIntervalSince1970, forKey: .recordedAt)
    }
}
