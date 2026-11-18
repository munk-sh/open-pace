import SwiftUI

/// 全仓唯一本地化键入口：视图只引用本枚举，真实文案在
/// `Resources/Localizable.xcstrings`（sourceLanguage = zh-Hans）。
/// 本地化键与 `accessibilityIdentifier` 解耦，既有 identifier 一律不改名。
enum L10n {
    // MARK: - Tab

    static var tabRun: LocalizedStringKey { LocalizedStringKey("tab.run.title") }
    static var tabHistory: LocalizedStringKey { LocalizedStringKey("tab.history.title") }
    static var tabSettings: LocalizedStringKey { LocalizedStringKey("tab.settings.title") }

    // MARK: - 跑步页

    static var runNavigationTitle: LocalizedStringKey { LocalizedStringKey("run.navigation.title") }
    static var runMetricDistance: LocalizedStringKey { LocalizedStringKey("run.metric.distance") }
    static var runMetricTime: LocalizedStringKey { LocalizedStringKey("run.metric.time") }
    static var runMetricCurrent: LocalizedStringKey { LocalizedStringKey("run.metric.current") }
    static var runMetricAverage: LocalizedStringKey { LocalizedStringKey("run.metric.average") }
    static var runMetricSplits: LocalizedStringKey { LocalizedStringKey("run.metric.splits") }
    static var runMetricSamples: LocalizedStringKey { LocalizedStringKey("run.metric.samples") }
    static var runMetricPoints: LocalizedStringKey { LocalizedStringKey("run.metric.points") }
    static var runStatusSaved: LocalizedStringKey { LocalizedStringKey("run.status.saved") }
    static var runActionStart: LocalizedStringKey { LocalizedStringKey("run.action.start") }
    static var runActionPause: LocalizedStringKey { LocalizedStringKey("run.action.pause") }
    static var runActionResume: LocalizedStringKey { LocalizedStringKey("run.action.resume") }
    static var runActionFinish: LocalizedStringKey { LocalizedStringKey("run.action.finish") }
    static var runActionCancel: LocalizedStringKey { LocalizedStringKey("run.action.cancel") }
    static var runActionSave: LocalizedStringKey { LocalizedStringKey("run.action.save") }
    static var runActionDiscard: LocalizedStringKey { LocalizedStringKey("run.action.discard") }
    static var runActionOpenSettings: LocalizedStringKey { LocalizedStringKey("run.action.openSettings") }
    static var runActionRetryLocation: LocalizedStringKey { LocalizedStringKey("run.action.retryLocation") }
    static var runForegroundOnlyHint: LocalizedStringKey { LocalizedStringKey("run.status.foregroundOnly") }
    static var runActionViewHistory: LocalizedStringKey { LocalizedStringKey("run.action.viewHistory") }
    static var runStartLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.startRecording") }
    static var runPauseLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.pauseRecording") }
    static var runResumeLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.resumeRecording") }
    static var runFinishLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.finishAndSave") }
    static var runCancelCountdownLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.cancelCountdown") }
    static var runSaveLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.saveRun") }
    static var runDiscardLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.discardRun") }
    static var runDiscardConfirmTitle: LocalizedStringKey { LocalizedStringKey("run.discardConfirm.title") }
    static var runDiscardConfirmMessage: LocalizedStringKey { LocalizedStringKey("run.discardConfirm.message") }
    static var runDiscardConfirmConfirm: LocalizedStringKey { LocalizedStringKey("run.discardConfirm.confirm") }
    static var runDiscardConfirmCancel: LocalizedStringKey { LocalizedStringKey("run.discardConfirm.cancel") }
    static var runViewHistoryLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.viewHistory") }

    // MARK: - 轨迹地图

    static var runMapEmptyTitle: LocalizedStringKey { LocalizedStringKey("run.map.empty.title") }
    static var runMapEmptyBody: LocalizedStringKey { LocalizedStringKey("run.map.empty.body") }
    static var runMapSingleTitle: LocalizedStringKey { LocalizedStringKey("run.map.single.title") }
    static var runMapSingleBody: LocalizedStringKey { LocalizedStringKey("run.map.single.body") }
    static var runMapPreviewLabel: LocalizedStringKey { LocalizedStringKey("run.map.preview.label") }
    static var runSplitsDetailTitle: LocalizedStringKey { LocalizedStringKey("run.splits.detail.title") }
    static var runFinishedSplitsEmpty: LocalizedStringKey { LocalizedStringKey("run.finished.splits.empty") }

    /// 授权提示是需要拼接进 `String?` 的纯文本。
    static var locationDenied: String {
        String(localized: "run.status.locationDenied")
    }

    static var waitingAuthorization: String {
        String(localized: "run.status.waitingAuthorization")
    }

    static var locationUnavailable: String {
        String(localized: "run.status.locationUnavailable")
    }

    /// 保存失败提示：zh-Hans 可读文案 + 重试语义，不回显英文错误描述。
    static var saveFailed: String {
        String(localized: "run.status.saveFailed")
    }

    static var backgroundDegradedHint: String {
        String(localized: "run.location.backgroundDegradedHint")
    }

    /// 单行紧凑胶囊的短文案；完整长句仍作为该胶囊的 accessibilityLabel。
    static var backgroundDegradedHintShort: String {
        String(localized: "run.location.backgroundDegradedHintShort")
    }

    // MARK: - 历史页

    static var historyNavigationTitle: LocalizedStringKey { LocalizedStringKey("history.navigation.title") }
    static var historyEmptyTitle: LocalizedStringKey { LocalizedStringKey("history.empty.title") }
    static var historyEmptyBody: LocalizedStringKey { LocalizedStringKey("history.empty.body") }
    static var historyRunAgain: LocalizedStringKey { LocalizedStringKey("history.empty.action") }

    // MARK: - 跑次详情

    static var runDetailNavigationTitle: LocalizedStringKey { LocalizedStringKey("runDetail.navigation.title") }
    static var runDetailFieldStart: LocalizedStringKey { LocalizedStringKey("runDetail.field.start") }
    static var runDetailFieldEnd: LocalizedStringKey { LocalizedStringKey("runDetail.field.end") }
    static var runDetailFieldDistance: LocalizedStringKey { LocalizedStringKey("runDetail.field.distance") }
    static var runDetailFieldActiveDuration: LocalizedStringKey { LocalizedStringKey("runDetail.field.activeDuration") }
    static var runDetailFieldAveragePace: LocalizedStringKey { LocalizedStringKey("runDetail.field.averagePace") }
    static var runDetailSplitsEmpty: LocalizedStringKey { LocalizedStringKey("runDetail.splits.empty") }
    static var runDetailExportButton: LocalizedStringKey { LocalizedStringKey("runDetail.export.button") }
    static var runDetailExportSection: LocalizedStringKey { LocalizedStringKey("runDetail.export.section") }
    static var runDetailExportFooter: LocalizedStringKey { LocalizedStringKey("runDetail.export.footer") }
    static var runDetailExported: LocalizedStringKey { LocalizedStringKey("runDetail.export.exported") }
    static var runDetailShare: LocalizedStringKey { LocalizedStringKey("runDetail.export.share") }
    static var runDetailExportFailed: LocalizedStringKey { LocalizedStringKey("runDetail.export.failed") }
    static var runDetailExportEmptySamples: LocalizedStringKey { LocalizedStringKey("runDetail.export.emptySamples") }
    static var runDetailExportEmptyLabel: LocalizedStringKey { LocalizedStringKey("runDetail.export.emptyLabel") }
    static var runDetailExportLabel: LocalizedStringKey { LocalizedStringKey("runDetail.export.label") }
    static var runDetailShareLabel: LocalizedStringKey { LocalizedStringKey("runDetail.export.shareLabel") }

    // MARK: - 设置页

    static var settingsNavigationTitle: LocalizedStringKey { LocalizedStringKey("settings.navigation.title") }
    static var settingsAnnouncementTitle: LocalizedStringKey { LocalizedStringKey("settings.announcement.title") }
    static var settingsAnnouncementBody: LocalizedStringKey { LocalizedStringKey("settings.announcement.body") }
    static var settingsSectionAnnouncement: LocalizedStringKey { LocalizedStringKey("settings.section.announcement") }
    static var settingsFooterAnnouncement: LocalizedStringKey { LocalizedStringKey("settings.footer.announcement") }
    static var settingsSectionDiagnostics: LocalizedStringKey { LocalizedStringKey("settings.section.diagnostics") }
    static var settingsDiagnosticsCopy: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.copy") }
    static var settingsDiagnosticsCopied: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.copied") }
    static var settingsDiagnosticsVersion: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.version") }
    static var settingsDiagnosticsBuild: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.build") }
    static var settingsDiagnosticsAuthorization: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.authorization") }
    static var settingsDiagnosticsAccuracy: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.accuracy") }
    static var settingsDiagnosticsSamples: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.samples") }
    static var settingsDiagnosticsLastSample: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.lastSample") }
    static var settingsDiagnosticsBackground: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.background") }
    static var settingsDiagnosticsRawCallbacks: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.rawCallbacks") }
    static var settingsDiagnosticsDroppedCallbacks: LocalizedStringKey { LocalizedStringKey("settings.diagnostics.droppedCallbacks") }

    // 诊断纯文本（复制/导出）用 String 变体，避免 LocalizedStringKey 被插入字符串。
    static var settingsDiagnosticsVersionText: String { String(localized: "settings.diagnostics.version") }
    static var settingsDiagnosticsBuildText: String { String(localized: "settings.diagnostics.build") }
    static var settingsDiagnosticsAuthorizationText: String { String(localized: "settings.diagnostics.authorization") }
    static var settingsDiagnosticsAccuracyText: String { String(localized: "settings.diagnostics.accuracy") }
    static var settingsDiagnosticsSamplesText: String { String(localized: "settings.diagnostics.samples") }
    static var settingsDiagnosticsLastSampleText: String { String(localized: "settings.diagnostics.lastSample") }
    static var settingsDiagnosticsBackgroundText: String { String(localized: "settings.diagnostics.background") }
    static var settingsDiagnosticsRawCallbacksText: String { String(localized: "settings.diagnostics.rawCallbacks") }
    static var settingsDiagnosticsDroppedCallbacksText: String { String(localized: "settings.diagnostics.droppedCallbacks") }

    // MARK: - 隐私与同意

    static var consentGateTitle: LocalizedStringKey { LocalizedStringKey("consent.gate.title") }
    static var consentGateBody: LocalizedStringKey { LocalizedStringKey("consent.gate.body") }
    static var consentGateAgree: LocalizedStringKey { LocalizedStringKey("consent.gate.agree") }
    static var consentGateDecline: LocalizedStringKey { LocalizedStringKey("consent.gate.decline") }
    static var settingsSectionAbout: LocalizedStringKey { LocalizedStringKey("settings.section.about") }
    static var settingsPrivacyPolicyTitle: LocalizedStringKey { LocalizedStringKey("settings.privacyPolicy.title") }
    static var settingsPrivacyPolicyBody: LocalizedStringKey { LocalizedStringKey("settings.privacyPolicy.body") }
    static var settingsConsentStatus: LocalizedStringKey { LocalizedStringKey("settings.consent.status") }
    static var settingsConsentRevoke: LocalizedStringKey { LocalizedStringKey("settings.consent.revoke") }
    static var privacyPolicyNavigationTitle: LocalizedStringKey { LocalizedStringKey("privacyPolicy.navigation.title") }
    static var privacyPolicyUnavailable: LocalizedStringKey { LocalizedStringKey("privacyPolicy.unavailable") }

    /// 无任何定位采样时的距离位文案（拼接进 `String` 的纯文本）。
    static var runDistanceUnavailable: String {
        String(localized: "run.distance.unavailable")
    }

    /// 记录态首条 fix 未到时的内联提示。
    static var runWaitingLocation: String {
        String(localized: "run.waiting.location")
    }

    /// 降级接受低精度 fix 时的明确精度提示。
    static var runDegradedAccuracy: String {
        String(localized: "run.location.degradedAccuracy")
    }

    /// 未同意时记录入口被禁用的原因文案（拼接进 `String?` 的纯文本）。
    static var runConsentRequired: String {
        String(localized: "run.consent.required")
    }
}
