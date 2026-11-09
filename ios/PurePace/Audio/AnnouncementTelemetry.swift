import Foundation

/// 播报时刻的音频环境快照：下发到平台层的会话配置 + 两个只读音频环境布尔。
struct AnnouncementAudioContext: Equatable, Sendable {
    let category: String
    let mode: String
    let categoryOptions: [String]
    let isOtherAudioPlaying: Bool
    let secondaryAudioShouldBeSilencedHint: Bool
    let sessionActivated: Bool
}

/// 播报遥测接缝：`SpeechAnnouncementSpeaker` 在起始/回调时写入，跑次结束导出。
protocol AnnouncementTelemetryRecording: AnyObject {
    func recordStarted(
        splitIndex: Int,
        text: String,
        startedAt: Date,
        context: AnnouncementAudioContext
    )
    func recordSpeechDidStart(splitIndex: Int, startedAt: Date)
    func recordFinished(
        splitIndex: Int,
        finishedAt: Date,
        cancelled: Bool,
        sessionDeactivated: Bool,
        duckRevoked: Bool
    )
    func snapshot() -> [RunTelemetryAnnouncement]
}

/// 线程安全的进程内播报遥测累积器。
///
/// 只累积事实，不做去重或调度；结束导出为 `telemetry.announcements[]`。
final class AnnouncementTelemetryRecorder: AnnouncementTelemetryRecording {
    private let lock = NSLock()
    private var entries: [RunTelemetryAnnouncement] = []

    func recordStarted(
        splitIndex: Int,
        text: String,
        startedAt: Date,
        context: AnnouncementAudioContext
    ) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(
            RunTelemetryAnnouncement(
                splitIndex: splitIndex,
                text: text,
                startedAt: startedAt.timeIntervalSince1970,
                finishedAt: nil,
                cancelled: false,
                category: context.category,
                mode: context.mode,
                categoryOptions: context.categoryOptions,
                isOtherAudioPlaying: context.isOtherAudioPlaying,
                secondaryAudioShouldBeSilencedHint: context.secondaryAudioShouldBeSilencedHint,
                sessionActivated: context.sessionActivated,
                sessionDeactivated: false,
                duckRevoked: false
            )
        )
    }

    func recordSpeechDidStart(splitIndex: Int, startedAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = lastIndex(for: splitIndex, unfinished: true) else { return }
        let entry = entries[index]
        entries[index] = RunTelemetryAnnouncement(
            splitIndex: entry.splitIndex,
            text: entry.text,
            startedAt: startedAt.timeIntervalSince1970,
            finishedAt: entry.finishedAt,
            cancelled: entry.cancelled,
            category: entry.category,
            mode: entry.mode,
            categoryOptions: entry.categoryOptions,
            isOtherAudioPlaying: entry.isOtherAudioPlaying,
            secondaryAudioShouldBeSilencedHint: entry.secondaryAudioShouldBeSilencedHint,
            sessionActivated: entry.sessionActivated,
            sessionDeactivated: entry.sessionDeactivated,
            duckRevoked: entry.duckRevoked
        )
    }

    func recordFinished(
        splitIndex: Int,
        finishedAt: Date,
        cancelled: Bool,
        sessionDeactivated: Bool,
        duckRevoked: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        let finishedAtValue = finishedAt.timeIntervalSince1970
        guard let index = lastIndex(for: splitIndex, unfinished: true) else {
            // 起始回调缺失时的兜底：仍记录一条完整条目，避免遥测缺口。
            entries.append(
                RunTelemetryAnnouncement(
                    splitIndex: splitIndex,
                    text: "",
                    startedAt: finishedAtValue,
                    finishedAt: finishedAtValue,
                    cancelled: cancelled,
                    category: "",
                    mode: "",
                    categoryOptions: [],
                    isOtherAudioPlaying: false,
                    secondaryAudioShouldBeSilencedHint: false,
                    sessionActivated: false,
                    sessionDeactivated: sessionDeactivated,
                    duckRevoked: duckRevoked
                )
            )
            return
        }
        let entry = entries[index]
        entries[index] = RunTelemetryAnnouncement(
            splitIndex: entry.splitIndex,
            text: entry.text,
            startedAt: entry.startedAt,
            finishedAt: finishedAtValue,
            cancelled: cancelled,
            category: entry.category,
            mode: entry.mode,
            categoryOptions: entry.categoryOptions,
            isOtherAudioPlaying: entry.isOtherAudioPlaying,
            secondaryAudioShouldBeSilencedHint: entry.secondaryAudioShouldBeSilencedHint,
            sessionActivated: entry.sessionActivated,
            sessionDeactivated: sessionDeactivated,
            duckRevoked: duckRevoked
        )
    }

    func snapshot() -> [RunTelemetryAnnouncement] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    private func lastIndex(for splitIndex: Int, unfinished: Bool) -> Int? {
        for index in entries.indices.reversed() {
            let entry = entries[index]
            guard entry.splitIndex == splitIndex else { continue }
            guard !unfinished || entry.finishedAt == nil else { continue }
            return index
        }
        return nil
    }
}
