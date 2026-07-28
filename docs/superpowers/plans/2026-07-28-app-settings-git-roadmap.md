# App Settings Git Roadmap

**Goal:** Add safe, app-level controls for the current Mac's global Git installation and configuration.

## Phases

- [completed] [Phase 1: Global Git Settings](2026-07-28-app-settings-git-phase-1.md)

## Boundaries

- Global Git settings write through `git config --global`.
- Repository-specific pull, fetch, remote, identity override, and safety settings remain in Repository Settings.
- Credentials, signing keys, and hooks are out of scope for Phase 1.
- Git settings are machine-specific and are not added to Firebase app settings sync.
