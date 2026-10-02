import Foundation

// The backend (node-postgres) returns NUMERIC columns as JSON strings and
// INTEGER columns as numbers, so numeric fields are decoded leniently.
extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return JSNumber.string(d) }
        return nil
    }

    func flexInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Double(s).map { Int($0) } }
        return nil
    }

    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func optString(_ key: Key) -> String? {
        (try? decodeIfPresent(String.self, forKey: key)) ?? nil
    }
}

enum JSNumber {
    /// Formats a number the way JavaScript's `String(n)` would for the values we deal with.
    static func string(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }
}

enum APIDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }
}

struct RecipeIngredient: Decodable, Hashable {
    let id: Int
    let name: String
    let displayName: String?
    /// Raw amount as sent by the API (NUMERIC → string), e.g. "70" or "0.5".
    let amount: String?
    let unit: String?
    let note: String?

    enum CodingKeys: String, CodingKey { case id, name, displayName = "display_name", amount, unit, note }

    init(id: Int, name: String, displayName: String? = nil, amount: String? = nil, unit: String? = nil, note: String? = nil) {
        self.id = id; self.name = name; self.displayName = displayName
        self.amount = amount; self.unit = unit; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        name = c.optString(.name) ?? ""
        displayName = c.optString(.displayName)
        amount = c.flexString(.amount)
        unit = c.optString(.unit)
        note = c.optString(.note)
    }

    /// `ing.display_name || ing.name`
    var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }
}

struct RecipeStep: Decodable, Hashable, Identifiable {
    let id: Int
    let stepOrder: Int
    let title: String?
    let text: String
    let imageUrl: String?
    let timerSeconds: Int
    let prepMinutes: Int
    let cookMinutes: Int
    let showTimer: Bool
    let showPrepTimer: Bool
    let showCookTimer: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, text
        case stepOrder = "step_order", imageUrl = "image_url", timerSeconds = "timer_seconds"
        case prepMinutes = "prep_minutes", cookMinutes = "cook_minutes"
        case showTimer = "show_timer", showPrepTimer = "show_prep_timer", showCookTimer = "show_cook_timer"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        stepOrder = c.flexInt(.stepOrder) ?? 0
        title = c.optString(.title)
        text = c.optString(.text) ?? ""
        imageUrl = c.optString(.imageUrl)
        timerSeconds = c.flexInt(.timerSeconds) ?? 0
        prepMinutes = c.flexInt(.prepMinutes) ?? 0
        cookMinutes = c.flexInt(.cookMinutes) ?? 0
        // The web checks `!== false`, so a missing/null flag means "show".
        showTimer = ((try? c.decodeIfPresent(Bool.self, forKey: .showTimer)) ?? nil) ?? true
        showPrepTimer = ((try? c.decodeIfPresent(Bool.self, forKey: .showPrepTimer)) ?? nil) ?? true
        showCookTimer = ((try? c.decodeIfPresent(Bool.self, forKey: .showCookTimer)) ?? nil) ?? true
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "שלב \(stepOrder)"
    }

    var hasPrepTimer: Bool { prepMinutes > 0 && showPrepTimer }
    var hasCookTimer: Bool { cookMinutes > 0 && showCookTimer }
    var hasPlainTimer: Bool { !hasPrepTimer && !hasCookTimer && timerSeconds > 0 && showTimer }
}

struct RecipeNote: Decodable, Hashable, Identifiable {
    let id: Int
    let noteText: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey { case id, noteText = "note_text", createdAt = "created_at" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        noteText = c.optString(.noteText) ?? ""
        createdAt = APIDate.parse(c.optString(.createdAt))
    }
}

struct MissingIngredient: Decodable, Hashable {
    let id: Int
    let name: String
    let displayName: String?

    enum CodingKeys: String, CodingKey { case id, name, displayName = "display_name" }

    var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }
}

/// A recipe row. Used for the list (`/api/recipes`), the detail (`/api/recipes/:id`,
/// which adds ingredients/steps/notes/related), related cards and fridge results
/// (which add `match_percent` / `missing_ingredients`).
struct Recipe: Decodable, Hashable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let difficulty: String?
    let prepTime: Int?
    let cookTime: Int?
    let servings: Int?
    let category: String?
    let tags: [String]
    let imageUrl: String?
    let createdAt: Date?
    let storyText: String?

    var ingredients: [RecipeIngredient]
    var steps: [RecipeStep]
    var notes: [RecipeNote]
    var related: [Recipe]

    let matchPercent: Int?
    let missingIngredients: [MissingIngredient]

    enum CodingKeys: String, CodingKey {
        case id, title, description, difficulty, servings, category, tags
        case prepTime = "prep_time", cookTime = "cook_time", imageUrl = "image_url"
        case createdAt = "created_at", storyText = "story_text"
        case ingredients, steps, notes, related
        case matchPercent = "match_percent", missingIngredients = "missing_ingredients"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        title = c.optString(.title) ?? ""
        description = c.optString(.description)
        difficulty = c.optString(.difficulty)
        prepTime = c.flexInt(.prepTime)
        cookTime = c.flexInt(.cookTime)
        servings = c.flexInt(.servings)
        category = c.optString(.category)
        tags = ((try? c.decodeIfPresent([String].self, forKey: .tags)) ?? nil) ?? []
        imageUrl = c.optString(.imageUrl)
        createdAt = APIDate.parse(c.optString(.createdAt))
        storyText = c.optString(.storyText)
        ingredients = ((try? c.decodeIfPresent([RecipeIngredient].self, forKey: .ingredients)) ?? nil) ?? []
        steps = ((try? c.decodeIfPresent([RecipeStep].self, forKey: .steps)) ?? nil) ?? []
        notes = ((try? c.decodeIfPresent([RecipeNote].self, forKey: .notes)) ?? nil) ?? []
        related = ((try? c.decodeIfPresent([Recipe].self, forKey: .related)) ?? nil) ?? []
        matchPercent = c.flexInt(.matchPercent)
        missingIngredients = ((try? c.decodeIfPresent([MissingIngredient].self, forKey: .missingIngredients)) ?? nil) ?? []
    }

    /// `(r.prep_time || 0) + (r.cook_time || 0)`
    var totalMinutes: Int { (prepTime ?? 0) + (cookTime ?? 0) }
}

struct Nutrition: Decodable {
    let calories: String?
    let proteinG: String?
    let fatG: String?
    let carbsG: String?
    let sugarG: String?
    let fiberG: String?
    let sodiumMg: String?
    let perServings: Int?
    let totalWeightG: Double?

    enum CodingKeys: String, CodingKey {
        case calories, proteinG = "protein_g", fatG = "fat_g", carbsG = "carbs_g"
        case sugarG = "sugar_g", fiberG = "fiber_g", sodiumMg = "sodium_mg"
        case perServings = "per_servings", totalWeightG = "total_weight_g"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = c.flexString(.calories)
        proteinG = c.flexString(.proteinG)
        fatG = c.flexString(.fatG)
        carbsG = c.flexString(.carbsG)
        sugarG = c.flexString(.sugarG)
        fiberG = c.flexString(.fiberG)
        sodiumMg = c.flexString(.sodiumMg)
        perServings = c.flexInt(.perServings)
        totalWeightG = c.flexDouble(.totalWeightG)
    }

    struct Row: Identifiable {
        let label: String
        let value: String
        let unit: String
        let decimal: Bool
        var id: String { label }
    }

    var rows: [Row] {
        [
            Row(label: "קלוריות", value: calories ?? "0", unit: "קק\"ל", decimal: false),
            Row(label: "חלבון", value: proteinG ?? "0", unit: "ג׳", decimal: true),
            Row(label: "שומן", value: fatG ?? "0", unit: "ג׳", decimal: true),
            Row(label: "פחמימות", value: carbsG ?? "0", unit: "ג׳", decimal: true),
            Row(label: "סיבים תזונתיים", value: fiberG ?? "0", unit: "ג׳", decimal: true),
            Row(label: "סוכר", value: sugarG ?? "0", unit: "ג׳", decimal: true),
            Row(label: "נתרן", value: sodiumMg ?? "0", unit: "מ\"ג", decimal: false),
        ]
    }

    var hasPer100: Bool { (totalWeightG ?? 0) > 0 }

    /// `(parseFloat(val) / servingWeightG) * 100`, 1 decimal for grams, rounded otherwise.
    func per100(_ row: Row) -> String {
        guard let weight = totalWeightG, weight > 0 else { return "" }
        let v = (Double(row.value) ?? 0) / weight * 100
        return row.decimal ? String(format: "%.1f", v) : String(Int((v + 0.5).rounded(.down)))
    }
}

struct CatalogIngredient: Decodable, Hashable {
    let id: Int
    let name: String
    let isPantryStaple: Bool
    let displayName: String?
    let recipeCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, isPantryStaple = "is_pantry_staple", displayName = "display_name", recipeCount = "recipe_count"
    }

    init(id: Int, name: String, isPantryStaple: Bool = false, displayName: String? = nil, recipeCount: Int = 0) {
        self.id = id; self.name = name; self.isPantryStaple = isPantryStaple
        self.displayName = displayName; self.recipeCount = recipeCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt(.id) ?? 0
        name = c.optString(.name) ?? ""
        isPantryStaple = ((try? c.decodeIfPresent(Bool.self, forKey: .isPantryStaple)) ?? nil) ?? false
        displayName = c.optString(.displayName)
        recipeCount = c.flexInt(.recipeCount) ?? 0
    }

    var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }
}
