import XCTest

/// Odd things a person does with the real app. Each test starts from an empty app.
final class EdgeCaseUITests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    override func setUp() { continueAfterFailure = true }

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    private func back(_ app: XCUIApplication) {
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
    }

    @discardableResult
    private func addFolder(_ app: XCUIApplication, _ name: String) -> Bool {
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(name)
        app.alerts.buttons["Create"].tap()
        return app.staticTexts[name].waitForExistence(timeout: 3)
    }

    private func newNote(_ app: XCUIApplication, text: String) {
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        if !text.isEmpty { editor.typeText(text) }
        sleep(1)
    }

    // MARK: Folders

    func testBlankAndWhitespaceFolderNamesCreateNothing() {
        let app = launchApp()
        for name in ["", "   "] {
            app.buttons["New Folder"].firstMatch.tap()
            if !name.isEmpty { app.alerts.textFields.firstMatch.typeText(name) }
            app.alerts.buttons["Create"].tap()
        }
        XCTAssertTrue(app.staticTexts["No Folders"].waitForExistence(timeout: 2), "a blank name must not create a folder")
    }

    func testVeryLongFolderNameStillWorks() {
        let app = launchApp()
        let long = "LongName" + String(repeating: "x", count: 150)
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(long)
        app.alerts.buttons["Create"].tap()
        sleep(1)
        shot(app, "110-long-folder-name")
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'LongName'")).firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertLessThanOrEqual(row.label.count, 120, "the name is cut at 120 characters")
        row.tap()
        XCTAssertTrue(app.buttons["New Note"].firstMatch.waitForExistence(timeout: 3), "the folder opens")
        shot(app, "111-long-folder-screen")
    }

    func testTwoFoldersWithTheSameNameBothShow() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Twin"))
        XCTAssertTrue(addFolder(app, "Twin"))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Twin").count, 2)
    }

    // MARK: Notes

    func testOpeningANoteAndLeavingItEmptyLeavesNothingBehind() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Ghosts"))
        app.staticTexts["Ghosts"].tap()
        newNote(app, text: "")
        back(app)
        sleep(1)
        shot(app, "112-after-empty-note")
        XCTAssertTrue(app.staticTexts["No Notes"].waitForExistence(timeout: 3), "no ghost note after an empty visit")
        back(app)
        XCTAssertTrue(app.staticTexts["Ghosts"].exists)
    }

    func testWhitespaceOnlyNoteIsRemoved() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Blank"))
        app.staticTexts["Blank"].tap()
        newNote(app, text: "   \n  \n ")
        back(app)
        XCTAssertTrue(app.staticTexts["No Notes"].waitForExistence(timeout: 3), "a note with only spaces is discarded")
    }

    func testLongNoteSavesAndReopensComplete() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Long"))
        app.staticTexts["Long"].tap()
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Big note\n")
        let paragraph = "The quick brown fox jumps over the lazy dog. "
        for _ in 0..<12 { editor.typeText(String(repeating: paragraph, count: 4) + "\n") }
        sleep(1)
        let typed = editor.value as? String ?? ""
        back(app)
        app.staticTexts["Big note"].firstMatch.tap()
        let reopened = app.textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual((reopened.value as? String)?.count, typed.count, "the whole note comes back")
        XCTAssertGreaterThan(typed.count, 2_000)
    }

    // MARK: Edit mode

    func testEditModeWithNothingSelectedAndThenDeletingEverything() {
        let app = launchApp()
        for name in ["One", "Two", "Three"] { XCTAssertTrue(addFolder(app, name)) }
        app.buttons["Edit"].tap()
        XCTAssertFalse(app.buttons["Delete"].isEnabled, "nothing selected, nothing to delete")
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.buttons["Delete"].isEnabled)
        app.buttons["Deselect All"].tap()
        XCTAssertFalse(app.buttons["Delete"].isEnabled)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Edit"].exists)

        app.buttons["Edit"].tap()
        app.buttons["Select All"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Folders"].waitForExistence(timeout: 3), "everything deleted, empty state shows")
        shot(app, "113-all-folders-deleted")
    }

    // MARK: Lists

    func testBulletAndChecklistEdgeCases() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Lists"))
        app.staticTexts["Lists"].tap()
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))

        editor.typeText("Title")
        app.buttons["Bullet List"].tap()
        XCTAssertEqual(editor.value as? String, "Title", "the title line never becomes a list")

        editor.typeText("\n")
        app.buttons["Bullet List"].tap()
        editor.typeText("a")
        XCTAssertEqual(editor.value as? String, "Title\n• a")
        app.buttons["Checklist"].tap()
        XCTAssertEqual(editor.value as? String, "Title\n○ a", "pressing the other list button swaps the marker")
        app.buttons["Bullet List"].tap()
        XCTAssertEqual(editor.value as? String, "Title\n• a")
        app.buttons["Bullet List"].tap()
        XCTAssertEqual(editor.value as? String, "Title\na", "pressing it again turns the list off")

        app.buttons["Bullet List"].tap()
        editor.typeText("\n")
        XCTAssertEqual(editor.value as? String, "Title\n• a\n• ")
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(editor.value as? String, "Title\n• a\n", "backspace after the marker removes the marker")
        editor.typeText("plain")
        XCTAssertEqual(editor.value as? String, "Title\n• a\nplain")
    }

    func testTableEdgeCases() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Tables"))
        app.staticTexts["Tables"].tap()
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Sheet\nbefore")
        app.buttons["Table"].tap()

        // Grow it wide and tall.
        let addColumn = app.buttons["Column"].firstMatch
        XCTAssertTrue(addColumn.waitForExistence(timeout: 3))
        for _ in 0..<8 { addColumn.tap() }
        for _ in 0..<5 { app.buttons["Row"].firstMatch.tap() }
        shot(app, "114-wide-table")
        XCTAssertTrue(app.buttons["Row"].exists && app.buttons["Column"].exists)

        // Text still works after the table.
        app.textViews.element(boundBy: 1).tap()
        app.textViews.element(boundBy: 1).typeText("after the table")
        sleep(1)

        // Second table straight away.
        app.buttons["Table"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Row").count, 2, "two tables")
        shot(app, "115-two-tables")

        // Leave and reopen: both tables and the text survive.
        back(app)
        app.staticTexts["Sheet"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Row"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Row").count, 2, "both tables came back")
        shot(app, "116-tables-reopened")
    }

    // MARK: Search

    func testSearchOpensANoteAndComesBack() {
        let app = launchApp()
        XCTAssertTrue(addFolder(app, "Stash"))
        app.staticTexts["Stash"].tap()
        newNote(app, text: "Findable zebra note")
        back(app)
        back(app)

        let field = app.textFields["Search"]
        field.tap()
        field.typeText("ZEBRA")
        let result = app.staticTexts["Findable zebra note"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3), "search finds the note by text, any case")
        result.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "Findable zebra note")
        back(app)
        shot(app, "117-back-from-search")
        XCTAssertTrue(app.textFields["Search"].exists, "back to the main screen")
    }

    // MARK: Data survives a relaunch

    func testEverythingSurvivesClosingAndReopeningTheApp() {
        let path = "/tmp/note-ui-persist-\(UUID().uuidString).sqlite"
        let first = launchApp(databasePath: path)
        XCTAssertTrue(addFolder(first, "Persist"))
        first.staticTexts["Persist"].tap()
        newNote(first, text: "Remember me\nsecond line")
        back(first)
        back(first)
        first.terminate()

        let second = launchApp(databasePath: path)
        XCTAssertTrue(second.staticTexts["Persist"].waitForExistence(timeout: 5), "the folder is still there")
        second.staticTexts["Persist"].tap()
        XCTAssertTrue(second.staticTexts["Remember me"].waitForExistence(timeout: 3), "and the note")
        second.staticTexts["Remember me"].firstMatch.tap()
        XCTAssertEqual(second.textViews.firstMatch.value as? String, "Remember me\nsecond line")
        try? FileManager.default.removeItem(atPath: path)
    }
}
