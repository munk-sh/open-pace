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

extension RunLocationReadiness {
    /// 叠加定位链路故障后的最终状态：系统定位服务关闭或最近一次系统定位失败
    /// 一律落到既有 `.unavailable`（文案「定位暂不可用，请重试」+ retry 出口），
    /// 不静默当成「等待首条样本」。
    static func resolve(
        authorization: RunLocationAuthorization,
        servicesEnabled: Bool,
        lastErrorCode: Int?
    ) -> RunLocationReadiness {
        guard servicesEnabled, lastErrorCode == nil else { return .unavailable }
        return RunLocationReadiness(authorization: authorization)
    }
}

/// 记录态「零可用 fix」的搜索阶段：先定性为搜索中，30 秒到点按可归因原因给出重试。
///
/// 与 `RunLocationReadiness` 职责不同——后者描述「能不能采」，本类型描述
/// 「进入记录态后是否收到了可用 fix」。两者都不新建计时真源。
enum RunLocationSearchState: Equatable, Sendable {
    /// 已拿到可用 fix，或不在记录态。
    case idle
    /// 记录态 30 秒内仍无任何可用 fix。
    case searching
    /// 记录态 30 秒到点仍无可用 fix，按原因给出可读文案 + 重试入口。
    case timedOut(RunLocationSearchFailureReason)

    /// 记录态搜索窗口（秒）。
    ///
    /// 推导（先定后测，禁止红了再调）：真机首次定位在开阔地通常 1–5s，室内/电梯
    /// 遮挡常见 10–25s；30s 足够覆盖「走出遮挡后恢复」，又不让用户长时间面对
    /// 「计时在走、距离不动且没有任何解释」。
    static let timeoutSeconds: TimeInterval = 30

    var isTimedOut: Bool {
        if case .timedOut = self { return true }
        return false
    }

    /// 唯一派生入口：全部输入来自既有定位源计数器 / 授权 / 服务开关与会话时钟。
    static func resolve(
        isRunning: Bool,
        hasLocationData: Bool,
        elapsedSinceRecording: TimeInterval,
        authorization: RunLocationAuthorization,
        servicesEnabled: Bool,
        rawCallbackCount: Int,
        filteredCallbackCount: Int,
        timeout: TimeInterval = RunLocationSearchState.timeoutSeconds
    ) -> RunLocationSearchState {
        guard isRunning, !hasLocationData else { return .idle }
        guard elapsedSinceRecording >= timeout else { return .searching }
        if !authorization.isAuthorized {
            return .timedOut(.unauthorized)
        }
        if !servicesEnabled {
            return .timedOut(.servicesDisabled)
        }
        if rawCallbackCount > 0, filteredCallbackCount >= rawCallbackCount {
            return .timedOut(.accuracyFiltered)
        }
        return .timedOut(.noCallbacks)
    }
}

/// 搜索超时的可归因原因（只四类，不引入「系统限制」兜底）。
enum RunLocationSearchFailureReason: String, Equatable, Sendable {
    case unauthorized
    case servicesDisabled
    case accuracyFiltered
    case noCallbacks

    /// 30 秒到点后展示的可读原因。
    var message: String {
        switch self {
        case .unauthorized:
            return L10n.runLocationSearchUnauthorized
        case .servicesDisabled:
            return L10n.runLocationSearchServicesDisabled
        case .accuracyFiltered:
            return L10n.runLocationSearchAccuracyFiltered
        case .noCallbacks:
            return L10n.runLocationSearchNoCallbacks
        }
    }
}
