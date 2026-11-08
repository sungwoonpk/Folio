import XCTest

/// The icon next to Edit cycles System, Light, Dark.
final class AppearanceIconTests: XCTestCase {
    let shots = NSTemporaryDirectory() + "note-ui-shots"

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    func testIconSwitchesBetweenLightAndDarkOnly() throws {
        let app = launchApp()
        XCTAssertFalse(app.buttons["Settings"].exists, "the settings gear is gone")
        let icon = app.buttons["Appearance"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        let start = icon.value as? String
        XCTAssertTrue(["Light", "Dark"].contains(start ?? ""), "only two states exist, got \(start ?? "nil")")

        var seen: [String] = []
        for index in 0..<4 {
            icon.tap()
            sleep(1)
            seen.append(icon.value as? String ?? "?")
            shot(app, "6\(index)-after-tap-\(index + 1)")
        }
        // Every tap flips the mode: Light, Dark, Light, Dark (or the other way round).
        XCTAssertEqual(Set(seen), ["Light", "Dark"])
        XCTAssertEqual(seen, (0..<4).map { index in (start == "Light") == (index % 2 == 1) ? "Light" : "Dark" }.map { $0 })
        XCTAssertNotEqual(seen[0], start, "the first tap changes what you see")
    }
}
