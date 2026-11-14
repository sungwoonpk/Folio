# Testing

Two kinds of tests: unit tests for everything that is not UI, and UI tests that drive the real app.

```bash
# Logic: storage, search, trash, documents. No simulator needed.
# GitHub Actions runs this and a simulator build on every push and pull request
cd Packages/NoteCore && swift test

# The real app, driven through its screens
xcodebuild -project Folio.xcodeproj -scheme Folio \
  -destination 'platform=iOS Simulator,name=<an installed simulator>' test
```

- **Unit tests:** storage, search, odd queries, huge notes, 25 saves at once, midnight boundaries, migrations, Recently Deleted expiry.
- **UI tests:** every main flow plus awkward ones: blank and very long names, empty notes, deleting every folder, restoring with no folder left, closing and reopening the app.
- **Isolation:** UI tests launch with `-ui-testing`: in-memory database, the system light/dark mode. `-ui-testing-db <path>` uses a file for tests that relaunch.
- **Screenshots:** `TEST_RUNNER_SCREENSHOT_DIR=docs/screenshots xcodebuild ... -only-testing:FolioUITests/ScreenshotTests test`
- **Demo video:** `DemoTests` plays the tour slowly. Run it with `TEST_RUNNER_DEMO=1` while `xcrun simctl io booted recordVideo demo.mp4` records the simulator, then convert with `ffmpeg`.
