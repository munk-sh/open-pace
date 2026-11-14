import XCTest
@testable import PurePace

final class PrivacyPolicyDocumentTests: XCTestCase {
    private enum DocError: Error {
        case repoRootNotFound
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
        throw DocError.repoRootNotFound
    }

    private func sourceMarkdown() throws -> String {
        let url = try repoRoot().appendingPathComponent("docs/privacy/privacy-policy-zh-Hans.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 真源按二级标题切分为 10 个必需条目，顺序与正文一致。
    func testParsesRequiredSectionsFromRealSource() throws {
        let document = PrivacyPolicyDocument(markdown: try sourceMarkdown())
        XCTAssertEqual(
            document.sections.map(\.title),
            ["采集项", "用途", "权限清单", "存储与保留", "共享", "删除", "撤回同意", "未成年人", "联系方式", "生效日期"]
        )
        XCTAssertTrue(
            document.sections.allSatisfy { !$0.body.isEmpty },
            "每个必需条目都必须有正文"
        )
    }

    func testSectionBodyExcludesHeading() {
        let document = PrivacyPolicyDocument(
            markdown: "# 标题\n\n## 采集项\n\n第一行\n第二行\n\n## 用途\n\n只在本机"
        )
        XCTAssertEqual(document.sections.count, 2)
        XCTAssertEqual(document.sections[0].title, "采集项")
        XCTAssertEqual(document.sections[0].body, "第一行\n第二行")
        XCTAssertEqual(document.sections[1].body, "只在本机")
    }

    func testEmptyMarkdownHasNoSections() {
        XCTAssertTrue(PrivacyPolicyDocument(markdown: "").sections.isEmpty)
        XCTAssertTrue(PrivacyPolicyDocument(markdown: "# 只有一级标题").sections.isEmpty)
    }

    /// bundle 副本与 docs 真源逐字节一致（手工改副本 / 漂移即判红）。
    func testBundleCopyMatchesSourceBytes() throws {
        let root = try repoRoot()
        let source = try Data(contentsOf: root.appendingPathComponent("docs/privacy/privacy-policy-zh-Hans.md"))
        let bundleCopy = try Data(contentsOf: root.appendingPathComponent("ios/PurePace/Resources/privacy-policy-zh-Hans.md"))
        XCTAssertEqual(source, bundleCopy, "bundle 副本必须与 docs 真源逐字节一致")
    }

    /// 真源渲染文本必须含同意屏/政策页语义关键词。
    func testSourceContainsConsentSemantics() throws {
        let text = try sourceMarkdown()
        for keyword in ["敏感个人信息", "不出本机", "撤回同意"] {
            XCTAssertTrue(text.contains(keyword), "政策正文缺少关键词：\(keyword)")
        }
    }
}
