# Change: Add Sidebar Branch Tree

## Why
The BRANCHES section in the sidebar currently shows a disabled "Coming soon" placeholder. Users need to browse local branches, understand the repository's branch hierarchy (especially for slash-separated branch names like `feat/test-new-branch`), and quickly navigate to a branch's history or check it out. This change brings the sidebar closer to the SourceTree-style branch browsing experience.

## What Changes
- Replace the BRANCHES "Coming soon" placeholder with a live tree view of local branches.
- Parse branch names by `/` delimiter to build a collapsible folder hierarchy (e.g., `feat/` folder containing `test-new-branch`).
- Integrate branch selection with the main content panel:
  - Single-click a branch → switch to **History** view filtered to that branch.
  - Double-click a branch → **checkout** that branch (no-op if already checked out).
  - Right-click a branch → display a **context menu** with branch actions (Checkout, Merge into current, Rebase current onto, Fetch, Push to, Track Remote Branch, Diff Against Current, Rename, Delete, Copy Branch Name, Create Pull Request).
- Highlight the **current branch** with a circle icon and bold text.
- Keep other placeholder sections (Tags, Remotes, Stashes, Submodules, Subtrees) as disabled placeholders.

## Impact
- Affected specs: `main-window`
- Affected code:
  - `macgit/Views/MainWindow/SidebarView.swift` — tree rendering, selection, context menus
  - `macgit/Views/MainWindow/MainWindowView.swift` — routing branch selection to HistoryView
  - `macgit/Views/History/HistoryView.swift` — accept optional branch filter parameter
  - `macgit/Services/GitStatusService.swift` — commit history filtered by a specific branch

## Non-Goals
- Remote branches are intentionally excluded from this tree; they remain in the separate REMOTES section.
- Drag-and-drop branch reordering is out of scope.
- Renaming and creating pull requests are menu placeholders unless already implemented elsewhere.
