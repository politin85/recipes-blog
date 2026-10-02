import SwiftUI

// MARK: - Ingredient manager

struct IngredientManagerView: View {
    @Environment(AdminSession.self) private var session
    @State private var rows: [AliasRow] = []
    /// What the server currently holds, to detect edits and to send `old_note`.
    @State private var saved: [UUID: AliasRow] = [:]
    @State private var loading = true
    @State private var query = ""
    @State private var sortColumn: AliasRow.SortColumn?
    @State private var ascending = true
    @State private var busyTool: String?
    @State private var titlesProgress: String?
    @State private var confirm: Tool?
    @State private var askDiagnose = false
    @State private var diagnoseName = ""
    @State private var diagnoseOutput: String?
    @State private var stripRemaining: [String] = []

    enum Tool: String, Identifiable {
        case stripAmounts, generateTitles
        var id: String { rawValue }
        var message: String {
            switch self {
            case .stripAmounts:
                "פעולה זו תסיר את כל הכמויות בסוגריים מטקסטי השלבים במסד הנתונים. הכמויות יוצגו דינמית מרשימת המצרכים."
            case .generateTitles:
                "פעולה זו תיצור כותרות אוטומטיות לכל השלבים שכותרתם ריקה או \"שלב N\". כל קריאה ל-Claude עולה כסף."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("🧂 מנהל מצרכים").font(.display(22.4)).foregroundStyle(Theme.ink)

                    tools

                    if let diagnoseOutput {
                        ScrollView(.horizontal) {
                            Text(diagnoseOutput)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: 0xD4D4D4))
                                .padding(12)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                        .background(Color(hex: 0x1E1E1E), in: RoundedRectangle(cornerRadius: 8))
                        .environment(\.layoutDirection, .leftToRight)
                    }

                    if !stripRemaining.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("שלבים לבדיקה ידנית (\(stripRemaining.count))").font(.rubik(13.6, .semibold))
                            ForEach(stripRemaining, id: \.self) { Text($0).font(.rubik(12.5)) }
                        }
                        .foregroundStyle(Theme.inkLight)
                        .padding(12)
                        .background(AdminColors.warningBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("⚠️ השינויים גלובליים — משפיעים על כל המתכונים שמשתמשים במצרך זה")
                        .font(.rubik(13.1))
                        .foregroundStyle(Theme.inkLight)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminColors.warningBackground, in: RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        TextField("סנן מצרכים...", text: $query).autocorrectionDisabled().fieldBox()
                        Menu {
                            ForEach(AliasRow.SortColumn.allCases) { column in
                                Button {
                                    sort(by: column)
                                } label: {
                                    Label(column.label, systemImage: sortColumn == column ? (ascending ? "arrow.up" : "arrow.down") : "")
                                }
                            }
                        } label: {
                            Label("מיון", systemImage: "arrow.up.arrow.down")
                                .font(.rubik(13.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.sandDark, lineWidth: 1.5))
                        }
                    }

                    if loading {
                        StateBox(spinnerColor: Theme.terracotta, message: "טוען מצרכים...")
                    } else if rows.isEmpty {
                        Text("אין מצרכים").font(.rubik(14)).foregroundStyle(Theme.inkMuted)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach($rows) { $row in
                                if row.matches(query) {
                                    AliasRowView(row: $row) { save(row) }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
        }
        .background(Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
        .task { if rows.isEmpty { await load() } }
        .alert("אישור פעולה", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { tool in
            Button("המשך", role: .destructive) { Task { await run(tool) } }
            Button("ביטול", role: .cancel) {}
        } message: { tool in
            Text(tool.message)
        }
        .alert("אבחון מצרך", isPresented: $askDiagnose) {
            TextField("שם מקורי של המצרך", text: $diagnoseName)
            Button("אבחן") { Task { await diagnose() } }
            Button("ביטול", role: .cancel) {}
        }
    }

    private var tools: some View {
        FlowLayout(spacing: 8) {
            Button(busyTool == "clean" ? "מנקה..." : "🧹 ניקוי כפילויות (כל המתכונים)") { Task { await cleanAll() } }
                .buttonStyle(ToolButtonStyle(color: Theme.olive))
            Button(busyTool == "strip" ? "מסיר כמויות..." : "✂️ הסר כמויות מטקסטים (חד-פעמי)") { confirm = .stripAmounts }
                .buttonStyle(ToolButtonStyle(color: Color(hex: 0x8B4513)))
            Button(titlesProgress ?? "✨ צור כותרות אוטומטיות לכל המתכונים") { confirm = .generateTitles }
                .buttonStyle(ToolButtonStyle(color: Color(hex: 0x6B5B95)))
            Button("🔍 אבחן מצרך") { askDiagnose = true }
                .buttonStyle(ToolButtonStyle(color: Color(hex: 0x555555)))
        }
        .disabled(busyTool != nil || titlesProgress != nil)
    }

    private func load() async {
        if let loaded = await session.run("שגיאה בטעינת המצרכים", { try await $0.aliasRows() }) {
            rows = sortColumn.map { AliasRow.sorted(loaded, by: $0, ascending: ascending) } ?? loaded
            saved = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        }
        loading = false
    }

    private func sort(by column: AliasRow.SortColumn) {
        if sortColumn == column { ascending.toggle() } else { sortColumn = column; ascending = true }
        rows = AliasRow.sorted(rows, by: column, ascending: ascending)
    }

    /// Saves a row's display name / note if they changed (`saveAlias`).
    private func save(_ row: AliasRow) {
        guard let before = saved[row.id] else { return }
        let display = row.displayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? row.originalName : row.displayName.trimmingCharacters(in: .whitespaces)
        let note = row.note.trimmingCharacters(in: .whitespaces)
        guard display != before.displayName || note != before.note else { return }
        Task {
            let ok = await session.run("שגיאה בשמירה", {
                try await $0.saveAlias(originalName: row.originalName, oldNote: before.note, displayName: display, note: note)
            }) != nil
            guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
            if ok {
                rows[index].displayName = display
                rows[index].note = note
                saved[row.id] = rows[index]
                session.show("נשמר ✓")
            } else {
                rows[index] = before
            }
        }
    }

    private func cleanAll() async {
        busyTool = "clean"
        defer { busyTool = nil }
        if let updated = await session.run({ try await $0.cleanAllDuplicates() }) {
            session.show("ניקוי הסתיים — \(updated) שלבים עודכנו")
        }
    }

    private func run(_ tool: Tool) async {
        switch tool {
        case .stripAmounts:
            busyTool = "strip"
            defer { busyTool = nil }
            guard let result = await session.run({ try await $0.stripAmounts() }) else { return }
            stripRemaining = result.remaining
            let message = "עודכנו \(result.updated) שלבים." + (result.remaining.isEmpty ? "" : " נותרו \(result.remaining.count) שלבים לבדיקה ידנית.")
            session.show(message, result.remaining.isEmpty ? .success : .info)
        case .generateTitles:
            titlesProgress = "מתחיל..."
            defer { titlesProgress = nil }
            guard let result = await session.run({ api in
                try await api.generateStepTitles { text in titlesProgress = text }
            }) else { return }
            session.show(result.total == 0 ? "אין שלבים לעדכון" : "עודכנו \(result.updated) כותרות")
        }
    }

    private func diagnose() async {
        let name = diagnoseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        diagnoseOutput = "טוען..."
        diagnoseOutput = await session.run({ try await $0.diagnose(name: name) }) ?? "שגיאה"
    }
}

struct AliasRowView: View {
    @Binding var row: AliasRow
    let save: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.originalName).font(.rubik(13.1)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Text("\(row.usageCount)")
                    .font(.rubik(12, .semibold))
                    .foregroundStyle(Theme.inkLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.sand, in: Capsule())
                    .accessibilityLabel("בשימוש ב-\(row.usageCount) מתכונים")
            }
            HStack(spacing: 6) {
                TextField(row.originalName, text: $row.displayName).focused($focused).onSubmit(save).fieldBox()
                TextField("הערה", text: $row.note).focused($focused).onSubmit(save).fieldBox()
            }
        }
        .padding(10)
        .card(radius: Theme.radius)
        // Saving on leaving the field, like the web table's `onblur`.
        .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
    }
}

// MARK: - Pantry staples

struct PantryView: View {
    @Environment(AdminSession.self) private var session
    @State private var staples: [AdminAPI.PantryItem] = []
    @State private var candidates: [IngredientGroup] = []
    @State private var loading = true
    @State private var adding = false

    private var chips: [IngredientGroup] {
        IngredientGroup.group(staples.map { ($0.id, $0.label) })
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("🧺 מוצרי יסוד").font(.display(22.4)).foregroundStyle(Theme.ink)
                    Text("מוצרי יסוד נספרים כ\"קיימים\" אוטומטית בחישוב % התאמה כשהטוגל מופעל ב\"מתכון לפי מצרכים\". לחיצה על מוצר מסירה אותו מהרשימה.")
                        .font(.rubik(13.1))
                        .foregroundStyle(Theme.inkMuted)

                    if loading {
                        StateBox(spinnerColor: Theme.olive, message: "טוען...")
                    } else if staples.isEmpty {
                        Text("אין מוצרי יסוד עדיין").font(.rubik(14)).foregroundStyle(Theme.inkMuted)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(chips) { group in
                                Button("\(group.displayName) ×") { Task { await remove(group) } }
                                    .buttonStyle(PillButtonStyle(fill: Theme.olive, border: Theme.olive, foreground: .white))
                            }
                        }
                    }

                    Button("+ הוסף מוצרי יסוד") { adding = true }
                        .buttonStyle(ToolButtonStyle())
                        .disabled(loading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .refreshable { await load() }
        }
        .background(Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
        .task { if staples.isEmpty { await load() } }
        .sheet(isPresented: $adding) {
            PantryAddSheet(candidates: candidates) { groups in Task { await add(groups) } }
        }
    }

    private func load() async {
        if let loaded = await session.run("שגיאה בטעינה", { try await $0.pantryStaples() }) {
            staples = loaded
            let stapleIDs = Set(loaded.map(\.id))
            if let all = try? await API.shared.ingredients() {
                candidates = IngredientGroup.group(all.filter { !stapleIDs.contains($0.id) }.map { ($0.id, $0.label) })
            }
        }
        loading = false
    }

    private func add(_ groups: [IngredientGroup]) async {
        let ids = groups.flatMap(\.ids)
        guard !ids.isEmpty else { return }
        let ok = await session.run({ api -> Void in
            for id in ids { try await api.addPantryStaple(ingredientID: id) }
        }) != nil
        await load()
        if ok { session.show("נוספו \(groups.count) מוצרים ✓") }
    }

    private func remove(_ group: IngredientGroup) async {
        let ok = await session.run({ api -> Void in
            for id in group.ids { try await api.removePantryStaple(ingredientID: id) }
        }) != nil
        await load()
        if ok { session.show("הוסר ✓") }
    }
}

struct PantryAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [IngredientGroup]
    let onAdd: ([IngredientGroup]) -> Void

    @State private var selected: Set<String> = []
    @State private var query = ""

    private var visible: [IngredientGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? candidates : candidates.filter { $0.displayName.contains(q) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("הוספת מוצרי יסוד").font(.display(18.4)).foregroundStyle(Theme.ink)
                Spacer()
                Button("ביטול") { dismiss() }.font(.rubik(14.4)).foregroundStyle(Theme.inkMuted)
            }
            TextField("חיפוש...", text: $query).autocorrectionDisabled().fieldBox()
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(visible) { group in
                        let isSelected = selected.contains(group.id)
                        Button(group.displayName) {
                            if isSelected { selected.remove(group.id) } else { selected.insert(group.id) }
                        }
                        .buttonStyle(PillButtonStyle(
                            fill: isSelected ? Theme.olive : .white,
                            border: isSelected ? Theme.olive : Theme.sandDark,
                            foreground: isSelected ? .white : Theme.inkLight
                        ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("+ הוסף נבחרים (\(selected.count))") {
                onAdd(candidates.filter { selected.contains($0.id) })
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.olive))
            .disabled(selected.isEmpty)
        }
        .padding(20)
        .presentationBackground(.white)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - Site settings

struct SiteSettingsView: View {
    @Environment(AdminSession.self) private var session
    @State private var siteName = ""
    @State private var heroTitle = ""
    @State private var siteDescription = ""
    @State private var heroImage = ""
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            AdminHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("⚙️ הגדרות אתר").font(.display(22.4)).foregroundStyle(Theme.ink)
                    AdminField(label: "שם האתר", text: $siteName, placeholder: "מתכונים מחושבים")
                    AdminField(label: "כותרת דף הבית", text: $heroTitle, placeholder: "מתכונים עם אהבה")
                    AdminField(label: "תיאור האתר (מוצג מתחת לכותרת)", text: $siteDescription,
                               placeholder: "מטבח ביתי חם — מתכונים אמיתיים...", lines: 2)
                    FieldLabel(text: "תמונה ראשית של דף הבית")
                    ImageField(url: $heroImage, height: 120, placeholder: "📷\nלחץ לבחירת תמונה ראשית", allowsPositioning: false)
                    Button(saving ? "שומר..." : "💾 שמור הגדרות") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(saving)

                    Button("התנתק") { session.logout() }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        guard let settings = try? await API.shared.settings() else { return }
        siteName = settings["site_name"] ?? ""
        heroTitle = settings["hero_title"] ?? ""
        siteDescription = settings["site_description"] ?? ""
        heroImage = [settings["main_image_url"], settings["hero_image_url"], settings["hero_image"]]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let ok = await session.run("שגיאה בשמירת ההגדרות", {
            try await $0.saveSettings(
                siteName: siteName.trimmingCharacters(in: .whitespaces),
                heroTitle: heroTitle.trimmingCharacters(in: .whitespaces),
                description: siteDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                mainImageURL: heroImage.trimmingCharacters(in: .whitespaces)
            )
        }) != nil
        if ok { session.show("ההגדרות נשמרו ✓") }
    }
}
