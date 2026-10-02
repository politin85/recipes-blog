import CoreGraphics
import Foundation
import Testing
@testable import RecipesAdmin

private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

@Suite struct RecipeDraftTests {
    private func sampleRecipe() throws -> Recipe {
        try decode("""
        {"id":7,"title":"חלה","description":"רכה","difficulty":"medium","prep_time":20,"cook_time":30,"servings":3,
         "category":"אפייה","tags":["שבת","שמרים"],"image_url":"https://x/y.png#pos=50,40,1.2","is_hidden":true,"story_text":null,
         "ingredients":[{"id":1,"name":"קמח לבן","display_name":"קמח","amount":"500","unit":"גרם","note":""},
                        {"id":2,"name":"מלח","display_name":null,"amount":null,"unit":null,"note":"קורט"}],
         "steps":[{"id":10,"step_order":1,"title":"לישה","text":"לשים את הקמח","image_url":null,"timer_seconds":630,
                   "prep_minutes":15,"cook_minutes":0,"show_timer":true,"show_prep_timer":false,"show_cook_timer":true}]}
        """)
    }

    @Test func draftMirrorsRecipe() throws {
        let draft = RecipeDraft(try sampleRecipe())
        #expect(draft.id == 7)
        #expect(draft.tags == "שבת, שמרים")
        #expect(draft.isHidden)
        #expect(draft.ingredients[0].name == "קמח")
        #expect(draft.ingredients[0].originalLabel == "שם מקורי: קמח לבן")
        #expect(draft.ingredients[1].originalLabel == nil)
        #expect(draft.steps[0].timerMinutes == "11")   // Math.round(630 / 60)
        #expect(draft.steps[0].showPrepTimer == false)
    }

    @Test func payloadMatchesWebForm() throws {
        var draft = RecipeDraft(try sampleRecipe())
        draft.ingredients[1].name = "מלח גס"                   // renamed → the typed name is sent
        draft.ingredients.append(IngredientDraft())              // empty rows are dropped
        draft.steps.append(StepDraft())
        let payload = draft.payload

        #expect(payload["title"] as? String == "חלה")
        #expect(payload["prep_time"] as? Int == 20)
        #expect(payload["is_hidden"] as? Bool == true)
        #expect(payload["story_text"] is NSNull)
        #expect(payload["tags"] as? [String] == ["שבת", "שמרים"])

        let ingredients = try #require(payload["ingredients"] as? [[String: Any]])
        #expect(ingredients.count == 2)
        #expect(ingredients[0]["name"] as? String == "קמח לבן")   // untouched → original name
        #expect(ingredients[0]["amount"] as? Double == 500)
        #expect(ingredients[0]["note"] is NSNull)
        #expect(ingredients[1]["name"] as? String == "מלח גס")
        #expect(ingredients[1]["amount"] is NSNull)
        #expect(ingredients[1]["note"] as? String == "קורט")

        let steps = try #require(payload["steps"] as? [[String: Any]])
        #expect(steps.count == 1)
        #expect(steps[0]["timer_seconds"] as? Int == 660)
        #expect(steps[0]["prep_minutes"] as? Int == 15)
        #expect(steps[0]["cook_minutes"] as? Int == 0)
        #expect(steps[0]["show_prep_timer"] as? Bool == false)
        #expect(steps[0]["image_url"] is NSNull)

        #expect(JSONSerialization.isValidJSONObject(payload))
    }

    @Test func emptyNumbersBecomeNull() {
        var draft = RecipeDraft()
        draft.title = "  בדיקה "
        draft.servings = "0"
        let payload = draft.payload
        #expect(payload["title"] as? String == "בדיקה")
        #expect(payload["servings"] is NSNull)
        #expect(payload["prep_time"] is NSNull)
        #expect(payload["difficulty"] as? String == "easy")
    }

    @Test func recalcTimesSumsSteps() {
        var draft = RecipeDraft()
        var a = StepDraft(); a.prepMinutes = "10"; a.cookMinutes = "25"
        var b = StepDraft(); b.prepMinutes = "5"
        draft.steps = [a, b]
        draft.recalcTimes()
        #expect(draft.prepTime == "15")
        #expect(draft.cookTime == "25")
    }

    @Test func flagsIngredientsNoStepMentions() throws {
        let draft = RecipeDraft(try sampleRecipe())
        #expect(!draft.isUnmentioned(draft.ingredients[0]))   // "הקמח" matches with the Hebrew prefix
        #expect(draft.isUnmentioned(draft.ingredients[1]))
    }
}

@Suite struct AdminTimerTests {
    @Test func detectsMinutes() {
        #expect(AdminTimer.minutes(in: "מחכים חצי שעה") == 30)
        #expect(AdminTimer.minutes(in: "רבע שעה בתנור") == 15)
        #expect(AdminTimer.minutes(in: "אופים 10-15 דקות") == 13)
        #expect(AdminTimer.minutes(in: "מתפיחים 1–2 שעות") == 120)
        #expect(AdminTimer.minutes(in: "לשים כ-8 דקות") == 8)
        #expect(AdminTimer.minutes(in: "מקררים 2 שעות") == 120)
        #expect(AdminTimer.minutes(in: "מערבבים היטב") == nil)
    }
}

@Suite struct CropStateTests {
    private let image = CGSize(width: 2000, height: 1000)
    private let viewport = CGSize(width: 320, height: 180)

    @Test func centeredByDefault() {
        let crop = CropState()
        let position = crop.position(image: image, viewport: viewport)
        #expect(position == ImagePosition(x: 50, y: 50, zoom: 1))
        #expect(CropState.url(base: "https://x/a.png#pos=1,2,3", position: position) == "https://x/a.png#pos=50,50,1")
    }

    @Test func roundTripsAStoredPosition() {
        let stored = ImagePosition(x: 40, y: 50, zoom: 1.5)
        let crop = CropState(position: stored, image: image, viewport: viewport)
        #expect(crop.position(image: image, viewport: viewport) == stored)
        #expect(CropState.url(base: "https://x/a.png", position: stored) == "https://x/a.png#pos=40,50,1.5")
    }

    @Test func clampKeepsTheViewportCovered() {
        var crop = CropState()
        crop.offset = CGSize(width: 5000, height: 5000)
        crop.clamp(image: image, viewport: viewport)
        // Image is 360×180 at zoom 1: it can move 20pt sideways and not at all vertically.
        #expect(crop.offset == CGSize(width: 20, height: 0))
        let origin = crop.origin(image: image, viewport: viewport)
        #expect(origin.x == 0 && origin.y == 0)
    }
}

@Suite struct AdminListTests {
    @Test func groupsByDisplayName() {
        let groups = IngredientGroup.group([(3, "מלח"), (1, "חמאה"), (2, "חמאה"), (3, "מלח")])
        #expect(groups.map(\.displayName) == ["חמאה", "מלח"])
        #expect(groups[0].ids == [1, 2])
        #expect(groups[1].ids == [3])
    }

    @Test func aliasRowsDecodeSortAndFilter() throws {
        let rows: [AliasRow] = try decode("""
        [{"original_name":"קמח לבן","display_name":"קמח","note":"","original_note":"","usage_count":"12"},
         {"original_name":"אבקת אפייה","display_name":null,"note":"שקית","usage_count":3}]
        """)
        #expect(rows[0].usageCount == 12)
        #expect(rows[1].displayName == "אבקת אפייה")
        #expect(AliasRow.sorted(rows, by: .usageCount, ascending: true).map(\.usageCount) == [3, 12])
        #expect(AliasRow.sorted(rows, by: .originalName, ascending: true).first?.originalName == "אבקת אפייה")
        #expect(rows[1].matches("שקית") && !rows[0].matches("שקית") && rows[0].matches(" "))
    }

    @Test func multipartBodyIsWellFormed() {
        let body = AdminAPI.multipartBody(boundary: "B", fields: [("upload_preset", "Recipes"), ("folder", "recipes")],
                                          fileName: "photo.jpg", fileData: Data([1, 2, 3]), mimeType: "image/jpeg")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"upload_preset\"\r\n\r\nRecipes\r\n"))
        #expect(text.contains("name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--B--\r\n"))
    }

    @Test func jsNumberParsing() {
        #expect(JSParse.int("12") == 12)
        #expect(JSParse.int("12.7") == 12)
        #expect(JSParse.int("") == nil)
        #expect(JSParse.int("0") == nil)
        #expect(JSParse.float("0.5") == 0.5)
        #expect(JSParse.float("abc") == nil)
    }
}
