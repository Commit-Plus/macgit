# Drag and Drop Git Actions - Design Spec

**Date:** 2026-06-27
**Status:** Approved (brainstorm phase)
**Author:** Codex collaboration session

## Purpose

Add a small, safe subset of Tower-style drag-and-drop Git actions to macgit. The first release makes common actions discoverable without reproducing Tower's full feature set or introducing hidden branch checkouts.

Reference: [Tower - More Productive with Drag and Drop](https://www.git-tower.com/features/drag-and-drop)

## V1 Scope

1. Select and drag one or more commits from History onto any local branch to cherry-pick them.
2. Drag a local branch onto the currently checked-out branch and confirm either Merge or Rebase.
3. Drag one commit or one local branch onto the BRANCHES header to open Create Branch with the dragged ref as its starting point.
4. Drag one or more selected working-copy files onto the STASHES header to stash only those paths.
5. Drag a stash entry onto File status to apply the stash without deleting it.

## Safety Boundary

Commit drops are accepted by any local branch. After explicit confirmation, macgit checks out a non-current target before cherry-picking and leaves that branch checked out. Branch merge and rebase drops remain limited to the currently checked-out branch.

Every accepted drop opens a confirmation sheet before Git runs. Merge is the default branch operation; holding Option while dropping preselects Rebase. Stash-to-working-copy is Apply-only in v1, while Pop remains available through the existing context menu.

## Chosen Approach

Implement three vertical slices over a small shared drag payload and validation policy:

1. Commit drag foundation and cherry-pick.
2. Branch drag merge/rebase and branch creation.
3. File/stash drag workflows.

This approach ships useful, testable behavior after every phase. Building every workflow at once would create a large coordinated change in `SidebarView`, while a generic drag-action framework would add abstractions before macgit has enough drag workflows to justify them.

## Architecture

### Shared Drag Model

Add a typed `GitDragPayload` conforming to `Transferable`. Supported payloads are:

- Ordered commit hashes.
- One local branch name.
- Working-copy file paths.
- One stash ref.

Every payload includes the standardized repository path. Drop validation rejects payloads created by another repository or window.

Add a pure `GitDragDropPolicy` that maps a payload and target to an allowed action or a rejection reason. It owns branch-operation target checks, payload cardinality, accepted target combinations, and source/target equality checks. It does not run Git commands or present UI.

### View Responsibilities

- `HistoryView` owns commit selection and creates commit payloads.
- `FileStatusView` uses its existing action selection to create file payloads.
- `SidebarView` creates local-branch and stash payloads, renders all drop targets, and forwards accepted requests.
- `MainWindowView` owns pending drag actions, confirmation sheets, and execution coordination.
- Existing `GitStatusService` extensions remain the only layer that invokes Git.
- Existing `GitUndoManager` registration paths remain the undo layer.

This keeps drag decoration close to each row while avoiding Git execution logic inside drop handlers.

## Interaction Design

### Commit Selection and Drag

- Plain click selects one commit and displays its details.
- Command-click toggles a commit in the selection.
- Shift-click selects the visible range from the selection anchor.
- Dragging a selected row carries the full selection.
- Dragging an unselected row carries only that commit.
- A batch is normalized into oldest-first History order before cherry-pick.
- Every local branch row highlights with a distinct fill and border while a commit payload is over it and shows a concise cherry-pick action label.
- Dropping opens a confirmation that lists the target branch and ordered commits.
- Confirming a non-current target checks out that branch before cherry-picking and leaves it checked out.

Multi-selection applies only to drag actions in v1. The detail panel continues to show the primary selected commit.

### Create Branch by Drop

The BRANCHES header accepts exactly one commit or one local branch. Dropping opens the existing Create Branch sheet with the dragged hash or branch preselected as the starting point. The user still enters the new branch name and chooses whether to check it out.

A multi-commit payload is rejected by this target with a concise `Select one commit to create a branch` hint.

### Branch Merge and Rebase

A non-current local branch is draggable. The current branch row is the only merge/rebase target.

- Default drop: open confirmation with Merge selected, then run `git merge <source>`.
- Option-drop: open the same confirmation with Rebase selected, then run `git rebase <source>`.
- The sheet names both source and current branches and explains which branch will move.
- Dropping the current branch onto itself is rejected.

### Stash Selected Files

Dragging a working-copy file row carries all selected action files when the dragged row is selected; otherwise it carries only that row. The STASHES header accepts the payload and opens an adapted stash sheet that displays the selected path count and accepts a message.

The Git operation stashes exactly the selected paths, including matching untracked files, and leaves unrelated working-copy changes untouched. Staged and unstaged changes for a selected path follow Git's path-scoped stash behavior.

### Apply Stash

Each stash row is draggable. File status in the WORKSPACE section accepts one stash payload and opens the existing stash confirmation. Confirming applies the stash and leaves the stash entry in the list.

Pop, dropping individual files out of a stash, and partial stash application are not part of v1.

## Data Flow

### Drag Validation

```text
Source row creates GitDragPayload
  -> target receives payload
  -> GitDragDropPolicy validates repository, source, target, and cardinality
  -> valid target highlights and produces GitDragDropRequest
  -> SidebarView forwards request to MainWindowView
  -> MainWindowView opens the matching confirmation sheet
```

No Git command runs while hovering or directly inside a drop handler.

### Confirmed Execution

```text
Confirmation action
  -> revalidate repository and current branch
  -> reject if another conflicting Git operation is active
  -> invoke existing or extended GitStatusService method
  -> register GitUndoEntry only after success
  -> refresh SyncState
  -> post .repositoryDidChange
  -> dismiss confirmation
```

If the current branch changes between drop and confirmation, the request is rejected and the user must repeat the drop.

## Git Operations

| Action | Command shape | Notes |
|---|---|---|
| Cherry-pick commits | `git cherry-pick <oldest> ... <newest>` | One sequenced operation and one undo entry. |
| Merge branch | `git merge <source>` | Runs only with the destination checked out. |
| Rebase current branch | `git rebase <source>` | Runs only with the current branch checked out. |
| Create branch | `git branch <name> <start>` or existing checkout variant | Reuses Create Branch behavior. |
| Stash selected paths | `git stash push -u -m <message> -- <paths...>` | Includes selected untracked paths and preserves unrelated changes. |
| Apply stash | `git stash apply <ref>` | Does not drop the stash. |

Arguments are passed through `Process.arguments`; no shell command strings are constructed.

## Undo and Refresh Behavior

- Batch cherry-pick captures HEAD before and after the full successful sequence. Undo resets to the old HEAD using the existing expected-HEAD guard; redo cherry-picks the same ordered hashes.
- Merge and rebase use the existing guarded HEAD-changing undo pattern.
- Create Branch uses the existing create/delete branch undo support.
- Path-scoped stash records the exact paths and untracked option in its redo operation so redo does not stash unrelated changes.
- Apply stash reuses the existing safety checks and undo behavior for stash apply.
- No undo entry is registered if the original Git action fails.
- Every successful action refreshes `SyncState` and posts `.repositoryDidChange`.

## Error Handling

Before execution, macgit verifies:

- The payload repository matches the open repository.
- The commit destination branch still exists locally; merge/rebase destinations are still current.
- The source branch is not the current branch.
- The payload has the cardinality required by the target.
- No incompatible cherry-pick, merge, rebase, or conflict resolution is already in progress.

Cherry-pick, merge, and rebase conflicts use the existing in-progress-operation UI so the user can resolve, continue, or abort from File status. Other Git failures use existing error alerts and preserve enough pending context for the user to review what failed.

Invalid hover targets do not accept the drop. Valid targets use an accent highlight plus an action label; drag behavior does not rely on color alone.

## Roadmap

### Phase 1: Commit Drag

- Add `GitDragPayload`, drop targets, and pure validation policy.
- Add testable History multi-selection semantics.
- Drag one or more commits onto any local branch to confirm and cherry-pick oldest-first.
- Drag one commit onto BRANCHES to open Create Branch with the commit preselected.
- Add batch cherry-pick undo/redo support.

### Phase 2: Branch Drag

- Make non-current local branch rows draggable.
- Drag a local branch onto the current branch to confirm Merge or Rebase.
- Use Option-drop to preselect Rebase.
- Drag a local branch onto BRANCHES to open Create Branch with the branch preselected.
- Reuse guarded merge/rebase and create-branch undo support.

### Phase 3: Stash Drag

- Create file payloads from existing File status action selections.
- Drag selected files onto STASHES to open a path-scoped stash confirmation.
- Extend stash service and redo metadata with selected paths.
- Make stash rows draggable.
- Drag a stash onto File status to confirm Apply-only behavior.

## Testing

Each phase includes pure unit tests and real temporary-repository integration tests.

### Unit Tests

- `HistoryCommitSelectionTests`: plain, Command, and Shift selection; primary commit; drag selection resolution; oldest-first ordering.
- `GitDragDropPolicyTests`: repository mismatch, current versus non-current target, source equals target, supported payload/target pairs, and cardinality rules.
- `FileDragSelectionTests`: selected-row payload versus unselected-row fallback and staged/unstaged duplicate path handling.

### Integration Tests

- Batch cherry-pick applies commits oldest-first and supports guarded undo/redo.
- Branch merge moves only the current branch and registers undo.
- Branch rebase rebases only the current branch and registers undo.
- Create Branch uses the dropped commit or branch as its start point.
- Path-scoped stash stores selected tracked and untracked paths while preserving unrelated changes.
- Stash apply changes the working copy while retaining the stash entry.
- Failed or conflicting operations do not register undo entries and expose the existing in-progress state.

Run focused tests during each task, then run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Do not launch the app after verification. Pointer-level drag previews, hover highlights, modifier-key behavior, and VoiceOver labels are manual QA for the user.

## Out of Scope for V1

- Arbitrary destination branches or hidden branch checkout.
- Remote branch drag sources or targets.
- Commit reordering, squash, fixup, or revert-by-modifier.
- Cherry-picking merge commits that require mainline selection.
- Push, pull, publish, track, or pull-request drag actions.
- Dragging individual files out of commits or stashes.
- Partial stash application or stash Pop by drag.
- Cross-repository drag actions.
- A generic plugin-style drag action registry.
