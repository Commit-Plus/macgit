# macgit AGENTS.md

## Project: macgit (Commit+)
A macOS Git client built with Swift and SwiftUI. Git is driven via `Process()` subprocess. See `README.md` for details.

## Build & Test

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Run tests after non-trivial changes. Tests live in `macgitTests/` (XCTest, real temp Git repos).

> **Agent note:** Do not launch the app. Verification is complete when `xcodebuild build` succeeds and targeted tests pass. If the full test suite crashes during bootstrapping ("Early unexpected exit" / `abort() called`), do not re-run it; a successful build is sufficient.

### Building from `main` vs. Feature Branches / Worktrees

Xcode places DerivedData under `~/Library/Developer/Xcode/DerivedData/macgit-<hash>/`. The hash is derived from the path to `macgit.xcodeproj`, so each worktree or clone directory gets its own DerivedData folder. Opening `.../macgit-*/Build/Products/Debug/Commit+.app` after building from multiple locations can launch multiple app instances.

To avoid this, pin the `main` build to a fixed DerivedData path:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/macgit-main build
```

For feature branches or worktrees, use the default build command above (each will get its own `macgit-<hash>` folder). After the work is merged and you no longer need the worktree build, remove it:

```bash
find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -type d -name 'macgit-*' ! -name 'macgit-main' -exec rm -rf {} +
```

To start completely fresh, remove all macgit DerivedData and rebuild from `main`:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/macgit-*
```

## License Header

Every `.swift` file must start with the AGPL v3 header. The pre-commit hook blocks commits missing these markers: `Copyright (C)`, `GNU Affero General Public License`, `trantienthanh2412@gmail.com`.

```swift
//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
```

## Architecture

```
macgit/
├── App/         # Entry point, AppState, ToolbarAction, menu/toolbar wiring
├── Views/       # SwiftUI views
├── Services/    # Git operations & business logic (GitStatusService + extensions)
├── Models/      # Data models
├── ViewModels/  # View models
└── Resources/   # Assets
```

Git operations are centralized in `macgit/Services/GitStatusService*.swift`.

## Workflow Conventions

1. **Superpowers skills — use sparingly.** For simple issues, work directly. For complex/multi-step tasks, ask the user before invoking a skill.
2. **OpenSpec is deprecated.** Use `docs/superpowers/specs/` and `docs/superpowers/plans/` instead.
3. **Complex features need a Superpowers roadmap.** Create a top-level roadmap under `docs/superpowers/plans/` linking to per-phase plans, and mark phases `[pending]`, `[in progress]`, or `[completed]`.
4. **Use feature branches for phase work.** Develop on `codex/<phase>` branches branched from `main`; never commit directly to `main`.
   - Before creating a feature branch, ensure you are on `main` and the working tree is clean.
   - If the current branch is not `main` or has uncommitted changes, ask the user to commit/stash them and switch to `main` first.
   - Only create the feature branch from a clean `main` state.

## Current Feature Status: Git Undo Roadmap

**Roadmap:** `docs/superpowers/plans/2026-06-19-git-undo-roadmap.md`

| Phase | Scope | Status |
|-------|-------|--------|
| 0 + 1A | Undo/redo infra + file-level stage/unstage | Merged to `main` |
| 1B | Hunk/line stage undo | Merged to `main` |
| 2 | Commit undo | Merged to `main` |
| 3A | Stash save/drop undo | Merged to `main` |
| 3B | Stash apply/pop undo | Merged to `main` |
| 4 | Local branch actions undo | Merged to `main` |
| 5 | Discard/remove undo | Merged to `main` at `0115a7f` |
| 6 | History actions (cherry-pick/revert/reset/merge/rebase) | Merged to `main` at `177ffb9` |
| 7 | Remote actions (pull rollback, published branch removal) | Merged to `main` at `c896c28` |

Shared rules: undo entries register only after the original action succeeds; every undo/redo refreshes `SyncState` and posts `.repositoryDidChange`; destructive inverses verify expected state before running; undo stacks are not persisted across launches.

## Recent Changes

### Menu Bar Actions Enable/Disable Logic (2026-06-16)
The `@FocusedValue`/`@FocusedBinding` approach does not work reliably with `NavigationSplitView` on macOS, so menu actions are driven by notifications:

- `ToolbarAction.swift` defines `ToolbarAction` and `Notification.Name.toolbarAction`.
- `macgitApp.swift` posts toolbar-action notifications from the `Actions` menu and disables items via `appState.hasOpenRepository`.
- `MainWindowView.swift` listens for `.toolbarAction` and calls `handleToolbarAction(_:)`.

The same notification pattern is reused by Git Undo menu actions (`GitUndoMenuAction.swift`).
