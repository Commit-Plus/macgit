# Native Repository Tabs Phase 1

**Roadmap:** [`2026-08-15-native-repository-tabs-roadmap.md`](2026-08-15-native-repository-tabs-roadmap.md)

**Status:** [completed]

## Scope

1. Re-enable native AppKit window tabbing for the main `WindowGroup`.
2. Replace process-global new-window payload flags with a typed, unique per-window request.
3. Configure each main window with a shared tabbing identifier and a repository-aware tab title.
4. Add File menu actions for New Tab, New Window, Open/Clone Repository, Close Repository, Close Tab, and Close Window.
5. Retain standard Window menu tab navigation, tab-bar, merge, and detach behavior supplied by AppKit.
6. Scope File, repository toolbar, Search, Git Undo, and Git Flow notifications to the key native tab.
7. Prevent interactive tab/window dismissal while a repository operation is active.
8. Add focused request/routing tests, run `git diff --check`, targeted tests, and a macOS build.
9. Preserve the existing tab-group frame when a repository-picker tab is created or revisited.

## Acceptance Criteria

- Command-T creates a native tab whose initial content is `RepoPickerView`.
- A single tab does not force the tab bar to remain visible; creating a second tab reveals the native bar below the toolbar.
- Command-N creates a separate repository-picker window.
- Command-W closes only the selected tab and closes the window when it is the last tab.
- Shift-Command-W closes all tabs in the selected window group.
- Close Repository keeps the tab and returns it to `RepoPickerView`.
- Opening a repository, recent repository, clone result, or worktree targets the intended tab/window without shared payload races.
- Commands received by inactive tabs do not perform Git or presentation actions.
- Each tab keeps its own repository and operation state.
- Opening a repository-picker tab does not resize the existing repository window.

## Verification

- `RepositoryWindowRequestTests` previously passed for unique picker-window identity, request coding, and active-window notification ownership. After adding picker-tab size preservation coverage, the target compiled but the XCTest host aborted before bootstrapping with the repository's known `Early unexpected exit ... abort() called` failure; the command was not rerun.
- `git diff --check` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed. Existing Swift concurrency warnings remain outside this feature scope.
- The application was not launched, per repository verification policy.
