import CoreGraphics
import XCTest
@testable import PurePace

/// 采样判定的 L1 反例（纯逻辑、无 UI）：与 `LocalizationPolicyTests` 的「运行中」代表帧同构。
/// 基准帧为运行中绿样本（最大空洞 79.27pt，距 80 上限 0.73pt），反例只喂帧、不依赖产品代码回退。
final class RunLayoutSamplingCounterexampleTests: XCTestCase {
    private let navigationBarBottom: CGFloat = 137.3
    private let primaryActionTop: CGFloat = 701.0

    /// inline 胶囊实测框：宽 358.3 / 高 36.7。
    private let hintFrame = CGRect(x: 17.3, y: 485.15, width: 358.3, height: 36.7)

    private var runningFrames: [CGRect] {
        [
            CGRect(x: 88.5, y: 204.58, width: 216, height: 67),
            CGRect(x: 184.5, y: 275.58, width: 24, height: 14.3),
            CGRect(x: 59.8, y: 369.15, width: 97, height: 40.7),
            hintFrame,
            CGRect(x: 24, y: 535, width: 345, height: 32),
            CGRect(x: 24, y: 573, width: 345, height: 62.73)
        ]
    }

    /// 与胶囊同心、但上下各外扩 0.71pt（合计高 1.42pt）的内层文本帧。
    private var innerTextFrame: CGRect {
        CGRect(
            x: hintFrame.minX + 24,
            y: hintFrame.minY - 0.71,
            width: hintFrame.width - 48,
            height: hintFrame.height + 1.42
        )
    }

    private func evaluate(_ frames: [CGRect]) -> RunLayoutBalancePolicy.Evaluation {
        RunLayoutBalancePolicy.evaluate(
            contentFrames: frames,
            navigationBarBottom: navigationBarBottom,
            primaryActionTop: primaryActionTop
        )
    }

    private func layoutFrame(_ rect: CGRect) -> RunLayoutFrame {
        RunLayoutFrame(
            x: Double(rect.minX),
            y: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    /// 基准帧必须先判绿，且最大空洞距离 80 上限 < 1pt（否则下移 6pt 的反例没有意义）。
    func testRunningBaselinePassesWithinOnePointOfLimit() {
        let evaluation = evaluate(runningFrames)
        XCTAssertTrue(evaluation.passes, "\(evaluation.problems)")
        XCTAssertEqual(evaluation.largestGap, 79.27, accuracy: 0.01)
        XCTAssertLessThan(RunLayoutBalancePolicy.maximumGap - evaluation.largestGap, 1)
    }

    /// ac-counterexample-downshift-6-red：胶囊整体下移 6pt 后同一判定必须判红，
    /// 且红在「最大单一垂直空洞 > 80」这条既有判据上（阈值不放宽）。
    func testCapsuleDownshiftBySixPointsFailsLargestGap() {
        let shifted = runningFrames.map { frame in
            frame == hintFrame ? frame.offsetBy(dx: 0, dy: 6) : frame
        }
        let evaluation = evaluate(shifted)
        XCTAssertGreaterThan(evaluation.largestGap, RunLayoutBalancePolicy.maximumGap)
        XCTAssertEqual(evaluation.largestGap, 81.3, accuracy: 0.01)
        XCTAssertFalse(evaluation.passes)
        XCTAssertTrue(
            evaluation.problems.contains { $0.contains("最大单一垂直空洞") },
            "\(evaluation.problems)"
        )
    }

    /// ac-dedupe-largest-neutral：内层文本帧去重后的 `largestGap` 必须与「仅胶囊帧」逐位相等（差值 0）；
    /// 若去重误删胶囊本身，判定的最大空洞会跳变到 125.15pt，本用例判红。
    func testDedupeLeavesLargestGapEqualToCapsuleOnly() {
        let framesWithInnerText = runningFrames + [innerTextFrame]
        let deduped = RunLayoutSamplingPolicy.dedupeFramesInsideHint(
            framesWithInnerText.map(layoutFrame),
            hint: layoutFrame(hintFrame)
        )
        let dedupedRects = deduped.map { frame in
            CGRect(
                x: CGFloat(frame.x),
                y: CGFloat(frame.y),
                width: CGFloat(frame.width),
                height: CGFloat(frame.height)
            )
        }
        XCTAssertFalse(dedupedRects.contains(innerTextFrame), "内层文本帧必须被去重")
        XCTAssertTrue(dedupedRects.contains(hintFrame), "胶囊自身 frame 不得被误删")
        XCTAssertEqual(dedupedRects.count, runningFrames.count)

        let withInnerText = evaluate(dedupedRects)
        let capsuleOnly = evaluate(runningFrames)
        XCTAssertEqual(withInnerText.largestGap, capsuleOnly.largestGap, "差值必须为 0")
        XCTAssertEqual(withInnerText.largestGap, 79.27, accuracy: 0.01)
        XCTAssertTrue(withInnerText.passes, "\(withInnerText.problems)")
    }
}
