# Autonomous AI Conflict Resolution Roadmap

Build a repository-scoped resolver that lets the selected AI provider resolve complete text-conflict files, stage successful results, and interrupt the user only for decisions the repository context cannot determine.

## Architecture

- Reuse `AIProviderRegistry` and `AIProviderController`; do not create a parallel provider or credential path.
- Keep `ConflictMergeToolView` presentation-focused. A dedicated main-actor controller owns progress and user questions, while `GitStatusService` remains responsible for reading Git stages, fingerprinting inputs, writing files, and staging resolved results.
- Require typed decisions for every conflict section: Current, Incoming, Both in either order, replacement code, or Needs User.
- Reject stale or incomplete plans before modifying the worktree.
- Treat repository content as untrusted prompt data and keep cloud-provider context within each provider's configured character budget.

## Phases

- [completed] **Phase 1 — Autonomous text-conflict resolution**
  - Plan: [2026-08-31-ai-conflict-resolution-phase-1.md](2026-08-31-ai-conflict-resolution-phase-1.md)
  - Add typed request/response models and provider-neutral generation.
  - Load Base, Current, Incoming, and parsed conflict sections with a stable fingerprint.
  - Resolve every supported file automatically, including replacement code, and stage complete files.
  - Collect only undecidable sections as grouped user questions.
  - Add toolbar progress, provider selection, actionable failures, and post-run navigation.
- [pending] **Phase 2 — Context retrieval and validation repair**
  - Add repository-confined `read_file`, `search_code`, history, and symbol-context requests.
  - Allow bounded multi-round context retrieval before asking the user.
  - Add optional user-configured validation commands and one bounded AI repair pass.
- [pending] **Phase 3 — Recoverable batch transactions**
  - Capture original worktree bytes and unmerged index entries before applying a batch.
  - Restore complete batches through one Undo AI Resolution command.
  - Persist an interrupted-session recovery record under repository-local Git metadata.
- [pending] **Phase 4 — Cross-file consistency repairs**
  - Permit explicit, previewable edits outside conflicted files when resolving API or symbol migrations requires them.
  - Keep cross-file writes in the same recoverable transaction and never auto-commit the merge.

## Shared safety rules

- Never apply a plan if its file fingerprint or selected provider changed while generation was running.
- Never stage a file with unanswered sections, duplicate/missing decisions, empty replacement code, or remaining conflict markers.
- Do not execute repository-provided scripts without explicit user configuration.
- Do not automatically commit or push a merge.
- API keys remain device-local in Keychain and never enter prompts, logs, repository files, or Firebase.
