import Foundation
import PurePaceRunCore

/// App 沙盒内的真实存储位置：归档目录与 checkpoint 文件由 `FileManager` 构造，不写死绝对路径。
enum RunStorage {
    static func makeStores(fileManager: FileManager = .default) -> (checkpoint: RunCheckpointStore, archive: RunArchiveStore) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let archiveDirectory = documents.appendingPathComponent("Runs", isDirectory: true)
        let checkpointURL = caches.appendingPathComponent("active-run.jsonl")
        return (
            checkpoint: RunCheckpointStore(fileURL: checkpointURL),
            archive: RunArchiveStore(directoryURL: archiveDirectory)
        )
    }
}
