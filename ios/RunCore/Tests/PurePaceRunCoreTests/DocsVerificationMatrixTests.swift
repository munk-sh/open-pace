import XCTest

/// `docs/verification-matrix.md` 的结构守护（L1，无 UI）。
///
/// 约束：纯表格、表头逐字一致、恰 10 条接缝、6 列；全部行回填后为
/// 9 行实测 + 1 行显式缺口（Dynamic Type），不再保留 `pending: 待对应 item 回填`。
final class DocsVerificationMatrixTests: XCTestCase {
    private static let expectedHeader = "| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |"
    private static let pendingMarker = "pending: 待对应 item 回填"
    private static let gapMarker = "缺口"
    private static let expectedSeamCount = 10
    private static let seams = ["后台定位", "锁屏", "重启", "Info.plist", "TTS", "duck", "GPX", "竖屏", "Dynamic Type", "设计 token"]

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
        XCTAssertEqual(lines.count, Self.expectedSeamCount + 2, "必须恰为表头 + 分隔行 + 10 行接缝")

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

    func testMatrixCoversTenSeamsWithNineMeasuredRowsAndOneExplicitGap() throws {
        let dataRows = Array(try nonEmptyLines().dropFirst(2))
        XCTAssertEqual(dataRows.count, Self.expectedSeamCount)

        let pendingRows = dataRows.filter { $0.contains(Self.pendingMarker) }
        XCTAssertEqual(pendingRows.count, 0, "回填后不得再有 pending 行")

        let gapRows = dataRows.filter { $0.contains(Self.gapMarker) }
        XCTAssertEqual(gapRows.count, 1, "Dynamic Type 显式缺口行必须恰为 1 行")

        let measuredRows = dataRows.filter {
            !$0.contains(Self.pendingMarker) && !$0.contains(Self.gapMarker)
        }
        XCTAssertEqual(measuredRows.count, 9, "回填后 9 条接缝必须为实测行")

        let gapRow = gapRows.first
        XCTAssertNotNil(gapRow, "缺少显式缺口行")
        XCTAssertTrue(gapRow?.contains("Dynamic Type") ?? false, "缺口行必须落在 Dynamic Type")
        XCTAssertTrue(gapRow?.contains("缺口：本波未做（预算取舍）") ?? false,
                      "缺口行现状必须写明预算取舍")
        XCTAssertTrue(gapRow?.contains("none（缺口）") ?? false,
                      "缺口行断言名/反例列必须为 none（缺口）")

        for seam in Self.seams {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertNotNil(row, "缺少接缝：\(seam)")
        }

        for seam in Self.seams where seam != "Dynamic Type" {
            let row = dataRows.first { $0.contains(seam) }
            XCTAssertFalse(row?.contains(Self.pendingMarker) ?? true, "\(seam) 已实测，不得标 pending")
            XCTAssertFalse(row?.contains(Self.gapMarker) ?? true, "\(seam) 已实测，不得含缺口标记")
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
