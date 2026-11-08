import AVFoundation
import Foundation
import PurePaceRunCore

/// 播报命令的投递接缝；测试用 spy 断言投递次数与顺序。
protocol AnnouncementSpeaking: AnyObject {
    func speak(_ command: AnnouncementCommand)
}

/// 最小语音合成接缝：一次 `speak` + 结束/取消回调，生产实现包装 `AVSpeechSynthesizer`。
protocol SpeechSynthesizing: AnyObject {
    func speak(_ text: String, onFinish: @escaping (_ cancelled: Bool) -> Void)
}

/// 生产实现：把一条短句交给系统合成器，并在结束或取消时回调。
final class AVSpeechSynthesizing: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: ((Bool) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: @escaping (_ cancelled: Bool) -> Void) {
        self.onFinish = onFinish
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(cancelled: false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(cancelled: true)
    }

    private func finish(cancelled: Bool) {
        let callback = onFinish
        onFinish = nil
        callback?(cancelled)
    }
}

/// 播报文案的纯函数：只依赖 Foundation，不写进 `RunCore`。
enum AnnouncementText {
    static func sentence(for command: AnnouncementCommand) -> String {
        let totalSeconds = max(0, Int(command.elapsed.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "已完成第 \(command.splitIndex) 公里，用时 \(String(format: "%02d:%02d", minutes, seconds))"
    }
}

/// 真实播报器：每条命令固定「激活会话 → 一次合成 → 结束/取消后停用会话」。
///
/// 关闭开关由编排器保证命令不再下发；本类型只对重复投递的同一条命令去重，
/// 不自建公里判定、计时或调度规则。会话调用失败被吞掉，不打断跑次。
final class SpeechAnnouncementSpeaker: AnnouncementSpeaking {
    private struct CommandKey: Hashable {
        let trigger: AnnouncementTrigger
        let splitIndex: Int
    }

    private let audioSession: AudioSessionAdapter
    private let injectedSynthesizer: SpeechSynthesizing?
    private lazy var synthesizer: SpeechSynthesizing = injectedSynthesizer ?? AVSpeechSynthesizing()
    private let text: (AnnouncementCommand) -> String
    private var lastDelivered: CommandKey?

    init(
        audioSession: AudioSessionAdapter = AudioSessionAdapter(),
        synthesizer: SpeechSynthesizing? = nil,
        text: @escaping (AnnouncementCommand) -> String = AnnouncementText.sentence(for:)
    ) {
        self.audioSession = audioSession
        self.injectedSynthesizer = synthesizer
        self.text = text
    }

    func speak(_ command: AnnouncementCommand) {
        let key = CommandKey(trigger: command.trigger, splitIndex: command.splitIndex)
        guard lastDelivered != key else { return }
        lastDelivered = key

        do {
            try audioSession.beginAnnouncement()
        } catch {
            // 会话激活失败不打断跑次；合成结束后停用调用仍由协调器按真实状态幂等处理。
        }

        synthesizer.speak(text(command)) { [weak self] _ in
            try? self?.audioSession.endAnnouncement()
        }
    }
}
