# Git Flow Lite Phase 3: Release and Hotfix Finish

Status: completed on `codex/git-flow-lite-phase-3`.

## Goal

Make Release and Hotfix usable end to end while keeping the first Git Flow version deliberately small and native-Git based.

## Scope

- Finish Release by merging the release branch into Main, creating an annotated version tag, then merging the release branch back into Develop.
- Finish Hotfix by merging the hotfix branch into Main, creating an annotated version tag, then merging the hotfix branch into Develop.
- Keep Feature and Bugfix finish behavior unchanged: one `--no-ff` merge into Develop.
- Store an in-progress finish checkpoint in the repository Git common directory so conflicts can be resumed or aborted after the app refreshes.
- Expose Resume Finish and Abort Finish from the Git Flow app menu and sidebar Git Flow context menu when a checkpoint exists.
- Register compound Undo/Redo after successful Release/Hotfix finish, including target branch resets, tag delete/recreate, and source branch restore/delete.
- Stop before tag collisions, dirty worktrees, missing target branches, or target branches checked out in another worktree.

## Verification

- Focused planner, service, command-state, and recovery tests.
- `git diff --check`.
- macOS build. Do not launch the app.
