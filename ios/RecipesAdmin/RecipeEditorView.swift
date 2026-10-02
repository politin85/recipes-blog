import SwiftUI

@MainActor
@Observable
final class RecipeEditorModel {
    var draft = RecipeDraft()
    var loading = false
    var loadFailed = false
    var saving = false
    var calculating = false
    /// The backend drops a recipe's nutrition whenever it is updated.
    var nutritionNeedsRecalculation = false

    var isNew: Bool { draft.id == nil }

    func load(_ id: Int) async {
        loading = true
        defer { loading = false }
        guard let recipe = try? await API.shared.recipe(id: id) else {
            loadFailed = true
            return
        }
        draft = RecipeDraft(recipe)
    }

    /// Creates or updates the recipe, then reloads it (the server fills in times and timers).
    func save(session: AdminSession, successMessage: String) async -> Bool {
        guard !draft.trimmedTitle.isEmpty else {
            session.show("שם המתכון הוא שדה חובה", .error)
            return false
        }
        saving = true
        defer { saving = false }
        let wasNew = isNew
        let current = draft
        guard let id = await session.run("שגיאה בשמירה — נסה שוב", { try await $0.save(current) }) else { return false }
        session.show(successMessage)
        if !wasNew { nutritionNeedsRecalculation = true }
        if let fresh = try? await API.shared.recipe(id: id) {
            draft = RecipeDraft(fresh)
        } else {
            draft.id = id
        }
        return true
    }

    func calculateNutrition(session: AdminSession) async {
        guard let id = draft.id else {
            session.show("שמור קודם את המתכון", .error)
            return
        }
        calculating = true
        defer { calculating = false }
        if let calories = await session.run("שגיאה בחישוב ערכים תזונתיים", { try await $0.calculateNutrition(recipeID: id) }) {
            nutritionNeedsRecalculation = false
            session.show("✓ \(calories) קק\"ל למנה")
        }
    }

    func cleanDuplicates(session: AdminSession) async {
        guard let id = draft.id else { return }
        guard let updated = await session.run("שגיאה בניקוי", { try await $0.cleanDuplicates(recipeID: id) }) else { return }
        session.show("ניקוי הסתיים — \(updated) שלבים עודכנו")
        if updated > 0, let fresh = try? await API.shared.recipe(id: id) {
            draft.steps = fresh.steps.map(StepDraft.init)
        }
    }
}

struct RecipeEditorView: View {
    @Environment(AdminSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let recipeID: Int?
    let onChange: () -> Void

    @State private var model = RecipeEditorModel()
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold))
                        Text("חזרה").font(.rubik(14.4))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                LogoMark()
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.headerHeight)
            .background(Theme.terracotta.ignoresSafeArea(edges: .top))

            if model.loading {
                ScrollView { StateBox(spinnerColor: Theme.terracotta, message: "טוען מתכון...") }
            } else if model.loadFailed {
                ScrollView { StateBox(icon: "😕", message: "שגיאה בטעינת המתכון") }
            } else {
                form
            }
        }
        .background(Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if let recipeID, model.draft.id == nil { await model.load(recipeID) }
        }
    }

    private var form: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: 16) {
                Text(model.isNew ? "מתכון חדש ✨" : "עריכת מתכון")
                    .font(.display(22.4))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                visibilityRow

                AdminField(label: "שם המתכון *", text: $model.draft.title, placeholder: "שם המתכון")
                    .accessibilityIdentifier("recipe-title")

                SectionDivider(title: "תמונה ראשית")
                ImageField(url: $model.draft.imageURL)

                AdminField(label: "תיאור קצר", text: $model.draft.description, placeholder: "תיאור קצר של המתכון...", lines: 3)
                AdminField(label: "סיפור / תיאור מורחב", text: $model.draft.story,
                           placeholder: "ספר על המתכון — מאיפה בא, מה ייחודי בו, זכרונות...", lines: 5)

                HStack(alignment: .top, spacing: 12) {
                    AdminField(label: "קטגוריה", text: $model.draft.category, placeholder: "אפייה, עיקריות...")
                    VStack(spacing: 6) {
                        FieldLabel(text: "רמת קושי")
                        Picker("רמת קושי", selection: $model.draft.difficulty) {
                            Text("קל").tag("easy")
                            Text("בינוני").tag("medium")
                            Text("מאתגר").tag("hard")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.sandDark, lineWidth: 1.5))
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    AdminField(label: "הכנה (דק')", text: $model.draft.prepTime, placeholder: "0", keyboard: .numberPad)
                    AdminField(label: "בישול/אפייה (דק')", text: $model.draft.cookTime, placeholder: "0", keyboard: .numberPad)
                    AdminField(label: "מנות", text: $model.draft.servings, placeholder: "4", keyboard: .numberPad)
                }

                AdminField(label: "תגיות (מופרדות בפסיק)", text: $model.draft.tags, placeholder: "שוקולד, אפייה, קל...")

                if !model.isNew { sectionSave("💾 שמור פרטים") }

                SectionDivider(title: "מרכיבים") {
                    Button("+ הוסף") { model.draft.ingredients.append(IngredientDraft()) }
                        .buttonStyle(PillButtonStyle(fontSize: 12.8, verticalPadding: 5))
                }
                ForEach($model.draft.ingredients) { $ingredient in
                    IngredientRow(
                        ingredient: $ingredient,
                        unmentioned: model.draft.isUnmentioned(ingredient),
                        move: { move(&model.draft.ingredients, ingredient.id, by: $0) },
                        delete: { model.draft.ingredients.removeAll { $0.id == ingredient.id } }
                    )
                }
                if !model.isNew { sectionSave("💾 שמור מרכיבים") }

                SectionDivider(title: "שלבי הכנה") {
                    Button("+ הוסף") { model.draft.steps.append(StepDraft()) }
                        .buttonStyle(PillButtonStyle(fontSize: 12.8, verticalPadding: 5))
                }
                ForEach(Array($model.draft.steps.enumerated()), id: \.element.id) { index, $step in
                    StepRow(
                        step: $step,
                        number: index + 1,
                        recalcTimes: { model.draft.recalcTimes() },
                        move: { move(&model.draft.steps, step.id, by: $0) },
                        delete: { model.draft.steps.removeAll { $0.id == step.id } }
                    )
                }
                if !model.isNew { sectionSave("💾 שמור שלבים") }

                if !model.isNew { preview }

                if model.nutritionNeedsRecalculation {
                    Text("⚠️ שמירת מתכון מוחקת את הערכים התזונתיים שלו בשרת. לחץ \"חשב ערכים תזונתיים\" כדי ליצור אותם מחדש.")
                        .font(.rubik(13.1))
                        .foregroundStyle(Theme.inkLight)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminColors.warningBackground, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .leading) { Rectangle().fill(AdminColors.warningBorder).frame(width: 3) }
                }

                actions
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var visibilityRow: some View {
        let hidden = model.draft.isHidden
        return HStack(spacing: 12) {
            Text(hidden ? "🙈" : "👁️").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(hidden ? "מוסתר מהבלוג" : "מוצג בבלוג").font(.rubik(14.4, .semibold)).foregroundStyle(Theme.ink)
                Text(hidden ? "המתכון לא מופיע לגולשים" : "המתכון גלוי לכל הגולשים").font(.rubik(12.5)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button(hidden ? "הצג בבלוג" : "הסתר") { model.draft.isHidden.toggle() }
                .buttonStyle(ToolButtonStyle(color: hidden ? Theme.olive : Theme.inkMuted))
        }
        .padding(14)
        .background(hidden ? Theme.sand : Color(hex: 0xE8F5E9), in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func sectionSave(_ title: String) -> some View {
        HStack {
            Spacer()
            Button(model.saving ? "שומר..." : title) {
                Task { if await model.save(session: session, successMessage: "נשמר ✓") { onChange() } }
            }
            .buttonStyle(ToolButtonStyle())
            .disabled(model.saving)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { showPreview.toggle() }
            } label: {
                HStack {
                    Text("👁 תצוגה מקדימה").font(.display(16)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(showPreview ? "▲ סגור" : "▼ פתח").font(.rubik(12.8)).foregroundStyle(Theme.inkMuted)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showPreview {
                RecipePreview(draft: model.draft)
                    .padding(14)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.sand).frame(height: 1) }
            }
        }
        .card(radius: Theme.radius)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !model.isNew {
                HStack(spacing: 10) {
                    Button("🧹 ניקוי כפילות") { Task { await model.cleanDuplicates(session: session) } }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(model.calculating ? "⏳ מחשב..." : "🥗 חשב ערכים תזונתיים") {
                        Task { await model.calculateNutrition(session: session) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.calculating)
                }
            }
            HStack(spacing: 10) {
                Button("ביטול") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(model.saving ? "שומר..." : (model.isNew ? "צור מתכון ✓" : "שמור שינויים ✓")) {
                    let wasNew = model.isNew
                    Task {
                        if await model.save(session: session, successMessage: wasNew ? "המתכון נוצר בהצלחה ✓" : "השינויים נשמרו ✓") {
                            onChange()
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.saving)
                .accessibilityIdentifier("submit")
            }
        }
        .padding(.top, 8)
    }

    private func move<T: Identifiable>(_ items: inout [T], _ id: T.ID, by delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }
}

/// Up / down / delete controls shared by ingredient and step rows.
struct RowControls: View {
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { move(-1) } label: { Image(systemName: "chevron.up").frame(width: 30, height: 30) }
                .accessibilityLabel("הזז למעלה")
            Button { move(1) } label: { Image(systemName: "chevron.down").frame(width: 30, height: 30) }
                .accessibilityLabel("הזז למטה")
            Button(action: delete) { Text("✕").frame(width: 30, height: 30) }
                .foregroundStyle(AdminColors.danger)
                .accessibilityLabel("מחק שורה")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.inkMuted)
        .buttonStyle(.plain)
    }
}

struct IngredientRow: View {
    @Binding var ingredient: IngredientDraft
    let unmentioned: Bool
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = ingredient.originalLabel {
                Text(label).font(.rubik(11.5)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 6) {
                TextField("שם מרכיב *", text: $ingredient.name).fieldBox()
                RowControls(move: move, delete: delete)
            }
            HStack(spacing: 6) {
                TextField("כמות", text: $ingredient.amount).keyboardType(.decimalPad).fieldBox().frame(width: 84)
                TextField("יחידה", text: $ingredient.unit).fieldBox().frame(width: 96)
                TextField("הערה", text: $ingredient.note).fieldBox()
            }
            if unmentioned {
                Text("מצרך זה לא מוזכר בשום שלב").font(.rubik(11.5)).foregroundStyle(Color(hex: 0x8A6D00))
            }
        }
        .padding(10)
        .background(unmentioned ? AdminColors.warningBackground : Theme.cream, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius)
            .strokeBorder(unmentioned ? AdminColors.warningBorder : Theme.sand, lineWidth: 1.5))
    }
}

struct StepRow: View {
    @Binding var step: StepDraft
    let number: Int
    let recalcTimes: () -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.rubik(13, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.terracotta, in: Circle())
                TextField("כותרת השלב (אופציונלי)", text: $step.title).fieldBox()
                RowControls(move: move, delete: delete)
            }

            TextField("הוראות השלב *", text: $step.text, axis: .vertical)
                .lineLimit(4...14)
                .focused($textFocused)
                .fieldBox()
                // Like the web form: leaving the text fills an empty timer from the text.
                .onChange(of: textFocused) { _, focused in
                    if !focused, step.timerMinutes.isEmpty, let minutes = AdminTimer.minutes(in: step.text) {
                        step.timerMinutes = String(minutes)
                    }
                }

            HStack(alignment: .bottom, spacing: 8) {
                numberField("⏱ טיימר (דק')", $step.timerMinutes, "דקות")
                numberField("🥄 הכנה (דק')", $step.prepMinutes, "0")
                    .onChange(of: step.prepMinutes) { _, _ in recalcTimes() }
                numberField("🔥 בישול (דק')", $step.cookMinutes, "0")
                    .onChange(of: step.cookMinutes) { _, _ in recalcTimes() }
            }

            Toggle("הצג טיימר הכנה", isOn: $step.showPrepTimer)
            Toggle("הצג טיימר בישול/אפייה", isOn: $step.showCookTimer)

            ImageField(url: $step.imageURL, height: 120, placeholder: "📷 תמונה לשלב (אופציונלי)", showsURLField: false)
        }
        .font(.rubik(13.6))
        .foregroundStyle(Theme.inkLight)
        .tint(Theme.olive)
        .padding(12)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.sand, lineWidth: 1.5))
    }

    private func numberField(_ label: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.rubik(11.5)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.8)
            TextField(placeholder, text: text).keyboardType(.numberPad).fieldBox()
        }
    }
}

/// "תצוגה מקדימה": the form as a reader would roughly see it.
struct RecipePreview: View {
    let draft: RecipeDraft

    private var meta: [String] {
        let payload = draft.payload
        let prep = payload["prep_time"] as? Int ?? 0
        let cook = payload["cook_time"] as? Int ?? 0
        var items: [String] = []
        if prep > 0 { items.append("🥄 הכנה: \(prep) דק'") }
        if cook > 0 { items.append("🔥 בישול: \(cook) דק'") }
        if prep + cook > 0 { items.append("⏱ סה\"כ: \(prep + cook) דק'") }
        if let servings = payload["servings"] as? Int { items.append("🍽 \(servings) מנות") }
        items.append("📊 \(Labels.difficulty[draft.difficulty] ?? draft.difficulty)")
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !draft.imageURL.isEmpty {
                RemoteImage(urlString: draft.imageURL, width: 1200) { Theme.sand }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }
            Text(draft.trimmedTitle.isEmpty ? "(ללא שם)" : draft.trimmedTitle)
                .font(.display(22))
                .foregroundStyle(Theme.ink)
            FlowLayout(spacing: 8) {
                ForEach(meta, id: \.self) { TagChip(text: $0) }
            }
            if !draft.description.isEmpty {
                Text(draft.description).font(.rubik(14.4)).foregroundStyle(Theme.inkLight)
            }
            if !draft.ingredients.isEmpty {
                Text("מרכיבים").font(.display(16)).foregroundStyle(Theme.ink)
                ForEach(draft.ingredients) { ing in
                    let quantity = [ing.amount, ing.unit].filter { !$0.isEmpty }.joined(separator: " ")
                    Text("• \(ing.name)\(quantity.isEmpty ? "" : " — \(quantity)")\(ing.note.isEmpty ? "" : " (\(ing.note))")")
                        .font(.rubik(14))
                        .foregroundStyle(Theme.inkLight)
                }
            }
            if !draft.steps.isEmpty {
                Text("שלבי הכנה").font(.display(16)).foregroundStyle(Theme.ink)
                ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(step.title.isEmpty ? String(step.text.prefix(60)) : step.title)")
                            .font(.rubik(14.4, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(step.text).font(.rubik(14)).foregroundStyle(Theme.inkLight).lineSpacing(5)
                    }
                }
            }
            if !draft.story.isEmpty {
                Text("💬 על המתכון").font(.display(16)).foregroundStyle(Theme.ink)
                Text(draft.story).font(.rubik(14)).foregroundStyle(Theme.inkLight).lineSpacing(5)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
