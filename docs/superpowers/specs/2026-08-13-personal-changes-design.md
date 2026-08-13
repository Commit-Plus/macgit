# Personal Changes Design

## Goal

Let a user keep intentional, long-lived local modifications—such as localhost service URLs, local Redis configuration, or machine-specific app settings—inside a tracked working tree without treating those modifications as temporary Git stashes or accidentally committing them through Commit+.

Personal Changes is a Commit+ feature layered on top of normal Git files and patches. Git continues to report the files as modified. Commit+ records which selected hunks belong to a named personal profile, can apply or pause those hunks, and protects them from Commit+-initiated staging by default.

## Product Contract

The following behavior is normative across every phase:

- Adding a change to a profile does not untrack, ignore, reset, stage, or otherwise rewrite the file by default.
- Git continues to report an applied Personal Change as a normal working-tree modification.
- Personal ownership is hunk/line-based, not merely file-based. A file may contain both personal and ordinary changes.
- A profile may contain changes from multiple tracked text files.
- `Keep changes applied` is the default capture behavior. `Save and pause` explicitly stores the patch and reverses it from the working tree only after a complete preflight succeeds.
- `Protect from staging in Commit+` is enabled by default and applies to every Commit+ staging and commit entry point.
- Protection is an application guarantee, not a Git guarantee. External tools and the Git CLI can still stage or commit the same content.
- Apply and Pause are explicit, reversible working-tree operations. Neither changes Git tracking.
- Remove from Profile and Delete Profile keep the working files unchanged.
- Revert and Delete is a separate destructive action that requires confirmation and succeeds only when the stored patch can be reversed safely.
- Patch conflicts never trigger an automatic destructive fallback. The profile or entry becomes `Needs Attention`.
- No phase uses `assume-unchanged`, `skip-worktree`, a hidden commit, a stash ref, or a tracked repository file as the persistence mechanism.

## User Experience

### Sidebar

Add a `PERSONAL CHANGES` section immediately after `WORKSPACE` and before `BRANCHES`. Each row represents a profile rather than a file:

```text
PERSONAL CHANGES
  ● Local Development       Applied
  ○ Local Redis             Paused
  ! Customer Environment    Needs Attention
```

Selecting a row opens a detail surface containing:

- Profile name and branch scope.
- Protection setting.
- Derived profile state for the current working copy.
- Managed files and hunks.
- Apply, Pause, Update, Remove, Delete, and Revert and Delete actions when eligible.

The section is repository-local and persists its expanded state through `SidebarSettingsStore`.

### File Status

Both the ellipsis menu and the right-click context menu use one shared Personal Changes menu implementation:

```text
Personal Changes
  Create New Profile…
  Add to “Local Development”…
  Add to “Local Redis”…
```

For an already-managed selection, the menu may instead offer Update or Remove from Profile. The creation/update sheet previews the selected patch and lets the user choose:

- A new or existing profile.
- Exact hunks/lines.
- `Current Branch` or `All Branches` scope.
- `Protect from staging in Commit+`, on by default.
- `Keep changes applied`, on by default; turning it off means Save and Pause.

Managed files remain visible in `Changed`. Rows and diff hunks receive a Personal badge or visual treatment; the UI must not present the repository as clean when Git reports modifications.

### Staging and committing

When protection is enabled:

- Whole-file, selected-file, Stage All, hunk, line, double-click, quick-action, and commit-all staging paths must not stage managed personal content.
- Normal changes in the same file remain stageable.
- An explicit `Stage anyway` path may be offered only after warning that the content can be committed. It does not silently disable or delete the profile.
- If Commit+ detects that an external tool staged managed content, commit is blocked and the user is offered Review Staged Diff, Unstage Personal Changes, or an explicit Keep Staged override.

## Domain Model

Use stable UUID identity. Never persist `stash@{n}`, a repository path as cross-machine identity, or a transient diff row ID.

```swift
struct PersonalChangeProfile: Codable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: UUID
    var name: String
    var scope: PersonalChangeScope
    var protectsFromStaging: Bool
    var entries: [PersonalChangeEntry]
    let createdAt: Date
    var updatedAt: Date
}

enum PersonalChangeScope: Codable, Sendable {
    case allBranches
    case branch(String)
}

struct PersonalChangeEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let baseBlobOID: String
    let baseFileMode: String
    let patch: String
    let patchFingerprint: String
}
```

The concrete implementation may split manifests and patch payloads into separate files, but the persisted contract must retain equivalent information and a schema version.

Do not persist a trusted `isApplied` Boolean. Applied state depends on the current working copy and can change through an editor, Git checkout, or another tool.

## Derived State

Inspect every entry against the current worktree and index. Aggregate entry state into profile state.

- `applied`: the reverse patch is valid and the forward patch is not needed.
- `paused`: the forward patch is valid and the personal content is absent.
- `partiallyApplied`: entries or selected patch fragments disagree.
- `needsAttention`: neither direction can be applied safely, the base is unavailable, or branch/file state is unsupported.
- `stagedExternally`: protected personal content appears in the index.
- `unavailableForBranch`: the current branch does not match the profile scope.

Inspection is evidence, not mutation. Refreshing File Status or Sidebar must never apply, reverse, stage, or unstage a patch.

## Persistence

Store definitions beneath the absolute Git common directory:

```text
<git-common-dir>/commitplus/personal-changes/
  schema.json
  profiles/
    <profile-uuid>/
      manifest.json
      changes.patch
```

Requirements:

- Writes are atomic and sorted/deterministic where practical.
- A newer unsupported schema is reported without overwriting it.
- A corrupt profile is isolated and surfaced as an error; other profiles still load.
- Definitions are shared by linked worktrees through the Git common directory.
- Current status is inspected separately for each working copy.
- Local repository paths, credentials, and working-copy state are not embedded in an export or future cloud payload.
- No Firebase read or write occurs in Phases 1–5.

## Patch Lifecycle

### Capture

Capture is limited initially to unstaged modifications of tracked, non-conflicted text files with no staged change for the same path.

1. Resolve the current index blob and file mode.
2. Build a unified patch only for the selected hunks/lines.
3. Validate that the patch applies forward to the base and reverses from the current working content.
4. Reject overlapping ownership by another protected profile unless the user resolves the overlap.
5. Save the profile atomically.
6. If Keep Applied is selected, stop without changing the file.
7. If Save and Pause is selected, preflight the complete reverse operation, reverse it once, refresh repository state, and roll back the persisted mutation if execution fails.

### Apply and Pause

Profile-level Apply/Pause is all-or-nothing:

1. Validate branch scope, tracked text paths, index constraints, and every patch entry.
2. Run a complete `git apply --check` equivalent in the requested direction.
3. Apply the complete patch once only if all entries pass.
4. Refresh `SyncState` and post `.repositoryDidChange` after success.
5. On failure, leave both working files and the stored profile unchanged.

Normal changes may coexist if the patch applies cleanly and does not overlap them.

### Remove and Delete

- Remove Entry/Profile Membership changes only the stored definition.
- Delete Profile removes only the stored definition and keeps working files untouched.
- Revert and Delete first preflights a complete reverse, then reverses the patch, and only then removes the stored profile.
- A partially applied or conflicted profile cannot use Revert and Delete until resolved.

### Update

Update replaces selected stored entries only after verifying their old personal patch is represented in the current working content and the replacement selection is valid. It must not absorb unrelated changes merely because they are in the same file.

## Protected Staging Architecture

Direct `git add <path>` cannot preserve a personal hunk in the working tree while staging ordinary changes from the same file. Protected staging therefore needs a dedicated service rather than UI-only filtering.

For whole-file or multi-file staging, the planner creates a candidate index without touching the working tree:

1. Snapshot the real index identity/tree.
2. Create a temporary alternate index based on the real index.
3. Stage the requested working-tree paths into the alternate index.
4. Reverse protected personal patches from the alternate index.
5. Diff the real index tree against the candidate tree.
6. Verify the real index has not changed since the snapshot.
7. Apply the candidate diff to the real index atomically.
8. Delete the temporary index on every exit path.

This design preserves pre-existing staged changes and leaves working files untouched. The implementation must use an explicit alternate-index execution context and must never replace or unlock the real index blindly.

For hunk/line staging, a pure policy classifies requested patch lines as personal, ordinary, or mixed. Ordinary selections use the existing cached patch path. Protected personal selections are blocked by default. Mixed selections require the user to narrow the selection or explicitly override protection; Commit+ must not guess which overlapping lines to stage.

Commit protection is a second guard. Before commit, inspect the index for protected personal content. Blocking commit is required even if the content was staged outside Commit+.

## Branch and Worktree Semantics

- Profile definitions are shared across linked worktrees; status and applied content are not.
- `Current Branch` records the exact branch at capture time. Detached HEAD is unsupported for creating a branch-scoped profile in the MVP.
- Checkout through Commit+ performs a non-mutating Personal Changes preflight before Git checkout.
- Early phases do not automatically pause or apply profiles during checkout.
- A later lifecycle phase may offer a coordinated Pause old profile → Checkout → Apply matching profile operation, but it must be explicit or opt-in, preflight all three steps, and provide recovery if checkout fails.
- External checkout is detected by normal repository refresh. Commit+ reports an out-of-scope applied profile or an available matching profile; it does not silently rewrite files.

## Architecture Boundaries

- SwiftUI views render values and issue callbacks.
- `MainWindowView` owns cross-surface orchestration and repository-operation presentation.
- A `PersonalChangesController` owns loaded profiles and derived per-worktree inspection state.
- `PersonalChangeStore` owns repository-local persistence.
- `PersonalChangeService` owns capture, inspection, Apply, Pause, Update, and safe removal operations.
- `PersonalChangeStagePlanner` and `GitStatusService` own Git/index execution.
- Existing `DiffPatchBuilder` may be reused where its patch contract is sufficient; Personal Changes-specific metadata and classification belong in dedicated types.
- Every async callback constructs and captures immutable `Sendable` requests before crossing a `Task` boundary.

## Eligibility for the Initial Release

Supported:

- Tracked text files.
- Unstaged modified content.
- Selected whole hunks or lines.
- Exact current-branch or all-branches scope.
- Multiple files per profile.

Rejected with a specific reason:

- Untracked or ignored files.
- Binary files.
- Rename, deletion, submodule, or file-mode-only changes.
- Conflict entries.
- A path with staged changes during capture/update.
- Overlapping ownership across protected profiles.
- Detached HEAD for a current-branch profile.

## Safety and Recovery

- Every mutating operation preflights all entries before changing any file.
- Temporary indexes and files use unique temporary directories and are cleaned on success and failure.
- Persistence uses atomic writes and does not overwrite unsupported schemas.
- Operations fail if the index changes after planning.
- External staging is never silently undone.
- Every error identifies the profile and affected path without exposing file content in diagnostics.
- Successful operations refresh `SyncState` and `.repositoryDidChange`; successful routine actions do not add success banners.
- Undo may be added only where the inverse is guarded by the same expected patch/index state. Do not register a best-effort inverse.

## Accessibility and Copy

- Applied, Paused, Needs Attention, and externally staged states must not rely on color alone.
- Icon-only controls have labels and help text.
- Menus name the affected profile and use ellipses when a sheet or confirmation follows.
- Destructive copy distinguishes keeping working files from reverting them.
- The UI explicitly states that Git CLI and other applications can still stage Personal Changes.

## Verification Boundary

- Use real temporary Git repositories for patch, alternate-index, checkout, and external-staging tests.
- Add pure unit tests for schema migration, eligibility, state aggregation, overlap policy, menu eligibility, and protected-stage planning.
- Run `rtk git diff --check` and the focused tests for each phase.
- Run the macOS build after non-trivial phase changes.
- Do not launch the app. Runtime UI validation remains a documented manual acceptance item when a phase changes layout or interaction.

## Explicit Non-Goals

- Making Git itself understand Personal Changes.
- Hiding modified files from `git status`.
- Guaranteeing protection when committing through another application or the CLI.
- `assume-unchanged`, `skip-worktree`, `.gitignore`, stash refs, hidden commits, or automatic branch creation.
- Binary, rename, deletion, untracked, submodule, or conflicted-file support in the initial roadmap.
- Automatic Apply/Pause on external branch changes.
- Team-shared profiles.
- Firebase/cloud synchronization or automatic cross-device merge in this roadmap.
- Uploading source patches without an approved end-to-end encryption and storage design.

