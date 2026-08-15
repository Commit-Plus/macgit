# Inline Create Pull Request Phase 1

**Roadmap:** [`2026-08-15-inline-create-pull-request-roadmap.md`](2026-08-15-inline-create-pull-request-roadmap.md)

**Status:** [completed]

## Scope

1. Route every in-app Create Pull Request entry point to the Pull Requests sidebar item.
2. Replace sheet presentation with an inline create mode owned by Pull Request workspace state.
3. Split the create screen into a compact scrollable draft form and a resizable read-only changes area.
4. Load local changed files and selected-file patches using the existing three-dot target/source comparison rules.
5. Reuse existing file-list and diff presentation components.
6. Preserve loading, empty, error, validation, cancellation, and submit behavior.
7. Add targeted controller and Git diff tests.

## Acceptance Criteria

- Create from the Pull Requests header, Workspace context menu, or local branch context menu selects Pull Requests and displays the inline editor.
- The branch context flow still publishes/pushes before showing the editor and uses the chosen remote.
- Changing source or target reloads the changed-file list and selected-file diff without publishing stale results.
- Create stays disabled while changes are loading, unavailable, empty, invalid, or submitting.
- Cancel returns to the Pull Request list and clears draft change state.
- Successful creation refreshes the list and exits create mode.

## Verification

- Targeted Pull Request, provider, model, and Git merge-diff tests passed.
- `git diff --check` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed.
