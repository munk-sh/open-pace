import Foundation
import PurePaceRunCore

private let usageText = """
用法: PurePaceGpxTool --input <path> --output <path>

读取 GPX 1.1 文件并重新写出到目标路径，供外部脚本做逐字段校验。
  --input <path>   源 GPX 文件路径
  --output <path>  目标 GPX 文件路径
  -h, --help       显示本帮助并退出 0

退出码:
  0  成功
  2  参数缺失或未知参数
  3  解析或 IO 失败
"""

private func reportError(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

private func exitWithArgumentError(_ message: String) -> Never {
    reportError(message)
    exit(2)
}

var inputPath: String?
var outputPath: String?
let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0

while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "-h", "--help":
        print(usageText)
        exit(0)
    case "--input":
        index += 1
        guard index < arguments.count else {
            exitWithArgumentError("缺少 --input 的值")
        }
        inputPath = arguments[index]
    case "--output":
        index += 1
        guard index < arguments.count else {
            exitWithArgumentError("缺少 --output 的值")
        }
        outputPath = arguments[index]
    default:
        exitWithArgumentError("未知参数 '\(argument)'")
    }
    index += 1
}

guard let inputPath, let outputPath else {
    exitWithArgumentError("缺少 --input 或 --output")
}

do {
    let track = try GPXCodec.read(from: URL(fileURLWithPath: inputPath))
    try GPXCodec.write(track, to: URL(fileURLWithPath: outputPath))
} catch {
    reportError(String(describing: error))
    exit(3)
}

exit(0)
