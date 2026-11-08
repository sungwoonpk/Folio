import XCTest

/// Opens the existing notes again and again. Each must show its text every time.
final class ReopenOldNotesTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    func testOldNotesAreNeverEmptyWhenOpened() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        for round in 1...3 {
            for (folder, noteTitle) in [("Test1", "Daddy"), ("D", "Asdasdasdsa")] {
                XCTAssertTrue(app.staticTexts[folder].waitForExistence(timeout: 5))
                app.staticTexts[folder].tap()
                let row = app.staticTexts[noteTitle].firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 3), "no note \(noteTitle) in \(folder)")
                row.tap()
                let editor = app.textViews.firstMatch
                sleep(2)
                shot(app, "79-after-tap-round\(round)-\(folder)")
                XCTAssertTrue(editor.waitForExistence(timeout: 3), "no editor in round \(round) \(folder)")
                // give the editor time to load, then it must have text or a table
                let hasText = NSPredicate(format: "value != ''")
                let loaded = expectation(for: hasText, evaluatedWith: editor)
                let hasTable = app.textFields.firstMatch.waitForExistence(timeout: 0.1)
                if !hasTable { wait(for: [loaded], timeout: 4) }
                shot(app, "80-round\(round)-\(folder)")
                XCTAssertFalse(app.staticTexts["No Note"].exists, "No Note shown in round \(round) \(folder)")
                app.buttons.matching(identifier: "chevron.left").firstMatch.tap()   // back to the folder
                app.buttons.matching(identifier: "chevron.left").firstMatch.tap()   // back to home
            }
        }
    }
}
