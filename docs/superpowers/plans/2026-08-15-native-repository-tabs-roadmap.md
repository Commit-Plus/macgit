# Native Repository Tabs Roadmap

**Goal:** Add Finder-style native macOS tabs so each tab owns one repository window session, opens a repository picker with Command-T, and exposes standard tab actions in the File and Window menus.

## Global Constraints

- Use AppKit native window tabbing rather than a custom in-content tab strip.
- Keep the tab bar hidden for a single tab and let macOS place it below the repository toolbar when a second tab is created.
- Keep repository state isolated per tab, including `MainWindowView`, `SyncState`, Git undo, Pull Request state, sheets, and operation progress.
- Route File, Actions, Git Undo, Search, and Git Flow commands only to the active tab.
- Preserve repository opening, clone, recent-repository, worktree-window, account, Firebase, and local Git behavior outside the tab lifecycle.
- Every new Swift file starts with the repository AGPL v3 header.
- Do not launch the application. Verification ends with focused tests and a successful macOS build.

## Phases

| Phase | Scope | Status | Plan |
| --- | --- | --- | --- |
| 1 | Native tab lifecycle, per-window requests, File/Window commands, active-tab routing, and verification | [completed] | [`2026-08-15-native-repository-tabs-phase-1.md`](2026-08-15-native-repository-tabs-phase-1.md) |

## Completion

The roadmap is complete when Command-T opens a native repository-picker tab, File exposes New/Close tab and window actions, repository commands target only the selected tab, focused tests pass, and the macOS build succeeds.
