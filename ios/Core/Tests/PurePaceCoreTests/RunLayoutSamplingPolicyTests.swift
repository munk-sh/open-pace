import XCTest
@testable import PurePaceCore

/// `RunLayoutSamplingPolicy` 的 L1 判据（纯逻辑、无 UI、无外部 IO）：
/// 稳定采样的有界轮数与连续一致口径、胶囊去重的中心点判据及其反例。
final class RunLayoutSamplingPolicyTests: XCTestCase {
    private let navigationBarBottom: Double = 137.3
    private let primaryActionTop: Double = 701.0

    /// inline 胶囊（图标 + 短文案合并元素）实测框。
    private static let hintFrame = RunLayoutFrame(x: 17.3, y: 599.03, width: 358.3, height: 36.7)

    /// 运行中代表帧（与 UI 用例同一采样口径：静态文本块 + inline 胶囊）。
    private var runningFrames: [RunLayoutFrame] {
        [
            RunLayoutFrame(x: 88.5, y: 204.58, width: 216, height: 67),
            RunLayoutFrame(x: 184.5, y: 275.58, width: 24, height: 14.3),
            RunLayoutFrame(x: 59.8, y: 369.15, width: 97, height: 40.7),
            RunLayoutFrame(x: 96.2, y: 413.85, width: 24, height: 14.3),
            RunLayoutFrame(x: 269.4, y: 369.15, width: 30.7, height: 40.7),
            RunLayoutFrame(x: 102.6, y: 493.15, width: 11.3, height: 14.3),
            Self.hintFrame
        ]
    }

    private func sample(_ frames: [RunLayoutFrame]) -> RunLayoutSample {
        RunLayoutSample(
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop,
            contentFrames: frames
        )
    }

    /// 把胶囊整体平移（模拟布局稳定过程中的瞬时位移），其余帧不动。
    private func sample(shiftingHintBy dy: Double) -> RunLayoutSample {
        let shifted = runningFrames.map { frame in
            frame == Self.hintFrame
                ? RunLayoutFrame(x: frame.x, y: frame.y + dy, width: frame.width, height: frame.height)
                : frame
        }
        return sample(shifted)
    }

    // MARK: - 稳定采样

    /// ac-settle-three-consecutive-stable：前两轮漂移、第 3 轮起一致时，
    /// 返回的必须是稳定后的集合，而不是首轮采样。
    func testSettleRequiresThreeConsecutiveStableRounds() {
        let firstRound = sample(shiftingHintBy: 1.5)
        let secondRound = sample(shiftingHintBy: 3)
        let settled = sample(shiftingHintBy: 0)

        var tracker = RunLayoutSamplingPolicy.SettleTracker()
        XCTAssertFalse(tracker.record(firstRound))
        XCTAssertFalse(tracker.record(secondRound))
        XCTAssertFalse(tracker.record(settled))
        XCTAssertFalse(tracker.record(settled), "第 4 轮仍在累计，不得先行判稳定")
        XCTAssertTrue(tracker.record(settled), "第 5 轮达成连续 3 轮一致")

        let result = RunLayoutSamplingPolicy.settledSample(
            from: [firstRound, secondRound, settled, settled, settled]
        )
        XCTAssertEqual(result, settled, "连续 3 轮一致后应返回该稳定集合")
        XCTAssertNotEqual(result, firstRound, "不得把首轮抖动样本当成终值")
    }

    /// 连续一致计数的精确边界：连续 3 轮一致即稳定，且返回最后一致轮次的样本。
    func testSettleBecomesStableExactlyOnThirdMatchingRound() {
        var tracker = RunLayoutSamplingPolicy.SettleTracker()
        let stable = sample(shiftingHintBy: 0)
        XCTAssertFalse(tracker.record(stable))
        XCTAssertFalse(tracker.record(stable))
        XCTAssertTrue(tracker.record(stable), "连续第 3 轮一致必须判稳定")
        XCTAssertEqual(tracker.rounds, 3)
        XCTAssertEqual(tracker.stableSample, stable)
        XCTAssertFalse(tracker.canRecordMore, "稳定后不得再采样")
    }

    /// 中途漂移必须重置连续计数。
    func testSettleResetsCounterAfterDrift() {
        let a = sample(shiftingHintBy: 0)
        let b = sample(shiftingHintBy: 2)
        let result = RunLayoutSamplingPolicy.settledSample(from: [a, a, b, b, b])
        XCTAssertEqual(result, b, "漂移后应重新累计 3 轮一致")
    }

    /// ac-counterexample-settle-not-vacuous：每轮都不同的持续漂移必须返回未稳定。
    /// 若把稳定判据改成恒真（首轮即稳定），这里取到的会是首轮样本从而判红。
    func testSettleRejectsContinuousDrift() {
        let drifting = (0..<RunLayoutSamplingPolicy.maximumRounds).map { round in
            sample(shiftingHintBy: Double(round))
        }
        XCTAssertNil(
            RunLayoutSamplingPolicy.settledSample(from: drifting),
            "持续漂移序列不得判稳定"
        )

        var tracker = RunLayoutSamplingPolicy.SettleTracker()
        for round in drifting {
            tracker.record(round)
        }
        XCTAssertFalse(tracker.isStable)
        XCTAssertNil(tracker.stableSample)
        XCTAssertEqual(tracker.rounds, RunLayoutSamplingPolicy.maximumRounds)
        XCTAssertFalse(tracker.canRecordMore, "轮数到上限后必须停止采样")
    }

    /// 有界预算写死：3 轮一致 / 12 轮上限 / 6s 上限；任一处被放大都判红。
    func testSettleBudgetIsBounded() {
        XCTAssertEqual(RunLayoutSamplingPolicy.requiredStableRounds, 3)
        XCTAssertEqual(RunLayoutSamplingPolicy.maximumRounds, 12)
        XCTAssertEqual(RunLayoutSamplingPolicy.settleTimeout, 6, accuracy: 0.000_1)
    }

    /// 采样比较包含内容区上下界：帧集合相同但导航栏/主操作位移时必须判为不同布局。
    func testSampleComparisonCoversRegionBounds() {
        let frames = runningFrames
        let base = RunLayoutSample(
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop,
            contentFrames: frames
        )
        let movedBar = RunLayoutSample(
            navigationBarBottom: navigationBarBottom + 0.5,
            primaryActionTop: primaryActionTop,
            contentFrames: frames
        )
        let movedAction = RunLayoutSample(
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop - 0.5,
            contentFrames: frames
        )
        XCTAssertFalse(RunLayoutSamplingPolicy.isSameLayout(base, movedBar))
        XCTAssertFalse(RunLayoutSamplingPolicy.isSameLayout(base, movedAction))
    }

    /// 只消解可及树遍历顺序，不对坐标做容差：同一几何、乱序帧仍判同一布局；
    /// 但任一帧位移 0.01pt 必须判不同。
    func testSampleComparisonIgnoresOrderButNotGeometry() {
        let frames = runningFrames
        let reordered = RunLayoutSample(
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop,
            contentFrames: frames.reversed()
        )
        XCTAssertTrue(RunLayoutSamplingPolicy.isSameLayout(sample(frames), reordered))

        let nudged = frames.map { frame in
            frame == Self.hintFrame
                ? RunLayoutFrame(x: frame.x, y: frame.y + 0.01, width: frame.width, height: frame.height)
                : frame
        }
        XCTAssertFalse(RunLayoutSamplingPolicy.isSameLayout(sample(frames), sample(nudged)))
    }

    // MARK: - 胶囊去重

    /// ac-dedupe-center-in-hint：比胶囊高 1.42pt 的内层文本帧（与胶囊同心）必须被去重，
    /// 胶囊自身 frame 必须保留（否则内容块被清空）。
    func testDedupeRemovesTallerInnerTextFrame() {
        let hint = Self.hintFrame
        // 上下各外扩 0.71pt：严格包含判据为假，中心点仍在胶囊内。
        let innerText = RunLayoutFrame(
            x: hint.x + 24,
            y: hint.y - 0.71,
            width: hint.width - 48,
            height: hint.height + 1.42
        )
        let strictlyContained = innerText.minY >= hint.minY && innerText.maxY <= hint.maxY
        XCTAssertFalse(strictlyContained, "1.42pt 高差下严格包含判据必然漏判")
        XCTAssertTrue(RunLayoutSamplingPolicy.isFrameInsideHint(innerText, hint: hint))

        let frames = runningFrames + [innerText]
        let deduped = RunLayoutSamplingPolicy.dedupeFramesInsideHint(frames, hint: hint)
        XCTAssertFalse(deduped.contains(innerText), "内层文本帧必须被去重")
        XCTAssertTrue(deduped.contains(hint), "胶囊自身 frame 必须保留")
        XCTAssertEqual(deduped.count, runningFrames.count)
    }

    /// 中心点落在胶囊外的相邻内容块必须保留，不得误删。
    func testDedupeKeepsAdjacentBlockOutsideHint() {
        let hint = Self.hintFrame
        let below = RunLayoutFrame(x: 24, y: hint.maxY + 4, width: 345, height: 31.3)
        let above = RunLayoutFrame(x: 24, y: hint.minY - 40, width: 345, height: 31.3)
        for adjacent in [below, above] {
            XCTAssertFalse(RunLayoutSamplingPolicy.isFrameInsideHint(adjacent, hint: hint))
        }
        let deduped = RunLayoutSamplingPolicy.dedupeFramesInsideHint([above, hint, below], hint: hint)
        XCTAssertEqual(deduped, [above, hint, below])
    }

    /// 边界容差：中心点落在胶囊内缩 0.5pt 之外的贴边帧保留，进入内缩矩形才去重。
    func testDedupeBoundaryTolerance() {
        let hint = Self.hintFrame
        // 中心点距胶囊左沿 0.2pt：落在 0.5pt 容差带内，不判为内层帧。
        let hugging = RunLayoutFrame(x: hint.x - 9.8, y: hint.midY - 7, width: 20, height: 14)
        XCTAssertEqual(hugging.midX, hint.x + 0.2, accuracy: 0.000_1)
        XCTAssertFalse(RunLayoutSamplingPolicy.isFrameInsideHint(hugging, hint: hint))

        // 中心点越过容差带 0.6pt：判为内层帧。
        let inside = RunLayoutFrame(x: hugging.x + 0.4, y: hugging.y, width: 20, height: 14)
        XCTAssertEqual(inside.midX, hint.x + 0.6, accuracy: 0.000_1)
        XCTAssertTrue(RunLayoutSamplingPolicy.isFrameInsideHint(inside, hint: hint))

        XCTAssertEqual(
            RunLayoutSamplingPolicy.dedupeFramesInsideHint([hugging, inside], hint: hint),
            [hugging]
        )
        XCTAssertEqual(RunLayoutSamplingPolicy.hintInsetTolerance, 0.5, accuracy: 0.000_1)
    }

    /// 无胶囊（如已保存态没有 inline 提示）时原样返回，不做任何删除。
    func testDedupeWithoutHintKeepsEveryFrame() {
        let frames = runningFrames
        XCTAssertEqual(RunLayoutSamplingPolicy.dedupeFramesInsideHint(frames, hint: nil), frames)
        let empty = RunLayoutFrame(x: 0, y: 0, width: 0, height: 0)
        XCTAssertEqual(RunLayoutSamplingPolicy.dedupeFramesInsideHint(frames, hint: empty), frames)
    }
}
