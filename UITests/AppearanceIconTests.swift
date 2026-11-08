import XCTest

/// The icon next to Edit cycles System, Light, Dark.
final class AppearanceIconTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    func testIconSwitchesMode() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertFalse(app.buttons["Settings"].exists, "the settings gear is gone")
        let icon = app.buttons["Appearance"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.tap()                      // System -> Light
        shot(app, "60-light")
        icon.tap()                      // Light -> Dark
        sleep(1)
        shot(app, "61-dark")
        icon.tap()                      // Dark -> System
        sleep(1)
        shot(app, "62-system")
    }
}
