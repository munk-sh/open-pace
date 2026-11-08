import Foundation

/// 把已归档跑次写成真实 GPX 1.1 文件；复用 `GPXCodec`，不重造编码器。
public struct RunGPXExporter: Sendable {
    /// 导出目录；由调用方给出。
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// 由记录的归档采样构建轨迹并落盘，返回最终 `.gpx` 文件 URL。
    ///
    /// 采样为空时抛 `RunArchiveError.emptySamples` 且不落文件；目标已存在时追加递增后缀。
    @discardableResult
    public func export(_ record: RunRecord) throws -> URL {
        guard !record.samples.isEmpty else {
            throw RunArchiveError.emptySamples
        }
        let stem = RunRecordNaming.stem(for: record)
        guard let track = GPXTrack(
            name: "PurePace Run \(stem)",
            createdAt: record.startedAt,
            activityType: "running",
            points: record.samples
        ) else {
            throw RunArchiveError.invalidRecord("采样点无法构建 GPX 轨迹")
        }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RunArchiveError.ioFailure("无法创建导出目录: \(error.localizedDescription)")
        }
        let target = RunRecordNaming.uniqueURL(
            in: directoryURL,
            stem: stem,
            pathExtension: "gpx"
        )
        do {
            try GPXCodec.write(track, to: target)
        } catch let error as GPXCodecError {
            throw RunArchiveError.ioFailure(error.description)
        }
        return target
    }
}
