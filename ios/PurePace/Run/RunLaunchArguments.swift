import Foundation

/// 启动参数解析：纯函数、Release 可编译，不与定位源门控互相读取。
enum RunLaunchArguments {
    static let autoStartRecordingFlag = "-autoStartRecording"
    /// 仅截图取证：首屏 Tab（`run` / `history` / `settings`），Release 路径不读取。
    static let screenshotInitialTabFlag = "-screenshotInitialTab"
    /// 仅截图取证：历史页注入一条演示跑次（不落盘）。
    static let screenshotHistoryDemoFlag = "-screenshotHistoryDemo"
    /// 仅截图取证：历史页加载后直接进入首条记录详情。
    static let screenshotOpenRunDetailFlag = "-screenshotOpenRunDetail"

    /// 紧跟在 flag 之后的取值（小写化）；缺失、后跟其它 flag 或越界时返回 `nil`。
    static func value(after flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        let value = arguments[nextIndex]
        guard !value.hasPrefix("-") else { return nil }
        return value.lowercased()
    }

    /// 裸 flag 是否出现。
    static func flagEnabled(_ flag: String, arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    /// 默认关；裸 flag 或后跟 `1` / `true` 为开，其后跟其它值（含 `0`）为关。
    static func autoStartRecordingEnabled(arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: autoStartRecordingFlag) else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let value = arguments[nextIndex]
        guard !value.hasPrefix("-") else { return true }
        switch value.lowercased() {
        case "1", "true":
            return true
        default:
            return false
        }
    }
}
