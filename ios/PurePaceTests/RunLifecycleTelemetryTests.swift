import Foundation
import PurePaceRunCore
import UIKit
import XCTest
@testable import PurePace

final class RunLifecycleTelemetryTests: XCTestCase {
    private let t0: TimeInterval = 1_700_000_000

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - ac-telemetry-event-names / ac-telemetry-event-order-and-time

    func testRecorderCapturesFourNotificationsInArrivalOrderWithInjectedClock() {
        let center = NotificationCenter()
        let clock = MutableClock(date: Date(timeIntervalSince1970: t0))
        let box = RunLifecycleSnapshotBox()
        let recorder = RunLifecycleTelemetryRecorder(
            center: center,
            now: { clock.date },
            snapshotProvider: { box.read() }
        )

        let steps: [(Notification.Name, RunLifecycleSnapshot)] = [
            (UIApplication.protectedDataWillBecomeUnavailableNotification, snapshot(samples: 3, distance: 12, elapsed: 4)),
            (UIApplication.protectedDataDidBecomeAvailableNotification, snapshot(samples: 7, distance: 30, elapsed: 9)),
            (UIApplication.didEnterBackgroundNotification, snapshot(samples: 9, distance: 45, elapsed: 13)),
            (UIApplication.willEnterForegroundNotification, snapshot(samples: 12, distance: 60, elapsed: 18))
        ]
        for (index, step) in steps.enumerated() {
            clock.date = Date(timeIntervalSince1970: t0 + Double(index))
            box.update(step.1)
            center.post(name: step.0, object: nil)
        }

        XCTAssertEqual(
            recorder.events.map(\.name),
            [
                "protectedDataWillBecomeUnavailable",
                "protectedDataDidBecomeAvailable",
                "didEnterBackground",
                "willEnterForeground"
            ]
        )
        XCTAssertEqual(
            recorder.events.map(\.at),
            [
                "2023-11-14T22:13:20Z",
                "2023-11-14T22:13:21Z",
                "2023-11-14T22:13:22Z",
                "2023-11-14T22:13:23Z"
            ]
        )
        let formatter = ISO8601DateFormatter()
        for event in recorder.events {
            XCTAssertNotNil(formatter.date(from: event.at), "at 必须是可解析的 UTC ISO8601")
        }
    }

    // MARK: - ac-telemetry-event-snapshot

    func testRecorderUsesSnapshotAtEachEventMoment() {
        let center = NotificationCenter()
        let clock = MutableClock(date: Date(timeIntervalSince1970: t0))
        let box = RunLifecycleSnapshotBox()
        let recorder = RunLifecycleTelemetryRecorder(
            center: center,
            now: { clock.date },
            snapshotProvider: { box.read() }
        )

        let counts = [3, 7, 9, 12]
        let notifications = [
            UIApplication.protectedDataWillBecomeUnavailableNotification,
            UIApplication.protectedDataDidBecomeAvailableNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willEnterForegroundNotification
        ]
        for (index, count) in counts.enumerated() {
            box.update(snapshot(samples: count, distance: Double(count) * 5, elapsed: Double(count) + 1))
            center.post(name: notifications[index], object: nil)
        }

        XCTAssertEqual(recorder.events.map(\.sampleCount), counts)
        XCTAssertEqual(recorder.events.map(\.distanceMeters), [15, 35, 45, 60])
        XCTAssertEqual(recorder.events.map(\.elapsedSeconds), [4, 8, 10, 13])
    }

    // MARK: - ac-telemetry-events-fields / ac-telemetry-additive-no-behavior-change

    func testWriterPersistsEventsWithFixedFieldNamesAndTypes() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = makeRecord()
        let url = try store.save(record)
        let events = [
            RunLifecycleEvent(
                name: "didEnterBackground",
                at: "2023-11-14T22:13:20Z",
                sampleCount: 3,
                distanceMeters: 12.5,
                elapsedSeconds: 7
            )
        ]

        try RunTelemetryWriter(directoryURL: store.directoryURL).inject(
            telemetry: makeTelemetry(events: events),
            sources: [:],
            recordID: record.id,
            defaultSource: .device
        )

        let telemetry = try XCTUnwrap(readJSON(url)["telemetry"] as? [String: Any])
        let rawEvents = try XCTUnwrap(telemetry["events"] as? [[String: Any]])
        XCTAssertEqual(rawEvents.count, 1)
        let event = try XCTUnwrap(rawEvents.first)
        XCTAssertEqual(event["name"] as? String, "didEnterBackground")
        XCTAssertEqual(event["at"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(event["sampleCount"] as? Int, 3)
        XCTAssertEqual((event["distanceMeters"] as? NSNumber)?.doubleValue, 12.5)
        XCTAssertEqual((event["elapsedSeconds"] as? NSNumber)?.doubleValue, 7)
    }

    func testWriterWritesEmptyEventsAndKeepsExistingTelemetryKeys() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = makeRecord()
        let url = try store.save(record)

        try RunTelemetryWriter(directoryURL: store.directoryURL).inject(
            telemetry: makeTelemetry(events: []),
            sources: [:],
            recordID: record.id,
            defaultSource: .device
        )

        let telemetry = try XCTUnwrap(readJSON(url)["telemetry"] as? [String: Any])
        XCTAssertEqual((telemetry["events"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(
            (telemetry["authorizationStatus"] as? [String: Any])?["name"] as? String,
            "authorizedAlways"
        )
        XCTAssertEqual(telemetry["allowsBackgroundLocationUpdates"] as? Bool, true)
        XCTAssertEqual(telemetry["pausesLocationUpdatesAutomatically"] as? Bool, false)
        XCTAssertEqual((telemetry["announcements"] as? [[String: Any]])?.count, 0)
    }

    // MARK: - ac-bundle-self-report

    func testBundleSelfReportFromInjectedInfoDictionary() {
        let bundle = RunTelemetryBundle(
            infoDictionary: [
                "UIBackgroundModes": ["location", "audio"],
                "CFBundleIdentifier": "sh.munk.purepace",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1"
            ]
        )

        XCTAssertEqual(bundle.backgroundModes, ["location", "audio"])
        XCTAssertEqual(bundle.identifier, "sh.munk.purepace")
        XCTAssertEqual(bundle.shortVersion, "0.1.0")
        XCTAssertEqual(bundle.buildVersion, "1")
    }

    func testBundleSelfReportFromRunningMainBundle() {
        let bundle = RunTelemetryBundle(
            infoDictionary: SystemBundleInfoProvider().infoDictionary
        )

        XCTAssertEqual(bundle.identifier, "sh.munk.purepace")
        XCTAssertTrue(bundle.backgroundModes.contains("location"))
        XCTAssertTrue(bundle.backgroundModes.contains("audio"))
        XCTAssertEqual(bundle.shortVersion, "0.1.0")
        XCTAssertEqual(bundle.buildVersion, "1")
    }

    func testWriterPersistsBundleSelfReport() throws {
        let (root, store) = makeStores()
        defer { try? FileManager.default.removeItem(at: root) }

        let record = makeRecord()
        let url = try store.save(record)
        let bundle = RunTelemetryBundle(
            infoDictionary: [
                "UIBackgroundModes": ["location", "audio"],
                "CFBundleIdentifier": "sh.munk.purepace",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1"
            ]
        )

        try RunTelemetryWriter(directoryURL: store.directoryURL).inject(
            telemetry: makeTelemetry(events: [], bundle: bundle),
            sources: [:],
            recordID: record.id,
            defaultSource: .device
        )

        let telemetry = try XCTUnwrap(readJSON(url)["telemetry"] as? [String: Any])
        let rawBundle = try XCTUnwrap(telemetry["bundle"] as? [String: Any])
        XCTAssertEqual(rawBundle["backgroundModes"] as? [String], ["location", "audio"])
        XCTAssertEqual(rawBundle["identifier"] as? String, "sh.munk.purepace")
        XCTAssertEqual(rawBundle["shortVersion"] as? String, "0.1.0")
        XCTAssertEqual(rawBundle["buildVersion"] as? String, "1")
    }

    // MARK: - 夹具

    private final class MutableClock: @unchecked Sendable {
        var date: Date

        init(date: Date) {
            self.date = date
        }
    }

    private func snapshot(
        samples: Int,
        distance: Double,
        elapsed: TimeInterval
    ) -> RunLifecycleSnapshot {
        RunLifecycleSnapshot(
            sampleCount: samples,
            distanceMeters: distance,
            elapsedSeconds: elapsed
        )
    }

    private func makeTelemetry(
        events: [RunLifecycleEvent],
        bundle: RunTelemetryBundle = RunTelemetryBundle(infoDictionary: [:])
    ) -> RunTelemetry {
        RunTelemetry(
            authorizationStatus: RunTelemetryAuthorization(name: "authorizedAlways", rawValue: 3),
            accuracyAuthorization: RunTelemetryAuthorization(name: "full", rawValue: 0),
            allowsBackgroundLocationUpdates: true,
            pausesLocationUpdatesAutomatically: false,
            announcements: [],
            events: events,
            bundle: bundle
        )
    }

    private func makeStores() -> (root: URL, store: RunArchiveStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurePaceLifecycle-\(UUID().uuidString)", isDirectory: true)
        return (
            root,
            RunArchiveStore(directoryURL: root.appendingPathComponent("Runs", isDirectory: true))
        )
    }

    private func makeRecord() -> RunRecord {
        RunRecord(
            startedAt: Date(timeIntervalSince1970: t0),
            endedAt: Date(timeIntervalSince1970: t0 + 10),
            distance: RunDistance(meters: 100)!,
            activeDuration: 10,
            splits: [],
            samples: []
        )!
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "RunLifecycleTelemetryTests", code: 1)
        }
        return json
    }
}
