# Pull Request Detail Phase 4

**Roadmap:** [`2026-08-15-inline-create-pull-request-roadmap.md`](2026-08-15-inline-create-pull-request-roadmap.md)

**Status:** [completed]

## Scope

1. Recompose the detail header around title, number, state, source/target branches, author, and creation date.
2. Move Overview/Changes navigation into a dedicated row below the header.
3. Split Overview into a main conversation column and a right metadata sidebar.
4. Render description and each comment as bordered, background-backed conversation blocks.
5. Show reviewers and assignees in the metadata sidebar.
6. Decode requested reviewers from GitHub and GitLab detail APIs.

## Acceptance Criteria

- The header establishes Pull Request identity and branch relationship before secondary actions.
- Author and date metadata are visible without entering the Overview content.
- Overview and Changes remain functional and load Changes lazily.
- Description, comments, refresh, and comment composition remain in the main column.
- Reviewers and assignees have separate, readable sidebar sections with empty states.
- Existing markdown, comment submission, browser actions, and detail refresh behavior remain intact.

## Verification

- `git diff --check` passed.
- Targeted `PullRequestControllerTests`, `GitHubPullRequestServiceTests`, and `GitLabPullRequestServiceTests` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed.
- Runtime visual inspection was not performed because repository instructions prohibit launching the app during verification.
