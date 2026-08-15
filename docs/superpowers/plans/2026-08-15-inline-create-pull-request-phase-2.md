# Inline Create Pull Request Phase 2

**Roadmap:** [`2026-08-15-inline-create-pull-request-roadmap.md`](2026-08-15-inline-create-pull-request-roadmap.md)

**Status:** [completed]

## Scope

1. Add provider-neutral selectable Pull Request participants and draft selections.
2. Load eligible GitHub and GitLab project participants with pagination where required.
3. Render searchable multi-selection controls for reviewers and assignees when supported.
4. Submit GitLab participant IDs with merge-request creation.
5. Submit GitHub reviewer and assignee usernames after Pull Request creation.
6. Preserve a successful creation result when a follow-up participant request fails and surface the partial failure clearly.
7. Add targeted provider and controller tests.

## Acceptance Criteria

- Participant controls show only provider-supported data returned for the active repository/account.
- Existing create behavior remains unchanged when no participants are selected.
- GitHub and GitLab encode provider-specific participant identifiers correctly.
- A post-create participant failure reports that the Pull Request was created and identifies the incomplete metadata step.
- Switching repositories or dismissing creation cannot publish stale participant results.

## Verification

- GitHub participant loading, post-create reviewer/assignee requests, and warning behavior are covered by targeted tests.
- GitLab project-member loading and create-payload reviewer/assignee IDs are covered by targeted tests.
- Controller participant loading and partial-success messaging are covered by targeted tests.
- The targeted Pull Request test group and macOS build passed.
