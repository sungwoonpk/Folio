# 1. Folders are one level deep

Status: accepted, 2026-11-08

## Decision
Folders can only sit at the top. A folder cannot hold a folder. Every note lives in exactly one folder.

## Why
- The main screen is a flat list of folders and each folder is a flat list of notes. Every note is two taps from the start.
- A flat list keeps the screens simple: the folder picker, drag to reorder and Edit mode all work on one list, with no tree to expand.
- Deep trees are easy to build and hard to use. People lose notes inside them.
- "Notes always live in a folder" means there is no loose pile of notes to lose track of.

## How it is enforced
In `NoteStore`, not in the screens. `createFolder` and `moveFolder` throw `tooDeep` when a folder would go below the limit, so no code path can break the rule. The limit is a parameter (`maxFolderDepth`, default 1) so the tree logic can still be tested with deeper trees.

Older data was brought forward by a migration (`v2-flat-folders`): folders that were inside folders moved to the top level, and no note was lost.

Deleting a folder removes it for good. Its notes are not lost: they go to Recently Deleted without a folder, and restoring one asks which folder to put it in (`v4-no-folder-trash`).

## Costs
- No hierarchy for people who want one. Search and manual folder order are the answer to that.
- A folder with a lot of notes is a long list. Notes are grouped by date to keep it readable.

## Considered
- **Unlimited nesting.** Rejected for the reasons above.
- **Tags instead of folders.** Not built. Folders are what people expect, and a note in one place is easier to reason about.
- **An "All Notes" view and loose notes.** Tried and removed. It made the main screen mix two ideas.
