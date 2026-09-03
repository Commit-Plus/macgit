# Repository AI Phase 4: Broader Repository Analysis

**Branch:** `codex/repository-ai-broader-analysis`

## Goal

Expand Repository AI beyond the current working tree and single commit so users can compare branches or refs, search bounded commit history, and analyze an existing GitHub or GitLab pull request using Commit+'s current local Git and provider-account services.

## Independent delivery

- This phase may start from the completed Phase 1 baseline without Phase 2, Phase 3, or Phase 5.
- Without Phase 2, branch comparison, history search, and pull-request analysis are explicit context modes or quick actions that load typed evidence before the provider request.
- With Phase 2 present, the same services register as model-callable tools. The generic `execute_git` policy remains read-only and does not absorb provider API calls.
- Without Phase 3, Phase 4 uses its own validated commit/ref/PR references and plain source labels. If the shared citation model is already present, it adopts it and adds commit/PR citation kinds.

## Architecture

```text
Repository AI context action or optional agent harness
  -> RepositoryAIRepositoryAnalysisService
       -> GitStatusService for refs/history/diffs
       -> PullRequestProviding for GitHub/GitLab context
  -> bounded evidence + fingerprint
  -> selected AI provider
  -> validated answer and optional references
```

## Scope decisions

- Add three independent typed capabilities: `compare_refs`, `search_history`, and `pull_request_context`.
- Local Git analysis stays offline and read-only. Pull-request context uses existing authenticated GitHub/GitLab services and their normal account/repository matching.
- Never let the model construct an arbitrary provider URL, host, API token, HTTP header, or remote Git command.
- Bound result counts, patch sizes, comments, and metadata before provider submission.
- Treat branch names, commit messages, PR bodies, reviews, comments, and patches as untrusted repository/provider data.

## Task 1 — Shared analysis contracts

- [ ] Add typed inputs/results for ref comparison, history search, and pull-request context with explicit truncation and fingerprint metadata.
- [ ] Add validated `RepositoryAIRef` and `RepositoryAICommitReference` values resolved by app code before expensive context loading.
- [ ] Add a capability registry that can be invoked by explicit UI context modes and optionally adapted to the Phase 2 tool registry.
- [ ] Keep service results provider-neutral and independent of SwiftUI, HTTP response payloads, or tool-call envelope formats.
- [ ] Reuse Phase 3 citations when present; otherwise expose stable source labels and keep an adapter seam for later citation adoption.

## Task 2 — Branch and ref comparison

- [ ] Implement `compare_refs(base:head:)` using validated refs resolved to immutable object IDs.
- [ ] Determine the merge base and return ahead/behind counts, commit subjects, file name status, number statistics, and a bounded `base...head` patch.
- [ ] Distinguish two-dot commit ranges from three-dot review diffs explicitly; do not let provider wording choose ambiguous Git semantics.
- [ ] Cover branches, remote-tracking refs, tags, detached HEAD, missing refs, unrelated histories, renamed files, merge commits, and large comparisons.
- [ ] Fingerprint resolved base/head/merge-base IDs so a moved branch invalidates the answer.

## Task 3 — Bounded history search

- [ ] Implement `search_history` with app-controlled fields for query text, author, path, ref scope, date bounds, order, and result limit.
- [ ] Translate only typed filters to approved `git log` arguments; never accept a raw revision expression or arbitrary format string from provider output.
- [ ] Default to the current branch and a small result limit; require explicit user context to broaden to all local branches/remotes.
- [ ] Return stable commit IDs, dates, authors, subjects, matched paths, and bounded snippets suitable for a follow-up Explain Commit action.
- [ ] Reject regex/path/ref forms that exceed the supported grammar or could trigger external helpers/unbounded output.

## Task 4 — Pull-request context

- [ ] Add `RepositoryAIPullRequestContextService` over `PullRequestProviding` and existing account/repository resolution.
- [ ] Allow an explicit selected PR from Commit+'s list/detail state or a validated PR number for the current canonical repository only.
- [ ] Load bounded title, body, author, base/head refs, state, labels, participants, reviews/comments, changed-file metadata, and patch context already available through existing GitHub/GitLab services.
- [ ] Exclude credentials, authorization headers, hidden account data, unrelated repositories, and mutation methods such as comment, merge, close, or update.
- [ ] Fingerprint provider, canonical repository identity, PR number, update timestamp/head SHA, and supplied changed-file context.
- [ ] Surface missing account, unsupported host, permission, rate-limit, deleted PR, and stale PR errors without falling back to guessed local data.

## Task 5 — Provider and controller integration

- [ ] Add Compare Branches, Search History, and Analyze Pull Request context actions to Repository AI with native branch/PR pickers already used elsewhere in Commit+.
- [ ] On the Phase 1 standalone path, execute the selected typed capability once and send its bounded result through the existing provider-neutral repository response seam.
- [ ] When Phase 2 is present, register the three capabilities as typed tools and let the harness make repeated calls within its existing budgets.
- [ ] Preserve selected provider, feature-access checks, local conversation lifecycle, cancellation, and stale-response rejection.
- [ ] Do not fetch remotes automatically. Analysis uses current local refs and already requested provider API data; any user-initiated refresh remains a separate existing action.

## Task 6 — Result presentation

- [ ] Show the active analysis scope above the question: base/head refs, history scope/filter, or provider/repository/PR number.
- [ ] Present compact evidence activity without mixing raw provider data into trusted UI labels.
- [ ] Navigate commit references to History and PR references to the existing PR detail when those destinations remain current.
- [ ] If Phase 3 citations are present, validate and render commit/file/PR citations through its common UI; otherwise keep references non-clickable but copyable.
- [ ] Preserve History selection, loaded pagination depth, and existing PR controller cache behavior during background refresh.

## Task 7 — Tests and verification

- [ ] Real Git tests cover ahead/behind, merge base, two-dot/three-dot semantics, moved refs, tags, detached HEAD, unrelated history, renames, merge commits, path filters, dates, authors, empty results, and output bounds.
- [ ] PR service tests cover GitHub/GitLab mapping, canonical repository enforcement, bounded comments/patches, permissions, rate limits, stale head SHA, deleted PRs, and credential exclusion.
- [ ] Controller tests run every capability from the Phase 1 standalone path and optionally verify Phase 2 registration without changing service behavior.
- [ ] Presentation tests cover context labels, navigation, stale references, cancellation, provider errors, and missing-account recovery.
- [ ] Run `git diff --check`, focused Repository AI/Git/PR tests, the full suite for this non-trivial change, and the macOS build sequentially without launching the app. Do not rerun the documented Firebase bootstrap abort.

## Acceptance criteria

- A user can compare two valid refs, search a bounded history scope, or analyze a selected current-repository PR without another pending Repository AI phase.
- Branch comparison is based on immutable resolved objects and rejects answers when refs move during generation.
- PR analysis uses existing provider-account services, never exposes credentials, and never performs a PR mutation.
- Every context has deterministic limits and clear truncation/uncertainty messaging.
- Phase 2 and Phase 3 integrations are adopted when available but are not required for Phase 4 completion.

## Non-goals

- Automatic fetch, pull, remote discovery, cloning, or background provider polling initiated by AI.
- Creating, commenting on, editing, closing, approving, or merging pull requests.
- Whole-repository indexing, semantic code search, embeddings, or arbitrary provider HTTP access.
- Working-tree or ref mutations.

## Cross-phase integration contract

Phase 4 exports provider-neutral analysis services. Phase 2 may register them as tools, Phase 3 may validate their citations, and Phase 5 may consume their immutable refs as proposal context. Each consumer remains optional and must not move network or mutation authority into the generic Git query executor.
