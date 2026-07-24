# Branch List Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Share local and remote-tracking branch discovery across the sidebar and branch pickers with a two-minute TTL, while invalidating local-name cache only after create/delete/rename.

**Architecture:** Add an actor-owned `BranchListCache` with repository/remote keys, timestamps, and in-flight request deduplication. Expose cached methods and invalidation through `GitStatusService`; keep existing Git commands as the uncached loader seams. Migrate every UI branch-list consumer to the service adapter and prewarm the cache while the sidebar loads.

**Tech Stack:** Swift concurrency (`actor`, `Task`), Foundation `Date`/`URL`, SwiftUI, XCTest, existing `GitStatusService` actor and `xcodebuild`.

## Global Constraints

- Cache only local branch and local remote-tracking discovery; never run network `git fetch` implicitly.
- TTL is exactly two minutes.
- Local branch-name invalidation occurs after successful create, delete, or rename only; changing a branch tip or checking out does not invalidate the local-name cache.
- Remote-tracking branch-name invalidation occurs after explicit fetch/prune and push operations that can create/delete a published branch.
- Every new Swift file starts with the repository's AGPL v3 header.
- Do not launch the app; build is the required macOS verification.

## File map

- Create `macgit/Services/BranchListCache.swift`: pure cache actor and cache key/entry types; no Git or SwiftUI dependencies beyond Foundation.
- Modify `macgit/Services/GitStatusService.swift`: own one cache instance so all service extensions share it.
- Modify `macgit/Services/GitStatusService+Branch.swift`: expose cached local discovery and invalidate after successful local create/delete/rename.
- Modify `macgit/Services/GitStatusService+Remote.swift`: expose cached remote discovery and invalidate remote cache after relevant successful remote mutations.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: use cached discovery and prewarm local/remote branch lists during repository loading.
- Modify `macgit/Views/Common/PushSheetView.swift`, `BranchSheetView.swift`, `MergeSheetView.swift`, `PullSheetView.swift`, `RepositorySettingsSheetView.swift`, and `macgit/App/PullRequestController.swift`: replace direct branch discovery calls with cached service methods.
- Modify `macgit/Views/MainWindow/RepoPickerView.swift` only if its repository-clone branch picker is a local-repository branch-list consumer; otherwise leave its remote-URL discovery unchanged.
- Create `macgitTests/BranchListCacheTests.swift`: cache hit, expiry, invalidation, in-flight deduplication, and key isolation tests.

---

### Task 1: Add the tested cache actor

**Files:**
- Create: `macgit/Services/BranchListCache.swift`
- Test: `macgitTests/BranchListCacheTests.swift`

**Interfaces:**
- Produces `actor BranchListCache` with `static let ttl: TimeInterval = 120`, `enum Key: Hashable` for `.local(URL)` and `.remote(URL, String)`, `values(for:now:load:)`, `invalidate(repositoryURL:)`, and `invalidateRemote(repositoryURL:remote:)`.
- The loader signature is `@escaping @Sendable () async -> [String]`; failed discovery is represented by the existing callers' empty-array loader result, so the cache remains independent of Git errors.

- [ ] **Step 1: Write tests for a cache hit and isolated keys.**

  Use an actor-safe counter and a fixed `Date`:

  ```swift
  func testValidEntryIsReturnedWithoutRunningLoaderAgain() async {
      let cache = BranchListCache()
      let calls = CallCounter()
      let repository = URL(fileURLWithPath: "/tmp/repo-a")

      let first = await cache.values(for: .local(repository), now: Date(timeIntervalSince1970: 0)) {
          await calls.increment()
          return ["main", "feature/a"]
      }
      let second = await cache.values(for: .local(repository), now: Date(timeIntervalSince1970: 60)) {
          await calls.increment()
          return ["different"]
      }

      XCTAssertEqual(first, ["main", "feature/a"])
      XCTAssertEqual(second, first)
      XCTAssertEqual(await calls.value, 1)
  }

  func testLocalAndRemoteKeysDoNotShareEntries() async {
      let cache = BranchListCache()
      let repository = URL(fileURLWithPath: "/tmp/repo-a")

      let local = await cache.values(for: .local(repository), now: .init(timeIntervalSince1970: 0)) { ["main"] }
      let remote = await cache.values(for: .remote(repository, "origin"), now: .init(timeIntervalSince1970: 0)) { ["release"] }

      XCTAssertEqual(local, ["main"])
      XCTAssertEqual(remote, ["release"])
  }
  ```

- [ ] **Step 2: Run the focused tests and verify they fail for the missing cache type.**

  Run:

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/BranchListCacheTests test
  ```

  Expected: compilation failure because `BranchListCache` is not implemented yet.

- [ ] **Step 3: Implement TTL, invalidation, and in-flight deduplication.**

  Store `[Key: Entry]` and `[Key: Task<[String], Never>]` inside the actor. A value is valid when `now.timeIntervalSince(entry.createdAt) < 120`. On a miss, await the existing task when present; otherwise create one from the loader, store the result with the supplied `now`, and clear the in-flight task. `invalidate(repositoryURL:)` removes local and every remote key for that URL; the remote-specific method removes only that remote key.

- [ ] **Step 4: Add expiry, invalidation, and concurrent-request tests.**

  Cover `now == createdAt + 120` as expired, repository invalidation, remote-only invalidation, and two simultaneous `values` calls sharing one loader invocation. Use an async gate/counter rather than sleeps so the test is deterministic.

- [ ] **Step 5: Run the focused tests and commit the cache unit.**

  Run the focused `xcodebuild ... -only-testing:macgitTests/BranchListCacheTests test` command and expect PASS, then commit:

  ```bash
  git add macgit/Services/BranchListCache.swift macgitTests/BranchListCacheTests.swift
  git commit -m "feat: add shared branch list cache"
  ```

### Task 2: Connect the cache to GitStatusService and mutation seams

**Files:**
- Modify: `macgit/Services/GitStatusService.swift`
- Modify: `macgit/Services/GitStatusService+Branch.swift`
- Modify: `macgit/Services/GitStatusService+Remote.swift`

**Interfaces:**
- `GitStatusService` owns `private let branchListCache = BranchListCache()`.
- Add `func cachedLocalBranches(in:) async -> [String]`, `func cachedRemoteBranches(remote:in:) async -> [String]`, `func invalidateBranchListCache(in:) async`, and `func invalidateRemoteBranchListCache(remote:in:) async`.
- Existing `localBranches(in:)` and `remoteBranches(remote:in:)` remain uncached loaders and keep their current parsing behavior.

- [ ] **Step 1: Add service-level cache tests or test seams before implementation.**

  Keep `BranchListCacheTests` responsible for cache mechanics. Verify the adapter by searching that cached methods call the existing discovery methods through `BranchListCache`, and by compiling the service extensions; do not introduce a second fake Git runner solely for this adapter.

- [ ] **Step 2: Implement cached service methods.**

  Route local discovery through `.local(repositoryURL)` and remote discovery through `.remote(repositoryURL, remote)`, passing closures that call the existing uncached methods. Await cache invalidation from the service actor after successful mutations.

- [ ] **Step 3: Invalidate local names only after successful create/delete/rename.**

  In `createBranch`, `deleteBranch`, and `renameBranch`, assign the successful `runGit` output first, then call `await invalidateBranchListCache(in: repositoryURL)`, then return output. A thrown Git error must skip invalidation. `setUpstream`, checkout, and tip-changing operations must not invalidate local branch names.

- [ ] **Step 4: Invalidate remote names after relevant operations.**

  In `fetch(options:in:)` and `fetchBranch(...)`, invalidate remote-tracking cache after the remote Git command succeeds. For `push(options:in:)`, invalidate the affected remote cache after all push commands succeed when branches were pushed; tag-only pushes do not need branch-list invalidation. `deleteRemoteBranch` invalidates its remote cache after success.

- [ ] **Step 5: Build the service changes and commit.**

  Run:

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

  Expect `BUILD SUCCEEDED`, then commit the service integration.

### Task 3: Migrate branch-list consumers and warm the sidebar cache

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/Common/PushSheetView.swift`
- Modify: `macgit/Views/Common/BranchSheetView.swift`
- Modify: `macgit/Views/Common/MergeSheetView.swift`
- Modify: `macgit/Views/Common/PullSheetView.swift`
- Modify: `macgit/Views/Common/RepositorySettingsSheetView.swift`
- Modify: `macgit/App/PullRequestController.swift`
- Inspect/modify: `macgit/Views/MainWindow/RepoPickerView.swift`

**Interfaces:**
- Every local-repository branch-list UI calls `cachedLocalBranches(in:)` or `cachedRemoteBranches(remote:in:)`; no view calls the uncached discovery methods.

- [ ] **Step 1: Replace local branch calls.**

  Migrate the local branch calls in `SidebarView.loadBranches`, `PushSheetView.loadData`, `BranchSheetView.loadBranches`, `MergeSheetView`, `RepositorySettingsSheetView`, and `PullRequestController` to `cachedLocalBranches(in:)`.

- [ ] **Step 2: Replace remote-tracking branch calls.**

  Migrate `SidebarView.loadRemotes`, `BranchSheetView`, `MergeSheetView`, and `PullSheetView` to `cachedRemoteBranches(remote:in:)`. Leave `RepoPickerView`'s `remoteBranches(remoteURL:)` call unchanged if it is discovering branches from a remote URL during clone rather than from an opened local repository.

- [ ] **Step 3: Warm the cache from SidebarView without changing visible behavior.**

  During the existing sidebar repository load, use the cached methods for the branch and remote trees. Do not add an implicit network fetch. The existing loading guards and stale-load IDs remain responsible for UI state; the cache only removes duplicate Git discovery across consumers.

- [ ] **Step 4: Search for uncached UI consumers and compile.**

  Run:

  ```bash
  rg -n 'localBranches\\(|remoteBranches\\(remote:' macgit --glob '*.swift'
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

  Expected: remaining direct calls are only the uncached service implementations, non-local clone discovery, or explicitly documented non-UI seams; build succeeds.

- [ ] **Step 5: Commit the consumer migration.**

  ```bash
  git add macgit macgitTests
  git commit -m "perf: share cached branch discovery across pickers"
  ```

### Task 4: Final verification and handoff

**Files:**
- Modify: none unless verification exposes a scoped issue.

- [ ] **Step 1: Run the focused cache tests.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/BranchListCacheTests test
  ```

- [ ] **Step 2: Run the full build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

  Do not launch the app. If an unrelated full test bootstrap abort occurs, do not repeatedly rerun it; report the exact failure and retain the successful build as verification.

- [ ] **Step 3: Inspect the final diff and status.**

  ```bash
  git diff main...HEAD --stat
  git diff --check
  git status --short
  ```

  Confirm no unrelated files changed, no branch-tip operation invalidates the local name cache, and all new Swift files carry the AGPL header.
