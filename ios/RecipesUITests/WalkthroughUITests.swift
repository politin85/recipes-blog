import XCTest

/// End-to-end smoke tests against the live backend. Screenshots are attached to the test
/// report, and also written to `$TEST_RUNNER_SHOT_DIR` when that is set.
final class WalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "אישור", "אפשר", "לאפשר"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func text(_ label: String) -> XCUIElement {
        // Cards and rows are exposed as combined elements, so match on any element's label.
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 14) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    func testHomeFiltersAndDrawer() {
        app.launch()
        XCTAssertTrue(text("כל המתכונים").waitForExistence(timeout: 20))
        XCTAssertTrue(text("טורטיות קמח ביתיות").waitForExistence(timeout: 20), "recipes should load")
        shot("01-home-list")

        app.buttons["תצוגת כרטיסים"].tap()
        app.swipeUp(velocity: .slow)
        shot("02-home-grid")

        app.buttons["סינון ומיון"].tap()
        XCTAssertTrue(text("רמת קושי").waitForExistence(timeout: 5))
        shot("03-filter-sheet")
        app.buttons["הכל"].firstMatch.tap()
        XCTAssertTrue(app.buttons["מרקים"].waitForExistence(timeout: 5))
        app.buttons["מרקים"].tap()
        app.buttons["החל"].tap()
        XCTAssertTrue(text("מרק בצל צרפתי").waitForExistence(timeout: 5))
        XCTAssertFalse(text("טורטיות קמח ביתיות").exists, "category filter should hide baking recipes")
        shot("04-home-filtered")

        app.swipeDown()
        app.buttons["תצוגת רשימה"].tap()
        app.buttons["תפריט"].tap()
        XCTAssertTrue(text("הגדרות").waitForExistence(timeout: 5))
        shot("05-drawer")
        app.buttons["⭐ מועדפים"].tap()
        XCTAssertTrue(text("⭐ מועדפים").waitForExistence(timeout: 5))
        shot("06-favorites")
    }

    func testFridge() {
        app.launchArguments = ["-route", "fridge"]
        app.launch()
        XCTAssertTrue(text("המרכיבים שלי").waitForExistence(timeout: 20))
        let field = app.textFields.firstMatch
        field.tap()
        XCTAssertTrue(app.buttons["קמח לחם"].waitForExistence(timeout: 20), "common ingredients should be suggested")
        shot("10-fridge-suggestions")
        app.buttons["קמח לחם"].tap()
        XCTAssertFalse(app.buttons["שומשום"].exists, "picking should close the suggestions")
        field.typeText("x")   // the list only reopens on typing; no match for a Latin letter
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(app.buttons["שומשום"].waitForExistence(timeout: 5))
        app.buttons["שומשום"].tap()
        XCTAssertTrue(text("תוצאות לפי % התאמה").waitForExistence(timeout: 20), "results should load")
        shot("11-fridge-results")

        app.buttons["הצג הכל"].tap()
        XCTAssertTrue(text("כל המרכיבים").waitForExistence(timeout: 5))
        shot("12-fridge-all-ingredients")
    }

    func testRecipeScalingCookModeAndTimer() {
        // Recipe 99 has 11 steps and a 20-second timer; recipe ids are stable in the live database.
        app.launchArguments = ["-route", "recipe/99"]
        app.launch()
        XCTAssertTrue(text("מרכיבים").waitForExistence(timeout: 20), "recipe should load")
        app.tap() // lets the interruption monitor answer the notification prompt
        shot("20-recipe-top")

        scrollTo(app.buttons["2x"])
        app.buttons["2x"].tap()
        shot("21-recipe-doubled")

        let cook = app.buttons["👨‍🍳 מצב בישול"]
        scrollTo(cook)
        shot("22-recipe-steps")
        cook.tap()
        XCTAssertTrue(app.buttons["✕ צא ממצב בישול"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("שלב 1 מתוך 11").waitForExistence(timeout: 5))
        shot("23-cook-mode")
        app.buttons["הבא →"].firstMatch.tap()
        XCTAssertTrue(text("שלב 2 מתוך 11").waitForExistence(timeout: 5))
        shot("24-cook-mode-step2")
        app.buttons["✕ צא ממצב בישול"].tap()

        // Run the short timer on the last step to completion.
        let start = app.buttons.matching(identifier: "▶ הפעל טיימר")
        scrollTo(text("מתכונים נוספים"))
        XCTAssertGreaterThan(start.count, 0, "steps should show timers")
        let last = start.element(boundBy: start.count - 1)
        scrollTo(last, maxSwipes: 3)
        last.tap()
        XCTAssertTrue(app.buttons["⏸ עצור"].waitForExistence(timeout: 5))
        shot("25-timer-running")
        XCTAssertTrue(app.buttons["✓ הסתיים"].waitForExistence(timeout: 40), "timer should finish")
        shot("26-timer-done")

        scrollTo(text("על בסיס נתוני USDA FoodData Central"))
        shot("27-recipe-bottom")
    }

    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// Answers a system permission prompt (alarms / notifications) if one is showing.
    private func allowSystemPrompt() {
        sleep(2)
        shot("00-permission-prompt")
        for label in ["Allow", "אישור", "אפשר"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    func testTimerRunsAsSystemTimer() {
        app.launchArguments = ["-route", "recipe/99"]
        app.launch()
        XCTAssertTrue(text("מרכיבים").waitForExistence(timeout: 20), "recipe should load")
        allowSystemPrompt()

        // The first timer of recipe 99 is two minutes long.
        let start = app.buttons["▶ הפעל טיימר"].firstMatch
        scrollTo(start)
        start.tap()
        XCTAssertTrue(app.buttons["⏸ עצור"].waitForExistence(timeout: 5))
        shot("30-timer-in-app")

        // Leave the app: the timer keeps counting in the Dynamic Island…
        XCUIDevice.shared.press(.home)
        sleep(3)
        shot("31-timer-dynamic-island")

        // …and on the Lock Screen / notification list.
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.01))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)))
        sleep(2)
        shot("32-timer-lock-screen")
        XCUIDevice.shared.press(.home)

        app.activate()
        XCTAssertTrue(app.buttons["⏸ עצור"].waitForExistence(timeout: 5), "timer should still be running")
        app.buttons["⏸ עצור"].tap()
        XCTAssertTrue(app.buttons["▶ המשך"].waitForExistence(timeout: 5))
        shot("33-timer-paused")
        app.buttons["איפוס טיימר"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "reset should restore the start button")
    }

    func testNarrationUsesDeviceVoice() {
        app.launchArguments = ["-route", "recipe/99"]
        app.launch()
        XCTAssertTrue(text("מרכיבים").waitForExistence(timeout: 20), "recipe should load")
        allowSystemPrompt()

        let read = app.buttons["🔊 הקרא שלב"].firstMatch
        scrollTo(read)
        read.tap()
        XCTAssertTrue(app.buttons["⏸ השהה"].waitForExistence(timeout: 20), "narration should start")
        shot("40-narration-playing")
        app.buttons["⏸ השהה"].firstMatch.tap()
        XCTAssertTrue(app.buttons["▶ המשך"].waitForExistence(timeout: 5))
    }
}
