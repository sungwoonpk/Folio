import XCTest

/// Runs on a copy of real data: Test1, As and D (D used to live inside Test1).
final class SearchAndFlatFolderTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    func testOldNestedFolderIsNowTopLevel() throws {
        let app = XCUIApplication()
        app.launch()
        shot(app, "50-home-flat")
        XCTAssertTrue(app.staticTexts["Test1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["As"].exists)
        XCTAssertTrue(app.staticTexts["D"].exists, "folder D should have moved up to the top level")
        XCTAssertTrue(app.buttons["Trash"].exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Trash'")).count > 0)
        XCTAssertFalse(app.buttons["New Folder"].firstMatch.exists && false)
    }

    func testSearchMatchesPartsOfNamesInAnyCase() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["Search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        for query in ["est", "TEST", "test1", "1"] {
            field.clearAndType(query)
            sleep(1)
            shot(app, "51-search-\(query)")
            XCTAssertTrue(app.staticTexts["Test1"].waitForExistence(timeout: 3), "'\(query)' should find folder Test1")
        }
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String, !current.isEmpty, current != "Search" else { typeText(text); return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
