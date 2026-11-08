import XCTest

/// Every UI test starts from an empty app, so tests cannot depend on each other or on leftover data.
func launchApp(databasePath: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    if let databasePath { app.launchArguments += ["-ui-testing-db", databasePath] }
    app.launch()
    return app
}
