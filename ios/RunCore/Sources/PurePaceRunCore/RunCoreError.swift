import Foundation

/// 跑步域统一错误类型。只做错误分类与可读描述，不含恢复策略。
public enum RunCoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidDistance(Double)
    case invalidPace(Double)
    case invalidDuration(TimeInterval)
    case invalidSplitIndex(Int)
    case invalidCoordinate(latitude: Double, longitude: Double)
    case invalidSample(String)
    case invalidStateTransition(from: RunSessionState, to: RunSessionState)
    case corruptedCheckpoint(String)

    public var description: String {
        switch self {
        case let .invalidDistance(meters):
            return "invalidDistance: 距离必须为有限非负数，实际 \(meters)"
        case let .invalidPace(secondsPerKilometer):
            return "invalidPace: 配速必须为有限正数，实际 \(secondsPerKilometer)"
        case let .invalidDuration(duration):
            return "invalidDuration: 耗时必须为有限正数，实际 \(duration)"
        case let .invalidSplitIndex(index):
            return "invalidSplitIndex: 分段序号必须从 1 开始，实际 \(index)"
        case let .invalidCoordinate(latitude, longitude):
            return "invalidCoordinate: 坐标越界，纬度 \(latitude)，经度 \(longitude)"
        case let .invalidSample(reason):
            return "invalidSample: 采样点不合法，原因 \(reason)"
        case let .invalidStateTransition(from, to):
            return "invalidStateTransition: 不允许从 \(from.rawValue) 迁移到 \(to.rawValue)"
        case let .corruptedCheckpoint(reason):
            return "corruptedCheckpoint: checkpoint 数据损坏，原因 \(reason)"
        }
    }
}
