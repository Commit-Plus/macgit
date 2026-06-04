## Context
This change modifies the main window sidebar to display local branches as a hierarchical tree. It touches the navigation model (`SidebarSelection`), the sidebar view (`SidebarView`), the main window coordinator (`MainWindowView`), and the history view (`HistoryView`).

## Goals
- Display local branches as a slash-delimited folder tree in the sidebar.
- Unify sidebar selection so both workspace items and branches can be selected within the same `List`.
- Route branch clicks to the History view with the correct branch filter.
- Provide immediate checkout via double-click and a rich context menu via right-click.

## Non-Goals
- Remote branch tree (handled by REMOTES section separately).
- Full rename/delete implementation inside context menu (leverages existing `BranchSheetView` where possible).
- Pull request creation workflow.

## Decisions

### Decision: Unified `SidebarSelection` enum
**What:** Replace `SidebarItem?` with a new `SidebarSelection` enum:
```swift
enum SidebarSelection: Hashable {
    case item(SidebarItem)
    case branch(String)
}
```
**Why:** SwiftUI `List(selection:)` requires a single homogeneous tag type. Branches are dynamic strings, while workspace items are static enum cases. A wrapping enum is the cleanest way to let both coexist in the same selectable list without resorting to proxy IDs or separate state variables that can fall out of sync.

### Decision: Build tree in-memory from flat branch list
**What:** On each refresh, take the flat array of branch names from `GitStatusService.localBranches`, split on `/`, and build a lightweight `BranchNode` tree (`isFolder: Bool`, `name: String`, `children: [BranchNode]`).  
**Why:** Git itself does not store folders; the hierarchy is purely a naming convention. A client-side tree construction is sufficient and avoids adding a new persistence layer or Git CLI complexity.

### Decision: Branch selection → History view with filter parameter
**What:** When `selectedBranch` is non-nil, `MainWindowView` renders `HistoryView(repositoryURL: repositoryURL, branchFilter: selectedBranch)`. When a workspace item is selected, it behaves exactly as before.  
**Why:** This reuses the existing History UI, graph canvas, and file-diff panels rather than creating a separate "branch detail" view, minimizing code duplication.

### Decision: History view accepts optional `branchFilter: String?`
**What:** Add an optional `branchFilter` parameter to `HistoryView`. When provided, the view loads `git log <branch> …` instead of `git log --all …` and hides the "All Branches / Current Branch" picker.  
**Why:** Keeps the existing "All Branches" toggle behavior intact while allowing external callers (the sidebar) to lock the filter to a specific branch.

### Decision: Context menu items as placeholders where unsupported
**What:** The right-click context menu will show all requested items. Actions that are not yet implemented (e.g., "Create Pull Request", "Track Remote Branch") will be visible but disabled, or omitted if they require substantial new backend work.  
**Why:** Provides UI parity with the SourceTree reference. Fully implementing every action would bloat this change. We will implement the ones that already have service support (Checkout, Merge, Delete, Rename, Copy) and disable/omit the rest.

## Risks / Trade-offs
- **Risk:** `SidebarSelection` enum change is a breaking API change for `SidebarView` and `MainWindowView`.  
  → Mitigation: Both files are in the same module; no public framework API to maintain. Update is mechanical.
- **Risk:** Frequent branch refreshes in large repositories could cause UI flicker.  
  → Mitigation: Load branches inside `SyncState` background refresh or only on explicit user refresh / app activation. The initial implementation will load on `task` and rely on existing background sync triggers.

## Migration Plan
No migration needed; this is a net-new UI feature within the existing app.

## Open Questions
- None at this time.
