import Foundation

/// 写死且不随模式变化的硬阈值（与 PRD / WorkSet 口径一致）。
enum HarnessThresholdValues {
    static let distanceRelativeErrorMax: Double = 0.01
    static let paceErrorMaxSecondsPerKilometer: Double = 2.0
    static let splitBoundaryToleranceSamples: Int = 1
    static let accuracyFilterMeters: Double = 50.0
    static let checkpointEveryAcceptedSamples: Int = 10
}

struct HarnessSampleCounts: Equatable, Sendable, Encodable {
    let received: Int
    let accepted: Int
    let rejectedByAccuracy: Int
    let rejectedByFirstPoint: Int
}

struct HarnessThresholdsRecord: Equatable, Sendable, Encodable {
    let distanceRelativeErrorMax: Double
    let paceErrorMaxSecondsPerKilometer: Double
    let splitBoundaryToleranceSamples: Int
    let accuracyFilterMeters: Double
    let checkpointEveryAcceptedSamples: Int

    static let fixed = HarnessThresholdsRecord(
        distanceRelativeErrorMax: HarnessThresholdValues.distanceRelativeErrorMax,
        paceErrorMaxSecondsPerKilometer: HarnessThresholdValues.paceErrorMaxSecondsPerKilometer,
        splitBoundaryToleranceSamples: HarnessThresholdValues.splitBoundaryToleranceSamples,
        accuracyFilterMeters: HarnessThresholdValues.accuracyFilterMeters,
        checkpointEveryAcceptedSamples: HarnessThresholdValues.checkpointEveryAcceptedSamples
    )
}

/// `rawSamples[]` 元素：与输入按接收顺序一一对应。
struct HarnessRawSampleRecord: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Double
    let accepted: Bool
    let accuracyMeters: Double?
    let rejectedReason: String?
}

struct HarnessSplitRecord: Equatable, Sendable {
    let index: Int
    let distanceMeters: Double
    let durationSeconds: Double
    let paceSecondsPerKilometer: Double?
}

struct HarnessAnnouncementRecord: Equatable, Sendable, Encodable {
    let trigger: String
    let splitIndex: Int
    let distanceMeters: Double
    let paceSecondsPerKilometer: Double
    let elapsedSeconds: Double
}

struct HarnessActualRecord: Equatable, Sendable {
    let distanceMeters: Double
    let elapsedSeconds: Double
    let averagePaceSecondsPerKilometer: Double?
    let currentPaceSecondsPerKilometer: Double?
    let completedKilometers: Int
    let splitCount: Int
    let splitSampleIndexes: [Int]

    static let empty = HarnessActualRecord(
        distanceMeters: 0,
        elapsedSeconds: 0,
        averagePaceSecondsPerKilometer: nil,
        currentPaceSecondsPerKilometer: nil,
        completedKilometers: 0,
        splitCount: 0,
        splitSampleIndexes: []
    )
}

/// resume 模式的恢复事实；`announcedSplitIndex` 已按 `?? splits.count` 归一。
struct HarnessRestoredSnapshot: Equatable, Sendable, Encodable {
    let checkpointPath: String
    let completedDistanceMeters: Double
    let elapsedSeconds: Double
    let splitCount: Int
    let announcedSplitIndex: Int
}

struct HarnessStatusError: Equatable, Sendable, Encodable {
    let code: String
    let message: String
}

/// 唯一对外可观测面：稳定机读 status 文档。
struct HarnessStatus: Equatable, Sendable {
    let schemaVersion: Int
    let mode: String?
    let state: String?
    let startedAt: Double?
    let updatedAt: Double
    let finishedAt: Double?
    let resumed: Bool
    let restored: HarnessRestoredSnapshot?
    let rawSamples: [HarnessRawSampleRecord]
    let sampleCounts: HarnessSampleCounts
    let actual: HarnessActualRecord
    let thresholds: HarnessThresholdsRecord
    let splits: [HarnessSplitRecord]
    let announcements: [HarnessAnnouncementRecord]
    let error: HarnessStatusError?
    let locationAuthorization: String?
    let includesLocationAuthorization: Bool

    static func failure(
        mode: String?,
        error: HarnessStatusError,
        now: Date = Date()
    ) -> HarnessStatus {
        HarnessStatus(
            schemaVersion: 1,
            mode: mode,
            state: nil,
            startedAt: nil,
            updatedAt: now.timeIntervalSince1970,
            finishedAt: nil,
            resumed: false,
            restored: nil,
            rawSamples: [],
            sampleCounts: HarnessSampleCounts(
                received: 0,
                accepted: 0,
                rejectedByAccuracy: 0,
                rejectedByFirstPoint: 0
            ),
            actual: .empty,
            thresholds: .fixed,
            splits: [],
            announcements: [],
            error: error,
            locationAuthorization: nil,
            includesLocationAuthorization: mode == HarnessMode.corelocation.rawValue
        )
    }
}

// MARK: - Encodable（显式写出 null，保证契约键始终存在）

private extension KeyedEncodingContainer {
    mutating func encodeHarness<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

extension HarnessStatus: Encodable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case state
        case startedAt
        case updatedAt
        case finishedAt
        case resumed
        case restored
        case rawSamples
        case sampleCounts
        case actual
        case thresholds
        case splits
        case announcements
        case error
        case locationAuthorization
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeHarness(mode, forKey: .mode)
        try container.encodeHarness(state, forKey: .state)
        try container.encodeHarness(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeHarness(finishedAt, forKey: .finishedAt)
        try container.encode(resumed, forKey: .resumed)
        try container.encodeHarness(restored, forKey: .restored)
        try container.encode(rawSamples, forKey: .rawSamples)
        try container.encode(sampleCounts, forKey: .sampleCounts)
        try container.encode(actual, forKey: .actual)
        try container.encode(thresholds, forKey: .thresholds)
        try container.encode(splits, forKey: .splits)
        try container.encode(announcements, forKey: .announcements)
        try container.encodeHarness(error, forKey: .error)
        if includesLocationAuthorization {
            try container.encodeHarness(locationAuthorization, forKey: .locationAuthorization)
        }
    }
}

extension HarnessRawSampleRecord: Encodable {
    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case timestamp
        case accepted
        case accuracyMeters
        case rejectedReason
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(accepted, forKey: .accepted)
        try container.encodeHarness(accuracyMeters, forKey: .accuracyMeters)
        try container.encodeHarness(rejectedReason, forKey: .rejectedReason)
    }
}

extension HarnessSplitRecord: Encodable {
    private enum CodingKeys: String, CodingKey {
        case index
        case distanceMeters
        case durationSeconds
        case paceSecondsPerKilometer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encodeHarness(paceSecondsPerKilometer, forKey: .paceSecondsPerKilometer)
    }
}

extension HarnessActualRecord: Encodable {
    private enum CodingKeys: String, CodingKey {
        case distanceMeters
        case elapsedSeconds
        case averagePaceSecondsPerKilometer
        case currentPaceSecondsPerKilometer
        case completedKilometers
        case splitCount
        case splitSampleIndexes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encodeHarness(averagePaceSecondsPerKilometer, forKey: .averagePaceSecondsPerKilometer)
        try container.encodeHarness(currentPaceSecondsPerKilometer, forKey: .currentPaceSecondsPerKilometer)
        try container.encode(completedKilometers, forKey: .completedKilometers)
        try container.encode(splitCount, forKey: .splitCount)
        try container.encode(splitSampleIndexes, forKey: .splitSampleIndexes)
    }
}

// MARK: - 原子 writer

enum HarnessStatusWriter {
    static func encode(_ status: HarnessStatus) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(status)
    }

    /// 同目录临时文件写入后原子替换目标文件，读侧永远看不到半截 JSON。
    static func write(_ status: HarnessStatus, to url: URL) throws {
        let data = try encode(status)
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }
}
