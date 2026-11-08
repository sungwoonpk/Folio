# 3. Notes are blocks, edited as text runs

Status: accepted, 2026-11-08

## Decision
A note is stored as an ordered list of blocks. The editor does not edit blocks one by one. It shows the note as runs of plain text with tables in between, and converts to and from blocks when loading and saving.

## Storage
One `block` row per line or table: `kind`, `content`, `meta`, `position`.

| Kind | Content | Meta |
| --- | --- | --- |
| `text` | the line | none |
| `bullet` | the line, without the marker | none |
| `checklist` | the line, without the marker | `done` when checked |
| `table` | the cells as searchable text | the cells as JSON |

`image` and `audio` exist as kinds but nothing uses them yet. The note row caches its title (first line) and a one-line preview (the lines after it, tables skipped), so lists never load note bodies.

## Editing
Each text run is one `UITextView`. List lines carry a visible marker (`•`, `○`, `◉`) in the text. That keeps Return, backspace and selection behaving like a text editor. `NoteDocument` turns markers into blocks on save and back on load. A table is its own view between two runs, so there is always somewhere to put the cursor.

## Why
- Typing in a real text view feels right. Per-block fields make Return and backspace across blocks awkward.
- Structured blocks make search and previews exact: table cells are searchable but do not appear in the preview, and checked items are known without parsing text.
- New kinds can be added without changing the schema.

## Costs
- Saving replaces all of a note's blocks in one transaction. That is simple and safe, and cost grows with note length. Saves are debounced by 400 ms.
- Because a save replaces everything, the editor must never save before the note has loaded. Early on a cancelled read looked like an empty note and could be saved over the real one (PR #10). The editor now stays locked until a read succeeds.
- A typed line that starts with `• ` becomes a bullet. That is the convention.
- Line endings are normalized before splitting, since pasted text can carry `\r` (#18).

## Considered
- **Attributed text or rich text storage.** Hard to search, preview and migrate.
- **Markdown text.** Simple, but it needs a parser and tables are awkward to edit.
- **One SwiftUI text field per block.** The most direct mapping, and the least pleasant to type in.
