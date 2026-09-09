# Phase 1: explicit branch replacement

Status: [completed]

1. Capture the selected local commit and fetched remote commit before confirmation. Show destination, lost commit count, and default-branch warning.
2. Push the captured commit with an explicit remote SHA lease. Revalidate local tip and remote configuration after credential selection. Never retry with plain force.
3. Keep `Push to` and `Force Push to`; omit submenu destinations identical to tracked upstream. Add a single-branch force action in the push sheet and a non-fast-forward recovery hint.
4. Preserve both commits with local recovery refs and register guarded undo/redo only after successful replacement.
5. Verify reset, divergence, stale remote/local/configuration, mapped destinations, and undo/redo with temporary Git repositories. Build without launching the app; do not retry Firebase test-host bootstrap failure.

## Implemented

- Both entry points use a single-branch confirmation; the Push sheet action applies only to that branch, never its tag selection.
- Tracked push retains the configured upstream destination. Submenus retain their short names and omit only the exact duplicate mapping.
- The service fetches the destination into a unique local recovery ref and preserves both commits under `refs/commitplus/force-push/<UUID>/`. These recovery refs are retained locally; the Undo stack itself is still session-only.
- Force Push is refused for destinations with different fetch/push URLs or multiple push URLs. A separate remote with one matching endpoint is required.
- The explicit lease pins the reviewed remote commit even when background fetch runs. The pushed source is an immutable commit, with local-tip and endpoint checks after credential resolution.
- Normal push and tag push keep their existing execution paths; branch non-fast-forward errors now point to Force Push.

## Verification

- macOS build and build-for-testing succeeded.
- Targeted XCTest compiled, but the app test host aborted before connecting (`Early unexpected exit ... abort() called`). Not retried; XCTest assertions and runtime UI remain unverified.
- A standalone Swift harness compiled the production force-push service extension and plan with minimal process/credential adapters (no Firebase host). Nine scenarios passed against real temporary Git repos: reset with mapped destination and Undo/Redo; divergence; remote advancement after background fetch; local change; remote deletion; endpoint change; server protection; multiple URLs; and rejection of a normal fast-forward update. The reset scenario also checked that unrelated branches/tags were not pushed.
- The standalone harness does not validate provider credentials, SwiftUI presentation, or app Undo registration.
