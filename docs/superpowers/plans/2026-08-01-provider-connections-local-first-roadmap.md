# Local-First Git Provider Connections Roadmap

**Goal:** Keep GitHub/GitLab Connections usable while signed out, and sync their non-secret metadata when a Commit+ Firebase account is available.

**Architecture:** A machine-local metadata store is the source of truth. Provider tokens remain in Keychain and SSH key paths remain local. An optional cloud store merges remote metadata into local state after sign-in and mirrors local metadata back to Firestore without rolling back local state when cloud operations fail.

## Phases

- [completed] [Phase 1: Local-first storage, guest Connections, and Git credential routing](2026-08-01-provider-connections-local-first-phase-1.md) (branch: `codex/provider-connections-local-first`)

## Shared Rules

- Connecting, editing, deleting, and using a provider account must not require Firebase Auth.
- Signing out must never clear local provider connections, Keychain tokens, or SSH key references.
- Firestore stores metadata only; provider tokens and SSH key paths never sync.
- Local writes take effect first. Firestore failure must not undo visible local state.
- On sign-in, merge by provider, normalized host, and provider user identity; prefer a usable local connection over cloud metadata.
- If no matching app-managed connection exists, Git may use the configured system credential helper.
- Route all push entry points through the same provider-account selection and credential injection pipeline.
