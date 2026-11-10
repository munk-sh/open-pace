#if DEBUG
import Foundation
import PurePaceRunCore

/// 仅截图取证用的演示跑次：由 `-screenshotHistoryDemo` 显式门控、只存在于 DEBUG 编译，
/// 不落盘、不读夹具，Release 路径编译期即不存在，正常启动不可见。
enum HistoryDemoRecords {
    static func records(arguments: [String] = CommandLine.arguments) -> [RunRecord]? {
        guard RunLaunchArguments.flagEnabled(
            RunLaunchArguments.screenshotHistoryDemoFlag,
            arguments: arguments
        ) else {
            return nil
        }
        return makeRecords()
    }

    private static func makeRecords() -> [RunRecord] {
        let startedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let activeDuration: TimeInterval = 1_860
        guard let total = RunDistance(meters: 5_120), let splitDistance = RunDistance(meters: 1_000) else {
            return []
        }
        let splits: [RunSplit] = [1, 2, 3].compactMap { index in
            RunSplit(
                index: index,
                distance: splitDistance,
                duration: activeDuration / 3
            )
        }
        let samples: [RunSample] = stride(from: 0.0, through: 1_800.0, by: 60.0).compactMap { offset in
            RunSample(
                latitude: 31.2304 + offset / 100_000,
                longitude: 121.4737 + offset / 100_000,
                altitude: 4,
                timestamp: startedAt.addingTimeInterval(offset),
                heartRate: 148,
                cadence: 176
            )
        }
        let record = RunRecord(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(activeDuration),
            distance: total,
            activeDuration: activeDuration,
            splits: splits,
            samples: samples
        )
        return record.map { [$0] } ?? []
    }
}
#endif
