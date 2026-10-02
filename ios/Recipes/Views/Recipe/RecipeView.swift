import SwiftUI

struct RecipeView: View {
    @Environment(AppModel.self) private var app
    @State private var model: RecipeModel
    @State private var stickyTitleVisible = false

    init(recipeID: Int) {
        _model = State(initialValue: RecipeModel(recipeID: recipeID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(style: .solid(Theme.terracotta), showsBack: true)
                .zIndex(1)

            switch model.phase {
            case .loading:
                ScrollView { StateBox(spinnerColor: Theme.terracotta, message: "טוען מתכון...") }
            case .failed:
                ScrollView { StateBox(icon: "😕", message: "המתכון לא נמצא או שאירעה שגיאה") }
            case .loaded:
                if let recipe = model.recipe {
                    loaded(recipe)
                }
            }
        }
        .background(Theme.cream.ignoresSafeArea())
        .task { await model.load() }
        .onDisappear {
            // Leaving the page (not just covering it with another recipe) stops narration.
            if !app.path.contains(.recipe(model.recipeID)) { model.stopAllSpeech() }
        }
    }

    private func loaded(_ recipe: Recipe) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    RecipeHero(recipe: recipe) { visible in
                        withAnimation(.easeInOut(duration: 0.25)) { stickyTitleVisible = !visible }
                    }

                    if let story = recipe.storyText, !story.isEmpty {
                        StoryBlock(text: story)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 24) {
                            IngredientsCard(model: model, recipe: recipe)
                            if !recipe.tags.isEmpty { TagsCard(tags: recipe.tags) }
                            ListenCard(model: model)
                        }
                        .padding(.bottom, 32)

                        StepsSection(model: model, recipe: recipe) { stepID in
                            withAnimation { proxy.scrollTo("step-\(stepID)", anchor: .center) }
                        }

                        NotesCard(model: model, notes: recipe.notes)
                            .padding(.top, 32)

                        if let nutrition = model.nutrition {
                            NutritionCard(nutrition: nutrition)
                                .padding(.top, 32)
                        }

                        if !recipe.related.isEmpty {
                            RelatedSection(recipes: recipe.related)
                                .padding(.top, 32)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 64)
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)

                    FooterView()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if stickyTitleVisible {
                        Text(recipe.title)
                            .font(.display(16))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Theme.stickyTitle)
                            .shadow(color: Theme.ink.opacity(0.2), radius: 4, x: 0, y: 2)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
                .clipped()
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Hero

struct RecipeHero: View {
    @Environment(AppModel.self) private var app
    let recipe: Recipe
    let onTitleVisibility: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let category = recipe.category, !category.isEmpty {
                Text(category)
                    .font(.rubik(12.8, .semibold))
                    .foregroundStyle(.white)
                    .textStroke()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                    .padding(.bottom, 12)
            }

            strip {
                Text(recipe.title)
                    .font(.display(22))
                    .kerning(-0.2)
            }
            .onScrollVisibilityChange(threshold: 0.05) { onTitleVisibility($0) }

            if let description = recipe.description, !description.isEmpty {
                strip {
                    Text(description)
                        .font(.rubik(13, .semibold))
                        .lineSpacing(4)
                }
            }

            stats

            let isFav = app.isFavorite(recipe.id)
            Button {
                app.toggleFavorite(recipe.id)
            } label: {
                Text(isFav ? "⭐ במועדפים" : "☆ הוסף למועדפים")
                    .font(.rubik(14.1, .semibold))
                    .foregroundStyle(.white)
                    .textStroke()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.white.opacity(isFav ? 0.25 : 0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: 208, alignment: .bottomLeading)
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 32)
        .background {
            LinearGradient(colors: [Theme.terracotta, Theme.terracottaDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            if recipe.imageUrl != nil {
                // The web hero uses the crop position as background-position and ignores the zoom.
                RemoteImage(urlString: recipe.imageUrl, applyZoom: false, width: 1400) { Color.clear }
            }
        }
        .clipped()
    }

    /// `.hero-strip`: white stroked text on a translucent dark band.
    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .textStroke()
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 3))
    }

    private var stats: some View {
        FlowLayout(spacing: 6, lineSpacing: 4) {
            if let prep = recipe.prepTime, prep > 0 {
                stat("הכנה", "\(prep) דק'")
                separator
            }
            if let cook = recipe.cookTime, cook > 0 {
                stat("בישול/אפייה", "\(cook) דק'")
                separator
            }
            if recipe.totalMinutes > 0 {
                stat("סה\"כ", "\(recipe.totalMinutes) דק'")
                separator
            }
            if let servings = recipe.servings, servings > 0 {
                stat("מנות", "\(servings)")
            }
            if let difficulty = recipe.difficulty, let label = Labels.difficulty[difficulty] {
                VStack(alignment: .leading, spacing: 4) {
                    statLabel("קושי")
                    Text(label)
                        .font(.rubik(13.1, .semibold))
                        .foregroundStyle(.white)
                        .textStroke()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(pillColor(difficulty), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 3))
    }

    private func pillColor(_ difficulty: String) -> Color {
        switch difficulty {
        case "easy": Color(hex: 0xC8F0CC)
        case "medium": Color(hex: 0xFDE9A0)
        default: Color(hex: 0xFDD0D0)
        }
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .font(.rubik(12, .semibold))
            .foregroundStyle(.white)
            .textStroke()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            statLabel(label)
            Text(value)
                .font(.rubik(12, .semibold))
                .foregroundStyle(.white)
                .textStroke()
        }
    }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 34)
    }
}

struct StoryBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.rubik(16.8))
            .foregroundStyle(Theme.inkLight)
            .lineSpacing(13)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.white)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.terracotta).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .shadowSm()
    }
}

// MARK: - Sidebar cards

struct IngredientsCard: View {
    @Bindable var model: RecipeModel
    let recipe: Recipe

    @State private var servingsText = ""
    @FocusState private var servingsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            servingsControl
                .padding(.bottom, 20)

            CardHeading(title: "מרכיבים")

            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                    row(index, ingredient, isLast: index == recipe.ingredients.count - 1)
                }
            }
        }
        .padding(24)
        .card()
        .onAppear { servingsText = String(model.currentServings) }
        .onChange(of: model.currentServings) { _, value in servingsText = String(value) }
        .onChange(of: servingsFocused) { _, focused in if !focused { commitServings() } }
    }

    private func commitServings() {
        if let value = Int(servingsText.trimmingCharacters(in: .whitespaces)), value >= 1 {
            model.setServings(value)
        }
        servingsText = String(model.currentServings)
    }

    private var servingsControl: some View {
        FlowLayout(spacing: 12) {
            TextField("", text: $servingsText)
                .font(.rubik(16, .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .focused($servingsFocused)
                .frame(width: 58, height: 34)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(servingsFocused ? Theme.terracotta : Theme.sandDark, lineWidth: 1.5))
                .toolbar {
                    if servingsFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("סיום") { servingsFocused = false }
                        }
                    }
                }
                .accessibilityLabel("מנות")

            Text("מנות")
                .font(.rubik(13.6))
                .foregroundStyle(Theme.inkMuted)

            HStack(spacing: 4) {
                multiplier("½x", .half)
                multiplier("1x", .one)
                multiplier("2x", .two)
            }
        }
    }

    private func multiplier(_ title: String, _ m: RecipeModel.Multiplier) -> some View {
        Button(title) {
            servingsFocused = false
            model.applyMultiplier(m)
        }
        .buttonStyle(PillButtonStyle(foreground: Theme.inkMuted, fontSize: 13.1, horizontalPadding: 12, verticalPadding: 4))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func row(_ index: Int, _ ingredient: RecipeIngredient, isLast: Bool) -> some View {
        let checked = model.checkedIngredients.contains(index)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.label)
                    .font(.rubik(15.2))
                    .foregroundStyle(Theme.ink)
                    .strikethrough(checked, color: Theme.terracotta)
                if let note = ingredient.note, !note.isEmpty {
                    Text(note)
                        .font(.rubik(12.5))
                        .italic()
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(Amount.listText(ingredient, ratio: model.ratio))
                .font(.rubik(14.1, .medium))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 12)
        .opacity(checked ? 0.42 : 1)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Theme.sand).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if checked { model.checkedIngredients.remove(index) } else { model.checkedIngredients.insert(index) }
        }
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
    }
}

struct TagsCard: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeading(title: "תגיות")
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { TagChip(text: $0, fontSize: 12.8, horizontalPadding: 16) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .card()
    }
}

/// "האזנה למתכון": narrates the whole recipe through the backend's Google TTS proxy.
struct ListenCard: View {
    @Environment(AppModel.self) private var app
    let model: RecipeModel

    private var label: String {
        switch model.recipeSpeech.state {
        case .idle: "הפעל קריינות"
        case .loading: "מכין קריינות..."
        case .playing: "⏸ השהה"
        case .paused: "▶ המשך"
        case .failed: "שגיאה — נסה שוב"
        }
    }

    var body: some View {
        let clip = model.recipeSpeech
        VStack(alignment: .leading, spacing: 0) {
            CardHeading(title: "האזנה למתכון")
            Button {
                clip.toggle(text: model.fullSpeechText, voice: app.ttsVoice)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2").font(.system(size: 15, weight: .medium))
                    Text(label).font(.rubik(15.2, .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.terracotta, in: RoundedRectangle(cornerRadius: Theme.radius))
                .opacity(clip.state == .loading ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(clip.state == .loading)

            if clip.isLoaded {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    HStack(spacing: 10) {
                        Text(StepTimers.format(Int(clip.currentTime)))
                        Slider(
                            value: Binding(get: { clip.currentTime }, set: { clip.seek(to: $0) }),
                            in: 0...max(clip.duration, 1)
                        )
                        .tint(Theme.terracotta)
                        Text(StepTimers.format(Int(clip.duration)))
                    }
                    .font(.rubik(12).monospacedDigit())
                    .foregroundStyle(Theme.inkMuted)
                    .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.top, 12)
            }
        }
        .padding(24)
        .card()
    }
}
