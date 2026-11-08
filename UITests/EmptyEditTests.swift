import XCTest

/// Fresh install, nothing created: Edit must still visibly do something.
final class EmptyEditTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    func testEditOnEmptyHomeShowsMessage() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["No Folders"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.staticTexts["Nothing to Edit"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Done"].exists)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/30-empty-edit.png"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["No Folders"].waitForExistence(timeout: 2))
    }
}
