import Foundation
import PurePaceRunCore

/// 测试用单调时钟：只由用例显式推进，禁止真实 sleep。
final class TestRunClock: RunTimeSource, @unchecked Sendable {
    private var value: TimeInterval = 0

    init(_ start: TimeInterval = 0) {
        value = start
    }

    var uptime: TimeInterval { value }

    func advance(by seconds: TimeInterval) {
        value += seconds
    }
}
