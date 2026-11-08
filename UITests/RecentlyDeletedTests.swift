import XCTest

/// Delete a folder: the folder is gone, its notes are in Recently Deleted, and restoring asks for a folder.
final class RecentlyDeletedTests: XCTestCase {
    private func back(_ app: XCUIApplication) {
        app.buttons.matching(identifier: "chevron.left").firstMatch.tap()
    }

    func testDeletedFolderLeavesItsNotesAndRestoreAsksForAFolder() throws {
        continueAfterFailure = false
        let app = launchApp()

        let n = Int.random(in: 100...999)
        let gone = "Gone\(n)", keep = "Keep\(n)", noteText = "Lost note \(n)"
        for name in [gone, keep] {
            app.buttons["New Folder"].firstMatch.tap()
            app.alerts.textFields.firstMatch.typeText(name)
            app.alerts.buttons["Create"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3))
        }

        // A note inside the folder that will be deleted.
        app.staticTexts[gone].tap()
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText(noteText)
        sleep(1)
        back(app)   // editor to folder
        back(app)   // folder to home

        // The button is called Recently Deleted and shows no number.
        let recently = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Recently Deleted'")).firstMatch
        XCTAssertTrue(recently.exists)
        XCTAssertFalse(recently.label.contains(where: \.isNumber), "no count next to Recently Deleted")

        // Delete the folder through Edit.
        app.buttons["Edit"].tap()
        app.staticTexts[gone].tap()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts[gone].waitForExistence(timeout: 2), "the folder itself is gone")
        XCTAssertTrue(app.staticTexts[keep].exists)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }

        // Its note is in Recently Deleted.
        recently.tap()
        XCTAssertTrue(app.staticTexts["Recently Deleted"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[noteText].waitForExistence(timeout: 3), "the note survives in Recently Deleted")
        XCTAssertFalse(app.staticTexts[gone].exists, "no folder is kept there")

        // Restore it: a folder picker appears, pick Keep.
        app.buttons["Edit"].tap()
        app.staticTexts[noteText].tap()
        app.buttons["Restore"].tap()
        let pickKeep = app.buttons[keep].firstMatch
        XCTAssertTrue(pickKeep.waitForExistence(timeout: 3), "restore must ask which folder")
        XCTAssertFalse(app.buttons[gone].exists, "the deleted folder is not offered")
        pickKeep.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts[noteText].exists, "restored note left Recently Deleted")

        // And it is now inside Keep.
        back(app)
        app.staticTexts[keep].tap()
        XCTAssertTrue(app.staticTexts[noteText].waitForExistence(timeout: 3), "the note is in the folder that was picked")
    }
}
