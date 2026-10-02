import SwiftUI

struct RecipeListView: View {
    @Environment(AdminSession.self) private var session
    @State private var recipes: [Recipe] = []
    @State private var hidden: [Int: Bool] = [:]
    @State private var unmatched: [Int: Int] = [:]
    @State private var loading = true
    @State private var failed = false
    @State private var pendingDelete: Recipe?
    @State private var editor: EditorTarget?

    enum EditorTarget: Hashable, Identifiable {
        case new
        case edit(Int)
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(loading ? "מתכונים" : "מתכונים (\(recipes.count))")
                            .font(.display(22.4))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button("+ חדש") { editor = .new }
                            .buttonStyle(ToolButtonStyle(color: Theme.terracotta))
                    }

                    if loading {
                        StateBox(spinnerColor: Theme.terracotta, message: "טוען...")
                    } else if failed {
                        StateBox(icon: "⚠️", message: "שגיאה בטעינה")
                    } else if recipes.isEmpty {
                        StateBox(icon: "📖", message: "אין מתכונים עדיין")
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(recipes) { recipe in row(recipe) }
                        }
                    }
                }
                .padding(20)
            }
            .refreshable { await load() }
        }
        .background(Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $editor) { target in
            RecipeEditorView(recipeID: { if case .edit(let id) = target { return id } else { return nil } }()) {
                Task { await load() }
            }
        }
        .task { await load() }
        .confirmationDialog(
            pendingDelete.map { "האם למחוק את \"\($0.title)\"?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("מחק", role: .destructive) {
                if let recipe = pendingDelete { Task { await delete(recipe) } }
            }
            Button("ביטול", role: .cancel) {}
        }
    }

    private func isHidden(_ recipe: Recipe) -> Bool { hidden[recipe.id] ?? recipe.isHidden }

    private func row(_ recipe: Recipe) -> some View {
        let isHidden = isHidden(recipe)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if (unmatched[recipe.id] ?? 0) > 0 {
                        Text("⚠️").font(.system(size: 13))
                            .accessibilityLabel("\(unmatched[recipe.id] ?? 0) מצרכים לא מוזכרים בשלבי ההכנה")
                    }
                    Text(recipe.title)
                        .font(.rubik(15.2, .medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                }
                if let category = recipe.category, !category.isEmpty {
                    Text(category).font(.rubik(12.5)).foregroundStyle(Theme.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editor = .edit(recipe.id) }
            .accessibilityAddTraits(.isButton)

            Button {
                Task { await toggleHidden(recipe) }
            } label: {
                Text(isHidden ? "🙈" : "👁").font(.system(size: 18)).frame(width: 40, height: 40)
            }
            .accessibilityLabel(isHidden ? "מוסתר — לחץ להצגה" : "מוצג — לחץ להסתרה")

            Button {
                pendingDelete = recipe
            } label: {
                Text("🗑").font(.system(size: 18)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("מחק \(recipe.title)")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .card(radius: Theme.radius)
        .opacity(isHidden ? 0.55 : 1)
    }

    private func load() async {
        guard let loaded = await session.run("שגיאה בטעינה", { try await $0.recipes() }) else {
            failed = recipes.isEmpty
            loading = false
            return
        }
        recipes = loaded
        hidden = [:]
        failed = false
        loading = false
        if let counts = await session.run({ try await $0.unmatchedIngredientCounts() }) { unmatched = counts }
    }

    private func toggleHidden(_ recipe: Recipe) async {
        let newValue = !isHidden(recipe)
        guard await session.run("שגיאה בעדכון", { try await $0.setHidden(newValue, recipeID: recipe.id) }) != nil else { return }
        hidden[recipe.id] = newValue
        session.show(newValue ? "המתכון הוסתר" : "המתכון מוצג")
    }

    private func delete(_ recipe: Recipe) async {
        guard await session.run("שגיאה במחיקה", { try await $0.deleteRecipe(recipe.id) }) != nil else { return }
        session.show("המתכון נמחק")
        await load()
    }
}
