import Foundation
import PurePaceRunCore

/// 跑步页展示用的纯格式化函数：只做数值到字符串的映射，不持有状态、不读时钟。
enum RunFormatting {
    /// 配速空态固定占位，便于 UI 测试稳定断言。
    static let emptyPace = "--"

    /// 全仓固定时区：中文日期格式必须与设备时区无关，固定 fixture 才能稳定断言。
    static let zhHansTimeZone = TimeZone(identifier: "Asia/Shanghai")!

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

    /// 历史行 / 详情共用的 zh-Hans 日期时间（分钟精度，如「2025年10月9日 16:53」）。
    static func zhHansDateTimeText(_ date: Date, timeZone: TimeZone = zhHansTimeZone) -> String {
        zhHansDateText(date, format: "yyyy年M月d日 HH:mm", timeZone: timeZone)
    }

    /// 历史详情的起止时间：带秒，保证同一次跑次的开始/结束文本可区分。
    static func dateTimeText(_ date: Date, timeZone: TimeZone = zhHansTimeZone) -> String {
        zhHansDateText(date, format: "yyyy年M月d日 HH:mm:ss", timeZone: timeZone)
    }

    private static func zhHansDateText(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// 分段序号文本（`RunSplit.index` 从 1 开始）。
    static func splitIndexText(_ index: Int) -> String {
        "\(index)"
    }

    /// 分段区域摘要，含分段条数，供 UI 测试与详情标题共用。
    static func splitSummaryText(count: Int) -> String {
        "分段 · \(max(0, count))"
    }
}
