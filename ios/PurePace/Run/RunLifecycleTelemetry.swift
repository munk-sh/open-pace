import Foundation
import SwiftUI

/// 锁屏/前后台事件发生当刻的跑次快照。
struct RunLifecycleSnapshot: Equatable, Sendable {
    let sampleCount: Int
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval

    static let zero = RunLifecycleSnapshot(sampleCount: 0, distanceMeters: 0, elapsedSeconds: 0)
}

/// 单条锁屏/前后台事件：事件名 + UTC ISO8601 时刻 + 当刻快照。
struct RunLifecycleEvent: Codable, Equatable, Sendable {
    let name: String
    let at: String
    let sampleCount: Int
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
}

/// 进程内事件累积接缝：跑次结束导出为 `telemetry.events[]`。
protocol RunLifecycleTelemetryRecording: AnyObject {
    var events: [RunLifecycleEvent] { get }
}

/// 线程安全的锁屏/前后台事件记录器。
///
/// 只观察四条 `UIApplication` 通知并追加事实，不改变会话状态、不驱动定位；
/// App 启动即注册，`deinit` 移除观察者。时刻格式固定为 UTC ISO8601（秒级）。
final class RunLifecycleTelemetryRecorder: RunLifecycleTelemetryRecording, @unchecked Sendable {
    private static let observedNotifications: [(name: String, notification: Notification.Name)] = [
        (
            "protectedDataWillBecomeUnavailable",
            UIApplication.protectedDataWillBecomeUnavailableNotification
        ),
        // UIKit 只有「DidBecomeAvailable」通知（无 DidBecomeUnavailable），按系统实际 API 记录。
        (
            "protectedDataDidBecomeAvailable",
            UIApplication.protectedDataDidBecomeAvailableNotification
        ),
        ("didEnterBackground", UIApplication.didEnterBackgroundNotification),
        ("willEnterForeground", UIApplication.willEnterForegroundNotification)
    ]

    private let lock = NSLock()
    private var entries: [RunLifecycleEvent] = []
    private let center: NotificationCenter
    private let now: @Sendable () -> Date
    private let snapshotProvider: @Sendable () -> RunLifecycleSnapshot
    private var tokens: [NSObjectProtocol] = []

    init(
        center: NotificationCenter = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        snapshotProvider: @escaping @Sendable () -> RunLifecycleSnapshot = { .zero }
    ) {
        self.center = center
        self.now = now
        self.snapshotProvider = snapshotProvider
        for entry in Self.observedNotifications {
            let name = entry.name
            let token = center.addObserver(
                forName: entry.notification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.record(name: name)
            }
            tokens.append(token)
        }
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }

    var events: [RunLifecycleEvent] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    private func record(name: String) {
        let at = Self.iso8601String(from: now())
        let snapshot = snapshotProvider()
        let event = RunLifecycleEvent(
            name: name,
            at: at,
            sampleCount: snapshot.sampleCount,
            distanceMeters: snapshot.distanceMeters,
            elapsedSeconds: snapshot.elapsedSeconds
        )
        lock.lock()
        entries.append(event)
        lock.unlock()
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// 跑次快照的线程安全中转盒：通知回调线程读取，主线程状态变化时写入。
final class RunLifecycleSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = RunLifecycleSnapshot.zero

    func update(_ snapshot: RunLifecycleSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    func read() -> RunLifecycleSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
