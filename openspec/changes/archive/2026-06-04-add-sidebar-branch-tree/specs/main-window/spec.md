## ADDED Requirements

### Requirement: Branch Tree Structure
The system SHALL display local branches in the BRANCHES sidebar section as a hierarchical tree based on slash (`/`) delimiters in branch names.

#### Scenario: Flat branch list with no slashes
- **GIVEN** a repository with branches `main` and `release`
- **WHEN** the sidebar BRANCHES section is expanded
- **THEN** both `main` and `release` appear as top-level leaf items

#### Scenario: Nested branch names create folders
- **GIVEN** a repository with a branch named `feat/test-new-branch`
- **WHEN** the sidebar BRANCHES section is expanded
- **THEN** a folder node `feat` is shown, and inside it a leaf item `test-new-branch`

#### Scenario: Multiple branches under same prefix
- **GIVEN** branches `feat/ui` and `feat/api`
- **WHEN** the sidebar is rendered
- **THEN** a single `feat` folder contains both `ui` and `api` leaf items

## MODIFIED Requirements

### Requirement: Sidebar Navigation
The system SHALL provide a left sidebar with workspace navigation items. The BRANCHES section SHALL display the local branch tree instead of a disabled placeholder.

#### Scenario: Sidebar items visible
- **WHEN** the main window is active
- **THEN** the sidebar contains at minimum the following sections and items:
  - **WORKSPACE**: File status, History, Search
  - **BRANCHES**: Live tree of local branches (hierarchical by `/` delimiter)
  - Placeholder sections (collapsed or disabled) for Tags, Remotes, Stashes, Submodules, Subtrees

#### Scenario: Sidebar selection updates detail
- **WHEN** the user selects an item in the sidebar
- **THEN** the right panel updates to show the corresponding content view
- **AND** selecting a branch navigates to the History view filtered by that branch

## ADDED Requirements

### Requirement: Branch Selection Navigation
The system SHALL navigate to the History view filtered to the selected branch when the user single-clicks a branch leaf in the sidebar.

#### Scenario: Single click branch shows filtered history
- **WHEN** the user single-clicks a branch named `feat/test-new-branch` in the sidebar
- **THEN** the right panel shows the History view
- **AND** the commit list is filtered to commits reachable from that branch only

### Requirement: Branch Checkout
The system SHALL check out a branch when the user double-clicks it in the sidebar. Double-clicking the currently checked-out branch SHALL be a no-op.

#### Scenario: Double click checks out branch
- **GIVEN** the current branch is `main`
- **WHEN** the user double-clicks `feat/test-new-branch` in the sidebar
- **THEN** the system runs `git checkout feat/test-new-branch`
- **AND** the sidebar updates to show `feat/test-new-branch` as the current branch

#### Scenario: Double click current branch is no-op
- **GIVEN** the current branch is `main`
- **WHEN** the user double-clicks `main` in the sidebar
- **THEN** no Git command is executed
- **AND** the UI state remains unchanged

### Requirement: Branch Context Menu
The system SHALL display a context menu on right-clicking a branch in the sidebar with the following actions: Checkout, Merge into current, Rebase current onto, Fetch, Push to, Track Remote Branch, Diff Against Current, Rename, Delete, Copy Branch Name to Clipboard, and Create Pull Request.

#### Scenario: Context menu appears on right click
- **WHEN** the user right-clicks a branch in the sidebar
- **THEN** a context menu appears with the listed branch actions

#### Scenario: Checkout from context menu
- **WHEN** the user selects "Checkout" from the context menu
- **THEN** the system checks out the selected branch

#### Scenario: Delete from context menu
- **WHEN** the user selects "Delete" from the context menu
- **THEN** the system deletes the selected branch using the existing delete-branch flow

### Requirement: Current Branch Visual Indicator
The system SHALL visually indicate the currently checked-out branch in the sidebar with a circle icon and bold text.

#### Scenario: Current branch highlighted
- **GIVEN** the current branch is `main`
- **WHEN** the sidebar branch tree is rendered
- **THEN** the `main` item displays a filled circle icon to its left
- **AND** the `main` text uses a bold font weight
