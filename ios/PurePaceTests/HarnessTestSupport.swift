import Foundation
import PurePaceRunCore

enum HarnessTestSupport {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purepace-harness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 1 度纬度对应的米数（与 GeoDistance 的球面半径口径一致）。
    static let metersPerDegreeLatitude = Double.pi / 180.0 * 6_371_000.0

    static func sample(
        latitude: Double,
        longitude: Double,
        timestamp: TimeInterval,
        altitude: Double? = nil
    ) -> RunSample? {
        RunSample(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: Date(timeIntervalSince1970: timestamp),
            heartRate: nil,
            cadence: nil
        )
    }

    static func sampleLine(
        latitude: Double,
        longitude: Double,
        timestamp: TimeInterval,
        accuracy: Double? = nil
    ) -> String {
        var line = "{\"type\":\"sample\",\"lat\":\(latitude),\"lon\":\(longitude),\"timestamp\":\(timestamp)"
        if let accuracy {
            line += ",\"accuracy\":\(accuracy)"
        }
        return line + "}"
    }

    /// 测试内现算的 1 Hz、5:00–7:00/km 正北向参考路线（不使用任何夹具）。
    static func referenceRoute(
        meters: Double,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> [(timestamp: Date, latitude: Double, longitude: Double)] {
        var points: [(timestamp: Date, latitude: Double, longitude: Double)] = []
        let latitudeOrigin = 31.0
        let longitudeOrigin = 121.0
        var traveled = 0.0
        var elapsed: TimeInterval = 0
        while traveled < meters {
            let paceSecondsPerKilometer = 360.0 + 60.0 * sin(2.0 * Double.pi * elapsed / 600.0)
            traveled += 1000.0 / paceSecondsPerKilometer
            elapsed += 1
            points.append(
                (
                    timestamp: start.addingTimeInterval(elapsed),
                    latitude: latitudeOrigin + traveled / metersPerDegreeLatitude,
                    longitude: longitudeOrigin
                )
            )
        }
        return points
    }

    /// 逐点累计的参照距离（第一条为 0）。
    static func cumulativeDistances(
        _ points: [(timestamp: Date, latitude: Double, longitude: Double)]
    ) -> [Double] {
        var distances: [Double] = [0]
        distances.reserveCapacity(points.count)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let step = GeoDistance.meters(
                latitude1: previous.latitude,
                longitude1: previous.longitude,
                latitude2: current.latitude,
                longitude2: current.longitude
            )
            distances.append(distances[index - 1] + step)
        }
        return distances
    }

    static func writeStream(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func decodeJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "HarnessTestSupport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "status 不是 JSON 对象"
            ])
        }
        return object
    }
}
