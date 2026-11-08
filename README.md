# Note

> Cause all note apps are terrible.

A fast, quiet notes app for iPhone. Folders, checklists, bullets and tables, search that finds a word by any part of it, and nothing to sign in to. Everything stays on the phone in a local SQLite database.

Built with SwiftUI and SQLite.

<p align="center">
  <img src="docs/screenshots/01-folders.png" width="19%" alt="Folders">
  <img src="docs/screenshots/02-notes.png" width="19%" alt="A folder's notes, grouped by date">
  <img src="docs/screenshots/03-checklist.png" width="19%" alt="A checklist">
  <img src="docs/screenshots/04-table.png" width="19%" alt="A table">
  <img src="docs/screenshots/05-dark.png" width="19%" alt="Dark mode">
</p>

## What it does

- **Folders, one level deep.** The main screen shows only folders. Tap one to see its notes. No folders inside folders, on purpose.
- **Notes grouped by when you last changed them.** Pinned, Today, Last 7 Days, Last 30 Days, then months, then years.
- **A first line that is the title.** It is bold and larger. Everything below is the note.
- **Bullets, checklists and tables** in the same note. Return continues a list, Return on an empty item ends it. Tap a circle to check an item off.
- **Search that is forgiving.** `est`, `3`, `test` and `TEST` all find `Test3`. It searches folder names and note text, and works for Korean too.
- **Recently Deleted.** Deleting a note moves it here. Restoring asks which folder it should go into. Deleting a folder removes the folder and sends its notes here.
- **Edit mode** on the folder list and on a notes page: select several items to delete or move, drag folders into the order you want.
- **Light, dark or follow the phone.** One icon cycles through the three. Plain white and black, with brown for small details.
- **Autosave.** Nothing to press. A note that is opened and left empty is removed.

## Using it

| To do this | Do this |
| --- | --- |
| Make a folder | Folder icon at the top right of the main screen |
| Write a note | Open a folder, press the brown button at the bottom right |
| Make a list or table | Icons at the top right of a note: bullets, checklist, table |
| Check something off | Tap its circle |
| Pin, move, duplicate a note | Press and hold it, or swipe right to pin |
| Delete a note | Swipe left, or press and hold. It goes to Recently Deleted |
| Rename, duplicate or delete a folder | Press and hold it |
| Reorder folders | Edit, then drag the handles |
| Delete or move many at once | Edit, tick the items, then Delete or Move |
| Get a deleted note back | Recently Deleted (bottom of the main screen), swipe right or Edit, then choose a folder |
| Change light and dark | The sun/moon icon next to Edit |
| Find anything | Search field on the main screen |

## Run it

You need Xcode with the iOS 17 SDK or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `project.yml`, so it is not checked in.

```bash
git clone https://github.com/sungwoonpk/Note-App.git
cd Note-App
brew install xcodegen
xcodegen generate
open Notes.xcodeproj
```

Pick an iPhone simulator and press Run. The only dependency, [GRDB](https://github.com/groue/GRDB.swift), is fetched by Swift Package Manager the first time.

## Tests

```bash
# Logic: storage, search, trash, document model (no simulator needed)
cd Packages/NoteCore && swift test

# The real app, driven through its screens in a simulator
xcodebuild -project Notes.xcodeproj -scheme Notes \
  -destination 'platform=iOS Simulator,name=<an installed iPhone>' test
```

UI tests launch the app with `-ui-testing`, which uses an in-memory database, so every test starts from an empty app and cannot depend on another. `-ui-testing-db <path>` uses a database file instead, for a test that needs to relaunch the app.

To redo the screenshots above:

```bash
TEST_RUNNER_SCREENSHOT_DIR=docs/screenshots xcodebuild -project Notes.xcodeproj -scheme Notes \
  -destination 'platform=iOS Simulator,name=<an installed iPhone>' \
  -only-testing:NotesUITests/ScreenshotTests test
```

## Repo structure

```
Note-App/
├── App/                       The SwiftUI app
│   ├── NotesApp.swift         Entry point, colors, fonts, light/dark setting
│   ├── RootView.swift         Split view and the navigation stack
│   ├── HomeView.swift         Folder list, search, Edit mode, Recently Deleted button
│   ├── FolderScreen.swift     One folder's notes, grouped by date
│   ├── EditorView.swift       The note editor: loading, autosave, header buttons
│   ├── NoteTextView.swift     Text view for a run of text: title, bullets, checklists
│   ├── TableBlockView.swift   The editable table
│   ├── TrashScreen.swift      Recently Deleted
│   ├── AppModel.swift         App state and every action the screens call
│   └── Components.swift       Header, icon buttons, rows, folder picker
├── Packages/NoteCore/         Everything that is not UI. A Swift package
│   ├── Sources/NoteCore/
│   │   ├── Models.swift       Folder, Note, Block
│   │   ├── AppDatabase.swift  SQLite schema and migrations
│   │   ├── NoteStore.swift    Every read and write: folders, notes, trash, search
│   │   ├── NoteDocument.swift Note text <-> blocks: bullets, checklists, tables
│   │   ├── NoteGrouping.swift Today / Last 7 Days / months / years
│   │   └── FolderSearch.swift Folder names by any part, any case
│   └── Tests/NoteCoreTests/   Unit tests
├── UITests/                   Tests that drive the real app in a simulator
├── docs/screenshots/          Images used in this README
└── project.yml                XcodeGen project definition
```

## How it works

**Two layers.** `NoteCore` knows nothing about screens. It can be tested in a second without a simulator. `App` only draws and calls `NoteStore`.

**Data.** SQLite through GRDB, in WAL mode. Three tables: `folder`, `note`, `block`, plus a full-text index `noteSearch`. A note is a list of blocks. The block kinds that are in use are `text`, `bullet`, `checklist` (checked ones are marked `done`) and `table` (cells as JSON). Each note row also caches its title and one-line preview, so the lists never load note bodies. Schema changes are numbered migrations, and old data is carried forward (for example, folders that were nested in an earlier version were moved to the top level, and nothing was lost).

**Search.** Full-text search with the trigram tokenizer, which matches any part of a word, ignores case, and needs no spaces, so it works for Korean. Queries shorter than three characters fall back to a plain substring scan. Folder names are matched separately. A test checks that searching ten thousand notes takes under fifty milliseconds.

**The editor.** A note is shown as runs of text with tables between them, so there is always somewhere to put the cursor. Each run is a `UITextView` that is styled as you type: the first line is the title, list lines get a marker (`•`, `○`, `◉`) and a hanging indent, checked items are crossed out. The markers are what you see, and they are turned into blocks when saving. Korean input is handled: the text is never rewritten while a character is still being composed.

**Safety.** The editor stays locked until the note has been read from the database, and tries again if the read fails. A failed read can never turn into an empty note that gets saved over the real one. This was a real bug, found by a test that reopens notes repeatedly, and it has a test of its own now.

**Navigation.** `NavigationSplitView` with a `NavigationStack` for the folder screens. The system navigation bars are hidden and every screen draws one header, so all actions sit together at the top right.

## Design decisions

- **Folders are one level.** Nested trees get confusing fast. The rule is enforced in `NoteCore` (it throws), not just hidden in the UI.
- **Notes always live in a folder.** There is no loose pile of notes to lose track of.
- **A deleted folder is not kept.** Only notes are recoverable, because they are the thing with content.
- **Local first.** No account, no network. Fast to open, nothing to leak.
- **Plain markers in the text.** Keeping `•` and `○` in the text makes Return, backspace and selection behave the way people expect, and still saves as real blocks.

## Status

A working first version, tested on iPhone simulators.

Not done yet: sync and sign-in, images, voice notes, numbered lists. The layout for iPad exists but has not been tested.
