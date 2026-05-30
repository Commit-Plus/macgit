## ADDED Requirements

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
