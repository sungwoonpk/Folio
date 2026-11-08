import XCTest

/// Places where a normal flow could get stuck or look wrong.
final class FlowGapTests: XCTestCase {
    private func back(_ app: XCUIApplication) {
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
    }

    private func addFolder(_ app: XCUIApplication, _ name: String) {
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(name)
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3))
    }

    /// Delete the only folder, so its note sits in Recently Deleted and no folder is left to restore it into.
    func testRestoringWhenNoFolderExistsIsNotADeadEnd() {
        let app = launchApp()
        addFolder(app, "Only")
        app.staticTexts["Only"].tap()
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Stranded note")
        sleep(1)
        back(app)
        back(app)

        app.buttons["Edit"].tap()
        app.staticTexts["Only"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Folders"].waitForExistence(timeout: 3))

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Recently Deleted'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Stranded note"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        app.staticTexts["Stranded note"].tap()
        app.buttons["Restore"].tap()

        // The picker has no folders. It must offer a way to make one, otherwise the note can never come back.
        let newFolder = app.buttons["New Folder"].firstMatch
        XCTAssertTrue(newFolder.waitForExistence(timeout: 3), "no way to create a folder while restoring")
        newFolder.tap()
        app.alerts.textFields.firstMatch.typeText("Rescued")
        app.alerts.buttons["Create"].tap()
        XCTAssertFalse(app.staticTexts["Stranded note"].waitForExistence(timeout: 3), "the note should be restored into the new folder")
        back(app)
        app.staticTexts["Rescued"].tap()
        XCTAssertTrue(app.staticTexts["Stranded note"].waitForExistence(timeout: 3))
    }

    /// Edit works on the folder list. While a search is showing notes, Edit must not leave a half-working screen.
    func testEditAndSearchDoNotFightEachOther() {
        let app = launchApp()
        addFolder(app, "Alpha")
        let field = app.textFields["Search"]
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the search field did not take focus")
        field.typeText("Alp")
        XCTAssertTrue(app.staticTexts["Alpha"].waitForExistence(timeout: 2))
        app.buttons["Edit"].tap()

        // Either the search is cleared and the folder list shows checks, or Edit is not offered. Nothing in between.
        let searching = (field.value as? String).map { $0 != "Search" && !$0.isEmpty } ?? false
        XCTAssertFalse(searching, "Edit is on while a search is still filtering the list")
        XCTAssertTrue(app.buttons["Done"].exists)
        app.staticTexts["Alpha"].tap()
        XCTAssertTrue(app.buttons["Delete"].isEnabled, "the folder can be selected")
    }
}
