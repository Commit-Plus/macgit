# Tag Context Menu Design

## Goal

Expand the right-click menu for tag leaf rows in the sidebar from its current copy-only action to a compact set of useful tag operations matching the supplied reference.

## Context Menu

For a tag named `v1.0.1`, show these items in order:

1. **Copy Tag Name to Clipboard**
2. Divider
3. **Checkout v1.0.1**
4. **Details...**
5. Divider
6. **Diff Against Current**
7. Divider
8. **Push to** submenu containing the configured remotes
9. **Delete v1.0.1**

Checkout reuses the existing detached-HEAD confirmation flow. The Push submenu is disabled when the repository has no configured remotes.

## Tag Details

`Details...` opens a small sheet with basic information for the selected tag:

- tag name
- resolved commit hash
- commit author name and email
- commit date
- commit subject and body

Both lightweight and annotated tags resolve through to their tagged commit for the commit fields. The sheet has a single **OK** button and displays a clear error state if the metadata cannot be loaded.

## Operations

- **Diff Against Current** opens the app's existing history/diff experience for the tag versus the current checkout. The implementation should reuse existing comparison presentation where available instead of adding comparison UI to the sidebar.
- **Push to > remote** pushes only the selected tag to the chosen remote, then refreshes repository state.
- **Delete** first presents a destructive confirmation naming the tag. Confirmation deletes only the local tag, reloads the Tags section, and falls back to History if the deleted tag was selected.

All Git execution belongs in `GitStatusService` or existing `MainWindowView` operation callbacks. `SidebarView` owns menu presentation and lightweight sheet/confirmation state, but should not duplicate subprocess logic.

## Error Handling

Failures use the existing repository-operation/error presentation paths. A failed push or deletion leaves the tag and current selection unchanged. Actions register state changes only after Git reports success.

## Testing and Verification

- Add focused service tests for tag metadata resolution, pushing one tag, and deleting a local tag.
- Add pure-policy or menu-support tests where behavior can be separated from SwiftUI rendering.
- Build with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.
- Do not launch the app after building.
