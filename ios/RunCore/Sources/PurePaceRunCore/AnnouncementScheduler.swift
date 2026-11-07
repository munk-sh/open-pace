import Foundation

/// 每公里播报调度器。
///
/// 消费 `RunMetricsUpdate` 与调用方传入的 `RunSessionState`，产出按序、去重的
/// `AnnouncementCommand`。契约要点：
///
/// - 公里边界以 `RunMetricsUpdate.newlyCompletedSplits` 为准，每个 `splitIndex` 至多播报一次；
/// - 重复 tick 靠内部最大已播序号去抖，不依赖调用方去重，也不使用时钟间隔判定；
/// - `ready` / `paused` 恒不播报；
/// - 进入 `finished` 至多补一条收尾命令，此后不再产出任何命令；
/// - `paused → running` 的首次 tick 对未播公里最多补播一条 `.resumedAfterPause`。
///
/// 纯值语义：`struct` + `Sendable`，无 `class`/`actor`/锁/全局可变状态，不做 IO。
/// 所有命令的 `elapsed` 直接取自 `RunMetrics.elapsed`，保证用例可确定。
public struct AnnouncementScheduler: Equatable, Sendable {
    /// 每公里长度（米）。与 `RunMetricsEngine.splitDistanceMeters` 口径一致。
    private static let metersPerKilometer: Double = 1000.0

    private var lastAnnouncedSplitIndex: Int
    private var lastState: RunSessionState?
    private var didAnnounceFinish: Bool

    /// 由已播公里序号恢复；缺省 `0` 等价于全新调度器，负值按 `0` 处理。
    public init(announcedSplitIndex: Int = 0) {
        self.lastAnnouncedSplitIndex = max(0, announcedSplitIndex)
        self.lastState = nil
        self.didAnnounceFinish = false
    }

    /// 已播报过的最大公里序号；`0` 表示尚未播报任何公里。
    public var announcedSplitIndex: Int {
        lastAnnouncedSplitIndex
    }

    /// 喂入一次度量快照与会话状态，返回本次应播报的命令（按序、去重）。
    public mutating func tick(
        _ update: RunMetricsUpdate,
        state: RunSessionState
    ) -> [AnnouncementCommand] {
        let previousState = lastState
        lastState = state

        // 结束后不再产出任何命令，包含再次传入 `finished` 或携带新分段的 tick。
        guard !didAnnounceFinish else { return [] }

        switch state {
        case .ready, .paused:
            return []
        case .finished:
            didAnnounceFinish = true
            return finishCommands(update.metrics)
        case .running:
            if previousState == .paused {
                return catchUpCommands(update.metrics)
            }
            return kilometerCommands(update)
        }
    }
}

private extension AnnouncementScheduler {
    /// 公里边界命令：只取尚未播报过的 `newlyCompletedSplits`，按序号递增输出。
    mutating func kilometerCommands(_ update: RunMetricsUpdate) -> [AnnouncementCommand] {
        let pending = update.newlyCompletedSplits
            .filter { $0.index > lastAnnouncedSplitIndex }
            .sorted { $0.index < $1.index }
        guard !pending.isEmpty else { return [] }

        var commands: [AnnouncementCommand] = []
        for split in pending {
            guard let pace = split.pace,
                  let distance = RunDistance(meters: Double(split.index) * Self.metersPerKilometer),
                  let command = AnnouncementCommand(
                      trigger: .kilometerCompleted,
                      splitIndex: split.index,
                      distance: distance,
                      pace: pace,
                      elapsed: update.metrics.elapsed
                  )
            else {
                continue
            }
            lastAnnouncedSplitIndex = split.index
            commands.append(command)
        }
        return commands
    }

    /// 恢复补播：`paused → running` 的首次 tick，对未播公里最多补播一条。
    mutating func catchUpCommands(_ metrics: RunMetrics) -> [AnnouncementCommand] {
        let pending = metrics.splits.filter { $0.index > lastAnnouncedSplitIndex }
        let targetIndex: Int
        let pace: RunPace?
        if let lastPending = pending.max(by: { $0.index < $1.index }) {
            targetIndex = lastPending.index
            pace = lastPending.pace
        } else {
            guard metrics.completedKilometers > lastAnnouncedSplitIndex else { return [] }
            targetIndex = metrics.completedKilometers
            pace = metrics.splits.last?.pace ?? metrics.averagePace
        }

        guard targetIndex > lastAnnouncedSplitIndex,
              targetIndex >= 1,
              let distance = RunDistance(meters: Double(targetIndex) * Self.metersPerKilometer),
              let pace,
              let command = AnnouncementCommand(
                  trigger: .resumedAfterPause,
                  splitIndex: targetIndex,
                  distance: distance,
                  pace: pace,
                  elapsed: metrics.elapsed
              )
        else {
            return []
        }
        lastAnnouncedSplitIndex = targetIndex
        return [command]
    }

    /// 收尾命令：至多一条，`splitIndex == 已完成公里数`，0 公里时不产出。
    func finishCommands(_ metrics: RunMetrics) -> [AnnouncementCommand] {
        let splitIndex = metrics.completedKilometers
        guard splitIndex >= 1,
              let distance = RunDistance(meters: Double(splitIndex) * Self.metersPerKilometer),
              let pace = metrics.splits.last(where: { $0.index == splitIndex })?.pace
                  ?? metrics.averagePace,
              let command = AnnouncementCommand(
                  trigger: .finished,
                  splitIndex: splitIndex,
                  distance: distance,
                  pace: pace,
                  elapsed: metrics.elapsed
              )
        else {
            return []
        }
        return [command]
    }
}
