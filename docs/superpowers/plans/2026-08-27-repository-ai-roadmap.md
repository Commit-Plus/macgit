# Repository AI Roadmap

Build a repository-scoped AI assistant in the toolbar side panel. The assistant must use bounded repository tools, explicit policy boundaries, and the existing provider, credential, model, entitlement, Git Undo, and repository-refresh architecture.

## Delivery model

- Phase numbers organize product scope; they are not a required implementation order.
- Any pending phase may start from a clean current `main` whenever requested. It must not require another pending phase to compile, test, or satisfy its own acceptance criteria.
- Each phase plan defines a standalone path on the completed Phase 1 baseline and optional integration behavior when another phase is already present.
- A phase branch adopts compatible seams already merged on `main`; it must not copy a second provider stack, Git runtime, conversation controller, or mutation service just to avoid an optional dependency.
- Each phase has its own status. Starting or completing one phase does not implicitly change another phase's status.
- If two phase branches touch the same shared contract, the later merge rebases onto current `main`, reuses the merged contract, and updates only its adapter. The roadmap does not reserve shared files for a phase that has not started.

## Phases

- [completed] **Phase 1 — Review changes and explain commits**
  - Add typed `working_tree_changes` and `commit_changes` tools on `GitStatusService`.
  - Bound diff context, validate commit references, and reject stale working-tree answers.
  - Extend every implemented AI provider with repository-question generation.
  - Replace the placeholder Chat tab with quick actions, context selection, provider selection, and a conversation transcript.
  - Gate execution through the existing `repositoryChat` feature policy.
  - Plan: [Repository AI Phase 1: Review Changes and Explain Commits](2026-08-27-repository-ai-phase-1-review-and-explain.md)
- [completed] **Phase 2 — Agentic read-only Git harness**
  - Replace the caller-selected context tool with a provider-neutral tool-calling loop where the model can request bounded Git arguments and inspect each result before answering.
  - Reuse `GitStatusService.runGit(arguments:in:)` behind an AI-only command policy; never expose arbitrary shell execution or unrestricted Git commands.
  - Make staged-only review work naturally through `git diff --cached`, preserve multi-turn context, and reject answers built from stale repository state.
  - Plan: [Repository AI Phase 2: Agentic Read-Only Git Harness](2026-09-03-repository-ai-phase-2-agentic-git-harness.md)
- [pending] **Phase 3 — File-aware follow-up tools**
  - Add safe file-content and file-diff tools with explicit path allow-lists derived from prior Git results.
  - Add response citations back to files, commits, and diff hunks.
  - Plan: [Repository AI Phase 3: File-Aware Context and Citations](2026-09-03-repository-ai-phase-3-file-aware-context-and-citations.md)
- [pending] **Phase 4 — Broader repository analysis**
  - Add branch comparison, history search, and pull-request context tools.
  - Plan: [Repository AI Phase 4: Broader Repository Analysis](2026-09-03-repository-ai-phase-4-broader-repository-analysis.md)
- [in progress] **Phase 5 — Confirmed local Git mutations**
  - Add semantic stage, unstage, commit, create/check out branches, and apply an existing Conflict AI resolution one operation at a time.
  - Require explicit user confirmation, expected-state validation, Git Undo integration where supported, and normal repository refresh notifications.
  - Plan: [Repository AI Phase 5: Confirmed Git Mutations](2026-09-03-repository-ai-phase-5-confirmed-git-mutations.md)
- [pending] **Phase 6 — Confirmed remote Git operations**
  - Add preflighted fetch, pull, and push proposals using existing remote/account flows; force and destructive remote operations remain separate later work.
  - Require an explicit remote/branch/refspec preview and confirmation, then revalidate state immediately before execution.
  - Plan: [Repository AI Phase 6: Confirmed Remote Git Operations](2026-09-03-repository-ai-phase-6-confirmed-remote-git-operations.md)

## Roadmap-wide guardrails

- Never expose an arbitrary shell command, executable path, working directory, environment, credential, or unbounded repository output to the model.
- Read tools and mutation tools remain separate policy domains. The generic Git query tool never grows write access.
- Any AI-proposed mutation pauses for an explicit user confirmation and revalidates expected repository state immediately before execution.
- Repository content and provider output remain untrusted. Validate paths, refs, tool arguments, citations, structured output, and stale fingerprints in app code.
- Preserve the currently selected Apple Intelligence or BYOK provider and surface provider/configuration/entitlement failures as actionable UI feedback.
- Every phase adds focused unit and real temporary-repository integration coverage, runs `git diff --check`, and builds the macOS app without launching it.
