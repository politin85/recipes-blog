import Foundation

/// Ports of the pure helpers in fridge.html.
enum FridgeLogic {
    private static let categoryRules: [(pattern: String, category: String)] = [
        ("(עגבני|מלפפון|גזר|בצל|שום|פלפל.*ירוק|חסה|תרד|כרוב|קישוא|חציל|פטריה|סלרי|ברוקולי|כרישה|קולרבי|סלק|אספרגוס|ארטישוק|בטטה|תפוחי אדמה|דלע|שמפיניון|תירס|אפונה.*טרי|ראדיש)", "ירקות"),
        ("(תפוח|בננה|תות|לימון|תפוז|אבוקדו|מנגו|אוכמניות|פירות יער|צימוק|משמש|שזיף|אגס|ענבים|מלון|אבטיח|רימון|קיוי|אננס|פסיפלורה|ליים)", "פירות"),
        ("(גבינה|יוגורט|שמנת|ריקוטה|פרמזן|מוצרלה|גאודה|בולגרי|קוטג|מסקרפון|לבנה|חמאה|ביצ|חלב|קרם פרש)", "גבינות ומוצרי חלב"),
        ("(עוף|פרגית|בקר|כבש|טלה|טחון|נקניק|שוק|חזה|כנף|כבד|אנטריקוט|שניצל|סטייק|בשר|עגל|הודו)", "בשר ועוף"),
        ("(שרימפס|סלמון|טונה|דיונון|קלמרי|אנשובי|בקלה|מוסר|לוקוס|ברמונדי|פלמידה|אמנון|קרפיון|דג )", "דגים ופירות ים"),
        ("(עדשים|חומוס|שעועית|פול|קטניות|סויה|טופו|פולים)", "קטניות"),
        ("(קמח|אורז|פסטה|שיפון|כוסמת|קינואה|שיבולת שועל|פולנטה|קורנפלור|סולת|שמרים|מחמצת|גריסים|בורגול)", "דגנים וקמחים"),
        ("(פפריקה|כמון|כורכום|קינמון|אורגנו|בזיליקום|רוזמרין|טימין|עירית|פטרוזיליה|כוסברה|שמיר|נענע|זעתר|בהרת|קארי|צ.ילי|ג.ינג.ר|וניל|אגוז מוסקט|תבלין|כוכב אניס)", "תבלינים ועשבי תיבול"),
        ("(שמן|חומץ|רוטב|מיונז|חרדל|קטשופ|ציר|יין|בירה|מיץ|חלב קוקוס|שמן שומשום|טחינה|פסטו|האריסה)", "נוזלים ורטבות"),
    ]
    static let otherCategory = "אחר"

    private static let compiledRules: [(re: NSRegularExpression, category: String)] = categoryRules.map {
        (try! NSRegularExpression(pattern: $0.pattern), $0.category)
    }

    /// `categorizeIng(name)`
    static func category(for name: String) -> String {
        let range = NSRange(location: 0, length: (name as NSString).length)
        for rule in compiledRules where rule.re.firstMatch(in: name, range: range) != nil {
            return rule.category
        }
        return otherCategory
    }

    /// `buildDisplayGroups()`: display name → all ingredient ids sharing it.
    static func displayGroups(_ ingredients: [CatalogIngredient]) -> [String: [Int]] {
        var groups: [String: [Int]] = [:]
        var seen = Set<Int>()
        for ing in ingredients where seen.insert(ing.id).inserted {
            groups[ing.label, default: []].append(ing.id)
        }
        return groups
    }

    private static func dedupedByLabel(_ items: [CatalogIngredient]) -> [CatalogIngredient] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.label).inserted }
    }

    /// The autocomplete list: the 10 most common ingredients on an empty query,
    /// otherwise up to 8 prefix matches. Pantry staples and selected items are excluded.
    static func suggestions(query: String, ingredients: [CatalogIngredient], selected: Set<String>) -> [CatalogIngredient] {
        let cur = query.trimmingCharacters(in: .whitespaces).lowercased()
        let candidates = ingredients.filter { !$0.isPantryStaple && !selected.contains($0.label) }
        if cur.isEmpty { return dedupedByLabel(Array(candidates.prefix(10))) }
        return dedupedByLabel(Array(candidates.filter { $0.label.lowercased().hasPrefix(cur) }.prefix(8)))
    }

    /// What Enter picks when nothing is highlighted: the first exact or prefix match.
    static func submitMatch(query: String, ingredients: [CatalogIngredient]) -> CatalogIngredient? {
        let cur = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !cur.isEmpty else { return nil }
        return ingredients.first { $0.label.lowercased() == cur || $0.label.lowercased().hasPrefix(cur) }
    }

    struct CategoryGroup: Identifiable {
        let name: String
        let items: [CatalogIngredient]
        var id: String { name }
    }

    private static let hebrew = Locale(identifier: "he")

    /// The "show all" modal: non-pantry ingredients bucketed by category, "אחר" last.
    static func categoryGroups(_ ingredients: [CatalogIngredient]) -> [CategoryGroup] {
        var buckets: [String: [CatalogIngredient]] = [:]
        for ing in ingredients where !ing.isPantryStaple {
            buckets[category(for: ing.name), default: []].append(ing)
        }
        let names = buckets.keys.sorted { a, b in
            if a == otherCategory { return false }
            if b == otherCategory { return true }
            return a.compare(b, locale: hebrew) == .orderedAscending
        }
        return names.map { name in
            let sorted = buckets[name]!.sorted { $0.name.compare($1.name, locale: hebrew) == .orderedAscending }
            return CategoryGroup(name: name, items: dedupedByLabel(sorted))
        }
    }

    /// Highest match% first, alphabetical (Hebrew locale) on ties.
    static func sortResults(_ recipes: [Recipe]) -> [Recipe] {
        recipes.sorted { a, b in
            let pa = a.matchPercent ?? 0, pb = b.matchPercent ?? 0
            if pa != pb { return pa > pb }
            return a.title.compare(b.title, locale: hebrew) == .orderedAscending
        }
    }
}
