import SwiftUI
import UserNotifications

/// Wall-clock step timers, like the `timers` map in recipe.html. Each running timer also
/// schedules a local notification so it still rings when the phone is locked.
@MainActor
@Observable
final class StepTimers {
    struct Entry {
        var total: Int
        var pausedElapsed: TimeInterval = 0
        var startedAt: Date?
        var done = false
        var started = false
        var generation = 0

        var running: Bool { startedAt != nil }

        func remaining(at now: Date) -> TimeInterval {
            if done { return 0 }
            let elapsed = pausedElapsed + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
            return max(0, Double(total) - elapsed)
        }
    }

    private(set) var entries: [String: Entry] = [:]
    private let recipeID: Int
    private let recipeTitle: String

    init(recipeID: Int, recipeTitle: String) {
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func entry(_ id: String, total: Int) -> Entry {
        entries[id] ?? Entry(total: total)
    }

    func toggle(_ id: String, total: Int, label: String, sound: String) {
        if entry(id, total: total).running {
            pause(id)
        } else {
            start(id, total: total, label: label, sound: sound)
        }
    }

    private func start(_ id: String, total: Int, label: String, sound: String) {
        var e = entry(id, total: total)
        guard !e.done else { return }
        e.startedAt = Date()
        e.started = true
        e.generation += 1
        entries[id] = e

        let remaining = e.remaining(at: Date())
        let generation = e.generation
        scheduleNotification(id, after: remaining, label: label, sound: sound)

        Task {
            let deadline = Date().addingTimeInterval(remaining)
            try? await Task.sleep(for: .seconds(remaining))
            guard var current = entries[id], current.generation == generation, current.running else { return }
            current.startedAt = nil
            current.pausedElapsed = Double(current.total)
            current.done = true
            entries[id] = current
            // If the app was suspended the notification already rang; don't ring again late.
            if Date().timeIntervalSince(deadline) < 2 { SoundPlayer.shared.play(sound) }
        }
    }

    private func pause(_ id: String) {
        guard var e = entries[id], let startedAt = e.startedAt else { return }
        e.pausedElapsed += Date().timeIntervalSince(startedAt)
        e.startedAt = nil
        e.generation += 1
        entries[id] = e
        cancelNotification(id)
    }

    func reset(_ id: String, total: Int) {
        let generation = (entries[id]?.generation ?? 0) + 1
        entries[id] = Entry(total: total, generation: generation)
        cancelNotification(id)
    }

    private func notificationID(_ id: String) -> String { "timer-\(recipeID)-\(id)" }

    private func scheduleNotification(_ id: String, after seconds: TimeInterval, label: String, sound: String) {
        guard seconds >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "⏰ " + (label.isEmpty ? "הטיימר הסתיים" : label)
        content.body = recipeTitle
        content.sound = UNNotificationSound(named: UNNotificationSoundName("\(sound).wav"))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notificationID(id), content: content, trigger: trigger)
        )
    }

    private func cancelNotification(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID(id)])
    }

    /// `formatTime(sec)` → "MM:SS"
    static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// While the app is open the timer plays its own sound, so the banner is shown silently.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
