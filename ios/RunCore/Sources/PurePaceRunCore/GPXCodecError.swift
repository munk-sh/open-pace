import Foundation

/// GPX 编解码与文件 IO 的失败原因。与 `RunCoreError` 保持独立，互不影响。
public enum GPXCodecError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidDocument(String)
    case missingTrack(String)
    case unsupportedNamespace(String)
    case invalidPoint(index: Int, reason: String)
    case ioFailure(String)

    public var description: String {
        switch self {
        case .invalidDocument(let detail):
            return "invalid GPX document: \(detail)"
        case .missingTrack(let detail):
            return "missing GPX track: \(detail)"
        case .unsupportedNamespace(let detail):
            return "unsupported GPX namespace: \(detail)"
        case .invalidPoint(let index, let reason):
            return "invalid GPX track point at index \(index): \(reason)"
        case .ioFailure(let detail):
            return "GPX IO failure: \(detail)"
        }
    }
}
