import XCTest

/// Drives the real app: folder, note, bullets, table. Fails if the editor falls back to "No Note".
final class EditorFlowTests: XCTestCase {
    let shots = "/private/tmp/claude-501/-Users-jamespark-Documents-Projects/9e34b958-314b-4232-878e-8574099fa729/scratchpad/shots"

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = app.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    private func assertNoteStillOpen(_ app: XCUIApplication, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        shot(app, step)
        XCTAssertFalse(app.staticTexts["No Note"].exists, "fell back to No Note after: \(step)", file: file, line: line)
    }

    func testBulletsAndTable() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText("Work")
        app.alerts.buttons["Create"].tap()
        app.staticTexts["Work"].tap()
        shot(app, "01-folder")

        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Shopping list")
        assertNoteStillOpen(app, "02-title")

        editor.typeText("\n")
        app.buttons["Bullet List"].tap()
        assertNoteStillOpen(app, "03-bullet-on")

        editor.typeText("milk\n")
        editor.typeText("eggs")
        assertNoteStillOpen(app, "04-bullets-typed")

        app.buttons["Table"].tap()
        assertNoteStillOpen(app, "05-table-inserted")

        // wait past the autosave debounce, then check again
        sleep(2)
        assertNoteStillOpen(app, "06-after-save")

        let cell = app.textFields.firstMatch
        if cell.waitForExistence(timeout: 3) {
            cell.tap()
            cell.typeText("name")
            assertNoteStillOpen(app, "07-table-cell")
        }
        sleep(2)
        assertNoteStillOpen(app, "08-final")
    }
}
