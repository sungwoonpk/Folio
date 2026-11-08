import XCTest

/// Writes notes, leaves them, opens them again and again. Each must show its text every time.
/// This guards the bug where an old note opened empty and typing would have overwritten it.
final class ReopenNotesTests: XCTestCase {
    func testNotesAlwaysShowTheirTextWhenReopened() throws {
        continueAfterFailure = false
        let app = launchApp()

        let folder = "Loop\(Int.random(in: 100...999))"
        app.buttons["New Folder"].firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText(folder)
        app.alerts.buttons["Create"].tap()
        app.staticTexts[folder].tap()

        let titles = ["Alpha text", "Beta text"]
        for title in titles {
            app.buttons["New Note"].firstMatch.tap()
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 3))
            editor.typeText(title)
            sleep(1)
            app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
        }

        for round in 1...4 {
            for title in titles {
                let row = app.staticTexts[title].firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 3), "round \(round): \(title) missing from the list")
                row.tap()
                let editor = app.textViews.firstMatch
                XCTAssertTrue(editor.waitForExistence(timeout: 5), "round \(round): no editor for \(title)")
                let shown = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value CONTAINS %@", title), object: editor
                )
                XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "round \(round): \(title) opened empty")
                XCTAssertFalse(app.staticTexts["No Note"].exists)
                app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
            }
        }
    }
}
