## ADDED Requirements

### Requirement: Branch Graph Visualization
The system SHALL display commit history as a visual branch graph with smooth curved lines connecting commits on the same branch and merge commits.

#### Scenario: Smooth branch curves
- **WHEN** the user opens the History view on a repository with multiple branches
- **THEN** the branch lines are drawn as smooth bezier curves rather than straight segmented lines
- **AND** each branch lane has a distinct color

#### Scenario: Merge commit visualization
- **WHEN** a merge commit exists in the history
- **THEN** the graph shows incoming curves from the merged branch lane into the target branch lane

### Requirement: Commit List Integration
The system SHALL render each commit as a row in the graph containing the commit message, author name, relative date, short hash, and branch/tag labels.

#### Scenario: Commit row display
- **WHEN** the history is loaded
- **THEN** each commit row shows:
  - A colored dot indicating the commit's branch lane
  - The commit subject message
  - Author name
  - Relative date (e.g., "2 hours ago")
  - Short hash (first 7 characters)
  - Ref labels (branches, tags) when present

### Requirement: Branch Filter Toggle
The system SHALL provide a toggle above the commit graph to switch between showing all branches or only the current branch.

#### Scenario: Filter to current branch
- **WHEN** the user selects "Current Branch" in the filter bar
- **THEN** the graph reloads to show only commits reachable from HEAD

#### Scenario: Filter to all branches
- **WHEN** the user selects "All Branches" in the filter bar
- **THEN** the graph reloads to show commits across all local and remote branches

### Requirement: Commit Selection and File Changes
The system SHALL display the files changed in the selected commit in a bottom panel, and allow selecting a file to view its diff.

#### Scenario: Select commit shows files
- **WHEN** the user clicks a commit in the graph
- **THEN** the bottom panel updates to show the list of files changed in that commit
- **AND** selecting a file from that list shows the commit diff in the right pane

#### Scenario: Diff viewer for commit changes
- **WHEN** a file is selected from the commit's changed file list
- **THEN** the diff viewer shows the unified diff of that file in the selected commit
- **AND** added lines are green, removed lines are red, context lines are neutral

### Requirement: Commit Context Menu Actions
The system SHALL provide a context menu on commit rows with common actions.

#### Scenario: Checkout commit
- **WHEN** the user right-clicks a commit and selects "Checkout"
- **THEN** the system executes `git checkout <hash>` and updates the working directory

#### Scenario: Cherry-pick commit
- **WHEN** the user right-clicks a commit and selects "Cherry Pick"
- **THEN** the system executes `git cherry-pick <hash>`

#### Scenario: Copy commit hash
- **WHEN** the user right-clicks a commit and selects "Copy Hash"
- **THEN** the full commit hash is copied to the pasteboard
