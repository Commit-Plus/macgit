# Repository AI Phase 6: Confirmed Remote Git Operations

**Status:** [pending]

**Branch:** `codex/repository-ai-confirmed-remote-git-operations`

## Goal

Let Repository AI prepare and explain safe remote operations—fetch, fast-forward pull, and ordinary push—while Commit+ owns authentication, target selection, preflight, confirmation, execution, refresh, and error recovery.

## Independent delivery

- This phase may start from the completed Phase 1 baseline. Without Phase 2, it uses one typed remote-operation proposal from the selected provider and the normal confirmation UI.
- With Phase 2 present, a model can request a semantic remote-operation proposal, but no mutation or network operation runs in the agent loop. The generic `execute_git` query tool remains read-only and offline.
- It may adopt Phase 4's validated remote/branch context when present; otherwise all remote and ref identities are resolved by app code from the current repository state.

## Architecture

```text
User request
  -> provider proposes RepositoryAIRemoteOperation
  -> app resolves current remote + local/upstream refs
  -> preflight / preview / expected-state fingerprint
  -> explicit user confirmation
  -> existing SyncState / GitStatusService remote operation
  -> refresh and deterministic chat result
```

The provider never sends raw `git push`, credentials, a URL, refspec, `--force`, or arbitrary Git arguments.

## Initial action set

- `fetch(remoteID:)`
- `pull_fast_forward(remoteID:branchID:)`
- `push_current_branch(remoteID:)`

## Scope and safety rules

- Resolve `remoteID`, current branch, upstream, remote-tracking ref, and refspec exclusively through trusted repository state. The provider chooses only opaque IDs supplied in the planning manifest.
- Fetch is explicitly confirmed when initiated by chat, because it causes network activity and updates remote-tracking refs.
- Pull requires a preflight proving it is a fast-forward under the established Commit+ pull policy. Divergence, conflicts, an in-progress Git operation, detached HEAD, missing upstream, a dirty state that existing pull policy rejects, or a changed remote cancels the proposal.
- Push requires a configured upstream or an app-owned explicit upstream-selection sheet. Preview local and remote object IDs, commits-to-push count, target branch, and any protected-branch warning before confirmation.
- Revalidate the remote URL/identity, local HEAD, upstream, target remote-tracking ref, and relevant working/index fingerprints immediately before execution.
- Do not expose passwords, access tokens, SSH command configuration, custom transport helpers, URLs from a model, or provider-account credentials in prompt/tool data or chat output.
- Force push, `--force-with-lease`, arbitrary refspecs, deleting remote branches/tags, remote URL/config changes, clone, submodule remote operations, and pull request mutations remain out of scope.

## Tasks

- [ ] Add typed `RepositoryAIRemoteOperation`, app-resolved remote/branch manifests, expected-state snapshots, and a pending-confirmation lifecycle bound to one repository window.
- [ ] Add a pure policy that accepts only opaque remote/branch IDs from the current trusted manifest and produces exact preflight requirements.
- [ ] Reuse existing SyncState/GitStatusService fetch, pull, and push paths rather than issuing model-generated Git arrays; preserve existing credential prompts and error reporting.
- [ ] Present an app-owned confirmation sheet whose title, target remote/branch, commits count, warnings, and button are derived from the preview, never provider prose.
- [ ] Integrate optional Phase 2 semantic proposal transport while suspending the run at approval; cancellation/denial/staleness must be returned as deterministic app-generated outcomes.
- [ ] Add real temporary-repository tests for fetch, fast-forward pull, ordinary push, missing/diverged upstream, protected branches, stale refs, denied/cancelled proposals, and no operation before confirmation.
- [ ] Run `git diff --check`, focused remote/Repository AI tests, the full suite subject to the known Firebase bootstrap limitation, and the macOS build without launching the app.

## Acceptance criteria

- A chat request can prepare fetch, a safe fast-forward pull, or an ordinary push, but every operation remains pending until the user confirms an exact app-owned preview.
- The provider cannot select arbitrary hosts/URLs/refspecs, send credentials, force a push, bypass existing Git policy, or execute a remote operation through `execute_git`.
- Stale state, preflight failure, cancellation, denial, or an operation error leaves the repository/chat in an accurate, actionable state.

## Non-goals

- Force or lease-force pushes, remote branch/tag deletion, remote configuration, arbitrary refspecs, cloning, interactive rebase/merge resolution, pull-request mutation, or automatically retrying a remote action.
