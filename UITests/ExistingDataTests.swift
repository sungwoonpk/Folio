import XCTest

/// Opens the notes that already exist (a copy of the real data) and edits them.
final class ExistingDataTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    private func assertNoteStillOpen(_ app: XCUIApplication, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        shot(app, step)
        XCTAssertFalse(app.staticTexts["No Note"].exists, "fell back to No Note after: \(step)", file: file, line: line)
    }

    func testEditExistingNoteWithBulletsAndTable() throws {
        let app = XCUIApplication()
        app.launch()
        shot(app, "10-home")

        app.staticTexts["Test1"].tap()
        shot(app, "11-test1")
        app.staticTexts["Daddy"].firstMatch.tap()
        sleep(1)
        assertNoteStillOpen(app, "12-opened-daddy")

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        sleep(1)
        assertNoteStillOpen(app, "13-tapped-editor")

        editor.typeText(" more")
        sleep(2)
        assertNoteStillOpen(app, "14-typed")

        let cell = app.textFields.firstMatch
        if cell.waitForExistence(timeout: 2) {
            cell.tap()
            cell.typeText("x")
            sleep(2)
            assertNoteStillOpen(app, "15-table-cell")
        }
    }

    func testEditNoteInSubfolder() throws {
        let app = XCUIApplication()
        app.launch()
        app.staticTexts["Test1"].tap()
        app.staticTexts["D"].firstMatch.tap()
        shot(app, "20-subfolder")
        app.staticTexts["Asdasdasdsa"].firstMatch.tap()
        sleep(1)
        assertNoteStillOpen(app, "21-opened")
        let cell = app.textFields.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 3))
        cell.tap()
        cell.typeText("hello")
        sleep(2)
        assertNoteStillOpen(app, "22-typed-in-cell")
    }
}
