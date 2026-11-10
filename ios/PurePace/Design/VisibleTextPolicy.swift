import Foundation

/// 可见文案的 zh-Hans 白名单判定（纯函数）。
/// 除 `km` / `/km` / `GPX` / `PurePace` 等专有名词与单位外，任何 ASCII 字母都视为裸英文。
/// 单测用固定列表证明可通过，并用英文反例证明能红；UI 用例把真实可及树喂给同一判定。
enum VisibleTextPolicy {
    /// 允许出现在用户可见文案里的拉丁字母片段（单位 / 格式名 / 产品名）。
    static let allowedLatinTokens = ["/km", "km", "GPX", "PurePace"]

    static func isAllowed(_ text: String) -> Bool {
        var remainder = text
        for token in allowedLatinTokens {
            remainder = remainder.replacingOccurrences(of: token, with: "")
        }
        return remainder.range(of: "[A-Za-z]", options: .regularExpression) == nil
    }

    /// 返回所有含裸英文的文案；空数组表示全部通过。
    static func violations(in texts: [String]) -> [String] {
        texts.filter { !isAllowed($0) }
    }
}
