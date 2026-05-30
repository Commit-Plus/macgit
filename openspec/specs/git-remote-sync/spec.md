# git-remote-sync Specification

## Purpose
TBD - created by archiving change add-git-sync-buttons. Update Purpose after archive.
## Requirements
### Requirement: Remote Synchronization Operations
The system SHALL support Push, Pull, and Fetch operations against the remote repository via Git CLI, and provide ahead/behind commit counts for the current branch.

#### Scenario: Push sends local commits to remote
- **WHEN** the user triggers Push
- **THEN** the system executes `git push` in the open repository
- **AND** upon success the File status view and badge counts refresh

#### Scenario: Pull merges remote commits into local branch
- **WHEN** the user triggers Pull
- **THEN** the system executes `git pull` in the open repository
- **AND** upon success the File status view and badge counts refresh

#### Scenario: Fetch updates remote-tracking branches
- **WHEN** the user triggers Fetch
- **THEN** the system executes `git fetch` in the open repository
- **AND** upon success the Pull and Push badge counts are immediately refreshed

#### Scenario: Ahead count for Push badge
- **WHEN** the system calculates ahead/behind counts
- **THEN** it runs `git rev-list --count @{upstream}..HEAD` to determine how many local commits are ahead of the upstream

#### Scenario: Behind count for Pull badge
- **WHEN** the system calculates ahead/behind counts
- **THEN** it runs `git rev-list --count HEAD..@{upstream}` to determine how many upstream commits are behind the local branch

### Requirement: Conflict Detection and Popup Notice
The system SHALL detect merge conflicts in the working directory before executing Push, Pull, or Commit, and display a popup notice. It SHALL also detect conflicts that arise during a Pull operation.

#### Scenario: Existing conflicts block Push and Pull
- **WHEN** the user clicks Push or Pull
- **AND** the working directory contains files with a conflict status
- **THEN** a native alert popup warns the user that conflicts must be resolved first
- **AND** the Git command is not executed

#### Scenario: Conflicts arising during Pull
- **WHEN** the user triggers Pull
- **AND** the merge results in conflicts
- **THEN** a native alert popup notifies the user that merge conflicts occurred during Pull
- **AND** the File status view refreshes to show the new conflicted files

#### Scenario: Existing conflicts shown before Commit
- **WHEN** the user opens the Commit sheet from the toolbar
- **AND** the working directory contains conflicted files
- **THEN** a native alert popup warns the user about unresolved conflicts

### Requirement: Pull Modal Dialog
The system SHALL display a modal dialog when the user clicks the Pull toolbar button, allowing selection of remote repository, remote branch, and pull options before executing the command.

#### Scenario: Pull dialog opens
- **WHEN** the user clicks the Pull toolbar button
- **THEN** a modal sheet appears showing:
  - A "Pull from repository" picker populated with configured remotes
  - A "Remote branch to pull" picker populated with remote-tracking branches and a Refresh button
  - The current local branch name displayed under "Pull into local branch"
  - An Options section with toggles:
    - Commit merged changes immediately (default ON)
    - Include messages from commits being merged in merge commit (default ON)
    - Create new commit even if fast-forward merge (default OFF)
    - Rebase instead of merge (default OFF)
  - Cancel and OK buttons

#### Scenario: Pull executes with selected options
- **WHEN** the user clicks OK in the Pull dialog
- **THEN** the system executes `git pull <remote> <branch>` with the selected options applied via appropriate flags (`--no-commit`, `--no-log`, `--no-ff`, `--rebase`)
- **AND** the dialog closes

#### Scenario: Pull with no new changes
- **WHEN** the Pull command completes successfully
- **AND** there were no new changes to merge
- **THEN** a native alert popup appears with the message "Already up to date."

#### Scenario: Pull with new changes
- **WHEN** the Pull command completes successfully
- **AND** new commits were merged
- **THEN** a native alert popup appears with the message "Pull completed successfully."

#### Scenario: Cancel Pull dialog
- **WHEN** the user clicks Cancel in the Pull dialog
- **THEN** the dialog closes and no Git command is executed

### Requirement: Fetch Empty Notification
The system SHALL display a brief notification when Fetch completes successfully but no new remote changes were retrieved.

#### Scenario: Fetch with no new changes
- **WHEN** the user triggers Fetch
- **AND** `git fetch` completes successfully
- **AND** the number of commits behind upstream did not increase
- **THEN** a native alert popup appears with the message "No new changes on remote."

### Requirement: Push Modal Dialog
The system SHALL display a modal dialog when the user clicks the Push toolbar button, allowing selection of remote repository, branches to push, and options before executing the command.

#### Scenario: Push dialog opens
- **WHEN** the user clicks the Push toolbar button
- **THEN** a modal sheet appears showing:
  - A "Push to repository" picker populated with configured remotes
  - A "Branches to push" list showing local branches with:
    - A checkbox to select the branch for pushing
    - The local branch name
    - The mapped remote branch name (if tracked)
    - A "Track" button to set upstream for untracked branches
  - A "Select All" checkbox
  - A "Push all tags" toggle
  - Cancel and OK buttons

#### Scenario: Push executes with selected branches
- **WHEN** the user clicks OK in the Push dialog
- **AND** at least one branch is selected
- **THEN** the system executes `git push <remote> <branch>` for each selected branch
- **AND** if "Push all tags" is enabled, also executes `git push --tags`
- **AND** the dialog closes

#### Scenario: Push with nothing to push
- **WHEN** the Push command completes successfully
- **AND** there were no new commits to push
- **THEN** a native alert popup appears with the message "Everything up-to-date."

#### Scenario: Push with new commits
- **WHEN** the Push command completes successfully
- **AND** new commits were pushed
- **THEN** a native alert popup appears with the message "Push completed successfully."

#### Scenario: Cancel Push dialog
- **WHEN** the user clicks Cancel in the Push dialog
- **THEN** the dialog closes and no Git command is executed

