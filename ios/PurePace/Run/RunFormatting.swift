import Foundation
import PurePaceRunCore

/// 跑步页展示用的纯格式化函数：只做数值到字符串的映射，不持有状态、不读时钟。
enum RunFormatting {
    /// 配速空态固定占位，便于 UI 测试稳定断言。
    static let emptyPace = "--"

    static func distanceText(_ distance: RunDistance) -> String {
        String(format: "%.2f km", distance.meters / 1000)
    }

    static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func paceText(_ pace: RunPace?) -> String {
        guard let pace else {
            return emptyPace
        }
        let total = max(0, Int(pace.secondsPerKilometer.rounded()))
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    static func splitCountText(_ count: Int) -> String {
        "\(max(0, count))"
    }
}
