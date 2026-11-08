import Foundation
import PurePaceRunCore

/// App 沙盒内的真实存储位置：归档目录、checkpoint 文件与 GPX 导出目录
/// 一律由 `FileManager` 构造，不写死绝对路径；可注入 `FileManager` 供测试指向临时目录。
enum RunStorage {
    static func documentsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    /// App 沙盒 `Documents/Exports/`，GPX 导出唯一落点。
    static func exportDirectory(fileManager: FileManager = .default) -> URL {
        documentsDirectory(fileManager: fileManager)
            .appendingPathComponent("Exports", isDirectory: true)
    }

    static func makeExporter(fileManager: FileManager = .default) -> RunGPXExporter {
        RunGPXExporter(directoryURL: exportDirectory(fileManager: fileManager))
    }

    static func makeStores(
        fileManager: FileManager = .default
    ) -> (checkpoint: RunCheckpointStore, archive: RunArchiveStore, exporter: RunGPXExporter) {
        let documents = documentsDirectory(fileManager: fileManager)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let archiveDirectory = documents.appendingPathComponent("Runs", isDirectory: true)
        let checkpointURL = caches.appendingPathComponent("active-run.jsonl")
        return (
            checkpoint: RunCheckpointStore(fileURL: checkpointURL),
            archive: RunArchiveStore(directoryURL: archiveDirectory),
            exporter: RunGPXExporter(directoryURL: exportDirectory(fileManager: fileManager))
        )
    }
}
