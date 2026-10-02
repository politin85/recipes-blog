import SwiftUI

@MainActor
@Observable
final class FridgeModel {
    enum Results { case initial, searching, failed, loaded([Recipe]) }

    private(set) var ingredients: [CatalogIngredient] = []
    private var groups: [String: [Int]] = [:]
    /// Selected display names, in the order they were added.
    private(set) var selected: [String] = []
    private(set) var pantryEnabled = false
    private(set) var results: Results = .initial
    private var searchTask: Task<Void, Never>?

    var selectedSet: Set<String> { Set(selected) }

    func load() async {
        guard ingredients.isEmpty, let loaded = try? await API.shared.ingredients() else { return }
        // Stable sort by popularity, like the web.
        ingredients = loaded.enumerated().sorted {
            $0.element.recipeCount != $1.element.recipeCount
                ? $0.element.recipeCount > $1.element.recipeCount
                : $0.offset < $1.offset
        }.map(\.element)
        groups = FridgeLogic.displayGroups(ingredients)
    }

    func add(_ ingredient: CatalogIngredient) {
        guard !selected.contains(ingredient.label) else { return }
        selected.append(ingredient.label)
        scheduleSearch()
    }

    func remove(_ label: String) {
        selected.removeAll { $0 == label }
        scheduleSearch()
    }

    func toggle(_ ingredient: CatalogIngredient) {
        if selected.contains(ingredient.label) { remove(ingredient.label) } else { add(ingredient) }
    }

    func togglePantry() {
        pantryEnabled.toggle()
        scheduleSearch()
    }

    /// Re-runs the search 350 ms after the last change.
    private func scheduleSearch() {
        searchTask?.cancel()
        guard !selected.isEmpty else {
            results = .initial
            return
        }
        let ids = selected.flatMap { groups[$0] ?? [] }
        let pantry = pantryEnabled
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            results = .searching
            do {
                let found = try await API.shared.recipesByIngredients(ids: ids, includePantry: pantry)
                guard !Task.isCancelled else { return }
                results = .loaded(FridgeLogic.sortResults(found))
            } catch {
                guard !Task.isCancelled else { return }
                results = .failed
            }
        }
    }
}

struct FridgeView: View {
    @Environment(AppModel.self) private var app
    @State private var model = FridgeModel()
    @State private var query = ""
    @State private var dropdownVisible = false
    @State private var showAll = false
    @FocusState private var searchFocused: Bool

    private var suggestions: [CatalogIngredient] {
        FridgeLogic.suggestions(query: query, ingredients: model.ingredients, selected: model.selectedSet)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(style: .solid(Theme.terracotta), showsBack: true)
                .zIndex(1)

            ScrollView {
                VStack(spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 40) {
                        pickerCard.zIndex(1)
                        resultsArea
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
        }
        .background(Theme.cream.ignoresSafeArea())
        .task { await model.load() }
        .sheet(isPresented: $showAll) { AllIngredientsSheet(model: model) }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Text("מתכון לפי מצרכים 🥕")
                .font(.display(28.8))
                .foregroundStyle(.white)
            Text("הקלד מרכיבים שיש לך — נמצא מה אפשר להכין")
                .font(.rubik(16, .light))
                .foregroundStyle(.white.opacity(0.8))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 32)
        .background(LinearGradient(colors: [Theme.olive, Theme.oliveDark], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Picker

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("המרכיבים שלי")
                    .font(.display(17.6))
                    .foregroundStyle(.white)
                searchInput
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.olive, in: UnevenRoundedRectangle(topLeadingRadius: Theme.radiusLg, topTrailingRadius: Theme.radiusLg))
            .zIndex(1)

            VStack(alignment: .leading, spacing: 0) {
                chips
                    .padding(.bottom, 16)

                HStack {
                    Text("כל המרכיבים")
                        .font(.rubik(12.8, .semibold))
                        .kerning(0.9)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Button("הצג הכל") {
                        searchFocused = false
                        showAll = true
                    }
                    .buttonStyle(PillButtonStyle(fill: .clear, border: Theme.olive, foreground: Theme.olive, fontSize: 12.5, horizontalPadding: 12, verticalPadding: 4))
                }
                .padding(.top, 8)
                .padding(.bottom, 8)

                HStack {
                    Text("כלול מוצרי יסוד בחיפוש % התאמה")
                        .font(.rubik(13.6))
                        .foregroundStyle(Theme.inkLight)
                    Spacer(minLength: 8)
                    Button(model.pantryEnabled ? "דלוק" : "כבוי") { model.togglePantry() }
                        .buttonStyle(PillButtonStyle(
                            fill: model.pantryEnabled ? Theme.olive : Theme.sand,
                            border: model.pantryEnabled ? Theme.olive : Theme.sandDark,
                            foreground: model.pantryEnabled ? .white : Theme.inkMuted,
                            fontSize: 12.8,
                            verticalPadding: 4
                        ))
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(Theme.sand).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.sand).frame(height: 1) }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .card()
    }

    private var searchInput: some View {
        TextField("", text: $query, prompt: Text("הקלד מרכיב...").foregroundStyle(.white.opacity(0.6)))
            .font(.rubik(14.4))
            .foregroundStyle(.white)
            .tint(.white)
            .multilineTextAlignment(.leading)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($searchFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.white.opacity(searchFocused ? 0.3 : 0.2), in: Capsule())
            .onChange(of: searchFocused) { _, focused in dropdownVisible = focused }
            .onChange(of: query) { _, _ in if searchFocused { dropdownVisible = true } }
            .onSubmit {
                if let match = FridgeLogic.submitMatch(query: query, ingredients: model.ingredients) { pick(match) }
            }
            .overlay(alignment: .top) {
                if dropdownVisible, !suggestions.isEmpty {
                    dropdown.offset(y: 46)
                }
            }
    }

    private var dropdown: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, ingredient in
                    Button {
                        pick(ingredient)
                    } label: {
                        Text(ingredient.label)
                            .font(.rubik(14.4))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < suggestions.count - 1 {
                        Rectangle().fill(Theme.sand).frame(height: 1)
                    }
                }
            }
        }
        .frame(height: min(220, CGFloat(suggestions.count) * 42.5))
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sandDark, lineWidth: 1.5))
        .shadowMd()
    }

    private func pick(_ ingredient: CatalogIngredient) {
        query = ""
        dropdownVisible = false
        model.add(ingredient)
    }

    @ViewBuilder
    private var chips: some View {
        if model.selected.isEmpty {
            Text("עדיין לא הוספת מרכיבים")
                .font(.rubik(13.3))
                .foregroundStyle(Theme.inkMuted)
                .frame(minHeight: 32)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(model.selected, id: \.self) { label in
                    Button {
                        model.remove(label)
                    } label: {
                        HStack(spacing: 8) {
                            Text(label).font(.rubik(13.1, .medium))
                            Text("×").font(.rubik(14.4))
                        }
                        .foregroundStyle(Theme.terracotta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Theme.terracottaPale, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.terracotta, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("הסר \(label)")
                }
            }
            .frame(minHeight: 32)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsArea: some View {
        switch model.results {
        case .initial:
            StateBox(icon: "🥕", message: "הוסף מרכיבים כדי למצוא מתכונים")
        case .searching:
            StateBox(spinnerColor: Theme.olive, message: "מחפש...")
        case .failed:
            StateBox(icon: "⚠️", message: "שגיאה בחיפוש — נסה שוב")
        case .loaded(let recipes):
            if recipes.isEmpty {
                StateBox(icon: "🤷", message: "לא נמצאו מתכונים עם המרכיבים שבחרת", detail: "נסה להוסיף עוד מרכיבים")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("תוצאות לפי % התאמה")
                            .font(.display(22.4))
                            .foregroundStyle(Theme.ink)
                        Text("\(recipes.count) נמצאו")
                            .font(.rubik(14.4))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.bottom, 24)

                    ForEach(recipes) { recipe in
                        FridgeResultCard(recipe: recipe)
                            .onTapGesture { app.openRecipe(recipe.id) }
                            .accessibilityAddTraits(.isButton)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
    }
}

struct FridgeResultCard: View {
    let recipe: Recipe

    private var matchColor: Color {
        let pct = recipe.matchPercent ?? 0
        return pct == 100 ? Color(hex: 0x2E7D32) : (pct >= 80 ? Theme.olive : Color(hex: 0xE65100))
    }

    var body: some View {
        HStack(spacing: 0) {
            // The fridge page ignores the crop position.
            RemoteImage(urlString: recipe.imageUrl, usePosition: false, width: 400) {
                Theme.terracottaPale.overlay(Text(Labels.emoji(for: recipe.category)).font(.system(size: 32)))
            }
            .frame(width: 90)
            .frame(maxHeight: .infinity)
            .background(Theme.terracottaPale)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(recipe.title)
                        .font(.display(16.8))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let category = recipe.category, !category.isEmpty {
                        Text(category)
                            .font(.rubik(12.5))
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.bottom, 8)

                if let description = recipe.description, !description.isEmpty {
                    Text(description)
                        .font(.rubik(14.1))
                        .foregroundStyle(Theme.inkMuted)
                        .lineSpacing(5)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 12)
                }

                if let pct = recipe.matchPercent {
                    HStack(spacing: 12) {
                        Text("התאמה").font(.rubik(12.8)).foregroundStyle(Theme.inkMuted)
                        GeometryReader { geo in
                            Capsule().fill(Theme.sand)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(matchColor).frame(width: geo.size.width * Double(min(max(pct, 0), 100)) / 100)
                                }
                        }
                        .frame(height: 6)
                        Text("\(pct)%").font(.rubik(13.6, .semibold)).foregroundStyle(matchColor)
                    }
                    .padding(.bottom, 12)

                    if recipe.missingIngredients.isEmpty {
                        Text("✓ יש לך את כל המרכיבים!")
                            .font(.rubik(13.1, .medium))
                            .foregroundStyle(Color(hex: 0x2E7D32))
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(Array(recipe.missingIngredients.enumerated()), id: \.offset) { _, missing in
                                Text("− " + missing.label)
                                    .font(.rubik(12))
                                    .foregroundStyle(Theme.terracotta)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: 0xFFF0EB), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.terracottaPale, lineWidth: 1))
                            }
                        }
                    }
                }

                HStack(spacing: 16) {
                    if recipe.totalMinutes > 0 {
                        Text("⏱ \(recipe.totalMinutes) דק'")
                    }
                    if let difficulty = recipe.difficulty, let label = Labels.difficulty[difficulty] {
                        Text(label)
                    }
                }
                .font(.rubik(12.8))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .shadowSm()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
    }
}

/// The "כל המרכיבים" modal: every non-pantry ingredient, grouped by category.
struct AllIngredientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: FridgeModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("כל המרכיבים").font(.display(18.4)).foregroundStyle(Theme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Text("✕").font(.system(size: 22)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("סגור")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.sand).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(FridgeLogic.categoryGroups(model.ingredients)) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.name)
                                .font(.display(15.2))
                                .foregroundStyle(Theme.ink)
                                .padding(.bottom, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.sand).frame(height: 1.5) }

                            FlowLayout(spacing: 8) {
                                ForEach(group.items, id: \.id) { ingredient in
                                    let isSelected = model.selectedSet.contains(ingredient.label)
                                    Button(ingredient.label) { model.toggle(ingredient) }
                                        .buttonStyle(PillButtonStyle(
                                            fill: isSelected ? Theme.olive : .white,
                                            border: isSelected ? Theme.olive : Theme.sandDark,
                                            foreground: isSelected ? .white : Theme.inkLight,
                                            fontSize: 13.6
                                        ))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .background(.white)
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.radiusLg)
        .presentationBackground(.white)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
