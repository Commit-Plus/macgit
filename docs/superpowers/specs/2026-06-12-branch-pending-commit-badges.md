# Branch Pending Commit Badges

**Date:** 2026-06-12
**Status:** Approved

## Overview

Display the number of pending commits that need to be pushed (ahead) or pulled (behind) for each branch in the BRANCHES sidebar, similar to SourceTree.

## Motivation

Currently, users cannot see at a glance which local branches have unpushed commits or are behind the remote. This leads to confusion when working across multiple branches and increases the risk of accidentally diverging or forgetting to push work.

## Design

### Data Model

```swift
struct BranchSyncStatus: Equatable {
    let ahead: Int   // local commits not on remote
    let behind: Int  // remote commits not on local
}
```

- `ahead > 0`: branch has local commits that have not been pushed to the upstream.
- `behind > 0`: the upstream branch has commits that have not been pulled.
- `ahead == 0 && behind == 0`: branch is in sync with upstream.

### Git Service Extension

Extend `GitStatusService+Branch.swift` with:

```swift
func branchSyncStatus(for branch: String, in repositoryURL: URL) async -> BranchSyncStatus?
```

Implementation logic:
1. Call `upstreamBranch(for:branch:)` to check if the branch has an upstream tracking branch.
2. If no upstream exists, return `nil` (badge hidden).
3. If upstream exists:
   - Run `git rev-list --count <branch>..<upstream>` to get behind count.
   - Run `git rev-list --count <upstream>..<branch>` to get ahead count.
   - If both are `0`, return `nil` (badge hidden).
   - Otherwise return `BranchSyncStatus(ahead: ahead, behind: behind)`.

### UI Changes

In `SidebarView`:

1. Add state:
   ```swift
   @State private var branchSyncStatus: [String: BranchSyncStatus] = [:]
   ```

2. In `loadBranches()`, after fetching the branch list and current branch, iterate through all branches and fetch `BranchSyncStatus` for each to populate the dictionary.

3. In `branchRowView(for:)`, after the branch name, insert a `Spacer()` and a trailing badge container:
   - If `ahead > 0`: show a small gray pill with the number and an up-arrow (`↑`).
   - If `behind > 0`: show a small gray pill with the number and a down-arrow (`↓`).
   - Badge style: `Color.secondary` background, white text, `cornerRadius(4)`, `font(.system(size: 10))`.
   - If both ahead and behind are non-zero, show both badges side by side.

### Data Flow

```
SidebarView loads
  └── loadBranches()
        ├── fetch local branches
        ├── fetch current branch
        ├── for each branch: fetch upstreamBranch()
        │   └── if upstream exists: fetch ahead/behind via rev-list
        └── store results in branchSyncStatus
              └── branchRowView re-evaluates, shows badges
```

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Branch has no upstream (untracked) | Badge hidden entirely |
| Branch is in sync with upstream | Badge hidden |
| Only ahead | Single `↑` badge with count |
| Only behind | Single `↓` badge with count |
| Both ahead and behind | Both badges shown side by side |

### Error Handling

- If `rev-list` fails (e.g., network issue during remote fetch), silently return `nil` for that branch rather than crashing the UI.
- The main branch list is already wrapped in `isLoadingBranches` / `ProgressView`, so the sync status loading will naturally piggyback on that experience.

## Trade-offs

- **Per-Branch Git Commands (Chosen):** For each branch, run individual `rev-list` commands. Simple to implement and accurate. Most personal repos have < 30 branches, so this is acceptable. Can be upgraded to batch computation later if performance becomes a concern.

## Future Work

- Batch `rev-list` calls to reduce git process overhead for repositories with many branches.
- Progressive loading: show branch names immediately and fill in badges asynchronously.
- Cache sync statuses across refreshes to avoid redundant git calls.

