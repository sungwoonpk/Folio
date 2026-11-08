import XCTest

final class MoveIconTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    func testMoveIconInEditMode() throws {
        let app = XCUIApplication()
        app.launch()
        app.staticTexts["Test1"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Move"].waitForExistence(timeout: 3))
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/70-move-icon.png"))
    }
}
