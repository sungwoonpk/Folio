import XCTest

/// "Test3" must be found by "est", "3", "test" and "TEST", not only by the whole name.
final class SearchTests: XCTestCase {
    func testFolderNamesMatchAnyPartInAnyCase() throws {
        continueAfterFailure = false
        let app = launchApp()

        let suffix = Int.random(in: 100...999)
        let target = "Zebra\(suffix)", other = "Qwerty\(suffix)"
        for name in [target, other] {
            app.buttons["New Folder"].firstMatch.tap()
            app.alerts.textFields.firstMatch.typeText(name)
            app.alerts.buttons["Create"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3))
        }

        let field = app.textFields["Search"]
        field.tap()
        for query in ["ebra", "ZEBRA", "\(suffix)", target.lowercased()] {
            field.typeText(query)
            XCTAssertTrue(app.staticTexts[target].waitForExistence(timeout: 3), "'\(query)' should find \(target)")
            // The digits are in both names, every other query is only in the target.
            if query != "\(suffix)" { XCTAssertFalse(app.staticTexts[other].exists, "'\(query)' should not find \(other)") }
            app.buttons["Clear"].tap()
        }
    }
}
