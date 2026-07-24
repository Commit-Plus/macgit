# Branch List Cache Design

## Goal

Remove the small loading pause when branch selectors open by sharing one cached
source for local branches and remote-tracking branches across the sidebar,
push confirmation, and other branch-list sheets.

## Scope and behavior

- Cache only branch discovery already available in the local repository. It
  does not run network `git fetch` implicitly.
- Cache local branch names by repository URL.
- Cache remote-tracking branch names by repository URL and remote name.
- Use a two-minute TTL. A cache hit returns immediately; an expired or
  missing entry runs the existing Git discovery command and replaces the entry.
- Deduplicate concurrent requests for the same repository/key so opening more
  than one picker does not start duplicate discovery processes.
- Sidebar repository loading may prefetch local and remote-tracking branch
  lists, so later sheets normally render from the warm cache.

## Architecture

Add a small actor-owned branch cache behind `GitStatusService`:

- `BranchListCache` owns entries, timestamps, and in-flight tasks.
- `GitStatusService` exposes cached branch-list methods and one repository
  invalidation method. Views do not access the cache directly.
- Existing uncached discovery methods remain the single Git command seams used
  by the cache, keeping parsing and process execution centralized.

All branch-list consumers migrate to the cached methods, including
`SidebarView`, `PushSheetView`, `BranchSheetView`, `MergeSheetView`,
`PullSheetView`, repository settings, pull-request branch selection, and any
other UI branch picker found during implementation.

## Invalidation

Invalidate the local branch-name cache immediately after a successful branch
creation, deletion, or rename, regardless of the remaining TTL. Changing a
branch's commit tip does not invalidate this cache: commit, merge, rebase,
reset, cherry-pick, revert, pull, fetch/fast-forward, and push do not change
the set of local branch names. Checkout also does not change that set; the
current-branch marker is separate state. The invalidation must not happen
before a failed operation is reported.

The remote-tracking branch-name cache is invalidated after an explicit fetch
(including prune), and after push when the operation can create or delete a
published branch. Discovery still reads local remote-tracking refs; a later
fetch remains the source of truth for branches changed by other clients.

## Testing

Add focused tests for:

1. A valid entry being returned without a second discovery.
2. An entry expiring after two minutes.
3. Invalidation forcing the next request to rediscover.
4. Concurrent requests sharing one in-flight discovery.
5. Repository and remote keys not leaking results into one another.

Build verification will use the project's macOS `xcodebuild ... build` command;
the app will not be launched.
