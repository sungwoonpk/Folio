# Architecture

How Folio is put together. The reasons behind the big choices are in [decisions](decisions/README.md).

## Repo structure

```
Folio/
├── App/                       SwiftUI app
│   ├── FolioApp.swift         Entry point, colors, fonts
│   ├── RootView.swift         Split view and navigation stack
│   ├── HomeView.swift         Folders, search, Edit, Recently Deleted button
│   ├── FolderScreen.swift     One folder's notes, grouped by date
│   ├── EditorView.swift       Editor: loading, autosave, header buttons
│   ├── NoteTextView.swift     Text runs: title, bullets, checklists
│   ├── TableBlockView.swift   Editable table
│   ├── TrashScreen.swift      Recently Deleted
│   ├── AppModel.swift         State and actions
│   └── Components.swift       Header, buttons, rows, folder picker
├── Packages/NoteCore/         Everything that is not UI (Swift package)
│   ├── Sources/NoteCore/
│   │   ├── Models.swift       Folder, Note, Block
│   │   ├── AppDatabase.swift  SQLite schema and migrations
│   │   ├── NoteStore.swift    Every read and write
│   │   ├── NoteDocument.swift Note text <-> blocks
│   │   ├── NoteGrouping.swift Today, Last 7 Days, months, years
│   │   └── FolderSearch.swift Folder names, any part, any case
│   └── Tests/NoteCoreTests/   Unit tests
├── UITests/                   Tests that drive the real app
├── .github/                   CI, issue and PR templates, Dependabot
├── CHANGELOG.md               What changed, release by release
├── docs/                      Screenshots, demo GIF, design decisions
└── project.yml                XcodeGen project definition
```

## How it works

- **Two layers.** `NoteCore` has no UI and is tested without a simulator. `App` draws and calls `NoteStore`.
- **Storage.** SQLite through GRDB. Tables `folder`, `note`, `block` and a search index. Changes ship as numbered migrations, so old data carries forward.
- **Note content.** A note is blocks: `text`, `bullet`, `checklist` (checked ones marked `done`), `table` (cells as JSON). Title and one-line preview are cached on the note, so lists never load bodies.
- **Search.** FTS5 with the trigram tokenizer: any part of a word, any case. Under three characters it falls back to a substring scan. Folder names are matched separately.
- **Editor.** Text runs with tables between them. Each run is a `UITextView` styled as you type. Markers `•` `○` `◉` are what you see and become blocks on save.
- **Load safety.** The editor stays locked until the note has been read, and retries on failure. A failed read can never become an empty note that overwrites the real one.
- **Navigation.** `NavigationSplitView` with a `NavigationStack`. System bars are hidden, each screen draws one header so actions sit together at the top right.

## Decisions in short

The reasoning is written down in [decisions](decisions/README.md): [one-level folders](decisions/0001-one-level-folders.md), [trigram search](decisions/0002-trigram-search.md), [blocks and text runs](decisions/0003-blocks-and-text-runs.md), [30 days in Recently Deleted](decisions/0004-recently-deleted-expiry.md). In short:

- **Folders are one level.** Nested trees get confusing. `NoteCore` enforces it, the UI does not just hide it.
- **Notes always live in a folder.** No loose pile to lose track of.
- **A deleted folder is not kept.** Only notes are recoverable, they are what holds content.
- **Deleted notes expire.** They stay in Recently Deleted for 30 days, then they are removed for good.
- **Local first.** No account, no network. Fast to open, nothing to leak.
- **Plain markers in the text.** Return, backspace and selection behave as people expect, and it still saves as real blocks.
