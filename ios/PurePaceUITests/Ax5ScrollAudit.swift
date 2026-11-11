import XCTest

/// AX5 可滚动屏（List / ScrollView）的倾向口径：交互元素必须「滚动可达 + 视口内 + 互不覆盖」，
/// 静态文本 / cell 只判水平不溢出（垂直允许滚动，但计数必须打印）。
///
/// 该口径只由测试侧持有：生产布局不动（详情页保持系统 List 滚动），
/// 04 反例用合成快照证明判红能力，不改生产代码、不放宽任何超时。
enum Ax5ScrollAudit {
    /// 一个可及元素在某一滚动步的几何/可点快照。
    struct Snapshot: Equatable {
        let key: String
        let isInteractive: Bool
        let frame: CGRect
        let isHittable: Bool
    }

    struct Result: Equatable {
        let interactiveViolations: [String]
        let horizontalViolations: [String]
        /// 需要滚动才能进入视口的静态元素数量（仅取证计数，不判红）。
        let scrollRequiredStaticCount: Int

        var passes: Bool {
            interactiveViolations.isEmpty && horizontalViolations.isEmpty
        }
    }

    /// 判定：交互元素 hittable 且 frame 完整落在视口内、且不被另一交互元素覆盖；
    /// 静态元素只判水平（`window` 左右边界），垂直越界仅计数。
    static func audit(
        snapshots: [Snapshot],
        viewport: CGRect,
        window: CGRect
    ) -> Result {
        let tolerance: CGFloat = 1
        let interactives = snapshots.filter { $0.isInteractive }
        var interactiveViolations: [String] = []

        for snapshot in interactives {
            guard snapshot.isHittable else {
                interactiveViolations.append(
                    "\(snapshot.key) hittable=false（滚动到底仍不可点） frame=\(snapshot.frame)"
                )
                continue
            }
            let insideViewport = snapshot.frame.minX >= viewport.minX - tolerance
                && snapshot.frame.maxX <= viewport.maxX + tolerance
                && snapshot.frame.minY >= viewport.minY - tolerance
                && snapshot.frame.maxY <= viewport.maxY + tolerance
            if !insideViewport {
                interactiveViolations.append(
                    "\(snapshot.key) frame=\(snapshot.frame) 未完整落在视口 \(viewport)"
                )
            }
            for other in interactives where other.key != snapshot.key {
                let frame = other.frame
                if frame == snapshot.frame || frame.contains(snapshot.frame) || snapshot.frame.contains(frame) {
                    continue
                }
                if frame.intersects(snapshot.frame) {
                    interactiveViolations.append(
                        "\(snapshot.key) 与交互元素 \(other.key) 相交 frame=\(snapshot.frame) other=\(frame)"
                    )
                }
            }
        }

        var horizontalViolations: [String] = []
        var scrollRequiredStaticCount = 0
        for snapshot in snapshots where !snapshot.isInteractive {
            let insideHorizontally = snapshot.frame.minX >= window.minX - tolerance
                && snapshot.frame.maxX <= window.maxX + tolerance
            if !insideHorizontally {
                horizontalViolations.append(
                    "\(snapshot.key) 水平溢出 frame=\(snapshot.frame) window=\(window)"
                )
            }
            if snapshot.frame.maxY > viewport.maxY + tolerance
                || snapshot.frame.minY < viewport.minY - tolerance {
                scrollRequiredStaticCount += 1
            }
        }

        return Result(
            interactiveViolations: interactiveViolations,
            horizontalViolations: horizontalViolations,
            scrollRequiredStaticCount: scrollRequiredStaticCount
        )
    }
}

/// 反例：两条合成快照必须判红，且**失败点不同**
/// （i 错在水平口径；(ii) 错在滚动到底仍 hittable=false）；
/// 另一条「仅静态元素垂直滚动」必须判绿，证明口径没有退化成「全都不许滚动」。
final class Ax5ScrollAuditCounterexampleTests: XCTestCase {
    private static let viewport = CGRect(x: 0, y: 0, width: 393, height: 764)
    private static let window = CGRect(x: 0, y: 0, width: 393, height: 852)

    func testHorizontalOverflowIsRejectedOnHorizontalCriterion() {
        let result = Ax5ScrollAudit.audit(
            snapshots: [
                .init(
                    key: "button:runDetail.export",
                    isInteractive: true,
                    frame: CGRect(x: 16, y: 600, width: 361, height: 44),
                    isHittable: true
                ),
                .init(
                    key: "staticText:runDetail.distance",
                    isInteractive: false,
                    frame: CGRect(x: 16, y: 120, width: 420, height: 76),
                    isHittable: false
                )
            ],
            viewport: Self.viewport,
            window: Self.window
        )
        XCTAssertFalse(result.horizontalViolations.isEmpty, "水平溢出必须判红")
        XCTAssertTrue(result.interactiveViolations.isEmpty, "本反例的失败点必须是水平口径，而非交互口径")
    }

    func testUnreachableInteractiveIsRejectedOnHittableCriterion() {
        let result = Ax5ScrollAudit.audit(
            snapshots: [
                .init(
                    key: "button:runDetail.export",
                    isInteractive: true,
                    frame: CGRect(x: 16, y: 900, width: 361, height: 44),
                    isHittable: false
                )
            ],
            viewport: Self.viewport,
            window: Self.window
        )
        XCTAssertFalse(result.interactiveViolations.isEmpty, "滚动到底仍不可点必须判红")
        XCTAssertTrue(result.interactiveViolations.contains { $0.contains("hittable=false") })
        XCTAssertTrue(result.horizontalViolations.isEmpty, "本反例的失败点必须是交互可达性，而非水平口径")
    }

    func testVerticalScrollingStaticContentPassesAndIsCounted() {
        let result = Ax5ScrollAudit.audit(
            snapshots: [
                .init(
                    key: "button:runDetail.export",
                    isInteractive: true,
                    frame: CGRect(x: 16, y: 600, width: 361, height: 44),
                    isHittable: true
                ),
                .init(
                    key: "staticText:runDetail.startedAt",
                    isInteractive: false,
                    frame: CGRect(x: 16, y: -120, width: 361, height: 30),
                    isHittable: false
                )
            ],
            viewport: Self.viewport,
            window: Self.window
        )
        XCTAssertTrue(result.passes, "纯文本垂直滚出视口不得判红：\(result)")
        XCTAssertEqual(result.scrollRequiredStaticCount, 1, "滚出视口的静态元素必须被计数取证")
    }
}
