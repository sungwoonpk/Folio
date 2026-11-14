# 4. Deleted notes expire after 30 days

Status: accepted, 2026-11-13

## Decision
A note stays in Recently Deleted for 30 days. When the app opens, notes that were deleted 30 days ago or longer are removed for good. A note that was never deleted is never touched, however old it is.

## Why
- Recently Deleted is a safety net, not a second archive. Without an end it only grows, and a note someone chose to delete would stay on the device forever.
- 30 days is long enough to notice a mistake and short enough that the list stays about the last month. It is also what people expect from a notes app.
- The screen says it ("Notes are removed for good after 30 days."), so nothing disappears by surprise.

## How it works
`NoteStore.purgeExpiredNotes(now:)` deletes notes whose `deletedAt` is at least `trashRetentionDays` old. The app calls it once at launch, before the first load. It takes `now` as a parameter, so the tests check the 29-day, 30-day and 31-day cases without waiting. Blocks go with their note, and deleted notes are not in the search index, so there is nothing else to clean up.

Notes inside a deleted folder count from the moment the folder was deleted. Notes that were already in Recently Deleted keep the time they were first deleted.

## Costs
- A note not restored within 30 days is gone. There is no second copy.
- It only runs at launch. A device left open for weeks keeps expired notes until the next launch. That is fine for a phone app.

## Considered
- **Never expire.** Simple, but the list grows forever and "deleted" stops meaning deleted.
- **A setting for the number of days.** More to build and explain than it is worth for one list.
- **Per-note countdown ("12 days left").** Nice, but it needs a row layout change for little gain. One line of text at the bottom says the same thing.
