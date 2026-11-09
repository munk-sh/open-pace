import Foundation
import PurePaceRunCore

/// 采样来源：真实定位链路为 `device`，`-uiTestLocation` 确定性源为 `simulated`。
enum RunSampleSource: String, Codable, Sendable, Equatable {
    case device
    case simulated
}

/// 授权/精度状态的可序列化快照：字面量名称 + 平台原始值。
struct RunTelemetryAuthorization: Codable, Equatable, Sendable {
    let name: String
    let rawValue: Int
}

/// 单条每公里播报的音频自证记录。
///
/// 只承载「机器可断言」的事实：播报时刻下发的会话配置、两个音频环境布尔、
/// 起止时间与结束/duck 撤销记录。`finishedAt` 为 nil 表示会话结束时该次播报尚未回调完成。
struct RunTelemetryAnnouncement: Codable, Equatable, Sendable {
    let splitIndex: Int
    let text: String
    let startedAt: TimeInterval
    let finishedAt: TimeInterval?
    let cancelled: Bool
    let category: String
    let mode: String
    let categoryOptions: [String]
    let isOtherAudioPlaying: Bool
    let secondaryAudioShouldBeSilencedHint: Bool
    let sessionActivated: Bool
    let sessionDeactivated: Bool
    let duckRevoked: Bool

    private enum CodingKeys: String, CodingKey {
        case splitIndex
        case text
        case startedAt
        case finishedAt
        case cancelled
        case category
        case mode
        case categoryOptions
        case isOtherAudioPlaying
        case secondaryAudioShouldBeSilencedHint
        case sessionActivated
        case sessionDeactivated
        case duckRevoked
    }

    /// 手写编码：`finishedAt` 即使为 nil 也写成 `null`，保证键始终存在（类型正确）。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(splitIndex, forKey: .splitIndex)
        try container.encode(text, forKey: .text)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(finishedAt, forKey: .finishedAt)
        try container.encode(cancelled, forKey: .cancelled)
        try container.encode(category, forKey: .category)
        try container.encode(mode, forKey: .mode)
        try container.encode(categoryOptions, forKey: .categoryOptions)
        try container.encode(isOtherAudioPlaying, forKey: .isOtherAudioPlaying)
        try container.encode(
            secondaryAudioShouldBeSilencedHint,
            forKey: .secondaryAudioShouldBeSilencedHint
        )
        try container.encode(sessionActivated, forKey: .sessionActivated)
        try container.encode(sessionDeactivated, forKey: .sessionDeactivated)
        try container.encode(duckRevoked, forKey: .duckRevoked)
    }

    init(
        splitIndex: Int,
        text: String,
        startedAt: TimeInterval,
        finishedAt: TimeInterval?,
        cancelled: Bool,
        category: String,
        mode: String,
        categoryOptions: [String],
        isOtherAudioPlaying: Bool,
        secondaryAudioShouldBeSilencedHint: Bool,
        sessionActivated: Bool,
        sessionDeactivated: Bool,
        duckRevoked: Bool
    ) {
        self.splitIndex = splitIndex
        self.text = text
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.cancelled = cancelled
        self.category = category
        self.mode = mode
        self.categoryOptions = categoryOptions
        self.isOtherAudioPlaying = isOtherAudioPlaying
        self.secondaryAudioShouldBeSilencedHint = secondaryAudioShouldBeSilencedHint
        self.sessionActivated = sessionActivated
        self.sessionDeactivated = sessionDeactivated
        self.duckRevoked = duckRevoked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        splitIndex = try container.decode(Int.self, forKey: .splitIndex)
        text = try container.decode(String.self, forKey: .text)
        startedAt = try container.decode(TimeInterval.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .finishedAt)
        cancelled = try container.decode(Bool.self, forKey: .cancelled)
        category = try container.decode(String.self, forKey: .category)
        mode = try container.decode(String.self, forKey: .mode)
        categoryOptions = try container.decode([String].self, forKey: .categoryOptions)
        isOtherAudioPlaying = try container.decode(Bool.self, forKey: .isOtherAudioPlaying)
        secondaryAudioShouldBeSilencedHint = try container.decode(
            Bool.self,
            forKey: .secondaryAudioShouldBeSilencedHint
        )
        sessionActivated = try container.decode(Bool.self, forKey: .sessionActivated)
        sessionDeactivated = try container.decode(Bool.self, forKey: .sessionDeactivated)
        duckRevoked = try container.decode(Bool.self, forKey: .duckRevoked)
    }
}

/// 内嵌进单条跑次 JSON 的 additive 遥测对象。
struct RunTelemetry: Codable, Equatable, Sendable {
    let authorizationStatus: RunTelemetryAuthorization
    let accuracyAuthorization: RunTelemetryAuthorization
    let allowsBackgroundLocationUpdates: Bool
    let pausesLocationUpdatesAutomatically: Bool
    let announcements: [RunTelemetryAnnouncement]
}

/// 遥测写回接缝，便于在测试中注入桩以断言注入参数。
protocol RunTelemetryWriting: Sendable {
    /// 把遥测注入到按 `recordID` 匹配的既有跑次 JSON；只新增 `telemetry` 与 `samples[].source`。
    func inject(
        telemetry: RunTelemetry,
        sources: [TimeInterval: RunSampleSource],
        recordID: UUID,
        defaultSource: RunSampleSource
    ) throws
}

/// additive 遥测写回：读 `RunArchiveStore` 已落盘的 JSON → 仅新增两个键 → 原子替换。
///
/// 目标文件按解码出的 `RunRecord.id` 匹配，不复制文件名规则，也不触碰其它旧记录。
struct RunTelemetryWriter: RunTelemetryWriting {
    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func inject(
        telemetry: RunTelemetry,
        sources: [TimeInterval: RunSampleSource],
        recordID: UUID,
        defaultSource: RunSampleSource
    ) throws {
        let fileManager = FileManager.default
        guard let target = try locate(recordID: recordID, fileManager: fileManager) else {
            return
        }
        let data = try Data(contentsOf: target)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let encoder = JSONEncoder()
        let telemetryData = try encoder.encode(telemetry)
        root["telemetry"] = try JSONSerialization.jsonObject(with: telemetryData)

        if var samples = root["samples"] as? [[String: Any]] {
            for index in samples.indices where samples[index]["timestamp"] != nil {
                let timestamp = (samples[index]["timestamp"] as? NSNumber)?.doubleValue
                let source = timestamp.flatMap { sources[$0] } ?? defaultSource
                samples[index]["source"] = source.rawValue
            }
            root["samples"] = samples
        }

        let output = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let temporaryURL = directoryURL.appendingPathComponent(".run-\(UUID().uuidString).telemetry.tmp")
        try output.write(to: temporaryURL)
        _ = try fileManager.replaceItemAt(target, withItemAt: temporaryURL)
    }

    private func locate(recordID: UUID, fileManager: FileManager) throws -> URL? {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        } catch {
            return nil
        }
        let decoder = JSONDecoder()
        for entry in entries where entry.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let record = try? decoder.decode(RunRecord.self, from: data),
                  record.id == recordID
            else {
                continue
            }
            return entry
        }
        return nil
    }
}
