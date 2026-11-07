import XCTest
import PurePaceRunCore

// 合成 1 Hz 坐标流：固定航向、恒定配速，时间戳从固定基准递增（不读当前时间）。
private let syntheticEarthRadius = 6_371_000.0
private let metersPerDegreeLatitude = syntheticEarthRadius * Double.pi / 180.0
private let syntheticBaseLatitude = 31.2304
private let syntheticBaseLongitude = 121.4737

private func makeSyntheticStream(
    paceSecondsPerKilometer: Double,
    sampleCount: Int,
    bearingDegrees: Double = 60.0,
    startTimestamp: TimeInterval = 0
) -> [RunSample] {
    let metersPerSecond = 1000.0 / paceSecondsPerKilometer
    let bearing = bearingDegrees * Double.pi / 180.0
    let metersPerDegreeLongitude = metersPerDegreeLatitude
        * cos(syntheticBaseLatitude * Double.pi / 180.0)

    var samples: [RunSample] = []
    for index in 0..<sampleCount {
        let traveled = metersPerSecond * Double(index)
        let latitude = syntheticBaseLatitude + traveled * cos(bearing) / metersPerDegreeLatitude
        let longitude = syntheticBaseLongitude + traveled * sin(bearing) / metersPerDegreeLongitude
        guard let sample = RunSample(
            latitude: latitude,
            longitude: longitude,
            altitude: nil,
            timestamp: Date(timeIntervalSince1970: startTimestamp + Double(index)),
            heartRate: nil,
            cadence: nil
        ) else {
            return []
        }
        samples.append(sample)
    }
    return samples
}

// 独立参考实现：用 atan2 形式的 Haversine，与被测实现的计算过程相互独立。
private func referenceMeters(from first: RunSample, to second: RunSample) -> Double {
    let phi1 = first.latitude * Double.pi / 180.0
    let phi2 = second.latitude * Double.pi / 180.0
    let deltaPhi = (second.latitude - first.latitude) * Double.pi / 180.0
    let deltaLambda = (second.longitude - first.longitude) * Double.pi / 180.0
    let a = sin(deltaPhi / 2.0) * sin(deltaPhi / 2.0)
        + cos(phi1) * cos(phi2) * sin(deltaLambda / 2.0) * sin(deltaLambda / 2.0)
    return 2.0 * syntheticEarthRadius * atan2(sqrt(min(1.0, a)), sqrt(max(0.0, 1.0 - a)))
}

private func referenceCumulative(_ samples: [RunSample]) -> [Double] {
    var cumulative: [Double] = [0.0]
    guard samples.count > 1 else { return cumulative }
    for index in 1..<samples.count {
        cumulative.append(cumulative[index - 1] + referenceMeters(from: samples[index - 1], to: samples[index]))
    }
    return cumulative
}

final class RunMetricsEngineTests: XCTestCase {
    // MARK: - Haversine

    func testEarthRadiusConstantMatchesSharedScale() {
        XCTAssertEqual(GeoDistance.earthRadiusMeters, 6_371_000.0)

        let coordinates: [(Double, Double)] = [
            (31.2304, 121.4737),
            (31.2322, 121.4749),
            (31.2340, 121.4761),
            (31.2358, 121.4773)
        ]
        var total = 0.0
        for index in 1..<coordinates.count {
            total += GeoDistance.meters(
                latitude1: coordinates[index - 1].0,
                longitude1: coordinates[index - 1].1,
                latitude2: coordinates[index].0,
                longitude2: coordinates[index].1
            )
        }
        XCTAssertEqual(total, 691.16, accuracy: 0.05)

        let same = GeoDistance.meters(latitude1: 31.2304, longitude1: 121.4737, latitude2: 31.2304, longitude2: 121.4737)
        XCTAssertEqual(same, 0.0, accuracy: 1e-9)
        let forward = GeoDistance.meters(latitude1: 31.2304, longitude1: 121.4737, latitude2: 31.2322, longitude2: 121.4749)
        let backward = GeoDistance.meters(latitude1: 31.2322, longitude1: 121.4749, latitude2: 31.2304, longitude2: 121.4737)
        XCTAssertEqual(forward, backward, accuracy: 1e-9)
    }

    // MARK: - 首点

    func testFirstAcceptedSampleOnlyEstablishesAnchor() {
        let stream = makeSyntheticStream(paceSecondsPerKilometer: 300, sampleCount: 4)
        XCTAssertEqual(stream.count, 4)

        var engine = RunMetricsEngine()
        let update = engine.ingest(stream[0])

        XCTAssertEqual(update.metrics.distance.meters, 0)
        XCTAssertEqual(update.metrics.elapsed, 0)
        XCTAssertNil(update.metrics.averagePace)
        XCTAssertNil(update.metrics.currentPace)
        XCTAssertTrue(update.metrics.splits.isEmpty)
        XCTAssertEqual(update.metrics.completedKilometers, 0)
        XCTAssertTrue(update.newlyCompletedSplits.isEmpty)

        let second = engine.ingest(stream[1])
        XCTAssertGreaterThan(second.metrics.distance.meters, 0)
        XCTAssertEqual(second.metrics.elapsed, 1.0, accuracy: 1e-9)
    }

    // MARK: - 距离与配速阈值

    func testDistanceRelativeErrorWithinOnePercent() {
        for pace in [300.0, 420.0] {
            let stream = makeSyntheticStream(paceSecondsPerKilometer: pace, sampleCount: 1000)
            XCTAssertEqual(stream.count, 1000)

            var engine = RunMetricsEngine()
            for sample in stream {
                _ = engine.ingest(sample)
            }

            guard let reference = referenceCumulative(stream).last else {
                return XCTFail("参考累计距离缺失")
            }
            XCTAssertGreaterThan(reference, 2000)
            XCTAssertEqual(
                engine.metrics.distance.meters,
                reference,
                accuracy: reference * 0.01,
                "配速 \(pace) s/km 的累计距离相对误差超过 1%"
            )
        }
    }

    func testAveragePaceErrorWithinTwoSecondsPerKilometer() {
        for pace in [300.0, 420.0] {
            let stream = makeSyntheticStream(paceSecondsPerKilometer: pace, sampleCount: 1000)
            guard let first = stream.first, let last = stream.last else {
                return XCTFail("合成流不应为空")
            }
            let activeElapsed = last.timestamp.timeIntervalSince(first.timestamp)

            var engine = RunMetricsEngine()
            for sample in stream {
                _ = engine.ingest(sample)
            }

            guard let reference = referenceCumulative(stream).last, reference > 0 else {
                return XCTFail("参考累计距离缺失")
            }
            let truth = activeElapsed / (reference / 1000.0)
            guard let averagePace = engine.metrics.averagePace else {
                return XCTFail("恒定配速流应产生平均配速")
            }
            XCTAssertEqual(averagePace.secondsPerKilometer, truth, accuracy: 2.0)
            XCTAssertEqual(averagePace.secondsPerKilometer, pace, accuracy: 2.0)
        }
    }

    func testCurrentPaceWarmUpIsNilThenWithinTwoSecondsPerKilometer() {
        for pace in [300.0, 420.0] {
            let stream = makeSyntheticStream(paceSecondsPerKilometer: pace, sampleCount: 400)
            var engine = RunMetricsEngine()

            var measuredCount = 0
            for (index, sample) in stream.enumerated() {
                let update = engine.ingest(sample)
                let current = update.metrics.currentPace
                if index <= 2 {
                    XCTAssertNil(current, "窗口预热未完成时不应返回当前配速（index \(index)）")
                } else {
                    guard let current else {
                        return XCTFail("预热完成后当前配速不应为 nil（index \(index)）")
                    }
                    XCTAssertEqual(current.secondsPerKilometer, pace, accuracy: 2.0)
                    measuredCount += 1
                }
            }
            XCTAssertGreaterThan(measuredCount, 380)
        }
    }

    // MARK: - 公里分段

    func testSplitBoundariesAndSplitsStayWithinOneSample() {
        for pace in [300.0, 420.0] {
            let stream = makeSyntheticStream(paceSecondsPerKilometer: pace, sampleCount: 1000)
            let reference = referenceCumulative(stream)
            var engine = RunMetricsEngine()

            var emissionIndex: [Int: Int] = [:]
            var emittedSplits = 0
            var seen: [RunSplit] = []

            for (index, sample) in stream.enumerated() {
                let update = engine.ingest(sample)
                if !update.newlyCompletedSplits.isEmpty {
                    emittedSplits += 1
                    for split in update.newlyCompletedSplits {
                        emissionIndex[split.index] = index
                    }
                }

                let metrics = update.metrics
                XCTAssertEqual(metrics.splits.count, metrics.completedKilometers)
                XCTAssertGreaterThanOrEqual(metrics.distance.meters + 1e-9, Double(metrics.splits.count) * 1000.0)
                XCTAssertGreaterThanOrEqual(metrics.splits.count, seen.count)
                XCTAssertEqual(Array(metrics.splits.prefix(seen.count)), seen)
                seen = metrics.splits
            }

            XCTAssertGreaterThanOrEqual(seen.count, 2)
            XCTAssertEqual(emittedSplits, seen.count, "每个分段只应发出一次")

            for (offset, split) in seen.enumerated() {
                let ordinal = offset + 1
                XCTAssertEqual(split.index, ordinal)
                XCTAssertEqual(split.distance.meters, 1000.0, accuracy: 1e-9)
                XCTAssertGreaterThan(split.duration, 0)
                XCTAssertNotNil(split.pace)
                XCTAssertEqual(split.duration, pace, accuracy: 2.0)

                let target = Double(ordinal) * 1000.0
                guard let expected = reference.firstIndex(where: { $0 >= target }) else {
                    return XCTFail("参考累计距离未跨过第 \(ordinal) 公里")
                }
                guard let actual = emissionIndex[split.index] else {
                    return XCTFail("第 \(ordinal) 段没有发出记录")
                }
                XCTAssertLessThanOrEqual(
                    abs(actual - expected),
                    1,
                    "第 \(ordinal) 段边界与理论采样点相差超过 1 个采样点"
                )
            }
        }
    }

    // MARK: - 重复点与时间倒退

    func testDuplicatePointAddsNoDistanceOrSplitButAdvancesElapsed() {
        let stream = makeSyntheticStream(paceSecondsPerKilometer: 300, sampleCount: 8)
        guard let base = stream.first else { return XCTFail("合成流不应为空") }

        var engine = RunMetricsEngine()
        _ = engine.ingest(base)

        for index in 1...5 {
            guard let duplicate = RunSample(
                latitude: base.latitude,
                longitude: base.longitude,
                altitude: nil,
                timestamp: Date(timeIntervalSince1970: Double(index)),
                heartRate: nil,
                cadence: nil
            ) else {
                return XCTFail("重复点应合法")
            }
            let update = engine.ingest(duplicate)
            XCTAssertEqual(update.metrics.distance.meters, 0, accuracy: 1e-12)
            XCTAssertTrue(update.metrics.splits.isEmpty)
            XCTAssertTrue(update.newlyCompletedSplits.isEmpty)
            XCTAssertEqual(update.metrics.completedKilometers, 0)
            XCTAssertEqual(update.metrics.elapsed, Double(index), accuracy: 1e-9)
        }
        XCTAssertNil(engine.metrics.currentPace)
    }

    func testTimeRegressionSamplesAreDiscardedEntirely() {
        let stream = makeSyntheticStream(paceSecondsPerKilometer: 300, sampleCount: 10)
        var engine = RunMetricsEngine()
        for sample in stream[0...4] {
            _ = engine.ingest(sample)
        }
        let snapshot = engine.metrics
        XCTAssertGreaterThan(snapshot.distance.meters, 0)
        XCTAssertGreaterThan(snapshot.elapsed, 0)

        // 等时重放：整条丢弃。
        _ = engine.ingest(stream[4])
        XCTAssertEqual(engine.metrics, snapshot)

        // 时间倒退 + 坐标大幅位移：不得产生负增量或回退。
        guard let regressed = RunSample(
            latitude: 40.0,
            longitude: 130.0,
            altitude: nil,
            timestamp: stream[2].timestamp,
            heartRate: nil,
            cadence: nil
        ) else {
            return XCTFail("倒退样本本身合法")
        }
        let update = engine.ingest(regressed)
        XCTAssertEqual(update.metrics, snapshot)
        XCTAssertTrue(update.newlyCompletedSplits.isEmpty)
    }

    // MARK: - 暂停

    func testPauseFreezesElapsedAndExcludesDistance() {
        let stream = makeSyntheticStream(paceSecondsPerKilometer: 300, sampleCount: 40)
        var engine = RunMetricsEngine()

        for sample in stream[0...3] {
            _ = engine.ingest(sample)
        }
        let beforePause = engine.metrics
        XCTAssertEqual(beforePause.elapsed, 3.0, accuracy: 1e-9)
        XCTAssertGreaterThan(beforePause.distance.meters, 0)

        engine.pause(at: Date(timeIntervalSince1970: 3.5))
        let paused = engine.metrics
        XCTAssertNil(paused.currentPace)
        XCTAssertEqual(paused.elapsed, beforePause.elapsed, accuracy: 1e-9)
        XCTAssertEqual(paused.distance, beforePause.distance)

        // 暂停区间的采样点（含位移与时间推进）不得累计距离或活跃时长。
        for sample in stream[4...8] {
            let update = engine.ingest(sample)
            XCTAssertTrue(update.newlyCompletedSplits.isEmpty)
        }
        XCTAssertEqual(engine.metrics, paused)

        engine.resume(at: Date(timeIntervalSince1970: 8.5))
        let resumed = engine.metrics
        XCTAssertEqual(resumed.distance, beforePause.distance)
        XCTAssertEqual(resumed.elapsed, beforePause.elapsed, accuracy: 1e-9)

        // 恢复后的首个样本重建位置锚点：跨越暂停空档不产生位移。
        let anchorUpdate = engine.ingest(stream[9])
        XCTAssertEqual(anchorUpdate.metrics.distance, beforePause.distance)
        XCTAssertEqual(anchorUpdate.metrics.elapsed, beforePause.elapsed + 0.5, accuracy: 1e-9)

        // 之后的样本恢复累计距离。
        let movingUpdate = engine.ingest(stream[10])
        XCTAssertGreaterThan(movingUpdate.metrics.distance.meters, beforePause.distance.meters)
        XCTAssertEqual(movingUpdate.metrics.elapsed, beforePause.elapsed + 1.5, accuracy: 1e-9)
    }

    // MARK: - 锚点幂等与非法锚点

    func testAnchorCallsAreIdempotentAndStaleTimestampsIgnored() {
        let stream = makeSyntheticStream(
            paceSecondsPerKilometer: 300,
            sampleCount: 4,
            startTimestamp: 1_000
        )
        XCTAssertEqual(stream.count, 4)

        // 未 start 直接 ingest：正常工作。
        var implicit = RunMetricsEngine()
        let first = implicit.ingest(stream[0])
        XCTAssertEqual(first.metrics.elapsed, 0)
        XCTAssertEqual(first.metrics.distance.meters, 0)
        XCTAssertTrue(implicit.ingest(stream[1]).metrics.distance.meters > 0)

        // 重复 start/暂停/恢复/结束 + 早于账本的锚点时间。
        var engine = RunMetricsEngine()
        engine.start(at: Date(timeIntervalSince1970: 1_000))
        engine.start(at: Date(timeIntervalSince1970: 2_000))
        _ = engine.ingest(stream[0])
        _ = engine.ingest(stream[1])
        XCTAssertEqual(engine.metrics.elapsed, 1.0, accuracy: 1e-9)

        engine.pause(at: Date(timeIntervalSince1970: 500))
        XCTAssertNil(engine.metrics.currentPace)
        engine.pause(at: Date(timeIntervalSince1970: 600))
        XCTAssertNil(engine.metrics.currentPace)
        engine.resume(at: Date(timeIntervalSince1970: 600))
        engine.resume(at: Date(timeIntervalSince1970: 700))

        _ = engine.ingest(stream[2])
        XCTAssertEqual(engine.metrics.elapsed, 2.0, accuracy: 1e-9)

        engine.finish(at: Date(timeIntervalSince1970: 900))
        let finished = engine.metrics
        engine.finish(at: Date(timeIntervalSince1970: 950))
        _ = engine.ingest(stream[3])

        XCTAssertEqual(engine.metrics, finished)
        XCTAssertTrue(engine.metrics.elapsed.isFinite)
        XCTAssertGreaterThanOrEqual(engine.metrics.elapsed, 0)
        XCTAssertTrue(engine.metrics.distance.meters.isFinite)
        XCTAssertGreaterThanOrEqual(engine.metrics.distance.meters, 0)
    }
}
