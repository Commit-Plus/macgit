# Phase 2: History modal and lifecycle

- [x] Replace placeholder with searchable history sheet, date and preview rows, loading/error/empty states.
- [x] Serialize saves at explicit boundaries: question submission, response completion/cancellation/error, completed Git actions, and new/load transitions. Streaming deltas only update memory; interrupted responses retain their received text with an interruption notice.
- [x] Restore messages and identity for follow-up; prohibit switching while requests or Git approvals are active.
- [x] Reset transcript identity on every conversation selection, with initial scroll anchored at the bottom.
- [x] Initially render the latest 20 messages with exact stack measurement; load earlier messages in pages of 20 while anchoring the previously first message. Keep the complete transcript available to the AI; this is render pagination, not database pagination.
- [x] macOS xcodebuild build succeeded; git diff --check passed.

No app launch or runtime tests, following the repository instruction to verify by building.

Do not launch the app. Interactive UI validation remains for the user.

- Transcript scrollbar uses the shared Sidebar overlay bridge with small controls; only user scroll phases reveal it, then it hides after 900 ms idle. Loaded messages use an eager VStack to avoid lazy height estimates for long Markdown. Load more still reveals 20 messages at a time; rendering cost grows with explicitly loaded history. Runtime scroll verification remains pending.
