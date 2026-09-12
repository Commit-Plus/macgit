# Phase 2: History modal and lifecycle

- [x] Replace placeholder with searchable history sheet, date and preview rows, loading/error/empty states.
- [x] Serialize saves, debounce transcript updates, flush at response completion and before new/load transitions.
- [x] Restore messages and identity for follow-up; prohibit switching while requests or Git approvals are active.
- [x] Reset transcript identity on every conversation selection, with initial scroll anchored at the bottom.
- [x] Initially render the latest 20 messages in a lazy stack; load earlier messages in pages of 20 while anchoring the previously first message. Keep the complete transcript available to the AI; this is render pagination, not database pagination.
- [x] macOS xcodebuild build succeeded; git diff --check passed.

No app launch or runtime tests, following the repository instruction to verify by building.

Do not launch the app. Interactive UI validation remains for the user.
