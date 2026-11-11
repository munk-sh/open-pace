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

/// 历史列表用的轻量索引项：不包含 `samples`，列表页据此成行，无需解码轨迹。
public struct RunRecordSummary: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let distance: RunDistance
    public let activeDuration: TimeInterval
    /// 归档里是否有非空轨迹（只做存在性判断，不解码坐标）。
    public let hasTrack: Bool

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        distance: RunDistance,
        activeDuration: TimeInterval,
        hasTrack: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distance = distance
        self.activeDuration = activeDuration
        self.hasTrack = hasTrack
    }

    /// 由完整记录派生索引项（截图 fixture / 已解码记录复用）。
    public init(record: RunRecord) {
        self.init(
            id: record.id,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            distance: record.distance,
            activeDuration: record.activeDuration,
            hasTrack: !record.samples.isEmpty
        )
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

    /// 历史列表用的轻量索引：只读文件头部元数据，绝不解码 `samples`。
    ///
    /// 排序与坏文件跳过语义与 `list()` 一致：`startedAt` 降序、等值按 `id.uuidString` 升序。
    /// 采样数组超大或畸形都不影响成行（这正是索引存在的原因）。
    public func listSummaries() throws -> [RunRecordSummary] {
        let entries = try archiveFiles()
        var summaries: [RunRecordSummary] = []
        for entry in entries {
            guard let summary = Self.summary(of: entry) else {
                continue
            }
            summaries.append(summary)
        }
        return summaries.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// 按 id 读取单条完整记录（详情页 / 导出用）；找不到返回 nil。
    public func record(withID id: UUID) throws -> RunRecord? {
        let entries = try archiveFiles()
        let decoder = JSONDecoder()
        for entry in entries where entry.deletingPathExtension().lastPathComponent.hasSuffix(id.uuidString) {
            guard let data = try? Data(contentsOf: entry),
                  let record = try? decoder.decode(RunRecord.self, from: data)
            else {
                continue
            }
            return record
        }
        return nil
    }

    // MARK: - 索引内部实现

    /// 目录内所有 `.json` 常规文件；目录缺失/非目录一律返回空且不隐式创建。
    private func archiveFiles() throws -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
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
        return entries.filter { entry in
            guard entry.pathExtension.lowercased() == "json" else { return false }
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
    }

    private struct SummaryPayload: Decodable {
        let formatVersion: Int
        let id: String
        let startedAt: Double
        let endedAt: Double
        let distance: Double
        let activeDuration: TimeInterval
        let splits: [SplitPayload]

        struct SplitPayload: Decodable {
            let index: Int
            let distance: Double
            let duration: TimeInterval
        }
    }

    /// 从归档 JSON 中剔除 `samples` 键值后解码索引字段：只搬运字节，从不构造 `RunSample`。
    private static let samplesKey = Data("\"samples\"".utf8)

    private static func summary(of url: URL) -> RunRecordSummary? {
        guard let data = try? Data(contentsOf: url),
              let stripped = strippingSamples(from: data)
        else {
            return nil
        }
        guard let payload = try? JSONDecoder().decode(SummaryPayload.self, from: stripped.data) else {
            return nil
        }
        guard payload.formatVersion == RunRecord.currentFormatVersion else { return nil }
        guard let id = UUID(uuidString: payload.id) else { return nil }
        let startedAt = Date(timeIntervalSince1970: payload.startedAt)
        let endedAt = Date(timeIntervalSince1970: payload.endedAt)
        guard payload.startedAt.isFinite, payload.endedAt.isFinite, endedAt >= startedAt else { return nil }
        guard let distance = RunDistance(meters: payload.distance) else { return nil }
        guard payload.activeDuration.isFinite, payload.activeDuration >= 0 else { return nil }
        var splits: [RunSplit] = []
        for split in payload.splits {
            guard let splitDistance = RunDistance(meters: split.distance),
                  let valid = RunSplit(index: split.index, distance: splitDistance, duration: split.duration)
            else {
                return nil
            }
            splits.append(valid)
        }
        guard RunCheckpoint.hasContiguousSplitIndices(splits) else { return nil }
        return RunRecordSummary(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            distance: distance,
            activeDuration: payload.activeDuration,
            hasTrack: stripped.hasTrack
        )
    }

    private static func strippingSamples(from data: Data) -> (data: Data, hasTrack: Bool)? {
        guard let keyRange = data.range(of: samplesKey) else { return nil }
        var cursor = keyRange.upperBound
        while cursor < data.endIndex, isWhitespace(data[cursor]) { cursor += 1 }
        guard cursor < data.endIndex, data[cursor] == UInt8(ascii: ":") else { return nil }
        cursor += 1
        while cursor < data.endIndex, isWhitespace(data[cursor]) { cursor += 1 }
        guard cursor < data.endIndex else { return nil }

        var hasTrack = true
        let valueStart = cursor
        let valueEnd: Data.Index
        switch data[cursor] {
        case UInt8(ascii: "["):
            var look = cursor + 1
            while look < data.endIndex, isWhitespace(data[look]) { look += 1 }
            hasTrack = look < data.endIndex && data[look] != UInt8(ascii: "]")
            var depth = 0
            var scan = cursor
            while scan < data.endIndex {
                let byte = data[scan]
                if byte == UInt8(ascii: "[") { depth += 1 }
                if byte == UInt8(ascii: "]") {
                    depth -= 1
                    if depth == 0 { break }
                }
                scan += 1
            }
            guard scan < data.endIndex else { return nil }
            valueEnd = scan + 1
        case UInt8(ascii: "\""):
            var scan = cursor + 1
            var escaped = false
            while scan < data.endIndex {
                let byte = data[scan]
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { break }
                scan += 1
            }
            guard scan < data.endIndex else { return nil }
            valueEnd = scan + 1
        default:
            var scan = cursor
            while scan < data.endIndex,
                  data[scan] != UInt8(ascii: ","),
                  data[scan] != UInt8(ascii: "}") {
                scan += 1
            }
            valueEnd = scan
        }

        var removeStart = min(keyRange.lowerBound, valueStart)
        var removeEnd = valueEnd
        if removeEnd < data.endIndex, data[removeEnd] == UInt8(ascii: ",") {
            removeEnd += 1
        } else if removeStart > data.startIndex, data[removeStart - 1] == UInt8(ascii: ",") {
            removeStart -= 1
        }
        var stripped = Data()
        stripped.append(data[data.startIndex..<removeStart])
        stripped.append(data[removeEnd...])
        return (stripped, hasTrack)
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }
}
