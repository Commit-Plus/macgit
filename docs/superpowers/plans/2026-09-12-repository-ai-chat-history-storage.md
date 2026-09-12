# Phase 1: SQLite persistence

- [x] Actor-isolated SQLite store and repository/date index.
- [x] Atomic upsert of a Codable transcript, retaining message IDs, tool output, citations, and evidence fingerprints.
- [x] Search normalized titles and transcript text, load payload only on selection.
- [x] Parameter binding and visible propagation of storage errors.

A conversation is one atomic SQLite row; search uses a normalized text column and substring matching. Full-text indexing can be added if measured history sizes justify it.
