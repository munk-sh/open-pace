import Foundation
import PurePaceRunCore

/// 测试用单调时钟：只由用例显式推进，禁止真实 sleep。
///
/// 计时真源是注入的 `RunTimeSource`（生产为系统单调时钟）；用例用本类把
/// 「会话时间」与喂入的 `Date` 对齐，断言活跃时长既不依赖真实墙钟、
/// 也不回退到采样时间戳累加。
final class TestRunClockSource: RunTimeSource, @unchecked Sendable {
    private var value: TimeInterval

    init(_ start: TimeInterval = 0) {
        value = start
    }

    var uptime: TimeInterval { value }

    func advance(by seconds: TimeInterval) {
        value += seconds
    }

    /// 对齐到某个 `Date` 的读数；只允许前进，保持单调时钟契约（回拨视为未推进）。
    func advance(to date: Date) {
        advance(to: date.timeIntervalSince1970)
    }

    /// 对齐到某个单调读数值；只允许前进，保持单调时钟契约。
    func advance(to seconds: TimeInterval) {
        value = max(value, seconds)
    }
}
