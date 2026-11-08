import Foundation

/// 跑次归档与 GPX 导出的失败原因。与 `RunCoreError`/`GPXCodecError` 保持独立。
public enum RunArchiveError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidRecord(String)
    case emptySamples
    case ioFailure(String)

    public var description: String {
        switch self {
        case .invalidRecord(let detail):
            return "invalid run record: \(detail)"
        case .emptySamples:
            return "run record has no samples to export"
        case .ioFailure(let detail):
            return "run archive IO failure: \(detail)"
        }
    }
}

/// 跑次文件命名：`<startedAt 的 UTC 紧凑时间>-<id>`，导出只换扩展名。
enum RunRecordNaming {
    static func stem(for record: RunRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "\(formatter.string(from: record.startedAt))-\(record.id.uuidString)"
    }

    /// 目标已存在时追加 `-2`、`-3`… 递增后缀，绝不覆盖。
    static func uniqueURL(in directory: URL, stem: String, pathExtension: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(stem).\(pathExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(suffix).\(pathExtension)")
            suffix += 1
        }
        return candidate
    }
}

/// 按「一次跑次一文件」落盘的归档存储。文件即真源，不内置内存缓存。
public struct RunArchiveStore: Sendable {
    /// 归档目录；由调用方给出，缺失时 `list()` 视为空且不隐式创建。
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// 保存一条记录，自动建目录并返回最终文件 URL。已存在同名目标时追加递增后缀。
    @discardableResult
    public func save(_ record: RunRecord) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            throw RunArchiveError.ioFailure("归档目录路径被同名普通文件占用")
        }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RunArchiveError.ioFailure("无法创建归档目录: \(error.localizedDescription)")
        }
        let target = RunRecordNaming.uniqueURL(
            in: directoryURL,
            stem: RunRecordNaming.stem(for: record),
            pathExtension: "json"
        )
        let temporaryURL = directoryURL.appendingPathComponent(".run-\(UUID().uuidString).tmp")
        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: target)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw RunArchiveError.ioFailure("无法写入跑次记录: \(error.localizedDescription)")
        }
        return target
    }

    /// 按 `startedAt` 降序列出全部有效记录；等值时按 `id.uuidString` 升序。
    ///
    /// 目录缺失返回空数组且不抛错；单文件解码/校验失败静默跳过；目录级 IO 失败才抛错。
    public func list() throws -> [RunRecord] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            return []
        }
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        } catch {
            throw RunArchiveError.ioFailure("无法读取归档目录: \(error.localizedDescription)")
        }
        let decoder = JSONDecoder()
        var records: [RunRecord] = []
        for entry in entries {
            guard entry.pathExtension.lowercased() == "json" else {
                continue
            }
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            guard let data = try? Data(contentsOf: entry) else {
                continue
            }
            guard let record = try? decoder.decode(RunRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }
        return records.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
