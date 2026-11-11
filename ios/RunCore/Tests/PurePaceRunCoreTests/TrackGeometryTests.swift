import XCTest
import PurePaceRunCore

/// 轨迹渲染纯逻辑：>60s 断线分段、ε=3m 的 RDP 抽稀、8–12% padding 相机包围盒。
final class TrackGeometryTests: XCTestCase {
    // MARK: - ac-map-break-segments

    func testSegmentSplitAtSixtySecondsBoundary() {
        // 59s 间隔不能断线。
        let close = samples(at: [0, 59, 118])
        XCTAssertEqual(TrackGeometry.segments(from: close).count, 1, "≤60s 间隔不得断线")

        // 61s 间隔必须断线（严格大于 60）。
        let split = samples(at: [0, 61])
        XCTAssertEqual(TrackGeometry.segments(from: split).count, 2, ">60s 必须切成两段")

        // 跨 3 段夹具：0 / 30 / 61 / 130（61 与 130 两处 >60s）。
        let three = samples(at: [0, 30, 100, 170])
        XCTAssertEqual(TrackGeometry.segments(from: three).count, 3, "跨 3 段夹具必须输出 3 段")
    }

    func testSegmentsPreserveOriginalCoordinates() {
        let samples = samples(at: [0, 90])
        let segments = TrackGeometry.segments(from: samples)
        XCTAssertEqual(segments[0], [TrackCoordinate(latitude: 31.0, longitude: 121.0)])
        XCTAssertEqual(segments[1], [TrackCoordinate(latitude: 31.0, longitude: 121.0)])
    }

    func testEmptySamplesProduceNoSegments() {
        XCTAssertEqual(TrackGeometry.segments(from: []).count, 0)
        XCTAssertEqual(TrackGeometry.renderSegments(from: []).count, 0)
    }

    // MARK: - ac-map-rdp-render-only

    func testSimplificationKeepsEveryPointWithinThreeMeters() {
        // 固定夹具：一条 30m 直线轨迹，中点分别偏移 1m（应被抽掉）与 8m（应保留）。
        let latitude = 31.0
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(latitude * .pi / 180)
        var samples: [RunSample] = []
        // 沿经度每 10m 一个点，共 4 个（30m）。
        for index in 0...3 {
            let offsetMeters = Double(index) * 10
            samples.append(makeSample(
                latitude: latitude,
                longitude: 121.0 + offsetMeters / metersPerDegreeLongitude,
                seconds: Double(index) * 10
            ))
        }
        // 在 10m 处加两个纬度偏移点：1m 与 8m。
        samples.insert(makeSample(latitude: latitude + 1 / metersPerDegreeLatitude, longitude: 121.0 + 10 / metersPerDegreeLongitude, seconds: 5), at: 1)
        samples.insert(makeSample(latitude: latitude + 8 / metersPerDegreeLatitude, longitude: 121.0 + 20 / metersPerDegreeLongitude, seconds: 15), at: 3)
        samples.sort { $0.timestamp < $1.timestamp }

        let simplified = TrackGeometry.simplify(
            samples.map { TrackCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        )
        XCTAssertLessThan(simplified.count, samples.count, "抽稀必须真的减少点数")
        XCTAssertLessThanOrEqual(maxDeviation(from: samples, to: simplified), 3.0, "每点最大偏差必须 <3m")
    }

    func testSimplificationLeavesShortSegmentsUntouched() {
        let two = [TrackCoordinate(latitude: 31, longitude: 121), TrackCoordinate(latitude: 31.001, longitude: 121.001)]
        XCTAssertEqual(TrackGeometry.simplify(two), two)
    }

    // MARK: - ac-map-camera-fit

    func testCameraPaddingAcceptsEightToTwelvePercentOnly() {
        let points = [
            TrackCoordinate(latitude: 31.0, longitude: 121.0),
            TrackCoordinate(latitude: 31.001, longitude: 121.001)
        ]
        for ratio in [0.08, 0.10, 0.12] {
            XCTAssertNotNil(TrackGeometry.cameraBox(for: points, paddingRatio: ratio), "\(ratio) 必须合法")
        }
        XCTAssertNil(TrackGeometry.cameraBox(for: points, paddingRatio: 0.07), "7% 必须判红")
        XCTAssertNil(TrackGeometry.cameraBox(for: points, paddingRatio: 0.13), "13% 必须判红")
    }

    func testCameraBoxExpandsByPaddingOnEverySide() {
        let points = [
            TrackCoordinate(latitude: 31.0, longitude: 121.0),
            TrackCoordinate(latitude: 31.001, longitude: 121.001)
        ]
        guard let box = TrackGeometry.cameraBox(for: points, paddingRatio: 0.10) else {
            return XCTFail("10% padding 必须产出包围盒")
        }
        let expectedLatitudeSpan = 0.001 * 1.2
        let expectedLongitudeSpan = 0.001 * 1.2
        XCTAssertEqual(box.latitudeSpan, expectedLatitudeSpan, accuracy: 1e-9)
        XCTAssertEqual(box.longitudeSpan, expectedLongitudeSpan, accuracy: 1e-9)
        XCTAssertEqual(box.centerLatitude, 31.0005, accuracy: 1e-9)
        XCTAssertEqual(box.centerLongitude, 121.0005, accuracy: 1e-9)
    }

    func testCameraBoxNilForEmptyTrack() {
        XCTAssertNil(TrackGeometry.cameraBox(for: [], paddingRatio: 0.10))
    }

    // MARK: - helpers

    private func samples(at seconds: [Double]) -> [RunSample] {
        seconds.compactMap { second in
            makeSample(latitude: 31.0, longitude: 121.0, seconds: second)
        }
    }

    private func makeSample(latitude: Double, longitude: Double, seconds: Double) -> RunSample {
        RunSample(
            latitude: latitude,
            longitude: longitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: 1_760_000_000 + seconds),
            heartRate: nil,
            cadence: nil
        )!
    }

    /// 原点到抽稀后折线的最大偏差（米），复用与实现一致的局部米制投影。
    private func maxDeviation(from samples: [RunSample], to simplified: [TrackCoordinate]) -> Double {
        let latitude = samples.first?.latitude ?? 0
        let longitudeScale = 111_320 * cos(latitude * .pi / 180)
        func project(_ latitude: Double, _ longitude: Double) -> (Double, Double) {
            (longitude * longitudeScale, latitude * 111_320)
        }
        let polyline = simplified.map { project($0.latitude, $0.longitude) }
        var maximum = 0.0
        for sample in samples {
            let point = project(sample.latitude, sample.longitude)
            var minimum = Double.greatestFiniteMagnitude
            for index in 1..<polyline.count {
                minimum = min(minimum, distance(point, polyline[index - 1], polyline[index]))
            }
            maximum = max(maximum, minimum)
        }
        return maximum
    }

    private func distance(
        _ point: (Double, Double),
        _ start: (Double, Double),
        _ end: (Double, Double)
    ) -> Double {
        let dx = end.0 - start.0
        let dy = end.1 - start.1
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.0 - start.0, point.1 - start.1)
        }
        var t = ((point.0 - start.0) * dx + (point.1 - start.1) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        return hypot(point.0 - (start.0 + t * dx), point.1 - (start.1 + t * dy))
    }
}
