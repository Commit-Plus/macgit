# Repository AI Roadmap

Build a repository-scoped AI assistant in the toolbar side panel. The assistant must use bounded, read-only Git tools and the existing provider, credential, model, and entitlement architecture.

## Phases

- [completed] **Phase 1 — Review changes and explain commits**
  - Add typed `working_tree_changes` and `commit_changes` tools on `GitStatusService`.
  - Bound diff context, validate commit references, and reject stale working-tree answers.
  - Extend every implemented AI provider with repository-question generation.
  - Replace the placeholder Chat tab with quick actions, context selection, provider selection, and a conversation transcript.
  - Gate execution through the existing `repositoryChat` feature policy.
- [pending] **Phase 2 — File-aware follow-up tools**
  - Add safe file-content and file-diff tools with explicit path allow-lists from Git results.
  - Preserve multi-turn context while revalidating repository state.
- [pending] **Phase 3 — Broader repository analysis**
  - Add branch comparison, history search, and pull-request context tools.
  - Add citations from responses back to files, commits, and diff hunks.

## Phase 1 acceptance

- Review current staged, unstaged, and untracked changes without allowing arbitrary shell commands.
- Explain `HEAD` or a user-supplied valid commit-ish.
- Use the currently selected Apple Intelligence or BYOK provider.
- Show provider/configuration and entitlement failures as actionable UI feedback.
- Unit-test tool routing, commit-ref validation, bounded context, and stale-result protection.
- Pass `git diff --check`, targeted tests, and the macOS build without launching the app.
