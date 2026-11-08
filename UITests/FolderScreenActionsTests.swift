import XCTest

/// Notes page: three dots at the top right (Edit inside), new note button at the bottom right.
final class FolderScreenActionsTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    func testThreeDotsAndNewNoteButton() throws {
        continueAfterFailure = false
        let app = launchApp()

        let name = "Pg\(Int.random(in: 100...999))"
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(name)
        app.alerts.buttons["Create"].tap()
        app.staticTexts[name].tap()

        // Give the folder a note first, so the empty-state button is not on screen.
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("First note")
        sleep(1)
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()

        let more = app.buttons["More"]
        let fab = app.buttons["New Note"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 3), "three dots at the top")
        XCTAssertTrue(fab.exists, "new note button")
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(fab.frame.midX, screen.midX, "new note button is on the right")
        XCTAssertGreaterThan(fab.frame.midY, screen.midY, "and at the bottom")
        XCTAssertLessThan(more.frame.midY, screen.height * 0.2, "three dots are at the top")
        XCTAssertGreaterThan(more.frame.midX, screen.midX, "and on the right")

        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/100-folder-screen.png"))

        // The menu holds Edit, and Edit hides the new note button.
        more.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 2))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["New Note"].exists, "no new note button while editing")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["New Note"].firstMatch.waitForExistence(timeout: 2))
    }
}
