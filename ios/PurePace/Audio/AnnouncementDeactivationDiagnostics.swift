import Foundation
import PurePaceRunCore

/// 一次播报结束的会话停用结果（成功路径不落盘，仅用于统一入口）。
enum AnnouncementDeactivationOutcome {
    case success
    case notApplicable(
        splitIndex: Int,
        occurredAt: Date,
        coordinatorStateBefore: AudioSessionState,
        coordinatorStateAfter: AudioSessionState
    )
    case failed(
        splitIndex: Int,
        occurredAt: Date,
        error: Error,
        coordinatorStateBefore: AudioSessionState,
        coordinatorStateAfter: AudioSessionState,
        platformCallIssued: Bool
    )
}

/// 停用诊断记录的写入接缝；生产实现写 App 容器内固定路径，测试可注入临时目录。
protocol AnnouncementDeactivationDiagnosing: AnyObject {
    func record(_ outcome: AnnouncementDeactivationOutcome)
}

/// 生产实现：把非成功结果追加写入 `Documents/Diagnostics/announcement-deactivation.json`。
///
/// 固定路径可由 `xcrun devicectl device copy from --domain-type appDataContainer
/// --source Documents/Diagnostics/announcement-deactivation.json` 拉取。
/// 追加保留历史、`NSLock` 串行、`Data.write(options: .atomic)` 原子替换；
/// 读旧文件失败或写盘失败一律吞掉，绝不打断播报路径。
final class AnnouncementDeactivationDiagnosticsFile: AnnouncementDeactivationDiagnosing {
    static let relativePath = "Diagnostics/announcement-deactivation.json"

    private struct Document: Codable {
        let version: Int
        var outcomes: [Entry]
    }

    private struct Entry: Codable {
        let splitIndex: Int
        let occurredAt: Double
        let outcome: String
        let errorDomain: String?
        let errorCode: Int?
        let coordinatorStateBefore: String
        let coordinatorStateAfter: String
        let platformCallIssued: Bool
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    /// `directoryURL` 为注入的基目录（生产默认为 App 的 Documents 目录）。
    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let base = directoryURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.fileURL = base.appendingPathComponent(Self.relativePath, isDirectory: false)
        self.fileManager = fileManager
    }

    func record(_ outcome: AnnouncementDeactivationOutcome) {
        guard let entry = Self.entry(for: outcome) else { return }
        lock.lock()
        defer { lock.unlock() }

        var document = loadDocument()
        document.outcomes.append(entry)

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(document).write(to: fileURL, options: .atomic)
        } catch {
            // 诊断写盘失败不得打断播报；成功证据不依赖本地日志。
        }
    }

    private static func entry(for outcome: AnnouncementDeactivationOutcome) -> Entry? {
        switch outcome {
        case .success:
            return nil
        case let .notApplicable(splitIndex, occurredAt, stateBefore, stateAfter):
            return Entry(
                splitIndex: splitIndex,
                occurredAt: occurredAt.timeIntervalSince1970,
                outcome: "not-applicable",
                errorDomain: nil,
                errorCode: nil,
                coordinatorStateBefore: stateBefore.rawValue,
                coordinatorStateAfter: stateAfter.rawValue,
                platformCallIssued: false
            )
        case let .failed(splitIndex, occurredAt, error, stateBefore, stateAfter, platformCallIssued):
            let nsError = error as NSError
            return Entry(
                splitIndex: splitIndex,
                occurredAt: occurredAt.timeIntervalSince1970,
                outcome: "failed",
                errorDomain: nsError.domain,
                errorCode: nsError.code,
                coordinatorStateBefore: stateBefore.rawValue,
                coordinatorStateAfter: stateAfter.rawValue,
                platformCallIssued: platformCallIssued
            )
        }
    }

    /// 读旧文件：不存在或解析失败都重置为空，不向上抛错。
    private func loadDocument() -> Document {
        guard
            let data = try? Data(contentsOf: fileURL),
            let document = try? JSONDecoder().decode(Document.self, from: data)
        else {
            return Document(version: 1, outcomes: [])
        }
        return document
    }
}
