import Foundation

/// 应用内政策正文的只读模型：由同步脚本从 docs 真源复制的 bundle 文本按 Markdown
/// 二级标题切分为章节块，视图只负责渲染，不在 Swift 里重复写正文。
struct PrivacyPolicyDocument: Equatable {
    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let body: String
    }

    /// bundle 内正文副本的资源名（与 scripts/sync-privacy-policy.sh 的产物同名）。
    static let resourceName = "privacy-policy-zh-Hans"
    static let resourceExtension = "md"

    let sections: [Section]

    /// 从 Markdown 文本切分章节：`## 标题` 起一段，正文为标题到下一个二级标题之间的文本。
    init(markdown: String) {
        var sections: [Section] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            guard let title = currentTitle else { return }
            let body = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(Section(id: title, title: title, body: body))
            currentLines = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }
        flush()
        self.sections = sections
    }

    /// 从 bundle 读取正文副本；资源缺失或为空时返回 `nil`（视图给明确占位，不静默成功）。
    static func load(bundle: Bundle = .main) -> PrivacyPolicyDocument? {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ),
        let text = try? String(contentsOf: url, encoding: .utf8),
        !text.isEmpty else {
            return nil
        }
        return PrivacyPolicyDocument(markdown: text)
    }
}
