import Foundation

/// 活跃时长的唯一时间源。
///
/// 契约：`uptime` 单调递增，只允许在同一进程内做差值；暂停区间由引擎在
/// `pause` / `resume` 处显式扣除，**采样回调不参与计时**。注入协议让测试
/// 用确定性时钟推进，无需 sleep 真实时间。
public protocol RunTimeSource: Sendable {
    /// 单调时钟读数（秒）。
    var uptime: TimeInterval { get }
}

/// 生产默认实现：系统单调时钟（`ProcessInfo.systemUptime`，含休眠时间、不受墙钟跳变影响）。
public struct SystemMonotonicTimeSource: RunTimeSource {
    public init() {}

    public var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}