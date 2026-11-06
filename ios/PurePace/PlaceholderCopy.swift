import Foundation

/// 空壳占位页的静态文案与 Tab 定义。
/// 只承载展示文本，不含任何跑步业务逻辑或样例数据。
enum PlaceholderCopy {
    static let appName = "PurePace"
    static let tagline = "Your pace, purely yours."
}

enum PlaceholderTab: String, CaseIterable, Identifiable {
    case run
    case history
    case log
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .history: "History"
        case .log: "Log"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .run: "figure.run"
        case .history: "clock.arrow.circlepath"
        case .log: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}
