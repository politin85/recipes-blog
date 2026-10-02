import Foundation

/// The home page's client-side filtering and sorting (index.html `filtered()` / `getSorted()`).
struct RecipeFilter: Equatable {
    enum TimeRange: String, CaseIterable, Identifiable {
        case any = "", short, medium, long
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: "כל הזמנים"
            case .short: "עד 30 דק'"
            case .medium: "30–60 דק'"
            case .long: "שעה+"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case dateDesc = "date-desc", dateAsc = "date-asc"
        case diffEasy = "diff-easy", diffHard = "diff-hard"
        case timeAsc = "time-asc", timeDesc = "time-desc"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dateDesc: "חדש לישן"
            case .dateAsc: "ישן לחדש"
            case .diffEasy: "קושי: קל → מאתגר"
            case .diffHard: "קושי: מאתגר → קל"
            case .timeAsc: "זמן: קצר → ארוך"
            case .timeDesc: "זמן: ארוך → קצר"
            }
        }
        var groupsByDifficulty: Bool { self == .diffEasy || self == .diffHard }
    }

    var search = ""
    var category = ""
    var difficulty = ""
    var timeRange: TimeRange = .any
    var sort: Sort = .dateDesc

    /// The number shown on the filter button's badge.
    var badgeCount: Int {
        [!category.isEmpty, !difficulty.isEmpty, timeRange != .any, sort != .dateDesc].filter { $0 }.count
    }

    func matches(_ r: Recipe) -> Bool {
        if !difficulty.isEmpty, r.difficulty != difficulty { return false }
        if !category.isEmpty, r.category != category { return false }
        let total = r.totalMinutes
        switch timeRange {
        case .any: break
        case .short: if total > 30 { return false }
        case .medium: if total <= 30 || total > 60 { return false }
        case .long: if total <= 60 { return false }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            let inTitle = r.title.lowercased().contains(q)
            let inTags = r.tags.contains { $0.lowercased().contains(q) }
            let inCat = (r.category ?? "").lowercased().contains(q)
            if !inTitle && !inTags && !inCat { return false }
        }
        return true
    }

    private static let diffOrder = ["easy": 0, "medium": 1, "hard": 2]

    func apply(to recipes: [Recipe], favoritesOnly: Bool, favorites: [Int]) -> [Recipe] {
        var list = recipes
        if favoritesOnly { list = list.filter { favorites.contains($0.id) } }
        list = list.filter(matches)

        func diff(_ r: Recipe) -> Int { r.difficulty.flatMap { Self.diffOrder[$0] } ?? 1 }
        func date(_ r: Recipe) -> TimeInterval { r.createdAt?.timeIntervalSince1970 ?? 0 }

        // Stable, like Array.prototype.sort.
        return list.enumerated().sorted { a, b in
            let cmp: Double
            switch sort {
            case .dateAsc: cmp = date(a.element) - date(b.element)
            case .diffEasy: cmp = Double(diff(a.element) - diff(b.element))
            case .diffHard: cmp = Double(diff(b.element) - diff(a.element))
            case .timeAsc: cmp = Double(a.element.totalMinutes - b.element.totalMinutes)
            case .timeDesc: cmp = Double(b.element.totalMinutes - a.element.totalMinutes)
            case .dateDesc: cmp = date(b.element) - date(a.element)
            }
            return cmp != 0 ? cmp < 0 : a.offset < b.offset
        }.map(\.element)
    }

    static func categories(in recipes: [Recipe]) -> [String] {
        Array(Set(recipes.compactMap(\.category).filter { !$0.isEmpty })).sorted()
    }
}
