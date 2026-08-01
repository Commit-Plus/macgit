# AI Commit Message Roadmap

## Goal

Generate editable commit messages from staged changes through a provider-neutral AI layer. Keep source-code handling explicit and make future cloud providers additive.

## Phases

- [completed] [Phase 1: Apple Intelligence and provider placeholders](2026-08-01-ai-commit-message-phase-1-apple-intelligence.md)
- [pending] Phase 2: Cloud provider implementations and secure credential-backed requests

## Shared constraints

- Generation never stages files or commits automatically.
- Only staged changes are used for the Phase 1 generation request.
- Apple Intelligence remains the default on-device provider when available.
- Cloud provider credentials stay machine-local in Keychain and never sync through Firebase.
- Provider-specific APIs remain behind the shared commit-message provider protocol.
