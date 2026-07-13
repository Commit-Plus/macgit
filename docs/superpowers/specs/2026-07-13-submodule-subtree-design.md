# Submodule and Subtree Sidebar Management Design

**Date:** 2026-07-13
**Status:** Approved; Phase 1 implementation started
**Source:** User-approved SourceTree-inspired proposal

## Purpose

Add first-class Git submodule and subtree management to Commit+ without turning `SidebarView` into a Git execution layer. Submodules and subtrees share a familiar sidebar presentation, but they retain different data models because Git provides standard metadata for submodules and no equivalent portable registry for subtrees.

## Chosen Approach

Implement submodules first, then subtrees.

- Submodules are discovered from `.gitmodules`, index gitlinks, and `git submodule status`. Commit+ does not persist duplicate submodule metadata.
- Subtrees use a Commit+-owned repository-local registry stored through `git config --local` under `commitplus-subtree.<id>.*` keys. The registry records path, repository, branch, and squash policy.
- `SidebarView` owns presentation state, sheets, confirmation state, and callbacks. Git parsing and mutation remain in `GitStatusService+Submodule.swift` and `GitStatusService+Subtree.swift`.
- Network operations use the existing `GitProviderCredentialResolver`; credentials must not appear in command arguments, logs, registry values, or UI error copy.
- Successful mutations post `.repositoryDidChange`. Creation operations stage or modify repository content but never create a commit automatically.

## Alternatives Considered

### One generic nested-repository model

Rejected because it hides important Git semantics. A submodule points at a gitlink commit and can be uninitialized or detached; a subtree is normal parent-repository content and has no gitlink.

### Infer subtrees only from commit trailers

Rejected because `git subtree` history can be squashed, rewritten, imported without `git subtree`, or missing the original URL and current branch. Inference may assist a future import flow, but it cannot be the source of truth.

### Track a `.commitplus/subtrees.json` file

Rejected for v1 because it adds Commit+-specific tracked content to user repositories. A local Git config registry keeps the feature non-invasive. A user cloning on another Mac must explicitly use `Link Existing Subtree...` to restore the local link.

## User Experience

### Entry Points

- `Actions > Add Submodule...`
- `Actions > Add/Link Subtree...`
- The same two actions in the sidebar background context menu.
- A `+` button in each visible section header.

The existing `Show Submodules` and `Show Subtrees` settings remain visibility preferences. Completing an add/link operation automatically enables the corresponding preference. When a preference is enabled and the list is empty, the section shows a concise empty state with an Add action; the user never has to enable the preference before using an Actions menu command.

### Submodule Row

A row shows the submodule name, relative path, optional configured branch, and one status badge:

- `Clean`
- `Modified`
- `New commits`
- `Not initialized`
- `Missing`
- `Conflict`

Single-click selects the row. Double-click opens an initialized submodule in a new Commit+ window. Context actions are state-aware:

- `Open in Commit+`
- `Show in Finder`
- `Open in Terminal`
- `Initialize`
- `Update to Recorded Commit`
- `Update from Remote...`
- `Synchronize URL`
- `Edit Submodule Settings...`
- `Deinitialize...`
- `Remove Submodule...`

`Update to Recorded Commit` and `Update from Remote...` remain separate because the former follows the superproject gitlink while the latter advances from the configured remote branch.

### Subtree Row

A row shows the registered name, local relative path, branch, and `Squashed` when applicable. V1 does not claim an ahead/behind or synchronized status because calculating that reliably is expensive and ambiguous for rewritten subtree history.

Context actions:

- `Show in Finder`
- `Open in Terminal`
- `Pull from Subtree Remote...`
- `Push to Subtree Remote...`
- `Edit Link...`
- `Unlink from Commit+`

`Unlink from Commit+` removes only local registry metadata. It never deletes the subtree directory. V1 intentionally omits `Remove Subtree` because subtree files are ordinary tracked files and deleting them should remain an explicit parent-repository file change.

## Add Sheets

### Add Submodule

Fields:

- Repository URL, required.
- Local relative path, required and constrained to the repository root.
- Branch, optional; an empty value uses the remote default branch.
- `Initialize after adding`, on by default.
- `Shallow clone`, off by default; when enabled, depth is `1`.

The operation runs `git submodule add`, refreshes repository state, and leaves `.gitmodules` plus the gitlink staged for the user to commit.

### Add or Link Subtree

Fields:

- Mode: `Add new subtree` or `Link existing directory`.
- Repository: an existing remote name or URL, required.
- Branch, required.
- Local relative path, required and constrained to the repository root.
- `Squash imported history`, on by default.

Add mode runs `git subtree add` and records the registry only after Git succeeds. Link mode requires an existing tracked directory, performs no history mutation, and records the registry after validation.

## Architecture

### Models

`GitSubmoduleEntry` contains stable identity, name, path, URL, configured branch, recorded commit, checked-out commit, and `GitSubmoduleState`.

`GitSubtreeEntry` contains registry ID, display name, path, repository, branch, and squash policy.

`SubmoduleAddRequest`, `SubmoduleUpdateRequest`, and `SubtreeLinkRequest` carry validated sheet input into service methods. Paths are always repository-relative strings with `/` separators.

### Services

`GitStatusService+Submodule.swift`:

- Discovers configuration with `git config -z --file .gitmodules --get-regexp`.
- Reads recorded gitlinks with `git ls-files --stage`.
- Reads checkout state with `git submodule status --recursive` and targeted repository checks.
- Owns add, initialize, recorded update, remote update, sync, set URL/branch, deinitialize, and remove operations.

`GitSubtreeRegistry.swift`:

- Reads and writes only `commitplus-subtree.<id>.path`, `.repository`, `.branch`, and `.squash` in local Git config.
- Rejects duplicate paths, missing required fields, paths outside the repository, and registry entries whose path overlaps another registered subtree.
- Uses a stable slug plus collision suffix for IDs; callers do not derive IDs independently.

`GitStatusService+Subtree.swift`:

- Preflights `git subtree -h` before the first mutation.
- Owns add, pull, and push commands.
- Writes registry state only after a successful add.
- Posts repository refresh only after successful mutation.

### UI Boundary

`SidebarView` receives operation callbacks from `MainWindowView`. It does not resolve provider credentials or construct network environments. `MainWindowView` supplies the connected-account credential resolver and uses the existing repository progress runner.

Submodule and subtree UI is split into focused files where practical:

- `SidebarSubmoduleViews.swift`
- `SidebarSubtreeViews.swift`
- `AddSubmoduleSheet.swift`
- `AddOrLinkSubtreeSheet.swift`

The main `SidebarView.swift` retains state orchestration and section placement so the existing list remains one SwiftUI hierarchy.

## Validation and Guards

- Every local path must be non-empty, relative, standardized, and contained by `repositoryURL` after symlink-aware standardization.
- A new submodule/subtree path must not already be registered by the same feature.
- Submodule remove requires confirmation and refuses to proceed while the submodule contains uncommitted changes unless the user explicitly confirms force removal.
- Submodule deinitialize distinguishes local checkout removal from repository removal in its confirmation copy.
- Subtree pull and push require a clean parent-repository index and working tree in v1. Commit+ reports the blocking paths rather than invoking the command.
- Subtree push confirmation states that commits affecting the prefix will be split and sent to the configured repository/branch.
- Cancellation or Git failure leaves sheets open where user input can fix the issue, does not update registry state, and does not post a success refresh.

## Error Handling

- Service methods throw `GitError.commandFailed` with sanitized Git stderr.
- Missing `git subtree` support produces a dedicated actionable error: `This Git installation does not include git subtree.`
- Malformed `.gitmodules` entries appear as unavailable rows only when a safe path can be identified; otherwise they are omitted and one section-level load error is shown.
- A stale subtree registry entry remains visible with `Missing folder`; users can edit or unlink it.
- Authentication uses the same HTTPS/SSH credential environment paths as other remote operations.

## Refresh and Selection

- Load submodules/subtrees lazily when their section first expands, then reload on matching `.repositoryDidChange` notifications.
- Preserve selection by stable path/registry ID across reloads.
- Add `SidebarSelection.submodule(String)` and `SidebarSelection.subtree(String)`; the associated value is the relative path for submodules and registry ID for subtrees.
- Add `submodulesExpanded` and `subtreesExpanded` to `SidebarSectionState` with backward-compatible decoder defaults of `true`.

## Testing Strategy

Use real temporary Git repositories for service integration tests and pure unit tests for parsers, validation, policy, and registry encoding.

- Submodule discovery: initialized, uninitialized, modified, new commit, conflict marker, relative URL, configured branch, nested submodule.
- Submodule lifecycle: add, initialize, recorded update, remote update, sync, set URL/branch, deinitialize, guarded remove, force remove.
- Subtree registry: round-trip, duplicate path rejection, corrupt/incomplete entries, stale directory, unlink without deleting files.
- Subtree lifecycle: capability preflight, add with and without squash, link existing, pull, push, clean-tree guard, failed command does not persist registry.
- Sidebar policy tests cover action visibility and enabled state without snapshot-testing SwiftUI rendering.

During phase implementation, run focused tests first, then the complete test suite for non-trivial changes, and finally a macOS build. Do not launch the app. If the full test host exits during bootstrap with the documented early-exit/abort failure, do not rerun it; a successful build plus focused tests is sufficient.

## Phasing

1. Read-only submodule discovery, sidebar display, and open actions.
2. Safe submodule add, initialize, update, and sync actions.
3. Submodule configuration, deinitialize, and guarded removal.
4. Subtree registry, link-existing flow, and read-only sidebar display.
5. Subtree add, pull, push, capability checks, and network integration.

Each phase is implemented on its own `codex/submodule-subtree-phase-N-*` branch created from clean, current `main`. A phase is marked completed only after it is merged to `main` and verification succeeds there.

## Out of Scope

- Automatically committing any submodule or subtree operation.
- Recursive bulk actions across every nested submodule.
- Editing files inside a submodule from the parent repository detail view.
- Portable tracked subtree metadata.
- Automatic subtree discovery based solely on commit messages.
- Subtree split/merge/rejoin advanced commands.
- Undo/redo registration for network or destructive nested-repository operations in v1.
