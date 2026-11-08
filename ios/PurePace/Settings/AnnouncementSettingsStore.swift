import Foundation
import SwiftUI

/// 单点持久化的每公里播报偏好：默认开启，写入即经同一 `UserDefaults` 键回读。
@MainActor
final class AnnouncementSettingsStore: ObservableObject {
    /// 唯一偏好键；类型外不得再散落字面量。
    static let enabledKey = "announcements.kilometerEnabled"

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
}
