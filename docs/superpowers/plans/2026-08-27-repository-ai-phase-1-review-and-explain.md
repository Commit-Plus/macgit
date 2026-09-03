# Repository AI Phase 1: Review Changes and Explain Commits

**Status:** completed

## Goal

Ship the first repository-scoped AI assistant using bounded, app-selected Git context. Users can review current unstaged/untracked changes, explain a recent commit or validated commit-ish, choose any configured AI provider, and read the answer in the repository toolbar panel.

## Delivered architecture

```text
RepositoryAIChatView
  -> RepositoryAIChatController chooses a typed context
  -> AIProviderController executes that context
  -> GitStatusService builds a bounded snapshot
  -> selected CommitMessageAIProvider generates text
  -> fingerprint is revalidated before display
```

The model does not choose or execute tools in Phase 1. `RepositoryAIToolCall` contains only `workingTreeChanges` and `commitChanges(reference:)`, and the app executes the selected case before making the provider request.

## Completed tasks

- [completed] Add provider-neutral Repository AI request, message, tool-result, error, and commit-choice models.
- [completed] Add `RepositoryAIToolExecuting` on `GitStatusService` with bounded working-tree and commit-change snapshots.
- [completed] Validate commit references before Git execution and resolve them to stable object IDs.
- [completed] Add Repository AI prompts that treat repository content as untrusted evidence.
- [completed] Extend Apple Intelligence, OpenAI, Claude, Gemini, DeepSeek, and OpenRouter with repository-response generation.
- [completed] Add a main-actor chat controller with Review Changes, Explain Commit, free-form questions, provider selection, loading/error presentation, and New Conversation.
- [completed] Gate the panel through the existing `repositoryChat` feature access policy.
- [completed] Add focused routing, commit-reference, context-budget, and stale-fingerprint tests.

## Acceptance criteria

- Review Changes and a normal free-form question receive bounded unstaged and untracked working-tree evidence.
- Explain Commit resolves `HEAD`, a branch, a tag, or another validated commit-ish and includes bounded metadata, name status, number statistics, and patch context.
- A provider change or repository fingerprint change prevents a stale answer from being displayed as current.
- Repository text, paths, and commit messages are data in the prompt and cannot become app instructions.
- Provider availability, configuration, and generation failures appear as assistant-visible errors.
- No Phase 1 Repository AI path stages, unstages, commits, checks out, fetches, pushes, or invokes a shell.

## Known limitations carried forward

- `submitDraft()` always chooses `workingTreeChanges`; `git diff` therefore omits changes that exist only in the index. A prompt such as `review staged files` cannot obtain staged-only evidence. Phase 2 addresses this through model-selected `git diff --cached`.
- The visible transcript is primarily presentation state. Most providers receive one assembled request rather than the full local multi-turn conversation and tool history.
- The model cannot request another Git query after seeing the first snapshot, recover from an insufficient query, inspect an individual file on demand, or cite a validated source location.
- Repository output is bounded only through the two fixed context builders; there is no general AI Git policy or agent call budget.

## Main implementation seams

- `macgit/Models/RepositoryAI.swift`
- `macgit/Services/RepositoryAIToolExecutor.swift`
- `macgit/Services/RepositoryAIPrompt.swift`
- `macgit/App/AIProviderController.swift`
- `macgit/App/RepositoryAIChatController.swift`
- `macgit/Views/MainWindow/RepositoryAIChatView.swift`
- `macgitTests/RepositoryAITests.swift`

## Independent phase contract

Phase 1 is a completed baseline, not a prerequisite checklist that forces the remaining phase order. Any later phase may keep this fixed-context behavior as its fallback while adding its own standalone services and UI. Later merges may replace the internal routing, but they must preserve Phase 1 quick actions, feature access, providers, errors, and stale-result safety.

## Non-goals

- Model-driven or repeated tool calls.
- Staged-only free-form review.
- Arbitrary file reading or broader history/branch/pull-request analysis.
- AI-proposed repository mutations.
