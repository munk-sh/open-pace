import Foundation
import PurePaceRunCore

/// 详情页导出状态与动作：只调用 `RunGPXExporter` 把真实归档采样写入 `.gpx`，
/// 并在更新界面前核对目标文件真实存在且非空；不拼 GPX 内容、不读样例、不联网。
struct RunExportState: Equatable {
    enum Phase: Equatable {
        case idle
        case exported(URL)
        case failed
    }

    private(set) var phase: Phase = .idle

    /// 执行一次导出；失败时停留在失败态，不产生分享入口。
    mutating func export(
        _ record: RunRecord,
        using exporter: RunGPXExporter,
        fileManager: FileManager = .default
    ) {
        do {
            let url = try exporter.export(record)
            guard Self.isLandedGPXFile(url, fileManager: fileManager) else {
                phase = .failed
                return
            }
            phase = .exported(url)
        } catch {
            phase = .failed
        }
    }

    /// 落盘判定：扩展名为 `.gpx` 且文件真实存在、字节数 > 0。
    static func isLandedGPXFile(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.pathExtension == "gpx" else { return false }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return false
        }
        guard let size = attributes[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }
}
