import Foundation
import PurePaceRunCore

/// 直接流里的采样行（已通过 RunSample 字段校验）。
struct HarnessStreamSample: Equatable, Sendable {
    let sample: RunSample
    let accuracyMeters: Double?
}

/// 直接流事件：控制行与采样行统一顺序化。
enum HarnessStreamEvent: Equatable, Sendable {
    case start(Date)
    case pause(Date)
    case resume(Date)
    case finish(Date)
    case sample(HarnessStreamSample)
}

/// 直接流解析失败；`code` 固定为 `invalidStreamLine`，message 带行号。
struct HarnessStreamError: Error, Equatable, Sendable {
    let code: String
    let message: String
    let lineNumber: Int
}

/// JSONL 直接流解析器（纯逻辑，不做 IO）。
///
/// 契约：UTF-8、一行一个 JSON 对象、时间基准统一 epoch 秒；
/// `type` 省略视为 `sample`；空行忽略；其余解析失败抛出带行号的稳定错误。
enum HarnessStreamParser {
    static let invalidLineCode = "invalidStreamLine"

    private struct LinePayload: Decodable {
        let type: String?
        let lat: Double?
        let lon: Double?
        let timestamp: Double?
        let altitude: Double?
        let accuracy: Double?
        let heartRate: Int?
        let cadence: Int?
    }

    static func parse(line: String, lineNumber: Int) throws -> HarnessStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw error(lineNumber, "不是合法的 UTF-8 文本")
        }
        let payload: LinePayload
        do {
            payload = try JSONDecoder().decode(LinePayload.self, from: data)
        } catch {
            throw self.error(lineNumber, "不是合法的 JSON 对象或字段类型不匹配")
        }

        let type = payload.type ?? "sample"
        switch type {
        case "start", "pause", "resume", "finish":
            guard let timestamp = dateValue(payload.timestamp) else {
                throw error(lineNumber, "控制行 \(type) 缺少合法 timestamp")
            }
            switch type {
            case "start":
                return .start(timestamp)
            case "pause":
                return .pause(timestamp)
            case "resume":
                return .resume(timestamp)
            default:
                return .finish(timestamp)
            }
        case "sample":
            guard let latitude = payload.lat, let longitude = payload.lon else {
                throw error(lineNumber, "采样行缺少 lat/lon")
            }
            guard let timestamp = dateValue(payload.timestamp) else {
                throw error(lineNumber, "采样行缺少合法 timestamp")
            }
            guard let sample = RunSample(
                latitude: latitude,
                longitude: longitude,
                altitude: finite(payload.altitude),
                timestamp: timestamp,
                heartRate: payload.heartRate,
                cadence: payload.cadence
            ) else {
                throw error(lineNumber, "采样点字段不合法")
            }
            return .sample(HarnessStreamSample(sample: sample, accuracyMeters: finite(payload.accuracy)))
        default:
            throw error(lineNumber, "未知 type '\(type)'")
        }
    }

    private static func error(_ lineNumber: Int, _ message: String) -> HarnessStreamError {
        HarnessStreamError(
            code: invalidLineCode,
            message: "第 \(lineNumber) 行: \(message)",
            lineNumber: lineNumber
        )
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }
        return value
    }

    private static func dateValue(_ seconds: Double?) -> Date? {
        guard let seconds, seconds.isFinite else {
            return nil
        }
        let date = Date(timeIntervalSince1970: seconds)
        guard date != .distantPast, date != .distantFuture else {
            return nil
        }
        return date
    }
}
