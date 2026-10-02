import Foundation

/// Faithful ports of the quantity and step-text helpers in recipe.html.
enum Amount {
    /// `formatAmount(n)`: rounds to the nearest quarter and renders ¼ ½ ¾.
    static func format(_ n: Double) -> String {
        if n == 0 || n.isNaN { return "" }
        let rounded = (n * 4 + 0.5).rounded(.down) / 4   // Math.round
        let whole = rounded.rounded(.down)
        let frac = rounded - whole
        let wholeStr = String(Int(whole))
        let fracs: [Double: String] = [0.25: "¼", 0.5: "½", 0.75: "¾"]
        if frac == 0 { return wholeStr }
        if whole == 0 { return fracs[frac] ?? String(format: "%.2f", rounded) }
        return wholeStr + (fracs[frac] ?? "+" + String(format: "%.2f", frac))
    }

    /// JavaScript `parseFloat`: parses the leading numeric prefix, NaN otherwise.
    static func parseFloat(_ s: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(trimmed) { return d }
        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = nil
        return scanner.scanDouble() ?? .nan
    }

    /// `ing.amount ? formatAmount(parseFloat(ing.amount) * ratio) : ''`
    static func scaled(_ ingredient: RecipeIngredient, ratio: Double) -> String {
        guard let amount = ingredient.amount, !amount.isEmpty else { return "" }
        return format(parseFloat(amount) * ratio)
    }

    /// The ingredient-list amount cell: `${amt}${ing.unit ? ' ' + ing.unit : ''}`
    static func listText(_ ingredient: RecipeIngredient, ratio: Double) -> String {
        let amt = scaled(ingredient, ratio: ratio)
        if let unit = ingredient.unit, !unit.isEmpty { return amt + " " + unit }
        return amt
    }
}

enum StepText {
    // Hebrew prefix letters that may precede an ingredient name (ו ה ב ל מ כ + combined).
    private static let prefixAlt = ["וה", "וב", "ול", "ו", "ה", "ב", "ל", "מ", "כ"].joined(separator: "|")
    // Boundary chars allowed immediately before/after an ingredient match.
    private static let boundary = "[\\s,.:;!?()\"'׳״—–\\-…]"
    // Optional Hebrew suffix (up to 2 letters) — absorbs plural/construct endings.
    private static let suffix = "(?:[\\u05D0-\\u05EA]{1,2})?"

    private static let amountStripRE = try! NSRegularExpression(
        pattern: "\\s*\\(\\s*[0-9.,½¼¾⅓⅔]+\\s*[-–]?\\s*[0-9.,½¼¾⅓⅔]*\\s*(?:גרם|מ״ל|מ\"ל|כף|כפיות?|כפות|ק״ג|ק\"ג|ליטר|יחידות?|יח׳|יח'|ס\"מ|°C|מעלות|ג׳|ג'|מל|כוס|כוסות|קורט|לפי הטעם|לפי הצורך)\\s*\\)",
        options: [.caseInsensitive]
    )
    private static let multiSpaceRE = try! NSRegularExpression(pattern: "\\s{2,}")
    private static let cleanRE = try! NSRegularExpression(
        pattern: "\\s*\\([^)]*(?:גרם|מ״ל|מ\"ל|כף|כפית|ק״ג|ק\"ג|ליטר|יחידות?|ס\"מ|ס״מ|יח'|יח׳)[^)]*\\)"
    )
    private static let whitespaceRE = try! NSRegularExpression(pattern: "\\s+")

    private static func replaceAll(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    /// `stripExistingAmounts(text)`
    static func stripExistingAmounts(_ text: String) -> String {
        let stripped = replaceAll(amountStripRE, in: text, with: "")
        return replaceAll(multiSpaceRE, in: stripped, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `cleanStepText(text)` — what the web keeps in `stepOriginals` for re-rendering after a servings change.
    static func clean(_ text: String) -> String {
        replaceAll(cleanRE, in: text, with: "")
    }

    /// Escapes a name for use in a regex and lets any whitespace run match `\s+`.
    private static func variantPattern(_ name: String) -> String {
        let ns = name as NSString
        var out = ""
        var last = 0
        for m in whitespaceRE.matches(in: name, range: NSRange(location: 0, length: ns.length)) {
            out += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            out += "\\s+"
            last = m.range.location + m.range.length
        }
        out += NSRegularExpression.escapedPattern(for: ns.substring(from: last))
        return out
    }

    /// Unique (first occurrence wins), then longest first — stable, like JS `Array.prototype.sort`.
    private static func uniqueLongestFirst(_ names: [String]) -> [String] {
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        return stableSortedByLengthDesc(unique) { $0 }
    }

    private static func stableSortedByLengthDesc<T>(_ items: [T], _ key: (T) -> String) -> [T] {
        items.enumerated().sorted { a, b in
            let la = key(a.element).utf16.count, lb = key(b.element).utf16.count
            return la != lb ? la > lb : a.offset < b.offset
        }.map(\.element)
    }

    /// `highlightIngredients(text)`: returns the same HTML string the website builds —
    /// each ingredient mention becomes `<strong>name</strong><span …> (amount unit)</span>`.
    static func highlightHTML(_ text: String, ingredients: [RecipeIngredient], ratio: Double) -> String {
        guard !ingredients.isEmpty else { return text }
        var result = stripExistingAmounts(text)

        // Group ingredients by display name so duplicate entries share a per-name occurrence counter.
        var order: [String] = []
        var groups: [String: [RecipeIngredient]] = [:]
        for ing in ingredients {
            let displayName = ing.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if displayName.isEmpty { continue }
            if groups[displayName] == nil { order.append(displayName) }
            groups[displayName, default: []].append(ing)
        }

        // Longest name first to avoid partial matches.
        for displayName in stableSortedByLengthDesc(order, { $0 }) {
            let ings = groups[displayName]!
            let names = ings.flatMap { ing in
                [displayName, ing.name.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
            }
            let variants = uniqueLongestFirst(names).map(variantPattern)
            guard let re = try? NSRegularExpression(
                pattern: "(^|\(boundary))((?:\(prefixAlt))?)(\(variants.joined(separator: "|")))(\(suffix))(?=\\z|\(boundary))"
            ) else { continue }

            let ns = result as NSString
            var out = ""
            var last = 0
            var counter = 0
            for m in re.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let p1 = ns.substring(with: m.range(at: 1))
                let p2 = ns.substring(with: m.range(at: 2))
                let p4 = ns.substring(with: m.range(at: 4))
                // For duplicates: first text occurrence → first list entry, second → second, etc.
                let ing = counter < ings.count ? ings[counter] : ings[ings.count - 1]
                counter += 1
                let amt = Amount.scaled(ing, ratio: ratio)
                var amtStr = ""
                if !amt.isEmpty {
                    amtStr = " (" + amt
                    if let unit = ing.unit, !unit.isEmpty { amtStr += " " + unit }
                    amtStr += ")"
                }
                out += "\(p1)\(p2)<strong>\(displayName)\(p4)</strong><span style=\"color:var(--ink-muted);font-weight:400\">\(amtStr)</span>"
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            result = out
        }
        return result
    }

    /// The matcher `markStepIngredientsDone` uses to tick ingredient-list rows a step mentions.
    static func mentions(_ ingredient: RecipeIngredient, in text: String) -> Bool {
        let names = [ingredient.displayName, ingredient.name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let variants = uniqueLongestFirst(names).map(variantPattern)
        guard !variants.isEmpty,
              let re = try? NSRegularExpression(
                pattern: "(^|\(boundary))(?:\(prefixAlt))?(?:\(variants.joined(separator: "|")))\(suffix)(?=\\z|\(boundary))"
              ) else { return false }
        return re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: - HTML → styled runs

    struct Run: Equatable {
        enum Style: Equatable { case plain, strong, muted }
        var text: String
        var style: Style
    }

    private static let tagRE = try! NSRegularExpression(pattern: "<(/?)(strong|b|span|br)\\b[^>]*>", options: [.caseInsensitive])

    /// Splits the highlighted HTML into runs. Only the tags the highlighter emits
    /// (plus `<b>`/`<br>`) are interpreted; anything else stays literal text.
    static func runs(fromHTML html: String) -> [Run] {
        let ns = html as NSString
        var runs: [Run] = []
        var strongDepth = 0
        var spanDepth = 0
        var last = 0

        func append(_ s: String) {
            guard !s.isEmpty else { return }
            let style: Run.Style = spanDepth > 0 ? .muted : (strongDepth > 0 ? .strong : .plain)
            if let lastRun = runs.last, lastRun.style == style {
                runs[runs.count - 1].text += s
            } else {
                runs.append(Run(text: s, style: style))
            }
        }

        for m in tagRE.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            let closing = m.range(at: 1).length > 0
            switch ns.substring(with: m.range(at: 2)).lowercased() {
            case "strong", "b": strongDepth = max(0, strongDepth + (closing ? -1 : 1))
            case "span": spanDepth = max(0, spanDepth + (closing ? -1 : 1))
            default: append("\n")
            }
            last = m.range.location + m.range.length
        }
        append(ns.substring(from: last))
        return runs
    }
}
