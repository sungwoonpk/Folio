# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Recently Deleted removes notes for good after 30 days, and the screen says so (decision record 4)
- VoiceOver labels for the selection marks, pinned notes and table cells
- `docs/architecture.md` and `docs/testing.md`

### Changed
- The app is called Folio, renamed from Notes
- An open note is saved the moment the app leaves the foreground, without waiting for the typing pause
- The README is shorter: layout, internals and test details moved into `docs/`
- `Package.resolved` is committed, so tests and CI use the same GRDB version
- Every generated `*.xcodeproj` is ignored, and the leftover `Notes.xcodeproj` stub is gone

### Fixed
- Compiler warnings in `NoteCore`

## [0.1.0] - 2026-11-08

First working version.

### Added
- Folders, one level deep, with notes sorted by last change: Pinned, Today, Last 7 Days, Last 30 Days, months, years
- Notes with a title line, bullets, checklists and tables, saved automatically
- Search over folder names and note text that matches any part of a word, in any case
- Recently Deleted: restore into a chosen folder, or make a new folder on the spot
- Edit mode: select to delete or move, drag folders into order
- Light and dark mode, one icon flips between them
- Unit tests for storage, search, migrations and the document model, and UI tests that drive the real app
- GitHub Actions: unit tests and a simulator build on every push and pull request

### Fixed
- An old note could open empty and be saved over, because the editor read the note inside a task that SwiftUI cancels during navigation (#10)
- Folder names are trimmed, cannot be empty and are capped in length (#17)
- Pasted Windows and old Mac line endings no longer leave stray characters (#18)
- Restoring a note that was never deleted no longer moves it (#19)
- A note can be restored when no folder exists (#20)
- Edit no longer fights a search in progress (#21)
- The last opened note is no longer tinted on a compact screen (#22)
- The light and dark switch has two states instead of three that looked alike (#23, #24)
