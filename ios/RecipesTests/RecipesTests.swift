import Foundation
import Testing
@testable import Recipes

private final class BundleToken {}

private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

// MARK: - Port fidelity (against the website's own JavaScript)

/// HighlightFixtures.json is produced by scripts/make_highlight_fixtures.js, which runs the
/// functions lifted from recipe.html over every live recipe.
private struct Fixtures: Decodable {
    struct AmountCase: Decodable { let n: Double; let text: String }
    struct Case: Decodable { let servings: Int; let html: String }
    struct Step: Decodable { let text: String; let cleaned: String; let mentions: [Bool]; let cases: [Case] }
    struct Recipe: Decodable { let id: Int; let servings: Int?; let ingredients: [RecipeIngredient]; let steps: [Step] }
    let amounts: [AmountCase]
    let recipes: [Recipe]

    static func load() throws -> Fixtures {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "HighlightFixtures", withExtension: "json"))
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }
}

@Suite struct WebParityTests {
    @Test func formatAmountMatchesWebsite() throws {
        for c in try Fixtures.load().amounts {
            #expect(Amount.format(c.n) == c.text, "formatAmount(\(c.n))")
        }
    }

    @Test func cleanStepTextMatchesWebsite() throws {
        for recipe in try Fixtures.load().recipes {
            for step in recipe.steps {
                #expect(StepText.clean(step.text) == step.cleaned, "recipe \(recipe.id)")
            }
        }
    }

    @Test func highlightedStepsMatchWebsite() throws {
        let fixtures = try Fixtures.load()
        #expect(fixtures.recipes.count > 20)
        var checked = 0
        for recipe in fixtures.recipes {
            let base = Double(max(1, recipe.servings ?? 1))
            for step in recipe.steps {
                for (i, c) in step.cases.enumerated() {
                    // The first case is the initial render (raw text); the others follow a servings change.
                    let source = i == 0 ? step.text : StepText.clean(step.text)
                    let html = StepText.highlightHTML(source, ingredients: recipe.ingredients, ratio: Double(c.servings) / base)
                    #expect(html == c.html, "recipe \(recipe.id), servings \(c.servings)")
                    checked += 1
                }
            }
        }
        #expect(checked > 500)
    }

    @Test func stepMentionsMatchWebsite() throws {
        for recipe in try Fixtures.load().recipes {
            for step in recipe.steps {
                let mentions = recipe.ingredients.map { StepText.mentions($0, in: step.text) }
                #expect(mentions == step.mentions, "recipe \(recipe.id)")
            }
        }
    }
}

// MARK: - Step text

@Suite struct StepTextTests {
    private let flour = RecipeIngredient(id: 1, name: "קמח לבן", displayName: "קמח", amount: "500", unit: "גרם")
    private let salt = RecipeIngredient(id: 2, name: "מלח", amount: "0.5", unit: "כפית")

    @Test func injectsScaledAmountsAfterMentions() {
        let html = StepText.highlightHTML("מערבבים את הקמח והמלח.", ingredients: [flour, salt], ratio: 2)
        let text = StepText.runs(fromHTML: html).map(\.text).joined()
        #expect(text == "מערבבים את הקמח (1000 גרם) והמלח (1 כפית).")
    }

    @Test func runsCarryStyles() {
        let runs = StepText.runs(fromHTML: StepText.highlightHTML("מוסיפים מלח", ingredients: [salt], ratio: 1))
        #expect(runs == [
            .init(text: "מוסיפים ", style: .plain),
            .init(text: "מלח", style: .strong),
            .init(text: " (½ כפית)", style: .muted),
        ])
    }

    @Test func duplicateNamesUseOccurrenceOrder() {
        let first = RecipeIngredient(id: 1, name: "מים", amount: "100", unit: "מ״ל")
        let second = RecipeIngredient(id: 2, name: "מים", amount: "50", unit: "מ״ל")
        let html = StepText.highlightHTML("מים, ועוד מים, ושוב מים", ingredients: [first, second], ratio: 1)
        let text = StepText.runs(fromHTML: html).map(\.text).joined()
        #expect(text == "מים (100 מ״ל), ועוד מים (50 מ״ל), ושוב מים (50 מ״ל)")
    }

    @Test func stripsAmountsAlreadyInText() {
        #expect(StepText.stripExistingAmounts("קמח (500 גרם) ושמן  (2 כפות)") == "קמח ושמן")
    }

    @Test func noIngredientsLeavesTextUntouched() {
        #expect(StepText.highlightHTML("טקסט (5 גרם)", ingredients: [], ratio: 1) == "טקסט (5 גרם)")
    }

    @Test func parseFloatBehavesLikeJavaScript() {
        #expect(Amount.parseFloat("70") == 70)
        #expect(Amount.parseFloat("0.5") == 0.5)
        #expect(Amount.parseFloat("2 כפות") == 2)
        #expect(Amount.parseFloat("abc").isNaN)
    }
}

// MARK: - Images

@Suite struct ImageTests {
    @Test func parsesPositionFragment() {
        let url = "https://res.cloudinary.com/x/image/upload/v1/recipes/a.png#pos=49,45,1.09"
        #expect(ImagePosition(urlString: url) == ImagePosition(x: 49, y: 45, zoom: 1.09))
        #expect(ImagePosition(urlString: "https://example.com/a.png") == nil)
        #expect(ImageURL.base(url) == "https://res.cloudinary.com/x/image/upload/v1/recipes/a.png")
    }

    @Test func cloudinaryURLsAreResized() {
        let url = ImageURL.optimized("https://res.cloudinary.com/x/image/upload/v1/recipes/a.png#pos=50,50,1", width: 400)
        #expect(url?.absoluteString == "https://res.cloudinary.com/x/image/upload/f_jpg,q_auto,c_limit,w_400/v1/recipes/a.png")
        #expect(ImageURL.optimized("https://example.com/a.png")?.absoluteString == "https://example.com/a.png")
    }
}

// MARK: - Decoding

@Suite struct DecodingTests {
    @Test func recipeDetailDecodes() throws {
        let recipe: Recipe = try decode("""
        {"id":23,"title":"לחמניות","description":null,"difficulty":"easy","prep_time":152,"cook_time":20,"servings":18,
         "category":"אפייה","tags":["לחם"],"image_url":"https://x/y.png#pos=50,50,1","created_at":"2026-04-17T16:26:09.763Z",
         "is_hidden":false,"story_text":null,
         "ingredients":[{"id":2,"name":"סוכר","display_name":"סוכר לבן","is_pantry_staple":true,"amount":"70","unit":"גרם","note":""},
                        {"id":243,"name":"חמאה להברשה","display_name":null,"amount":null,"unit":null,"note":"להברשה"}],
         "steps":[{"id":1105,"recipe_id":23,"step_order":1,"title":null,"text":"מערבבים","image_url":null,"timer_seconds":null,
                   "prep_minutes":0,"cook_minutes":12,"show_timer":true,"show_prep_timer":true,"show_cook_timer":true}],
         "notes":[{"id":1,"recipe_id":23,"note_text":"18 דקות","created_at":"2026-05-16T17:24:46.768Z"}],
         "related":[{"id":99,"title":"טורטיות","image_url":null,"prep_time":40,"cook_time":25,"difficulty":"easy","category":"אפייה"}]}
        """)
        #expect(recipe.totalMinutes == 172)
        #expect(recipe.ingredients[0].label == "סוכר לבן")
        #expect(recipe.ingredients[0].amount == "70")
        #expect(recipe.ingredients[1].label == "חמאה להברשה")
        #expect(recipe.steps[0].displayTitle == "שלב 1")
        #expect(recipe.steps[0].hasCookTimer && !recipe.steps[0].hasPrepTimer && !recipe.steps[0].hasPlainTimer)
        #expect(recipe.notes[0].createdAt != nil)
        #expect(recipe.related[0].totalMinutes == 65)
        #expect(recipe.createdAt != nil)
    }

    @Test func nutritionDecodesNumericStrings() throws {
        let n: Nutrition = try decode("""
        {"recipe_id":23,"calories":271,"protein_g":"3.5","fat_g":"11.6","carbs_g":"38.7","sugar_g":"9","fiber_g":"0.9",
         "sodium_mg":38,"per_servings":18,"updated_at":"2026-05-06T19:31:21.589Z","total_weight_g":"72.8"}
        """)
        #expect(n.rows.map(\.value) == ["271", "3.5", "11.6", "38.7", "0.9", "9", "38"])
        #expect(n.hasPer100)
        #expect(n.per100(n.rows[0]) == "372")   // 271 / 72.8 * 100
        #expect(n.per100(n.rows[1]) == "4.8")
        let none = try JSONDecoder().decode(Nutrition?.self, from: Data("null".utf8))
        #expect(none == nil)
    }

    @Test func fridgeResultDecodes() throws {
        let recipes: [Recipe] = try decode("""
        [{"id":5,"title":"בצק","prep_time":9,"cook_time":null,"tags":[],"match_percent":20,
          "missing_ingredients":[{"id":71,"name":"מים קרים","display_name":"מים"}]}]
        """)
        #expect(recipes[0].matchPercent == 20)
        #expect(recipes[0].missingIngredients[0].label == "מים")
        #expect(recipes[0].totalMinutes == 9)
    }
}

// MARK: - Home filtering

@Suite struct RecipeFilterTests {
    private func recipes() throws -> [Recipe] {
        try decode("""
        [{"id":1,"title":"חלה","difficulty":"medium","prep_time":20,"cook_time":30,"category":"אפייה","tags":["שבת"],"created_at":"2026-01-01T00:00:00.000Z"},
         {"id":2,"title":"מרק בצל","difficulty":"easy","prep_time":10,"cook_time":15,"category":"מרקים","tags":[],"created_at":"2026-03-01T00:00:00.000Z"},
         {"id":3,"title":"בריסקט","difficulty":"hard","prep_time":30,"cook_time":240,"category":"עיקריות","tags":["פסח"],"created_at":"2026-02-01T00:00:00.000Z"},
         {"id":4,"title":"פיתות","difficulty":"easy","prep_time":40,"cook_time":10,"category":"אפייה","tags":[],"created_at":"2026-04-01T00:00:00.000Z"}]
        """)
    }

    private func ids(_ filter: RecipeFilter, favoritesOnly: Bool = false, favorites: [Int] = []) throws -> [Int] {
        filter.apply(to: try recipes(), favoritesOnly: favoritesOnly, favorites: favorites).map(\.id)
    }

    @Test func defaultIsNewestFirst() throws {
        #expect(try ids(RecipeFilter()) == [4, 2, 3, 1])
    }

    @Test func searchMatchesTitleTagsAndCategory() throws {
        #expect(try ids(RecipeFilter(search: "בצל")) == [2])
        #expect(try ids(RecipeFilter(search: "פסח")) == [3])
        #expect(try ids(RecipeFilter(search: "אפייה")) == [4, 1])
    }

    @Test func timeRanges() throws {
        #expect(try ids(RecipeFilter(timeRange: .short)) == [2])
        #expect(try ids(RecipeFilter(timeRange: .medium)) == [4, 1])
        #expect(try ids(RecipeFilter(timeRange: .long)) == [3])
    }

    @Test func sortsAreStable() throws {
        #expect(try ids(RecipeFilter(sort: .diffEasy)) == [2, 4, 1, 3])
        #expect(try ids(RecipeFilter(sort: .diffHard)) == [3, 1, 2, 4])
        #expect(try ids(RecipeFilter(sort: .timeAsc)) == [2, 1, 4, 3])
        #expect(try ids(RecipeFilter(sort: .dateAsc)) == [1, 3, 2, 4])
    }

    @Test func favoritesAndBadge() throws {
        #expect(try ids(RecipeFilter(), favoritesOnly: true, favorites: [3, 2]) == [2, 3])
        #expect(RecipeFilter().badgeCount == 0)
        #expect(RecipeFilter(category: "אפייה", difficulty: "easy", sort: .timeAsc).badgeCount == 3)
        #expect(RecipeFilter.categories(in: try recipes()) == ["אפייה", "מרקים", "עיקריות"])
    }
}

// MARK: - Fridge

@Suite struct FridgeLogicTests {
    private let catalog = [
        CatalogIngredient(id: 1, name: "מלח", isPantryStaple: true, recipeCount: 23),
        CatalogIngredient(id: 2, name: "חמאה רכה", displayName: "חמאה", recipeCount: 9),
        CatalogIngredient(id: 3, name: "חמאה קרה", displayName: "חמאה", recipeCount: 5),
        CatalogIngredient(id: 4, name: "חלב", recipeCount: 4),
        CatalogIngredient(id: 5, name: "גזר", recipeCount: 2),
    ]

    @Test func categorizes() {
        #expect(FridgeLogic.category(for: "גזר") == "ירקות")
        #expect(FridgeLogic.category(for: "חמאה רכה") == "גבינות ומוצרי חלב")
        #expect(FridgeLogic.category(for: "קמח לבן") == "דגנים וקמחים")
        #expect(FridgeLogic.category(for: "משהו אחר") == "אחר")
    }

    @Test func groupsIdsByDisplayName() {
        #expect(FridgeLogic.displayGroups(catalog)["חמאה"] == [2, 3])
    }

    @Test func suggestionsSkipPantryAndSelected() {
        #expect(FridgeLogic.suggestions(query: "", ingredients: catalog, selected: []).map(\.id) == [2, 4, 5])
        #expect(FridgeLogic.suggestions(query: "ח", ingredients: catalog, selected: []).map(\.id) == [2, 4])
        #expect(FridgeLogic.suggestions(query: "ח", ingredients: catalog, selected: ["חמאה"]).map(\.id) == [4])
        #expect(FridgeLogic.submitMatch(query: "חל", ingredients: catalog)?.id == 4)
    }

    @Test func categoryGroupsPutOtherLast() {
        let extra = catalog + [CatalogIngredient(id: 6, name: "משהו")]
        let groups = FridgeLogic.categoryGroups(extra)
        #expect(groups.last?.name == "אחר")
        #expect(!groups.flatMap(\.items).contains { $0.isPantryStaple })
        #expect(groups.first { $0.name == "גבינות ומוצרי חלב" }?.items.map(\.label) == ["חלב", "חמאה"])
    }
}
