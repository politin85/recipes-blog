import ActivityKit
import AlarmKit
import OSLog
import SwiftUI
import UserNotifications

private let timerLog = Logger(subsystem: "com.nirpoliti.recipes", category: "timers")

/// Wall-clock step timers, like the `timers` map in recipe.html.
///
/// Each running timer is also a system timer (AlarmKit): it keeps counting when the app is
/// closed, shows on the Lock Screen and in the Dynamic Island, and rings like a Clock timer.
/// Without alarm access it falls back to a Live Activity (same places on screen) plus a
/// local notification that rings at the end.
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
        /// The system alarm backing this timer, once one has been scheduled.
        var alarmID: UUID?
        /// Whether the system has reported that alarm yet (scheduling is asynchronous).
        var alarmSeen = false

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
    private var observer: Task<Void, Never>?
    /// Live Activities of timers running without a system alarm.
    private var activities: [String: Activity<StepTimerAttributes>] = [:]

    init(recipeID: Int, recipeTitle: String) {
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        // Follow pause / resume / cancel done from the Lock Screen or the Dynamic Island.
        observer = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.sync(with: alarms)
            }
        }
    }

    isolated deinit {
        observer?.cancel()
    }

    private static var usesSystemTimers: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// Asks for alarm access (the system timer); falls back to notification permission.
    static func requestPermission() async {
        if AlarmManager.shared.authorizationState == .notDetermined {
            do {
                _ = try await AlarmManager.shared.requestAuthorization()
            } catch {
                timerLog.error("alarm authorization failed: \(String(describing: error), privacy: .public)")
            }
        }
        timerLog.info("alarm authorization: \(String(describing: AlarmManager.shared.authorizationState), privacy: .public)")
        if !usesSystemTimers {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
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

    // MARK: Local state

    /// Marks the timer as running and arranges for it to flip to "done" in the app.
    private func beginCountdown(_ id: String, total: Int, sound: String?) {
        var e = entry(id, total: total)
        guard !e.done, !e.running else { return }
        e.startedAt = Date()
        e.started = true
        e.generation += 1
        entries[id] = e

        let remaining = e.remaining(at: Date())
        let generation = e.generation
        Task {
            let deadline = Date().addingTimeInterval(remaining)
            try? await Task.sleep(for: .seconds(remaining))
            guard var current = entries[id], current.generation == generation, current.running else { return }
            current.startedAt = nil
            current.pausedElapsed = Double(current.total)
            current.done = true
            entries[id] = current
            finishActivity(id)
            // With a system timer the alarm itself rings. Otherwise play the sound here, unless
            // the app was suspended and the notification already rang.
            if let sound, Date().timeIntervalSince(deadline) < 2 { SoundPlayer.shared.play(sound) }
        }
    }

    private func haltCountdown(_ id: String) {
        guard var e = entries[id], let startedAt = e.startedAt else { return }
        e.pausedElapsed += Date().timeIntervalSince(startedAt)
        e.startedAt = nil
        e.generation += 1
        entries[id] = e
    }

    // MARK: Actions

    private func start(_ id: String, total: Int, label: String, sound: String) {
        let before = entry(id, total: total)
        guard !before.done else { return }
        let system = Self.usesSystemTimers
        beginCountdown(id, total: total, sound: system ? nil : sound)

        guard system else {
            startFallback(id, label: label, sound: sound)
            return
        }
        // Resume the existing system timer if there is one, otherwise schedule a new one.
        if let alarmID = before.alarmID, (try? AlarmManager.shared.resume(id: alarmID)) != nil { return }
        scheduleAlarm(id, duration: before.remaining(at: Date()), label: label, sound: sound)
    }

    private func pause(_ id: String) {
        haltCountdown(id)
        if let alarmID = entries[id]?.alarmID {
            try? AlarmManager.shared.pause(id: alarmID)
        }
        cancelNotification(id)
        showActivity(id, label: "", createIfNeeded: false)
    }

    func reset(_ id: String, total: Int) {
        if let alarmID = entries[id]?.alarmID {
            // `cancel` covers a counting or paused timer, `stop` one that is ringing.
            if (try? AlarmManager.shared.cancel(id: alarmID)) == nil { try? AlarmManager.shared.stop(id: alarmID) }
        }
        let generation = (entries[id]?.generation ?? 0) + 1
        entries[id] = Entry(total: total, generation: generation)
        cancelNotification(id)
        endActivity(id)
    }

    // MARK: System timer (AlarmKit)

    private func scheduleAlarm(_ id: String, duration: TimeInterval, label: String, sound: String) {
        guard duration >= 1 else { return }
        let alarmID = UUID()
        entries[id]?.alarmID = alarmID
        entries[id]?.alarmSeen = false

        let name = label.isEmpty ? recipeTitle : "\(label) · \(recipeTitle)"
        let presentation = AlarmPresentation(
            alert: .init(title: LocalizedStringResource(String.LocalizationValue("⏰ \(name)"))),
            countdown: .init(
                title: LocalizedStringResource(String.LocalizationValue(name)),
                pauseButton: AlarmButton(text: "השהה", textColor: .white, systemImageName: "pause.fill")
            ),
            paused: .init(
                title: LocalizedStringResource(String.LocalizationValue(name)),
                resumeButton: AlarmButton(text: "המשך", textColor: .white, systemImageName: "play.fill")
            )
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: RecipeTimerMetadata(recipeTitle: recipeTitle, label: label),
            tintColor: TimerColors.terracotta
        )
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: duration,
            attributes: attributes,
            sound: .named("\(sound).wav")
        )
        Task {
            do {
                let alarm = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
                timerLog.info("scheduled system timer, state: \(String(describing: alarm.state), privacy: .public)")
            } catch {
                timerLog.error("could not schedule system timer: \(String(describing: error), privacy: .public)")
                // Could not create a system timer (e.g. too many alarms): still alert via notification.
                if entries[id]?.alarmID == alarmID { entries[id]?.alarmID = nil }
                if entries[id]?.running == true { startFallback(id, label: label, sound: sound) }
            }
        }
    }

    /// Applies changes made outside the app to the timers shown on the page.
    private func sync(with alarms: [Alarm]) {
        let states = Dictionary(alarms.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        for (id, e) in entries {
            guard let alarmID = e.alarmID, !e.done else { continue }
            if states[alarmID] != nil, !e.alarmSeen { entries[id]?.alarmSeen = true }
            switch states[alarmID] {
            case .paused where e.running:
                haltCountdown(id)
            case .countdown where !e.running && e.started:
                beginCountdown(id, total: e.total, sound: nil)
            case .alerting:
                var finished = e
                finished.startedAt = nil
                finished.pausedElapsed = Double(e.total)
                finished.done = true
                finished.generation += 1
                entries[id] = finished
            case nil where e.alarmSeen && e.started && e.remaining(at: Date()) > 1.5:
                // Cancelled from the Live Activity: back to the initial state.
                entries[id] = Entry(total: e.total, generation: e.generation + 1)
            default:
                break
            }
        }
    }

    // MARK: Fallback: Live Activity + notification

    private func startFallback(_ id: String, label: String, sound: String) {
        guard let e = entries[id] else { return }
        scheduleNotification(id, after: e.remaining(at: Date()), label: label, sound: sound)
        showActivity(id, label: label, createIfNeeded: true)
    }

    private func activityState(_ e: Entry) -> ActivityContent<StepTimerAttributes.ContentState> {
        let now = Date()
        let remaining = e.remaining(at: now)
        let end = e.running ? now.addingTimeInterval(remaining) : nil
        return ActivityContent(
            state: .init(endDate: end, remaining: remaining, total: Double(e.total)),
            staleDate: end
        )
    }

    /// Creates or refreshes the timer's Live Activity to match its current state.
    private func showActivity(_ id: String, label: String, createIfNeeded: Bool) {
        guard let e = entries[id] else { return }
        let content = activityState(e)
        if let activity = activities[id] {
            Task { await activity.update(content) }
        } else if createIfNeeded {
            do {
                activities[id] = try Activity.request(
                    attributes: StepTimerAttributes(recipeTitle: recipeTitle, label: label),
                    content: content
                )
            } catch {
                timerLog.error("could not start Live Activity: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func finishActivity(_ id: String) {
        guard let activity = activities.removeValue(forKey: id), let e = entries[id] else { return }
        let content = ActivityContent(
            state: StepTimerAttributes.ContentState(endDate: nil, remaining: 0, total: Double(e.total)),
            staleDate: nil
        )
        Task { await activity.end(content, dismissalPolicy: .after(.now + 120)) }
    }

    private func endActivity(_ id: String) {
        guard let activity = activities.removeValue(forKey: id) else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
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
