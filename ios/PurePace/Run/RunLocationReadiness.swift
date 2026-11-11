import Foundation

/// 定位可用性的可恢复判定：把「权限被拒」与「定位不可用」拆成两种状态，
/// 各自只带一个明确的下一步动作，视图按 readiness 渲染而不是拼一句合并提示。
enum RunLocationReadiness: String, Equatable, Sendable {
    /// 已授权，定位就绪。
    case ready
    /// 尚未决定，等待系统授权弹窗（沿用既有提示键）。
    case awaitingAuthorization
    /// 用户拒绝授权，下一步只能去系统设置。
    case permissionDenied
    /// 系统层面定位不可用（如家长控制/设备策略），下一步是重试。
    case unavailable

    /// 下一步动作；`nil` 表示当前没有需要用户点按的恢复动作。
    enum NextAction: String, Equatable, Sendable {
        case openSettings
        case retry
    }

    init(authorization: RunLocationAuthorization) {
        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            self = .ready
        case .notDetermined:
            self = .awaitingAuthorization
        case .denied:
            self = .permissionDenied
        case .restricted:
            self = .unavailable
        }
    }

    var nextAction: NextAction? {
        switch self {
        case .permissionDenied:
            return .openSettings
        case .unavailable:
            return .retry
        case .ready, .awaitingAuthorization:
            return nil
        }
    }

    /// 提示文案在 String Catalog 中的键；`nil` 表示就绪无提示。
    var messageKey: String? {
        switch self {
        case .ready:
            return nil
        case .awaitingAuthorization:
            return "run.status.waitingAuthorization"
        case .permissionDenied:
            return "run.status.locationDenied"
        case .unavailable:
            return "run.status.locationUnavailable"
        }
    }

    /// 经 `L10n` 类型化入口取到的可读文案。
    var message: String? {
        switch self {
        case .ready:
            return nil
        case .awaitingAuthorization:
            return L10n.waitingAuthorization
        case .permissionDenied:
            return L10n.locationDenied
        case .unavailable:
            return L10n.locationUnavailable
        }
    }
}
