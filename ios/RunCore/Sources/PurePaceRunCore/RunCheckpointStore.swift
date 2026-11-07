import Foundation

/// 基于真实文件的 JSONL checkpoint 存储（一行一个 JSON、UTF-8、以 `\n` 结尾）。
///
/// 文件即真源：不缓存、不重写历史行。每次 `append` 独立打开/关闭文件句柄，
/// 返回后磁盘内容可被新的 store 实例读到。
public struct RunCheckpointStore: Sendable {
    /// 落盘文件位置。
    public let fileURL: URL

    private static let newline: UInt8 = 0x0A

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 追加一条 checkpoint。父目录不存在时自动创建。
    public func append(_ checkpoint: RunCheckpoint) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
        var line = try JSONEncoder().encode(checkpoint)
        line.append(RunCheckpointStore.newline)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// 按写入顺序返回全部有效记录。文件缺失视为空数组。
    ///
    /// 尾行不完整或非法时静默丢弃；非尾行损坏抛出 `RunCoreError.corruptedCheckpoint`。
    public func loadAll() throws -> [RunCheckpoint] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw RunCoreError.corruptedCheckpoint("无法读取 checkpoint 文件: \(error.localizedDescription)")
        }
        guard !data.isEmpty else {
            return []
        }

        let endsWithNewline = data.last == RunCheckpointStore.newline
        var segments = data.split(separator: RunCheckpointStore.newline, omittingEmptySubsequences: false).map { Data($0) }
        if endsWithNewline {
            // 结尾换行产生的空片段不是记录。
            segments.removeLast()
        }
        let truncatedTail = !endsWithNewline

        let decoder = JSONDecoder()
        var checkpoints: [RunCheckpoint] = []
        checkpoints.reserveCapacity(segments.count)
        for (offset, lineData) in segments.enumerated() {
            let isTail = offset == segments.count - 1
            if isTail && truncatedTail {
                // 无结尾换行的末行视为部分写入，静默丢弃。
                continue
            }
            do {
                let checkpoint = try decoder.decode(RunCheckpoint.self, from: lineData)
                checkpoints.append(checkpoint)
            } catch {
                if isTail {
                    // 末行是合法行但内容非法，按尾行丢弃处理。
                    continue
                }
                throw RunCoreError.corruptedCheckpoint("第 \(offset + 1) 行无法解码: \(error.localizedDescription)")
            }
        }
        return checkpoints
    }

    /// 返回最后一条有效记录；文件缺失或没有有效记录时为 `nil`。
    public func loadLatest() throws -> RunCheckpoint? {
        try loadAll().last
    }

    /// 删除落盘文件；文件不存在时同样成功（幂等）。
    public func reset() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }
}
