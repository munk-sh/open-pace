import Foundation
import PurePaceRunCore

/// 诊断区唯一数据快照：全部字段来自既有单一来源，不新建第二套计时或采样账本。
///
/// - 版本 / 构建 sha：来自已装包 `Info.plist`（构建期写入，运行时绝不再读 git）。
/// - 授权 / 精度：来自系统授权探针。
/// - 采样数 / 最近样本时间：来自编排器的归档采样序列（与结束页同口径）。
/// - raw / 精度过滤丢弃：来自定位源计数器；50m 阈值室内可能全部滤掉，必须可归因。
/// - 定位服务 / 最近错误：来自定位源 `start()` 前置检查与 `didFailWithError` 转发。
struct RunDiagnostics: Equatable, Sendable {
    let version: String
    let buildSHA: String
    let authorization: RunLocationAuthorization
    let accuracy: RunLocationAccuracy
    let sampleCount: Int
    let lastSampleAt: Date?
    let allowsBackgroundLocationUpdates: Bool
    let rawCallbackCount: Int
    let filteredCallbackCount: Int
    let locationServicesEnabled: Bool
    let lastError: RunLocationErrorInfo?

    init(
        bundleInfo: BundleInfoProviding,
        authorization: RunLocationAuthorization,
        accuracy: RunLocationAccuracy,
        sampleCount: Int,
        lastSampleAt: Date?,
        allowsBackgroundLocationUpdates: Bool,
        rawCallbackCount: Int,
        filteredCallbackCount: Int,
        locationServicesEnabled: Bool = true,
        lastError: RunLocationErrorInfo? = nil
    ) {
        let info = bundleInfo.infoDictionary
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "-"
        let buildNumber = info["CFBundleVersion"] as? String ?? "-"
        let sha = info["PurePaceBuildSHA"] as? String ?? ""
        self.version = buildNumber == "-" ? shortVersion : "\(shortVersion) (\(buildNumber))"
        // 构建期只写前 8 位；缺失时显式写「未注入」，不伪装成真实 sha。
        self.buildSHA = sha.isEmpty ? "未注入" : String(sha.prefix(8))
        self.authorization = authorization
        self.accuracy = accuracy
        self.sampleCount = sampleCount
        self.lastSampleAt = lastSampleAt
        self.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
        self.rawCallbackCount = rawCallbackCount
        self.filteredCallbackCount = filteredCallbackCount
        self.locationServicesEnabled = locationServicesEnabled
        self.lastError = lastError
    }

    /// 一键复制/导出的纯文本（中文标签与可见文案语义一致，不含命令）。
    var text: String {
        [
            "\(L10n.settingsDiagnosticsVersionText): \(version)",
            "\(L10n.settingsDiagnosticsBuildText): \(buildSHA)",
            "\(L10n.settingsDiagnosticsAuthorizationText): \(authorization.diagnosticText)",
            "\(L10n.settingsDiagnosticsAccuracyText): \(accuracy.diagnosticText)",
            "\(L10n.settingsDiagnosticsServicesText): \(locationServicesEnabled ? "开启" : "关闭")",
            "\(L10n.settingsDiagnosticsSamplesText): \(sampleCount)",
            "\(L10n.settingsDiagnosticsLastSampleText): \(Self.timeText(lastSampleAt))",
            "\(L10n.settingsDiagnosticsBackgroundText): \(allowsBackgroundLocationUpdates ? "是" : "否")",
            "\(L10n.settingsDiagnosticsRawCallbacksText): \(rawCallbackCount)",
            "\(L10n.settingsDiagnosticsDroppedCallbacksText): \(filteredCallbackCount)",
            "\(L10n.settingsDiagnosticsLastErrorText): \(lastError?.diagnosticText ?? "无")",
        ].joined(separator: "\n")
    }

    private static func timeText(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
extension RunLocationAuthorization {
    /// 诊断区中文口径（与 `RunLocationReadiness` 的用户文案语义一致）。
    var diagnosticText: String {
        switch self {
        case .notDetermined: return "未决定"
        case .restricted: return "受限"
        case .denied: return "已拒绝"
        case .authorizedWhenInUse: return "仅前台"
        case .authorizedAlways: return "始终允许"
        }
    }
}

extension RunLocationAccuracy {
    var diagnosticText: String {
        switch self {
        case .full: return "精确"
        case .reduced: return "仅大致位置"
        }
    }
}
