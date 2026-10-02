import XCTest

/// End-to-end checks of the admin app against the live backend.
/// Needs the admin app installed on the device and `TEST_RUNNER_ADMIN_PW` set; skipped otherwise.
/// The only data it writes is a hidden recipe that it deletes again.
final class AdminUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.nirpoliti.recipes.admin")
    private let testTitle = "ZZ app test - delete me"

    private func password() throws -> String {
        guard let pw = ProcessInfo.processInfo.environment["ADMIN_PW"], !pw.isEmpty else {
            throw XCTSkip("ADMIN_PW not provided")
        }
        return pw
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

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 20) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    /// Brings the app to the login screen, signing out if a session was saved.
    private func launchSignedOut() {
        app.launchArguments = ["-skipLock"]
        app.launch()
        if !app.secureTextFields["password"].waitForExistence(timeout: 8) {
            if !app.buttons["פתח נעילה"].exists { app.tabBars.buttons["הגדרות"].tap() }
            scrollTo(app.buttons["התנתק"])
            app.buttons["התנתק"].tap()
        }
        XCTAssertTrue(app.secureTextFields["password"].waitForExistence(timeout: 8))
    }

    private func login(_ pw: String) {
        let field = app.secureTextFields["password"]
        field.tap()
        field.typeText(pw)
        app.buttons["כניסה"].tap()
    }

    func testLoginBrowseAndRecipeRoundTrip() throws {
        let pw = try password()
        launchSignedOut()
        shot("60-admin-login")

        // A wrong password is rejected.
        login("definitely-wrong")
        XCTAssertTrue(element("סיסמה שגויה").waitForExistence(timeout: 15))

        // The real one opens the recipe list.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.secureTextFields["password"].waitForExistence(timeout: 8))
        login(pw)
        XCTAssertTrue(element("מתכונים (").waitForExistence(timeout: 20), "recipe list should load")
        shot("61-admin-recipes")

        // Create a hidden recipe…
        app.buttons["+ חדש"].tap()
        XCTAssertTrue(element("מתכון חדש").waitForExistence(timeout: 5))
        app.buttons["הסתר"].tap()
        XCTAssertTrue(element("מוסתר מהבלוג").waitForExistence(timeout: 3))
        let title = app.textFields["recipe-title"]
        title.tap()
        title.typeText(testTitle)
        shot("62-admin-new-recipe")
        let submit = app.buttons["submit"]
        scrollTo(submit)
        submit.tap()
        XCTAssertTrue(element("המתכון נוצר בהצלחה").waitForExistence(timeout: 20), "create should succeed")
        XCTAssertTrue(element("עריכת מתכון").waitForExistence(timeout: 10), "form should switch to edit mode")

        // …edit it (a save goes through the update path)…
        scrollTo(app.buttons["+ הוסף"].firstMatch)
        app.buttons.matching(identifier: "+ הוסף").element(boundBy: 1).tap()   // add a step
        let stepText = app.textFields["הוראות השלב *"].firstMatch.exists
            ? app.textFields["הוראות השלב *"].firstMatch : app.textViews.firstMatch
        scrollTo(stepText)
        stepText.tap()
        stepText.typeText("Mix for 10-15 minutes")
        scrollTo(submit)
        shot("63-admin-edit-recipe")
        submit.tap()
        XCTAssertTrue(element("השינויים נשמרו").waitForExistence(timeout: 20), "update should succeed")

        // …and delete it from the list.
        app.buttons["חזרה"].tap()
        // The keyboard may autocorrect the typed title, so match loosely.
        let created = NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "מחק", "app test")
        let delete = app.buttons.matching(created).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 20), "the new recipe should be listed")
        scrollTo(delete)
        delete.tap()
        app.buttons["מחק"].firstMatch.tap()
        XCTAssertTrue(element("המתכון נמחק").waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons.matching(created).firstMatch.waitForExistence(timeout: 3), "the recipe should be gone")
    }

    func testEditorAndTools() throws {
        let pw = try password()
        app.launchArguments = ["-skipLock"]
        app.launch()
        if app.secureTextFields["password"].waitForExistence(timeout: 6) { login(pw) }
        XCTAssertTrue(element("מתכונים (").waitForExistence(timeout: 20))

        // Open an existing recipe without changing it.
        element("חלה מושלמת").tap()
        XCTAssertTrue(element("עריכת מתכון").waitForExistence(timeout: 20))
        shot("64-admin-editor-top")
        scrollTo(app.buttons["💾 שמור מרכיבים"])
        shot("65-admin-editor-ingredients")
        scrollTo(element("👁 תצוגה מקדימה"))
        element("👁 תצוגה מקדימה").tap()
        app.swipeUp(velocity: .slow)
        shot("66-admin-editor-preview")
        app.buttons["חזרה"].tap()

        app.tabBars.buttons["מצרכים"].tap()
        XCTAssertTrue(element("השינויים גלובליים").waitForExistence(timeout: 20))
        XCTAssertTrue(app.textFields.count > 1, "ingredient rows should load")
        sleep(2)
        shot("67-admin-ingredients")

        app.tabBars.buttons["מוצרי יסוד"].tap()
        XCTAssertTrue(app.buttons["+ הוסף מוצרי יסוד"].waitForExistence(timeout: 20))
        sleep(4)
        shot("68-admin-pantry")
        XCTAssertTrue(element("סוכר חום").waitForExistence(timeout: 20), "pantry staples should load")

        app.tabBars.buttons["הגדרות"].tap()
        XCTAssertTrue(app.buttons["💾 שמור הגדרות"].waitForExistence(timeout: 10))
        shot("69-admin-settings")
    }
}
