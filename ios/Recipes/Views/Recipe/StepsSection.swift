import SwiftUI

struct StepsSection: View {
    let model: RecipeModel
    let recipe: Recipe
    let scrollTo: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("הוראות הכנה")
                .font(.display(24))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 12)

            FlowLayout(spacing: 8) {
                Button(model.allOpen ? "סגור את כל הצעדים" : "פתח את כל הצעדים") {
                    withAnimation(.easeInOut(duration: 0.3)) { model.toggleAllSteps() }
                }
                .buttonStyle(PillButtonStyle())

                Button(model.cookingMode ? "✕ צא ממצב בישול" : "👨‍🍳 מצב בישול") {
                    withAnimation(.easeInOut(duration: 0.3)) { model.toggleCookingMode() }
                    if model.cookingMode, let first = recipe.steps.first { scrollTo(first.id) }
                }
                .buttonStyle(PillButtonStyle(
                    fill: model.cookingMode ? Theme.olive : .white,
                    border: model.cookingMode ? Theme.olive : Theme.sandDark,
                    foreground: model.cookingMode ? .white : Theme.inkLight,
                    horizontalPadding: 20
                ))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)

            if model.cookingMode {
                cookingBar.padding(.bottom, 20)
            }

            VStack(spacing: 16) {
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    StepCard(model: model, step: step, index: index, total: recipe.steps.count, scrollTo: scrollTo)
                        .id("step-\(step.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Cooking mode keeps the screen awake — hands are busy.
        .onChange(of: model.cookingMode, initial: true) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var cookingBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("שלב \(model.cookingIndex + 1) מתוך \(recipe.steps.count)")
                .font(.rubik(13.6))
                .foregroundStyle(Theme.inkMuted)
            GeometryReader { geo in
                Capsule().fill(Theme.sand)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.terracotta).frame(width: geo.size.width * model.cookingProgress)
                    }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .card(radius: Theme.radius)
    }
}

struct StepCard: View {
    @Environment(AppModel.self) private var app
    let model: RecipeModel
    let step: RecipeStep
    let index: Int
    let total: Int
    let scrollTo: (Int) -> Void

    private var isOpen: Bool { model.openSteps.contains(step.id) }
    private var isDone: Bool { model.doneSteps.contains(step.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen { content }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .shadowSm()
        .opacity(model.isDimmed(index) ? 0.35 : 1)
        .allowsHitTesting(!model.isDimmed(index))
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("\(step.stepOrder)")
                .font(.rubik(14, .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(isDone ? Theme.olive : Theme.terracotta, in: Circle())

            Text(step.displayTitle)
                .font(.display(17))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if isDone {
                    Text("✓").font(.rubik(16, .semibold)).foregroundStyle(Theme.olive)
                }
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) { model.toggleOpen(step) }
        }
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step.imageUrl != nil {
                RemoteImage(urlString: step.imageUrl, width: 1000) { Theme.sand }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                    .padding(.bottom, 14)
            }

            StepTextView(runs: model.runs(for: step))

            if let timers = model.timers {
                if step.hasPrepTimer {
                    TimerBlock(timers: timers, id: "\(step.id)-prep", total: step.prepMinutes * 60, label: "🥄 הכנה")
                }
                if step.hasCookTimer {
                    TimerBlock(timers: timers, id: "\(step.id)-cook", total: step.cookMinutes * 60, label: "🔥 בישול/אפייה")
                }
                if step.hasPlainTimer {
                    TimerBlock(timers: timers, id: "\(step.id)", total: step.timerSeconds, label: "")
                }
            }

            footer

            if model.cookingMode { cookingNav }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speechLabel: String {
        switch model.speech(for: step).state {
        case .idle: "🔊 הקרא שלב"
        case .loading: "🔊 ..."
        case .playing: "⏸ השהה"
        case .paused: "▶ המשך"
        case .failed: "⚠️ שגיאה"
        }
    }

    private var footer: some View {
        let clip = model.speech(for: step)
        return FlowLayout(spacing: 12) {
            Button(speechLabel) {
                clip.toggle(text: step.text, voice: app.ttsVoice, failureResetDelay: .seconds(2))
            }
            .buttonStyle(PillButtonStyle(fill: .clear, foreground: Theme.inkMuted, fontSize: 12.8, verticalPadding: 5))
            .disabled(clip.state == .loading || clip.state == .failed)

            Button(isDone ? "✓ בוצע" : "✓ סמן כבוצע") {
                withAnimation(.easeInOut(duration: 0.2)) { model.toggleDone(step) }
            }
            .buttonStyle(PillButtonStyle(
                fill: isDone ? Theme.olive : .clear,
                border: isDone ? Theme.olive : Theme.sandDark,
                foreground: isDone ? .white : Theme.inkMuted,
                fontSize: 12.8,
                verticalPadding: 5
            ))
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.sand).frame(height: 1) }
        .padding(.top, 16)
    }

    private var cookingNav: some View {
        HStack {
            navButton("← הקודם", fill: Theme.sand, foreground: Theme.ink, disabled: index == 0) { go(index - 1) }
            Spacer()
            Text("\(index + 1) / \(total)")
                .font(.rubik(13.6))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            navButton(index == total - 1 ? "סיום ✓" : "הבא →", fill: Theme.terracotta, foreground: .white, disabled: false) { go(index + 1) }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.sand).frame(height: 1) }
        .padding(.top, 16)
    }

    private func go(_ target: Int) {
        var destination: Int?
        withAnimation(.easeInOut(duration: 0.3)) { destination = model.goToStep(target) }
        if let destination { scrollTo(destination) }
    }

    private func navButton(_ title: String, fill: Color, foreground: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.rubik(14.4, .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

/// Step text with ingredient names in bold ink and their scaled amounts in muted regular weight.
struct StepTextView: View {
    let runs: [StepText.Run]

    private var attributed: AttributedString {
        var out = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            switch run.style {
            case .plain:
                part.font = .rubik(15.2)
                part.foregroundColor = Theme.inkLight
            case .strong:
                part.font = .rubik(15.2, .semibold)
                part.foregroundColor = Theme.ink
            case .muted:
                part.font = .rubik(15.2)
                part.foregroundColor = Theme.inkMuted
            }
            out.append(part)
        }
        return out
    }

    var body: some View {
        Text(attributed)
            .lineSpacing(9)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

struct TimerBlock: View {
    @Environment(AppModel.self) private var app
    let timers: StepTimers
    let id: String
    let total: Int
    let label: String

    var body: some View {
        let entry = timers.entry(id, total: total)
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = entry.remaining(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 12) {
                    if !label.isEmpty {
                        Text(label).font(.rubik(12.8)).foregroundStyle(Theme.inkMuted)
                    }
                    Text(StepTimers.format(Int(remaining.rounded(.up))))
                        .font(.rubik(24, .semibold).monospacedDigit())
                        .foregroundStyle(entry.done ? Color(hex: 0x888888) : (entry.running ? Theme.olive : Theme.terracotta))
                        .frame(minWidth: 72, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)

                    Button(buttonTitle(entry)) {
                        timers.toggle(id, total: total, label: label, sound: app.timerSound)
                    }
                    .buttonStyle(PillButtonStyle(
                        fill: entry.running ? Theme.terracotta : .clear,
                        border: Theme.terracotta,
                        foreground: entry.running ? .white : Theme.terracotta,
                        fontSize: 13.6,
                        horizontalPadding: 20
                    ))
                    .disabled(entry.done)

                    if entry.started {
                        Button("↺") { timers.reset(id, total: total) }
                            .buttonStyle(PillButtonStyle(fill: .clear, border: Theme.inkMuted, foreground: Theme.inkMuted, fontSize: 13.6, horizontalPadding: 20))
                            .accessibilityLabel("איפוס טיימר")
                    }
                }

                GeometryReader { geo in
                    Capsule().fill(Theme.sand)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.terracotta)
                                .frame(width: geo.size.width * (total > 0 ? remaining / Double(total) : 0))
                        }
                }
                .frame(height: 4)
            }
        }
        .padding(.top, 16)
    }

    private func buttonTitle(_ entry: StepTimers.Entry) -> String {
        if entry.done { return "✓ הסתיים" }
        if entry.running { return "⏸ עצור" }
        return entry.started ? "▶ המשך" : "▶ הפעל טיימר"
    }
}
