import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct RecipesWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SystemTimerLiveActivity()
        StepTimerLiveActivity()
    }
}

/// What both kinds of timer activity show.
private struct TimerDisplay {
    enum Mode {
        case running(end: Date, total: TimeInterval)
        case paused(remaining: TimeInterval, total: TimeInterval)
        case finished
    }

    var title: String
    var label: String
    var mode: Mode
    /// The system alarm behind the timer, when its buttons can control it.
    var alarmID: UUID?

    init(_ context: ActivityViewContext<AlarmAttributes<RecipeTimerMetadata>>) {
        title = context.attributes.metadata?.recipeTitle ?? "טיימר"
        label = context.attributes.metadata?.label ?? ""
        alarmID = context.state.alarmID
        switch context.state.mode {
        case .countdown(let c): mode = .running(end: c.fireDate, total: c.totalCountdownDuration)
        case .paused(let p): mode = .paused(remaining: p.totalCountdownDuration - p.previouslyElapsedDuration, total: p.totalCountdownDuration)
        default: mode = .finished
        }
    }

    init(_ context: ActivityViewContext<StepTimerAttributes>) {
        title = context.attributes.recipeTitle
        label = context.attributes.label
        alarmID = nil
        if let end = context.state.endDate {
            mode = (context.isStale || end <= .now) ? .finished : .running(end: end, total: context.state.total)
        } else if context.state.remaining > 0 {
            mode = .paused(remaining: context.state.remaining, total: context.state.total)
        } else {
            mode = .finished
        }
    }
}

/// Step timer backed by a system alarm (AlarmKit).
struct SystemTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RecipeTimerMetadata>.self) { context in
            LockScreenTimerView(display: TimerDisplay(context))
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            timerIsland(TimerDisplay(context))
        }
    }
}

/// Step timer without a system alarm (plain Live Activity + notification).
struct StepTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StepTimerAttributes.self) { context in
            LockScreenTimerView(display: TimerDisplay(context))
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            timerIsland(TimerDisplay(context))
        }
    }
}

private func timerIsland(_ display: TimerDisplay) -> DynamicIsland {
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
            TimerControls(display: display)
                .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
            TimerTitle(display: display)
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
            VStack(spacing: 8) {
                TimerCountdown(mode: display.mode)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(TimerColors.terracotta)
                    .frame(maxWidth: .infinity)
                TimerProgress(mode: display.mode)
            }
        }
    } compactLeading: {
        Image(systemName: "timer")
            .foregroundStyle(TimerColors.terracotta)
    } compactTrailing: {
        TimerCountdown(mode: display.mode)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(TimerColors.terracotta)
            .frame(maxWidth: 56)
    } minimal: {
        Image(systemName: "timer")
            .foregroundStyle(TimerColors.terracotta)
    }
    .keylineTint(TimerColors.terracotta)
}

private struct LockScreenTimerView: View {
    let display: TimerDisplay

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                TimerTitle(display: display)
                Spacer(minLength: 12)
                TimerCountdown(mode: display.mode)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(TimerColors.terracotta)
                    .environment(\.layoutDirection, .leftToRight)
            }
            HStack(spacing: 12) {
                TimerProgress(mode: display.mode)
                TimerControls(display: display)
            }
        }
        .padding(16)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private struct TimerTitle: View {
    let display: TimerDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            if !display.label.isEmpty {
                Text(display.label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}

/// The remaining time: live while counting down, frozen while paused.
private struct TimerCountdown: View {
    let mode: TimerDisplay.Mode

    var body: some View {
        switch mode {
        case .running(let end, _):
            Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.center)
        case .paused(let remaining, _):
            Text(Self.format(remaining)).monospacedDigit()
        case .finished:
            Text("הסתיים")
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TimerProgress: View {
    let mode: TimerDisplay.Mode

    var body: some View {
        Group {
            switch mode {
            case .running(let end, let total):
                ProgressView(
                    timerInterval: end.addingTimeInterval(-total)...end,
                    countsDown: true,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
            case .paused(let remaining, let total):
                ProgressView(value: max(0, remaining), total: max(total, 1))
            case .finished:
                ProgressView(value: 0, total: 1)
            }
        }
        .tint(TimerColors.terracotta)
    }
}

/// Pause / resume / cancel — only for timers backed by a system alarm.
private struct TimerControls: View {
    let display: TimerDisplay

    var body: some View {
        if let alarmID = display.alarmID {
            HStack(spacing: 8) {
                switch display.mode {
                case .running:
                    Button(intent: PauseTimerIntent(alarmID: alarmID)) { Image(systemName: "pause.fill") }
                        .tint(TimerColors.terracotta)
                case .paused:
                    Button(intent: ResumeTimerIntent(alarmID: alarmID)) { Image(systemName: "play.fill") }
                        .tint(TimerColors.olive)
                case .finished:
                    EmptyView()
                }
                Button(intent: CancelTimerIntent(alarmID: alarmID)) { Image(systemName: "xmark") }
                    .tint(.gray)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .font(.system(size: 15, weight: .semibold))
        } else {
            Image(systemName: "timer")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TimerColors.terracotta)
        }
    }
}
