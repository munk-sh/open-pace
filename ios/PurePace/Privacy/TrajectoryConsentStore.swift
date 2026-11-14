import Foundation
import SwiftUI

/// 轨迹（敏感个人信息）单独同意的单键持久化：默认未同意，写入即经同一 `UserDefaults` 键回读。
/// 同意态只落在这一处；类型外不得再散落键名字面量。
@MainActor
final class TrajectoryConsentStore: ObservableObject {
    /// 唯一同意键；类型外不得再散落字面量。
    static let consentKey = "privacy.trajectoryConsent.v1"

    @Published private(set) var hasConsented: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasConsented = defaults.bool(forKey: Self.consentKey)
    }

    func grant() {
        setConsented(true)
    }

    func revoke() {
        setConsented(false)
    }

    func setConsented(_ consented: Bool) {
        guard hasConsented != consented else { return }
        hasConsented = consented
        defaults.set(consented, forKey: Self.consentKey)
    }

    /// 仅 DEBUG UI 用例：按启动参数预置或清空同意记录。
    static func applyUITestArguments(
        _ arguments: [String],
        defaults: UserDefaults = .standard
    ) {
        #if DEBUG
        if arguments.contains(RunLaunchArguments.uiTestResetConsentFlag) {
            defaults.removeObject(forKey: consentKey)
            return
        }
        if arguments.contains(RunLaunchArguments.uiTestConsentGrantedFlag) {
            defaults.set(true, forKey: consentKey)
        }
        #endif
    }
}
