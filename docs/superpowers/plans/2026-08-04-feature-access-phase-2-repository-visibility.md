# Feature Access Phase 2: Repository Visibility

**Branch:** `codex/feature-access-phase-2`

## Goal

Resolve each local repository as local-only, public, private, or unknown through provider APIs and a local cache, then expose that result to the shared feature-access boundary for later UI/action gates.

## Tasks

- [completed] Add GitHub and GitLab visibility-provider boundaries with authenticated and unauthenticated requests.
- [completed] Add a local visibility cache keyed by normalized provider repository identity, without storing local paths or credentials.
- [completed] Resolve all configured remotes conservatively: private wins, unknown blocks a public classification, and no remotes means local-only.
- [completed] Reuse connected provider accounts and machine-local tokens when an unauthenticated lookup cannot see a repository.
- [completed] Publish visibility state through an app-owned controller outside SwiftUI views.
- [completed] Add focused tests, run `git diff --check`, and build the macOS app without launching it.

## Acceptance criteria

- A repository with no remotes resolves to `local` without a network request.
- Public GitHub and GitLab repositories resolve without requiring a connected account.
- Private GitHub and GitLab repositories resolve only when a matching local API token can read them.
- An unsupported remote, provider error, missing credential, malformed payload, or mixed public/unknown remote set resolves to `unknown`.
- Any confirmed private remote makes the repository private, even when another remote is public.
- Only valid public/private results are cached; unknown is retried later and never becomes an accidental grant.
- Cache records contain normalized provider identity, visibility, and timestamp only.
- Phase 2 exposes decisions for private-repository access but does not yet block existing repository-opening, Pull Request, or Git Flow UI paths.
