import XCTest

/// Checklist: header button, Return continues and ends the list, tapping the box checks it.
final class ChecklistTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    func testChecklistFlow() throws {
        continueAfterFailure = false
        let app = launchApp()

        let folder = "Todo\(Int.random(in: 100...999))"
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(folder)
        app.alerts.buttons["Create"].tap()
        app.staticTexts[folder].tap()
        app.buttons["New Note"].firstMatch.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Groceries\n")
        app.buttons["Checklist"].tap()
        editor.typeText("milk\n")
        XCTAssertEqual(editor.value as? String, "Groceries\n○ milk\n○ ", "Return continues the checklist")
        editor.typeText("eggs\n")
        editor.typeText("\n")   // Return on an empty item ends the list
        XCTAssertEqual(editor.value as? String, "Groceries\n○ milk\n○ eggs\n", "Return on an empty item ends it")
        editor.typeText("done")
        shot(app, "90-checklist-typed")

        // Tap the box in front of "milk": second line, a little right of the left edge.
        let origin = editor.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: 22, dy: 50)).tap()
        sleep(1)
        shot(app, "91-after-tap")
        let value = editor.value as? String ?? ""
        XCTAssertTrue(value.contains("◉ milk"), "tapping the box should check milk, got: \(value.debugDescription)")
        XCTAssertTrue(value.contains("○ eggs"), "eggs stays unchecked")

        // Backspace right after a marker removes the marker.
        app.buttons["Checklist"].tap()
        sleep(1)
        shot(app, "92-toggle-again")
    }
}
