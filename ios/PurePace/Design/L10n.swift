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
    static var runStatusSaved: LocalizedStringKey { LocalizedStringKey("run.status.saved") }
    static var runActionStart: LocalizedStringKey { LocalizedStringKey("run.action.start") }
    static var runActionPause: LocalizedStringKey { LocalizedStringKey("run.action.pause") }
    static var runActionResume: LocalizedStringKey { LocalizedStringKey("run.action.resume") }
    static var runActionFinish: LocalizedStringKey { LocalizedStringKey("run.action.finish") }
    static var runActionViewHistory: LocalizedStringKey { LocalizedStringKey("run.action.viewHistory") }
    static var runStartLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.startRecording") }
    static var runPauseLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.pauseRecording") }
    static var runResumeLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.resumeRecording") }
    static var runFinishLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.finishAndSave") }
    static var runViewHistoryLabel: LocalizedStringKey { LocalizedStringKey("run.a11y.viewHistory") }

    /// 授权提示是需要拼接进 `String?` 的纯文本。
    static var locationDenied: String {
        String(localized: "run.status.locationDenied")
    }

    static var waitingAuthorization: String {
        String(localized: "run.status.waitingAuthorization")
    }

    static var backgroundDegradedHint: String {
        String(localized: "run.location.backgroundDegradedHint")
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
    static var runDetailExportLabel: LocalizedStringKey { LocalizedStringKey("runDetail.export.label") }
    static var runDetailShareLabel: LocalizedStringKey { LocalizedStringKey("runDetail.export.shareLabel") }

    // MARK: - 设置页

    static var settingsNavigationTitle: LocalizedStringKey { LocalizedStringKey("settings.navigation.title") }
    static var settingsAnnouncementTitle: LocalizedStringKey { LocalizedStringKey("settings.announcement.title") }
    static var settingsAnnouncementBody: LocalizedStringKey { LocalizedStringKey("settings.announcement.body") }
    static var settingsSectionAnnouncement: LocalizedStringKey { LocalizedStringKey("settings.section.announcement") }
    static var settingsFooterAnnouncement: LocalizedStringKey { LocalizedStringKey("settings.footer.announcement") }
}
