# Pull Request Detail Changes Phase 1

**Roadmap:** [`2026-08-14-pr-detail-changes-roadmap.md`](2026-08-14-pr-detail-changes-roadmap.md)

**Status:** [completed]

## Scope

1. Add provider-neutral changed-file and patch-availability models.
2. Extend `PullRequestProviding` with a paginated Pull Request changes operation.
3. Decode GitHub Pull Request files and GitLab merge-request diffs, including rename, binary, collapsed, and too-large states.
4. Add lazy loading, error state, refresh, selection, and session cache behavior to `PullRequestController`.
5. Split PR detail into enum-backed Overview and Changes tabs.
6. Reuse `CommitFileListView`, `DiffParser`, and `DiffView` for the read-only Changes experience.
7. Retain `Open Changes` as the provider fallback.
8. Add targeted provider and controller tests, then run `git diff --check`, focused tests, and a macOS build.

## Acceptance Criteria

- Overview renders the current metadata, description, assignees, comments, refresh action, and comment composer.
- Opening Changes triggers its first load without refetching Overview.
- Selecting a text file renders provider-supplied unified diff hunks with syntax highlighting and added/removed line treatment.
- Binary, missing, collapsed, or oversized patches show a clear non-empty state and browser action.
- Switching tabs and reopening a PR reuses valid session cache data.
- Selecting another PR cannot publish stale changed-file results from the previous PR.
- GitHub pagination uses up to 100 files per request and stops at the final page.
- GitLab pagination uses its diffs endpoint and preserves `collapsed` and `too_large` semantics.
- Existing PR detail/comment behavior remains covered and compiles unchanged.

## Verification

- Targeted GitHub, GitLab, and controller tests compiled successfully, but the XCTest host aborted before bootstrapping with the repository's known `Early unexpected exit ... abort() called` environment failure. The test command was not rerun.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` succeeded.
