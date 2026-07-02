# Firebase Foundation Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional Commit+ account, server-controlled Pro entitlement, and Pro-only sync for three app preferences without blocking guest Git workflows.

**Architecture:** Phase 0 adds Firebase/Google dependencies and app-owned boundaries while preserving guest startup when configuration is absent. Phase 1 builds authentication and Account UI, Phase 2 adds entitlements and secure account lifecycle, and Phase 3 adds conflict-aware Pro settings sync.

**Tech Stack:** Swift 5, SwiftUI, Firebase Apple SDK 12.15.0, GoogleSignIn-iOS 9.2.0, Cloud Firestore, Firebase Auth, Cloud Functions 2nd gen, Firebase Emulator Suite, XCTest, `xcodebuild`.

---

## Design Source

- [2026-07-02-firebase-foundation-design.md](../specs/2026-07-02-firebase-foundation-design.md)

## Plan Index

- Phase 0: [completed] [2026-07-02-firebase-foundation-phase-0-bootstrap.md](2026-07-02-firebase-foundation-phase-0-bootstrap.md) (branch: `codex/firebase-foundation-phase-0`, verified at `2da458a`)
- Phase 1: [in progress] [2026-07-02-firebase-foundation-phase-1-account-auth-ui.md](2026-07-02-firebase-foundation-phase-1-account-auth-ui.md) (worktree: `.worktrees/firebase-foundation-phase-1`, branch: `codex/firebase-foundation-phase-1`)
- Phase 2: [pending] [2026-07-02-firebase-foundation-phase-2-entitlement-lifecycle.md](2026-07-02-firebase-foundation-phase-2-entitlement-lifecycle.md) (branch: `codex/firebase-foundation-phase-2`)
- Phase 3: [pending] [2026-07-02-firebase-foundation-phase-3-settings-sync.md](2026-07-02-firebase-foundation-phase-3-settings-sync.md) (branch: `codex/firebase-foundation-phase-3`)

## Recommended Order

1. Phase 0 first: configuration, dependencies, and protocols must compile before any Firebase-backed feature.
2. Phase 1 next: establish Firebase identity and the always-visible Account entry point.
3. Phase 2 next: make Pro server-owned and add secure deletion before gating cloud behavior.
4. Phase 3 last: settings sync depends on both authenticated identity and entitlement.

## Shared Rules

- Develop each phase in its own `.worktrees/` checkout and mark its roadmap entry `[in progress]` before code changes.
- Preserve fully functional guest startup and local Git behavior in every phase.
- Never log passwords, Firebase ID tokens, Google tokens, or future Git provider credentials.
- Keep Firebase imports behind service boundaries; SwiftUI views consume app-owned protocols and state.
- Run targeted tests during tasks and the complete macOS test suite before marking a phase `[completed]`.
- After green verification, update this roadmap entry with the landed branch or merge commit.

## Out of Scope

- Polar checkout/webhooks/portal.
- GitHub, GitLab, or Bitbucket account integration.
- Repository-history sync.
- Sign in with Apple implementation.
