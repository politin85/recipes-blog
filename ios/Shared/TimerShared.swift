import ActivityKit
import AlarmKit
import AppIntents
import OSLog
import SwiftUI

/// What a step timer carries into its system alarm / Live Activity.
/// Compiled into both the app and the widget extension.
struct RecipeTimerMetadata: AlarmMetadata {
    var recipeTitle: String
    /// "🥄 הכנה", "🔥 בישול/אפייה" or empty for a plain step timer.
    var label: String
}

enum TimerColors {
    static let terracotta = Color(.sRGB, red: 0xC2 / 255.0, green: 0x62 / 255.0, blue: 0x2F / 255.0)
    static let olive = Color(.sRGB, red: 0x6B / 255.0, green: 0x7A / 255.0, blue: 0x3A / 255.0)
}

/// Runs a Live Activity button's action on the timer's system alarm.
enum TimerIntentRunner {
    private static let log = Logger(subsystem: "com.nirpoliti.recipes", category: "timer-intents")

    static func run(_ name: String, alarmID: String, _ action: (UUID) throws -> Void) {
        guard let id = UUID(uuidString: alarmID) else { return }
        do {
            try action(id)
        } catch {
            log.error("\(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}

// The buttons on the Live Activity run these in the app's process.

struct PauseTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "השהה טיימר"
    static var description = IntentDescription("משהה את הטיימר של השלב")

    @Parameter(title: "alarmID") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() throws -> some IntentResult {
        TimerIntentRunner.run("pause", alarmID: alarmID) { try AlarmManager.shared.pause(id: $0) }
        return .result()
    }
}

struct ResumeTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "המשך טיימר"
    static var description = IntentDescription("ממשיך את הטיימר של השלב")

    @Parameter(title: "alarmID") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() throws -> some IntentResult {
        TimerIntentRunner.run("resume", alarmID: alarmID) { try AlarmManager.shared.resume(id: $0) }
        return .result()
    }
}

struct CancelTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "בטל טיימר"
    static var description = IntentDescription("מבטל את הטיימר של השלב")

    @Parameter(title: "alarmID") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() throws -> some IntentResult {
        TimerIntentRunner.run("cancel", alarmID: alarmID) { try AlarmManager.shared.cancel(id: $0) }
        return .result()
    }
}

/// Live Activity for a step timer when system alarms are not available: the countdown still
/// shows on the Lock Screen and in the Dynamic Island, and a notification rings at the end.
struct StepTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Set while counting down.
        var endDate: Date?
        /// Time left while paused (or 0 when finished).
        var remaining: TimeInterval
        var total: TimeInterval
    }

    var recipeTitle: String
    var label: String
}
