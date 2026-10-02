import ActivityKit
import AlarmKit
import AppIntents
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

// The buttons on the Live Activity run these in the app's process.

struct PauseTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "השהה טיימר"
    static var isDiscoverable = false

    @Parameter(title: "alarmID") var alarmID: String

    init() {}
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.pause(id: id) }
        return .result()
    }
}

struct ResumeTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "המשך טיימר"
    static var isDiscoverable = false

    @Parameter(title: "alarmID") var alarmID: String

    init() {}
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.resume(id: id) }
        return .result()
    }
}

struct CancelTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "בטל טיימר"
    static var isDiscoverable = false

    @Parameter(title: "alarmID") var alarmID: String

    init() {}
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.cancel(id: id) }
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
