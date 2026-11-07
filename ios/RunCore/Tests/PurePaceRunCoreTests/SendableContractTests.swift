import XCTest
import PurePaceRunCore

/// 编译期契约：公开类型必须满足 `Sendable`（Swift 6 严格并发）。
private func requireSendable<T: Sendable>(_: T.Type) {}

final class SendableContractTests: XCTestCase {
    func testPublicContractTypesAreSendable() {
        requireSendable(RunSessionState.self)
        requireSendable(RunDistance.self)
        requireSendable(RunPace.self)
        requireSendable(RunSample.self)
        requireSendable(RunSplit.self)
        requireSendable(AnnouncementTrigger.self)
        requireSendable(AnnouncementCommand.self)
        requireSendable(AudioCategory.self)
        requireSendable(AudioMode.self)
        requireSendable(AudioCategoryOption.self)
        requireSendable(AudioSessionSettings.self)
        requireSendable(RunCoreError.self)
    }
}
