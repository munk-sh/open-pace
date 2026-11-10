import UIKit
import XCTest
@testable import PurePace

/// 最大辅助字号档 AX5（SwiftUI `.dynamicTypeSize = .accessibility5` /
/// UIKit `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`）主操作几何断言（L1）。
///
/// 只做纯函数判定：字号与文案理想尺寸在此处用 `UIFontMetrics` / `NSString.size(withAttributes:)`
/// 解析后注入 `PrimaryActionLayoutPolicy`，不靠截图取色、不靠运行态黑盒测量。
final class DynamicTypeLayoutTests: XCTestCase {
    // MARK: - 注入几何的来源

    /// 目标设备 iPhone 16 竖屏逻辑尺寸（pt），与 `scripts/test-ios.sh` 的
    /// `platform=iOS Simulator,name=iPhone 16` 一致；不做运行态实测。
    private static let screenWidth: CGFloat = 393
    private static let screenHeight: CGFloat = 852
    /// iPhone 16 竖屏底部安全区（Home Indicator）。
    private static let bottomSafeArea: CGFloat = 34
    /// 可用宽度 = 393 − 左右 `Spacing.md`(16 × 2) = 361pt。
    private static var availableWidth: CGFloat {
        screenWidth - DesignTokens.Spacing.md * 2
    }

    /// 主操作文案区横 / 纵内边距直接取既有 token 档位，不新增样式数值。
    private static let textInsets = CGSize(
        width: DesignTokens.Spacing.sm,
        height: DesignTokens.Spacing.xs
    )

    /// 主操作文案取最长的一条（「查看历史」，与 Localizable.xcstrings 的
    /// `run.action.viewHistory` 同源）；首屏「开始」必然更窄，故按最宽文案判定。
    private static let longestPrimaryActionCopy = "查看历史"

    private static let ax5Traits = UITraitCollection(
        preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
    )

    // MARK: - AX5 度量

    /// 字号基线取 `DesignTokens.Typography.titleSize`（`Typography.control` 的字号），
    /// 由 `UIFontMetrics(forTextStyle: .body)` 在 AX5 下缩放得出，不手调缩放比。
    private func ax5Font() -> UIFont {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: DesignTokens.Typography.titleSize,
            compatibleWith: Self.ax5Traits
        )
        return UIFont.systemFont(ofSize: scaled, weight: .semibold)
    }

    private func ax5TextSize(font: UIFont) -> CGSize {
        (Self.longestPrimaryActionCopy as NSString)
            .size(withAttributes: [.font: font])
    }

    /// AX5 正向几何：底部锚定主操作带。
    /// - 可用下沿 = 852 − 34（安全区）= 818；
    /// - 可用上沿 = 可用下沿 − (需求高度 + `Spacing.lg`)；
    /// - 需求高度 = 文案行高 + 上下各 `Spacing.xs`；
    /// - 内容底沿 = 可用上沿 − `Spacing.sectionGap`（主操作与上方内容之间至少留一档间距）。
    private func ax5Geometry() -> PrimaryActionLayoutPolicy.AccessibilityGeometry {
        let textSize = ax5TextSize(font: ax5Font())
        let requiredHeight = max(
            PrimaryActionLayoutPolicy.minimumActionHeight,
            textSize.height + Self.textInsets.height * 2
        )
        let availableBottom = Self.screenHeight - Self.bottomSafeArea
        let availableTop = availableBottom - (requiredHeight + DesignTokens.Spacing.lg)
        let contentBottom = availableTop - DesignTokens.Spacing.sectionGap
        let actionFrame = CGRect(
            x: DesignTokens.Spacing.md,
            y: availableBottom - requiredHeight,
            width: Self.availableWidth,
            height: requiredHeight
        )
        return PrimaryActionLayoutPolicy.AccessibilityGeometry(
            actionFrame: actionFrame,
            contentBottom: contentBottom,
            availableTop: availableTop,
            availableBottom: availableBottom,
            textSize: textSize,
            textInsets: Self.textInsets
        )
    }

    private func assertPasses(_ evaluation: PrimaryActionLayoutPolicy.AccessibilityEvaluation) {
        XCTAssertTrue(
            evaluation.passes,
            "AX5 主操作几何应通过，实际问题项: \(evaluation.issues.map(\.rawValue))"
        )
        XCTAssertTrue(evaluation.issues.isEmpty)
    }

    // MARK: - ac-ax5-single-source-thresholds

    func testAX5ThresholdsArePinnedBeforeMeasurement() {
        // 阈值于 2026-11-11 在实现前写死（先定后测，判红后未回调）。
        XCTAssertEqual(PrimaryActionLayoutPolicy.minimumActionHeight, DesignTokens.minTapTarget)
        XCTAssertEqual(PrimaryActionLayoutPolicy.minimumActionHeight, 44)
        XCTAssertEqual(PrimaryActionLayoutPolicy.layoutTolerance, 0.5)
    }

    // MARK: - ac-ax5-min-height（字号基线与需求高度来源）

    func testAX5TypographyBaselineComesFromTitleSizeToken() {
        let metrics = UIFontMetrics(forTextStyle: .body)
        let reference = metrics.scaledValue(
            for: DesignTokens.Typography.titleSize,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        XCTAssertEqual(
            reference,
            DesignTokens.Typography.titleSize,
            accuracy: 0.5,
            "字号基线必须等于 Typography.titleSize（control 字号），不得手调缩放比"
        )

        let ax5TextSize = ax5TextSize(font: ax5Font())
        // AX5 下文案行高本身就超过 44pt 最小点按区，按钮必须由内容撑高而不是固定高度。
        XCTAssertGreaterThan(
            ax5TextSize.height,
            PrimaryActionLayoutPolicy.minimumActionHeight,
            "AX5 文案行高应超过 44pt 点按区，否则本档几何断言失效"
        )
    }

    func testAX5PrimaryActionMeetsMinimumTapTarget() {
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(ax5Geometry())

        assertPasses(evaluation)
        XCTAssertGreaterThanOrEqual(
            evaluation.height,
            PrimaryActionLayoutPolicy.minimumActionHeight
        )
    }

    // MARK: - ac-ax5-no-overlap

    func testAX5PrimaryActionDoesNotOverlapUpperContent() {
        let geometry = ax5Geometry()
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)

        assertPasses(evaluation)
        XCTAssertGreaterThanOrEqual(
            geometry.actionFrame.minY,
            geometry.contentBottom - PrimaryActionLayoutPolicy.layoutTolerance
        )
        XCTAssertGreaterThanOrEqual(evaluation.contentGap, -PrimaryActionLayoutPolicy.layoutTolerance)
    }

    // MARK: - ac-ax5-no-clip

    func testAX5PrimaryActionIsNotClipped() {
        let geometry = ax5Geometry()
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)
        let tolerance = PrimaryActionLayoutPolicy.layoutTolerance

        assertPasses(evaluation)
        XCTAssertLessThanOrEqual(geometry.actionFrame.maxY, geometry.availableBottom + tolerance)
        XCTAssertGreaterThanOrEqual(geometry.actionFrame.minY, geometry.availableTop - tolerance)
    }

    // MARK: - ac-ax5-text-not-truncated

    func testAX5PrimaryActionTextIsNotTruncated() {
        let geometry = ax5Geometry()
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)
        let tolerance = PrimaryActionLayoutPolicy.layoutTolerance

        assertPasses(evaluation)
        XCTAssertLessThanOrEqual(geometry.textSize.width, evaluation.textArea.width + tolerance)
        XCTAssertLessThanOrEqual(geometry.textSize.height, evaluation.textArea.height + tolerance)
        XCTAssertFalse(evaluation.issues.contains(.textTruncated))
    }

    // MARK: - ac-ax5-counterexamples-red（共用同一策略实现，只改输入）

    func testFixed32ptActionHeightCounterexample() {
        let base = ax5Geometry()
        let geometry = PrimaryActionLayoutPolicy.AccessibilityGeometry(
            actionFrame: CGRect(
                x: base.actionFrame.minX,
                y: base.availableBottom - 32,
                width: base.actionFrame.width,
                height: 32
            ),
            contentBottom: base.contentBottom,
            availableTop: base.availableTop,
            availableBottom: base.availableBottom,
            textSize: base.textSize,
            textInsets: base.textInsets
        )
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)

        XCTAssertFalse(evaluation.passes, "固定 32pt 高必须判红")
        XCTAssertTrue(evaluation.issues.contains(.heightBelowMinimum))
        XCTAssertLessThan(evaluation.height, PrimaryActionLayoutPolicy.minimumActionHeight)
    }

    func testCompressedAvailableHeightCounterexample() {
        let base = ax5Geometry()
        let geometry = PrimaryActionLayoutPolicy.AccessibilityGeometry(
            actionFrame: base.actionFrame,
            contentBottom: base.contentBottom,
            availableTop: base.availableTop,
            availableBottom: base.actionFrame.maxY - PrimaryActionLayoutPolicy.layoutTolerance - 8,
            textSize: base.textSize,
            textInsets: base.textInsets
        )
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)

        XCTAssertFalse(evaluation.passes, "可用高度放不下主操作必须判红，静默裁剪不得算通过")
        XCTAssertTrue(evaluation.issues.contains(.exceedsAvailableHeight))
    }

    func testOverlapWithUpperContentCounterexample() {
        let base = ax5Geometry()
        let geometry = PrimaryActionLayoutPolicy.AccessibilityGeometry(
            actionFrame: base.actionFrame,
            contentBottom: base.actionFrame.minY + DesignTokens.Spacing.lg,
            availableTop: base.availableTop,
            availableBottom: base.availableBottom,
            textSize: base.textSize,
            textInsets: base.textInsets
        )
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)

        XCTAssertFalse(evaluation.passes, "内容底沿抬到主操作上沿之上必须判红")
        XCTAssertTrue(evaluation.issues.contains(.overlapsUpperContent))
        XCTAssertLessThan(evaluation.contentGap, 0)
    }

    func testStaticMinimumHeightTruncatesAX5TextCounterexample() {
        // 只满足 44pt 最小点按区、但不随 AX5 文案行高撑高时，文字区仍放不下文案 → 必须判红。
        let base = ax5Geometry()
        let geometry = PrimaryActionLayoutPolicy.AccessibilityGeometry(
            actionFrame: CGRect(
                x: base.actionFrame.minX,
                y: base.availableBottom - PrimaryActionLayoutPolicy.minimumActionHeight,
                width: base.actionFrame.width,
                height: PrimaryActionLayoutPolicy.minimumActionHeight
            ),
            contentBottom: base.contentBottom,
            availableTop: base.availableTop,
            availableBottom: base.availableBottom,
            textSize: base.textSize,
            textInsets: base.textInsets
        )
        let evaluation = PrimaryActionLayoutPolicy.evaluateAccessibilityLayout(geometry)

        XCTAssertFalse(evaluation.passes, "44pt 固定高度在 AX5 下会截断文案，必须判红")
        XCTAssertTrue(evaluation.issues.contains(.textTruncated))
    }
}
