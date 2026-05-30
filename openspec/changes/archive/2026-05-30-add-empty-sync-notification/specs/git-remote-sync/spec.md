## ADDED Requirements

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
