import Foundation

/// Harness 运行模式。`rawValue` 同时是 launch arg 取值与 status `mode` 字段取值。
enum HarnessMode: String, CaseIterable, Sendable {
    case direct
    case corelocation
    case resume
}

/// 已校验的 Harness 启动配置。路径来自 launch args，均为 App 容器内绝对路径。
struct HarnessConfiguration: Equatable, Sendable {
    let mode: HarnessMode
    let statusURL: URL
    let checkpointURL: URL
    let streamURL: URL?
    let maxDurationSeconds: TimeInterval?
}

/// 稳定的参数错误码；`code` 会原样写入 status `error.code`。
struct HarnessArgumentError: Error, Equatable, Sendable {
    let code: String
    let message: String
}

/// launch arg 解析结果。`.inactive` 表示没有 `--harness`，App 必须完全走占位首屏。
enum HarnessActivation: Equatable, Sendable {
    case inactive
    case active(HarnessConfiguration)
    case invalid(mode: HarnessMode?, statusURL: URL?, error: HarnessArgumentError)
}

/// 仅由 launch args 驱动的 Harness 入口判定（纯逻辑，无 IO、无平台框架）。
enum HarnessArgumentParser {
    static func parse(arguments: [String]) -> HarnessActivation {
        var flags: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                index += 1
                continue
            }
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                flags[token] = arguments[index + 1]
                index += 2
            } else {
                // 记为空值，交由「缺必需参数」统一报错。
                flags[token] = ""
                index += 1
            }
        }

        guard flags.keys.contains("--harness") else {
            return .inactive
        }

        let statusURL = url(from: flags["--status"])

        guard let rawMode = flags["--harness"], !rawMode.isEmpty else {
            return .invalid(
                mode: nil,
                statusURL: statusURL,
                error: HarnessArgumentError(
                    code: "missingHarnessMode",
                    message: "--harness 缺少取值（应为 direct/corelocation/resume）"
                )
            )
        }
        guard let mode = HarnessMode(rawValue: rawMode) else {
            return .invalid(
                mode: nil,
                statusURL: statusURL,
                error: HarnessArgumentError(
                    code: "unknownHarnessMode",
                    message: "未知 --harness 取值 '\(rawMode)'（应为 direct/corelocation/resume）"
                )
            )
        }

        var requiredFlags = ["--status", "--checkpoint"]
        if mode == .direct {
            requiredFlags.append("--stream")
        }
        for flag in requiredFlags {
            guard let value = flags[flag], !value.isEmpty else {
                return .invalid(
                    mode: mode,
                    statusURL: statusURL,
                    error: HarnessArgumentError(
                        code: "missingArgument",
                        message: "模式 \(mode.rawValue) 缺少必需参数 \(flag)"
                    )
                )
            }
        }

        var maxDuration: TimeInterval?
        if let rawDuration = flags["--max-duration"] {
            guard let value = TimeInterval(rawDuration), value.isFinite, value > 0 else {
                return .invalid(
                    mode: mode,
                    statusURL: statusURL,
                    error: HarnessArgumentError(
                        code: "invalidMaxDuration",
                        message: "--max-duration 必须是正的有限秒数，实际 '\(rawDuration)'"
                    )
                )
            }
            maxDuration = value
        }

        return .active(
            HarnessConfiguration(
                mode: mode,
                statusURL: url(from: flags["--status"])!,
                checkpointURL: url(from: flags["--checkpoint"])!,
                streamURL: mode == .direct ? url(from: flags["--stream"]) : nil,
                maxDurationSeconds: maxDuration
            )
        )
    }

    private static func url(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rawValue)
    }
}
