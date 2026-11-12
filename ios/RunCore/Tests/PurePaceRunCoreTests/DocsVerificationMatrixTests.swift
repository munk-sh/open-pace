import XCTest

/// `docs/verification-matrix.md` 的结构守护（L1，无 UI）。
///
/// 约束：纯表格、表头逐字一致、恰 21 条接缝、6 列；全部行回填后为
/// 21 行实测 + 0 行显式缺口，不再保留 `pending: 待对应 item 回填`。
final class DocsVerificationMatrixTests: XCTestCase {
    private static let expectedHeader = "| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |"
    private static let pendingMarker = "pending: 待对应 item 回填"
    private static let gapMarker = "缺口"
    private static let expectedSeamCount = 21
    private static let baseSeams = ["后台定位", "锁屏", "重启", "Info.plist", "TTS", "duck", "GPX", "竖屏", "Dynamic Type", "设计 token"]
    /// 本项（wi_intake_e7e73d829e61fa7a）新增的 5 条接缝：每行必须带本项标识归属。
    private static let workItemSeams = ["palette", "accent↔warning", "深色中性 chroma", "finish=accent", "discard 仅在确认层"]
    /// 本项（wi_intake_7b9d19bc1e3be0ee）新增的 4 条接缝。
    private static let trackSeams = ["地图壳", "RDP 抽稀", ">60s 断线", "list 轻量索引"]
    /// 本项（wi_intake_17fe09b83e2a3df0）新增的 1 条接缝。
    private static let ax5Seams = ["取证腿顺序无关"]
    /// 本项（wi_intake_1127fd3553df6ea7）新增的 1 条接缝。
    private static let uiLegSeams = ["详情导出固定底部"]
    private static let seams = baseSeams + workItemSeams + trackSeams + ax5Seams + uiLegSeams
    private static let workItemId = "wi_intake_e7e73d829e61fa7a"
    private static let trackWorkItemId = "wi_intake_7b9d19bc1e3be0ee"
    private static let ax5WorkItemId = "wi_intake_17fe09b83e2a3df0"
    private static let uiLegWorkItemId = "wi_intake_1127fd3553df6ea7"

    private enum MatrixError: Error, CustomStringConvertible {
        case repoRootNotFound(start: String)
        case fileMissing(String)

        var description: String {
            switch self {
            case let .repoRootNotFound(start):
                return "无法从 \(start) 向上定位含 VERSION 的仓库根"
            case let .fileMissing(path):
                return "验证矩阵文件不存在: \(path)"
            }
        }
    }

    // MARK: - 结构断言

    func testMatrixIsPureTableWithExpectedHeaderAndColumns() throws {
        let lines = try nonEmptyLines()

        XCTAssertEqual(lines.first, Self.expectedHeader, "表头必须逐字等于约定列名")
        XCTAssertEqual(lines.count, Self.expectedSeamCount + 2, "必须恰为表头 + 分隔行 + \(Self.expectedSeamCount) 行接缝")

        for (offset, line) in lines.enumerated() {
            XCTAssertTrue(line.hasPrefix("|"), "第 \(offset + 1) 行不是表格行：\(line)")
            let cells = line.components(separatedBy: "|")
            XCTAssertEqual(cells.count, 8, "第 \(offset + 1) 行必须恰为 6 列（含首尾分隔）：\(line)")
            let middle = cells.dropFirst().dropLast()
            XCTAssertTrue(middle.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                          "第 \(offset + 1) 行存在空单元格：\(line)")
        }
    }

    // MARK: - 覆盖、缺口与 pending 归属

    func testMatrixCoversTenSeamsWithTenMeasuredRowsAndNoGap() throws {
        let dataRows = Array(try nonEmptyLines().dropFirst(2))
        XCTAssertEqual(dataRows.count, Self.expectedSeamCount)

        let pendingRows = dataRows.filter { $0.contains(Self.pendingMarker) }
        XCTAssertEqual(pendingRows.count, 0, "回填后不得再有 pending 行")

        let gapRows = dataRows.filter { $0.contains(Self.gapMarker) }
        XCTAssertEqual(gapRows.count, 0, "回填后不得再有显式缺口行")

        let measuredRows = dataRows.filter {
            !$0.contains(Self.pendingMarker) && !$0.contains(Self.gapMarker)
        }
        XCTAssertEqual(measuredRows.count, Self.expectedSeamCount, "回填后 \(Self.expectedSeamCount) 条接缝必须全部为实测行")

        let dynamicTypeRow = dataRows.first { $0.contains("Dynamic Type") }
        XCTAssertNotNil(dynamicTypeRow, "缺少 Dynamic Type 行")
        XCTAssertTrue(dynamicTypeRow?.contains("本项实测") ?? false,
                      "Dynamic Type 行现状必须写明本项实测口径")
        XCTAssertTrue(dynamicTypeRow?.contains("testAX5PrimaryActionMeetsMinimumTapTarget") ?? false,
                      "Dynamic Type 行断言名必须为真实符号")
        XCTAssertTrue(dynamicTypeRow?.contains("testFixed32ptActionHeightCounterexample") ?? false,
                      "Dynamic Type 行反例必须为真实符号")
        XCTAssertTrue(dynamicTypeRow?.contains("ios/PurePaceTests/DynamicTypeLayoutTests.swift") ?? false,
                      "Dynamic Type 行证据路径必须指向新测试文件")
        XCTAssertTrue(dynamicTypeRow?.contains("ios/PurePace/Design/PrimaryActionLayoutPolicy.swift") ?? false,
                      "Dynamic Type 行证据路径必须指向几何策略文件")

        for seam in Self.seams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertNotNil(row, "缺少接缝：\(seam)")
        }

        for seam in Self.seams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertFalse(row?.contains(Self.pendingMarker) ?? true, "\(seam) 已实测，不得标 pending")
            XCTAssertFalse(row?.contains(Self.gapMarker) ?? true, "\(seam) 已实测，不得含缺口标记")
        }

        for seam in Self.workItemSeams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertNotNil(row, "缺少接缝：\(seam)")
            XCTAssertTrue(row?.contains("本项实测") ?? false, "\(seam) 现状必须写明本项实测口径")
            XCTAssertTrue(row?.contains(Self.workItemId) ?? false, "\(seam) 必须归属 \(Self.workItemId)")
        }

        for seam in Self.trackSeams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertNotNil(row, "缺少接缝：\(seam)")
            XCTAssertTrue(row?.contains("本项实测") ?? false, "\(seam) 现状必须写明本项实测口径")
            XCTAssertTrue(row?.contains(Self.trackWorkItemId) ?? false, "\(seam) 必须归属 \(Self.trackWorkItemId)")
        }

        for seam in Self.ax5Seams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertNotNil(row, "缺少接缝：\(seam)")
            XCTAssertTrue(row?.contains("本项实测") ?? false, "\(seam) 现状必须写明本项实测口径")
            XCTAssertTrue(row?.contains(Self.ax5WorkItemId) ?? false, "\(seam) 必须归属 \(Self.ax5WorkItemId)")
        }

        for seam in Self.uiLegSeams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertNotNil(row, "缺少接缝：\(seam)")
            XCTAssertTrue(row?.contains("本项实测") ?? false, "\(seam) 现状必须写明本项实测口径")
            XCTAssertTrue(row?.contains(Self.uiLegWorkItemId) ?? false, "\(seam) 必须归属 \(Self.uiLegWorkItemId)")
        }
    }

    // MARK: - 读取

    private func nonEmptyLines() throws -> [String] {
        let url = try repoRoot().appendingPathComponent("docs/verification-matrix.md")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MatrixError.fileMissing(url.path)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        for _ in 0..<12 {
            if fileManager.fileExists(atPath: url.appendingPathComponent("VERSION").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        throw MatrixError.repoRootNotFound(start: #filePath)
    }
}
