# Git Flow Lite

## Goal

Add a small, repository-local Git Flow workflow to Commit+ without depending on a `git-flow` executable. The first version covers the standard branch lifecycle and leaves custom workflow graphs, remote automation, and deep merge-strategy customization for later.

## Branch roles

| Role | Default branch or prefix | Starts from | Finishes into | Creates tag |
| --- | --- | --- | --- | --- |
| Main | `main` | - | - | - |
| Develop | `develop` | - | - | - |
| Feature | `feature/` | Develop | Develop | No |
| Bugfix | `bugfix/` | Develop | Develop | No |
| Release | `release/` | Develop | Main, then Develop | Yes |
| Hotfix | `hotfix/` | Main | Main, then Develop | Yes |

Feature and Bugfix share the same execution policy but remain distinct user-facing branch types. Hotfix is reserved for production fixes and therefore starts at Main and finishes into both long-lived branches.

## Initial scope

- Enable or disable Git Flow per repository.
- Select the Main and Develop branches and edit the four default prefixes.
- Start Feature, Bugfix, Release, and Hotfix branches.
- Finish all four topic types with `--no-ff` merge semantics.
- Create an annotated version tag while finishing Release or Hotfix.
- Offer local topic-branch deletion only after all required finish steps succeed.
- Stop safely on conflicts and allow the existing File Status conflict experience to resolve them before the workflow continues or aborts.
- Refresh `SyncState`, invalidate branch discovery when refs change, post `.repositoryDidChange`, and register safe compound Undo entries only after successful operations.

## Deferred scope

- Custom base/topic graphs or user-defined branch types.
- Separate upstream and downstream strategies.
- Automated push, remote-branch deletion, or force operations.
- Starting a workflow in a new worktree.
- Import, export, Firebase sync, or team-shared configuration.
- Rebase or squash finish strategies.
- Guaranteed preflight conflict prediction.

## Configuration and storage

Configuration is local to the repository and must not dirty the working tree. Use the repository Git common directory so linked worktrees observe the same workflow configuration. Do not sync workflow configuration through Firebase.

The configuration model must decode older or incomplete persisted data with safe defaults. Disabling Git Flow removes or ignores the active configuration but never deletes Git branches.

## UX

Repository Settings contains a Git Flow section with:

- Enabled toggle.
- Main and Develop branch pickers.
- Feature, Bugfix, Release, and Hotfix prefix fields.
- Explicit setup validation when either long-lived branch is missing.

The main window exposes a Git Flow toolbar menu:

- Start Feature...
- Start Bugfix...
- Start Release...
- Start Hotfix...
- Finish the current topic branch when its prefix matches the configuration.
- Configure Git Flow...
- Disable Git Flow.

Start sheets show the final branch name and starting point before creating anything. Finish sheets show the ordered execution plan, tag creation where applicable, and optional local branch deletion.

## Architecture

- SwiftUI views render state and send callbacks only.
- `MainWindowView` coordinates presentation, repository-operation progress, refreshes, and Undo registration.
- `GitFlowPlanner` performs pure role detection, validation, and ordered-plan creation.
- `GitFlowService` owns Git execution and delegates individual Git operations to `GitStatusService` extensions.
- `GitFlowConfigurationStore` owns repository-local configuration.
- `GitFlowRecoveryStore` owns the resumable finish checkpoint introduced with Release and Hotfix finishing.

No new third-party dependency is required.

## Safety

Every Start or Finish action checks:

- Git Flow is enabled and configured.
- Required base and target branches exist.
- The working tree is clean.
- No merge, rebase, cherry-pick, or revert is already in progress.
- The new branch or tag does not already exist.
- The relevant branch is not checked out in an incompatible linked worktree.

A multi-step finish never creates its tag or deletes its topic branch before prerequisite merges succeed. When an operation pauses on a conflict, persist enough local checkpoint state to resume the remaining steps deterministically after relaunch.

## Verification

Use XCTest with real temporary Git repositories for planner and integration behavior. Cover all four Start flows, Feature/Bugfix Finish, Release/Hotfix multi-target Finish, tag collisions, dirty worktrees, missing branches, linked worktrees, conflicts, resume, abort, and Undo state guards. Run focused tests and the prescribed macOS build without launching the app.
