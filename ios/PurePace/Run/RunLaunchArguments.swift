import Foundation

/// 启动参数解析：纯函数、Release 可编译，不与定位源门控互相读取。
enum RunLaunchArguments {
    static let autoStartRecordingFlag = "-autoStartRecording"

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
