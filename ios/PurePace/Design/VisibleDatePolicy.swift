import Foundation

/// 日期文案的 zh-Hans 判定（纯函数）：只接受「2025年10月9日 16:53」形态，
/// 且不得出现任何拉丁字母（英文月份、`at`、AM/PM 均因此被拒绝）。
enum VisibleDatePolicy {
    /// 中文日期时间：年月日 + 24 小时制分钟（详情可再带秒）。
    static let zhHansPattern = #"^\d{4}年\d{1,2}月\d{1,2}日 \d{2}:\d{2}(:\d{2})?$"#

    static func isZhHansDateTime(_ text: String) -> Bool {
        guard text.range(of: zhHansPattern, options: .regularExpression) != nil else {
            return false
        }
        return text.range(of: "[A-Za-z]", options: .regularExpression) == nil
    }
}
