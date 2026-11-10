import AVFoundation
import Foundation
import PurePaceRunCore
import XCTest
@testable import PurePace

/// 记录下发到平台层的调用序列，替代真实 `AVAudioSession`。
private final class AudioSessionSpy: AudioSessionControlling {
    struct CategoryCall: Equatable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    struct ActivationCall: Equatable {
        let active: Bool
        let options: AVAudioSession.SetActiveOptions
    }

    private(set) var categoryCalls: [CategoryCall] = []
    private(set) var activationCalls: [ActivationCall] = []

    var category: AVAudioSession.Category = .ambient
    var mode: AVAudioSession.Mode = .default
    var categoryOptions: AVAudioSession.CategoryOptions = []
    var isOtherAudioPlaying: Bool = false
    var secondaryAudioShouldBeSilencedHint: Bool = false
    /// 仅停用调用（`active == false`）抛错的注入点，用于复现真机上的迟到失败分支。
    var deactivationError: Error?

    var activations: [ActivationCall] { activationCalls.filter(\.active) }
    var deactivations: [ActivationCall] { activationCalls.filter { !$0.active } }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        categoryCalls.append(CategoryCall(category: category, mode: mode, options: options))
        self.category = category
        self.mode = mode
        self.categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activationCalls.append(ActivationCall(active: active, options: options))
        if !active, let deactivationError {
            throw deactivationError
        }
    }
}

/// 只记录、不落盘的诊断接缝默认值：普通用例不触碰真实容器 Documents。
private final class DiagnosticsSpy: AnnouncementDeactivationDiagnosing {
    private(set) var outcomes: [AnnouncementDeactivationOutcome] = []

    func record(_ outcome: AnnouncementDeactivationOutcome) {
        outcomes.append(outcome)
    }
}

/// 断言诊断文件 JSON 结构（ac-diagnostics-schema）的解码模型。
private struct DiagnosticsDocument: Decodable {
    struct Entry: Decodable {
        let splitIndex: Int
        let occurredAt: Double
        let outcome: String
        let errorDomain: String?
        let errorCode: Int?
        let coordinatorStateBefore: String
        let coordinatorStateAfter: String
        let platformCallIssued: Bool
    }

    let version: Int
    let outcomes: [Entry]
}

private func diagnosticsFileURL(in directory: URL) -> URL {
    directory.appendingPathComponent(
        AnnouncementDeactivationDiagnosticsFile.relativePath,
        isDirectory: false
    )
}

/// App 数据容器的 Documents 目录：即生产默认诊断落盘根，也是 `devicectl --domain-type
/// appDataContainer` 拉取路径的根。
private func appContainerDiagnosticsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
}

private func readDiagnostics(in directory: URL) throws -> DiagnosticsDocument {
    try JSONDecoder().decode(
        DiagnosticsDocument.self,
        from: Data(contentsOf: diagnosticsFileURL(in: directory))
    )
}

private final class SpeechSynthesizerSpy: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    private(set) var startedCount = 0
    private var onStart: (() -> Void)?
    private var onFinish: ((Bool) -> Void)?

    func speak(
        _ text: String,
        onStart: @escaping () -> Void,
        onFinish: @escaping (_ cancelled: Bool) -> Void
    ) {
        spoken.append(text)
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func start() {
        startedCount += 1
        let callback = onStart
        onStart = nil
        callback?()
    }

    func finish(cancelled: Bool = false) {
        let callback = onFinish
        onFinish = nil
        callback?(cancelled)
    }
}

final class AnnouncementSpeakerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOneSpeakPerDeliveredCommandWithKilometerIndex() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)
        let command = makeCommand(splitIndex: 1)

        speaker.speak(command)
        speaker.speak(command)

        XCTAssertEqual(synthesizer.spoken.count, 1)
        XCTAssertTrue(synthesizer.spoken[0].contains("第 1 公里"))
        XCTAssertTrue(synthesizer.spoken[0].contains("05:30"))
    }

    func testSessionSequenceActivatesSpeaksThenDeactivatesOnFinish() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)

        speaker.speak(makeCommand(splitIndex: 2))

        XCTAssertEqual(
            session.categoryCalls,
            [
                AudioSessionSpy.CategoryCall(
                    category: .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers, .mixWithOthers]
                )
            ]
        )
        XCTAssertEqual(session.activations.count, 1)
        XCTAssertEqual(session.activations.first?.options, [])
        XCTAssertEqual(synthesizer.spoken.count, 1)
        XCTAssertTrue(session.deactivations.isEmpty)

        synthesizer.finish()

        XCTAssertEqual(session.deactivations.count, 1)
        XCTAssertEqual(session.deactivations.first?.options, [.notifyOthersOnDeactivation])
    }

    func testCancelledSpeechStillDeactivatesOnce() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)

        speaker.speak(makeCommand(splitIndex: 3))
        synthesizer.finish(cancelled: true)
        synthesizer.finish(cancelled: true)

        XCTAssertEqual(session.activations.count, 1)
        XCTAssertEqual(session.deactivations.count, 1)
    }

    func testNoCommandProducesNoAudioSessionCalls() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        _ = makeSpeaker(session: session, synthesizer: synthesizer)

        XCTAssertTrue(session.categoryCalls.isEmpty)
        XCTAssertTrue(session.activationCalls.isEmpty)
        XCTAssertTrue(synthesizer.spoken.isEmpty)
    }

    func testDistinctSplitIndexesSpeakAgain() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer)

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.finish()
        speaker.speak(makeCommand(splitIndex: 2))

        XCTAssertEqual(synthesizer.spoken.count, 2)
        XCTAssertTrue(synthesizer.spoken[1].contains("第 2 公里"))
    }

    // MARK: - 音频遥测自证

    func testTelemetryRecordsDuckContractStartFinishAndDeactivation() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer, telemetry: recorder)

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(synthesizer.startedCount, 1, "起始回调必须被调用")
        let entries = recorder.snapshot()
        XCTAssertEqual(entries.count, 1)
        guard let entry = entries.first else { return }
        XCTAssertEqual(entry.splitIndex, 1)
        XCTAssertTrue(entry.text.contains("第 1 公里"))
        XCTAssertEqual(entry.category, "playback")
        XCTAssertEqual(entry.mode, "spokenAudio")
        XCTAssertTrue(entry.categoryOptions.contains("duckOthers"))
        XCTAssertTrue(entry.sessionActivated, "起播时下发了会话激活")
        XCTAssertTrue(entry.sessionDeactivated, "结束后恰好一次会话停用")
        XCTAssertTrue(entry.duckRevoked, "结束后 duck 撤销")
        XCTAssertFalse(entry.cancelled)
        XCTAssertNotNil(entry.finishedAt)
        XCTAssertLessThanOrEqual(entry.startedAt, entry.finishedAt ?? .greatestFiniteMagnitude)
    }

    func testTelemetryMarksCancelledButStillDeactivates() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer, telemetry: recorder)

        speaker.speak(makeCommand(splitIndex: 2))
        synthesizer.start()
        synthesizer.finish(cancelled: true)

        let entries = recorder.snapshot()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.cancelled, true)
        XCTAssertEqual(entries.first?.sessionDeactivated, true)
        XCTAssertEqual(session.deactivations.count, 1)
    }

    // MARK: - 停用边界：true / 中断 / 抛错三分支

    /// 机制① A 成功路径：协调器保持 `.active` 时结束播报，派生值唯一来自真实平台调用；
    /// 正常路径平台调用次数不变（`[true, false]` / 停用 1 次），诊断文件不新增记录。
    func testActiveSessionDeactivationWritesTrueDerivationsAndSinglePlatformCall() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let diagnosticsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("announcement-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: diagnosticsDirectory) }
        let adapter = AudioSessionAdapter(controller: session, observesInterruptions: false)
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder,
            diagnostics: AnnouncementDeactivationDiagnosticsFile(directoryURL: diagnosticsDirectory)
        )

        speaker.speak(makeCommand(splitIndex: 1))
        XCTAssertEqual(adapter.state, .active)
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(adapter.state, .inactive)
        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, false],
            "didFinish 后必须恰好下发一次 setActive(false)"
        )
        XCTAssertEqual(
            session.activationCalls.map(\.options),
            [[], [.notifyOthersOnDeactivation]],
            "激活不带选项、停用携带 notify 选项"
        )

        guard let entry = recorder.snapshot().first else {
            return XCTFail("缺少播报遥测条目")
        }
        XCTAssertTrue(entry.sessionActivated)
        XCTAssertTrue(entry.sessionDeactivated)
        XCTAssertTrue(entry.duckRevoked)
        XCTAssertFalse(entry.cancelled)
        XCTAssertNotNil(entry.finishedAt)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: diagnosticsFileURL(in: diagnosticsDirectory).path),
            "成功路径不得写诊断文件"
        )
    }

    /// ac-duck-alias-breaker：激活真实下发 `[.mixWithOthers]`（不含 `.duckOthers`）、停用携带
    /// `.notifyOthersOnDeactivation` 且成功时，两字段必须**分叉**：`sessionDeactivated == true`、
    /// `duckRevoked == false`。把实现改回 `duckRevoked: sessionDeactivated` 后本用例必判红。
    func testDuckRevokedDiffersFromSessionDeactivatedWhenActivationSkipsDuck() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let diagnostics = DiagnosticsSpy()
        let adapter = AudioSessionAdapter(
            controller: session,
            settings: AudioSessionSettings(
                category: .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers],
                deactivationOptions: [.notifyOthersOnDeactivation]
            ),
            observesInterruptions: false
        )
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder,
            diagnostics: diagnostics
        )

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, false],
            "成功路径仍必须真实下发一次停用"
        )
        XCTAssertEqual(adapter.state, .inactive)

        guard let entry = recorder.snapshot().first else {
            return XCTFail("缺少播报遥测条目")
        }
        XCTAssertTrue(entry.sessionActivated)
        XCTAssertTrue(entry.sessionDeactivated, "停用调用真实成功")
        XCTAssertFalse(entry.duckRevoked, "激活未下发 .duckOthers，不得声称撤销了 duck")
        guard case .success = diagnostics.outcomes.first else {
            return XCTFail("成功路径必须落 .success 结果")
        }
        XCTAssertEqual(diagnostics.outcomes.count, 1)
    }

    /// ac-announcement-text-fields：播报文本必须同时含距离、用时、配速三段；前缀逐字保留，
    /// 配速数字口径与 `RunFormatting.paceText` 一致（`m:ss /km`，分钟不补零）。
    func testAnnouncementTextIncludesDistanceElapsedAndPace() {
        let first = AnnouncementCommand(
            trigger: .kilometerCompleted,
            splitIndex: 1,
            distance: RunDistance(meters: 1000)!,
            pace: RunPace(secondsPerKilometer: 300)!,
            elapsed: 330
        )!
        XCTAssertEqual(AnnouncementText.sentence(for: first), "已完成第 1 公里，用时 05:30，配速 5:00 /km")

        let second = AnnouncementCommand(
            trigger: .kilometerCompleted,
            splitIndex: 2,
            distance: RunDistance(meters: 2000)!,
            pace: RunPace(secondsPerKilometer: 285.4)!,
            elapsed: 372
        )!
        XCTAssertEqual(AnnouncementText.sentence(for: second), "已完成第 2 公里，用时 06:12，配速 4:45 /km")
    }

    /// 机制② C `.interrupted` 路径：播报中出现 interruption began，didFinish 时协调器已非
    /// `.active`，`deactivate()` 返回 `.none`，因此没有平台停用调用、两个派生字段均为 false，
    /// 诊断文件新增 1 条 `not-applicable`（而非 `failed`）；随后 `shouldResume == false`
    /// 让状态回到 `.inactive`，下一次播报重新激活。
    func testInterruptionDuringSpeechSuppressesDeactivationThenNextAnnouncementReactivates() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let diagnosticsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("announcement-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: diagnosticsDirectory) }
        let adapter = AudioSessionAdapter(controller: session, observesInterruptions: false)
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder,
            diagnostics: AnnouncementDeactivationDiagnosticsFile(directoryURL: diagnosticsDirectory)
        )

        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.start()
        adapter.handleInterruption(.began)
        XCTAssertEqual(adapter.state, .interrupted)

        synthesizer.finish()

        XCTAssertEqual(adapter.state, .interrupted, "非 active 状态下 deactivate 不改变状态")
        XCTAssertTrue(session.deactivations.isEmpty, "协调器非 active 时不得下发 setActive(false)")

        guard let first = recorder.snapshot().first else {
            return XCTFail("缺少首条播报遥测条目")
        }
        XCTAssertTrue(first.sessionActivated)
        XCTAssertFalse(first.sessionDeactivated)
        XCTAssertFalse(first.duckRevoked)
        XCTAssertFalse(first.cancelled)
        XCTAssertNotNil(first.finishedAt)

        do {
            let document = try readDiagnostics(in: diagnosticsDirectory)
            XCTAssertEqual(document.version, 1)
            XCTAssertEqual(document.outcomes.count, 1, "not-applicable 恰好一条")
            let record = try XCTUnwrap(document.outcomes.first)
            XCTAssertEqual(record.splitIndex, 1)
            XCTAssertEqual(record.outcome, "not-applicable")
            XCTAssertNil(record.errorDomain)
            XCTAssertNil(record.errorCode)
            XCTAssertEqual(record.coordinatorStateBefore, "interrupted")
            XCTAssertEqual(record.coordinatorStateAfter, "interrupted")
            XCTAssertFalse(record.platformCallIssued)
            XCTAssertGreaterThan(record.occurredAt, 0)
            XCTAssertFalse(document.outcomes.contains { $0.outcome == "failed" })
        } catch {
            XCTFail("读取诊断文件失败：\(error)")
        }

        adapter.handleInterruption(.ended(shouldResume: false))
        XCTAssertEqual(adapter.state, .inactive)
        XCTAssertTrue(session.deactivations.isEmpty)

        speaker.speak(makeCommand(splitIndex: 2))
        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, true],
            "上一次结束未下发停用，下一次播报必须重新下发激活"
        )
        XCTAssertEqual(adapter.state, .active)
        guard let second = recorder.snapshot().last else {
            return XCTFail("缺少第二条播报遥测条目")
        }
        XCTAssertTrue(second.sessionActivated)
    }

    /// 机制③ B 抛错路径：`setActive(false)` 抛出时错误向上抛出、`state` 保持 `.active`
    /// （不提交、无重试、无回滚），落盘仍按真实结果写 false/false，并新增一条 `failed`
    /// 诊断记录；下一次播报不再重复激活，但结束仍能真实停用。
    func testThrownDeactivationKeepsActiveStateWritesFailureDiagnosticsAndRetriesNone() {
        let session = AudioSessionSpy()
        let injectedError = NSError(domain: "InjectedAudioErrorDomain", code: 561_017_449)
        session.deactivationError = injectedError
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        // 生产默认落盘位置：App 数据容器 Documents（`appDataContainer` 拉取路径的根）。
        let diagnosticsDirectory = appContainerDiagnosticsDirectory()
        let diagnosticsPath = diagnosticsFileURL(in: diagnosticsDirectory)
        try? FileManager.default.removeItem(at: diagnosticsPath)
        defer { try? FileManager.default.removeItem(at: diagnosticsPath) }
        XCTAssertEqual(
            diagnosticsDirectory,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            "诊断文件必须落在 App 数据容器 Documents 目录"
        )
        let adapter = AudioSessionAdapter(controller: session, observesInterruptions: false)
        let speaker = makeSpeaker(
            adapter: adapter,
            synthesizer: synthesizer,
            telemetry: recorder,
            diagnostics: AnnouncementDeactivationDiagnosticsFile()
        )

        speaker.speak(makeCommand(splitIndex: 1))
        XCTAssertEqual(adapter.state, .active)
        synthesizer.start()
        synthesizer.finish()

        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, false],
            "一次结束路径最多下发一次 setActive(false)"
        )
        XCTAssertEqual(adapter.state, .active, "平台调用失败时不得提交停用状态")

        guard let first = recorder.snapshot().first else {
            return XCTFail("缺少首条播报遥测条目")
        }
        XCTAssertTrue(first.sessionActivated)
        XCTAssertFalse(first.sessionDeactivated)
        XCTAssertFalse(first.duckRevoked)
        XCTAssertFalse(first.cancelled)
        XCTAssertNotNil(first.finishedAt)

        do {
            let document = try readDiagnostics(in: diagnosticsDirectory)
            XCTAssertEqual(document.version, 1)
            XCTAssertEqual(document.outcomes.count, 1, "失败恰好一条诊断记录")
            let record = try XCTUnwrap(document.outcomes.first)
            XCTAssertEqual(record.splitIndex, 1)
            XCTAssertEqual(record.outcome, "failed")
            XCTAssertEqual(record.errorDomain, injectedError.domain)
            XCTAssertEqual(record.errorCode, injectedError.code)
            XCTAssertEqual(record.coordinatorStateBefore, "active")
            XCTAssertEqual(record.coordinatorStateAfter, "active")
            XCTAssertTrue(record.platformCallIssued)
            XCTAssertGreaterThan(record.occurredAt, 0)
        } catch {
            XCTFail("读取诊断文件失败：\(error)")
        }

        // 清除注入错误，验证下一次结束能真实停用成功。
        session.deactivationError = nil
        speaker.speak(makeCommand(splitIndex: 2))
        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, false],
            "协调器仍为 active，下一次播报不再下发 setActive(true)"
        )
        XCTAssertEqual(adapter.state, .active)
        synthesizer.finish()

        XCTAssertEqual(
            session.activationCalls.map(\.active),
            [true, false, false],
            "下一次结束仍真实下发一次停用，且不重新激活"
        )
        XCTAssertEqual(adapter.state, .inactive)
        guard let second = recorder.snapshot().last else {
            return XCTFail("缺少第二条播报遥测条目")
        }
        XCTAssertFalse(second.sessionActivated)
        XCTAssertTrue(second.sessionDeactivated)
        XCTAssertTrue(second.duckRevoked)
    }

    /// ac-diagnostics-file-path：固定相对路径、追加保留历史、损坏文件重置、成功不写。
    func testDiagnosticsFileAppendsOutcomesAtFixedRelativePath() {
        XCTAssertEqual(
            AnnouncementDeactivationDiagnosticsFile.relativePath,
            "Diagnostics/announcement-deactivation.json"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("announcement-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = diagnosticsFileURL(in: directory)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 损坏的历史文件应被重置为空而不是抛错。
        try? Data("not-json".utf8).write(to: fileURL)

        let writer = AnnouncementDeactivationDiagnosticsFile(directoryURL: directory)
        writer.record(.success)
        writer.record(
            .failed(
                splitIndex: 1,
                occurredAt: Date(timeIntervalSince1970: 100),
                error: NSError(domain: "InjectedDomain", code: 7),
                coordinatorStateBefore: .active,
                coordinatorStateAfter: .active,
                platformCallIssued: true
            )
        )
        writer.record(
            .notApplicable(
                splitIndex: 2,
                occurredAt: Date(timeIntervalSince1970: 200),
                coordinatorStateBefore: .interrupted,
                coordinatorStateAfter: .interrupted
            )
        )

        do {
            let document = try readDiagnostics(in: directory)
            XCTAssertEqual(document.version, 1)
            XCTAssertEqual(document.outcomes.map(\.outcome), ["failed", "not-applicable"])
            XCTAssertEqual(document.outcomes.map(\.splitIndex), [1, 2])
            XCTAssertEqual(document.outcomes[0].occurredAt, 100, accuracy: 0.001)
            XCTAssertEqual(document.outcomes[1].occurredAt, 200, accuracy: 0.001)
        } catch {
            XCTFail("读取诊断文件失败：\(error)")
        }
    }

    /// ac-derived-fields-provenance：音频环境布尔在 `beginAnnouncement` 之后实时读取，
    /// 注入两组相反值都应原样落入遥测，证明未被写死或复用旧快照。
    func testAnnouncementContextPassesThroughInjectedAudioEnvironmentBooleans() {
        let session = AudioSessionSpy()
        let synthesizer = SpeechSynthesizerSpy()
        let recorder = AnnouncementTelemetryRecorder()
        let speaker = makeSpeaker(session: session, synthesizer: synthesizer, telemetry: recorder)

        session.isOtherAudioPlaying = true
        session.secondaryAudioShouldBeSilencedHint = true
        speaker.speak(makeCommand(splitIndex: 1))
        synthesizer.finish()

        session.isOtherAudioPlaying = false
        session.secondaryAudioShouldBeSilencedHint = false
        speaker.speak(makeCommand(splitIndex: 2))
        synthesizer.finish()

        let entries = recorder.snapshot()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].isOtherAudioPlaying, true)
        XCTAssertEqual(entries[0].secondaryAudioShouldBeSilencedHint, true)
        XCTAssertEqual(entries[1].isOtherAudioPlaying, false)
        XCTAssertEqual(entries[1].secondaryAudioShouldBeSilencedHint, false)
    }

    // MARK: - helpers

    private func makeSpeaker(
        session: AudioSessionSpy,
        synthesizer: SpeechSynthesizerSpy,
        telemetry: AnnouncementTelemetryRecording? = nil,
        diagnostics: AnnouncementDeactivationDiagnosing = DiagnosticsSpy(),
        now: @escaping () -> Date = { Date() }
    ) -> SpeechAnnouncementSpeaker {
        makeSpeaker(
            adapter: AudioSessionAdapter(controller: session, observesInterruptions: false),
            synthesizer: synthesizer,
            telemetry: telemetry,
            diagnostics: diagnostics,
            now: now
        )
    }

    private func makeSpeaker(
        adapter: AudioSessionAdapter,
        synthesizer: SpeechSynthesizerSpy,
        telemetry: AnnouncementTelemetryRecording? = nil,
        diagnostics: AnnouncementDeactivationDiagnosing = DiagnosticsSpy(),
        now: @escaping () -> Date = { Date() }
    ) -> SpeechAnnouncementSpeaker {
        SpeechAnnouncementSpeaker(
            audioSession: adapter,
            synthesizer: synthesizer,
            telemetry: telemetry,
            diagnostics: diagnostics,
            now: now
        )
    }

    private func makeCommand(splitIndex: Int) -> AnnouncementCommand {
        AnnouncementCommand(
            trigger: .kilometerCompleted,
            splitIndex: splitIndex,
            distance: RunDistance(meters: Double(splitIndex) * 1000)!,
            pace: RunPace(secondsPerKilometer: 330)!,
            elapsed: TimeInterval(splitIndex) * 330
        )!
    }
}
