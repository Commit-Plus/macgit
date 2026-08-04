# Git Provider Account Plan Limits Roadmap

**Goal:** Let Free and guest users add one GitHub or GitLab account while allowing Pro users to add multiple provider accounts.

**Architecture:** Keep provider accounts local-first and preserve every existing connection across sign-out or entitlement downgrade. A pure access policy decides whether a new provider identity may be created, while `GitProviderAccountController` enforces the decision before authentication and again before persisting credentials or metadata. SwiftUI only renders the decision and upgrade affordance.

## Phases

- [completed] [Phase 1: Provider account creation quota and upgrade UX](2026-08-04-git-provider-account-plan-limits-phase-1.md) (branch: `codex/git-provider-account-plan-limits`)

## Shared Rules

- Free and guest users may add one supported Git provider account total, regardless of whether it is GitHub or GitLab.
- Pro users may add multiple supported provider accounts.
- The quota applies only to creating a new provider identity. Existing accounts remain usable after sign-out, offline fallback, or entitlement downgrade.
- Reconnect, edit, delete, credential resolution, and Git operations must remain available for existing accounts.
- Never delete or disable provider credentials automatically because entitlement changes.
- Provider tokens remain in Keychain, SSH key references remain local, and Firestore receives metadata only.
- Bitbucket remains unavailable until its provider implementation is complete.
