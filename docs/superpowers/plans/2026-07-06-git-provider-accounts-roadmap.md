# Git Provider Accounts Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add connected Git provider accounts so a Firebase-backed macgit user can connect GitHub and GitLab identities for private repositories and pull request workflows.

**Architecture:** Firebase Auth remains the macgit identity. New provider account models, Keychain token vault, provider API clients, Git credential injection, and PR services live behind app-owned protocols so GitHub ships first without blocking GitLab support.

**Tech Stack:** Swift 5, SwiftUI, XCTest, macOS Keychain Services, AppKit URL handling, `URLSession`, existing `Process()` Git runner, Cloud Firestore metadata, `xcodebuild`.

---

## Design Source

- [2026-07-06-git-provider-accounts-design.md](../specs/2026-07-06-git-provider-accounts-design.md)

## Plan Index

- Phase 0: [completed] [2026-07-06-git-provider-accounts-phase-0-foundation.md](2026-07-06-git-provider-accounts-phase-0-foundation.md) (branch: `codex/git-provider-accounts-phase-0`)
- Phase 1: [completed] [2026-07-06-git-provider-accounts-phase-1-github-connect.md](2026-07-06-git-provider-accounts-phase-1-github-connect.md) (branch: `codex/git-provider-accounts-phase-1`)
- Phase 2: [pending] [2026-07-06-git-provider-accounts-phase-2-private-repo-credentials.md](2026-07-06-git-provider-accounts-phase-2-private-repo-credentials.md)
- Phase 3: [pending] [2026-07-06-git-provider-accounts-phase-3-pull-request-read.md](2026-07-06-git-provider-accounts-phase-3-pull-request-read.md)
- Phase 4: [pending] [2026-07-06-git-provider-accounts-phase-4-pull-request-actions.md](2026-07-06-git-provider-accounts-phase-4-pull-request-actions.md)
- Phase 5: [pending] [2026-07-06-git-provider-accounts-phase-5-gitlab-and-hardening.md](2026-07-06-git-provider-accounts-phase-5-gitlab-and-hardening.md)

## Recommended Order

1. Phase 0 first. It creates the provider account model, token vault, metadata store boundary, and controller without touching real provider auth.
2. Phase 1 connects GitHub through OAuth App device flow and proves the model with one real provider.
3. Phase 2 next. It uses connected accounts for private HTTPS Git operations while keeping tokens out of logs and command arguments.
4. Phase 3 next. It adds read-only pull request visibility so auth, remote parsing, and API clients can stabilize before write actions.
5. Phase 4 next. It adds create/comment/checkout PR actions with targeted permission and branch-state checks.
6. Phase 5 last. It adds GitLab support and decides which flows need Firebase Functions or Cloud Run based on real provider requirements.

## Shared Rules

- Develop each phase in its own `.worktrees/` checkout and mark its roadmap entry `[in progress]` before code changes.
- Keep Firebase Auth as the macgit identity; never reuse Firebase provider linkage for GitHub or GitLab accounts.
- Never store provider tokens, refresh tokens, client secrets, GitHub App private keys, or installation tokens in Firestore.
- Store production provider tokens only in macOS Keychain through `GitProviderTokenVault`.
- Do not put provider tokens into remote URLs, command-line arguments, crash logs, debug logs, or UI copy.
- Use external browser OAuth and verify callback `state`.
- Use PKCE for native OAuth flows whenever the selected provider supports it.
- Keep local Git usable for guests and signed-out users.
- Run focused tests during phase work and the complete macOS test suite before marking a phase `[completed]`.
- After green verification, update this roadmap entry with the landed branch or merge commit.

## Out of Scope

- Replacing Firebase Auth.
- Cross-device token sync.
- Shipping confidential provider secrets in the app bundle.
- Hosting webhooks without a backend.
- Bitbucket, Gitea, Azure DevOps, Gerrit, or code review providers beyond GitHub and GitLab.

## Completion

The roadmap is complete when GitHub private repository access and core PR workflows work from a connected provider account, GitLab has the same account/token/client boundaries, and backend requirements are documented from implemented constraints rather than assumed upfront.
