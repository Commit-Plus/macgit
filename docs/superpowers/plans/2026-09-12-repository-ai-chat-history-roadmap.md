# Repository AI chat history

Local history for the current repository, searchable by title and transcript, with selection restoring a conversation for continued chat.

- [completed] [Phase 1: SQLite persistence](2026-09-12-repository-ai-chat-history-storage.md)
- [completed] [Phase 2: History modal and lifecycle](2026-09-12-repository-ai-chat-history-ui.md)

Use the system SQLite3 module, no third-party dependency. Store the database in Application Support/Commit+/RepositoryAI/history.sqlite, outside repositories. Repository identity is the normalized path with symlinks resolved; moving a repository does not migrate its history. Pending Git approvals are never persisted. No cloud sync or automatic retention policy in this scope.
