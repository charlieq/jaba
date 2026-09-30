import BackgroundTasks
import Foundation
import JABAKit
import UserNotifications

/// Turns forecasts into local notifications.
///
/// Time-based notifications are scheduled for the start of each GO window, so
/// they fire on time even if iOS never wakes the app in the night. Each refresh
/// (foreground or background) rebuilds them from the latest forecast, and alerts
/// immediately if a window has already started or NOAA's nowcast shows aurora in view.
///
/// Runs off the main actor: notification-center calls are synchronous XPC under the
/// hood, and a stalled notification service must not freeze the UI.
nonisolated final class AlertScheduler: Sendable {
    private var center: UNUserNotificationCenter { .current() }
    private var defaults: UserDefaults { .standard }

    private static let prefix = "jaba.alert."
    /// Alert id → fire time for every alert JABA has scheduled or sent. Kept here
    /// rather than asking the notification center, so rescheduling never waits on it.
    private static let recordKey = "jaba.alertRecord"
    /// Alert this long before a window opens, to allow time to get dressed.
    static let leadTime: TimeInterval = 10 * 60
    /// Nowcast probability (%) within view that triggers a "look now" alert.
    static let nowcastThreshold = 30

    @concurrent func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Cancels every JABA alert that hasn't fired yet.
    @concurrent func removeAll(now: Date = .now) async {
        cancelPending(now: now)
    }

    private func cancelPending(now: Date) {
        var record = loadRecord()
        let pending = record.filter { $0.value > now.timeIntervalSince1970 }.map(\.key)
        guard !pending.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for id in pending { record[id] = nil }
        defaults.set(record, forKey: Self.recordKey)
    }

    @concurrent func sync(_ items: [(SavedLocation, AuroraOutlook)], includeMaybe: Bool, now: Date = .now) async {
        // Pending alerts are rebuilt from the latest forecast; what's left in the record has already fired.
        cancelPending(now: now)
        var fired = loadRecord().filter { $0.value > now.timeIntervalSince1970 - 3 * 86_400 }
        var requests: [UNNotificationRequest] = []

        for (location, outlook) in items {
            for night in outlook.nights {
                guard night.verdict == .go || (includeMaybe && night.verdict == .maybe),
                      let window = night.bestWindow, let best = night.best
                else { continue }
                let id = "\(Self.prefix)\(location.id.uuidString).\(Int(night.window.start.timeIntervalSince1970))"
                guard fired[id] == nil else { continue }

                let content = windowContent(location: location, outlook: outlook, night: night, best: best, window: window)
                let fireDate = window.start.addingTimeInterval(-Self.leadTime)
                if fireDate > now.addingTimeInterval(60) {
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSince(now), repeats: false)
                    requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    fired[id] = fireDate.timeIntervalSince1970
                } else if window.end > now {
                    requests.append(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                    fired[id] = now.timeIntervalSince1970
                }
            }

            if let nowcast = outlook.nowcast, let current = outlook.current,
               current.darkness.isDark, current.sky != .overcast,
               nowcast.inViewProbability >= Self.nowcastThreshold {
                let id = "\(Self.prefix)now.\(location.id.uuidString).\(Int(outlook.tonight.window.start.timeIntervalSince1970))"
                if fired[id] == nil {
                    requests.append(UNNotificationRequest(
                        identifier: id,
                        content: nowcastContent(location: location, nowcast: nowcast, current: current),
                        trigger: nil
                    ))
                    fired[id] = now.timeIntervalSince1970
                }
            }
        }

        defaults.set(fired, forKey: Self.recordKey)
        for request in requests {
            try? await center.add(request)
        }
    }

    private func loadRecord() -> [String: Double] {
        defaults.dictionary(forKey: Self.recordKey) as? [String: Double] ?? [:]
    }

    private func windowContent(
        location: SavedLocation, outlook: AuroraOutlook, night: NightReport,
        best: HourAssessment, window: DateInterval
    ) -> UNNotificationContent {
        let tz = outlook.timeZone
        let kp = best.kp.map { "Kp \(AuroraFormat.kp($0))" } ?? "Kp ?"
        let cloud = best.cloudCover.map { "\(AuroraFormat.percent($0)) cloud" } ?? "cloud unknown"
        let content = UNMutableNotificationContent()
        content.threadIdentifier = location.id.uuidString
        content.sound = .default
        if night.verdict == .go {
            content.title = "\(location.name): GO for aurora (\(night.score))"
            content.body = "Best \(AuroraFormat.timeRange(window.start, window.end, in: tz)): \(kp), \(cloud). Get out of the tent!"
        } else {
            content.title = "\(location.name): MAYBE (\(night.score))"
            content.body = "Photo check around \(AuroraFormat.time(best.time, in: tz)): \(kp), \(cloud). Point your camera north."
        }
        return content
    }

    private func nowcastContent(location: SavedLocation, nowcast: Nowcast, current: HourAssessment) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = location.id.uuidString
        content.sound = .default
        content.title = "\(location.name): aurora may be showing now"
        let sky = current.cloudCover.map { "\(AuroraFormat.percent($0)) cloud" } ?? "unknown cloud"
        content.body = "NOAA's 30-minute model shows a \(nowcast.inViewProbability)% chance within view, with \(sky). Take a look north."
        return content
    }
}

enum BackgroundRefresh {
    static let identifier = "com.charlieq.jaba.refresh"

    /// Asks iOS to wake the app in about 30 minutes. iOS decides the real timing.
    /// Fails harmlessly where background refresh is unavailable (e.g. the simulator).
    static func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        try? await BGTaskScheduler.shared.submitTaskRequest(request)
    }
}
