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

    /// App 沙盒 `Documents/Runs/`，跑次归档唯一落点。
    static func archiveDirectory(fileManager: FileManager = .default) -> URL {
        documentsDirectory(fileManager: fileManager)
            .appendingPathComponent("Runs", isDirectory: true)
    }

#if DEBUG
    /// 仅 DEBUG 且显式传 `-uiTestResetArchive` 时清空归档与导出目录，保证 UI 用例容器隔离。
    static func resetArchiveIfRequested(
        arguments: [String] = CommandLine.arguments,
        fileManager: FileManager = .default
    ) {
        guard arguments.contains("-uiTestResetArchive") else { return }
        try? fileManager.removeItem(at: archiveDirectory(fileManager: fileManager))
        try? fileManager.removeItem(at: exportDirectory(fileManager: fileManager))
    }
#endif

    static func makeExporter(fileManager: FileManager = .default) -> RunGPXExporter {
        RunGPXExporter(directoryURL: exportDirectory(fileManager: fileManager))
    }

    static func makeStores(
        fileManager: FileManager = .default
    ) -> (checkpoint: RunCheckpointStore, archive: RunArchiveStore, exporter: RunGPXExporter) {
        let documents = documentsDirectory(fileManager: fileManager)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let runsURL = archiveDirectory(fileManager: fileManager)
        let checkpointURL = caches.appendingPathComponent("active-run.jsonl")
        return (
            checkpoint: RunCheckpointStore(fileURL: checkpointURL),
            archive: RunArchiveStore(directoryURL: runsURL),
            exporter: RunGPXExporter(directoryURL: exportDirectory(fileManager: fileManager))
        )
    }
}
