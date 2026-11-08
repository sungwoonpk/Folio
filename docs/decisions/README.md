# Design decisions

Why Folio works the way it does. Each record is short: what was decided, why, what it costs, and what else was considered.

| # | Decision | In one line |
| --- | --- | --- |
| [1](0001-one-level-folders.md) | Folders are one level deep | Every note is two taps away, and the rule lives in the store |
| [2](0002-trigram-search.md) | Search uses an FTS5 trigram index | Any part of a word matches, in any case |
| [3](0003-blocks-and-text-runs.md) | Notes are blocks, edited as text runs | Plain text to type in, structure to search and preview |
