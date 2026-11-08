import XCTest

/// Builds a small demo and saves the README screenshots.
/// Skipped unless a folder is given:
///   TEST_RUNNER_SCREENSHOT_DIR=docs/screenshots xcodebuild test -only-testing:NotesUITests/ScreenshotTests ...
final class ScreenshotTests: XCTestCase {
    private func save(_ app: XCUIApplication, _ name: String, to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func back(_ app: XCUIApplication) {
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
    }

    private func addFolder(_ app: XCUIApplication, _ name: String) {
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(name)
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3))
    }

    /// New note in the open folder: types the text, then goes back to the folder.
    private func addNote(_ app: XCUIApplication, _ text: String) {
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText(text)
        sleep(1)
        back(app)
    }

    func testReadmeScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_SCREENSHOT_DIR to save screenshots")
        }
        continueAfterFailure = false
        let app = launchApp()

        for name in ["Work", "Personal", "Recipes"] { addFolder(app, name) }

        // Recipes and Personal get one note each.
        app.staticTexts["Recipes"].tap()
        addNote(app, "Kimchi stew\nSimmer kimchi with pork, tofu and scallions for twenty minutes.")
        back(app)
        app.staticTexts["Personal"].tap()
        addNote(app, "Reading list\nThe Pragmatic Programmer, then Designing Data-Intensive Applications.")
        back(app)

        // Work gets a plan with bullets, a checklist, and meeting notes with a table.
        app.staticTexts["Work"].tap()

        app.buttons["New Note"].firstMatch.tap()
        var editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Weekly plan\n")
        app.buttons["Bullet List"].tap()
        editor.typeText("Finish the editor\nWrite the README\nShip a first release")
        sleep(1)
        back(app)

        app.buttons["New Note"].firstMatch.tap()
        editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Launch checklist\n")
        app.buttons["Checklist"].tap()
        editor.typeText("Write the README\nRun every test\nTag a release")
        // Check the first two items by tapping their circles.
        let origin = editor.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: 22, dy: 50)).tap()
        origin.withOffset(CGVector(dx: 22, dy: 76)).tap()
        sleep(1)
        back(app)

        app.buttons["New Note"].firstMatch.tap()
        editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Meeting notes\n")
        app.buttons["Table"].tap()
        let cells = ["Topic", "Owner", "Search", "Sam", "Editor", "Lee"]
        for (index, text) in cells.enumerated() {
            let cell = app.textFields.element(boundBy: index)
            XCTAssertTrue(cell.waitForExistence(timeout: 3))
            cell.tap()
            cell.typeText(text)
        }
        sleep(1)
        back(app)

        // 1. Folders, light.
        back(app)
        sleep(1)
        save(app, "01-folders", to: dir)

        // 2. A folder's notes, grouped by date.
        app.staticTexts["Work"].tap()
        sleep(1)
        save(app, "02-notes", to: dir)

        // 3. Checklist note, reopened so the keyboard is down.
        app.staticTexts["Launch checklist"].firstMatch.tap()
        sleep(2)
        save(app, "03-checklist", to: dir)
        back(app)

        // 4. Bullets and a table.
        app.staticTexts["Meeting notes"].firstMatch.tap()
        sleep(2)
        save(app, "04-table", to: dir)
        back(app)
        back(app)

        // 5. Dark mode: the icon cycles System, Light, Dark.
        app.buttons["Appearance"].tap()
        app.buttons["Appearance"].tap()
        sleep(1)
        save(app, "05-dark", to: dir)
    }
}
