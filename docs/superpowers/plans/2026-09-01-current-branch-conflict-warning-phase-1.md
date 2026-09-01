# Current Branch Conflict Warning Phase 1

**Branch:** `codex/current-branch-conflict-warning`

## Tasks

- [completed] Add typed current-branch integration status and base-branch resolution.
- [completed] Add non-mutating base-merge conflict prediction.
- [completed] Add the fetch, upstream update, and base merge orchestration with Git Undo.
- [completed] Add the current-branch sidebar warning, details popover, and one-click action.
- [completed] Add focused temporary-repository integration tests.
- [completed] Run `git diff --check`, build the macOS app, and compile the test target without launching it.
- [completed] Expose predicted conflict paths and annotate matching File Status rows without replacing real-conflict presentation.
- [completed] Add File Status context-menu details with a read-only three-way conflict preview and the shared current-branch update action.

## Acceptance criteria

- Only the checked-out branch is inspected and warned.
- Existing upstream ahead/behind badges continue to describe the tracked feature branch.
- A separate warning appears when the resolved base has commits missing from the current branch.
- Enabled Git Flow topic branches use their configured base; other branches use the tracked remote's default branch.
- Warning details identify the upstream/base refs and missing commit counts.
- One action fetches relevant refs, updates from upstream when necessary, then merges the base remote-tracking ref.
- Dirty worktrees and in-progress Git operations cannot start the update.
- Predicted textual conflicts are visibly distinguished from ordinary base drift.
- Successful updates are undoable and never automatically pushed.
- Matching staged/changed rows show an orange outlined warning when the incoming base also changes their path; actual conflicts retain their filled purple conflict icon and do not show the preventive warning.
- Potential-conflict rows expose details from both their context and more menus, including exact conflict markers when a temporary three-way analysis can produce them.

## Verification

- `git diff --check` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build-for-testing` passed, including the new test source.
- Tests and the app were not launched, following the repository's macOS verification rule.

## Non-goals

- Scanning or warning on non-current local branches.
- Detecting semantic conflicts.
- Automatically stashing, committing, pushing, or force-pushing.
- Persisting inferred base branches for arbitrary existing branches.
