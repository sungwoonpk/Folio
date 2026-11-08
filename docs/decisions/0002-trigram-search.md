# 2. Search uses an FTS5 trigram index

Status: accepted, 2026-11-08

## Decision
Note text is indexed in SQLite FTS5 (`noteSearch`: note id, title, body) with the `trigram` tokenizer. A search matches any part of the text, in any case. Folder names are matched separately in Swift.

## Why
The goal was that `est`, `3`, `test` and `TEST` all find `Test3`. A normal word tokenizer only matches whole words or word starts. The trigram tokenizer splits text into overlapping three-character pieces, so any substring of three or more characters matches, case-insensitively, and the index does the work instead of a scan.

## How it works
- A query of three or more characters becomes a quoted phrase for FTS5, with quotes inside it escaped. Characters like `*`, `-`, `OR`, parentheses and quotes are plain text, not search syntax. Tests cover these.
- A query of one or two characters is too short for trigrams, so it falls back to a `LIKE` scan with `%` and `_` escaped.
- Folder names are matched with a case- and accent-insensitive substring check, because there are few of them.
- The index is rewritten whenever a note is saved. Deleted notes are removed from it, and come back when restored. Table cell text is indexed too, but kept out of the list preview.

## Costs
- A trigram index is bigger than a word index.
- One- and two-character queries scan the index rather than use it. That is fine at personal scale, and not measured beyond it. A test checks that a three-character-plus search over ten thousand notes stays under fifty milliseconds.
- No ranking or stemming. Results are ordered by pinned, then last change.

## Considered
- **`LIKE` on the stored blocks.** Simple, but a full scan for every search.
- **FTS5 with the default word tokenizer.** Fast, but would not find `est` inside `Test3`.
- **Filtering in memory.** Simplest, but loads every note body and does not scale.
- **A search library.** More than a notes app of this size needs.
