import CoreGraphics
import Foundation

/// JavaScript-style number parsing, as admin.html's `collectForm()` uses.
enum JSParse {
    /// `parseInt(s) || fallback`: leading integer digits, 0 / NaN count as missing.
    static func int(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        var digits = ""
        for (i, ch) in trimmed.enumerated() {
            if ch.isASCII, ch.isNumber { digits.append(ch) } else if i == 0, ch == "-" || ch == "+" { digits.append(ch) } else { break }
        }
        guard let value = Int(digits), value != 0 else { return nil }
        return value
    }

    /// `parseFloat(s) || null`
    static func float(_ s: String) -> Double? {
        let value = Amount.parseFloat(s)
        return value.isNaN || value == 0 ? nil : value
    }
}

struct IngredientDraft: Identifiable, Equatable {
    let id = UUID()
    /// What the field shows: the display name when there is one.
    var name = ""
    /// `data-original` / `data-display`: used to send the original name back when the field is untouched.
    var original = ""
    var display = ""
    var amount = ""
    var unit = ""
    var note = ""

    init() {}

    init(_ ingredient: RecipeIngredient) {
        name = ingredient.label
        original = ingredient.name
        display = ingredient.label
        amount = ingredient.amount ?? ""
        unit = ingredient.unit ?? ""
        note = ingredient.note ?? ""
    }

    /// `(orig && typed === disp) ? orig : typed`
    var payloadName: String {
        let typed = name.trimmingCharacters(in: .whitespaces)
        return (!original.isEmpty && typed == display) ? original : typed
    }

    /// "שם מקורי: …" is shown when the stored name differs from the display name.
    var originalLabel: String? {
        (!original.isEmpty && original != display) ? "שם מקורי: \(original)" : nil
    }
}

struct StepDraft: Identifiable, Equatable {
    let id = UUID()
    var title = ""
    var text = ""
    var timerMinutes = ""
    var prepMinutes = ""
    var cookMinutes = ""
    var showPrepTimer = true
    var showCookTimer = true
    var imageURL = ""

    init() {}

    init(_ step: RecipeStep) {
        title = step.title ?? ""
        text = step.text
        // `Math.round(timer_seconds / 60)`
        timerMinutes = step.timerSeconds > 0 ? String(Int((Double(step.timerSeconds) / 60 + 0.5).rounded(.down))) : ""
        prepMinutes = step.prepMinutes > 0 ? String(step.prepMinutes) : ""
        cookMinutes = step.cookMinutes > 0 ? String(step.cookMinutes) : ""
        showPrepTimer = step.showPrepTimer
        showCookTimer = step.showCookTimer
        imageURL = step.imageUrl ?? ""
    }
}

/// The recipe form (admin.html `renderForm` / `collectForm`).
struct RecipeDraft: Equatable {
    var id: Int?
    var title = ""
    var description = ""
    var story = ""
    var category = ""
    var difficulty = "easy"
    var prepTime = ""
    var cookTime = ""
    var servings = ""
    var tags = ""
    var imageURL = ""
    var isHidden = false
    var ingredients: [IngredientDraft] = []
    var steps: [StepDraft] = []

    init() {}

    init(_ recipe: Recipe) {
        id = recipe.id
        title = recipe.title
        description = recipe.description ?? ""
        story = recipe.storyText ?? ""
        category = recipe.category ?? ""
        difficulty = recipe.difficulty ?? "easy"
        prepTime = recipe.prepTime.flatMap { $0 > 0 ? String($0) : nil } ?? ""
        cookTime = recipe.cookTime.flatMap { $0 > 0 ? String($0) : nil } ?? ""
        servings = recipe.servings.flatMap { $0 > 0 ? String($0) : nil } ?? ""
        tags = recipe.tags.joined(separator: ", ")
        imageURL = recipe.imageUrl ?? ""
        isHidden = recipe.isHidden
        ingredients = recipe.ingredients.map(IngredientDraft.init)
        steps = recipe.steps.map(StepDraft.init)
    }

    private static func orNull(_ value: Any?) -> Any { value ?? NSNull() }
    private static func trimmedOrNull(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? NSNull() : t
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The JSON body for `POST /api/recipes` and `PUT /api/recipes/:id`.
    var payload: [String: Any] {
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let ingredientList: [[String: Any]] = ingredients.compactMap { ing in
            let name = ing.payloadName
            guard !name.isEmpty else { return nil }
            return [
                "name": name,
                "amount": Self.orNull(JSParse.float(ing.amount)),
                "unit": Self.trimmedOrNull(ing.unit),
                "note": Self.trimmedOrNull(ing.note),
            ]
        }

        let stepList: [[String: Any]] = steps.compactMap { step in
            let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return [
                "title": Self.trimmedOrNull(step.title),
                "text": text,
                "timer_seconds": Self.orNull(JSParse.int(step.timerMinutes).map { $0 * 60 }),
                "prep_minutes": JSParse.int(step.prepMinutes) ?? 0,
                "cook_minutes": JSParse.int(step.cookMinutes) ?? 0,
                "show_timer": true,
                "show_prep_timer": step.showPrepTimer,
                "show_cook_timer": step.showCookTimer,
                "image_url": Self.trimmedOrNull(step.imageURL),
            ]
        }

        return [
            "title": trimmedTitle,
            "description": Self.trimmedOrNull(description),
            "story_text": Self.trimmedOrNull(story),
            "category": Self.trimmedOrNull(category),
            "difficulty": difficulty,
            "prep_time": Self.orNull(JSParse.int(prepTime)),
            "cook_time": Self.orNull(JSParse.int(cookTime)),
            "servings": Self.orNull(JSParse.int(servings)),
            "is_hidden": isHidden,
            "tags": tagList,
            "ingredients": ingredientList,
            "steps": stepList,
            "image_url": Self.trimmedOrNull(imageURL),
        ]
    }

    /// `recalcTimes()`: recipe prep / cook totals follow the per-step minutes.
    mutating func recalcTimes() {
        let prep = steps.reduce(0) { $0 + (JSParse.int($1.prepMinutes) ?? 0) }
        let cook = steps.reduce(0) { $0 + (JSParse.int($1.cookMinutes) ?? 0) }
        prepTime = prep > 0 ? String(prep) : ""
        cookTime = cook > 0 ? String(cook) : ""
    }

    /// Whether no step mentions the ingredient (by its typed or original name) — the yellow highlight.
    func isUnmentioned(_ ingredient: IngredientDraft) -> Bool {
        let display = ingredient.name.trimmingCharacters(in: .whitespaces)
        guard !display.isEmpty else { return false }
        let names = [display, ingredient.original.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
        for name in names {
            let probe = RecipeIngredient(id: 0, name: name)
            if steps.contains(where: { !$0.text.isEmpty && StepText.mentions(probe, in: $0.text) }) { return false }
        }
        return true
    }
}

enum AdminTimer {
    private static func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static func round(_ d: Double) -> Int { Int((d + 0.5).rounded(.down)) }

    /// Minutes mentioned in a step's text ("חצי שעה", "10-15 דקות", "כ-20 דקות", "2 שעות"), used to
    /// pre-fill an empty timer field. Unlike the website's version this also catches single numbers
    /// (there, a `\b` after Hebrew letters never matches).
    static func minutes(in text: String) -> Int? {
        if firstMatch("חצי\\s*שעה", text) != nil { return 30 }
        if firstMatch("רבע\\s*שעה", text) != nil { return 15 }
        if let m = firstMatch("(\\d+)\\s*[-–]\\s*(\\d+)\\s*דק", text), let a = Double(m[1]), let b = Double(m[2]) {
            return round((a + b) / 2)
        }
        if let m = firstMatch("(\\d+)\\s*[-–]\\s*(\\d+)\\s*שע", text), let a = Double(m[1]), let b = Double(m[2]) {
            return round((a + b) / 2) * 60
        }
        if let m = firstMatch("(?:כ[-\\s]?)?(\\d+(?:\\.\\d+)?)\\s*(?:דקות|דקה|דק[׳'\"]?)(?![א-ת])", text), let v = Double(m[1]) {
            return round(v)
        }
        if let m = firstMatch("(?:כ[-\\s]?)?(\\d+(?:\\.\\d+)?)\\s*(?:שעות|שעה)(?![א-ת])", text), let v = Double(m[1]) {
            return round(v * 60)
        }
        return nil
    }
}

/// The image position editor's geometry (admin.html `updateCropView` / `applyCrop`).
struct CropState: Equatable {
    var offset: CGSize = .zero
    var zoom: CGFloat = 1

    private func baseScale(image: CGSize, viewport: CGSize) -> CGFloat {
        max(viewport.width / max(image.width, 1), viewport.height / max(image.height, 1))
    }

    func displayedSize(image: CGSize, viewport: CGSize) -> CGSize {
        let s = baseScale(image: image, viewport: viewport) * zoom
        return CGSize(width: image.width * s, height: image.height * s)
    }

    /// Keeps the image covering the viewport.
    mutating func clamp(image: CGSize, viewport: CGSize) {
        let size = displayedSize(image: image, viewport: viewport)
        let maxX = max(0, (size.width - viewport.width) / 2)
        let maxY = max(0, (size.height - viewport.height) / 2)
        offset.width = min(maxX, max(-maxX, offset.width))
        offset.height = min(maxY, max(-maxY, offset.height))
    }

    /// Top-left corner of the image inside the viewport.
    func origin(image: CGSize, viewport: CGSize) -> CGPoint {
        let size = displayedSize(image: image, viewport: viewport)
        return CGPoint(x: viewport.width / 2 - size.width / 2 + offset.width,
                       y: viewport.height / 2 - size.height / 2 + offset.height)
    }

    /// Restores the editor from a stored `#pos=`.
    init(position: ImagePosition?, image: CGSize, viewport: CGSize) {
        guard let position else { return }
        zoom = min(3, max(1, position.zoom))
        let s = baseScale(image: image, viewport: viewport)
        offset = CGSize(width: (0.5 - position.x / 100) * image.width * s * zoom,
                        height: (0.5 - position.y / 100) * image.height * s * zoom)
        clamp(image: image, viewport: viewport)
    }

    init() {}

    func position(image: CGSize, viewport: CGSize) -> ImagePosition {
        let size = displayedSize(image: image, viewport: viewport)
        func pct(_ offset: CGFloat, _ length: CGFloat) -> Double {
            ((0.5 - offset / max(length, 1)) * 100 + 0.5).rounded(.down)
        }
        return ImagePosition(x: pct(offset.width, size.width), y: pct(offset.height, size.height),
                             zoom: (Double(zoom) * 100).rounded() / 100)
    }

    /// `${base}#pos=${x},${y},${z}`
    static func url(base: String, position: ImagePosition) -> String {
        "\(ImageURL.base(base))#pos=\(JSNumber.string(position.x)),\(JSNumber.string(position.y)),\(JSNumber.string(position.zoom))"
    }
}

/// Ingredients sharing a display name, handled as one item (pantry chips and the add list).
struct IngredientGroup: Identifiable, Hashable {
    let displayName: String
    var ids: [Int]
    var id: String { displayName }

    static func group(_ items: [(id: Int, label: String)]) -> [IngredientGroup] {
        var order: [String] = []
        var map: [String: [Int]] = [:]
        for item in items {
            if map[item.label] == nil { order.append(item.label) }
            if !(map[item.label] ?? []).contains(item.id) { map[item.label, default: []].append(item.id) }
        }
        let he = Locale(identifier: "he")
        return order.map { IngredientGroup(displayName: $0, ids: map[$0] ?? []) }
            .sorted { $0.displayName.compare($1.displayName, locale: he) == .orderedAscending }
    }
}

/// A row of the ingredient manager (`/api/admin/ingredients/all`).
struct AliasRow: Identifiable, Decodable, Equatable {
    let id = UUID()
    let originalName: String
    var displayName: String
    var note: String
    let usageCount: Int

    enum CodingKeys: String, CodingKey {
        case originalName = "original_name", displayName = "display_name", note, usageCount = "usage_count"
    }

    init(originalName: String, displayName: String, note: String, usageCount: Int) {
        self.originalName = originalName; self.displayName = displayName; self.note = note; self.usageCount = usageCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalName = c.optString(.originalName) ?? ""
        let display = c.optString(.displayName) ?? ""
        displayName = display.isEmpty ? originalName : display
        note = c.optString(.note) ?? ""
        usageCount = c.flexInt(.usageCount) ?? 0
    }

    enum SortColumn: String, CaseIterable, Identifiable {
        case originalName, displayName, note, usageCount
        var id: String { rawValue }
        var label: String {
            switch self {
            case .originalName: "שם מקורי"
            case .displayName: "שם תצוגה"
            case .note: "הערה"
            case .usageCount: "שימוש"
            }
        }
    }

    static func sorted(_ rows: [AliasRow], by column: SortColumn, ascending: Bool) -> [AliasRow] {
        let he = Locale(identifier: "he")
        return rows.enumerated().sorted { a, b in
            let order: ComparisonResult
            switch column {
            case .originalName: order = a.element.originalName.compare(b.element.originalName, locale: he)
            case .displayName: order = a.element.displayName.compare(b.element.displayName, locale: he)
            case .note: order = a.element.note.compare(b.element.note, locale: he)
            case .usageCount:
                order = a.element.usageCount == b.element.usageCount ? .orderedSame
                    : (a.element.usageCount < b.element.usageCount ? .orderedAscending : .orderedDescending)
            }
            if order == .orderedSame { return a.offset < b.offset }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.map(\.element)
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || originalName.lowercased().contains(q) || displayName.lowercased().contains(q) || note.lowercased().contains(q)
    }
}
