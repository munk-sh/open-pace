import XCTest

/// 一次批采得到的可及元素本地快照：后续过滤与断言只消费这些值，不再触碰 `XCUIElement`。
/// 旧写法把查询返回的元素按序号惰性回读快照；AX 元素数随 MapKit 注记等漂移（实测 37↔39）时，
/// 逐个回读 identifier/label/frame 会抛 `No matches found for Element at index N`。
/// 这里改用 `XCUIElementSnapshot` 一次把当前整棵可及树读成本地值
/// （count + 每项 identifier / label / frame / elementType）。
struct AXElementSnapshot {
    let identifier: String
    let label: String
    let frame: CGRect
    let elementType: XCUIElement.ElementType
}

/// 批采入口：单次等待 ≤3s、失配时整批重采、轮数上限写死；不做无限重试、不加固定 sleep。
enum AXSnapshotBatch {
    /// 单轮等待上限：沿用各用例 `waitUntil` 的 0.2s 轮询语义，不放大既有 timeout。
    static let waitPerRound: TimeInterval = 3
    /// 整批重采轮数上限：快照漂移是瞬态，超过即判定为持续失配 / 目标真缺失。
    static let maxRounds = 3

    static func collect(
        from app: XCUIApplication,
        target: String,
        waitUntil: (TimeInterval, () -> Bool) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [AXElementSnapshot] {
        var latest: [AXElementSnapshot] = []
        var lastError: Error?
        for _ in 0..<maxRounds {
            let collected = waitUntil(waitPerRound) {
                do {
                    // UI 用例本来就跑在主线程：把非 Sendable 的快照读取与展开都留在 MainActor 内，
                    // 只把本地值类型（Sendable）带出闭包。
                    latest = try MainActor.assumeIsolated { flatten(try app.snapshot()) }
                    return true
                } catch {
                    lastError = error
                    return false
                }
            }
            if collected { return latest }
        }
        XCTFail(
            "AX 批采失败：elements=\(latest.count) target=\(target) "
                + "error=\(lastError.map { String(describing: $0) } ?? "无")",
            file: file,
            line: line
        )
        return latest
    }

    /// 展开整棵快照树。跳过根节点（application 自身），与 `descendants(matching: .any)` 口径一致。
    @MainActor
    private static func flatten(_ root: XCUIElementSnapshot) -> [AXElementSnapshot] {
        var result: [AXElementSnapshot] = []
        func visit(_ node: XCUIElementSnapshot) {
            for child in node.children {
                result.append(
                    AXElementSnapshot(
                        identifier: child.identifier,
                        label: child.label,
                        frame: child.frame,
                        elementType: child.elementType
                    )
                )
                visit(child)
            }
        }
        visit(root)
        return result
    }
}
