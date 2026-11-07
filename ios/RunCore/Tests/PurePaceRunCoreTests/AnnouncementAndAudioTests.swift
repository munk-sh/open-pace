import XCTest
import PurePaceRunCore

final class AnnouncementAndAudioTests: XCTestCase {
    func testAnnouncementTriggerCases() {
        XCTAssertEqual(
            AnnouncementTrigger.allCases,
            [.kilometerCompleted, .resumedAfterPause, .finished]
        )
        XCTAssertEqual(AnnouncementTrigger.kilometerCompleted.rawValue, "kilometerCompleted")
        XCTAssertEqual(AnnouncementTrigger.resumedAfterPause.rawValue, "resumedAfterPause")
        XCTAssertEqual(AnnouncementTrigger.finished.rawValue, "finished")
    }

    func testAnnouncementCommandValidation() {
        guard
            let distance = RunDistance(meters: 1000),
            let pace = RunPace(secondsPerKilometer: 300)
        else {
            return XCTFail("合法距离/配速不应为 nil")
        }

        let command = AnnouncementCommand(
            trigger: .kilometerCompleted,
            splitIndex: 1,
            distance: distance,
            pace: pace,
            elapsed: 300
        )
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.trigger, .kilometerCompleted)
        XCTAssertEqual(command?.splitIndex, 1)
        XCTAssertEqual(command?.distance, distance)
        XCTAssertEqual(command?.pace, pace)
        XCTAssertEqual(command?.elapsed, 300)

        XCTAssertNil(AnnouncementCommand(trigger: .finished, splitIndex: 0, distance: distance, pace: pace, elapsed: 300))
        XCTAssertNil(AnnouncementCommand(trigger: .finished, splitIndex: -1, distance: distance, pace: pace, elapsed: 300))
        XCTAssertNil(AnnouncementCommand(trigger: .finished, splitIndex: 1, distance: distance, pace: pace, elapsed: -1))
        XCTAssertNil(AnnouncementCommand(trigger: .finished, splitIndex: 1, distance: distance, pace: pace, elapsed: .infinity))

        let zeroElapsed = AnnouncementCommand(trigger: .resumedAfterPause, splitIndex: 2, distance: distance, pace: pace, elapsed: 0)
        XCTAssertNotNil(zeroElapsed)
    }

    func testAudioEnumCases() {
        XCTAssertEqual(AudioCategoryOption.allCases.count, 4)
        XCTAssertTrue(AudioCategoryOption.allCases.contains(.mixWithOthers))
        XCTAssertTrue(AudioCategoryOption.allCases.contains(.duckOthers))
        XCTAssertTrue(AudioCategoryOption.allCases.contains(.interruptSpokenAudioAndMixWithOthers))
        XCTAssertTrue(AudioCategoryOption.allCases.contains(.allowBluetoothA2DP))
        XCTAssertEqual(AudioCategoryOption.duckOthers.rawValue, "duckOthers")

        XCTAssertTrue(AudioCategory.allCases.contains(.playback))
        XCTAssertTrue(AudioCategory.allCases.contains(.playAndRecord))
        XCTAssertTrue(AudioMode.allCases.contains(.spokenAudio))
        XCTAssertEqual(AudioMode.default.rawValue, "default")
    }

    func testAudioSessionSettingsKeepsSetsAndEquality() {
        let settings = AudioSessionSettings(
            category: .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .mixWithOthers],
            deactivationOptions: [.mixWithOthers]
        )
        XCTAssertEqual(settings.category, .playback)
        XCTAssertEqual(settings.mode, .spokenAudio)
        XCTAssertEqual(settings.options, Set([AudioCategoryOption.duckOthers, .mixWithOthers]))
        XCTAssertEqual(settings.deactivationOptions, Set([AudioCategoryOption.mixWithOthers]))

        XCTAssertEqual(
            settings,
            AudioSessionSettings(
                category: .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .duckOthers],
                deactivationOptions: [.mixWithOthers]
            )
        )
        XCTAssertNotEqual(
            settings,
            AudioSessionSettings(
                category: .playback,
                mode: .spokenAudio,
                options: [.duckOthers],
                deactivationOptions: [.mixWithOthers]
            )
        )
        XCTAssertNotEqual(
            settings,
            AudioSessionSettings(
                category: .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers],
                deactivationOptions: [.mixWithOthers]
            )
        )
    }
}
