# Tags Sidebar Feature Design

## Overview

Add a **TAGS** section to the sidebar that lists all Git tags in the repository. Tags behave similarly to branches in terms of navigation and interaction, with key differences around checkout behavior (detached HEAD).

## Motivation

Users need to browse and navigate to tagged commits (releases, milestones) directly from the sidebar, just as they do with branches.

## Architecture

### Data Model

Extend `SidebarSelection` to support tags:

```swift
enum SidebarSelection: Hashable {
    case item(SidebarItem)
    case branch(String)
    case tag(String)
}
```

### Git Service

Add to `GitStatusService`:

- `tags(in:)` -> `[String]` — list all tag names
- `tagCommitHash(tag:in:)` -> `String?` — resolve tag to commit hash

### Sidebar View

Replace the placeholder "Coming soon" in the `TAGS` section with a real tag list:

- Flat list of tags (reusing the tree builder if tags contain `/`)
- Tag icon: `tag` (SF Symbol)
- Single click: select tag, show history scoped to tag
- Double click: show detached HEAD checkout confirmation

### Main Window

- Handle `.tag` in `selectedItem` switch
- Pass tag name to `HistoryView` (same as branch)
- Add detached HEAD checkout confirmation sheet

### History View

- Already supports `selectedBranch: String?` — extend to work with tag names too
- `tipHash(for:)` works for any ref (branch or tag)
- No changes needed beyond the parameter name semantics

## Interaction Design

| Action | Behavior |
|--------|----------|
| Single click tag | Select tag, History view shows tag's commit (scrolls to it) |
| Double click tag | Show confirmation: "Are you sure you want to checkout '<tag>'? Doing so will make your working copy a 'detached HEAD'..." |
| Tag context menu | Minimal: "Copy Tag Name to Clipboard" |

## Differences from Branches

- No "current tag" indicator (tags aren't checked out)
- No delete/rename/merge operations
- Double-click shows confirmation instead of direct checkout
- No folder expansion state conflicts (tags and branches are separate sections)

## Files Changed

- `macgit/Views/MainWindow/SidebarView.swift`
- `macgit/Views/MainWindow/MainWindowView.swift`
- `macgit/Services/GitStatusService+Branch.swift` (or new `GitStatusService+Tag.swift`)

## Testing

- Verify tag list appears in sidebar
- Verify single click navigates to tag commit in history
- Verify double click shows detached HEAD confirmation
- Verify checkout puts repo in detached HEAD state

## Open Questions

None — design approved by user.
