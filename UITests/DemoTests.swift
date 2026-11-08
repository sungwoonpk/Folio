import XCTest

/// Uses the app the way a person would, slowly enough to follow on video. For the README demo.
/// Skipped unless asked for:
///   TEST_RUNNER_DEMO=1 xcodebuild test -only-testing:NotesUITests/DemoTests ...
final class DemoTests: XCTestCase {
    private func pause(_ seconds: TimeInterval = 0.9) { Thread.sleep(forTimeInterval: seconds) }

    private func back(_ app: XCUIApplication) {
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
        pause(0.6)
    }

    private func addFolder(_ app: XCUIApplication, _ name: String) {
        app.buttons["New Folder"].firstMatch.tap()
        pause(0.5)
        app.alerts.textFields.firstMatch.typeText(name)
        pause(0.5)
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3))
        pause()
    }

    func testDemo() throws {
        guard ProcessInfo.processInfo.environment["DEMO"] != nil else { throw XCTSkip("set TEST_RUNNER_DEMO=1 to run the demo") }
        continueAfterFailure = false
        let app = launchApp()
        pause(1.5)

        // Folders
        addFolder(app, "Work")
        addFolder(app, "Home")

        // A note with bullets
        app.staticTexts["Work"].tap()
        pause()
        app.buttons["New Note"].firstMatch.tap()
        var editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Launch plan\n")
        app.buttons["Bullet List"].tap()
        editor.typeText("Finish the editor\nWrite the README\nShip it")
        pause()
        back(app)

        // A checklist, with the first two items checked
        app.buttons["New Note"].firstMatch.tap()
        editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Launch checklist\n")
        app.buttons["Checklist"].tap()
        editor.typeText("Run every test\nTag a release\nCelebrate")
        pause(0.8)
        let origin = editor.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: 22, dy: 50)).tap()
        pause(0.7)
        origin.withOffset(CGVector(dx: 22, dy: 76)).tap()
        pause(1.2)
        back(app)

        // A table
        app.buttons["New Note"].firstMatch.tap()
        editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Budget\n")
        app.buttons["Table"].tap()
        pause(0.8)
        for (index, text) in ["Item", "Cost", "Phone", "400"].enumerated() {
            let cell = app.textFields.element(boundBy: index)
            XCTAssertTrue(cell.waitForExistence(timeout: 3))
            cell.tap()
            cell.typeText(text)
        }
        pause(1.2)
        back(app)
        pause()
        back(app)
        pause()

        // Search finds a note by part of a word
        let search = app.textFields["Search"]
        search.tap()
        search.typeText("check")
        pause(1.5)
        app.buttons["Clear"].tap()
        pause(0.8)

        // Dark mode and back
        app.buttons["Appearance"].tap()
        pause(4.5)
        app.buttons["Appearance"].tap()
        pause(1.0)

        // Delete a note, then bring it back into a folder
        app.staticTexts["Work"].tap()
        pause()
        app.staticTexts["Launch plan"].firstMatch.swipeLeft()
        pause(0.6)
        app.buttons["Delete"].tap()
        pause(1.0)
        back(app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Recently Deleted'")).firstMatch.tap()
        pause(1.0)
        app.buttons["Edit"].tap()
        pause(0.6)
        app.staticTexts["Launch plan"].firstMatch.tap()
        pause(0.6)
        app.buttons["Restore"].tap()
        pause(1.2)
        app.buttons["Home"].firstMatch.tap()
        pause(1.2)
        back(app)
        pause(1.5)
    }
}
